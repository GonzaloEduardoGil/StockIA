"""Integra la aplicación recibida, sin importar main ni crear otra instancia.

Conserva seguridad, CORS y el orden de preparación/cierre de los procesos.
"""
import os
from fastapi.middleware.cors import CORSMiddleware
from sistema.database import connect_alert_listener, install_database_pool
from acceso.autenticacion import AuthenticationMiddleware
from acceso import autenticacion
from funciones import recomendaciones
from funciones import predicciones
from funciones.alertas import install_alert_events
from funciones.predicciones import install_prediction_schedule
from acceso.usuarios import install_user_management


def configurar_aplicacion(app):
    if getattr(app.state, 'stockia_configurada', False):
        return app
    for feature in (recomendaciones, predicciones, autenticacion):
        app.include_router(feature.router)

    app.add_middleware(AuthenticationMiddleware)

    # Mantener este orden: el pool se abre primero y se cierra al final, después
    # de completar predicciones y detener el Observer.
    install_alert_events(app, connect_alert_listener)
    install_prediction_schedule(app)
    install_user_management(app)
    install_database_pool(app)

    origins = [value.strip() for value in os.getenv(
        "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173",
    ).split(",") if value.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins,
                       allow_methods=["GET", "POST", "PUT", "PATCH"], allow_headers=["Accept", "Content-Type", "Authorization"])

    app.state.stockia_configurada = True
    return app
