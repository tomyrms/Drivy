"""Require the actual relay XCTest in xcresult exports, without printing payloads."""
import argparse
import json
from pathlib import Path

SUITE = 'MatrixMessagingRelayIntegrationTests'
METHOD = 'testRealRelayExchangeIdempotenceRecoveryAndContextRefusal'


def validate(summary, tree):
    total = summary.get('totalTestCount', 0)
    if (not isinstance(total, int) or total <= 0 or summary.get('passedTests') != total
            or summary.get('result') != 'Passed'
            or any(summary.get(key) != 0 for key in ['failedTests', 'skippedTests', 'expectedFailures'])):
        raise ValueError('Campagne native absente, ignorée ou en échec')

    def walk(node, in_bundle=False, in_suite=False):
        in_bundle = in_bundle or (node.get('nodeType') == 'Unit test bundle'
                                  and node.get('name') in ['DrivyTests', 'DrivyTests.xctest'])
        in_suite = in_suite or (in_bundle and node.get('name') == SUITE)
        if in_bundle and in_suite and node.get('nodeType') == 'Test Case':
            yield node
        for child in node.get('children', []):
            yield from walk(child, in_bundle, in_suite)

    cases = [case for root in tree.get('testNodes', []) for case in walk(root)]
    if (len(cases) != 1 or cases[0].get('name') not in [METHOD, METHOD + '()']
            or cases[0].get('result') != 'Passed'):
        raise ValueError('Scénario relais unique réussi non prouvé')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('summary')
    parser.add_argument('tests')
    args = parser.parse_args()
    try:
        validate(json.loads(Path(args.summary).read_text(encoding='utf-8')),
                 json.loads(Path(args.tests).read_text(encoding='utf-8')))
    except (OSError, ValueError, TypeError, KeyError):
        raise SystemExit('RELAY_EXECUTION_NOT_PROVEN') from None
    print('RELAY_EXECUTION_PASSED: 1 scenario, 0 skipped')
