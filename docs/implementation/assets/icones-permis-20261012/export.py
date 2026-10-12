"""Export de la famille retenue vers le catalogue Xcode.

Un seul SVG vectoriel par catégorie, en gabarit (`template-rendering-intent`) : la couleur vient de `foregroundStyle`,
donc du jeton clair ou sombre, et le vecteur est conservé (`preserves-vector-representation`) pour 16 à 48 pt et
toutes les densités d'écran. Taille intrinsèque 24 pt : celle d'une icône de menu, où SwiftUI n'affiche que l'image nue.
Centrage optique : un point au-dessus du centre géométrique, comme « Signaler ».

Ne pas retoucher les SVG du catalogue : modifier l'atelier, puis `python atelier.py && python selection.py && python export.py`.
Usage : python export.py   (écrit apps/ios/Drivy/Resources/Assets.xcassets/License-*.imageset)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from shapely import affinity

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import atelier  # noqa: E402

ROOT = HERE.parents[3]
CATALOG = ROOT / "apps/ios/Drivy/Resources/Assets.xcassets"
FINAL = HERE / "retenues"
LIFT = 1.0
SIZE = 24


def contents(filename):
    return json.dumps({
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }, indent=2) + "\n"


def main():
    selection = json.loads((HERE / "selection.json").read_text(encoding="utf-8"))
    FINAL.mkdir(exist_ok=True)
    report = {}
    for key, (title, _, _) in atelier.CATEGORIES.items():
        pick = selection[key]["retenue"]
        geom = affinity.translate(atelier.build(key, pick), 0, -LIFT)
        name = f"Catégorie {key.upper()} — {title}"
        (FINAL / f"{key}.svg").write_text(atelier.svg(geom, name), encoding="utf-8")
        imageset = CATALOG / f"License-{key}.imageset"
        imageset.mkdir(exist_ok=True)
        for old in imageset.glob("*.svg"):
            old.unlink()
        (imageset / f"license-{key}.svg").write_text(atelier.svg(geom, name, size=SIZE), encoding="utf-8")
        (imageset / "Contents.json").write_text(contents(f"license-{key}.svg"), encoding="utf-8")
        report[key] = {"asset": f"License-{key}", "direction": pick, **atelier.metrics(geom)}
    (HERE / "retenues.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    for k, v in report.items():
        print(k, v)


if __name__ == "__main__":
    main()
