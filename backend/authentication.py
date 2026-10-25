"""Acceso con las cuentas existentes, sesiones revocables y permisos del servidor."""
import hashlib
import hmac
import json
import re
import secrets
import threading
import time
from collections import OrderedDict
from pathlib import Path

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
import main

router = APIRouter()
hasher = PasswordHasher()
_dummy_hash = hasher.hash(secrets.token_urlsafe(32))
ROLES = {'Administrador', 'Encargado de stock', 'Vendedor'}
STOCK_ROLES = {'Administrador', 'Encargado de stock'}
SESSION_SECONDS = 8 * 60 * 60


def initialize_auth_schema():
    connection = main.obtener_conexion()
    try:
        with connection.cursor() as cursor:
            cursor.execute(Path(__file__).with_name('auth_schema.sql').read_text(encoding='utf-8'))
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


class LoginData(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=1024)


class LoginLimiter:
    def __init__(self):
        self._attempts = OrderedDict()
        self._lock = threading.Lock()

    def check(self, email, address):
        now = time.monotonic()
        keys = [(f'account:{address}:{email}', 5), (f'address:{address}', 30)]
        with self._lock:
            for value, limit in keys:
                key = hashlib.sha256(value.encode()).hexdigest()
                attempts = [t for t in self._attempts.get(key, []) if now - t < 60]
                if len(attempts) >= limit:
                    raise HTTPException(429, 'Demasiados intentos. Esperá un minuto e intentá nuevamente.')
                self._attempts[key] = attempts
            for value, _ in keys:
                key = hashlib.sha256(value.encode()).hexdigest()
                self._attempts[key].append(now)
                self._attempts.move_to_end(key)
            while len(self._attempts) > 4096:
                self._attempts.popitem(last=False)


limiter = LoginLimiter()


def verify_password(stored, supplied):
    if stored.startswith('$argon2'):
        try:
            return hasher.verify(stored, supplied)
        except (VerificationError, InvalidHashError):
            return False
    # Compatibilidad con las cuentas anteriores: al entrar correctamente,
    # su contraseña se reemplaza por un hash Argon2, sin cambiar la clave.
    try:
        hasher.verify(_dummy_hash, supplied)
    except (VerificationError, InvalidHashError):
        pass
    if stored.startswith(('$', 'pbkdf2', 'scrypt:')):
        return False
    return hmac.compare_digest(stored.encode('utf-8'), supplied.encode('utf-8'))


def public_user(row):
    return {'idUsuario': row[0], 'nombre': row[1], 'email': row[2], 'rol': row[3]}


@router.post('/auth/login', tags=['Autenticación'])
def login(data: LoginData, request: Request):
    email = data.email.strip().lower()
    limiter.check(email, request.client.host if request.client else 'unknown')
    connection = None
    try:
        connection = main.obtener_conexion()
        with connection.cursor() as cursor:
            cursor.execute('''SELECT "idUsuario", nombre, email, rol, contrasena
                              FROM "USUARIO" WHERE lower(email) = %s LIMIT 2''', (email,))
            rows = cursor.fetchall()
            stored = rows[0][4] if len(rows) == 1 else _dummy_hash
            valid = verify_password(stored, data.password)
            if len(rows) != 1 or not valid or rows[0][3] not in ROLES:
                raise HTTPException(401, 'Email o contraseña incorrectos.')
            user = rows[0]
            if not stored.startswith('$argon2') or hasher.check_needs_rehash(stored):
                cursor.execute('''UPDATE "USUARIO" SET contrasena = %s
                                  WHERE "idUsuario" = %s AND contrasena = %s''',
                               (hasher.hash(data.password), user[0], stored))
            token = secrets.token_urlsafe(32)
            digest = hashlib.sha256(token.encode('ascii')).hexdigest()
            cursor.execute('''INSERT INTO "STOCKIA_SESION" (token_hash, "idUsuario", expira)
                              VALUES (%s, %s, NOW() + %s * INTERVAL '1 second') RETURNING expira''',
                           (digest, user[0], SESSION_SECONDS))
            expiry = cursor.fetchone()[0]
        connection.commit()
        return {'token': token, 'usuario': public_user(user), 'expira': expiry}
    except HTTPException:
        if connection:
            connection.rollback()
        raise
    except Exception:
        if connection:
            connection.rollback()
        raise HTTPException(503, 'No se pudo iniciar sesión. Intentá nuevamente.') from None
    finally:
        if connection:
            connection.close()


def resolve_session(token):
    digest = hashlib.sha256(token.encode('ascii')).hexdigest()
    connection = main.obtener_conexion()
    connection.set_session(readonly=True)
    try:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT u."idUsuario", u.nombre, u.email, u.rol
                              FROM "STOCKIA_SESION" s
                              INNER JOIN "USUARIO" u ON u."idUsuario" = s."idUsuario"
                              WHERE s.token_hash = %s AND s.expira > NOW()''', (digest,))
            row = cursor.fetchone()
        if row is None or row[3] not in ROLES:
            return None
        return public_user(row)
    finally:
        try:
            connection.rollback()
        finally:
            connection.close()


@router.get('/auth/me', tags=['Autenticación'])
def me(request: Request):
    return request.state.user


@router.post('/auth/logout', tags=['Autenticación'])
def logout(request: Request):
    connection = main.obtener_conexion()
    try:
        with connection.cursor() as cursor:
            cursor.execute('DELETE FROM "STOCKIA_SESION" WHERE token_hash = %s',
                           (hashlib.sha256(request.state.auth_token.encode('ascii')).hexdigest(),))
        connection.commit()
        return {'sesionCerrada': True}
    except Exception:
        connection.rollback()
        raise HTTPException(503, 'No se pudo cerrar la sesión en el servicio.') from None
    finally:
        connection.close()


def allowed_roles(method, path):
    if path in ('/auth/me', '/auth/logout'):
        return ROLES
    if method == 'GET':
        if re.fullmatch(r'/(stock|productos|ventas)/?', path) or re.fullmatch(r'/(productos|ventas)/\d+', path):
            return ROLES
        if re.fullmatch(r'/(movimientos|alertas)(/\d+)?/?', path) or re.fullmatch(r'/(dashboard|predicciones|recomendaciones)/?', path) or re.fullmatch(r'/productos/\d+/analisis', path):
            return STOCK_ROLES
    if method == 'POST':
        if path.rstrip('/') == '/productos':
            return {'Administrador'}
        if path.rstrip('/') == '/ventas':
            return {'Vendedor'}
        if re.fullmatch(r'/stock/(entradas|ajustes)/\d+', path) or path == '/recomendaciones/generar' or re.fullmatch(r'/predicciones/\d+/generar', path):
            return STOCK_ROLES
    if method == 'PUT' and re.fullmatch(r'/productos/\d+', path):
        return {'Administrador'}
    if method == 'PATCH':
        if re.fullmatch(r'/productos/\d+/baja', path):
            return {'Administrador'}
        if re.fullmatch(r'/productos/\d+/stock-minimo', path) or re.fullmatch(r'/recomendaciones/\d+/decision', path):
            return STOCK_ROLES
    return None


class AuthenticationMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        path = request.url.path
        if request.method == 'OPTIONS' or path in ('/', '/auth/login', '/openapi.json', '/docs', '/docs/oauth2-redirect', '/redoc'):
            response = await call_next(request)
            if path.startswith('/auth/'):
                response.headers['Cache-Control'] = 'no-store'
            return response
        authorization = request.headers.get('authorization', '')
        parts = authorization.split()
        if len(parts) != 2 or parts[0].lower() != 'bearer' or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', parts[1]):
            return JSONResponse({'detail': 'Iniciá sesión para continuar.'}, 401, headers={'WWW-Authenticate': 'Bearer'})
        try:
            user = await run_in_threadpool(resolve_session, parts[1])
        except Exception:
            return JSONResponse({'detail': 'No se pudo verificar la sesión. Intentá nuevamente.'}, 503)
        if user is None:
            return JSONResponse({'detail': 'La sesión venció. Volvé a iniciar sesión.'}, 401, headers={'WWW-Authenticate': 'Bearer'})
        roles = allowed_roles(request.method, path)
        if roles is None:
            return JSONResponse({'detail': 'Ruta no disponible.'}, 404)
        if user['rol'] not in roles:
            return JSONResponse({'detail': 'Tu usuario no tiene permiso para esta operación.'}, 403)
        if request.method in ('POST', 'PATCH') and (path.rstrip('/') == '/ventas' or path.startswith('/recomendaciones/')):
            try:
                body = await request.json()
            except (json.JSONDecodeError, UnicodeDecodeError):
                return JSONResponse({'detail': 'Los datos de la operación no son válidos.'}, 422)
            if not isinstance(body, dict) or type(body.get('idUsuario')) is not int or body['idUsuario'] != user['idUsuario']:
                return JSONResponse({'detail': 'El usuario de la operación debe ser el de la sesión.'}, 403)
        request.state.user = user
        request.state.auth_token = parts[1]
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        return response
