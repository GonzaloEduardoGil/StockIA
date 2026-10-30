"""Conexiones compartidas por proceso. No almacena identidad de usuarios."""
from contextlib import contextmanager
import atexit
from collections import deque
from contextlib import asynccontextmanager
import logging
import os
import threading
import time

import psycopg2
from psycopg2 import extensions
from starlette.concurrency import run_in_threadpool

# Se conserva la configuración de conexión existente del proyecto.
DATABASE_URL = "postgresql://postgres.ciohdzojeekegzxaepyu:xM2Adp11T1dVt4At@aws-0-us-east-1.pooler.supabase.com:5432/postgres"

logger = logging.getLogger(__name__)


class DatabaseUnavailable(RuntimeError):
    """Error público sin DSN ni detalles privados de PostgreSQL."""


class PoolTimeout(DatabaseUnavailable):
    pass


class ConnectionPool:
    """Pool acotado para handlers síncronos de FastAPI y tareas en threadpool."""

    def __init__(self, connect, max_size=5, wait_seconds=3, health_seconds=30):
        if max_size < 1 or wait_seconds <= 0 or health_seconds < 0:
            raise ValueError('Configuración inválida del pool de conexiones.')
        self._connect = connect
        self.max_size = max_size
        self.wait_seconds = wait_seconds
        self.health_seconds = health_seconds
        self._condition = threading.Condition()
        self._idle = deque()
        self._total = 0
        self._closed = False

    def acquire(self):
        deadline = time.monotonic() + self.wait_seconds
        while True:
            with self._condition:
                if self._closed:
                    raise DatabaseUnavailable('El pool de conexiones está cerrado.')
                if self._idle:
                    raw, returned_at = self._idle.pop()
                    fresh = False
                elif self._total < self.max_size:
                    self._total += 1  # Reserva capacidad antes de abrir la conexión.
                    raw, returned_at, fresh = None, 0, True
                else:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise PoolTimeout('La base está ocupada. Intentá nuevamente en unos segundos.')
                    self._condition.wait(remaining)
                    continue
            if fresh:
                try:
                    raw = self._connect()
                except Exception:
                    self._discard(None)
                    raise DatabaseUnavailable('No se pudo conectar con la base de datos.') from None
            elif raw.closed:
                self._discard(raw)
                continue
            elif time.monotonic() - returned_at >= self.health_seconds:
                try:
                    # Validación previa al préstamo, nunca reintento de escrituras.
                    raw.autocommit = True
                    with raw.cursor() as cursor:
                        cursor.execute('SELECT 1')
                    raw.autocommit = False
                except Exception:
                    self._discard(raw)
                    continue
            with self._condition:
                closed = self._closed
            if closed:
                self._discard(raw)
                raise DatabaseUnavailable('El pool de conexiones está cerrado.')
            return BorrowedConnection(self, raw)

    def release(self, raw, discard=False):
        with self._condition:
            closed = self._closed
        if closed or discard or raw.closed:
            self._discard(raw)
            return
        try:
            if raw.get_transaction_status() == extensions.TRANSACTION_STATUS_UNKNOWN:
                self._discard(raw)
                return
            if raw.get_transaction_status() != extensions.TRANSACTION_STATUS_IDLE:
                raw.rollback()
            # Quitar primero las opciones del cliente: cambiar a autocommit con
            # readonly=True haría que psycopg emita SET adicionales innecesarios.
            raw.set_session(isolation_level='DEFAULT', readonly='DEFAULT',
                            deferrable='DEFAULT', autocommit=False)
            # DISCARD ALL debe ejecutarse fuera de una transacción. Limpia GUCs
            # (incluidos timeouts), rol, objetos temporales y estado de sesión.
            raw.autocommit = True
            with raw.cursor() as cursor:
                cursor.execute('DISCARD ALL')
            raw.autocommit = False
            raw.notices.clear()
            raw.notifies.clear()
        except Exception:
            # Una falla de limpieza no revierte un commit ya confirmado ni debe
            # enmascarar el error original de la operación. La conexión se elimina.
            self._discard(raw)
            return
        with self._condition:
            if not self._closed:
                self._idle.append((raw, time.monotonic()))
                self._condition.notify()
                return
        self._discard(raw)

    def _discard(self, raw):
        try:
            if raw is not None:
                raw.close()
        except Exception:
            pass
        finally:
            with self._condition:
                self._total -= 1
                self._condition.notify_all()

    def close(self):
        # No interrumpir una operación activa: se cerrará cuando devuelva su
        # préstamo. FastAPI completa las peticiones antes de cerrar su lifespan.
        with self._condition:
            self._closed = True
            idle = list(self._idle)
            self._idle.clear()
            self._condition.notify_all()
        for raw, _ in idle:
            self._discard(raw)

    def stats(self):
        with self._condition:
            return {'total': self._total, 'idle': len(self._idle),
                    'busy': self._total - len(self._idle), 'closed': self._closed}


class BorrowedConnection:
    """Préstamo exclusivo: close devuelve una vez, no cierra la conexión física."""

    def __init__(self, pool, raw):
        self._pool = pool
        self._raw = raw
        self._returned = False
        self._discard = False
        self._lock = threading.RLock()
        self._cursors = set()

    def _check(self):
        if self._returned:
            raise psycopg2.InterfaceError('La conexión ya fue devuelta al pool.')

    @property
    def closed(self):
        return self._returned or bool(self._raw.closed)

    @property
    def autocommit(self):
        with self._lock:
            self._check()
            return self._raw.autocommit

    @autocommit.setter
    def autocommit(self, value):
        with self._lock:
            self._check()
            self._raw.autocommit = value

    def cursor(self, *args, **kwargs):
        with self._lock:
            self._check()
            cursor = BorrowedCursor(self, self._raw.cursor(*args, **kwargs))
            self._cursors.add(cursor)
            return cursor

    def __getattr__(self, name):
        with self._lock:
            self._check()
            value = getattr(self._raw, name)
        if not callable(value):
            return value

        def call(*args, **kwargs):
            with self._lock:
                self._check()
                return value(*args, **kwargs)
        return call

    def close(self):
        with self._lock:
            if self._returned:
                return
            self._returned = True
            discard = self._discard
            for cursor in tuple(self._cursors):
                try:
                    cursor.close()
                except Exception:
                    discard = True
            discard = discard or self._discard
        self._pool.release(self._raw, discard=discard)

    def __enter__(self):
        self._check()
        return self

    def __exit__(self, kind, value, traceback):
        # Mantiene el comportamiento transaccional de un contexto psycopg2;
        # la devolución al pool sigue siendo explícita mediante close().
        if kind is None:
            self.commit()
        else:
            self.rollback()


class BorrowedCursor:
    def __init__(self, connection, raw):
        self._connection = connection
        self._raw = raw
        self._closed = False

    @property
    def connection(self):
        return self._connection

    @property
    def closed(self):
        return self._closed or self._connection.closed

    def _check(self):
        self._connection._check()
        if self._closed:
            raise psycopg2.InterfaceError('El cursor está cerrado.')

    def __getattr__(self, name):
        with self._connection._lock:
            self._check()
            value = getattr(self._raw, name)
        if not callable(value):
            return value

        def call(*args, **kwargs):
            with self._connection._lock:
                self._check()
                return value(*args, **kwargs)
        return call

    def close(self):
        with self._connection._lock:
            if self._closed:
                return
            self._closed = True
            try:
                self._raw.close()
            except Exception:
                self._connection._discard = True
            finally:
                self._connection._cursors.discard(self)

    def __enter__(self):
        self._check()
        return self

    def __exit__(self, kind, value, traceback):
        self.close()

    def __iter__(self):
        return self

    def __next__(self):
        with self._connection._lock:
            self._check()
            return next(self._raw)


def _connect():
    return psycopg2.connect(DATABASE_URL, connect_timeout=10,
                           keepalives=1, keepalives_idle=30,
                           keepalives_interval=10, keepalives_count=3)


def connect_alert_listener():
    # LISTEN conserva una conexión dedicada, fuera del pool de peticiones.
    return psycopg2.connect(os.getenv('ALERTS_DATABASE_URL') or DATABASE_URL,
                           connect_timeout=10, keepalives=1, keepalives_idle=30,
                           keepalives_interval=10, keepalives_count=3)


_pool = None
_pool_lock = threading.Lock()


def get_pool():
    global _pool
    with _pool_lock:
        if _pool is None:
            _pool = ConnectionPool(
                _connect,
                max_size=int(os.getenv('DB_POOL_MAX_SIZE', '5')),
                wait_seconds=float(os.getenv('DB_POOL_WAIT_SECONDS', '3')),
            )
        return _pool


def obtener_conexion():
    return get_pool().acquire()


def iniciar_pool():
    pool = get_pool()
    try:
        connection = pool.acquire()
        connection.close()
    except DatabaseUnavailable:
        # Las peticiones podrán reintentar luego; nunca registrar el DSN.
        logger.warning('La base no está disponible para precalentar el pool.')


def cerrar_pool():
    global _pool
    with _pool_lock:
        pool, _pool = _pool, None
    if pool is not None:
        pool.close()


def install_database_pool(app):
    previous_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app):
        await run_in_threadpool(iniciar_pool)
        try:
            async with previous_lifespan(app):
                yield
        finally:
            await run_in_threadpool(cerrar_pool)

    app.router.lifespan_context = lifespan


atexit.register(cerrar_pool)


def cerrar_recursos(conn, cursor) -> None:
    """Cierra cursor y conexión solo si fueron creados."""
    if cursor:
        cursor.close()
    if conn:
        conn.close()


def rollback_quietly(connection):
    try:
        connection.rollback()
    except Exception:
        pass


@contextmanager
def transaction():
    connection = obtener_conexion()
    try:
        with connection.cursor() as cursor:
            yield cursor
        connection.commit()
    except BaseException:
        try:
            connection.rollback()
        except Exception:
            pass
        raise
    finally:
        connection.close()
