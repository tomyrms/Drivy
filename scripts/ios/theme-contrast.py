#!/usr/bin/env python3
"""Contrôle de la palette native : valeurs claires figées et contrastes WCAG 2 du sombre Soft Charcoal.

Usage : python3 scripts/ios/theme-contrast.py [--json sortie.json]
Lit apps/ios/Drivy/UI/DrivyTheme.swift ; échoue si une valeur claire s'écarte de la référence
ou si un couple déclaré passe sous son seuil. Un calcul de palette ne qualifie pas le rendu réel.
"""
import hashlib, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'apps/ios/Drivy/UI/DrivyTheme.swift'

# Thème clair approuvé (tokens 3.8 + rail). Les tokens ajoutés reprennent la valeur du token qu'ils précisent.
LIGHT = dict(canvas='F7F8FA', surface='FFFFFF', surfaceCard='F7F8FA', surfaceRaised='FFFFFF', surfaceMuted='EEF2F7',
             text='18212B', muted='536174', textTertiary='536174', accent='245BD6', accentFill='245BD6',
             accentPressed='1947AD', onAccent='FFFFFF', accentSoft='EAF0FE', success='17633D', successSurface='E9F5EE',
             warning='7A4D00', warningSurface='FFF3D6', danger='B02B37', dangerSurface='FDECEF', border='D9E0E9',
             controlBorder='78869A', rail='C3CDD9', disabledText='5D6A7C', disabledSurface='E8EDF3',
             route='245BD6', routeHalo='FFFFFF', shadow='18212B')

TEXT, UI = 4.5, 3.0
# (premier plan, fond, seuil). Texte courant 4,5:1 ; élément d'interface non textuel 3:1 (WCAG 1.4.11).
PAIRS = [(fg, bg, TEXT) for bg in ('canvas', 'surface', 'surfaceCard', 'surfaceRaised', 'surfaceMuted')
         for fg in ('text', 'muted', 'accent', 'success', 'warning', 'danger')]
PAIRS += [('text', 'accentSoft', TEXT), ('muted', 'accentSoft', TEXT), ('accent', 'accentSoft', TEXT),
          ('success', 'successSurface', TEXT), ('warning', 'warningSurface', TEXT), ('danger', 'dangerSurface', TEXT),
          ('onAccent', 'accentFill', TEXT), ('onAccent', 'accentPressed', TEXT),
          ('accentFill', 'canvas', UI), ('accentFill', 'surfaceCard', UI),
          ('controlBorder', 'canvas', UI), ('controlBorder', 'surfaceCard', UI), ('controlBorder', 'surfaceMuted', UI),
          ('textTertiary', 'canvas', UI), ('textTertiary', 'surfaceCard', UI),
          ('route', 'routeHalo', UI), ('accent', 'surfaceRaised', UI)]
# Le thème clair historique laisse passer ces couples sous le seuil ; ils sont relevés, pas modifiés.
LIGHT_KNOWN = {('muted', 'surfaceMuted'), ('accent', 'surfaceMuted'), ('success', 'surfaceMuted'), ('warning', 'surfaceMuted'),
               ('danger', 'surfaceMuted'), ('controlBorder', 'surfaceMuted'), ('controlBorder', 'surfaceCard'), ('controlBorder', 'canvas')}


def luminance(value):
    channels = [int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def parse(text):
    tokens = {}
    pattern = re.compile(r'static let (\w+) = adaptive\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})'
                         r'(?:, elevated: 0x([0-9A-Fa-f]{6}))?(?:, darkHighContrast: 0x([0-9A-Fa-f]{6}))?\)')
    for name, light, dark, elevated, contrast in pattern.findall(text):
        tokens[name] = dict(light=light.upper(), dark=dark.upper(), elevated=(elevated or dark).upper(),
                            highContrast=(contrast or dark).upper())
    return tokens


def main():
    text = SOURCE.read_text(encoding='utf-8')
    tokens = parse(text)
    failures = []
    for name, expected in LIGHT.items():
        actual = tokens.get(name, {}).get('light')
        if actual != expected:
            failures.append(f'clair modifié : {name} = {actual}, attendu {expected}')
    for name in tokens:
        if name not in LIGHT:
            failures.append(f'token sans référence claire : {name}')
    pairs = []
    for mode in ('light', 'dark', 'elevated', 'highContrast'):
        for fg, bg, threshold in PAIRS:
            value = ratio(tokens[fg][mode], tokens[bg][mode])
            known = mode == 'light' and (fg, bg) in LIGHT_KNOWN
            passes = value >= threshold
            pairs.append(dict(mode=mode, foregroundToken=fg, backgroundToken=bg, foreground='#' + tokens[fg][mode],
                              background='#' + tokens[bg][mode], ratio=round(value, 2), referenceThreshold=threshold,
                              passes=passes, knownLightException=known))
            if not passes and not known:
                failures.append(f'{mode} : {fg} sur {bg} = {value:.2f} < {threshold}')
    steps = {mode: dict(cardOverPage=round(ratio(tokens['surfaceCard'][mode], tokens['canvas'][mode]), 2),
                        interactiveOverCard=round(ratio(tokens['surfaceMuted'][mode], tokens['surfaceCard'][mode]), 2))
             for mode in ('dark', 'elevated')}
    report = dict(source='apps/ios/Drivy/UI/DrivyTheme.swift', sourceSHA256=hashlib.sha256(text.encode('utf-8')).hexdigest(),
                  method='WCAG 2 sRGB relative luminance, ratio (Lmax+0.05)/(Lmin+0.05)', status='declared_source_only',
                  renderedPixelsVerified=False, lightValuesUnchanged=not any(f.startswith('clair') for f in failures),
                  surfaceSteps=steps, tokens=tokens, pairs=pairs, failures=failures)
    if '--json' in sys.argv:
        pathlib.Path(sys.argv[sys.argv.index('--json') + 1]).write_text(
            json.dumps(report, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    dark = [p for p in pairs if p['mode'] != 'light']
    print(f"{len(tokens)} tokens ; {len(pairs)} couples ; sombre {sum(p['passes'] for p in dark)}/{len(dark)} ; "
          f"clair inchangé : {report['lightValuesUnchanged']}")
    for failure in failures:
        print('ÉCHEC', failure)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
