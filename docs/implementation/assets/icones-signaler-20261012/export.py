"""Export des propositions retenues vers le catalogue Xcode, avec correction de taille optique.

Une icône large et basse paraît plus petite qu'un triangle de même boîte : chaque glyphe est mis à
l'échelle pour que √(largeur × hauteur) vaille TARGET, sans dépasser MAX de côté, puis centré
optiquement (un point au-dessus du centre géométrique). Les appréciations, glyphes de pastille,
gardent leur dessin plein cadre.

Usage : python export.py   (écrit apps/ios/Drivy/Resources/Assets.xcassets/Observation-*.imageset)
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from shapely import affinity

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import atelier  # noqa: E402

ROOT = HERE.parents[3]
CATALOG = ROOT / "apps/ios/Drivy/Resources/Assets.xcassets"
FINAL = HERE / "retenues"
TARGET = 46.0
MAX = 56.0
LIFT = 1.0
STATUS = {"status-attention", "status-rework", "status-positive"}
# Les aplats pleins paraissent plus grands que les glyphes de trait : on les réduit d'autant.
SOLID = {"marker": 0.86}


def normalize(geom, key):
    primary, secondary = atelier.layers(geom)
    whole = atelier.U(primary, secondary)
    minx, miny, maxx, maxy = whole.bounds
    w, h = maxx - minx, maxy - miny
    if key in STATUS:
        s = 1.0
    else:
        s = min(TARGET * SOLID.get(key, 1.0) / math.sqrt(w * h), MAX / max(w, h))
    origin = ((minx + maxx) / 2, (miny + maxy) / 2)
    dx, dy = 32 - origin[0], 32 - LIFT - origin[1]

    def place(g):
        return None if g is None else affinity.translate(affinity.scale(g, s, s, origin=origin), dx, dy)
    placed = place(primary) if secondary is None else (place(primary), place(secondary))
    return placed, s


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
    for key, spec in atelier.ICONS.items():
        if "-v" in key:
            continue
        # La dernière reprise retenue (« <clé>-vN », sans « ecartee ») remplace les sélections précédentes.
        reprises = [k for k in selection if k.startswith(f"{key}-v") and not selection[k].get("ecartee")]
        source = max(reprises, key=lambda k: int(k.rsplit("-v", 1)[1])) if reprises else key
        pick = selection[source]["retenue"]
        prop = next(p for p in atelier.ICONS[source]["directions"] if p["direction"] == pick)
        geom, scale = normalize(prop["build"](), key)
        title = f"{spec['title']} — {prop['name']}"
        (FINAL / f"{key}.svg").write_text(atelier.svg(geom, title), encoding="utf-8")
        # Dans le catalogue, 20 pt de taille intrinsèque : celle d'une icône de menu. Ailleurs l'image est redimensionnée.
        text = atelier.svg(geom, title, size=20)
        imageset = CATALOG / f"Observation-{key}.imageset"
        imageset.mkdir(exist_ok=True)
        for old in imageset.glob("*.svg"):
            old.unlink()
        (imageset / f"{key}.svg").write_text(text, encoding="utf-8")
        (imageset / "Contents.json").write_text(contents(f"{key}.svg"), encoding="utf-8")
        report[key] = {"source": source, "direction": pick, "scale": round(scale, 3), **atelier.metrics(geom)}
    (HERE / "retenues.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    for k, v in report.items():
        print(k, v)


if __name__ == "__main__":
    main()
