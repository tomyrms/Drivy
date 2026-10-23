"""Execute real script tests, rejecting empty suites and skipped tests."""
import json
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[2]
suite = unittest.TestSuite()
for directory, pattern in [('scripts/qualification', 'test_*.py'),
                           ('scripts/ios', 'test_test_selection.py'),
                           ('scripts/ios', 'test_visual_capture.py')]:
    discovered = unittest.TestLoader().discover(str(root / directory), pattern=pattern)
    if discovered.countTestCases() == 0:
        raise SystemExit('Suite de scripts vide : ' + pattern)
    suite.addTests(discovered)
result = unittest.TextTestRunner(verbosity=2).run(suite)
output = root / 'artifacts/qualification'
output.mkdir(parents=True, exist_ok=True)
(output / 'python.json').write_text(json.dumps(dict(tests=result.testsRun,
    failures=len(result.failures), errors=len(result.errors), skipped=len(result.skipped))), encoding='utf-8')
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 and not result.skipped else 1)
