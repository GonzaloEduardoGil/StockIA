import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import MagicMock, patch
from fastapi import HTTPException


class RecommendationQueriesTest(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        spec = importlib.util.spec_from_file_location('recommendation_queries_under_test', Path(__file__).resolve().parents[1] / 'recommendation_queries.py')
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'main': SimpleNamespace(obtener_conexion=lambda: self.connection)}):
            spec.loader.exec_module(self.module)

    def test_history_includes_pending_and_decided_records_read_only(self):
        from datetime import date
        self.cursor.fetchall.return_value = [(9, 7, 'Cuaderno', True, 73, 'Encargado', date(2026, 10, 24), 'Reposición', 40, 'Stock bajo', 'Pendiente')]
        result = self.module.consultar_recomendaciones()
        self.assertEqual(result['recomendaciones'][0]['idUsuario'], 73)
        self.assertEqual(result['recomendaciones'][0]['cantidadSugerida'], 40)
        self.connection.set_session.assert_called_once_with(readonly=True)
        query = self.cursor.execute.call_args_list[-1].args[0]
        self.assertNotIn('WHERE', query)
        self.assertIn('r.fecha DESC', query)
        self.connection.commit.assert_not_called()
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_empty_history(self):
        self.cursor.fetchall.return_value = []
        self.assertEqual(self.module.consultar_recomendaciones(), {'recomendaciones': [], 'cantidad': 0})

    def test_failure_does_not_expose_connection_details(self):
        self.cursor.execute.side_effect = RuntimeError('private diagnostic')
        with self.assertRaises(HTTPException) as error:
            self.module.consultar_recomendaciones()
        self.assertEqual(error.exception.status_code, 500)
        self.assertNotIn('private', error.exception.detail)
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
