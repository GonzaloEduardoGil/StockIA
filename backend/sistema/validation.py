"""Validación compartida de contraseñas y errores que nunca reflejan entradas."""
import hmac
from fastapi import HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator

class PrivateValidationRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def safe_handler(request):
            try:
                return await handler(request)
            except RequestValidationError as error:
                # La respuesta estándar incluye input; jamás devolver contraseñas.
                first = error.errors()[0]
                field = first['loc'][-1] if first.get('loc') else ''
                messages = {
                    'nombre': 'Ingresá un nombre de entre 1 y 100 caracteres.',
                    'email': 'Ingresá un email válido de hasta 255 caracteres.',
                    'rol': 'Elegí Encargado de stock o Vendedor.',
                    'passwordActual': 'Ingresá la contraseña actual.',
                    'password': 'La contraseña debe tener entre 8 y 1024 caracteres.',
                    'confirmacion': 'Revisá la confirmación de contraseña.',
                    'activo': 'Elegí un estado válido para la cuenta.',
                }
                message = messages.get(field, 'Revisá los datos del usuario.')
                raise HTTPException(422, message) from None

        return safe_handler


class PasswordData(BaseModel):
    model_config = ConfigDict(extra='forbid')
    password: SecretStr = Field(min_length=8, max_length=1024)
    confirmacion: SecretStr = Field(min_length=8, max_length=1024)

    @model_validator(mode='after')
    def passwords_match(self):
        password = self.password.get_secret_value()
        if not password.strip() or not hmac.compare_digest(
                password.encode('utf-8'), self.confirmacion.get_secret_value().encode('utf-8')):
            raise ValueError('Las contraseñas no coinciden o están vacías.')
        return self
