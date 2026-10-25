"""Observer de alertas: NOTIFY transaccional -> observadores locales -> SSE."""
import asyncio
from contextlib import asynccontextmanager
import logging
import select
import time

from fastapi import APIRouter, Request
from starlette.concurrency import run_in_threadpool
from starlette.responses import StreamingResponse

CHANNEL = 'stockia_alertas'
PAYLOAD = 'actualizar'
router = APIRouter()
logger = logging.getLogger(__name__)


def publish_alert_change(cursor):
    # PostgreSQL entrega después del COMMIT y agrupa payloads idénticos de una
    # misma transacción. Un rollback tampoco entrega notificaciones.
    cursor.execute('SELECT pg_notify(%s, %s)', (CHANNEL, PAYLOAD))


class AlertEvents:
    """Sujeto observable. Una conexión LISTEN por proceso, no por usuario."""

    def __init__(self, connect, retry_seconds=1):
        self.connect = connect
        self.retry_seconds = retry_seconds
        self.observers = set()
        self.task = None

    def subscribe(self):
        queue = asyncio.Queue(maxsize=1)
        self.observers.add(queue)
        if self.task is None:
            self.task = asyncio.create_task(self._listen())
        return queue

    def unsubscribe(self, queue):
        self.observers.discard(queue)

    def notify(self):
        for queue in tuple(self.observers):
            if queue.empty():
                queue.put_nowait(PAYLOAD)

    async def close(self):
        if self.task is not None:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
            self.task = None
        self.observers.clear()

    async def _listen(self):
        delay = self.retry_seconds
        while True:
            connection = None
            try:
                opening = asyncio.create_task(asyncio.to_thread(self._safe_call, self.connect))
                try:
                    connection, failed = await asyncio.shield(opening)
                except asyncio.CancelledError:
                    # No abandonar una conexión que sigue abriéndose en el hilo.
                    connection, _ = await opening
                    raise
                if failed:
                    raise RuntimeError('Conexión del observador no disponible.')
                connection.autocommit = True
                with connection.cursor() as cursor:
                    cursor.execute(f'LISTEN {CHANNEL}')
                # Resincroniza también cuando se recupera la conexión a Postgres.
                self.notify()
                delay = self.retry_seconds
                checked = time.monotonic()
                while True:
                    selecting = asyncio.create_task(asyncio.to_thread(self._safe_call, select.select, [connection], [], [], 1))
                    try:
                        selected, failed = await asyncio.shield(selecting)
                    except asyncio.CancelledError:
                        await asyncio.gather(selecting, return_exceptions=True)
                        raise
                    if failed:
                        raise RuntimeError('Conexión del observador interrumpida.')
                    ready, _, _ = selected
                    if ready:
                        connection.poll()
                        if connection.notifies:
                            connection.notifies.clear()
                            self.notify()
                    if time.monotonic() - checked >= 30:
                        checking = asyncio.create_task(asyncio.to_thread(self._safe_call, self._check, connection))
                        try:
                            _, failed = await asyncio.shield(checking)
                        except asyncio.CancelledError:
                            await asyncio.gather(checking, return_exceptions=True)
                            raise
                        if failed:
                            raise RuntimeError('Conexión del observador interrumpida.')
                        checked = time.monotonic()
            except asyncio.CancelledError:
                raise
            except Exception:
                # No registrar excepciones de conexión: pueden incluir credenciales.
                logger.warning('Se reconectará el observador de alertas.')
            finally:
                if connection is not None:
                    connection.close()
            await asyncio.sleep(delay)
            delay = min(delay * 2, 30)

    @staticmethod
    def _safe_call(function, *args):
        # Evita que asyncio registre una excepción de psycopg con datos de la
        # conexión si el hilo termina justo cuando se cancela su tarea.
        try:
            return function(*args), False
        except Exception:
            return None, True

    @staticmethod
    def _check(connection):
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')


async def alert_stream(events, token, resolve, *, check_seconds=15):
    """Señales sin datos privados; vuelve a validar sesión y rol periódicamente."""
    queue = events.subscribe()
    next_check = time.monotonic() + check_seconds
    try:
        yield 'event: actualizar\ndata: {}\n\n'
        while True:
            if time.monotonic() >= next_check:
                try:
                    user = await run_in_threadpool(resolve, token)
                except Exception:
                    yield 'event: reconectar\ndata: {}\n\n'
                    return
                if user is None or user['rol'] not in {'Administrador', 'Encargado de stock'}:
                    yield 'event: sesion_expirada\ndata: {}\n\n'
                    return
                next_check = time.monotonic() + check_seconds
            try:
                await asyncio.wait_for(queue.get(), timeout=max(0.01, next_check - time.monotonic()))
                yield 'event: actualizar\ndata: {}\n\n'
            except asyncio.TimeoutError:
                yield ': latido\n\n'
    finally:
        events.unsubscribe(queue)


@router.get('/eventos/alertas', tags=['Alertas'])
async def subscribe_alerts(request: Request):
    from modules.authentication import resolve_session
    return StreamingResponse(
        alert_stream(request.app.state.alert_events, request.state.auth_token, resolve_session),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache, no-store', 'X-Accel-Buffering': 'no'},
    )


def install_alert_events(app, connect):
    previous_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app):
        async with previous_lifespan(app):
            events = AlertEvents(connect)
            app.state.alert_events = events
            try:
                yield
            finally:
                await events.close()

    app.router.lifespan_context = lifespan
    app.include_router(router)
