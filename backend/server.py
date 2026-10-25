"""Arranque web de StockIA. Conserva main.py y sus rutas originales."""
import os
import psycopg2
import main
from alert_events import install_alert_events
from fastapi.middleware.cors import CORSMiddleware
from main import app
from authentication import router as authentication_router, AuthenticationMiddleware

app.include_router(authentication_router)
app.add_middleware(AuthenticationMiddleware)
from prediction_queries import router as prediction_router
from recommendation_queries import router as recommendation_router

app.include_router(prediction_router)
app.include_router(recommendation_router)


def connect_alert_listener():
    # LISTEN requiere una conexión directa o un pooler en modo sesión.
    # Puede configurarse aparte sin cambiar la URL original del backend.
    return psycopg2.connect(
        os.getenv('ALERTS_DATABASE_URL') or main.DATABASE_URL,
        connect_timeout=10, keepalives=1, keepalives_idle=30,
        keepalives_interval=10, keepalives_count=3,
    )


install_alert_events(app, connect_alert_listener)

origins = [value.strip() for value in os.getenv(
    "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173",
).split(",") if value.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_methods=["GET", "POST", "PUT", "PATCH"], allow_headers=["Accept", "Content-Type", "Authorization"])
