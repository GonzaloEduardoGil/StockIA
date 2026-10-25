"""Desde backend: python -m scripts.init_auth_db. Ejecutar antes de server:app."""
from modules.authentication import initialize_auth_schema

if __name__ == '__main__':
    initialize_auth_schema()
    print('Tabla de sesiones preparada. Cuentas y roles existentes conservados.')
