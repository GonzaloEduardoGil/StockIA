import asyncio
from contextlib import contextmanager
from datetime import date, timedelta
import threading
import unittest
from unittest.mock import MagicMock, patch

import numpy as np
from fastapi import HTTPException
from funciones import predicciones as service
from funciones import predicciones as schedule


class PredictionGenerationTest(unittest.TestCase):
    today=date(2026,10,30)
    sunday=date(2026,10,25)

    def connection(self, product=('Cuaderno',True), rows=None):
        connection=MagicMock(); cursor=connection.cursor.return_value
        cursor.fetchone.side_effect=[(True,),None,product,(True,),(91,)]
        cursor.fetchall.return_value=rows if rows is not None else [
            (self.sunday-timedelta(days=i),4) for i in range(20,-1,-1)]
        return connection,cursor

    def test_original_calculation_parameters_recursion_rounding_and_week_marker(self):
        conn,cursor=self.connection()
        model=MagicMock()
        model.predict.side_effect=[np.array([n]) for n in [-2,1.234,2.345,3,4,5,6]]
        with patch.object(service,'business_today',return_value=self.today), \
             patch.object(service,'obtener_conexion',return_value=conn) as acquire, \
             patch.object(service,'XGBRegressor',return_value=model) as factory:
            result=service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday)
        acquire.assert_called_once()
        factory.assert_called_once_with(objective='reg:squarederror',n_estimators=150,max_depth=3,
            learning_rate=0.05,subsample=0.8,colsample_bytree=0.8,random_state=42,n_jobs=1)
        self.assertEqual(model.fit.call_args.args[0].index.max().date(),self.sunday)
        self.assertEqual(model.predict.call_count,7)
        self.assertEqual(model.predict.call_args_list[1].args[0].iloc[0]['venta_dia_anterior'],0)
        self.assertEqual(model.predict.call_args_list[2].args[0].iloc[0]['venta_dia_anterior'],1.234)
        self.assertEqual(result['prediccionesDiarias'],[0,1.23,2.35,3,4,5,6])
        self.assertEqual(result['cantidadEstimada'],22)
        self.assertEqual(result['periodoPrediccion'],'Semanal: 2026-10-26 a 2026-11-01')
        self.assertEqual(result['mensaje'],'Predicción generada con éxito.')
        sql='\n'.join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertNotIn('CREATE ',sql)
        self.assertIn('pg_try_advisory_xact_lock',sql)
        self.assertIn('v.fecha <= %s',sql)
        self.assertIn('CURRENT_DATE',sql)
        conn.commit.assert_called_once();conn.close.assert_called_once()

    def test_actual_model_can_generate_seven_days_from_closed_sunday(self):
        conn,_=self.connection()
        with patch.object(service,'obtener_conexion',return_value=conn):
            result=service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday)
        self.assertEqual(result['prediccionesDiarias'],[4]*7)

    def test_missing_sales_on_sunday_are_zero_filled(self):
        conn,_=self.connection(rows=[(self.sunday-timedelta(days=i),4) for i in range(20,0,-1)])
        model=MagicMock();model.predict.return_value=np.array([2])
        with patch.object(service,'obtener_conexion',return_value=conn),patch.object(service,'XGBRegressor',return_value=model):
            service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday)
        self.assertEqual(model.fit.call_args.args[1].iloc[-1],0)

    def test_occupied_product_or_completed_week_does_not_train(self):
        for answers in [[(False,)],[(True,),(1,)]]:
            conn,cursor=self.connection();cursor.fetchone.side_effect=answers
            with patch.object(service,'obtener_conexion',return_value=conn),patch.object(service,'XGBRegressor') as model:
                self.assertIsNone(service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday))
            conn.commit.assert_not_called();conn.close.assert_called_once();model.assert_not_called()

    def test_product_and_history_errors_remain_original(self):
        for product,rows,status in [(None,[],404),(('Cuaderno',False),[],409),(('Cuaderno',True),[],422)]:
            conn,_=self.connection(product,rows)
            with self.subTest(status=status),patch.object(service,'obtener_conexion',return_value=conn):
                with self.assertRaises(HTTPException) as caught:
                    service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday)
                self.assertEqual(caught.exception.status_code,status)
                conn.rollback.assert_called_once();conn.close.assert_called_once()

    def test_unexpected_error_and_failed_cleanup_preserve_original_error(self):
        conn,cursor=self.connection()
        cursor.execute.side_effect=RuntimeError('error original')
        cursor.close.side_effect=RuntimeError('cierre')
        conn.rollback.side_effect=RuntimeError('rollback')
        with patch.object(service,'obtener_conexion',return_value=conn):
            with self.assertRaises(HTTPException) as caught:
                service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=self.sunday)
        self.assertEqual(caught.exception.status_code,500)
        self.assertEqual(caught.exception.detail,'No se pudo generar la predicción: error original')
        conn.close.assert_called_once()

    def test_weekly_invalid_cutoff_and_length_are_rejected(self):
        for day,days in [(self.today,7),(self.sunday,3)]:
            with patch.object(service,'obtener_conexion') as acquire:
                with self.assertRaises(HTTPException):
                    service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=days),fecha_historial=day)
                acquire.assert_not_called()

    def test_worker_keeps_closed_sunday_on_recovery_and_year_change(self):
        cursor=MagicMock();cursor.fetchall.return_value=[(7,),(8,)]
        @contextmanager
        def transaction():yield cursor
        for today in [date(2026,10,26),date(2026,10,29),date(2026,11,1),date(2027,1,1)]:
            with self.subTest(today=today),patch.object(schedule,'transaction',transaction), \
                 patch.object(schedule,'generar_prediccion',side_effect=[HTTPException(422,'sin datos'),{}]) as generate:
                schedule.weekly_batch(today=today)
            sunday=today-timedelta(days=today.weekday()+1)
            self.assertEqual(generate.call_count,2)
            self.assertEqual(generate.call_args.args[0],8)
            self.assertEqual(generate.call_args.args[1].diasPrediccion,7)
            self.assertEqual(generate.call_args.kwargs,{'fecha_historial':sunday})
            self.assertEqual(cursor.execute.call_args.args[1],(service.periodo_semanal(sunday),))

    def test_manual_original_1_14_30_uses_today_and_exactly_n_predictions(self):
        import main
        for days in [1,14,30]:
            conn=MagicMock();cursor=conn.cursor.return_value
            cursor.fetchone.side_effect=[(True,),('Cuaderno',True),(True,),(91,)]
            cursor.fetchall.return_value=[(self.today-timedelta(days=i),4) for i in range(20,-1,-1)]
            model=MagicMock();model.predict.return_value=np.array([4])
            with self.subTest(days=days),patch.object(service,'business_today',return_value=self.today), \
                 patch.object(service,'obtener_conexion',return_value=conn), \
                 patch.object(service,'XGBRegressor',return_value=model):
                result=main.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=days))
            self.assertEqual(result['periodoPrediccion'],f'Próximos {days} días')
            self.assertEqual(result['cantidadEstimada'],4*days)
            self.assertEqual(len(result['prediccionesDiarias']),days)
            self.assertEqual(model.predict.call_count,days)
            self.assertEqual(model.fit.call_args.args[0].index.max().date(),self.today)
            history=next(c for c in cursor.execute.call_args_list if 'SUM(dv.cantidad)' in c.args[0])
            self.assertEqual(history.args[1],(7,self.today))
            self.assertFalse(any('SELECT 1 FROM "PREDICCION_DEMANDA"' in c.args[0] for c in cursor.execute.call_args_list))
            conn.commit.assert_called_once();conn.close.assert_called_once()

    def test_manual_occupied_product_returns_409_without_training(self):
        conn=MagicMock();conn.cursor.return_value.fetchone.return_value=(False,)
        with patch.object(service,'obtener_conexion',return_value=conn),patch.object(service,'XGBRegressor') as model:
            with self.assertRaises(HTTPException) as caught:
                service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=14))
            self.assertEqual(caught.exception.status_code,409)
            model.assert_not_called();conn.close.assert_called_once()

    def test_manual_original_http_contract_and_stock_permissions_are_recovered(self):
        from fastapi.testclient import TestClient
        import main
        from acceso import autenticacion as security
        client=TestClient(main.app);self.addCleanup(client.close)
        self.assertIn('/predicciones/{id_producto}/generar',main.app.openapi()['paths'])
        headers={'Authorization':'Bearer '+'A'*43}
        for role in ['Administrador','Encargado de stock']:
            with patch.object(security,'resolve_session',return_value={'idUsuario':1,'rol':role}), \
                 patch.object(service,'generar_prediccion',return_value={'ok':True}) as generate:
                for days in range(1,31):
                    self.assertEqual(client.post('/predicciones/7/generar',json={'diasPrediccion':days},headers=headers).status_code,200)
                    self.assertEqual(generate.call_args.args[1].diasPrediccion,days)
                generate.reset_mock()
                for body in [{},{'diasPrediccion':0},{'diasPrediccion':31},{'diasPrediccion':1.5}]:
                    self.assertEqual(client.post('/predicciones/7/generar',json=body,headers=headers).status_code,422)
                generate.assert_not_called()
        with patch.object(security,'resolve_session',return_value={'idUsuario':1,'rol':'Vendedor'}), \
             patch.object(service,'generar_prediccion') as generate:
            self.assertEqual(client.post('/predicciones/7/generar',json={'diasPrediccion':7},headers=headers).status_code,403)
            generate.assert_not_called()
        self.assertEqual(client.post('/predicciones/7/generar',json={'diasPrediccion':7}).status_code,401)


class ScheduleLifecycleTest(unittest.IsolatedAsyncioTestCase):
    async def test_shutdown_waits_for_the_product_in_progress(self):
        started, release = threading.Event(), threading.Event()
        runner = schedule.PredictionSchedule()

        def batch(**kwargs):
            started.set()
            release.wait(timeout=3)

        with patch.object(schedule, 'weekly_batch', side_effect=batch):
            runner.task = asyncio.create_task(runner.run())
            try:
                for _ in range(100):
                    if started.is_set():
                        break
                    await asyncio.sleep(.01)
                self.assertTrue(started.is_set())
                closing = asyncio.create_task(runner.close())
                await asyncio.sleep(.05)
                self.assertFalse(closing.done())
                release.set()
                await asyncio.wait_for(closing, timeout=1)
            finally:
                release.set()
                await runner.close()

    async def test_shutdown_wakes_idle_scheduler_without_waiting_poll_interval(self):
        runner = schedule.PredictionSchedule()
        with patch.object(schedule, 'weekly_batch'):
            runner.task = asyncio.create_task(runner.run())
            await asyncio.sleep(.05)
            await asyncio.wait_for(runner.close(), timeout=1)
        self.assertTrue(runner.task.done())
