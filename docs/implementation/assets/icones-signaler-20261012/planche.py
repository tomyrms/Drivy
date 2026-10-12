"""Planche comparative : pour chaque icône, l'actuelle puis les cinq propositions, à 64, 28 et 16 px,
en clair et en sombre. Avec `--choix`, la proposition retenue est cerclée et ses notes affichées.

Usage : python planche.py [--choix] [--icones a,b] [-o planche.html]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

CURRENT = {
    "vehicle": "vehicle", "observation": "observation", "right-priority": "right-priority", "signage": "signage",
    "give-way": "give-way", "intersections": "intersections", "speed": "speed", "placement": "placement",
    "manoeuvres": "manoeuvres", "motorway": "motorway", "anticipation": "anticipation", "marker": "marker",
}
SF = {"status-attention": "SF Symbol exclamationmark", "status-rework": "SF Symbol xmark",
      "status-positive": "SF Symbol checkmark"}
DIRS = {"A": "Plan", "B": "Panneau", "C": "Instrument", "D": "Silhouette", "E": "Trace"}


def inline(svg_text: str) -> str:
    s = re.sub(r"<title[^>]*>.*?</title>", "", svg_text, flags=re.S)
    s = re.sub(r'(fill|stroke)="#[0-9A-Fa-f]{6}"', r'\1="currentColor"', s)
    s = re.sub(r'\s(width|height)="64"', "", s, count=2)
    return s.strip()


def current_svg(key):
    if key.endswith(("-v2", "-v3", "-v4", "-v5")):
        # Reprise : la référence est l'icône livrée au tour précédent, archivée.
        tour = "tour1" if key.endswith("-v2") else "tour2"
        f = HERE / "avant" / f"{key[:-3]}-{tour}.svg"
        return inline(f.read_text(encoding="utf-8")) if f.exists() else None
    name = CURRENT.get(key)
    if not name:
        return None
    # Les icônes d'avant la refonte, archivées : le catalogue porte désormais les nouvelles.
    f = HERE / "avant" / f"{name}.svg"
    return inline(f.read_text(encoding="utf-8")) if f.exists() else None


def cell(svg, extra=""):
    return (f'<div class="cell {extra}"><div class="big">{svg}</div>'
            f'<div class="row"><span class="s28">{svg}</span><span class="s16">{svg}</span>'
            f'<span class="dark"><span class="s28">{svg}</span><span class="s16">{svg}</span></span></div></div>')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--choix", action="store_true")
    ap.add_argument("--icones")
    ap.add_argument("-o", default="planche.html")
    a = ap.parse_args()
    data = json.loads((HERE / "propositions.json").read_text(encoding="utf-8"))
    choix = json.loads((HERE / "selection.json").read_text(encoding="utf-8")) if a.choix else {}
    keys = a.icones.split(",") if a.icones else list(data)
    rows = []
    for key in keys:
        spec = data[key]
        cur = current_svg(key)
        cur_html = cell(cur, "current") if cur else f'<div class="cell current sf">{SF.get(key, "")}</div>'
        props = []
        pick = choix.get(key, {})
        for p in spec["proposals"]:
            svg = inline((HERE / "propositions" / key / f"{p['direction']}.svg").read_text(encoding="utf-8"))
            won = pick.get("retenue") == p["direction"]
            score = pick.get("notes", {}).get(p["direction"])
            total = f'<b>{score["total"]:.2f}</b>' if score else ""
            crit = (" · ".join(str(score[k]) for k in ("reconnaissance", "qualite", "identite", "petite_taille", "integration"))
                    if score else "")
            props.append(cell(svg, "won" if won else "") .replace(
                '<div class="big">',
                f'<div class="lab"><span class="dir">{p["direction"]} · {p.get("famille") or DIRS.get(p["direction"], "")}</span>'
                f'<span class="name">{p["name"]}</span>{total}<small>{crit}</small></div><div class="big">', 1))
        why = f'<p class="why">{pick["pourquoi"]}</p>' if pick.get("pourquoi") else ""
        if f"{key}-v2" in choix:
            why += '<p class="why"><b>Remplacée par la reprise du 12 octobre, demandée par le porteur</b> (planche-reprise.png).</p>'
        if pick.get("remplace"):
            why += f'<p class="why">Remplace la sélection du premier tour : {pick["remplace"]}.</p>'
        rows.append(f'<section><h2>{spec["title"]} <code>{key}</code></h2>'
                    f'<div class="grid"><div class="lab"><span class="dir">Actuelle</span></div>{cur_html}{"".join(props)}</div>{why}</section>')
    legend = ("Notes /5 : reconnaissance · qualité graphique · identité Drivy · petite taille · intégration ; "
              "total pondéré 30/20/15/20/15. Cerclée : proposition retenue." if a.choix else "Atelier — études.")
    html = f"""<!doctype html><html lang="fr"><meta charset="utf-8"><title>Icônes Signaler</title>
<style>
:root{{--ink:#18212B;--muted:#536174;--accent:#245BD6;--bg:#F7F8FA;--card:#fff;--line:#D9E0E9;}}
body{{margin:0;padding:24px 28px;background:var(--bg);color:var(--ink);font:13px/1.35 -apple-system,"Segoe UI",system-ui,sans-serif}}
h1{{font-size:20px;margin:0 0 4px}} .legend{{color:var(--muted);margin:0 0 18px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px 12px;margin:0 0 14px}}
h2{{font-size:15px;margin:0 0 10px}} h2 code{{font-weight:400;color:var(--muted);font-size:12px}}
.grid{{display:grid;grid-template-columns:repeat(6,1fr);gap:10px;align-items:start}}
.grid>.lab:first-child{{display:none}}
.cell{{border:1px solid var(--line);border-radius:12px;padding:8px;color:var(--accent);position:relative}}
.cell.current{{color:var(--muted);background:#FBFCFD}} .cell.sf{{display:flex;align-items:center;justify-content:center;min-height:150px;color:var(--muted);font-size:12px}}
.cell.won{{border:2px solid var(--accent);box-shadow:0 0 0 3px #EAF0FE}}
.lab{{display:flex;flex-wrap:wrap;gap:2px 6px;align-items:baseline;color:var(--ink);min-height:30px;font-size:12px}}
.lab .dir{{color:var(--muted)}} .lab .name{{font-weight:600}} .lab b{{margin-left:auto;color:var(--accent)}} .lab small{{width:100%;color:var(--muted)}}
.big svg{{width:96px;height:96px;display:block;margin:4px auto 6px}}
.row{{display:flex;align-items:center;justify-content:space-around;gap:6px}}
.s28 svg{{width:28px;height:28px;display:block}} .s16 svg{{width:16px;height:16px;display:block}}
.dark{{display:flex;gap:8px;align-items:center;background:#19222E;color:#91B5FF;border-radius:8px;padding:5px 7px}}
.why{{margin:10px 2px 0;color:var(--ink);max-width:1100px}}
</style>
<h1>« Signaler » — cinq propositions par icône</h1><p class="legend">{legend}</p>
{''.join(rows)}
</html>"""
    (HERE / a.o).write_text(html, encoding="utf-8")
    print(HERE / a.o)


if __name__ == "__main__":
    main()
