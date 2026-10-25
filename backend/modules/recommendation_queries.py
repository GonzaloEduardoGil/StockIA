"""Historial de recomendaciones guardadas. Todas las consultas son de lectura."""
from fastapi import APIRouter, HTTPException
import main

router = APIRouter()


@router.get('/recomendaciones/', tags=['Recomendaciones'])
def consultar_recomendaciones():
    connection = None
    try:
        connection = main.obtener_conexion()
        connection.set_session(readonly=True)
        with connection.cursor() as cursor:
            cursor.execute('SET LOCAL statement_timeout = 10000')
            cursor.execute('''
                SELECT r."idRecomendacion", r."idProducto", p.nombre, p.activo,
                       r."idUsuario", u.nombre, r.fecha, r.tipo,
                       r."cantidadSugerida", r.motivo, r.estado
                FROM "RECOMENDACION" r
                INNER JOIN PRODUCTO p ON p."idProducto" = r."idProducto"
                INNER JOIN "USUARIO" u ON u."idUsuario" = r."idUsuario"
                ORDER BY r.fecha DESC, r."idRecomendacion" DESC
            ''')
            rows = [dict(zip(
                ['idRecomendacion', 'idProducto', 'nombreProducto', 'activo',
                 'idUsuario', 'nombreUsuario', 'fecha', 'tipo',
                 'cantidadSugerida', 'motivo', 'estado'], row,
            )) for row in cursor.fetchall()]
        return {'recomendaciones': rows, 'cantidad': len(rows)}
    except Exception:
        raise HTTPException(status_code=500, detail='No se pudieron consultar las recomendaciones guardadas.') from None
    finally:
        if connection:
            try:
                connection.rollback()
            finally:
                connection.close()
