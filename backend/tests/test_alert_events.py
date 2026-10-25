import asyncio
import importlib.util
from pathlib import Path
import threading
import unittest
from unittest.mock import MagicMock

spec = importlib.util.spec_from_file_location('alert_events_under_test', Path(__file__).resolve().parents[1] / 'modules' / 'alert_events.py')
events_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(events_module)


class QuietEvents(events_module.AlertEvents):
    async def _listen(self):
        await asyncio.Future()


class AlertObserverTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events = QuietEvents(lambda: None)

    async def asyncTearDown(self):
        await self.events.close()

    async def test_observers_receive_change_bursts_are_coalesced_and_unsubscribe(self):
        first = self.events.subscribe()
        second = self.events.subscribe()
        task = self.events.task
        self.events.notify()
        self.events.notify()
        self.assertEqual(first.qsize(), 1)
        self.assertEqual(second.qsize(), 1)
        self.assertIs(self.events.task, task)
        await first.get()
        self.events.unsubscribe(second)
        await second.get()
        self.events.notify()
        self.assertEqual(first.qsize(), 1)
        self.assertTrue(second.empty())

    async def test_stream_resyncs_on_connection_and_unsubscribes_on_close(self):
        stream = events_module.alert_stream(self.events, 'token', lambda _: None)
        self.assertIn('event: actualizar', await anext(stream))
        self.events.notify()
        self.assertIn('event: actualizar', await anext(stream))
        await stream.aclose()
        self.assertFalse(self.events.observers)

    async def test_revoked_session_and_removed_stock_role_stop_stream(self):
        for user in (None, {'rol': 'Vendedor'}):
            stream = events_module.alert_stream(self.events, 'token', lambda _: user, check_seconds=0)
            await anext(stream)
            self.assertIn('event: sesion_expirada', await anext(stream))
            with self.assertRaises(StopAsyncIteration):
                await anext(stream)
            self.assertFalse(self.events.observers)

    async def test_database_auth_failure_requests_reconnect_without_leaking_error(self):
        def unavailable(_):
            raise RuntimeError('private-db-detail')
        stream = events_module.alert_stream(self.events, 'token', unavailable, check_seconds=0)
        await anext(stream)
        frame = await anext(stream)
        self.assertIn('event: reconectar', frame)
        self.assertNotIn('private', frame)
        await stream.aclose()

    async def test_publisher_uses_existing_transaction_and_identical_payload(self):
        cursor = MagicMock()
        events_module.publish_alert_change(cursor)
        events_module.publish_alert_change(cursor)
        self.assertEqual(cursor.execute.call_count, 2)
        self.assertEqual(cursor.execute.call_args_list[0], cursor.execute.call_args_list[1])
        self.assertIn('pg_notify', cursor.execute.call_args.args[0])
        cursor.connection.commit.assert_not_called()

    async def test_stop_during_connection_open_closes_success_and_handles_failure(self):
        for fails in (False, True):
            entered, released = threading.Event(), threading.Event()
            connection = MagicMock()

            def connect():
                entered.set()
                released.wait(timeout=2)
                if fails:
                    raise RuntimeError('test-only connection failure')
                return connection

            events = events_module.AlertEvents(connect)
            events.subscribe()
            self.assertTrue(await asyncio.to_thread(entered.wait, 2))
            closing = asyncio.create_task(events.close())
            await asyncio.sleep(0)
            released.set()
            await asyncio.wait_for(closing, timeout=3)
            self.assertIsNone(events.task)
            if not fails:
                connection.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
