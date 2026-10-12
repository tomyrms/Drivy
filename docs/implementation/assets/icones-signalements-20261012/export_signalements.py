"""Export des quatre thèmes retenus vers le catalogue Xcode, puis copie web des quinze thèmes.

1. Sélection : la plus forte note de `selection.json` est retenue ; le script refuse une sélection ou
   un argument qui ne correspond pas aux notes (même contrôle que le 12 octobre).
2. Catalogue Xcode : même égalisation de taille optique et même `Contents.json` que les onze thèmes
   existants (fonctions de `../icones-signaler-20261012/export.py`, non modifié et non relancé).
3. Copie web : les quinze thèmes — onze relus tels quels dans le catalogue, quatre nouveaux — en
   `apps/web/client/assets/observation-themes/<clé>.svg`, `viewBox` 64 et `fill="currentColor"`.

Usage : python export_signalements.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "icones-signaler-20261012"))
import atelier as base  # noqa: E402
import export as base_export  # noqa: E402
import atelier_signalements as atelier  # noqa: E402

ROOT = HERE.parents[3]
CATALOG = ROOT / "apps/ios/Drivy/Resources/Assets.xcassets"
WEB = ROOT / "apps/web/client/assets/observation-themes"
FINAL = HERE / "retenues"
WEIGHTS = {"reconnaissance": 0.30, "qualite": 0.20, "identite": 0.15, "petite_taille": 0.20, "integration": 0.15}
EXISTING = ["vehicle", "observation", "right-priority", "signage", "give-way", "intersections", "speed",
            "placement", "manoeuvres", "motorway", "anticipation"]
THEMES = EXISTING + list(atelier.ICONS)

def check(selection):
    """La note est recalculée ; la retenue est la plus forte ; l'argument commence par sa lettre."""
    for key, spec in selection.items():
        totals = {}
        for letter, n in spec["notes"].items():
            total = round(sum(n[c] * w for c, w in WEIGHTS.items()), 2)
            if abs(total - n["total"]) > 0.005:
                raise SystemExit(f"{key} {letter} : total {n['total']} ≠ {total} recalculé")
            totals[letter] = total
        best = max(totals, key=totals.get)
        if spec["retenue"] != best:
            raise SystemExit(f"{key} : retenue {spec['retenue']} mais la plus forte note est {best}")
        if not spec["pourquoi"].startswith(f"{best} —"):
            raise SystemExit(f"{key} : l'argument ne correspond pas à la retenue {best}")


def web_svg(catalog_svg: str) -> str:
    """Le SVG du catalogue, pour le web : couleur héritée, pas de taille figée, décoratif (le libellé le nomme)."""
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"[^>]*/>', catalog_svg)
    if len(paths) != 1:
        raise SystemExit("un seul tracé attendu par thème")
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="currentColor" aria-hidden="true">'
            f'<path fill-rule="evenodd" d="{paths[0]}"/></svg>\n')


def main():
    selection = json.loads((HERE / "selection.json").read_text(encoding="utf-8"))
    check(selection)
    FINAL.mkdir(exist_ok=True)
    report = {}
    for key, spec in atelier.ICONS.items():
        pick = selection[key]["retenue"]
        prop = next(p for p in spec["directions"] if p["direction"] == pick)
        build = spec.get("finition") or prop["tours"][-1]
        geom, scale = base_export.normalize(build(), key)
        title = f"{spec['title']} — {prop['name']}"
        (FINAL / f"{key}.svg").write_text(base.svg(geom, title), encoding="utf-8", newline="\n")
        imageset = CATALOG / f"Observation-{key}.imageset"
        imageset.mkdir(exist_ok=True)
        for old in imageset.glob("*.svg"):
            old.unlink()
        (imageset / f"{key}.svg").write_text(base.svg(geom, title, size=20), encoding="utf-8", newline="\n")
        (imageset / "Contents.json").write_text(base_export.contents(f"{key}.svg"), encoding="utf-8", newline="\n")
        report[key] = {"direction": pick, "name": prop["name"], "finition": bool(spec.get("finition")),
                       "scale": round(scale, 3), "epaisseur_en_place": round(spec["trait"] * scale, 2) if "trait" in spec else None,
                       **base.metrics(geom)}
    WEB.mkdir(parents=True, exist_ok=True)
    for key in THEMES:
        source = (CATALOG / f"Observation-{key}.imageset" / f"{key}.svg").read_text(encoding="utf-8")
        (WEB / f"{key}.svg").write_text(web_svg(source), encoding="utf-8", newline="\n")
    (HERE / "retenues.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    for k, v in report.items():
        print(k, v)
    print(f"web : {len(THEMES)} thèmes dans {WEB}")


if __name__ == "__main__":
    main()
