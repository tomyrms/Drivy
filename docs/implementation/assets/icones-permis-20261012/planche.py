"""Planche comparative : pour chaque catégorie, les trois propositions à 64, 24, 20 et 16 pt, en clair et en sombre
(Soft Charcoal). Avec `--choix`, la retenue est cerclée et les notes pondérées sont affichées.

Usage : python planche.py [--choix] [--categories a,b] [-o planche.html]
        python planche.py --finale -o planche-finale.html   (la famille retenue seule, catalogue exporté)
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
DIRS = {"A": "Natif", "B": "Signature", "C": "Géométrique"}
ORDER = ["a1", "a", "m", "b", "b1", "be", "c1", "c", "c1e", "ce", "d1", "d", "d1e", "de", "f", "g"]
FAMILIES = [("Motocycles et cyclomoteurs", ["a", "a1", "m"]), ("Voitures et véhicules légers", ["b", "b1", "be"]),
            ("Véhicules lourds", ["c", "c1", "ce", "c1e"]), ("Transport de personnes", ["d", "d1", "de", "d1e"]),
            ("Catégories spéciales", ["f", "g"])]
CSS = """
body{margin:0;font:13px/1.35 -apple-system,'SF Pro Text','Segoe UI',sans-serif;background:#F7F8FA;color:#18212B}
h1{font-size:20px;margin:24px 24px 4px}p.lead{margin:0 24px 16px;color:#536174}
h2{font-size:15px;margin:22px 24px 8px;color:#536174;font-weight:600}
.cat{display:grid;grid-template-columns:72px repeat(3,1fr);gap:10px;margin:0 24px 10px;align-items:stretch}
.code{font:700 22px/1 -apple-system,'SF Pro Display','Segoe UI',sans-serif;display:flex;flex-direction:column;justify-content:center}
.code small{font:400 11px/1.25 -apple-system,'Segoe UI',sans-serif;color:#536174;margin-top:4px}
.cell{background:#fff;border:1px solid #D9E0E9;border-radius:14px;padding:10px 12px;display:flex;gap:12px;align-items:center;position:relative}
.cell.pick{outline:3px solid #245BD6;outline-offset:-2px}
.big{width:64px;height:64px;color:#245BD6;flex:none}.big svg{width:64px;height:64px}
.sizes{display:flex;gap:10px;align-items:center}
.l,.d{display:flex;gap:8px;align-items:center;padding:6px 8px;border-radius:9px}
.l{color:#18212B}.d{background:#17191C;color:#F4F5F6}
.s24 svg{width:24px;height:24px;display:block}.s20 svg{width:20px;height:20px;display:block}.s16 svg{width:16px;height:16px;display:block}
.acc{color:#245BD6}.d .acc{color:#86ABF8}
.tag{position:absolute;top:6px;right:10px;font-size:10px;color:#536174;text-transform:uppercase;letter-spacing:.04em}
.score{font-size:11px;color:#536174;margin-top:4px}
.meta{display:flex;flex-direction:column}
"""


def inline(text: str) -> str:
    s = re.sub(r"<title[^>]*>.*?</title>", "", text, flags=re.S)
    s = re.sub(r'fill="#[0-9A-Fa-f]{6}"', 'fill="currentColor"', s)
    return re.sub(r'\s(width|height)="\d+"', "", s, count=2).strip()


def sizes(svg):
    return (f'<div class="sizes"><div class="l"><span class="s24 acc">{svg}</span><span class="s20">{svg}</span>'
            f'<span class="s16">{svg}</span></div><div class="d"><span class="s24 acc">{svg}</span>'
            f'<span class="s20">{svg}</span><span class="s16">{svg}</span></div></div>')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--choix", action="store_true")
    ap.add_argument("--finale", action="store_true")
    ap.add_argument("--categories")
    ap.add_argument("-o", default="planche.html")
    a = ap.parse_args()
    data = json.loads((HERE / "propositions.json").read_text(encoding="utf-8"))
    sel = json.loads((HERE / "selection.json").read_text(encoding="utf-8")) if (a.choix or a.finale) else {}
    keys = a.categories.split(",") if a.categories else None
    out = [f"<!doctype html><meta charset=utf-8><title>Icônes de permis</title><style>{CSS}</style>"]
    if a.finale:
        out.append("<h1>Catégories de permis — famille retenue</h1>"
                   "<p class=lead>Catalogue exporté (License-*), 64 pt puis 24, 20 et 16 pt ; clair et Soft Charcoal.</p>")
    else:
        out.append("<h1>Catégories de permis — trois propositions par catégorie</h1>"
                   "<p class=lead>A Natif · B Signature · C Géométrique. 64 pt, puis 24 (accent), 20 et 16 pt (encre), "
                   "en clair et en sombre.</p>")
    for family, members in FAMILIES:
        members = [k for k in members if keys is None or k in keys]
        if not members:
            continue
        out.append(f"<h2>{family}</h2>")
        for k in members:
            info = data[k]
            out.append(f'<div class="cat"><div class="code">{info["code"]}<small>{info["title"]}</small></div>')
            if a.finale:
                svg = inline((HERE / "retenues" / f"{k}.svg").read_text(encoding="utf-8"))
                out.append(f'<div class="cell" style="grid-column:span 3"><div class="big">{svg}</div>{sizes(svg)}'
                           f'<div class="meta"><div class="score">{sel.get(k, {}).get("pourquoi", "")}</div></div></div></div>')
                continue
            for p in info["proposals"]:
                d = p["direction"]
                svg = inline((HERE / "propositions" / k / f"{d}.svg").read_text(encoding="utf-8"))
                pick = sel.get(k, {}).get("retenue") == d
                note = ""
                if a.choix and k in sel:
                    n = sel[k]["notes"][d]
                    note = f'<div class="score">{n["total"]:.2f} / 5</div>'
                out.append(f'<div class="cell{" pick" if pick else ""}"><span class="tag">{d} · {DIRS[d]}</span>'
                           f'<div class="big">{svg}</div><div class="meta">{sizes(svg)}{note}</div></div>')
            out.append("</div>")
    (HERE / a.o).write_text("\n".join(out), encoding="utf-8")
    print(HERE / a.o)


if __name__ == "__main__":
    main()
