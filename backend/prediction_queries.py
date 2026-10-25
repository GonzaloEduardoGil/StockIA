"""Consulta de predicciones guardadas; no entrena ni modifica resultados."""
from fastapi import APIRouter, HTTPException
import main

router = APIRouter()


@router.get('/predicciones/', tags=['Predicciones'])
def consultar_predicciones():
    connection = None
    try:
        connection = main.obtener_conexion()
        connection.set_session(readonly=True)
        with connection.cursor() as cursor:
            cursor.execute('SET LOCAL statement_timeout = 10000')
            cursor.execute('''
                SELECT d."idPrediccion", d."idProducto", p.nombre, p.activo,
                       d."fechaPrediccion", d."periodoPrediccion", d."cantidadEstimada"
                FROM (
                    SELECT DISTINCT ON ("idProducto") *
                    FROM "PREDICCION_DEMANDA"
                    ORDER BY "idProducto", "fechaPrediccion" DESC, "idPrediccion" DESC
                ) d
                INNER JOIN PRODUCTO p ON p."idProducto" = d."idProducto"
                ORDER BY d."fechaPrediccion" DESC, d."idPrediccion" DESC
            ''')
            predictions = [dict(zip(
                ['idPrediccion', 'idProducto', 'nombreProducto', 'activo',
                 'fechaPrediccion', 'periodoPrediccion', 'cantidadEstimada'],
                [*row[:6], float(row[6])],
            )) for row in cursor.fetchall()]
        return {'predicciones': predictions, 'cantidad': len(predictions)}
    except Exception:
        raise HTTPException(status_code=500, detail='No se pudieron consultar las predicciones guardadas.') from None
    finally:
        if connection:
            connection.rollback()
            connection.close()
