from datetime import datetime, timezone
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from psycopg2.errors import UniqueViolation
from acceso import autenticacion as auth, usuarios as users
from acceso import autenticacion as security


class UserManagementTest(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.patches = [patch.object(users.database, 'obtener_conexion', return_value=self.connection),
                        patch.object(users, '_schema_ready', True)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)
        self.app = FastAPI()
        self.app.include_router(auth.router)
        self.app.include_router(users.router)
        self.app.add_middleware(security.AuthenticationMiddleware)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.admin = {'idUsuario': 1, 'nombre': 'Admin', 'email': 'admin@example.com', 'rol': 'Administrador'}
        self.headers = {'Authorization': 'Bearer ' + 'A' * 43}
        self.payload = dict(nombre=' Cuenta nueva ', email=' Nueva@EXAMPLE.COM ', rol='Vendedor',
                            password='Only-Test-Password-998', confirmacion='Only-Test-Password-998')

    def authorize(self, role='Administrador'):
        return patch.object(security, 'resolve_session', return_value={**self.admin, 'rol': role})

    def test_routes_are_exclusive_to_admin(self):
        for method in ['get', 'post']:
            request = getattr(self.client, method)
            kwargs = {'json': self.payload} if method == 'post' else {}
            self.assertEqual(request('/usuarios/', **kwargs).status_code, 401)
            for role in ['Vendedor', 'Encargado de stock']:
                with self.authorize(role):
                    self.assertEqual(request('/usuarios/', headers=self.headers, **kwargs).status_code, 403)
        self.connection.cursor.assert_not_called()

    def test_create_hashes_password_normalizes_email_and_returns_only_identity(self):
        for role in ['Vendedor', 'Encargado de stock']:
            with self.subTest(role=role):
                self.cursor.fetchone.side_effect = [None, (7, 'Cuenta nueva', 'nueva@example.com', role, True)]
                with self.authorize():
                    response = self.client.post('/usuarios/', headers=self.headers, json={**self.payload, 'rol': role})
                self.assertEqual(response.status_code, 201)
                self.assertEqual(set(response.json()['usuario']), {'idUsuario', 'nombre', 'email', 'rol', 'activo'})
                self.assertNotIn(self.payload['password'], response.text)
                self.assertNotIn('$argon2', response.text)
                insert = next(call for call in reversed(self.cursor.execute.call_args_list) if 'INSERT INTO "USUARIO"' in call.args[0])
                self.assertEqual(insert.args[1][:3], ('Cuenta nueva', 'nueva@example.com', role))
                self.assertTrue(auth.hasher.verify(insert.args[1][3], self.payload['password']))
                self.assertIn('COALESCE(MAX("idUsuario"), 0) + 1', insert.args[0])
        self.assertTrue(any('LOCK TABLE' in call.args[0] for call in self.cursor.execute.call_args_list))
        self.assertEqual(self.connection.commit.call_count, 2)
        self.assertEqual(self.connection.close.call_count, 2)

    def test_invalid_data_and_confirmation_never_echo_password_or_write(self):
        cases = [{'rol': 'Administrador'}, {'email': 'no-es-email'}, {'nombre': '   '},
                 {'password': 'short'}, {'confirmacion': 'Different-password'},
                 {'extra': 'forbidden'}, {'password': ' ' * 10, 'confirmacion': ' ' * 10}]
        with self.authorize():
            for change in cases:
                with self.subTest(change=change):
                    response = self.client.post('/usuarios/', headers=self.headers, json={**self.payload, **change})
                    self.assertEqual(response.status_code, 422)
                    self.assertNotIn(self.payload['password'], response.text)
                    self.assertNotIn('Different-password', response.text)
                    self.assertNotIn('"input"', response.text)
        self.connection.cursor.assert_not_called()

    def test_duplicate_email_is_conflict_and_does_not_insert(self):
        self.cursor.fetchone.return_value = (1,)
        with self.authorize():
            response = self.client.post('/usuarios/', headers=self.headers, json=self.payload)
        self.assertEqual(response.status_code, 409)
        self.assertFalse(any('INSERT INTO' in call.args[0] for call in self.cursor.execute.call_args_list))
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_unique_constraint_and_broken_rollback_keep_clear_error(self):
        self.cursor.execute.side_effect = UniqueViolation('private constraint diagnostic')
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.post('/usuarios/', headers=self.headers, json=self.payload)
        self.assertEqual(response.status_code, 409)
        self.assertNotIn('private', response.text)
        self.connection.close.assert_called_once()

    def test_list_never_queries_or_returns_passwords(self):
        self.cursor.fetchall.return_value = [(7, 'Cuenta nueva', 'nueva@example.com', 'Vendedor', True)]
        with self.authorize():
            response = self.client.get('/usuarios/', headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['cantidad'], 1)
        self.assertNotIn('contrasena', self.cursor.execute.call_args.args[0])
        self.assertNotIn('password', response.text)
        self.connection.set_session.assert_called_once_with(readonly=True)
        self.connection.close.assert_called_once()

    def test_list_failure_still_closes_if_rollback_is_broken(self):
        self.cursor.execute.side_effect = RuntimeError('private query')
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.get('/usuarios/', headers=self.headers)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.close.assert_called_once()

    def test_new_account_password_works_with_existing_login(self):
        self.cursor.fetchone.side_effect = [None, (7, 'Cuenta nueva', 'nueva@example.com', 'Vendedor', True)]
        with self.authorize():
            created = self.client.post('/usuarios/', headers=self.headers, json=self.payload)
        self.assertEqual(created.status_code, 201)
        insert = next(call for call in self.cursor.execute.call_args_list if 'INSERT INTO "USUARIO"' in call.args[0])
        self.cursor.fetchall.return_value = [(7, 'Cuenta nueva', 'nueva@example.com', 'Vendedor', insert.args[1][3], True)]
        self.cursor.fetchone.side_effect = [(datetime(2030, 1, 1, tzinfo=timezone.utc),)]
        with patch.object(auth, 'limiter', auth.LoginLimiter()):
            response = self.client.post('/auth/login', json={'email': 'NUEVA@example.com', 'password': self.payload['password']})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['usuario']['rol'], 'Vendedor')
        self.assertNotIn('password', response.json()['usuario'])

    def test_schema_enforces_case_insensitive_uniqueness(self):
        with patch.object(users, '_schema_ready', False):
            users.initialize_user_schema()
        sql = '\n'.join(call.args[0] for call in self.cursor.execute.call_args_list)
        self.assertIn('CREATE UNIQUE INDEX', sql)
        self.assertIn('lower(btrim(email))', sql)
        self.connection.commit.assert_called_once()

    def test_edit_routes_are_admin_only(self):
        payload = {'nombre': 'Editado', 'email': 'editado@example.com'}
        self.assertEqual(self.client.patch('/usuarios/7/', json=payload).status_code, 401)
        for role in ['Vendedor', 'Encargado de stock']:
            with self.authorize(role):
                self.assertEqual(self.client.patch('/usuarios/7/', headers=self.headers, json=payload).status_code, 403)
        self.connection.cursor.assert_not_called()

    def test_edit_only_updates_name_and_email_for_each_operational_role(self):
        for role in ['Vendedor', 'Encargado de stock']:
            self.cursor.fetchone.side_effect = [(7, 'Antes', 'antes@example.com', role), None,
                                                (7, 'Editado', 'editado@example.com', role, True)]
            with self.authorize():
                response = self.client.patch('/usuarios/7/', headers=self.headers,
                    json={'nombre': ' Editado ', 'email': ' EDITADO@EXAMPLE.COM '})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()['usuario']['rol'], role)
            update = self.cursor.execute.call_args
            self.assertEqual(update.args[1], ('Editado', 'editado@example.com', 7))
            self.assertNotIn('contrasena', update.args[0])
            self.assertNotIn('SET rol', update.args[0])
            self.assertEqual(set(response.json()['usuario']), {'idUsuario', 'nombre', 'email', 'rol', 'activo'})
        self.assertEqual(self.connection.commit.call_count, 2)
        self.assertEqual(self.connection.close.call_count, 2)

    def test_edit_rejects_role_password_and_invalid_identity(self):
        with self.authorize():
            for change in [{'rol': 'Administrador'}, {'password': 'private-test-password'},
                           {'confirmacion': 'private-test-password'}, {'email': 'invalido'}, {'nombre': '  '}]:
                response = self.client.patch('/usuarios/7/', headers=self.headers,
                    json={'nombre': 'Editado', 'email': 'editado@example.com', **change})
                self.assertEqual(response.status_code, 422)
                self.assertNotIn('private-test-password', response.text)
        self.connection.cursor.assert_not_called()

    def test_edit_rejects_missing_user_and_administrator_target(self):
        with self.authorize():
            for current, status in [(None, 404), ((1, 'Admin', 'admin@example.com', 'Administrador'), 403)]:
                self.cursor.fetchone.side_effect = [current]
                response = self.client.patch('/usuarios/1/', headers=self.headers,
                    json={'nombre': 'Editado', 'email': 'editado@example.com'})
                self.assertEqual(response.status_code, status)
        self.assertFalse(any('UPDATE "USUARIO"' in c.args[0] for c in self.cursor.execute.call_args_list))

    def test_edit_duplicate_email_and_constraint_failure_release_connection(self):
        self.cursor.fetchone.side_effect = [(7, 'Antes', 'antes@example.com', 'Vendedor'), (1,)]
        with self.authorize():
            response = self.client.patch('/usuarios/7/', headers=self.headers,
                json={'nombre': 'Editado', 'email': 'ocupado@example.com'})
        self.assertEqual(response.status_code, 409)
        self.assertIn('"idUsuario" <> %s', self.cursor.execute.call_args.args[0])
        self.connection.close.assert_called_once()
        self.connection.reset_mock()
        self.cursor.execute.side_effect = UniqueViolation('private diagnostic')
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.patch('/usuarios/7/', headers=self.headers,
                json={'nombre': 'Editado', 'email': 'ocupado@example.com'})
        self.assertEqual(response.status_code, 409)
        self.assertNotIn('private', response.text)
        self.connection.close.assert_called_once()

    def test_edit_database_failure_is_public_and_always_releases(self):
        self.cursor.execute.side_effect = RuntimeError('private diagnostic')
        self.connection.rollback.side_effect = RuntimeError('private cleanup')
        with self.authorize():
            response = self.client.patch('/usuarios/7/', headers=self.headers,
                json={'nombre': 'Editado', 'email': 'editado@example.com'})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.close.assert_called_once()
