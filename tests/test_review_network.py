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

if __name__ == '__main__':
    unittest.main()
