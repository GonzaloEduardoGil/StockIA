import hashlib
import itertools
import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sistema import database
from acceso import autenticacion as security
from acceso import autenticacion as auth


class OwnPasswordTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old = 'QA-only-old-password'
        cls.new = 'QA-only-new-password'
        cls.stored = security.hasher.hash(cls.old)

    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = [(self.stored, True, 'Vendedor'), (1,)]
        for item in [patch.object(database, 'obtener_conexion', return_value=self.connection),
                     patch.object(auth, 'password_limiter', auth.LoginLimiter())]:
            item.start()
            self.addCleanup(item.stop)
        self.app = FastAPI()
        self.app.include_router(auth.router)
        self.app.add_middleware(security.AuthenticationMiddleware)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.headers = {'Authorization': 'Bearer ' + 'A' * 43}
        self.body = {'passwordActual': self.old, 'password': self.new, 'confirmacion': self.new}

    def authorize(self, role='Vendedor'):
        return patch.object(security, 'resolve_session', return_value={'idUsuario': 73, 'rol': role})

    def test_all_roles_can_change_only_their_password_and_revoke_all_sessions(self):
        for role in ['Administrador', 'Encargado de stock', 'Vendedor']:
            self.cursor.fetchone.side_effect = [(self.stored, True, role), (1,)]
            with self.authorize(role):
                response = self.client.post('/auth/password', json=self.body, headers=self.headers)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), {'passwordActualizada': True, 'sesionesCerradas': True})
            update = next(c for c in reversed(self.cursor.execute.call_args_list) if c.args[0].startswith('UPDATE'))
            self.assertEqual(update.args[1][1], 73)
            self.assertTrue(security.hasher.verify(update.args[1][0], self.new))
            self.assertNotIn(self.old, response.text)
            self.assertNotIn(self.new, response.text)
            self.assertNotIn('$argon2', response.text)
            self.assertEqual(self.cursor.execute.call_args.args[1], (73,))
            self.assertIn('DELETE FROM "STOCKIA_SESION"', self.cursor.execute.call_args.args[0])
        self.assertEqual(self.connection.commit.call_count, 3)
        self.assertEqual(self.connection.close.call_count, 3)

    def test_wrong_current_password_does_not_invalidate_session_or_write(self):
        with self.authorize():
            response = self.client.post('/auth/password', json={**self.body, 'passwordActual': 'wrong'}, headers=self.headers)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['detail'], 'La contraseña actual no es correcta.')
        self.assertFalse(any(c.args[0].strip().startswith(('UPDATE', 'DELETE')) for c in self.cursor.execute.call_args_list))
        self.connection.commit.assert_not_called()
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_no_session_or_another_user_id_cannot_be_used(self):
        self.assertEqual(self.client.post('/auth/password', json=self.body).status_code, 401)
        with self.authorize():
            for extra in [{'idUsuario': 99}, {'rol': 'Administrador'}, {'email': 'other@example.com'}]:
                response = self.client.post('/auth/password', json={**self.body, **extra}, headers=self.headers)
                self.assertEqual(response.status_code, 422)
                self.assertNotIn(self.old, response.text)
        self.connection.cursor.assert_not_called()

    def test_validation_errors_do_not_echo_any_password(self):
        with self.authorize():
            for change in [{'passwordActual': ''}, {'password': 'short'}, {'confirmacion': 'different'},
                           {'password': self.old, 'confirmacion': self.old},
                           {'password': ' '*8, 'confirmacion': ' '*8}]:
                response = self.client.post('/auth/password', json={**self.body, **change}, headers=self.headers)
                self.assertEqual(response.status_code, 422)
                self.assertNotIn(self.old, response.text)
                self.assertNotIn(self.new, response.text)
                self.assertNotIn('"input"', response.text)
        self.connection.cursor.assert_not_called()

    def test_revoked_session_is_checked_again_after_locking_user(self):
        self.cursor.fetchone.side_effect = [(self.stored, True, 'Vendedor'), None]
        with self.authorize():
            response = self.client.post('/auth/password', json=self.body, headers=self.headers)
        self.assertEqual(response.status_code, 401)
        self.assertFalse(any(c.args[0].strip().startswith(('UPDATE', 'DELETE')) for c in self.cursor.execute.call_args_list))
        session_check = self.cursor.execute.call_args
        self.assertIn('clock_timestamp()', session_check.args[0])
        self.assertEqual(session_check.args[1], (hashlib.sha256(('A'*43).encode()).hexdigest(), 73))
        sql = '\n'.join(c.args[0] for c in self.cursor.execute.call_args_list)
        self.assertIn('FOR UPDATE', sql)

    def test_inactive_missing_or_invalid_role_is_rejected(self):
        with self.authorize():
            for row in [None, (self.stored, False, 'Vendedor'), (self.stored, True, 'unknown')]:
                self.cursor.fetchone.side_effect = [row]
                response = self.client.post('/auth/password', json=self.body, headers=self.headers)
                self.assertEqual(response.status_code, 401)
        self.connection.commit.assert_not_called()

    def test_rate_limit_stops_repeated_wrong_current_passwords(self):
        self.cursor.fetchone.side_effect = itertools.cycle([(self.stored, True, 'Vendedor'), (1,)])
        with self.authorize():
            for _ in range(5):
                self.assertEqual(self.client.post('/auth/password', json={**self.body, 'passwordActual': 'wrong'}, headers=self.headers).status_code, 400)
            response = self.client.post('/auth/password', json=self.body, headers=self.headers)
        self.assertEqual(response.status_code, 429)
        self.connection.commit.assert_not_called()

    def test_failed_revocation_rolls_back_password_and_keeps_public_error(self):
        def execute(sql, *args):
            if sql.startswith('DELETE'):
                raise RuntimeError('private diagnostic')
        self.cursor.execute.side_effect = execute
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.post('/auth/password', json=self.body, headers=self.headers)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.commit.assert_not_called()
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_legacy_current_password_is_supported(self):
        self.cursor.fetchone.side_effect = [('old', True, 'Vendedor'), (1,)]
        with self.authorize():
            response = self.client.post('/auth/password', json={**self.body, 'passwordActual': 'old'}, headers=self.headers)
        self.assertEqual(response.status_code, 200)

    def test_route_without_authentication_middleware_is_also_protected(self):
        app = FastAPI()
        app.include_router(auth.router)
        with TestClient(app) as client:
            self.assertEqual(client.post('/auth/password', json=self.body).status_code, 401)
        self.connection.cursor.assert_not_called()

    def test_hash_failure_is_public_and_does_not_take_connection(self):
        with self.authorize(), patch.object(auth, 'hasher') as hasher:
            hasher.hash.side_effect = RuntimeError('private diagnostic')
            response = self.client.post('/auth/password', json=self.body, headers=self.headers)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.cursor.assert_not_called()
