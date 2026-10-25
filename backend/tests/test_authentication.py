import hashlib
import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI, Request, HTTPException
from fastapi.testclient import TestClient
from fastapi.middleware.cors import CORSMiddleware


class AuthenticationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SimpleNamespace(obtener_conexion=MagicMock())
        spec = importlib.util.spec_from_file_location('authentication_under_test', Path(__file__).resolve().parents[1] / 'modules' / 'authentication.py')
        cls.auth = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'main': cls.source}):
            spec.loader.exec_module(cls.auth)
        cls.password = 'test-only-password-never-used-in-real-db'
        cls.password_hash = cls.auth.hasher.hash(cls.password)
        cls.token = 'T' * 43

    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.source.obtener_conexion.return_value = self.connection
        self.auth.limiter = self.auth.LoginLimiter()
        self.user = {'idUsuario': 73, 'nombre': 'Cuenta de prueba', 'email': 'test@example.test', 'rol': 'Vendedor'}
        self.app = FastAPI()
        self.app.include_router(self.auth.router)
        self.app.add_middleware(self.auth.AuthenticationMiddleware)
        self.app.add_middleware(CORSMiddleware, allow_origins=['http://localhost:5173'], allow_methods=['GET', 'POST', 'PATCH'], allow_headers=['Content-Type', 'Authorization'])

        @self.app.get('/stock/')
        def stock():
            return {'productos': []}

        @self.app.post('/ventas/')
        async def sale(request: Request):
            return {'body': await request.json(), 'usuarioVerificado': request.state.user['idUsuario']}

        @self.app.post('/productos/')
        def new_product():
            return {'ok': True}

        self.client = TestClient(self.app)

    def authorize(self, role='Vendedor'):
        self.user['rol'] = role
        return patch.object(self.auth, 'resolve_session', return_value=self.user)

    def headers(self):
        return {'Authorization': f'Bearer {self.token}'}

    def prepare_login(self, stored=None):
        self.cursor.fetchall.return_value = [(73, self.user['nombre'], self.user['email'], self.user['rol'], stored or self.password_hash)]
        self.cursor.fetchone.return_value = (datetime(2026, 12, 31, tzinfo=timezone.utc),)

    def test_password_correct_wrong_and_legacy_upgrade(self):
        self.assertTrue(self.auth.verify_password(self.password_hash, self.password))
        self.assertFalse(self.auth.verify_password(self.password_hash, 'wrong'))
        self.prepare_login(self.password)
        result = self.client.post('/auth/login', json={'email': ' TEST@example.test ', 'password': self.password})
        self.assertEqual(result.status_code, 200)
        queries = [call.args[0] for call in self.cursor.execute.call_args_list]
        self.assertTrue(any('UPDATE "USUARIO"' in q for q in queries))
        update = next(call for call in self.cursor.execute.call_args_list if 'UPDATE "USUARIO"' in call.args[0])
        self.assertTrue(update.args[1][0].startswith('$argon2id$'))
        self.assertTrue(self.auth.hasher.verify(update.args[1][0], self.password))

    def test_login_only_returns_public_identity_and_session_token_digest_is_stored(self):
        self.prepare_login()
        response = self.client.post('/auth/login', json={'email': self.user['email'], 'password': self.password, 'rol': 'Administrador'})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['usuario']['rol'], 'Vendedor')
        self.assertNotIn('contrasena', data['usuario'])
        insert = next(call for call in self.cursor.execute.call_args_list if 'INSERT INTO "STOCKIA_SESION"' in call.args[0])
        self.assertEqual(insert.args[1][0], hashlib.sha256(data['token'].encode()).hexdigest())
        self.assertNotIn(data['token'], str(self.cursor.execute.call_args_list))
        self.connection.commit.assert_called_once()

    def test_wrong_and_unknown_accounts_have_same_message_and_never_write(self):
        self.prepare_login()
        wrong = self.client.post('/auth/login', json={'email': self.user['email'], 'password': 'wrong'})
        self.cursor.fetchall.return_value = []
        unknown = self.client.post('/auth/login', json={'email': 'unknown@example.test', 'password': 'wrong'})
        self.assertEqual(wrong.status_code, 401)
        self.assertEqual(unknown.json(), wrong.json())
        self.assertFalse(any('INSERT' in c.args[0] or 'UPDATE' in c.args[0] for c in self.cursor.execute.call_args_list))

    def test_requests_without_or_with_expired_session_are_rejected(self):
        self.assertEqual(self.client.get('/stock/').status_code, 401)
        with patch.object(self.auth, 'resolve_session', return_value=None):
            self.assertEqual(self.client.get('/stock/', headers=self.headers()).status_code, 401)

    def test_roles_are_checked_on_server(self):
        with self.authorize('Vendedor'):
            self.assertEqual(self.client.post('/productos/', json={}, headers=self.headers()).status_code, 403)
            self.assertEqual(self.client.get('/dashboard/', headers=self.headers()).status_code, 403)
        with self.authorize('Administrador'):
            self.assertEqual(self.client.post('/productos/', json={}, headers=self.headers()).status_code, 200)
        with self.authorize('Encargado de stock'):
            self.assertEqual(self.client.post('/ventas/', json={'idUsuario': 73}, headers=self.headers()).status_code, 403)

    def test_cannot_send_another_user_id_and_valid_body_survives_middleware(self):
        with self.authorize():
            wrong = self.client.post('/ventas/', json={'idUsuario': 99, 'productos': []}, headers=self.headers())
            valid = self.client.post('/ventas/', json={'idUsuario': 73, 'productos': []}, headers=self.headers())
        self.assertEqual(wrong.status_code, 403)
        self.assertEqual(valid.status_code, 200)
        self.assertEqual(valid.json()['body']['idUsuario'], 73)
        self.assertEqual(valid.json()['usuarioVerificado'], 73)

    def test_logout_revokes_only_current_token(self):
        with self.authorize():
            response = self.client.post('/auth/logout', headers=self.headers())
        self.assertEqual(response.status_code, 200)
        delete = self.cursor.execute.call_args
        self.assertIn('DELETE FROM "STOCKIA_SESION"', delete.args[0])
        self.assertEqual(delete.args[1], (hashlib.sha256(self.token.encode()).hexdigest(),))
        self.connection.commit.assert_called_once()

    def test_cors_applies_to_unauthorized_responses_and_preflight(self):
        response = self.client.get('/stock/', headers={'Origin': 'http://localhost:5173'})
        self.assertEqual(response.headers['access-control-allow-origin'], 'http://localhost:5173')
        preflight = self.client.options('/auth/login', headers={'Origin': 'http://localhost:5173', 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'content-type'})
        self.assertEqual(preflight.status_code, 200)

    def test_rate_limiter_and_session_readonly_lookup(self):
        limit = self.auth.LoginLimiter()
        for _ in range(5):
            limit.check('x@example.test', 'test-address')
        with self.assertRaises(HTTPException) as error:
            limit.check('x@example.test', 'test-address')
        self.assertEqual(error.exception.status_code, 429)
        self.cursor.fetchone.return_value = None
        self.assertIsNone(self.auth.resolve_session(self.token))
        self.connection.set_session.assert_called_once_with(readonly=True)
        self.connection.commit.assert_not_called()


if __name__ == '__main__':
    unittest.main()
