"""Predicciones: cálculo original compartido, consultas y programación semanal."""
from datetime import datetime, timedelta, timezone
from math import ceil
from fastapi import HTTPException
from pydantic import BaseModel, Field
import pandas as pd
from xgboost import XGBRegressor
from sistema.database import obtener_conexion
from fastapi import APIRouter, HTTPException
from sistema import database
import asyncio
from contextlib import asynccontextmanager
from datetime import timedelta
import logging
import os
from starlette.concurrency import run_in_threadpool
from sistema.database import transaction


ARGENTINA = timezone(timedelta(hours=-3))


def business_today():
    return datetime.now(ARGENTINA).date()


def periodo_semanal(fecha_historial):
    return f"Semanal: {fecha_historial + timedelta(days=1)} a {fecha_historial + timedelta(days=7)}"


class SolicitudPrediccion(BaseModel):
    diasPrediccion: int = Field(ge=1, le=30)


def _revertir(conn):
    if conn:
        try:
            conn.rollback()
        except Exception:
            pass


def _cerrar_recursos(cursor, conn):
    try:
        if cursor:
            cursor.close()
    finally:
        if conn:
            conn.close()


def generar_prediccion(
    id_producto: int,
    datos: SolicitudPrediccion,
    *, fecha_historial=None
):
    hoy = business_today()
    es_semanal = fecha_historial is not None
    fecha_historial = fecha_historial or hoy
    if es_semanal and (fecha_historial.weekday() != 6 or datos.diasPrediccion != 7):
        raise HTTPException(422, "La automática debe calcular siete días desde el cierre del domingo.")
    periodo_automatico = periodo_semanal(fecha_historial) if es_semanal else None
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        # El bloqueo vive en la misma transacción que guarda la predicción.
        cursor.execute("SELECT pg_try_advisory_xact_lock(71324, %s)", (id_producto,))
        if not cursor.fetchone()[0]:
            if es_semanal:
                return None
            raise HTTPException(409, "Ya se está generando una predicción para este producto. Intentá nuevamente en unos momentos.")
        if es_semanal:
            cursor.execute("""SELECT 1 FROM "PREDICCION_DEMANDA"
                WHERE "idProducto" = %s AND "periodoPrediccion" = %s LIMIT 1""",
                (id_producto, periodo_automatico))
            if cursor.fetchone():
                return None

        # Verifica el producto
        cursor.execute("""
            SELECT nombre, activo
            FROM PRODUCTO
            WHERE "idProducto" = %s;
        """, (id_producto,))

        producto = cursor.fetchone()

        if producto is None:
            raise HTTPException(
                status_code=404,
                detail="No se encontró el producto solicitado."
            )

        nombre_producto, activo = producto

        if not activo:
            raise HTTPException(
                status_code=409,
                detail="No se pueden generar predicciones para un producto inactivo."
            )

        # Obtiene ventas agrupadas por día
        cursor.execute("""
            SELECT
                v.fecha,
                SUM(dv.cantidad) AS cantidad_vendida
            FROM "DETALLE_VENTA" dv
            INNER JOIN "VENTA" v
                ON v."idVenta" = dv."idVenta"
            WHERE dv."idProducto" = %s AND v.fecha <= %s
            GROUP BY v.fecha
            ORDER BY v.fecha;
        """, (id_producto, fecha_historial))

        filas = cursor.fetchall()

        if len(filas) < 14:
            raise HTTPException(
                status_code=422,
                detail=(
                    "No hay suficiente historial para entrenar el modelo. "
                    "Se requieren al menos 14 días de ventas."
                )
            )

        ventas = pd.DataFrame(
            filas,
            columns=["fecha", "cantidadVendida"]
        )

        ventas["fecha"] = pd.to_datetime(ventas["fecha"])

        # Completa con cero los días en que no hubo ventas
        rango_fechas = pd.date_range(
            start=ventas["fecha"].min(),
            end=pd.Timestamp(fecha_historial),
            freq="D"
        )

        serie_ventas = (
            ventas
            .set_index("fecha")["cantidadVendida"]
            .reindex(rango_fechas, fill_value=0)
            .astype(float)
        )

        # Crea variables para el modelo
        entrenamiento = pd.DataFrame({
            "cantidad": serie_ventas
        })

        entrenamiento["venta_dia_anterior"] = (
            entrenamiento["cantidad"].shift(1)
        )

        entrenamiento["venta_hace_7_dias"] = (
            entrenamiento["cantidad"].shift(7)
        )

        entrenamiento["promedio_ultimos_7_dias"] = (
            entrenamiento["cantidad"]
            .shift(1)
            .rolling(window=7)
            .mean()
        )

        entrenamiento = entrenamiento.dropna()

        if len(entrenamiento) < 7:
            raise HTTPException(
                status_code=422,
                detail="No hay suficientes datos para entrenar XGBoost."
            )

        columnas = [
            "venta_dia_anterior",
            "venta_hace_7_dias",
            "promedio_ultimos_7_dias"
        ]

        X = entrenamiento[columnas]
        y = entrenamiento["cantidad"]

        modelo = XGBRegressor(
            objective="reg:squarederror",
            n_estimators=150,
            max_depth=3,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=42,
            n_jobs=1
        )

        modelo.fit(X, y)

        # Predice día por día para el período solicitado
        historial = list(serie_ventas.values)
        predicciones_diarias = []

        for _ in range(datos.diasPrediccion):
            datos_entrada = pd.DataFrame([{
                "venta_dia_anterior": historial[-1],
                "venta_hace_7_dias": historial[-7],
                "promedio_ultimos_7_dias": sum(historial[-7:]) / 7
            }])

            prediccion = float(modelo.predict(datos_entrada)[0])
            prediccion = max(0, prediccion)

            historial.append(prediccion)
            predicciones_diarias.append(prediccion)

        cantidad_estimada = ceil(sum(predicciones_diarias))
        periodo = f"Próximos {datos.diasPrediccion} días"

        # El campo de período existente identifica la semana, sin cambiar el esquema.
        if es_semanal:
            periodo = periodo_automatico
        cursor.execute('SELECT activo FROM PRODUCTO WHERE "idProducto" = %s FOR SHARE', (id_producto,))
        producto = cursor.fetchone()
        if not producto or not producto[0]:
            raise HTTPException(409, "El producto ya no está activo.")
        cursor.execute("SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires'")

        # Guarda el resultado para consultas y recomendaciones posteriores
        cursor.execute("""
            INSERT INTO "PREDICCION_DEMANDA" (
                "idProducto",
                "fechaPrediccion",
                "periodoPrediccion",
                "cantidadEstimada"
            )
            VALUES (%s, CURRENT_DATE, %s, %s)
            RETURNING "idPrediccion";
        """, (
            id_producto,
            periodo,
            cantidad_estimada
        ))

        id_prediccion = cursor.fetchone()[0]
        conn.commit()

        return {
            "mensaje": "Predicción generada con éxito.",
            "idPrediccion": id_prediccion,
            "idProducto": id_producto,
            "nombreProducto": nombre_producto,
            "periodoPrediccion": periodo,
            "cantidadEstimada": cantidad_estimada,
            "prediccionesDiarias": [
                round(prediccion, 2)
                for prediccion in predicciones_diarias
            ]
        }

    except HTTPException:
        _revertir(conn)
        raise

    except Exception as e:
        _revertir(conn)
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo generar la predicción: {str(e)}"
        )

    finally:
        try:
            _cerrar_recursos(cursor, conn)
        except Exception:
            pass


router = APIRouter()


@router.get('/predicciones/', tags=['Predicciones'])
def consultar_predicciones():
    connection = None
    try:
        connection = database.obtener_conexion()
        connection.set_session(readonly=True)
        with connection.cursor() as cursor:
            cursor.execute('SET LOCAL statement_timeout = 10000')
            cursor.execute('''
                SELECT d."idPrediccion", d."idProducto", p.nombre, p.activo,
                       d."fechaPrediccion", d."periodoPrediccion", d."cantidadEstimada"
                FROM (
                    SELECT DISTINCT ON ("idProducto") d.*
                    FROM "PREDICCION_DEMANDA" d
                    ORDER BY "idProducto", "fechaPrediccion" DESC, "idPrediccion" DESC
                ) d
                INNER JOIN PRODUCTO p ON p."idProducto" = d."idProducto"
                ORDER BY d."fechaPrediccion" DESC, d."idPrediccion" DESC
            ''')
            predictions = [dict(zip(
                ['idPrediccion', 'idProducto', 'nombreProducto', 'activo',
                 'fechaPrediccion', 'periodoPrediccion', 'cantidadEstimada'],
                [*row[:6], float(row[6]), *row[7:]],
            )) for row in cursor.fetchall()]
        return {'predicciones': predictions, 'cantidad': len(predictions)}
    except Exception:
        raise HTTPException(status_code=500, detail='No se pudieron consultar las predicciones guardadas.') from None
    finally:
        if connection:
            try:
                connection.rollback()
            except Exception:
                # La limpieza no debe reemplazar el resultado ni el error público.
                pass
            finally:
                # El pool devuelve o descarta el préstamo aunque falle el rollback.
                connection.close()


logger = logging.getLogger(__name__)


def weekly_batch(*, stop=lambda: False, today=None):
    today = today or business_today()
    monday = today - timedelta(days=today.weekday())
    domingo_cerrado = monday - timedelta(days=1)
    with transaction() as cursor:
        cursor.execute('''SELECT p."idProducto" FROM PRODUCTO p WHERE p.activo = TRUE
            AND NOT EXISTS (SELECT 1 FROM "PREDICCION_DEMANDA" d
                WHERE d."idProducto" = p."idProducto" AND d."periodoPrediccion" = %s)
            ORDER BY p."idProducto"''', (periodo_semanal(domingo_cerrado),))
        products = [row[0] for row in cursor.fetchall()]
    for product_id in products:
        if stop():
            break
        try:
            generar_prediccion(product_id, SolicitudPrediccion(diasPrediccion=7),
                               fecha_historial=domingo_cerrado)
        except HTTPException:
            # Sin historial, ocupado o falla individual: continuar con los demás.
            continue


class PredictionSchedule:
    def __init__(self):
        self.stopping = False
        self.task = None
        self.wakeup = asyncio.Event()

    async def run(self):
        while not self.stopping:
            try:
                await run_in_threadpool(weekly_batch, stop=lambda: self.stopping)
            except Exception:
                logger.warning('No se pudo actualizar la predicción semanal; se reintentará.')
            # Revisa semanas pendientes; los resultados guardados no se repiten.
            try:
                await asyncio.wait_for(self.wakeup.wait(), timeout=1800)
            except asyncio.TimeoutError:
                pass

    async def close(self):
        self.stopping = True
        self.wakeup.set()
        if self.task:
            # No cancelar un hilo que entrena y cerrar el pool mientras aún guarda.
            # Despertar la espera sin interrumpir una operación en curso.
            await self.task


def install_prediction_schedule(app):
    previous = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app):
        async with previous(app):
            schedule = PredictionSchedule()
            if os.getenv('PREDICTIONS_WEEKLY_ENABLED', 'true').lower() not in {'0', 'false', 'no'}:
                schedule.task = asyncio.create_task(schedule.run())
            try:
                yield
            finally:
                await schedule.close()

    app.router.lifespan_context = lifespan
