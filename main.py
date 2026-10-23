"""API de StockIA.

Este módulo reúne las rutas implementadas hasta CU 11:
productos, stock, movimientos y ventas.
"""

import os
from datetime import date
from decimal import Decimal
from typing import List, Optional

import psycopg2
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------

app = FastAPI(
    title="StockIA API",
    description="Backend para el sistema inteligente de gestión de inventario",
    version="1.0.0",
)

# Nunca guardar la contraseña de Supabase dentro de este archivo.
# En Windows, antes de iniciar la API, configurar DATABASE_URL en el entorno.
DATABASE_URL = "postgresql://postgres.ciohdzojeekegzxaepyu:xM2Adp11T1dVt4At@aws-0-us-east-1.pooler.supabase.com:5432/postgres"


def obtener_conexion():
    """Devuelve una conexión nueva a PostgreSQL."""
    if not DATABASE_URL:
        raise RuntimeError("La variable de entorno DATABASE_URL no está configurada.")
    return psycopg2.connect(DATABASE_URL)


def cerrar_recursos(conn, cursor) -> None:
    """Cierra cursor y conexión solo si fueron creados."""
    if cursor:
        cursor.close()
    if conn:
        conn.close()


# -----------------------------------------------------------------------------
# Modelos de entrada
# -----------------------------------------------------------------------------

class ProductoNuevo(BaseModel):
    nombre: str = Field(min_length=1)
    descripcion: Optional[str] = None
    categoria: Optional[str] = None
    precio: float = Field(gt=0)
    stockMinimo: int = Field(ge=0)
    stockInicial: int = Field(ge=0)


class ProductoActualizado(BaseModel):
    nombre: str = Field(min_length=1)
    descripcion: Optional[str] = None
    categoria: Optional[str] = None
    precio: float = Field(gt=0)


class StockMinimoActualizado(BaseModel):
    stockMinimo: int = Field(ge=0)


class EntradaStock(BaseModel):
    cantidad: int = Field(gt=0)
    motivo: Optional[str] = None


class AjusteStock(BaseModel):
    cantidad: int
    motivo: str


class ProductoVendido(BaseModel):
    idProducto: int
    cantidad: int = Field(gt=0)


class VentaNueva(BaseModel):
    idUsuario: int
    productos: List[ProductoVendido]


# -----------------------------------------------------------------------------
# Funciones auxiliares
# -----------------------------------------------------------------------------

def detectar_stock_bajo(cursor, id_producto: int):
    """Registra una alerta si el producto activo tiene stock menor o igual al mínimo."""
    cursor.execute(
        """
        SELECT p.nombre, p.activo, p."stockMinimo", s."cantidadDisponible"
        FROM PRODUCTO p
        INNER JOIN "STOCK" s ON s."idProducto" = p."idProducto"
        WHERE p."idProducto" = %s;
        """,
        (id_producto,),
    )
    producto = cursor.fetchone()

    if producto is None:
        return None

    nombre, activo, stock_minimo, cantidad_disponible = producto
    if not activo or cantidad_disponible > stock_minimo:
        return None

    mensaje = (
        f"Stock bajo para {nombre}: {cantidad_disponible} disponible(s), "
        f"mínimo configurado: {stock_minimo}."
    )

    cursor.execute(
        """
        INSERT INTO ALERTA (
            "idProducto", "fechaCreacion", mensaje,
            "cantidadDetectada", "stockMinimoDetectado"
        )
        VALUES (%s, CURRENT_TIMESTAMP, %s, %s, %s)
        RETURNING "idAlerta";
        """,
        (id_producto, mensaje, cantidad_disponible, stock_minimo),
    )
    id_alerta = cursor.fetchone()[0]

    return {"idAlerta": id_alerta, "mensaje": mensaje}


# -----------------------------------------------------------------------------
# Rutas generales
# -----------------------------------------------------------------------------

@app.get("/", tags=["General"])
def ruta_principal():
    return {"mensaje": "¡El motor de StockIA está funcionando!"}


# -----------------------------------------------------------------------------
# Productos - CU 01 a CU 05
# -----------------------------------------------------------------------------

@app.post("/productos/", tags=["Productos"])
def registrar_producto(producto: ProductoNuevo):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        cursor.execute(
            """
            INSERT INTO PRODUCTO (nombre, descripcion, categoria, precio, "stockMinimo")
            VALUES (%s, %s, %s, %s, %s)
            RETURNING "idProducto";
            """,
            (
                producto.nombre,
                producto.descripcion,
                producto.categoria,
                producto.precio,
                producto.stockMinimo,
            ),
        )
        nuevo_id = cursor.fetchone()[0]

        cursor.execute(
            """
            INSERT INTO "STOCK" ("idProducto", "cantidadDisponible", "fechaActualizacion")
            VALUES (%s, %s, CURRENT_DATE);
            """,
            (nuevo_id, producto.stockInicial),
        )
        conn.commit()

        return {
            "mensaje": "Producto y stock inicial registrados con éxito.",
            "idProducto": nuevo_id,
        }

    except Exception as exc:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"No se pudo registrar el producto: {exc}")

    finally:
        cerrar_recursos(conn, cursor)


@app.get("/productos/", tags=["Productos"])
def consultar_productos(criterio: Optional[str] = Query(default=None)):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        if criterio and criterio.strip():
            busqueda = f"%{criterio.strip()}%"
            cursor.execute(
                """
                SELECT "idProducto", nombre, descripcion, categoria, precio, "stockMinimo"
                FROM PRODUCTO
                WHERE nombre ILIKE %s OR categoria ILIKE %s
                ORDER BY nombre;
                """,
                (busqueda, busqueda),
            )
        else:
            cursor.execute(
                """
                SELECT "idProducto", nombre, descripcion, categoria, precio, "stockMinimo"
                FROM PRODUCTO
                ORDER BY nombre;
                """
            )

        productos = [
            {
                "idProducto": fila[0],
                "nombre": fila[1],
                "descripcion": fila[2],
                "categoria": fila[3],
                "precio": float(fila[4]),
                "stockMinimo": fila[5],
            }
            for fila in cursor.fetchall()
        ]
        return {"productos": productos, "cantidad": len(productos)}

    finally:
        cerrar_recursos(conn, cursor)


@app.get("/productos/{id_producto}", tags=["Productos"])
def consultar_producto_por_id(id_producto: int):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT "idProducto", nombre, descripcion, categoria, precio, "stockMinimo"
            FROM PRODUCTO
            WHERE "idProducto" = %s;
            """,
            (id_producto,),
        )
        fila = cursor.fetchone()

        if fila is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto solicitado.")

        return {
            "idProducto": fila[0],
            "nombre": fila[1],
            "descripcion": fila[2],
            "categoria": fila[3],
            "precio": float(fila[4]),
            "stockMinimo": fila[5],
        }

    finally:
        cerrar_recursos(conn, cursor)


@app.put("/productos/{id_producto}", tags=["Productos"])
def modificar_producto(id_producto: int, producto: ProductoActualizado):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute('SELECT activo FROM PRODUCTO WHERE "idProducto" = %s;', (id_producto,))
        resultado = cursor.fetchone()

        if resultado is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto solicitado.")
        if not resultado[0]:
            raise HTTPException(status_code=409, detail="El producto está inactivo y no puede modificarse.")

        cursor.execute(
            """
            UPDATE PRODUCTO
            SET nombre = %s, descripcion = %s, categoria = %s, precio = %s
            WHERE "idProducto" = %s AND activo = TRUE
            RETURNING "idProducto", nombre, descripcion, categoria, precio;
            """,
            (
                producto.nombre,
                producto.descripcion,
                producto.categoria,
                producto.precio,
                id_producto,
            ),
        )
        producto_actualizado = cursor.fetchone()
        conn.commit()

        return {
            "mensaje": "Producto modificado con éxito.",
            "producto": {
                "idProducto": producto_actualizado[0],
                "nombre": producto_actualizado[1],
                "descripcion": producto_actualizado[2],
                "categoria": producto_actualizado[3],
                "precio": float(producto_actualizado[4]),
            },
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail="No se pudo modificar el producto.")
    finally:
        cerrar_recursos(conn, cursor)


@app.patch("/productos/{id_producto}/baja", tags=["Productos"])
def dar_baja_producto(id_producto: int):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute('SELECT activo FROM PRODUCTO WHERE "idProducto" = %s;', (id_producto,))
        resultado = cursor.fetchone()

        if resultado is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto solicitado.")
        if not resultado[0]:
            raise HTTPException(status_code=409, detail="El producto ya se encuentra inactivo.")

        cursor.execute(
            """
            UPDATE PRODUCTO
            SET activo = FALSE
            WHERE "idProducto" = %s
            RETURNING "idProducto", nombre;
            """,
            (id_producto,),
        )
        producto = cursor.fetchone()
        conn.commit()

        return {
            "mensaje": "Producto dado de baja con éxito.",
            "idProducto": producto[0],
            "nombre": producto[1],
            "activo": False,
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail="No se pudo dar de baja el producto.")
    finally:
        cerrar_recursos(conn, cursor)


@app.patch("/productos/{id_producto}/stock-minimo", tags=["Productos"])
def configurar_stock_minimo(id_producto: int, datos: StockMinimoActualizado):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute('SELECT activo FROM PRODUCTO WHERE "idProducto" = %s;', (id_producto,))
        producto = cursor.fetchone()

        if producto is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto solicitado.")
        if not producto[0]:
            raise HTTPException(
                status_code=409,
                detail="No puede modificarse el stock mínimo de un producto inactivo.",
            )

        cursor.execute(
            'UPDATE PRODUCTO SET "stockMinimo" = %s WHERE "idProducto" = %s;',
            (datos.stockMinimo, id_producto),
        )
        alerta = detectar_stock_bajo(cursor, id_producto)

        cursor.execute(
            'SELECT "cantidadDisponible" FROM "STOCK" WHERE "idProducto" = %s;',
            (id_producto,),
        )
        fila_stock = cursor.fetchone()
        if fila_stock is None:
            raise HTTPException(
                status_code=409,
                detail="El producto no posee un registro de stock asociado.",
            )

        cantidad_disponible = fila_stock[0]
        conn.commit()

        return {
            "mensaje": "Stock mínimo actualizado con éxito.",
            "idProducto": id_producto,
            "stockMinimo": datos.stockMinimo,
            "cantidadDisponible": cantidad_disponible,
            "estadoStock": "BAJO" if cantidad_disponible <= datos.stockMinimo else "NORMAL",
            "alertaGenerada": alerta,
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception as exc:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"No se pudo configurar el stock mínimo: {exc}")
    finally:
        cerrar_recursos(conn, cursor)


# -----------------------------------------------------------------------------
# Stock y movimientos - CU 06 a CU 10
# -----------------------------------------------------------------------------

@app.get("/stock/", tags=["Stock"])
def consultar_stock(criterio: Optional[str] = Query(default=None)):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        consulta = """
            SELECT p."idProducto", p.nombre, p.categoria,
                   s."cantidadDisponible", p."stockMinimo",
                   CASE WHEN s."cantidadDisponible" <= p."stockMinimo"
                        THEN 'BAJO' ELSE 'NORMAL' END AS estado_stock
            FROM PRODUCTO p
            INNER JOIN "STOCK" s ON s."idProducto" = p."idProducto"
            WHERE p.activo = TRUE
        """
        parametros = []

        if criterio and criterio.strip():
            busqueda = f"%{criterio.strip()}%"
            consulta += " AND (p.nombre ILIKE %s OR p.categoria ILIKE %s)"
            parametros = [busqueda, busqueda]

        cursor.execute(consulta + " ORDER BY p.nombre;", parametros)
        productos = [
            {
                "idProducto": fila[0],
                "nombre": fila[1],
                "categoria": fila[2],
                "cantidadDisponible": fila[3],
                "stockMinimo": fila[4],
                "estadoStock": fila[5],
            }
            for fila in cursor.fetchall()
        ]
        return {"productos": productos, "cantidad": len(productos)}

    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"No se pudo consultar el stock: {exc}")
    finally:
        cerrar_recursos(conn, cursor)


@app.post("/stock/entradas/{id_producto}", tags=["Stock"])
def registrar_entrada_stock(id_producto: int, entrada: EntradaStock):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT p.nombre, p.activo, s."idStock", s."cantidadDisponible"
            FROM PRODUCTO p
            INNER JOIN "STOCK" s ON s."idProducto" = p."idProducto"
            WHERE p."idProducto" = %s
            FOR UPDATE OF s;
            """,
            (id_producto,),
        )
        producto = cursor.fetchone()

        if producto is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto o su stock.")

        nombre, activo, id_stock, cantidad_anterior = producto
        if not activo:
            raise HTTPException(
                status_code=409,
                detail="No se puede registrar una entrada para un producto inactivo.",
            )

        cursor.execute(
            """
            UPDATE "STOCK"
            SET "cantidadDisponible" = "cantidadDisponible" + %s,
                "fechaActualizacion" = CURRENT_DATE
            WHERE "idStock" = %s
            RETURNING "cantidadDisponible";
            """,
            (entrada.cantidad, id_stock),
        )
        cantidad_nueva = cursor.fetchone()[0]

        cursor.execute(
            """
            INSERT INTO "MOVIMIENTO_STOCK" ("idStock", fecha, "tipoMovimiento", cantidad, motivo)
            VALUES (%s, CURRENT_DATE, %s, %s, %s);
            """,
            (id_stock, "Entrada", entrada.cantidad, entrada.motivo),
        )
        alerta = detectar_stock_bajo(cursor, id_producto)
        conn.commit()

        return {
            "mensaje": "Entrada de stock registrada con éxito.",
            "idProducto": id_producto,
            "nombre": nombre,
            "cantidadAnterior": cantidad_anterior,
            "cantidadIngresada": entrada.cantidad,
            "cantidadDisponible": cantidad_nueva,
            "alertaGenerada": alerta,
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception as exc:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"No se pudo registrar la entrada de stock: {exc}")
    finally:
        cerrar_recursos(conn, cursor)


@app.post("/stock/ajustes/{id_producto}", tags=["Stock"])
def registrar_ajuste_stock(id_producto: int, ajuste: AjusteStock):
    conn = None
    cursor = None

    try:
        if ajuste.cantidad == 0:
            raise HTTPException(status_code=422, detail="La cantidad del ajuste no puede ser cero.")
        if not ajuste.motivo.strip():
            raise HTTPException(status_code=422, detail="El motivo del ajuste es obligatorio.")

        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT p.nombre, p.activo, s."idStock", s."cantidadDisponible"
            FROM PRODUCTO p
            INNER JOIN "STOCK" s ON s."idProducto" = p."idProducto"
            WHERE p."idProducto" = %s
            FOR UPDATE OF s;
            """,
            (id_producto,),
        )
        producto = cursor.fetchone()

        if producto is None:
            raise HTTPException(status_code=404, detail="No se encontró el producto o su stock.")

        nombre, activo, id_stock, cantidad_anterior = producto
        if not activo:
            raise HTTPException(status_code=409, detail="No se puede ajustar un producto inactivo.")

        cantidad_nueva = cantidad_anterior + ajuste.cantidad
        if cantidad_nueva < 0:
            raise HTTPException(
                status_code=409,
                detail=f"El ajuste dejaría stock negativo. Stock actual: {cantidad_anterior}.",
            )

        cursor.execute(
            """
            UPDATE "STOCK"
            SET "cantidadDisponible" = %s, "fechaActualizacion" = CURRENT_DATE
            WHERE "idStock" = %s;
            """,
            (cantidad_nueva, id_stock),
        )
        cursor.execute(
            """
            INSERT INTO "MOVIMIENTO_STOCK" ("idStock", fecha, "tipoMovimiento", cantidad, motivo)
            VALUES (%s, CURRENT_DATE, %s, %s, %s);
            """,
            (id_stock, "Ajuste", ajuste.cantidad, ajuste.motivo.strip()),
        )
        alerta = detectar_stock_bajo(cursor, id_producto)
        conn.commit()

        return {
            "mensaje": "Ajuste de stock registrado con éxito.",
            "idProducto": id_producto,
            "nombre": nombre,
            "cantidadAnterior": cantidad_anterior,
            "cantidadAjuste": ajuste.cantidad,
            "cantidadDisponible": cantidad_nueva,
            "alertaGenerada": alerta,
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception as exc:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"No se pudo registrar el ajuste de stock: {exc}")
    finally:
        cerrar_recursos(conn, cursor)


@app.get("/movimientos/", tags=["Movimientos"])
def consultar_movimientos(
    id_producto: Optional[int] = None,
    tipo_movimiento: Optional[str] = None,
    fecha_desde: Optional[date] = None,
    fecha_hasta: Optional[date] = None,
):
    conn = None
    cursor = None

    try:
        if tipo_movimiento:
            tipo_movimiento = tipo_movimiento.capitalize()
            if tipo_movimiento not in ["Entrada", "Ajuste", "Venta"]:
                raise HTTPException(
                    status_code=422,
                    detail="El tipo debe ser Entrada, Ajuste o Venta.",
                )

        conn = obtener_conexion()
        cursor = conn.cursor()
        consulta = """
            SELECT m."idMovimiento", m.fecha, m."tipoMovimiento", m.cantidad, m.motivo,
                   p."idProducto", p.nombre
            FROM "MOVIMIENTO_STOCK" m
            INNER JOIN "STOCK" s ON s."idStock" = m."idStock"
            INNER JOIN PRODUCTO p ON p."idProducto" = s."idProducto"
            WHERE 1 = 1
        """
        parametros = []

        if id_producto is not None:
            consulta += ' AND p."idProducto" = %s'
            parametros.append(id_producto)
        if tipo_movimiento:
            consulta += ' AND m."tipoMovimiento" = %s'
            parametros.append(tipo_movimiento)
        if fecha_desde:
            consulta += " AND m.fecha >= %s"
            parametros.append(fecha_desde)
        if fecha_hasta:
            consulta += " AND m.fecha <= %s"
            parametros.append(fecha_hasta)

        cursor.execute(consulta + ' ORDER BY m.fecha DESC, m."idMovimiento" DESC;', parametros)
        movimientos = [
            {
                "idMovimiento": fila[0],
                "fecha": fila[1],
                "tipoMovimiento": fila[2],
                "cantidad": fila[3],
                "motivo": fila[4],
                "idProducto": fila[5],
                "nombreProducto": fila[6],
            }
            for fila in cursor.fetchall()
        ]
        return {"movimientos": movimientos, "cantidad": len(movimientos)}

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"No se pudieron consultar los movimientos: {exc}")
    finally:
        cerrar_recursos(conn, cursor)


@app.get("/movimientos/{id_movimiento}", tags=["Movimientos"])
def consultar_detalle_movimiento(id_movimiento: int):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT m."idMovimiento", m.fecha, m."tipoMovimiento", m.cantidad, m.motivo,
                   p."idProducto", p.nombre
            FROM "MOVIMIENTO_STOCK" m
            INNER JOIN "STOCK" s ON s."idStock" = m."idStock"
            INNER JOIN PRODUCTO p ON p."idProducto" = s."idProducto"
            WHERE m."idMovimiento" = %s;
            """,
            (id_movimiento,),
        )
        fila = cursor.fetchone()

        if fila is None:
            raise HTTPException(status_code=404, detail="No se encontró el movimiento solicitado.")

        return {
            "idMovimiento": fila[0],
            "fecha": fila[1],
            "tipoMovimiento": fila[2],
            "cantidad": fila[3],
            "motivo": fila[4],
            "idProducto": fila[5],
            "nombreProducto": fila[6],
        }

    finally:
        cerrar_recursos(conn, cursor)


# -----------------------------------------------------------------------------
# Ventas - CU 11 - 13
# -----------------------------------------------------------------------------

@app.post("/ventas/", tags=["Ventas"])
def registrar_venta(venta: VentaNueva):
    conn = None
    cursor = None

    try:
        if not venta.productos:
            raise HTTPException(status_code=422, detail="La venta debe incluir al menos un producto.")

        ids_productos = [producto.idProducto for producto in venta.productos]
        if len(ids_productos) != len(set(ids_productos)):
            raise HTTPException(
                status_code=422,
                detail="Un producto no puede repetirse dentro de la misma venta.",
            )

        conn = obtener_conexion()
        cursor = conn.cursor()
        cursor.execute('SELECT rol FROM "USUARIO" WHERE "idUsuario" = %s;', (venta.idUsuario,))
        usuario = cursor.fetchone()

        if usuario is None:
            raise HTTPException(status_code=404, detail="No se encontró el usuario vendedor.")
        if usuario[0] != "Vendedor":
            raise HTTPException(status_code=403, detail="El usuario indicado no tiene rol de vendedor.")

        productos_procesados = []
        total_venta = Decimal("0")

        # Primero se valida todo. Si algo falla, no se crea ninguna venta parcial.
        for item in venta.productos:
            cursor.execute(
                """
                SELECT p.nombre, p.precio, p.activo, s."idStock", s."cantidadDisponible"
                FROM PRODUCTO p
                INNER JOIN "STOCK" s ON s."idProducto" = p."idProducto"
                WHERE p."idProducto" = %s
                FOR UPDATE OF s;
                """,
                (item.idProducto,),
            )
            producto = cursor.fetchone()

            if producto is None:
                raise HTTPException(status_code=404, detail=f"No existe el producto {item.idProducto}.")

            nombre, precio, activo, id_stock, cantidad_disponible = producto
            if not activo:
                raise HTTPException(status_code=409, detail=f"El producto '{nombre}' está inactivo.")
            if cantidad_disponible < item.cantidad:
                raise HTTPException(
                    status_code=409,
                    detail=f"Stock insuficiente para '{nombre}'. Disponible: {cantidad_disponible}.",
                )

            subtotal = precio * item.cantidad
            total_venta += subtotal
            productos_procesados.append(
                {
                    "idProducto": item.idProducto,
                    "nombre": nombre,
                    "idStock": id_stock,
                    "cantidad": item.cantidad,
                    "precioUnitario": precio,
                    "subtotal": subtotal,
                }
            )

        cursor.execute(
            """
            INSERT INTO "VENTA" ("idUsuario", fecha, total)
            VALUES (%s, CURRENT_DATE, %s)
            RETURNING "idVenta";
            """,
            (venta.idUsuario, total_venta),
        )
        id_venta = cursor.fetchone()[0]
        alertas = []

        for producto in productos_procesados:
            cursor.execute(
                """
                INSERT INTO "DETALLE_VENTA" (
                    "idVenta", "idProducto", cantidad, "precioUnitario", subtotal
                )
                VALUES (%s, %s, %s, %s, %s);
                """,
                (
                    id_venta,
                    producto["idProducto"],
                    producto["cantidad"],
                    producto["precioUnitario"],
                    producto["subtotal"],
                ),
            )
            cursor.execute(
                """
                UPDATE "STOCK"
                SET "cantidadDisponible" = "cantidadDisponible" - %s,
                    "fechaActualizacion" = CURRENT_DATE
                WHERE "idStock" = %s;
                """,
                (producto["cantidad"], producto["idStock"]),
            )
            cursor.execute(
                """
                INSERT INTO "MOVIMIENTO_STOCK" ("idStock", fecha, "tipoMovimiento", cantidad, motivo)
                VALUES (%s, CURRENT_DATE, %s, %s, %s);
                """,
                (
                    producto["idStock"],
                    "Venta",
                    producto["cantidad"],
                    f"Venta #{id_venta}",
                ),
            )

            alerta = detectar_stock_bajo(cursor, producto["idProducto"])
            if alerta:
                alertas.append(alerta)

        conn.commit()
        return {
            "mensaje": "Venta registrada con éxito.",
            "idVenta": id_venta,
            "total": float(total_venta),
            "productos": [
                {
                    "idProducto": producto["idProducto"],
                    "nombre": producto["nombre"],
                    "cantidad": producto["cantidad"],
                    "subtotal": float(producto["subtotal"]),
                }
                for producto in productos_procesados
            ],
            "alertasGeneradas": alertas,
        }

    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except Exception as exc:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"No se pudo registrar la venta: {exc}")
    finally:
        cerrar_recursos(conn, cursor)
@app.get("/ventas/", tags=["Ventas"])
def consultar_ventas(
    id_usuario: Optional[int] = None,
    fecha_desde: Optional[date] = None,
    fecha_hasta: Optional[date] = None
):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        consulta = """
            SELECT
                v."idVenta",
                v.fecha,
                v.total,
                u."idUsuario",
                u.nombre
            FROM "VENTA" v
            INNER JOIN "USUARIO" u
                ON u."idUsuario" = v."idUsuario"
            WHERE 1 = 1
        """

        parametros = []

        if id_usuario is not None:
            consulta += ' AND v."idUsuario" = %s'
            parametros.append(id_usuario)

        if fecha_desde:
            consulta += " AND v.fecha >= %s"
            parametros.append(fecha_desde)

        if fecha_hasta:
            consulta += " AND v.fecha <= %s"
            parametros.append(fecha_hasta)

        consulta += ' ORDER BY v.fecha DESC, v."idVenta" DESC;'

        cursor.execute(consulta, parametros)
        filas = cursor.fetchall()

        ventas = [
            {
                "idVenta": fila[0],
                "fecha": fila[1],
                "total": float(fila[2]),
                "idUsuario": fila[3],
                "vendedor": fila[4]
            }
            for fila in filas
        ]

        return {
            "ventas": ventas,
            "cantidad": len(ventas)
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudieron consultar las ventas: {str(e)}"
        )

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
@app.get("/ventas/{id_venta}", tags=["Ventas"])
def consultar_detalle_venta(id_venta: int):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                v."idVenta",
                v.fecha,
                v.total,
                u."idUsuario",
                u.nombre
            FROM "VENTA" v
            INNER JOIN "USUARIO" u
                ON u."idUsuario" = v."idUsuario"
            WHERE v."idVenta" = %s;
        """, (id_venta,))

        venta = cursor.fetchone()

        if venta is None:
            raise HTTPException(
                status_code=404,
                detail="No se encontró la venta solicitada."
            )

        cursor.execute("""
            SELECT
                dv."idDetalle",
                p."idProducto",
                p.nombre,
                dv.cantidad,
                dv."precioUnitario",
                dv.subtotal
            FROM "DETALLE_VENTA" dv
            INNER JOIN PRODUCTO p
                ON p."idProducto" = dv."idProducto"
            WHERE dv."idVenta" = %s
            ORDER BY dv."idDetalle";
        """, (id_venta,))

        detalles = [
            {
                "idDetalle": fila[0],
                "idProducto": fila[1],
                "nombreProducto": fila[2],
                "cantidad": fila[3],
                "precioUnitario": float(fila[4]),
                "subtotal": float(fila[5])
            }
            for fila in cursor.fetchall()
        ]

        return {
            "idVenta": venta[0],
            "fecha": venta[1],
            "total": float(venta[2]),
            "vendedor": {
                "idUsuario": venta[3],
                "nombre": venta[4]
            },
            "detalles": detalles
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo consultar el detalle de la venta: {str(e)}"
        )

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

# -----------------------------------------------------------------------------
# Alertas CU 15
# -----------------------------------------------------------------------------


@app.get("/alertas/", tags=["Alertas"])
def consultar_alertas(criterio: Optional[str] = Query(default=None)):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        consulta = """
            WITH alertas_recientes AS (
                SELECT DISTINCT ON ("idProducto")
                    "idAlerta",
                    "idProducto",
                    "fechaCreacion",
                    mensaje,
                    "cantidadDetectada",
                    "stockMinimoDetectado"
                FROM ALERTA
                ORDER BY
                    "idProducto",
                    "fechaCreacion" DESC,
                    "idAlerta" DESC
            )
            SELECT
                a."idAlerta",
                a."fechaCreacion",
                a.mensaje,
                p."idProducto",
                p.nombre,
                p.categoria,
                s."cantidadDisponible",
                p."stockMinimo"
            FROM PRODUCTO p
            INNER JOIN "STOCK" s
                ON s."idProducto" = p."idProducto"
            LEFT JOIN alertas_recientes a
                ON a."idProducto" = p."idProducto"
            WHERE p.activo = TRUE
              AND s."cantidadDisponible" <= p."stockMinimo"
        """

        parametros = []

        if criterio and criterio.strip():
            busqueda = f"%{criterio.strip()}%"
            consulta += """
                AND (
                    p.nombre ILIKE %s
                    OR p.categoria ILIKE %s
                )
            """
            parametros = [busqueda, busqueda]

        consulta += """
            ORDER BY
                (p."stockMinimo" - s."cantidadDisponible") DESC,
                p.nombre;
        """

        cursor.execute(consulta, parametros)
        filas = cursor.fetchall()

        alertas = [
            {
                "idAlerta": fila[0],
                "fechaCreacion": fila[1],
                "mensaje": fila[2],
                "idProducto": fila[3],
                "nombreProducto": fila[4],
                "categoria": fila[5],
                "cantidadDisponible": fila[6],
                "stockMinimo": fila[7],
                "estadoStock": "BAJO"
            }
            for fila in filas
        ]

        return {
            "alertas": alertas,
            "cantidad": len(alertas)
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudieron consultar las alertas: {str(e)}"
        )

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
@app.get("/alertas/{id_producto}" , tags=["Alertas"])
def consultar_detalle_alerta(id_producto: int):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                p."idProducto",
                p.nombre,
                p.descripcion,
                p.categoria,
                p.precio,
                p."stockMinimo",
                p.activo,
                s."cantidadDisponible",
                s."fechaActualizacion"
            FROM PRODUCTO p
            INNER JOIN "STOCK" s
                ON s."idProducto" = p."idProducto"
            WHERE p."idProducto" = %s;
        """, (id_producto,))

        producto = cursor.fetchone()

        if producto is None:
            raise HTTPException(
                status_code=404,
                detail="No se encontró el producto solicitado."
            )

        (
            id_producto,
            nombre,
            descripcion,
            categoria,
            precio,
            stock_minimo,
            activo,
            cantidad_disponible,
            fecha_actualizacion
        ) = producto

        if not activo or cantidad_disponible > stock_minimo:
            raise HTTPException(
                status_code=409,
                detail="La alerta ya no está vigente para este producto."
            )

        cursor.execute("""
            SELECT
                "idAlerta",
                "fechaCreacion",
                mensaje,
                "cantidadDetectada",
                "stockMinimoDetectado"
            FROM ALERTA
            WHERE "idProducto" = %s
            ORDER BY "fechaCreacion" DESC, "idAlerta" DESC
            LIMIT 1;
        """, (id_producto,))

        alerta = cursor.fetchone()

        return {
            "producto": {
                "idProducto": id_producto,
                "nombre": nombre,
                "descripcion": descripcion,
                "categoria": categoria,
                "precio": float(precio),
                "cantidadDisponible": cantidad_disponible,
                "stockMinimo": stock_minimo,
                "fechaActualizacion": fecha_actualizacion,
                "estadoStock": "BAJO"
            },
            "ultimaAlerta": (
                {
                    "idAlerta": alerta[0],
                    "fechaCreacion": alerta[1],
                    "mensaje": alerta[2],
                    "cantidadDetectada": alerta[3],
                    "stockMinimoDetectado": alerta[4]
                }
                if alerta else None
            )
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo consultar el detalle de la alerta: {str(e)}"
        )

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------
@app.get("/dashboard/", tags=["Dashboard"])
def consultar_dashboard(
    fecha_desde: Optional[date] = None,
    fecha_hasta: Optional[date] = None
):
    conn = None
    cursor = None

    try:
        conn = obtener_conexion()
        cursor = conn.cursor()

        filtro_ventas = "WHERE 1 = 1"
        parametros = []

        if fecha_desde:
            filtro_ventas += " AND fecha >= %s"
            parametros.append(fecha_desde)

        if fecha_hasta:
            filtro_ventas += " AND fecha <= %s"
            parametros.append(fecha_hasta)

        # Resumen general de ventas
        cursor.execute(f"""
            SELECT
                COUNT(*) AS cantidad_ventas,
                COALESCE(SUM(total), 0) AS total_facturado
            FROM "VENTA"
            {filtro_ventas};
        """, parametros)

        resumen_ventas = cursor.fetchone()

        # Evolución de ventas por día
        cursor.execute(f"""
            SELECT
                fecha,
                COUNT(*) AS cantidad_ventas,
                COALESCE(SUM(total), 0) AS total_facturado
            FROM "VENTA"
            {filtro_ventas}
            GROUP BY fecha
            ORDER BY fecha;
        """, parametros)

        evolucion_ventas = [
            {
                "fecha": fila[0],
                "cantidadVentas": fila[1],
                "totalFacturado": float(fila[2])
            }
            for fila in cursor.fetchall()
        ]

        # Ventas por producto durante el período elegido
        cursor.execute(f"""
            WITH ventas_periodo AS (
                SELECT "idVenta"
                FROM "VENTA"
                {filtro_ventas}
            )
            SELECT
                p."idProducto",
                p.nombre,
                COALESCE(SUM(dv.cantidad), 0) AS cantidad_vendida
            FROM PRODUCTO p
            LEFT JOIN "DETALLE_VENTA" dv
                ON dv."idProducto" = p."idProducto"
            LEFT JOIN ventas_periodo vp
                ON vp."idVenta" = dv."idVenta"
            WHERE p.activo = TRUE
              AND (
                  vp."idVenta" IS NOT NULL
                  OR dv."idDetalle" IS NULL
              )
            GROUP BY p."idProducto", p.nombre;
        """, parametros)

        productos_vendidos = [
            {
                "idProducto": fila[0],
                "nombre": fila[1],
                "cantidadVendida": fila[2]
            }
            for fila in cursor.fetchall()
        ]

        productos_mas_vendidos = sorted(
            productos_vendidos,
            key=lambda producto: producto["cantidadVendida"],
            reverse=True
        )[:5]

        productos_menos_vendidos = sorted(
            productos_vendidos,
            key=lambda producto: producto["cantidadVendida"]
        )[:5]

        # Estado actual del inventario
        cursor.execute("""
            SELECT
                COUNT(*) AS productos_activos,
                COALESCE(SUM(s."cantidadDisponible"), 0) AS unidades_disponibles,
                COUNT(*) FILTER (
                    WHERE s."cantidadDisponible" <= p."stockMinimo"
                ) AS productos_stock_bajo,
                COUNT(*) FILTER (
                    WHERE s."cantidadDisponible" > p."stockMinimo"
                ) AS productos_stock_normal
            FROM PRODUCTO p
            INNER JOIN "STOCK" s
                ON s."idProducto" = p."idProducto"
            WHERE p.activo = TRUE;
        """)

        inventario = cursor.fetchone()

        return {
            "periodo": {
                "fechaDesde": fecha_desde,
                "fechaHasta": fecha_hasta
            },
            "resumenVentas": {
                "cantidadVentas": resumen_ventas[0],
                "totalFacturado": float(resumen_ventas[1])
            },
            "productosMasVendidos": productos_mas_vendidos,
            "productosMenosVendidos": productos_menos_vendidos,
            "evolucionVentas": evolucion_ventas,
            "inventario": {
                "productosActivos": inventario[0],
                "unidadesDisponibles": inventario[1],
                "productosStockBajo": inventario[2],
                "productosStockNormal": inventario[3]
            },
            "informacionInsuficiente": len(evolucion_ventas) == 0
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo cargar el dashboard: {str(e)}"
        )

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()