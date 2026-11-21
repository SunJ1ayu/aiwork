import _no_egress
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bin'))
import _leg_session as session

class NetworkRetry(unittest.TestCase):
    def test_read_recovers_but_is_bounded(self):
        calls = []
        def operation():
            calls.append(1)
            if len(calls) < 3:
                raise session.ReviewError('TLS connection reset')
            return 'review'
        with patch('time.sleep'):
            self.assertEqual(session.network_read(operation), 'review')
            self.assertEqual(len(calls), 3)
            with self.assertRaises(session.ReviewError):
                session.network_read(lambda: (_ for _ in ()).throw(session.ReviewError('EOF')))

    def test_short_episode_does_not_absorb_every_attempt(self):
        # 评审机 2026-11-21 实测（issue #193）：TLS 断线成段出现，一段二十秒上下。
        # 重试只隔 1、2 秒的三次尝试全落在同一段里，腿没启动模型就失败了。
        episode_seconds = 20
        clock = [0.0]
        calls = []

        def operation():
            calls.append(clock[0])
            if clock[0] < episode_seconds:
                raise session.ReviewError('TLS packet decode error')
            return 'review'

        def sleep(delay):
            clock[0] += delay

        with patch('time.sleep', side_effect=sleep):
            self.assertEqual(session.network_read(operation), 'review')
        self.assertGreater(len(calls), 1)

    def test_retry_budget_stays_bounded(self):
        waits = []
        with patch('time.sleep', side_effect=waits.append):
            with self.assertRaises(session.ReviewError):
                session.network_read(lambda: (_ for _ in ()).throw(session.ReviewError('EOF')))
        self.assertEqual(len(waits), session.RETRY_ATTEMPTS - 1)
        for attempt, wait in enumerate(waits):
            span = min(session.RETRY_BACKOFF_CAP, session.RETRY_BACKOFF_BASE * 2 ** attempt)
            self.assertLessEqual(wait, span)
            self.assertGreaterEqual(wait, span / 2)
        self.assertLessEqual(sum(waits), session.RETRY_BACKOFF_CAP * session.RETRY_ATTEMPTS)

if __name__ == '__main__':
    unittest.main()
