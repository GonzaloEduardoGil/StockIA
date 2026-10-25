"""Preparación inicial/idempotente. Ejecutar antes de iniciar server:app."""
from authentication import initialize_auth_schema

if __name__ == '__main__':
    initialize_auth_schema()
    print('Tabla de sesiones preparada. Cuentas y roles existentes conservados.')
