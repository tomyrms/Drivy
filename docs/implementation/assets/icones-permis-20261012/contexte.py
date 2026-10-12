"""Aperçu des icônes retenues dans leurs contextes : filtre de permis (Leçons, Progression) fermé et ouvert,
lignes de permis du Profil, sélecteur de l'invitation (normal, sélectionné, désactivé). Maquette HTML aux
jetons de DrivyTheme, clair et Soft Charcoal ; elle ne remplace pas les captures du simulateur.

Usage : python contexte.py → contexte.html
"""
from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

T = {
    "light": dict(canvas="#F7F8FA", surface="#FFFFFF", card="#F7F8FA", muted_fill="#EEF2F7", text="#18212B",
                  muted="#536174", accent="#245BD6", accent_fill="#245BD6", accent_soft="#EAF0FE", border="#D9E0E9",
                  disabled="#5D6A7C", menu="#FFFFFF", toggle_off="#E8EDF3"),
    "dark": dict(canvas="#17191C", surface="#17191C", card="#272A2E", muted_fill="#34383D", text="#F4F5F6",
                 muted="#A1A5AD", accent="#86ABF8", accent_fill="#3D70E2", accent_soft="#2F3B54", border="#3A3E44",
                 disabled="#7A7F87", menu="#272A2E", toggle_off="#303338"),
}


def icon(key, size=22, color="currentColor"):
    s = (HERE / "retenues" / f"{key}.svg").read_text(encoding="utf-8")
    s = re.sub(r"<title>.*?</title>", "", s).replace('fill="#245BD6"', f'fill="{color}"')
    return s.replace('width="64" height="64"', f'width="{size}" height="{size}"')


def panel(mode):
    c = T[mode]
    seg = (f'<div style="display:flex;background:{c["muted_fill"]};border-radius:9px;padding:2px;margin:8px 0 10px">'
           f'<div style="flex:1;text-align:center;padding:6px;border-radius:7px;background:{c["surface"]};font-weight:600">Leçons</div>'
           f'<div style="flex:1;text-align:center;padding:6px;color:{c["muted"]}">Progression</div></div>')
    chevron = f'<span style="font-size:10px;margin-left:4px">⌃⌄</span>'
    filt = (f'<div style="display:flex;align-items:center;justify-content:space-between;min-height:44px">'
            f'<span style="display:flex;align-items:center;gap:6px;color:{c["accent"]};font-weight:600;font-size:15px">'
            f'{icon("b", 22, c["accent"])}Permis B{chevron}</span>'
            f'<span style="color:{c["accent"]};font-weight:600;font-size:15px">Filtrer et trier</span></div>')
    rows = [("Tous les permis", None, False), ("Permis B", "b", True), ("Permis A", "a", False), ("Permis BE", "be", False)]
    menu = (f'<div style="background:{c["menu"]};border-radius:13px;box-shadow:0 8px 30px rgba(0,0,0,.18);'
            f'width:250px;margin:4px 0 14px;overflow:hidden;border:1px solid {c["border"]}">')
    for i, (t, k, on) in enumerate(rows):
        check = f'<span style="width:18px;color:{c["text"]}">{"✓" if on else ""}</span>'
        img = icon(k, 22, c["text"]) if k else ""
        sep = f"border-top:1px solid {c['border']};" if i else ""
        menu += (f'<div style="display:flex;align-items:center;gap:8px;padding:11px 14px;{sep}">{check}'
                 f'<span style="flex:1">{t}</span>{img}</div>')
    menu += "</div>"
    head = (f'<div style="display:flex;align-items:center;gap:8px;margin:14px 0 6px;font-weight:700;font-size:17px">'
            f'{icon("a", 26, c["muted"])}Permis A<span style="font-weight:400;font-size:14px;color:{c["muted"]}">En pause</span></div>')

    def prow(k, title, sub):
        return (f'<div style="display:flex;align-items:center;gap:10px;padding:8px 14px;border-top:1px solid {c["border"]}">'
                f'<span style="width:44px;height:44px;border-radius:50%;background:{c["muted_fill"]};display:grid;place-items:center">'
                f'{icon(k, 26, c["muted"])}</span><span style="flex:1"><b style="font-size:16px">{title}</b><br>'
                f'<span style="color:{c["muted"]};font-size:14px">{sub}</span></span><span style="color:{c["muted"]}">›</span></div>')
    profile = (f'<div style="background:{c["card"] if mode == "dark" else c["surface"]};border-radius:12px;overflow:hidden;'
               f'border:1px solid {c["border"]}">' + prow("b", "Permis B", "14 leçons terminées · 21 h 00").replace("border-top", "border-x", 1)
               + prow("a", "Permis A", "3 leçons terminées · 4 h 30") + prow("be", "Permis BE", "2 leçons terminées · 3 h 00") + "</div>")

    def toggle(k, title, state):
        on = state == "on"
        col = {"on": c["accent"], "off": c["muted"], "disabled": c["disabled"]}[state]
        knob_bg = c["accent_fill"] if on else c["toggle_off"]
        op = "opacity:.5;" if state == "disabled" else ""
        return (f'<div style="display:flex;align-items:center;gap:10px;padding:10px 14px;border-top:1px solid {c["border"]};{op}">'
                f'{icon(k, 24, col)}<span style="flex:1">{title}</span>'
                f'<span style="width:46px;height:28px;border-radius:14px;background:{knob_bg};position:relative">'
                f'<span style="position:absolute;top:2px;{"right" if on else "left"}:2px;width:24px;height:24px;border-radius:50%;'
                f'background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25)"></span></span></div>')
    invite = (f'<div style="background:{c["card"] if mode == "dark" else c["surface"]};border-radius:12px;overflow:hidden;'
              f'border:1px solid {c["border"]}">' + toggle("b", "Permis B", "on").replace("border-top", "border-x", 1)
              + toggle("a1", "Permis A1", "off") + toggle("c", "Permis C", "disabled") + "</div>")
    lab = lambda t: f'<div style="font-size:12px;color:{c["muted"]};margin:16px 0 6px;text-transform:uppercase;letter-spacing:.04em">{t}</div>'
    return (f'<div style="background:{c["canvas"]};color:{c["text"]};padding:18px 18px 22px;width:340px;'
            f'font:15px/1.3 -apple-system,\'SF Pro Text\',\'Segoe UI\',sans-serif">'
            f'<div style="font-size:12px;color:{c["muted"]}">{"Clair" if mode == "light" else "Soft Charcoal"}</div>'
            f'{lab("Leçons — filtre fermé")}{seg}{filt}{lab("Filtre ouvert")}{menu}{lab("Progression — « Tous »")}{head}'
            f'{lab("Profil — permis suivis")}{profile}{lab("Invitation — normal, sélectionné, désactivé")}{invite}</div>')


def main():
    html = ('<!doctype html><meta charset=utf-8><title>Permis en contexte</title>'
            '<body style="margin:0;display:flex;background:#888">' + panel("light") + panel("dark") + "</body>")
    (HERE / "contexte.html").write_text(html, encoding="utf-8")
    print(HERE / "contexte.html")


if __name__ == "__main__":
    main()
