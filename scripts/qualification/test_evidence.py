import copy
import unittest

from evidence import validate_vitest, validate_native, validate_browser, validate_jobs, validate_tap, validate_cargo


class EvidenceTests(unittest.TestCase):
    def test_cargo_requires_four_scenarios_and_no_skips(self):
        text = 'test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 1s\n'
        validate_cargo(text)
        for bad in ['', text.replace('4 passed', '0 passed'), text.replace('0 ignored', '1 ignored'), text.replace('0 filtered', '1 filtered')]:
            with self.assertRaises(ValueError):
                validate_cargo(bad)

    def test_tap_requires_tests_and_rejects_skips(self):
        text = '# tests 1\n# pass 1\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n'
        validate_tap(text)
        for bad in ['', text.replace('# skipped 0', '# skipped 1'), text.replace('# tests 1', '# tests 0'), text + '# tests 1\n']:
            with self.assertRaises(ValueError):
                validate_tap(bad)

    def test_vitest_requires_executed_assertions_and_no_skips(self):
        report = dict(success=True, numTotalTests=1, numPassedTests=1,
                      numFailedTests=0, numPendingTests=0, numTodoTests=0,
                      testResults=[dict(status='passed', assertionResults=[dict(status='passed')])])
        validate_vitest(report)
        for field, value in [('success', False), ('numTotalTests', 0),
                             ('numPendingTests', 1), ('numTodoTests', 1), ('testResults', [])]:
            bad = copy.deepcopy(report)
            bad[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_vitest(bad)
        for status in ['pending', 'skipped', 'todo', 'failed']:
            bad = copy.deepcopy(report)
            bad['testResults'][0]['assertionResults'][0]['status'] = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                validate_vitest(bad)

    def test_native_requires_both_targets_and_no_skips(self):
        summary = dict(totalTestCount=2, passedTests=2, failedTests=0, skippedTests=0,
                       expectedFailures=0, result='Passed',
                       devicesAndConfigurations=[dict(device=dict(modelName='iPhone 17 Pro'))])
        tree = dict(testNodes=[dict(name=name, nodeType=kind, children=[
            dict(name='testExample()', nodeType='Test Case', result='Passed')])
            for name, kind in [('DrivyTests', 'Unit test bundle'), ('DrivyUITests', 'UI test bundle')]])
        validate_native(summary, tree)
        validate_native(summary, tree, 'iPhone')
        with self.assertRaises(ValueError):
            validate_native(summary, tree, 'iPad')
        for field, value in [('totalTestCount', 0), ('skippedTests', 1), ('failedTests', 1)]:
            bad = dict(summary, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_native(bad, tree)
        with self.assertRaises(ValueError):
            validate_native(summary, {'testNodes': tree['testNodes'][:1]})
        with self.assertRaises(ValueError):
            validate_native(summary, {})

    def test_browser_requires_positive_proof(self):
        validate_browser(dict(status='PASSED', checks=['synthetic check']))
        for bad in [{}, dict(status='FAILED', checks=['x']), dict(status='PASSED', checks=[])]:
            with self.assertRaises(ValueError):
                validate_browser(bad)

    def test_every_required_job_must_succeed(self):
        jobs = {name: {'result': 'success'} for name in ['resolve', 'checks', 'browser', 'ios', 'ipa', 'scripts', 'crypto']}
        validate_jobs(jobs)
        for status in ['skipped', 'cancelled', 'failure', None]:
            with self.subTest(status=status), self.assertRaises(ValueError):
                validate_jobs(dict(jobs, ios={'result': status}))
        with self.assertRaises(ValueError):
            validate_jobs({})


if __name__ == '__main__':
    unittest.main()
