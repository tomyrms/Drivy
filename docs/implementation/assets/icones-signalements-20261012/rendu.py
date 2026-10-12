"""Rendu des SVG en PNG, sans navigateur : c'est l'outil pour regarder les dessins à chaque tour.

Les SVG de l'atelier ne contiennent que des tracés `M … L … Z` remplis en `evenodd` ; ils sont relus
tels qu'écrits sur le disque (donc tels que livrés), tramés à 16 × la taille puis réduits, ce qui
reproduit l'anticrénelage d'un écran. Les planches montrent chaque dessin à 64, 28 et 16 px, le 16 px
agrandi cinq fois au pixel près, en clair et en sombre Soft Charcoal, puis flouté et en miroir.

Usage :
  python rendu.py tour 1            → tour-1.png (propositions du tour, taille optique égalisée)
  python rendu.py propositions      → propositions.png (dernier tour de chaque proposition)
  python rendu.py voisins           → voisins.png (chaque proposition entre ses voisines les plus proches)
  python rendu.py etudes 1          → etudes-tour-1.png (les études D, E, F, tour par tour)
  python rendu.py voisins-etudes    → voisins-etudes.png (les études D, E, F entre leurs voisines)
  python rendu.py choix             → choix.png et choix-<clé>.png (les six études par thème, pour choisir)
  python rendu.py finition          → finition.png (les quatre retenues, tour 2 puis finition)
  Avec `--lot 3`, les mêmes planches pour Démarrage, Virages et Éco-conduite : tour-1-3.png,
  tour-2-3.png, propositions-3.png, voisins-3.png, finition-3.png.
  python rendu.py famille           → famille.png (les quinze thèmes du catalogue, 28 et 16 pt, clair et sombre)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CATALOG = ROOT / "apps/ios/Drivy/Resources/Assets.xcassets"

# Couleurs de DrivyTheme : feuille (surface), bloc (surfaceCard), accent comme encre, texte, texte secondaire.
LIGHT = dict(page="#FFFFFF", card="#F7F8FA", accent="#245BD6", text="#18212B", muted="#536174", line="#D9E0E9")
DARK = dict(page="#1D1F23", card="#2A2D31", accent="#86ABF8", text="#F4F5F6", muted="#A1A5AD", line="#3A3F46")


def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def parse(svg_text):
    """Anneaux (listes de points) de tous les tracés d'un SVG de l'atelier, sur le canevas 64."""
    rings = []
    for d in re.findall(r'\sd="([^"]+)"', svg_text):
        for sub in d.split("Z"):
            nums = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", sub)]
            if len(nums) >= 6:
                rings.append(list(zip(nums[0::2], nums[1::2])))
    return rings


def mask(rings, px, ss=16, mirror=False):
    """Masque de couverture à `px` pixels de côté : remplissage evenodd, suréchantillonné `ss` fois."""
    n = px * ss
    k = n / 64.0
    acc = Image.new("1", (n, n), 0)
    for r in rings:
        layer = Image.new("1", (n, n), 0)
        pts = [((64 - x if mirror else x) * k, y * k) for x, y in r]
        ImageDraw.Draw(layer).polygon(pts, fill=1)
        acc = ImageChops.logical_xor(acc, layer)
    return acc.convert("L").resize((px, px), Image.LANCZOS if ss == 1 else Image.BOX)


def stamp(img, rings, xy, px, color, zoom=1, blur=0.0, mirror=False):
    m = mask(rings, px, mirror=mirror)
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    if zoom != 1:
        m = m.resize((px * zoom, px * zoom), Image.NEAREST)
    img.paste(Image.new("RGB", m.size, rgb(color)), xy, m)


def load(path):
    return parse(Path(path).read_text(encoding="utf-8"))


def normalized(key, geom):
    """La géométrie telle qu'elle sera exportée : même égalisation de taille optique que le catalogue."""
    sys.path.insert(0, str(HERE.parent / "icones-signaler-20261012"))
    import atelier as base  # noqa: E402
    import export as base_export  # noqa: E402
    g, scale = base_export.normalize(geom, key)
    return parse(base.svg(g, key)), scale


def cell(img, x, y, rings, pal, label=None, sub=None, w=250):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x, y, x + w, y + 196), 10, fill=rgb(pal["page"]), outline=rgb(pal["line"]))
    if label:
        d.text((x + 10, y + 6), label, font=font(13, True), fill=rgb(pal["text"]))
    if sub:
        d.text((x + 10, y + 24), sub, font=font(11), fill=rgb(pal["muted"]))
    stamp(img, rings, (x + 10, y + 46), 96, pal["accent"])
    stamp(img, rings, (x + 116, y + 46), 28, pal["accent"])
    stamp(img, rings, (x + 152, y + 52), 16, pal["accent"])
    stamp(img, rings, (x + 116, y + 84), 16, pal["accent"], zoom=5)      # le 16 px, pixel par pixel
    stamp(img, rings, (x + 10, y + 150), 40, pal["accent"], blur=2.2)    # test de flou
    stamp(img, rings, (x + 60, y + 150), 40, pal["accent"], mirror=True)  # test de miroir
    d.text((x + 106, y + 172), "flou · miroir", font=font(10), fill=rgb(pal["muted"]))


def sheet(rows, out, title):
    """rows : [(titre du thème, [(étiquette, sous-titre, anneaux), …]), …]."""
    cols = max(len(r[1]) for r in rows)
    width = 24 + cols * 2 * 258 + 20
    height = 60 + len(rows) * 232
    img = Image.new("RGB", (width, height), rgb("#EEF1F4"))
    d = ImageDraw.Draw(img)
    d.text((24, 16), title, font=font(18, True), fill=rgb(LIGHT["text"]))
    for i, (name, cells) in enumerate(rows):
        y = 56 + i * 232
        d.text((24, y), name, font=font(14, True), fill=rgb(LIGHT["text"]))
        for j, (label, sub, rings) in enumerate(cells):
            cell(img, 24 + j * 258, y + 24, rings, LIGHT, label, sub)
            cell(img, 24 + cols * 258 + 12 + j * 258, y + 24, rings, DARK, label, sub)
    img.save(out)
    print(out)


def proposals(tour=None, letters="ABC", keys=None):
    sys.path.insert(0, str(HERE))
    import atelier_signalements as atelier  # noqa: E402
    notes = {}
    f = HERE / "selection.json"
    if f.exists():
        notes = json.loads(f.read_text(encoding="utf-8"))
    rows = []
    for key, spec in atelier.ICONS.items():
        if keys is not None and key not in keys:
            continue
        cells = []
        for p in spec["directions"]:
            if p["direction"] not in letters:
                continue
            n = len(p["tours"]) if tour is None else min(tour, len(p["tours"]))
            rings, scale = normalized(key, p["tours"][n - 1]())
            total = notes.get(key, {}).get("notes", {}).get(p["direction"], {}).get("total")
            won = notes.get(key, {}).get("retenue") == p["direction"]
            label = f"{p['direction']} · {p['name']}" + (f"  {total:.2f}" if total and tour is None else "")
            sub = f"{p['famille']} · tour {n} · échelle {scale:.2f}" + ("  ← retenue" if won and tour is None else "")
            cells.append((label, sub, rings))
        if cells:
            rows.append((f"{spec['title']}  ({key})", cells))
    return rows


NEIGHBOURS = {
    "indicators": ["right-priority", "manoeuvres", "give-way"],
    "following-distance": ["placement", "vehicle", "motorway"],
    "braking": ["observation", "intersections", "speed"],
    "lane-change": ["manoeuvres", "placement", "motorway"],
    "moving-off": ["vehicle", "speed", "right-priority"],
    "bends": ["manoeuvres", "lane-change", "motorway"],
    "eco-driving": ["signage", "anticipation", "indicators"],
}


def neighbours(out, letters="ABC", keys=None):
    """Chaque proposition à 28 et 16 px entre les icônes existantes avec lesquelles elle pourrait se confondre."""
    rows = proposals(letters=letters, keys=keys)
    order = [re.search(r"\(([^)]+)\)$", name).group(1) for name, _ in rows]
    img = Image.new("RGB", (1180, 70 + len(rows) * 150), rgb("#EEF1F4"))
    d = ImageDraw.Draw(img)
    d.text((24, 16), "Voisinage — chaque proposition entre les icônes existantes les plus proches (28 et 16 px)",
           font=font(16, True), fill=rgb(LIGHT["text"]))
    for i, ((name, cells), key) in enumerate(zip(rows, order)):
        y = 56 + i * 150
        d.text((24, y), name, font=font(13, True), fill=rgb(LIGHT["text"]))
        olds = [(k, load(CATALOG / f"Observation-{k}.imageset" / f"{k}.svg")) for k in NEIGHBOURS[key]]
        for half, pal in enumerate((LIGHT, DARK)):
            x0 = 24 + half * 572
            d.rounded_rectangle((x0, y + 22, x0 + 560, y + 138), 10, fill=rgb(pal["page"]), outline=rgb(pal["line"]))
            x = x0 + 14
            for label, _, rings in cells:
                stamp(img, rings, (x, y + 38), 28, pal["accent"])
                stamp(img, rings, (x + 6, y + 82), 16, pal["accent"])
                d.text((x + 8, y + 112), label[:1], font=font(11, True), fill=rgb(pal["text"]))
                x += 56
            d.line((x + 4, y + 34, x + 4, y + 126), fill=rgb(pal["line"]))
            x += 24
            for k, rings in olds:
                stamp(img, rings, (x, y + 38), 28, pal["accent"])
                stamp(img, rings, (x + 6, y + 82), 16, pal["accent"])
                d.text((x - 6, y + 112), k[:11], font=font(10), fill=rgb(pal["muted"]))
                x += 76
    img.save(out)
    print(out)


THEMES = [("vehicle", "Maîtrise du véhicule"), ("observation", "Observation et contrôles"),
          ("right-priority", "Priorité à droite"), ("signage", "Signalisation"), ("give-way", "Céder le passage"),
          ("intersections", "Intersections et giratoires"), ("speed", "Vitesse"),
          ("placement", "Placement sur la chaussée"), ("manoeuvres", "Manœuvres"), ("motorway", "Autoroute"),
          ("anticipation", "Anticipation"), ("indicators", "Clignotants"),
          ("following-distance", "Distance de sécurité"), ("braking", "Freinage"),
          ("lane-change", "Changement de voie"), ("moving-off", "Démarrage"), ("bends", "Virages"),
          ("eco-driving", "Éco-conduite")]
NEW = {"indicators", "following-distance", "braking", "lane-change", "moving-off", "bends", "eco-driving"}


def family(out):
    """Les dix-huit thèmes relus dans le catalogue Xcode. En haut la grille de « Signaler » à 28 pt (@2x,
    56 px) ; dessous, deux bandes au pixel près, 28 px puis 16 px, et le 16 px agrandi trois fois.
    Les sept nouveaux sont soulignés."""
    icons = [(k, t, load(CATALOG / f"Observation-{k}.imageset" / f"{k}.svg")) for k, t in THEMES]
    pw, ph = 600, 990
    img = Image.new("RGB", (24 + 2 * (pw + 16), 64 + ph + 16), rgb("#EEF1F4"))
    d = ImageDraw.Draw(img)
    d.text((24, 16), "Famille des thèmes de « Signaler » — onze existants et sept nouveaux (soulignés)",
           font=font(17, True), fill=rgb(LIGHT["text"]))
    for half, (pal, name) in enumerate(((LIGHT, "Clair"), (DARK, "Sombre Soft Charcoal"))):
        x0, y0 = 24 + half * (pw + 16), 56
        d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), 18, fill=rgb(pal["page"]), outline=rgb(pal["line"]))
        d.text((x0 + 20, y0 + 14), f"{name} — 28 pt (@2x)", font=font(12), fill=rgb(pal["muted"]))
        cw, chh = (pw - 40) // 3, 104
        for i, (k, t, rings) in enumerate(icons):
            cx = x0 + 20 + (i % 3) * cw + cw // 2
            cy = y0 + 44 + (i // 3) * chh
            stamp(img, rings, (cx - 28, cy), 56, pal["accent"])
            tw = d.textlength(t, font=font(13, True))
            d.text((cx - tw / 2, cy + 62), t, font=font(13, True), fill=rgb(pal["text"]))
            if k in NEW:
                d.line((cx - tw / 2, cy + 82, cx + tw / 2, cy + 82), fill=rgb(pal["accent"]), width=2)
        ys = y0 + 44 + 6 * chh + 16
        d.line((x0 + 20, ys, x0 + pw - 20, ys), fill=rgb(pal["line"]))
        step = (pw - 40) / len(icons)
        for row, px in enumerate((28, 16)):
            yy = ys + 16 + row * 68
            d.text((x0 + 20, yy), f"{px} px, au pixel près", font=font(11), fill=rgb(pal["muted"]))
            for i, (k, t, rings) in enumerate(icons):
                xx = int(x0 + 20 + i * step + (step - px) / 2)
                stamp(img, rings, (xx, yy + 20 + (28 - px) // 2), px, pal["accent"])
                if k in NEW:
                    d.line((xx, yy + 54, xx + px, yy + 54), fill=rgb(pal["accent"]), width=2)
        yz = ys + 16 + 2 * 68
        d.text((x0 + 20, yz), "Le 16 px agrandi trois fois (pixels réels)", font=font(11), fill=rgb(pal["muted"]))
        step = (pw - 40) / 9
        for i, (k, t, rings) in enumerate(icons):
            xx = int(x0 + 20 + (i % 9) * step + (step - 48) / 2)
            yy = yz + 22 + (i // 9) * 62
            stamp(img, rings, (xx, yy), 16, pal["accent"], zoom=3)
            if k in NEW:
                d.line((xx, yy + 53, xx + 48, yy + 53), fill=rgb(pal["accent"]), width=2)
    img.save(out)
    print(out)


def choice(out_all):
    """Planche de choix : par thème, les six études côte à côte. Chaque carte porte sa lettre, son nom
    et sa note ; le dessin en grand, à 28 px et à 16 px au pixel près, en clair puis en sombre.
    La carte de l'icône livrée aujourd'hui est cerclée."""
    sys.path.insert(0, str(HERE))
    import atelier_signalements as atelier  # noqa: E402
    sel = json.loads((HERE / "selection.json").read_text(encoding="utf-8"))
    cw, ch, gap = 296, 348, 10
    width = 24 + 6 * (cw + gap) + 14

    def row(img, y, key, spec):
        d = ImageDraw.Draw(img)
        d.text((24, y), spec["title"], font=font(24, True), fill=rgb(LIGHT["text"]))
        live = sel[key].get("choix_porteur") or sel[key]["retenue"]
        for j, q in enumerate(spec["directions"]):
            letter = q["direction"]
            build = spec["finition"] if (letter == sel[key]["retenue"] and spec.get("finition")) else q["tours"][-1]
            rings, _ = normalized(key, build())
            total = sel[key]["notes"].get(letter, {}).get("total")
            x, yy = 24 + j * (cw + gap), y + 40
            won = letter == live
            d.rounded_rectangle((x, yy, x + cw, yy + ch), 16, fill=rgb(LIGHT["page"]),
                                outline=rgb(LIGHT["accent"] if won else LIGHT["line"]), width=4 if won else 1)
            d.text((x + 16, yy + 6), letter, font=font(40, True), fill=rgb(LIGHT["text"]))
            d.text((x + 54, yy + 12), q["name"], font=font(17, True), fill=rgb(LIGHT["text"]))
            if total is not None:
                d.text((x + 54, yy + 34), f"{total:.2f}".replace(".", ","), font=font(17, True), fill=rgb(LIGHT["accent"]))
            if won:
                d.text((x + 106, yy + 36), "livrée aujourd'hui", font=font(14), fill=rgb(LIGHT["muted"]))
            stamp(img, rings, (x + 20, yy + 68), 128, LIGHT["accent"])
            stamp(img, rings, (x + 180, yy + 84), 28, LIGHT["accent"])
            stamp(img, rings, (x + 236, yy + 90), 16, LIGHT["accent"])
            stamp(img, rings, (x + 180, yy + 132), 16, LIGHT["accent"], zoom=4)
            d.rounded_rectangle((x + 10, yy + 214, x + cw - 10, yy + ch - 10), 12, fill=rgb(DARK["page"]))
            stamp(img, rings, (x + 30, yy + 232), 88, DARK["accent"])
            stamp(img, rings, (x + 180, yy + 240), 28, DARK["accent"])
            stamp(img, rings, (x + 236, yy + 246), 16, DARK["accent"])
            stamp(img, rings, (x + 180, yy + 276), 16, DARK["accent"], zoom=3)

    rh = ch + 62
    whole = Image.new("RGB", (width, 70 + len(atelier.ICONS) * rh), rgb("#EEF1F4"))
    ImageDraw.Draw(whole).text((24, 16), "Nouveaux thèmes de « Signaler » — les études de chaque thème, à choisir par lettre",
                               font=font(26, True), fill=rgb(LIGHT["text"]))
    for i, (key, spec) in enumerate(atelier.ICONS.items()):
        row(whole, 66 + i * rh, key, spec)
        one = Image.new("RGB", (width, rh + 20), rgb("#EEF1F4"))
        row(one, 12, key, spec)
        one.save(HERE / f"choix-{key}.png")
        print(HERE / f"choix-{key}.png")
    whole.save(out_all)
    print(out_all)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "propositions"
    sys.path.insert(0, str(HERE))
    import atelier_signalements as _atelier  # noqa: E402
    lot3 = "--lot" in sys.argv and sys.argv[sys.argv.index("--lot") + 1] == "3"
    KEYS = _atelier.LOT3_KEYS if lot3 else _atelier.LOT1_KEYS
    SUFFIX = "-3" if lot3 else ""
    LOT = "Démarrage, Virages, Éco-conduite" if lot3 else "Nouveaux thèmes de « Signaler »"
    if what == "tour":
        n = int(sys.argv[2])
        sheet(proposals(n, keys=KEYS), HERE / f"tour-{n}{SUFFIX}.png", f"{LOT} — tour {n} (64 → 28 → 16 px, clair et sombre)")
    elif what == "etudes":
        n = int(sys.argv[2])
        sheet(proposals(n, "DEF", _atelier.LOT1_KEYS), HERE / f"etudes-tour-{n}.png",
              f"Études D, E, F — tour {n} (64 → 28 → 16 px, clair et sombre)")
    elif what == "voisins-etudes":
        neighbours(HERE / "voisins-etudes.png", "DEF", _atelier.LOT1_KEYS)
    elif what == "choix":
        choice(HERE / "choix.png")
    elif what == "voisins":
        neighbours(HERE / f"voisins{SUFFIX}.png", keys=KEYS)
    elif what == "finition":
        import atelier_signalements as atelier
        sel = json.loads((HERE / "selection.json").read_text(encoding="utf-8"))
        rows = []
        for key, spec in atelier.ICONS.items():
            if key not in KEYS or not spec.get("finition"):
                continue
            prop = next(q for q in spec["directions"] if q["direction"] == sel[key]["retenue"])
            before, s0 = normalized(key, prop["tours"][-1]())
            after, s1 = normalized(key, spec["finition"]())
            rows.append((f"{spec['title']}  ({key})", [
                (f"{prop['direction']} · {prop['name']}", f"tour {len(prop['tours'])} · échelle {s0:.2f}", before),
                (f"{prop['direction']} · {prop['name']}", f"finition, livrée · échelle {s1:.2f}", after)]))
        sheet(rows, HERE / f"finition{SUFFIX}.png", "Finition des retenues — graisse et taille optique en place")
    elif what == "famille":
        family(HERE / "famille.png")
    else:
        sheet(proposals(keys=KEYS), HERE / f"propositions{SUFFIX}.png", f"{LOT} — trois propositions par thème")
