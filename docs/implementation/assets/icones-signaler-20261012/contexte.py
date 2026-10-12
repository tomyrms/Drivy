"""Maquette de contexte : la grille « Signaler » et les repères de carte, en clair et en sombre,
avec les couleurs de DrivyTheme. Sert à juger la famille retenue en situation, pas à remplacer
les captures du simulateur.

Usage : python contexte.py -o contexte.html
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

THEMES = [("vehicle", "Maîtrise du véhicule"), ("observation", "Observation et contrôles"),
          ("right-priority", "Priorité à droite"), ("signage", "Signalisation"), ("give-way", "Céder le passage"),
          ("intersections", "Intersections et giratoires"), ("speed", "Vitesse"),
          ("placement", "Placement sur la chaussée"), ("manoeuvres", "Manœuvres"), ("motorway", "Autoroute"),
          ("anticipation", "Anticipation")]
STATUS = [("status-rework", "À retravailler", "danger"), ("status-attention", "Attention", "warning"),
          ("status-positive", "Point positif", "success")]

PALETTE = {
    "light": dict(page="#F7F8FA", surface="#FFFFFF", raised="#FFFFFF", text="#18212B", muted="#536174",
                  accent="#245BD6", soft="#EAF0FE", border="#D9E0E9", danger="#B02B37", warning="#7A4D00",
                  success="#17633D", neutral="#536174", halo="#FFFFFF", map="#EEF1F4", road="#FFFFFF", route="#245BD6"),
    "dark": dict(page="#10151C", surface="#1E2125", raised="#272A2E", text="#F4F5F6", muted="#A1A5AD",
                 accent="#86ABF8", soft="#2F3B54", border="#3A3F46", danger="#FF9DA3", warning="#E5BE7A",
                 success="#7CCFA0", neutral="#A1A5AD", halo="#17191C", map="#1C2026", road="#2C3138", route="#4D80EB"),
}


def glyph(key):
    s = (HERE / "retenues" / f"{key}.svg").read_text(encoding="utf-8")
    s = re.sub(r"<title[^>]*>.*?</title>", "", s, flags=re.S)
    s = re.sub(r'fill="#[0-9A-Fa-f]{6}"', 'fill="currentColor"', s)
    return re.sub(r'\s(width|height)="64"', "", s, count=2)


def marker_html(p, key, tone, selected=False, badge=True, glyph_color=None):
    size = 44 if selected else 32
    g = 26 if selected else 18
    color = p[tone]
    ring = p["accent"] if selected else color
    b = ""
    if badge and tone != "neutral":
        sk = {"danger": "status-rework", "warning": "status-attention", "success": "status-positive"}[tone]
        bs = 18 if selected else 16
        b = (f'<span style="position:absolute;right:-4px;bottom:-4px;width:{bs}px;height:{bs}px;border-radius:50%;'
             f'background:{color};color:{p["raised"]};box-shadow:0 0 0 2px {p["halo"]};display:flex;align-items:center;justify-content:center">'
             f'<span style="width:{bs-5}px;height:{bs-5}px;display:block">{glyph(sk)}</span></span>')
    return (f'<span style="position:relative;display:inline-flex;width:{size}px;height:{size}px;border-radius:50%;'
            f'background:{p["raised"]};box-shadow:inset 0 0 0 3px {ring},0 0 0 2px {p["halo"]};align-items:center;justify-content:center;'
            f'color:{glyph_color or color};margin:10px">'
            f'<span style="width:{g}px;height:{g}px;display:block">{glyph(key)}</span>{b}</span>')


def sheet(p, selected="give-way"):
    tiles = []
    for key, title in THEMES:
        on = key == selected
        bg = p["soft"] if on else "transparent"
        bd = p["accent"] if on else "transparent"
        tiles.append(f'<div class="tile" style="background:{bg};box-shadow:inset 0 0 0 1.5px {bd}">'
                     f'<span class="ic" style="color:{p["accent"]}">{glyph(key)}</span>'
                     f'<span class="tl" style="color:{p["text"]}">{title}</span></div>')
    appr = "".join(f'<div class="ap"><span class="ai" style="color:{p[t]}">{glyph(k)}</span>'
                   f'<span style="color:{p["text"]}">{label}</span></div>' for k, label, t in STATUS)
    return (f'<div class="sheet" style="background:{p["surface"]};color:{p["text"]};border-color:{p["border"]}">'
            f'<div class="hd"><b>Signaler</b><span class="mk" style="color:{p["muted"]}">{glyph("marker")}</span></div>'
            f'<div class="grid">{"".join(tiles)}</div><div class="apr" style="border-color:{p["border"]}">{appr}</div></div>')


def mapview(p):
    keys = [("speed", "danger"), ("give-way", "warning"), ("observation", "success"), ("marker", "neutral"),
            ("right-priority", "success"), ("manoeuvres", "danger"), ("anticipation", "warning")]
    pins = "".join(marker_html(p, k, t, selected=(i == 2), glyph_color=p["text"]) for i, (k, t) in enumerate(keys))
    alt = "".join(marker_html(p, k, t) for k, t in keys[:4])
    return (f'<div class="map" style="background:{p["map"]}">'
            f'<svg class="roads" viewBox="0 0 360 260"><path d="M-10 200 C80 180 120 120 200 110 S320 60 380 40" stroke="{p["road"]}" stroke-width="18" fill="none"/>'
            f'<path d="M60 -10 L90 280" stroke="{p["road"]}" stroke-width="12" fill="none"/>'
            f'<path d="M-10 200 C80 180 120 120 200 110 S320 60 380 40" stroke="{p["route"]}" stroke-width="5" fill="none" stroke-linecap="round"/></svg>'
            f'<div class="pins">{pins}</div><div class="pins alt"><small style="color:{p["muted"]}">Variante : glyphe à l\'encre</small>{alt}</div></div>')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", default="contexte.html")
    a = ap.parse_args()
    cols = "".join(f'<div class="col" style="background:{PALETTE[m]["page"]}"><h2 style="color:{PALETTE[m]["muted"]}">{"Clair" if m=="light" else "Sombre"}</h2>'
                   f'{sheet(PALETTE[m])}{mapview(PALETTE[m])}</div>' for m in ("light", "dark"))
    html = f"""<!doctype html><html lang="fr"><meta charset="utf-8"><title>Signaler en contexte</title>
<style>
body{{margin:0;font:14px/1.3 -apple-system,"Segoe UI",system-ui,sans-serif;display:flex}}
.col{{flex:1;padding:18px 22px}} h2{{font-size:13px;font-weight:600;margin:0 0 10px}}
.sheet{{width:375px;border:1px solid;border-radius:26px;padding:8px 8px 6px;margin-bottom:16px}}
.hd{{display:flex;align-items:center;justify-content:space-between;padding:8px 10px 10px 12px;font-size:17px}}
.mk svg{{width:28px;height:28px;display:block}}
.grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:4px}}
.tile{{min-height:80px;border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;padding:8px 6px}}
.ic svg{{width:28px;height:28px;display:block}} .tl{{font-size:13px;font-weight:600;text-align:center;line-height:1.2}}
.apr{{display:flex;border-top:1px solid;margin-top:6px;padding-top:6px}}
.ap{{flex:1;display:flex;flex-direction:column;align-items:center;gap:8px;padding:10px 4px;font-size:13px;font-weight:600}}
.ai svg{{width:24px;height:24px;display:block}}
.map{{position:relative;width:375px;height:260px;border-radius:20px;overflow:hidden}}
.roads{{position:absolute;inset:0;width:100%;height:100%}}
.pins{{position:relative;display:flex;flex-wrap:wrap;align-items:center;padding:10px 6px 0}}
.pins.alt{{padding-top:4px}} .pins.alt small{{width:100%;padding-left:10px}}
</style>{cols}</html>"""
    (HERE / a.o).write_text(html, encoding="utf-8")
    print(HERE / a.o)


if __name__ == "__main__":
    main()
