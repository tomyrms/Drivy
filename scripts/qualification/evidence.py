"""Fail-closed acceptance of synthetic CI evidence. Never print report payloads."""
import argparse
import json
import os
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_vitest(report):
    total = report.get('numTotalTests', 0)
    require(isinstance(total, int) and total > 0, 'Aucun test Vitest exécuté')
    require(report.get('success') is True and report.get('numPassedTests') == total,
            'Vitest incomplet ou en échec')
    for key in ['numFailedTests', 'numPendingTests', 'numTodoTests']:
        require(report.get(key) == 0, 'Compteur Vitest absent ou non nul : ' + key)
    suites = report.get('testResults', [])
    require(bool(suites), 'Aucun résultat de suite Vitest')
    count = 0
    for suite in suites:
        assertions = suite.get('assertionResults', [])
        require(suite.get('status') == 'passed' and bool(assertions), 'Suite Vitest vide ou non réussie')
        require(all(item.get('status') == 'passed' for item in assertions), 'Assertion Vitest ignorée ou en échec')
        count += len(assertions)
    require(count == total, 'Nombre de tests Vitest incohérent')


def validate_native(summary, tree, family=None):
    total = summary.get('totalTestCount', 0)
    require(isinstance(total, int) and total > 0, 'Aucun test natif exécuté')
    require(summary.get('passedTests') == total and summary.get('result') == 'Passed', 'Tests natifs incomplets')
    for key in ['failedTests', 'skippedTests', 'expectedFailures']:
        require(summary.get(key) == 0, 'Compteur natif absent ou non nul : ' + key)
    if family:
        devices = summary.get('devicesAndConfigurations', [])
        require(bool(devices) and all(item.get('device', {}).get('modelName', '').startswith(family)
                for item in devices), 'Famille de simulateur non prouvée : ' + family)

    def walk(node):
        yield node
        for child in node.get('children', []):
            yield from walk(child)

    nodes = [node for root in tree.get('testNodes', []) for node in walk(root)]
    for target, kind in [('DrivyTests', 'Unit test bundle'), ('DrivyUITests', 'UI test bundle')]:
        bundles = [node for node in nodes if node.get('nodeType') == kind
                   and node.get('name') in [target, target + '.xctest']]
        require(bool(bundles), 'Cible native absente : ' + target)
        cases = [node for bundle in bundles for node in walk(bundle) if node.get('nodeType') == 'Test Case']
        require(bool(cases) and all(node.get('result') == 'Passed' for node in cases),
                'Cible native vide, ignorée ou en échec : ' + target)


def validate_browser(report):
    require(report.get('status') == 'PASSED' and isinstance(report.get('checks'), list)
            and len(report['checks']) > 0, 'Recette navigateur absente, vide ou en échec')


def validate_jobs(jobs):
    expected = {'resolve', 'checks', 'browser', 'ios', 'ipa', 'scripts', 'crypto'}
    require(set(jobs) == expected, 'Liste des jobs obligatoires incomplète')
    require(all(job.get('result') == 'success' for job in jobs.values()),
            'Job obligatoire ignoré, annulé ou en échec')


def validate_tap(text):
    counts = {}
    for key in ['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo']:
        matches = re.findall(r'^# ' + key + r' (\d+)\s*$', text, re.MULTILINE)
        require(len(matches) == 1, 'Compteur TAP absent ou ambigu : ' + key)
        counts[key] = int(matches[0])
    require(counts['tests'] > 0 and counts['pass'] == counts['tests'], 'TAP vide ou incomplet')
    require(all(counts[key] == 0 for key in ['fail', 'cancelled', 'skipped', 'todo']), 'TAP ignoré ou en échec')


def validate_cargo(text):
    results = re.findall(r'^test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', text, re.MULTILINE)
    require(bool(results), 'Aucun résultat Cargo')
    require(sum(int(row[1]) for row in results) >= 4, 'Scénarios crypto absents ou incomplets')
    require(all(row[0] == 'ok' and all(int(count) == 0 for count in row[2:]) for row in results),
            'Scénario crypto ignoré, filtré ou en échec')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=['vitest', 'native', 'browser', 'jobs', 'tap', 'cargo'])
    parser.add_argument('paths', nargs='*')
    parser.add_argument('--output', help='Résumé Vitest sans messages, valeurs attendues ni journaux')
    parser.add_argument('--device-family', choices=['iPhone', 'iPad'])
    args = parser.parse_args()
    if args.kind == 'jobs':
        validate_jobs(json.loads(os.environ['QUALIFICATION_NEEDS']))
    elif args.kind in ['tap', 'cargo']:
        require(len(args.paths) == 1, 'Preuve de scripts absente')
        {'tap': validate_tap, 'cargo': validate_cargo}[args.kind](Path(args.paths[0]).read_text(encoding='utf-8'))
    else:
        reports = [json.loads(Path(path).read_text(encoding='utf-8')) for path in args.paths]
        require(len(reports) == (2 if args.kind == 'native' else 1), 'Preuves obligatoires absentes')
        if args.output:
            require(args.kind == 'vitest', 'Résumé filtré réservé à Vitest')
            report = reports[0]
            keys = ['success', 'numTotalTests', 'numPassedTests', 'numFailedTests', 'numPendingTests', 'numTodoTests']
            safe = {key: report.get(key) for key in keys}
            safe['testResults'] = [dict(status=suite.get('status'), assertionResults=[
                dict(status=item.get('status')) for item in suite.get('assertionResults', [])])
                for suite in report.get('testResults', [])]
            Path(args.output).write_text(json.dumps(safe, indent=2) + '\n', encoding='utf-8')
        if args.kind == 'native':
            validate_native(*reports, family=args.device_family)
        else:
            {'vitest': validate_vitest, 'browser': validate_browser}[args.kind](*reports)
    print('Preuves automatisées présentes et réussies. Qualification physique distincte.')


if __name__ == '__main__':
    main()
