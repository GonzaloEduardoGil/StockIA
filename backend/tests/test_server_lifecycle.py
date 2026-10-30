import os
import contextlib
import io
import runpy
import threading
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from fastapi import FastAPI
from sistema.bootstrap import configurar_aplicacion
from sistema import database
from acceso import autenticacion as security
from acceso import usuarios
from acceso import autenticacion
from funciones import alertas as observer
from funciones import predicciones as schedule
from server import app


class ServerLifecycleTest(unittest.TestCase):
    def test_configuration_is_idempotent_for_the_same_application(self):
        fresh = FastAPI()
        self.assertIs(configurar_aplicacion(fresh), fresh)
        routes, middleware, lifespan = list(fresh.routes), list(fresh.user_middleware), fresh.router.lifespan_context
        self.assertIs(configurar_aplicacion(fresh), fresh)
        self.assertEqual(fresh.routes, routes)
        self.assertEqual(fresh.user_middleware, middleware)
        self.assertIs(fresh.router.lifespan_context, lifespan)

    def test_weekly_worker_stops_before_observer_and_pool(self):
        events = []
        started = threading.Event()
        close_schedule = schedule.PredictionSchedule.close

        def batch(**kwargs):
            events.append('weekly.batch')
            started.set()

        async def stop_schedule(instance):
            await close_schedule(instance)
            events.append('weekly.stopped')

        async def stop_observer():
            events.append('observer.stopped')

        with patch.dict(os.environ, {'PREDICTIONS_WEEKLY_ENABLED': 'true'}), \
             patch.object(database, 'iniciar_pool', side_effect=lambda: events.append('pool.open')), \
             patch.object(database, 'cerrar_pool', side_effect=lambda: events.append('pool.closed')), \
             patch.object(usuarios, 'initialize_user_schema'), \
             patch.object(schedule, 'weekly_batch', side_effect=batch), \
             patch.object(schedule.PredictionSchedule, 'close', new=stop_schedule), \
             patch.object(observer, 'AlertEvents') as event_class:
            event_class.return_value.close = AsyncMock(side_effect=stop_observer)
            with TestClient(app):
                self.assertTrue(started.wait(2))
        self.assertEqual(events[0], 'pool.open')
        self.assertLess(events.index('weekly.batch'), events.index('weekly.stopped'))
        self.assertLess(events.index('weekly.stopped'), events.index('observer.stopped'))
        self.assertLess(events.index('observer.stopped'), events.index('pool.closed'))

    def test_main_and_server_share_protected_routes_without_duplicates(self):
        import main
        from fastapi.routing import APIRoute
        self.assertIs(main.app, app)
        self.assertIn(security.AuthenticationMiddleware, [middleware.cls for middleware in app.user_middleware])
        operations = [(route.path, method) for route in app.routes if isinstance(route, APIRoute)
                      for method in route.methods]
        self.assertEqual(len(operations), len(set(operations)))

    def test_session_preparation_command_resolves_new_module_without_executing_sql(self):
        with patch.object(autenticacion, 'initialize_auth_schema') as initialize, contextlib.redirect_stdout(io.StringIO()):
            runpy.run_module('scripts.init_auth_db', run_name='__main__')
        initialize.assert_called_once_with()

    def test_uvicorn_still_loads_server_app_without_opening_connections(self):
        import uvicorn
        with patch.object(database, 'obtener_conexion', side_effect=AssertionError('No abrir DB al importar')):
            for entry in ['server:app', 'main:app']:
                config = uvicorn.Config(entry, log_config=None)
                config.load()
                self.assertTrue(config.loaded)

    def test_assembled_server_opens_pool_first_and_closes_it_after_observer(self):
        events = []

        async def close_observer():
            events.append('observer.close')

        with patch.dict(os.environ, {'PREDICTIONS_WEEKLY_ENABLED': 'false'}), \
             patch.object(database, 'iniciar_pool', side_effect=lambda: events.append('pool.open')), \
             patch.object(database, 'cerrar_pool', side_effect=lambda: events.append('pool.close')), \
             patch.object(usuarios, 'initialize_user_schema', side_effect=lambda: events.append('users.prepare')), \
             patch.object(observer, 'AlertEvents') as event_class:
            event_class.return_value.close = AsyncMock(side_effect=close_observer)
            with TestClient(app) as client:
                self.assertEqual(client.get('/').json(), {'mensaje': '¡El motor de StockIA está funcionando!'})
                self.assertEqual(client.get('/stock/').status_code, 401)
                with patch.object(security, 'resolve_session', return_value={'idUsuario': 73, 'rol': 'Vendedor'}):
                    response = client.post('/productos/', json={}, headers={'Authorization': 'Bearer ' + 'A' * 43})
                self.assertEqual(response.status_code, 403)
        self.assertEqual(events, ['pool.open', 'users.prepare', 'observer.close', 'pool.close'])
