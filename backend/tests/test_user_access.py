from datetime import datetime, timezone
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sistema import database
from acceso import autenticacion as security
from acceso import autenticacion as auth, usuarios as users


class UserAccessTest(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.row = (7, 'Prueba', 'prueba@example.com', 'Vendedor', True)
        for active_patch in [patch.object(database, 'obtener_conexion', return_value=self.connection),
                             patch.object(users, '_schema_ready', True)]:
            active_patch.start()
            self.addCleanup(active_patch.stop)
        self.app = FastAPI()
        self.app.include_router(auth.router)
        self.app.include_router(users.router)
        self.app.add_middleware(security.AuthenticationMiddleware)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.headers = {'Authorization': 'Bearer ' + 'A' * 43}
        self.password = 'QA-only-new-password'

    def authorize(self, role='Administrador'):
        return patch.object(security, 'resolve_session', return_value={'idUsuario': 1, 'rol': role})

    def operations(self):
        return [('patch', '/usuarios/7/estado', {'activo': False}),
                ('patch', '/usuarios/7/rol', {'rol': 'Encargado de stock'}),
                ('post', '/usuarios/7/password', {'password': self.password, 'confirmacion': self.password})]

    def test_all_access_operations_are_admin_only(self):
        for method, path, body in self.operations():
            request = getattr(self.client, method)
            self.assertEqual(request(path, json=body).status_code, 401)
            for role in ['Vendedor', 'Encargado de stock']:
                with self.authorize(role):
                    self.assertEqual(request(path, json=body, headers=self.headers).status_code, 403)
        self.connection.cursor.assert_not_called()

    def test_deactivation_preserves_account_and_revokes_sessions_in_same_transaction(self):
        self.cursor.fetchone.side_effect = [self.row, (*self.row[:4], False)]
        with self.authorize():
            response = self.client.patch('/usuarios/7/estado', json={'activo': False}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['usuario']['activo'])
        sql = '\n'.join(c.args[0] for c in self.cursor.execute.call_args_list)
        self.assertIn('FOR UPDATE', sql)
        self.assertIn('UPDATE "USUARIO" SET activo', sql)
        self.assertIn('DELETE FROM "STOCKIA_SESION"', sql)
        self.assertNotIn('DELETE FROM "USUARIO"', sql)
        self.connection.commit.assert_called_once()
        self.connection.close.assert_called_once()

    def test_reactivation_does_not_restore_any_old_session(self):
        self.cursor.fetchone.side_effect = [(*self.row[:4], False), self.row]
        with self.authorize():
            response = self.client.patch('/usuarios/7/estado', json={'activo': True}, headers=self.headers)
        self.assertTrue(response.json()['usuario']['activo'])
        sql = '\n'.join(c.args[0] for c in self.cursor.execute.call_args_list)
        self.assertIn('DELETE FROM "STOCKIA_SESION"', sql)
        self.assertNotIn('INSERT INTO "STOCKIA_SESION"', sql)

    def test_password_reset_hashes_and_revokes_without_changing_inactive_state_or_role(self):
        inactive = (*self.row[:4], False)
        self.cursor.fetchone.side_effect = [inactive, inactive]
        with self.authorize():
            response = self.client.post('/usuarios/7/password', headers=self.headers,
                json={'password': self.password, 'confirmacion': self.password})
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['usuario']['activo'])
        self.assertEqual(response.json()['usuario']['rol'], 'Vendedor')
        update = next(c for c in self.cursor.execute.call_args_list if 'SET contrasena' in c.args[0])
        self.assertTrue(security.hasher.verify(update.args[1][0], self.password))
        self.assertNotIn(self.password, response.text)
        self.assertNotIn('$argon2', response.text)
        self.assertIn('DELETE FROM "STOCKIA_SESION"', self.cursor.execute.call_args.args[0])
        self.connection.commit.assert_called_once()

    def test_role_change_only_between_operational_roles_and_revokes_sessions(self):
        self.cursor.fetchone.side_effect = [self.row, (*self.row[:3], 'Encargado de stock', True)]
        with self.authorize():
            response = self.client.patch('/usuarios/7/rol', json={'rol': 'Encargado de stock'}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['usuario']['rol'], 'Encargado de stock')
        self.assertIn('DELETE FROM "STOCKIA_SESION"', self.cursor.execute.call_args.args[0])
        self.connection.commit.assert_called_once()

    def test_unchanged_role_is_idempotent(self):
        self.cursor.fetchone.return_value = self.row
        with self.authorize():
            response = self.client.patch('/usuarios/7/rol', json={'rol': 'Vendedor'}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(any(c.args[0].strip().startswith(('UPDATE', 'DELETE')) for c in self.cursor.execute.call_args_list))

    def test_missing_accounts_and_administrators_cannot_be_managed(self):
        with self.authorize():
            for current, expected in [(None, 404), ((1, 'Admin', 'admin@example.com', 'Administrador', True), 403)]:
                for method, path, body in self.operations():
                    self.cursor.fetchone.return_value = current
                    response = getattr(self.client, method)(path, json=body, headers=self.headers)
                    self.assertEqual(response.status_code, expected)
        self.assertFalse(any(c.args[0].strip().startswith(('UPDATE', 'DELETE')) for c in self.cursor.execute.call_args_list))

    def test_invalid_values_and_password_confirmation_never_echo_secrets(self):
        cases = [('patch', '/usuarios/7/estado', {'activo': 'false'}),
                 ('patch', '/usuarios/7/estado', {'activo': 0}),
                 ('patch', '/usuarios/7/rol', {'rol': 'Administrador'}),
                 ('post', '/usuarios/7/password', {'password': self.password, 'confirmacion': 'not-matching'}),
                 ('post', '/usuarios/7/password', {'password': 'short', 'confirmacion': 'short'})]
        with self.authorize():
            for method, path, body in cases:
                response = getattr(self.client, method)(path, json=body, headers=self.headers)
                self.assertEqual(response.status_code, 422)
                self.assertNotIn(self.password, response.text)
                self.assertNotIn('"input"', response.text)
        self.connection.cursor.assert_not_called()

    def test_session_revocation_failure_rolls_back_account_change(self):
        self.cursor.fetchone.side_effect = [self.row, (*self.row[:4], False)]
        def execute(sql, *args):
            if 'DELETE FROM "STOCKIA_SESION"' in sql:
                raise RuntimeError('private diagnostic')
        self.cursor.execute.side_effect = execute
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.patch('/usuarios/7/estado', json={'activo': False}, headers=self.headers)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.commit.assert_not_called()
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_inactive_account_cannot_login_and_receives_generic_credentials_error(self):
        stored = security.hasher.hash(self.password)
        self.cursor.fetchall.return_value = [(*self.row[:4], stored, False)]
        with patch.object(auth, 'limiter', auth.LoginLimiter()):
            response = self.client.post('/auth/login', json={'email': self.row[2], 'password': self.password})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()['detail'], 'Email o contraseña incorrectos.')
        self.assertFalse(any(c.args[0].strip().startswith(('INSERT', 'UPDATE')) for c in self.cursor.execute.call_args_list))
        self.assertIn('FOR UPDATE', self.cursor.execute.call_args.args[0])

    def test_login_uses_row_lock_and_session_lookup_filters_active_accounts(self):
        stored = security.hasher.hash(self.password)
        self.cursor.fetchall.return_value = [(*self.row[:4], stored, True)]
        self.cursor.fetchone.return_value = (datetime(2030, 1, 1, tzinfo=timezone.utc),)
        with patch.object(auth, 'limiter', auth.LoginLimiter()):
            response = self.client.post('/auth/login', json={'email': self.row[2], 'password': self.password})
        self.assertEqual(response.status_code, 200)
        self.assertIn('FOR UPDATE', self.cursor.execute.call_args_list[0].args[0])
        self.cursor.fetchone.return_value = None
        self.assertIsNone(security.resolve_session('A' * 43))
        self.assertIn('u.activo = TRUE', self.cursor.execute.call_args.args[0])

    def test_password_hash_failure_is_public_and_does_not_open_connection(self):
        with self.authorize(), patch.object(users, 'hasher') as hasher:
            hasher.hash.side_effect = RuntimeError('private diagnostic')
            response = self.client.post('/usuarios/7/password', headers=self.headers,
                json={'password': self.password, 'confirmacion': self.password})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.assertNotIn(self.password, response.text)
        self.connection.cursor.assert_not_called()
