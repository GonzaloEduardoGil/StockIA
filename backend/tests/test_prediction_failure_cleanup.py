"""La automática libera su único préstamo y permite reintentar tras fallar."""
from datetime import date,timedelta
import unittest
from unittest.mock import MagicMock,patch
from psycopg2 import OperationalError,extensions
from fastapi import HTTPException
from sistema import database
from funciones import predicciones as service


class PredictionFailureCleanupTest(unittest.TestCase):
    def check_failure(self, phase, cleanup_failure=False):
        physical=[]; failed=False; pending_error=False; committed=[]
        sunday=date(2026,10,25)
        def connect():
            raw=MagicMock();raw.closed=False;raw.notices=[];raw.notifies=[]
            raw.get_transaction_status.return_value=extensions.TRANSACTION_STATUS_IDLE
            raw.close.side_effect=lambda:setattr(raw,'closed',True)
            def cursor():
                cur=MagicMock();cur.__enter__.return_value=cur
                def execute(sql,params=()):
                    nonlocal failed,pending_error
                    if sql=='DISCARD ALL':return
                    cur.fetchone.return_value=None
                    if 'pg_try_advisory' in sql:cur.fetchone.return_value=(True,)
                    elif 'SELECT nombre, activo' in sql:
                        if phase=='read' and not failed:
                            failed=pending_error=True
                            if cleanup_failure:
                                raw.rollback.side_effect=OperationalError('rollback de prueba')
                                raw.get_transaction_status.return_value=extensions.TRANSACTION_STATUS_UNKNOWN
                                cur.close.side_effect=RuntimeError('cierre de prueba')
                            raise RuntimeError('error original de lectura')
                        cur.fetchone.return_value=('Cuaderno',True)
                    elif 'SELECT activo FROM PRODUCTO' in sql:cur.fetchone.return_value=(True,)
                    elif 'INSERT INTO "PREDICCION_DEMANDA"' in sql:
                        if phase=='save' and not failed:
                            failed=pending_error=True
                            if cleanup_failure:
                                raw.rollback.side_effect=OperationalError('rollback de prueba')
                                raw.get_transaction_status.return_value=extensions.TRANSACTION_STATUS_UNKNOWN
                                cur.close.side_effect=RuntimeError('cierre de prueba')
                            raise RuntimeError('error original de guardado')
                        cur.fetchone.return_value=(91,)
                    cur.fetchall.return_value=[(sunday-timedelta(days=i),4) for i in range(20,-1,-1)]
                cur.execute.side_effect=execute
                return cur
            raw.cursor.side_effect=cursor
            raw.commit.side_effect=lambda:committed.append(True)
            physical.append(raw)
            return raw
        pool=database.ConnectionPool(connect,max_size=1,wait_seconds=.02)
        self.addCleanup(pool.close)
        loans=[];close_counts={};original_close=database.BorrowedConnection.close
        def acquire():
            loan=pool.acquire();loans.append(loan);return loan
        def close(loan):
            close_counts[id(loan)]=close_counts.get(id(loan),0)+1
            original_close(loan)
        model=MagicMock();model.predict.return_value=[4.]
        model.fit.side_effect=lambda *args:self.assertEqual(pool.stats()['busy'],1)
        with patch.object(service,'obtener_conexion',side_effect=acquire), \
             patch.object(database.BorrowedConnection,'close',close), \
             patch.object(service,'XGBRegressor',return_value=model):
            with self.assertRaises(HTTPException) as caught:
                service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=sunday)
            self.assertTrue(pending_error)
            self.assertEqual(caught.exception.status_code,500)
            detail='lectura' if phase=='read' else 'guardado'
            self.assertEqual(caught.exception.detail,f'No se pudo generar la predicción: error original de {detail}')
            self.assertEqual(pool.stats()['busy'],0)
            self.assertFalse(committed)
            result=service.generar_prediccion(7,service.SolicitudPrediccion(diasPrediccion=7),fecha_historial=sunday)
            self.assertEqual(result['cantidadEstimada'],28)
            self.assertEqual(len(committed),1)
            self.assertEqual(pool.stats()['busy'],0)
            self.assertTrue(all(close_counts.get(id(loan))==1 for loan in loans))
        if cleanup_failure:self.assertTrue(physical[0].closed)

    def test_read_error_with_one_connection_allows_retry(self):self.check_failure('read')
    def test_save_error_with_one_connection_allows_retry(self):self.check_failure('save')
    def test_cleanup_failures_preserve_error_and_return_capacity(self):
        for phase in ['read','save']:
            with self.subTest(phase=phase):self.check_failure(phase,True)
