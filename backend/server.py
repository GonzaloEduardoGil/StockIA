"""Arranque web de StockIA. Conserva main.py y sus rutas originales."""
import os
from fastapi.middleware.cors import CORSMiddleware
from main import app

origins = [value.strip() for value in os.getenv(
    "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173",
).split(",") if value.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_methods=["GET", "POST", "PUT", "PATCH"], allow_headers=["Accept", "Content-Type"])
