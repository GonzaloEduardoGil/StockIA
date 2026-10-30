"""Regresiones de la extracción: unidades de trabajo completas, sin DB real."""
from decimal import Decimal
import unittest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
import main as inventario
import main as ventas


class BackendTransactionTest(unittest.TestCase):
    def test_sale_keeps_stock_details_movements_and_notifications_in_one_transaction(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [
            ('Vendedor',), ('A', Decimal('5'), True, 11, 8),
            ('B', Decimal('4'), True, 12, 9), (101,),
            ('A', True, 0, 6), ('B', True, 0, 8),
        ]
        request = ventas.VentaNueva(idUsuario=73, productos=[
            ventas.ProductoVendido(idProducto=7, cantidad=2),
            ventas.ProductoVendido(idProducto=8, cantidad=1),
        ])
        with patch.object(ventas, 'obtener_conexion', return_value=connection) as acquire:
            result = ventas.registrar_venta(request)
        self.assertEqual(result['idVenta'], 101)
        self.assertEqual(result['total'], 14)
        acquire.assert_called_once()
        connection.cursor.assert_called_once()
        connection.commit.assert_called_once()
        connection.rollback.assert_not_called()
        connection.close.assert_called_once()
        sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertEqual(sum('INSERT INTO "DETALLE_VENTA"' in q for q in sql), 2)
        self.assertEqual(sum('INSERT INTO "MOVIMIENTO_STOCK"' in q for q in sql), 2)
        self.assertEqual(sum('pg_notify' in q for q in sql), 2)

    def test_sale_failure_after_writes_rolls_back_without_partial_commit(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.side_effect = [('Vendedor',), ('A', Decimal('5'), True, 11, 8), (101,)]

        def execute(sql, *args):
            if 'INSERT INTO "MOVIMIENTO_STOCK"' in sql:
                raise RuntimeError('Falla simulada al registrar el movimiento')

        cursor.execute.side_effect = execute
        request = ventas.VentaNueva(idUsuario=73, productos=[ventas.ProductoVendido(idProducto=7, cantidad=2)])
        with patch.object(ventas, 'obtener_conexion', return_value=connection) as acquire:
            with self.assertRaises(HTTPException) as error:
                ventas.registrar_venta(request)
        self.assertEqual(error.exception.status_code, 500)
        acquire.assert_called_once()
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()
        connection.close.assert_called_once()
        sql = '\n'.join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn('INSERT INTO "VENTA"', sql)
        self.assertIn('UPDATE "STOCK"', sql)

    def test_entry_and_adjustment_rollback_if_movement_cannot_be_saved(self):
        cases = [(inventario.registrar_entrada_stock, inventario.EntradaStock(cantidad=2),
                  [('A', True, 11, 8), (10,)]),
                 (inventario.registrar_ajuste_stock, inventario.AjusteStock(cantidad=-1, motivo='Pérdida'),
                  [('A', True, 11, 8)])]
        for operation, data, rows in cases:
            with self.subTest(operation=operation.__name__):
                connection = MagicMock()
                cursor = connection.cursor.return_value
                cursor.fetchone.side_effect = rows

                def execute(sql, *args):
                    if 'INSERT INTO "MOVIMIENTO_STOCK"' in sql:
                        raise RuntimeError('Movimiento no disponible')

                cursor.execute.side_effect = execute
                with patch.object(inventario, 'obtener_conexion', return_value=connection) as acquire:
                    with self.assertRaises(HTTPException):
                        operation(7, data)
                acquire.assert_called_once()
                connection.commit.assert_not_called()
                connection.rollback.assert_called_once()
                connection.close.assert_called_once()
