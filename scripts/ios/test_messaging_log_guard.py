#!/usr/bin/env python3
"""Garde statique (#78, MSG-19) : aucun journal système ni sortie console dans le code natif de la messagerie.

Le contrôle est statique : il ne prouve pas ce qui sort d'un appareil, seulement qu'aucune API de journal (os.Logger, os_log,
NSLog, print, dump, debugPrint) n'est appelée dans les dossiers de la messagerie, où passent textes, clés et jetons. Les
diagnostics visibles passent par `MessagingDiagnostics` (codes fixes, testés par MessagingDiagnosticsTests). Aucune donnée réelle.
Lancer : python -m unittest scripts.ios.test_messaging_log_guard
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MESSAGING_DIRS = ['MessagingAPI', 'MessagingCore', 'MessagingUI']
FORBIDDEN = re.compile(r'(?<![A-Za-z0-9_.])(?:print|debugPrint|dump|NSLog|os_log)\s*\(|\bLogger\s*\(|\bimport\s+(?:OSLog|os\.log)\b|\bOSLogStore\b')


def swift_sources() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for name in MESSAGING_DIRS:
        files += sorted((ROOT / 'apps' / 'ios' / 'Drivy' / name).rglob('*.swift'))
    return files


def strip_comments_and_strings(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)


class MessagingLogGuardTests(unittest.TestCase):
    def test_sources_are_found(self):
        files = swift_sources()
        self.assertGreater(len(files), 40, 'les dossiers de la messagerie doivent être lus, sinon la garde ne garde rien')
        self.assertTrue(any(path.name == 'MessagingDiagnostics.swift' or 'Diagnostics' in path.name for path in files))

    def test_no_system_log_or_console_output_in_messaging_sources(self):
        offenders = []
        for path in swift_sources():
            code = strip_comments_and_strings(path.read_text(encoding='utf-8'))
            for number, line in enumerate(code.splitlines(), 1):
                if FORBIDDEN.search(line):
                    offenders.append(f'{path.relative_to(ROOT).as_posix()}:{number}')
        self.assertEqual(offenders, [], 'journal ou console dans le code de la messagerie : ' + ', '.join(offenders))

    def test_detector_catches_each_forbidden_call(self):
        for sample in ['print(text)', 'debugPrint(x)', 'dump(x)', 'NSLog("%@", x)', 'os_log("x")', 'let log = Logger(subsystem: "a")',
                       'import OSLog']:
            self.assertIsNotNone(FORBIDDEN.search(sample), sample)
        for sample in ['let fingerprint = 1', 'Self.fingerprint(for: scope)', 'blueprint(x)', 'sprint(1)']:
            self.assertIsNone(FORBIDDEN.search(sample), sample)


if __name__ == '__main__':
    unittest.main()
