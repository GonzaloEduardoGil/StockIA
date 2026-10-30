from concurrent.futures import ThreadPoolExecutor
import threading
import time
import unittest
from unittest.mock import patch

import psycopg2
from psycopg2 import extensions
from fastapi import FastAPI
from fastapi.testclient import TestClient

from sistema import database


class FakeConnection:
    def __init__(self):
        self.closed = 0
        self.autocommit = False
        self.readonly = False
        self.timeout = 0
        self.status = extensions.TRANSACTION_STATUS_IDLE
        self.close_count = 0
        self.rollback_count = 0
        self.committed = []
        self.pending = []
        self.fail_discard = False
        self.fail_select = False
        self.notices = []
        self.notifies = []

    def cursor(self):
        return FakeCursor(self)

    def get_transaction_status(self):
        return self.status

    def rollback(self):
        self.rollback_count += 1
        self.pending.clear()
        self.status = extensions.TRANSACTION_STATUS_IDLE

    def commit(self):
        self.committed.extend(self.pending)
        self.pending.clear()
        self.status = extensions.TRANSACTION_STATUS_IDLE

    def set_session(self, **options):
        for name in ('readonly', 'autocommit'):
            if name in options:
                setattr(self, name, options[name])

    def close(self):
        self.close_count += 1
        self.closed = 1


class FakeCursor:
    def __init__(self, connection):
        self.connection = connection
        self.closed = False

    def execute(self, sql):
        conn = self.connection
        if sql == 'DISCARD ALL':
            if conn.fail_discard:
                raise psycopg2.OperationalError('test-only reset failure')
            assert conn.autocommit
            assert conn.status == extensions.TRANSACTION_STATUS_IDLE
            conn.timeout = 0
            conn.readonly = False
            return
        if sql == 'SELECT 1' and conn.fail_select:
            raise psycopg2.OperationalError('test-only disconnected socket')
        if not conn.autocommit:
            conn.status = extensions.TRANSACTION_STATUS_INTRANS
        if sql.startswith('SET statement_timeout'):
            conn.timeout = int(sql.split('=')[1])
        elif sql.startswith('INSERT'):
            if conn.readonly:
                raise psycopg2.ProgrammingError('read-only transaction')
            conn.pending.append(sql)

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class DatabasePoolTest(unittest.TestCase):
    def setUp(self):
        self.physical = []

        def connect():
            conn = FakeConnection()
            self.physical.append(conn)
            return conn

        self.pool = database.ConnectionPool(connect, max_size=3, wait_seconds=0.2)

    def tearDown(self):
        self.pool.close()

    def test_readonly_then_write_and_timeout_reset_on_same_connection(self):
        first = self.pool.acquire()
        first.set_session(readonly=True)
        cursor = first.cursor()
        cursor.execute('SET statement_timeout = 123')
        self.physical[0].notices.append('estado de una operación anterior')
        self.physical[0].notifies.append('aviso anterior')
        first.close()  # También cierra el cursor olvidado y revierte la lectura.
        self.assertTrue(cursor._closed)
        second = self.pool.acquire()
        self.assertEqual(len(self.physical), 1)
        self.assertFalse(second.readonly)
        self.assertEqual(second.timeout, 0)
        self.assertEqual(self.physical[0].notices, [])
        self.assertEqual(self.physical[0].notifies, [])
        second.cursor().execute('INSERT test-only sale')
        second.commit()
        second.close()
        self.assertEqual(self.physical[0].committed, ['INSERT test-only sale'])

    def test_uncommitted_changes_are_rolled_back(self):
        connection = self.pool.acquire()
        connection.cursor().execute('INSERT should not persist')
        connection.close()
        again = self.pool.acquire()
        self.assertEqual(self.physical[0].pending, [])
        self.assertEqual(self.physical[0].committed, [])
        again.close()

    def test_double_close_and_saved_methods_cannot_reuse_returned_lease(self):
        old = self.pool.acquire()
        cursor = old.cursor()
        execute = cursor.execute
        commit = old.commit
        old.close()
        old.close()
        current = self.pool.acquire()
        for function in (old.cursor, commit, lambda: execute('SELECT 1')):
            with self.assertRaises(psycopg2.InterfaceError):
                function()
        self.assertEqual(self.pool.stats()['busy'], 1)
        current.cursor().execute('SELECT 1')
        current.close()
        self.assertEqual(self.pool.stats()['total'], 1)

    def test_simultaneous_close_returns_only_once(self):
        connection = self.pool.acquire()
        with ThreadPoolExecutor(max_workers=2) as executor:
            list(executor.map(lambda _: connection.close(), range(2)))
        self.assertEqual(self.pool.stats()['idle'], 1)
        self.assertEqual(self.pool.stats()['total'], 1)

    def test_three_concurrent_operations_have_exclusive_connections(self):
        barrier = threading.Barrier(3)

        def operation(index):
            connection = self.pool.acquire()
            try:
                connection.set_session(readonly=index % 2 == 0)
                connection.cursor().execute(f'SET statement_timeout = {index + 1}')
                barrier.wait(timeout=2)
                self.assertEqual(connection.timeout, index + 1)
                return id(connection._raw)
            finally:
                connection.close()

        with ThreadPoolExecutor(max_workers=3) as executor:
            ids = list(executor.map(operation, range(3)))
        self.assertEqual(len(set(ids)), 3)
        self.assertEqual(len(self.physical), 3)
        self.assertEqual(self.pool.stats()['busy'], 0)

    def test_full_pool_wait_is_bounded(self):
        held = [self.pool.acquire() for _ in range(3)]
        start = time.monotonic()
        try:
            with self.assertRaises(database.PoolTimeout):
                self.pool.acquire()
            self.assertLess(time.monotonic() - start, 1)
        finally:
            for connection in held:
                connection.close()

    def test_waiter_continues_when_connection_returns(self):
        held = [self.pool.acquire() for _ in range(3)]
        with ThreadPoolExecutor(max_workers=1) as executor:
            waiting = executor.submit(self.pool.acquire)
            held.pop().close()
            waiting.result(timeout=1).close()
        for connection in held:
            connection.close()

    def test_failed_reset_discards_and_replaces_connection(self):
        connection = self.pool.acquire()
        self.physical[0].fail_discard = True
        connection.close()
        self.assertEqual(self.physical[0].close_count, 1)
        replacement = self.pool.acquire()
        self.assertEqual(len(self.physical), 2)
        replacement.close()

    def test_dead_idle_connection_is_replaced_before_lending(self):
        connection = self.pool.acquire()
        connection.close()
        self.physical[0].closed = 1
        replacement = self.pool.acquire()
        self.assertEqual(len(self.physical), 2)
        replacement.close()

    def test_healthcheck_failure_is_replaced_without_retrying_business_operation(self):
        self.pool.health_seconds = 0
        connection = self.pool.acquire()
        connection.close()
        self.physical[0].fail_select = True
        replacement = self.pool.acquire()
        self.assertEqual(len(self.physical), 2)
        replacement.close()

    def test_connection_failure_releases_capacity_and_hides_details(self):
        pool = database.ConnectionPool(lambda: (_ for _ in ()).throw(RuntimeError('private-dsn')), max_size=1)
        try:
            with self.assertRaises(database.DatabaseUnavailable) as caught:
                pool.acquire()
            self.assertNotIn('private-dsn', str(caught.exception))
            self.assertEqual(pool.stats()['total'], 0)
        finally:
            pool.close()

    def test_shutdown_closes_idle_and_active_on_return(self):
        active = self.pool.acquire()
        idle = self.pool.acquire()
        idle.close()
        self.pool.close()
        self.assertTrue(self.physical[1].closed)
        self.assertFalse(self.physical[0].closed)
        with self.assertRaises(database.DatabaseUnavailable):
            self.pool.acquire()
        active.close()
        self.assertTrue(self.physical[0].closed)
        self.assertEqual(self.pool.stats()['total'], 0)

    def test_shutdown_wakes_waiters(self):
        held = [self.pool.acquire() for _ in range(3)]
        entered = threading.Event()

        def waiting():
            entered.set()
            return self.pool.acquire()

        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(waiting)
            self.assertTrue(entered.wait(1))
            self.pool.close()
            with self.assertRaises(database.DatabaseUnavailable):
                future.result(timeout=1)
        for connection in held:
            connection.close()

    def test_waiting_authentication_does_not_block_public_requests(self):
        from acceso.autenticacion import AuthenticationMiddleware
        self.pool.wait_seconds = 1
        held = [self.pool.acquire() for _ in range(3)]
        entered = threading.Event()
        acquire = self.pool.acquire

        def waiting():
            entered.set()
            return acquire()

        app = FastAPI()
        app.add_middleware(AuthenticationMiddleware)

        @app.get('/')
        async def health():
            return {'ok': True}

        @app.get('/stock/')
        def stock():
            return {}

        try:
            with patch.object(database, 'get_pool', return_value=self.pool), patch.object(self.pool, 'acquire', side_effect=waiting):
                with TestClient(app) as client, ThreadPoolExecutor(max_workers=1) as executor:
                    future = executor.submit(client.get, '/stock/', headers={'Authorization': 'Bearer ' + 'A' * 43})
                    self.assertTrue(entered.wait(1))
                    start = time.monotonic()
                    self.assertEqual(client.get('/').status_code, 200)
                    self.assertLess(time.monotonic() - start, 0.8)
                    self.assertEqual(future.result(timeout=2).status_code, 503)
        finally:
            for connection in held:
                connection.close()

    def test_shutdown_during_connection_open_does_not_leak(self):
        opening, finish = threading.Event(), threading.Event()
        physical = FakeConnection()

        def connect():
            opening.set()
            finish.wait(2)
            return physical

        pool = database.ConnectionPool(connect, max_size=1)
        with ThreadPoolExecutor(max_workers=1) as executor:
            borrowed = executor.submit(pool.acquire)
            self.assertTrue(opening.wait(1))
            pool.close()
            finish.set()
            with self.assertRaises(database.DatabaseUnavailable):
                borrowed.result(timeout=2)
        self.assertEqual(physical.close_count, 1)
        self.assertEqual(pool.stats()['total'], 0)

    def test_lifespan_warms_up_and_closes_shared_pool(self):
        app = FastAPI()
        database.install_database_pool(app)
        physical = FakeConnection()
        with patch.object(database, '_pool', None), patch.object(database, '_connect', return_value=physical):
            with TestClient(app):
                self.assertEqual(database.get_pool().stats()['idle'], 1)
                self.assertFalse(physical.closed)
            self.assertTrue(physical.closed)

    def _assert_reader_releases_after_failed_rollback(self, reader, expected=None, public_error=None, query_error=False):
        broken, healthy = FakeConnection(), FakeConnection()

        def rollback():
            broken.rollback_count += 1
            raise psycopg2.OperationalError('private rollback diagnostic')

        def cursor():
            current = FakeCursor(broken)
            execute_query = current.execute
            current.execute = lambda sql, *args, **kwargs: execute_query(sql)
            current.fetchall = lambda: []
            current.fetchone = lambda: (73, 'Prueba', 'test@example.test', 'Vendedor')
            if query_error:
                def execute(*args, **kwargs):
                    broken.status = extensions.TRANSACTION_STATUS_INERROR
                    raise psycopg2.OperationalError('private query diagnostic')
                current.execute = execute
            return current

        broken.rollback = rollback
        broken.cursor = cursor
        connections = iter([broken, healthy])
        pool = database.ConnectionPool(lambda: next(connections), max_size=1, wait_seconds=0.05)
        try:
            result, error = None, None
            with patch.object(database, 'obtener_conexion', side_effect=pool.acquire):
                try:
                    result = reader()
                except Exception as caught:
                    error = caught
            self.assertEqual(pool.stats()['busy'], 0, 'La limpieza perdió una plaza del pool.')
            self.assertEqual(pool.stats()['total'], 0)
            self.assertEqual(broken.close_count, 1)
            replacement = pool.acquire()
            try:
                replacement.cursor().execute('SELECT 1')
                self.assertIs(replacement._raw, healthy)
            finally:
                replacement.close()
            if public_error is not None:
                from fastapi import HTTPException
                self.assertIsInstance(error, HTTPException)
                self.assertEqual(error.status_code, 500)
                self.assertEqual(error.detail, public_error)
                self.assertNotIn('private', error.detail)
            else:
                self.assertIsNone(error, 'El error de limpieza reemplazó una respuesta válida.')
                self.assertEqual(result, expected)
        finally:
            pool.close()

    def test_predictions_rollback_disconnect_releases_capacity_and_preserves_result(self):
        from funciones.predicciones import consultar_predicciones
        self._assert_reader_releases_after_failed_rollback(
            consultar_predicciones, expected={'predicciones': [], 'cantidad': 0},
        )

    def test_predictions_rollback_disconnect_preserves_public_query_error(self):
        from funciones.predicciones import consultar_predicciones
        self._assert_reader_releases_after_failed_rollback(
            consultar_predicciones, public_error='No se pudieron consultar las predicciones guardadas.',
            query_error=True,
        )

    def test_recommendations_rollback_disconnect_preserves_result(self):
        from funciones.recomendaciones import consultar_recomendaciones
        self._assert_reader_releases_after_failed_rollback(
            consultar_recomendaciones, expected={'recomendaciones': [], 'cantidad': 0},
        )

    def test_recommendations_rollback_disconnect_preserves_public_query_error(self):
        from funciones.recomendaciones import consultar_recomendaciones
        self._assert_reader_releases_after_failed_rollback(
            consultar_recomendaciones, public_error='No se pudieron consultar las recomendaciones guardadas.',
            query_error=True,
        )

    def test_session_rollback_disconnect_preserves_resolved_identity(self):
        from acceso.autenticacion import resolve_session
        self._assert_reader_releases_after_failed_rollback(
            lambda: resolve_session('A' * 43),
            expected={'idUsuario': 73, 'nombre': 'Prueba', 'email': 'test@example.test', 'rol': 'Vendedor'},
        )


if __name__ == '__main__':
    unittest.main()
