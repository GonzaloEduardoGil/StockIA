from contextlib import contextmanager
from datetime import date, timedelta
import unittest
from unittest.mock import MagicMock, patch
from funciones import predicciones as service


class PredictionValidityTest(unittest.TestCase):
    def test_original_horizons_inclusive_and_year_change(self):
        for n in [1, 7, 15, 30]:
            self.assertEqual(service.fechas_periodo(date(2026,12,31),f'Próximos {n} días'),
                             (date(2027,1,1),date(2026,12,31)+timedelta(days=n)))
        self.assertEqual(service.fechas_periodo(date(2026,10,30),'Semanal: 2026-10-26 a 2026-11-01'),
                         (date(2026,10,26),date(2026,11,1)))

    def test_invalid_horizons_do_not_invent_dates(self):
        for text in [None,'QA','Próximos 0 días','Próximos 31 días','Semanal: 2026-02-31 a 2026-03-04',
                     'Semanal: 2026-11-05 a 2026-11-01']:
            self.assertIsNone(service.fechas_periodo(date(2026,10,30),text))

    def test_expiration_is_inclusive_and_replaced_never_reactivates(self):
        with patch.object(service,'business_today',return_value=date(2026,10,30)):
            self.assertTrue(service.datos_vigencia(date(2026,10,29),'Próximos 1 días')['vigente'])
            self.assertFalse(service.datos_vigencia(date(2026,10,28),'Próximos 1 días')['vigente'])
            self.assertFalse(service.datos_vigencia(date(2026,10,29),'Próximos 30 días',actual=False)['vigente'])

    def test_worker_skips_active_and_midweek_expiry_until_next_sunday(self):
        cursor=MagicMock()
        cursor.fetchall.return_value=[
            (1,date(2026,10,25),'Próximos 30 días'),
            (2,date(2026,10,25),'Próximos 3 días'),  # Vence miércoles.
            (3,date(2026,10,18),'Próximos 7 días'),
            (4,None,None),
        ]
        @contextmanager
        def transaction():yield cursor
        with patch.object(service,'transaction',transaction),patch.object(service,'generar_prediccion') as generate:
            service.weekly_batch(today=date(2026,10,30))
            self.assertEqual([c.args[0] for c in generate.call_args_list],[3,4])
            generate.reset_mock()
            service.weekly_batch(today=date(2026,11,2))
            self.assertEqual([c.args[0] for c in generate.call_args_list],[2,3,4])

    def test_locked_check_uses_latest_horizon_and_returns_connection(self):
        conn=MagicMock();cursor=conn.cursor.return_value
        cursor.fetchone.side_effect=[(True,),(date(2026,10,25),'Próximos 3 días')]
        with patch.object(service,'obtener_conexion',return_value=conn),patch.object(service,'XGBRegressor') as model:
            result=service.generar_prediccion(2,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=date(2026,10,25))
        self.assertIsNone(result);model.assert_not_called();conn.close.assert_called_once()
        self.assertIn('LIMIT 1',cursor.execute.call_args.args[0])
