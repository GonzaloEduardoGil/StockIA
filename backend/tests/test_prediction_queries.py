import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock
from fastapi import HTTPException


class PredictionQueriesTest(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.source = SimpleNamespace(obtener_conexion=MagicMock(return_value=self.connection))
        spec = importlib.util.spec_from_file_location('prediction_queries_under_test', Path(__file__).resolve().parents[1] / 'funciones' / 'predicciones.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.module.database = self.source

    def test_latest_saved_predictions_are_read_only(self):
        from datetime import date
        from decimal import Decimal
        self.cursor.fetchall.return_value = [(3, 7, 'Cuaderno', True, date(2026, 10, 23), 'Próximos 25 días', Decimal('83.00'))]
        result = self.module.consultar_predicciones()
        self.assertEqual(result['cantidad'], 1)
        self.assertEqual(result['predicciones'][0]['cantidadEstimada'], 83)
        self.connection.set_session.assert_called_once_with(readonly=True)
        sql = self.cursor.execute.call_args_list[-1].args[0]
        self.assertIn('DISTINCT ON ("idProducto")', sql)
        self.assertIn('"fechaPrediccion" DESC, "idPrediccion" DESC', sql)
        for call in self.cursor.execute.call_args_list:
            self.assertTrue(call.args[0].strip().startswith(('SELECT', 'SET LOCAL')))
        self.connection.commit.assert_not_called()
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_empty_predictions_are_not_fabricated(self):
        self.cursor.fetchall.return_value = []
        self.assertEqual(self.module.consultar_predicciones(), {'predicciones': [], 'cantidad': 0})

    def test_failure_closes_connection_without_exposing_database_error(self):
        self.cursor.execute.side_effect = RuntimeError('private database diagnostic')
        with self.assertRaises(HTTPException) as error:
            self.module.consultar_predicciones()
        self.assertEqual(error.exception.status_code, 500)
        self.assertNotIn('private', error.exception.detail)
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()
        self.connection.commit.assert_not_called()


if __name__ == '__main__':
    unittest.main()
