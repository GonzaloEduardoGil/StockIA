"""Alta, edición de identidad y consulta de cuentas operativas por el administrador."""
from contextlib import asynccontextmanager
import logging
import threading
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from psycopg2 import errors
from pydantic import BaseModel, ConfigDict, EmailStr, Field, StrictBool, field_validator
from starlette.concurrency import run_in_threadpool

from sistema import database
from sistema.database import rollback_quietly
from acceso.autenticacion import hasher, public_user
from sistema.validation import PrivateValidationRoute, PasswordData

logger = logging.getLogger(__name__)
_schema_lock = threading.Lock()
_schema_ready = False




def require_admin(request: Request):
    user = getattr(request.state, 'user', None)
    if not user:
        raise HTTPException(401, 'Iniciá sesión para continuar.')
    if user['rol'] != 'Administrador':
        raise HTTPException(403, 'Solo el administrador puede gestionar usuarios.')


router = APIRouter(route_class=PrivateValidationRoute,
                   dependencies=[Depends(require_admin)], tags=['Usuarios'])


class UserIdentity(BaseModel):
    model_config = ConfigDict(extra='forbid')
    nombre: str = Field(min_length=1, max_length=100)
    email: EmailStr = Field(max_length=255)

    @field_validator('nombre', 'email', mode='before')
    @classmethod
    def strip_fields(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator('email')
    @classmethod
    def normalize_email(cls, value):
        return str(value).lower()





class NewUser(UserIdentity, PasswordData):
    rol: Literal['Encargado de stock', 'Vendedor']


class UserStatus(BaseModel):
    model_config = ConfigDict(extra='forbid')
    activo: StrictBool


class UserRole(BaseModel):
    model_config = ConfigDict(extra='forbid')
    rol: Literal['Encargado de stock', 'Vendedor']


def managed_user(row):
    return {**public_user(row), 'activo': row[4]}


def initialize_user_schema():
    global _schema_ready
    with _schema_lock:
        if _schema_ready:
            return
        connection = database.obtener_conexion()
        try:
            with connection.cursor() as cursor:
                cursor.execute("SET LOCAL lock_timeout = '3s'")
                cursor.execute("SET LOCAL statement_timeout = '10s'")
                cursor.execute((Path(__file__).resolve().parents[1] / 'sql' / 'user_management_schema.sql').read_text(encoding='utf-8'))
            connection.commit()
            _schema_ready = True
        except Exception:
            rollback_quietly(connection)
            raise
        finally:
            connection.close()


@router.get('/usuarios/')
def list_users():
    connection = None
    try:
        connection = database.obtener_conexion()
        connection.set_session(readonly=True)
        with connection.cursor() as cursor:
            cursor.execute('''SELECT "idUsuario", nombre, email, rol, activo FROM "USUARIO"
                WHERE rol IN ('Encargado de stock', 'Vendedor')
                ORDER BY lower(nombre), "idUsuario"''')
            users = [managed_user(row) for row in cursor.fetchall()]
        return {'usuarios': users, 'cantidad': len(users)}
    except Exception:
        raise HTTPException(503, 'No se pudieron cargar los usuarios. Intentá nuevamente.') from None
    finally:
        if connection:
            rollback_quietly(connection)
            connection.close()


@router.post('/usuarios/', status_code=201)
def create_user(data: NewUser):
    connection = None
    try:
        initialize_user_schema()
        # Argon2 se calcula antes de tomar la conexión o bloquear escrituras.
        password_hash = hasher.hash(data.password.get_secret_value())
        connection = database.obtener_conexion()
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout = '3s'")
            cursor.execute("SET LOCAL statement_timeout = '10s'")
            # USUARIO no tiene secuencia/default para su ID. El bloqueo breve
            # coordina MAX+1 con otras altas y escrituras a la misma tabla.
            cursor.execute('LOCK TABLE "USUARIO" IN SHARE ROW EXCLUSIVE MODE')
            cursor.execute('SELECT 1 FROM "USUARIO" WHERE lower(btrim(email)) = %s', (data.email,))
            if cursor.fetchone():
                raise HTTPException(409, 'Ya existe un usuario con ese email.')
            cursor.execute('''INSERT INTO "USUARIO" ("idUsuario", nombre, email, rol, contrasena)
                SELECT COALESCE(MAX("idUsuario"), 0) + 1, %s, %s, %s, %s FROM "USUARIO"
                RETURNING "idUsuario", nombre, email, rol, activo''',
                (data.nombre, data.email, data.rol, password_hash))
            user = managed_user(cursor.fetchone())
        connection.commit()
        return {'usuario': user}
    except HTTPException:
        if connection:
            rollback_quietly(connection)
        raise
    except errors.UniqueViolation:
        if connection:
            rollback_quietly(connection)
        raise HTTPException(409, 'Ya existe un usuario con ese email.') from None
    except Exception:
        if connection:
            rollback_quietly(connection)
        raise HTTPException(503, 'No se pudo crear el usuario. Actualizá el listado antes de volver a intentarlo.') from None
    finally:
        if connection:
            connection.close()


@router.patch('/usuarios/{user_id}/')
def edit_user(user_id: int, data: UserIdentity):
    connection = None
    try:
        initialize_user_schema()
        connection = database.obtener_conexion()
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout = '3s'")
            cursor.execute("SET LOCAL statement_timeout = '10s'")
            cursor.execute('SELECT "idUsuario", nombre, email, rol FROM "USUARIO" WHERE "idUsuario" = %s FOR UPDATE', (user_id,))
            current = cursor.fetchone()
            if current is None:
                raise HTTPException(404, 'No se encontró el usuario.')
            if current[3] not in {'Encargado de stock', 'Vendedor'}:
                raise HTTPException(403, 'Solo se pueden editar encargados de stock y vendedores.')
            cursor.execute('SELECT 1 FROM "USUARIO" WHERE lower(btrim(email)) = %s AND "idUsuario" <> %s', (data.email, user_id))
            if cursor.fetchone():
                raise HTTPException(409, 'Ya existe un usuario con ese email.')
            # Rol y contraseña no forman parte del cuerpo ni del UPDATE.
            cursor.execute('''UPDATE "USUARIO" SET nombre = %s, email = %s
                WHERE "idUsuario" = %s RETURNING "idUsuario", nombre, email, rol, activo''',
                (data.nombre, data.email, user_id))
            user = managed_user(cursor.fetchone())
        connection.commit()
        return {'usuario': user}
    except HTTPException:
        if connection:
            rollback_quietly(connection)
        raise
    except errors.UniqueViolation:
        if connection:
            rollback_quietly(connection)
        raise HTTPException(409, 'Ya existe un usuario con ese email.') from None
    except Exception:
        if connection:
            rollback_quietly(connection)
        raise HTTPException(503, 'No se pudo confirmar la edición. Actualizá el listado antes de volver a intentarlo.') from None
    finally:
        if connection:
            connection.close()


def _change_access(user_id, change):
    connection = None
    try:
        initialize_user_schema()
        connection = database.obtener_conexion()
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout = '3s'")
            cursor.execute("SET LOCAL statement_timeout = '10s'")
            # Login toma el mismo bloqueo antes de verificar clave y emitir token.
            # Una sesión nueva no puede escapar a una baja o un reset concurrentes.
            cursor.execute('''SELECT "idUsuario", nombre, email, rol, activo
                FROM "USUARIO" WHERE "idUsuario" = %s FOR UPDATE''', (user_id,))
            current = cursor.fetchone()
            if current is None:
                raise HTTPException(404, 'No se encontró el usuario.')
            if current[3] not in {'Encargado de stock', 'Vendedor'}:
                raise HTTPException(403, 'Solo se pueden gestionar encargados de stock y vendedores.')
            user = managed_user(change(cursor, current))
        connection.commit()
        return {'usuario': user}
    except HTTPException:
        if connection:
            rollback_quietly(connection)
        raise
    except Exception:
        if connection:
            rollback_quietly(connection)
        raise HTTPException(503, 'No se pudo confirmar la operación. Actualizá el listado antes de volver a intentarlo.') from None
    finally:
        if connection:
            connection.close()


@router.patch('/usuarios/{user_id}/estado')
def change_status(user_id: int, data: UserStatus):
    def change(cursor, current):
        cursor.execute('''UPDATE "USUARIO" SET activo = %s WHERE "idUsuario" = %s
            RETURNING "idUsuario", nombre, email, rol, activo''', (data.activo, user_id))
        updated = cursor.fetchone()
        if not data.activo or not current[4]:
            cursor.execute('DELETE FROM "STOCKIA_SESION" WHERE "idUsuario" = %s', (user_id,))
        return updated
    return _change_access(user_id, change)


@router.post('/usuarios/{user_id}/password')
def reset_password(user_id: int, data: PasswordData):
    # El hash se calcula sin mantener una conexión ni un bloqueo.
    try:
        password_hash = hasher.hash(data.password.get_secret_value())
    except Exception:
        raise HTTPException(503, 'No se pudo preparar la nueva contraseña. Intentá nuevamente.') from None
    def change(cursor, current):
        cursor.execute('''UPDATE "USUARIO" SET contrasena = %s WHERE "idUsuario" = %s
            RETURNING "idUsuario", nombre, email, rol, activo''', (password_hash, user_id))
        updated = cursor.fetchone()
        cursor.execute('DELETE FROM "STOCKIA_SESION" WHERE "idUsuario" = %s', (user_id,))
        return updated
    return _change_access(user_id, change)


@router.patch('/usuarios/{user_id}/rol')
def change_role(user_id: int, data: UserRole):
    def change(cursor, current):
        if current[3] == data.rol:
            return current
        cursor.execute('''UPDATE "USUARIO" SET rol = %s WHERE "idUsuario" = %s
            RETURNING "idUsuario", nombre, email, rol, activo''', (data.rol, user_id))
        updated = cursor.fetchone()
        cursor.execute('DELETE FROM "STOCKIA_SESION" WHERE "idUsuario" = %s', (user_id,))
        return updated
    return _change_access(user_id, change)


def install_user_management(app):
    app.include_router(router)
    previous = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app):
        async with previous(app):
            try:
                await run_in_threadpool(initialize_user_schema)
            except Exception:
                logger.warning('No se pudo preparar el esquema de usuarios. Revisar sql/user_management_schema.sql y reiniciar el servicio.')
            yield

    app.router.lifespan_context = lifespan
