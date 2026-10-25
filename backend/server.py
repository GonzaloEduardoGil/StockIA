"""Arranque web de StockIA. Conserva main.py y sus rutas originales."""
import os
from fastapi.middleware.cors import CORSMiddleware
from main import app
from authentication import router as authentication_router, AuthenticationMiddleware

app.include_router(authentication_router)
app.add_middleware(AuthenticationMiddleware)
from prediction_queries import router as prediction_router
from recommendation_queries import router as recommendation_router

app.include_router(prediction_router)
app.include_router(recommendation_router)

origins = [value.strip() for value in os.getenv(
    "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173",
).split(",") if value.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_methods=["GET", "POST", "PUT", "PATCH"], allow_headers=["Accept", "Content-Type", "Authorization"])
