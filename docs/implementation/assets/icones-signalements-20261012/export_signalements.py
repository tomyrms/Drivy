"""Export des quatre thèmes retenus vers le catalogue Xcode, puis copie web des quinze thèmes.

1. Sélection : `selection.json` porte, par thème, la retenue du premier tour (`retenue`, la plus forte
   note parmi A, B, C — contrôlée ici) et, s'il a tranché, le choix du porteur (`choix_porteur`), qui
   prime sur toute note. Les études D, E, F sont notées mais ne remplacent rien d'elles-mêmes.
2. Catalogue Xcode : même égalisation de taille optique et même `Contents.json` que les onze thèmes
   existants (fonctions de `../icones-signaler-20261012/export.py`, non modifié et non relancé).
3. Copie web : les quinze thèmes — onze relus tels quels dans le catalogue, quatre nouveaux — en
   `apps/web/client/assets/observation-themes/<clé>.svg`, `viewBox` 64 et `fill="currentColor"`.

Usage :
  python export_signalements.py
      exporte selon selection.json (choix du porteur s'il existe, sinon retenue)
  python export_signalements.py --choix indicators=D following-distance=E braking=A lane-change=F
      enregistre le choix du porteur dans selection.json, puis exporte ; un thème non cité garde son état
  python export_signalements.py --choix indicators=         (lettre vide : efface le choix, retour à la retenue)
  python export_signalements.py --essai [--choix …]
      écrit dans ./essai/ au lieu du catalogue et du web, sans toucher à selection.json
"""
from __future__ import annotations

import argparse
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
WEIGHTS = {"reconnaissance": 0.30, "qualite": 0.20, "identite": 0.15, "petite_taille": 0.20, "integration": 0.15}
EXISTING = ["vehicle", "observation", "right-priority", "signage", "give-way", "intersections", "speed",
            "placement", "manoeuvres", "motorway", "anticipation"]
THEMES = EXISTING + list(atelier.ICONS)
FIRST_ROUND = "ABC"


def check(selection):
    """Les notes sont recalculées ; la retenue est la plus forte du premier tour ; l'argument commence
    par sa lettre ; un choix du porteur désigne une étude qui existe."""
    for key, spec in selection.items():
        totals = {}
        for letter, n in spec["notes"].items():
            total = round(sum(n[c] * w for c, w in WEIGHTS.items()), 2)
            if abs(total - n["total"]) > 0.005:
                raise SystemExit(f"{key} {letter} : total {n['total']} ≠ {total} recalculé")
            totals[letter] = total
        best = max((k for k in totals if k in FIRST_ROUND), key=totals.get)
        if spec["retenue"] != best:
            raise SystemExit(f"{key} : retenue {spec['retenue']} mais la plus forte note du premier tour est {best}")
        if not spec["pourquoi"].startswith(f"{best} —"):
            raise SystemExit(f"{key} : l'argument ne correspond pas à la retenue {best}")
        letters = [p["direction"] for p in atelier.ICONS[key]["directions"]]
        if spec.get("choix_porteur") and spec["choix_porteur"] not in letters:
            raise SystemExit(f"{key} : choix du porteur {spec['choix_porteur']} inconnu ({', '.join(letters)})")


def web_svg(catalog_svg: str) -> str:
    """Le SVG du catalogue, pour le web : couleur héritée, pas de taille figée, décoratif (le libellé le nomme)."""
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"[^>]*/>', catalog_svg)
    if len(paths) != 1:
        raise SystemExit("un seul tracé attendu par thème")
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="currentColor" aria-hidden="true">'
            f'<path fill-rule="evenodd" d="{paths[0]}"/></svg>\n')


def apply_choices(selection, pairs):
    for pair in pairs:
        key, _, letter = pair.partition("=")
        if key not in selection:
            raise SystemExit(f"thème inconnu : {key} (attendu : {', '.join(selection)})")
        letter = letter.strip().upper()
        if letter:
            selection[key]["choix_porteur"] = letter
        else:
            selection[key].pop("choix_porteur", None)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--choix", nargs="*", default=[], metavar="clé=LETTRE")
    ap.add_argument("--essai", action="store_true")
    args = ap.parse_args()

    path = HERE / "selection.json"
    selection = json.loads(path.read_text(encoding="utf-8"))
    apply_choices(selection, args.choix)
    check(selection)
    if args.choix and not args.essai:
        path.write_text(json.dumps(selection, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")

    catalog = HERE / "essai" / "Assets.xcassets" if args.essai else CATALOG
    web = HERE / "essai" / "observation-themes" if args.essai else WEB
    final = HERE / "essai" / "retenues" if args.essai else HERE / "retenues"
    for d in (catalog, web, final):
        d.mkdir(parents=True, exist_ok=True)

    report = {}
    for key, spec in atelier.ICONS.items():
        chosen = selection[key].get("choix_porteur")
        pick = chosen or selection[key]["retenue"]
        prop = next(p for p in spec["directions"] if p["direction"] == pick)
        # La finition a été faite sur la retenue du premier tour ; une autre étude sort à son dernier tour.
        finished = bool(spec.get("finition")) and pick == selection[key]["retenue"]
        build = spec["finition"] if finished else prop["tours"][-1]
        geom, scale = base_export.normalize(build(), key)
        title = f"{spec['title']} — {prop['name']}"
        (final / f"{key}.svg").write_text(base.svg(geom, title), encoding="utf-8", newline="\n")
        imageset = catalog / f"Observation-{key}.imageset"
        imageset.mkdir(exist_ok=True)
        for old in imageset.glob("*.svg"):
            old.unlink()
        (imageset / f"{key}.svg").write_text(base.svg(geom, title, size=20), encoding="utf-8", newline="\n")
        (imageset / "Contents.json").write_text(base_export.contents(f"{key}.svg"), encoding="utf-8", newline="\n")
        report[key] = {"direction": pick, "name": prop["name"], "origine": "choix du porteur" if chosen else "note",
                       "finition": finished, "scale": round(scale, 3),
                       "epaisseur_en_place": round(spec["trait"] * scale, 2) if finished and "trait" in spec else None,
                       **base.metrics(geom)}
    for key in THEMES:
        folder = catalog if key in atelier.ICONS else CATALOG
        source = (folder / f"Observation-{key}.imageset" / f"{key}.svg").read_text(encoding="utf-8")
        (web / f"{key}.svg").write_text(web_svg(source), encoding="utf-8", newline="\n")
    if not args.essai:
        (HERE / "retenues.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    for k, v in report.items():
        print(f"{k}: {v['direction']} ({v['origine']}), échelle {v['scale']}, finition {v['finition']}")
    print(f"catalogue : {catalog}")
    print(f"web : {len(THEMES)} thèmes dans {web}")


if __name__ == "__main__":
    main()
