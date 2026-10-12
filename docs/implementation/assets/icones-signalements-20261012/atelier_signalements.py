"""Atelier des quatre nouveaux thèmes de « Signaler » : clignotants, distance de sécurité, freinage,
changement de voie. Trois propositions par thème.

Il réutilise les primitives et la grammaire de l'atelier du 12 octobre (`../icones-signaler-20261012`) :
canevas 64, formes pleines d'une seule couleur, épaisseur 6, bouts ronds, contre-formes d'au moins 4,
vrais trous `evenodd`. Chaque proposition garde ses tours : le dernier est la proposition, les
précédents sont archivés dans `tours/` pour être comparés.

Usage : python atelier_signalements.py   → propositions/<clé>/<lettre>.svg, tours/<clé>/<lettre>-t<n>.svg, propositions.json
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from shapely import affinity
from shapely.geometry import box

HERE = Path(__file__).resolve().parent
BASE_DIR = HERE.parent / "icones-signaler-20261012"
sys.path.insert(0, str(BASE_DIR))
import atelier as base  # noqa: E402  (l'atelier du 12 octobre : primitives et sortie SVG)

U, line, disc, ring, rrect, rpoly = base.U, base.line, base.disc, base.ring, base.rrect, base.rpoly
arc, arc_pts, bezier, arrow, head, dashes, car_top = (base.arc, base.arc_pts, base.bezier, base.arrow,
                                                      base.head, base.dashes, base.car_top)
W, G = base.W, base.G

OUT = HERE / "propositions"
TOURS = HERE / "tours"


# ---------------------------------------------------------------- primitives ajoutées

def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def block_arrow(tip, ang, hl, hw, sl, sh, r=1.8):
    """Flèche pleine du tableau de bord : pointe en `tip`, tournée vers `ang` ; fût de `sl` × `sh`."""
    pts = [(0, 0), (-hl, -hw / 2), (-hl, -sh / 2), (-hl - sl, -sh / 2),
           (-hl - sl, sh / 2), (-hl, sh / 2), (-hl, hw / 2)]
    g = rpoly(pts, r)
    g = affinity.rotate(g, ang, origin=(0, 0))
    return affinity.translate(g, tip[0], tip[1])


def rays(cx, cy, r0, r1, angles, w=5.0):
    """Éclats : traits courts à bouts ronds, rayonnant autour de (cx, cy)."""
    return U(*[line(polar(cx, cy, r0, a), polar(cx, cy, r1, a), w=w) for a in angles])


def car_rear(cx, top, w=38.0, lights=True):
    """Voiture vue de l'arrière : pavillon, caisse, roues ; lunette et feux évidés."""
    k = w / 38.0
    cabin = rpoly([(cx - w * 0.30, top), (cx + w * 0.30, top), (cx + w * 0.43, top + 12 * k),
                   (cx - w * 0.43, top + 12 * k)], 3 * k)
    lower = rrect(cx - w / 2, top + 9.5 * k, w, 15.5 * k, 4.5 * k)
    wheels = U(rrect(cx - w / 2 + 2.5 * k, top + 20 * k, 8.5 * k, 9.5 * k, 2.5 * k),
               rrect(cx + w / 2 - 11 * k, top + 20 * k, 8.5 * k, 9.5 * k, 2.5 * k))
    window = rpoly([(cx - w * 0.235, top + 4 * k), (cx + w * 0.235, top + 4 * k),
                    (cx + w * 0.30, top + 9.2 * k), (cx - w * 0.30, top + 9.2 * k)], 1.0 * k)
    body = U(cabin, lower, wheels).difference(window)
    if lights:
        body = body.difference(U(rrect(cx - w / 2 + 3.2 * k, top + 13.2 * k, 8 * k, 4.4 * k, 2.2 * k),
                                 rrect(cx + w / 2 - 11.2 * k, top + 13.2 * k, 8 * k, 4.4 * k, 2.2 * k)))
    return body


def car_side_mini(x0, base_y, L=22.0):
    """Petite voiture de profil, avant à droite : silhouette sans vitres, faite pour 6 px de large."""
    k = L / 22.0
    lower = rrect(x0, base_y - 9.5 * k, L, 9.5 * k, 3 * k)
    cabin = rpoly([(x0 + 3.5 * k, base_y - 8 * k), (x0 + 7 * k, base_y - 16 * k), (x0 + L - 8 * k, base_y - 16 * k),
                   (x0 + L - 3.5 * k, base_y - 8 * k)], 2 * k)
    wheels = U(disc(x0 + 5.5 * k, base_y, 3.6 * k), disc(x0 + L - 5.5 * k, base_y, 3.6 * k))
    return U(lower, cabin, wheels)


def double_arrow(p0, p1, w=5.0, hl=8.0, hw=13.0):
    """Cote : fût et deux pointes pleines, de p0 à p1."""
    ang = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    s0 = (p0[0] + ux * hl * 0.6, p0[1] + uy * hl * 0.6)
    s1 = (p1[0] - ux * hl * 0.6, p1[1] - uy * hl * 0.6)
    return U(line(s0, s1, w=w), head(p1, ang, length=hl, width=hw), head(p0, ang + 180, length=hl, width=hw))


def sector(cx, cy, r_in, r_out, a0, a1, r=2.0):
    """Secteur d'anneau aux angles adoucis."""
    pts = arc_pts(cx, cy, r_out, a0, a1, 48) + arc_pts(cx, cy, r_in, a1, a0, 48)
    return rpoly(pts, r)


# ---------------------------------------------------------------- 1. Clignotants

def indicators_A_t1():
    left = block_arrow((4, 32), 180, hl=17, hw=30, sl=7, sh=12)
    right = block_arrow((60, 32), 0, hl=17, hw=30, sl=7, sh=12)
    return U(left, right)


def indicators_B_t1():
    arr = block_arrow((58, 41), 0, hl=19, hw=32, sl=27, sh=13)
    flash = rays(26, 41, 14.5, 23, (-128, -90, -52))
    return U(arr, flash)


def indicators_C_t1():
    car = car_rear(25, 15, 38)
    flash = rays(44, 31.5, 6.5, 13, (-38, 0, 38))
    return U(car, flash)



def indicators_A_t2():
    # Tour 2 — défaut nommé : à 16 px, deux losanges. Fûts allongés, têtes moins hautes : deux flèches.
    left = block_arrow((3, 32), 180, hl=15, hw=28, sl=10, sh=11)
    right = block_arrow((61, 32), 0, hl=15, hw=28, sl=10, sh=11)
    return U(left, right)


def indicators_B_t2():
    # Tour 2 — défaut nommé : les éclats posés sur le fût se lisaient « clic » ou couronne. Ils partent
    # maintenant de la pointe : la flèche émet, elle signale.
    arr = block_arrow((40, 32), 0, hl=17, hw=30, sl=17, sh=12)
    flash = rays(28, 32, 19, 28, (-45, 0, 45))
    return U(arr, flash)


def indicators_C_t2():
    # Tour 2 — défaut nommé : lunette et deux feux évidés faisaient un visage. Les feux pleins ; seuls
    # les éclats disent lequel clignote.
    car = car_rear(25, 15, 38, lights=False)
    flash = rays(44, 30.5, 6.5, 14, (-40, 0, 40), w=5.4)
    return U(car, flash)


# ---------------------------------------------------------------- 2. Distance de sécurité

def _car_end(cx, y0, y1, w, front):
    """Bout de voiture vue du dessus, coupé net au bord du canevas : l'avant porte le pare-brise."""
    if front:   # notre voiture, en bas : nez arrondi en haut
        return rrect(cx - w / 2, y0, w, (y1 - y0) + 12, 8).intersection(box(0, y0, 64, y1))
    return rrect(cx - w / 2, y0 - 12, w, (y1 - y0) + 12, 8).intersection(box(0, y0, 64, y1))


def following_A_t1():
    lead = _car_end(32, 6, 17, 26, front=False)
    ours = _car_end(32, 47, 58, 26, front=True)
    gap = double_arrow((32, 21.5), (32, 42.5), w=5, hl=8, hw=14)
    return U(lead, ours, gap)


def following_B_t1():
    behind = car_side_mini(4, 30, 20)
    ahead = car_side_mini(40, 30, 20)
    gap = double_arrow((21, 46), (43, 46), w=5, hl=7.5, hw=12.5)
    return U(behind, ahead, gap)


def following_C_t1():
    car = car_rear(32, 5, 30)
    bars = U(line((17, 40.5), (47, 40.5)), line((9.5, 53.5), (54.5, 53.5)))
    return U(car, bars)



def car_mini(cx, cy, w=19.0, h=18.0):
    """Voiture courte vue du dessus, avant en haut : caisse pleine, pare-brise évidé."""
    x, y = cx - w / 2, cy - h / 2
    body = rrect(x, y, w, h, 5.5)
    ws = rpoly([(x + 4.4, y + 4.6), (x + w - 4.4, y + 4.6), (x + w - 3.4, y + 9.2), (x + 3.4, y + 9.2)], 1.0)
    return body.difference(ws)


def following_A_t2():
    # Tour 2 — défaut nommé : sablier. Les voitures sont entières, la cote passe à côté de l'écart.
    lead = car_mini(21, 14)
    ours = car_mini(21, 50)
    gap = double_arrow((46, 21.5), (46, 42.5), w=5, hl=8, hw=14)
    return U(lead, ours, gap)


def following_B_t2():
    # Tour 2 — défaut nommé : deux yeux et une bouche. La cote monte entre les deux voitures.
    behind = car_side_mini(4, 38, 18)
    ahead = car_side_mini(42, 38, 18)
    gap = double_arrow((24.5, 31.5), (39.5, 31.5), w=4.6, hl=6, hw=10.5)
    return U(behind, ahead, gap)


def following_C_t2():
    # Tour 2 — défaut nommé : voiture posée sur un socle. Barres détachées, la première plus courte que
    # la voiture : elles fuient vers elle comme des repères au sol.
    car = car_rear(32, 5, 30)
    bars = U(line((21, 40.5), (43, 40.5)), line((12, 53.5), (52, 53.5)))
    return U(car, bars)


# ---------------------------------------------------------------- 3. Freinage

def braking_A_t1():
    drum = ring(32, 32, 14, 8)
    shoes = U(arc(32, 32, 24, -52, 52), arc(32, 32, 24, 128, 232))
    return U(drum, shoes)


def braking_B_t1():
    pad = rrect(9, 32, 38, 24, 6)
    grooves = U(rrect(15.5, 38.4, 25, 4, 2), rrect(15.5, 45.8, 25, 4, 2))
    arm = line((33, 34), (47.5, 9), w=7)
    return U(pad.difference(grooves), arm)


def braking_C_t1():
    cx, cy = 30, 34
    disc_ = ring(cx, cy, 23, 16.5)
    hub = disc(cx, cy, 7)
    caliper = sector(cx, cy, 12.5, 29.5, -72, -12, 2.5)
    return U(disc_.difference(caliper.buffer(G * 0.7)), hub, caliper)



def braking_A_t2():
    # Tour 2 — défaut nommé : tambour maigre entre deux ondes, lu « vibreur ». Tambour agrandi, il domine.
    drum = ring(32, 32, 15.5, 9)
    shoes = U(arc(32, 32, 25, -50, 50), arc(32, 32, 25, 130, 230))
    return U(drum, shoes)


def braking_B_t2():
    # Tour 2 — défaut nommé : une raclette. La pédale reçoit son contexte : l'accélérateur, étroit, à sa droite.
    pad = rrect(6, 34, 32, 22, 6)
    grooves = U(rrect(12, 39.6, 20, 4, 2), rrect(12, 46.6, 20, 4, 2))
    arm = line((23, 36), (30, 9), w=6.5)
    throttle = rrect(46, 24, 12, 32, 5)
    return U(pad.difference(grooves), arm, throttle)


def braking_C_t2():
    # Tour 2 — défaut nommé : part de camembert. L'étrier ne vise plus le centre : un bloc qui enjambe la jante.
    cx, cy = 30, 34
    disc_ = ring(cx, cy, 23, 16.5)
    hub = disc(cx, cy, 6.5)
    caliper = sector(cx, cy, 14.5, 30.5, -66, -14, 4.5)
    return U(disc_.difference(caliper.buffer(G * 0.75)), hub, caliper)


# ---------------------------------------------------------------- 4. Changement de voie

def _lane_shift(x0=16, x1=48, y_bottom=58, y_top=7, y_a=47, y_b=25, w=W, hl=11, hw=17):
    pts = [(x0, y_bottom)] + bezier((x0, y_a), (x0, y_a - 13), (x1, y_b + 13), (x1, y_b))
    return arrow(*pts, (x1, y_top), w=w, hl=hl, hw=hw)


def lane_change_A_t1():
    shift = _lane_shift()
    lane = U(line((32, 49), (32, 58)), line((32, 6), (32, 15)))
    return U(shift, lane)


def lane_change_B_t1():
    car = car_top(32, 32, 20, 36, rot=18)
    lane = dashes((32, 6), (32, 58), 4).difference(car.buffer(G))
    return U(car, lane)


def lane_change_C_t1():
    main = arrow((22, 58), (22, 7), hl=11, hw=17)
    branch = line(*([(46, 58)] + bezier((46, 50), (46, 37), (22, 41), (22, 28))))
    return U(main, branch)



def lane_change_A_t2():
    # Tour 2 — défaut nommé : S mou et tirets en miettes. Diagonale franche, tirets allongés.
    shift = _lane_shift(y_a=51, y_b=21)
    lane = U(line((32, 46), (32, 58)), line((32, 6), (32, 17)))
    return U(shift, lane.difference(shift.buffer(G)))


def lane_change_B_t2():
    # Tour 2 — défaut nommé : colonne étroite, trop proche de « Placement ». Voiture plus en biais.
    car = car_top(32, 32, 21, 36, rot=30)
    lane = dashes((32, 5), (32, 59), 4).difference(car.buffer(G))
    return U(car, lane)


def lane_change_C_t2():
    # Tour 2 — défaut nommé : la lettre « h ». La voie qui se rabat s'arrête à une contre-forme de la
    # voie rejointe, comme la trace mordue par le repère.
    main = arrow((22, 58), (22, 7), hl=11, hw=17)
    branch = line(*([(47, 58)] + bezier((47, 51), (47, 37), (22, 41), (22, 27))))
    return U(main, branch.difference(main.buffer(G)))


# ---------------------------------------------------------------- finition des retenues
# Vues dans la planche de famille, à côté des onze existantes : même idée, même dessin, seules la
# graisse et la taille optique changent. L'export réduit chaque glyphe (taille optique égalisée) ;
# le trait est épaissi d'autant pour retrouver l'épaisseur 6 de la famille une fois en place.

def indicators_final():
    # Bande trop basse : plus petite à l'œil que ses voisines. Têtes et fûts plus hauts (23 → 33).
    # Demi-hauteur de tête = longueur : les flancs sont à 45° exactement (l'audit relevait 45,9°).
    left = block_arrow((4, 32), 180, hl=16.5, hw=33, sl=8.5, sh=13)
    right = block_arrow((60, 32), 0, hl=16.5, hw=33, sl=8.5, sh=13)
    return U(left, right)


def following_final():
    # Barres à 6,4 : 6 en place après réduction (×0,93). Voiture élargie de 30 à 34 : lunette et feux
    # étaient sous la contre-forme minimale une fois réduits.
    car = car_rear(32, 5, 34)
    bars = U(line((21, 42.5), (43, 42.5), w=6.4), line((12, 54.8), (52, 54.8), w=6.4))
    return U(car, bars)


def braking_final():
    # Tambour et mâchoires à 6,5 : 6 en place après réduction (×0,92).
    drum = ring(32, 32, 16, 9.5)
    shoes = U(arc(32, 32, 25.75, -50, 50, w=6.5), arc(32, 32, 25.75, 130, 230, w=6.5))
    return U(drum, shoes)


def _lane_shift_arcs(x0, x1, y_bottom, y_tip, R, w, hl, hw):
    """La même flèche construite au compas : droite, arc de 45°, diagonale à 45° exactement, arc de 45°, droite."""
    k = R * (1 - math.cos(math.radians(45)))          # déport d'un arc
    m = R * math.sin(math.radians(45))                # montée d'un arc
    run = (x1 - x0) - 2 * k                           # déport (= montée) de la diagonale
    y1 = y_tip + hl + 0.5                             # fin de l'arc du haut, sous la pointe
    y2 = y1 + m                                       # fin de la diagonale
    y3 = y2 + run                                     # début de la diagonale
    y4 = y3 + m                                       # début de l'arc du bas
    low = arc_pts(x0 + R, y4, R, 180, 225, 24)        # tourne vers la droite
    high = arc_pts(x1 - R, y1, R, 45, 0, 24)          # se redresse
    pts = [(x0, y_bottom)] + low + high
    return arrow(*pts, (x1, y_tip), w=w, hl=hl, hw=hw)


def lane_change_final():
    # Flèche et tirets à 6,8 : 6 en place après réduction (×0,88). Le S du tour 2 était une courbe libre
    # (l'audit y relevait six arêtes à 151°) : il est reconstruit en deux arcs de rayon 8 et une
    # diagonale à 45° exactement. Les tirets s'arrêtent à une contre-forme de la flèche.
    shift = _lane_shift_arcs(x0=18, x1=46, y_bottom=59, y_tip=5, R=8, w=6.8, hl=12.5, hw=18)
    lane = U(line((32, 49), (32, 59), w=6.8), line((32, 5), (32, 12), w=6.8))
    return U(shift, lane.difference(shift.buffer(G)))


# ---------------------------------------------------------------- registre

def P(letter, famille, name, idea, *tours):
    return {"direction": letter, "famille": famille, "name": name, "idea": idea, "tours": list(tours)}


ICONS = {
    "indicators": {"finition": indicators_final, "title": "Clignotants", "directions": [
        P("A", "Instrument", "Paire de témoins", "Les deux flèches du témoin de clignotant, dos à dos, en aplat.",
          indicators_A_t1, indicators_A_t2),
        P("B", "Instrument", "Témoin qui clignote", "Une seule flèche de témoin et ses trois éclats : elle clignote.",
          indicators_B_t1, indicators_B_t2),
        P("C", "Silhouette", "Feu arrière", "L'arrière d'une voiture dont un feu clignote.", indicators_C_t1, indicators_C_t2),
    ]},
    "following-distance": {"finition": following_final, "trait": 6.4, "title": "Distance de sécurité", "directions": [
        P("A", "Plan", "L'écart dans l'axe", "Le véhicule qui précède, le nôtre, et la cote de l'écart entre les deux.",
          following_A_t1, following_A_t2),
        P("B", "Panneau", "Deux profils", "Deux voitures de profil qui se suivent, l'écart coté dessous.",
          following_B_t1, following_B_t2),
        P("C", "Instrument", "Barres d'écart", "L'arrière du véhicule qui précède et les barres d'écart du régulateur.",
          following_C_t1, following_C_t2),
    ]},
    "braking": {"finition": braking_final, "trait": 6.5, "title": "Freinage", "directions": [
        P("A", "Instrument", "Témoin de frein", "Le témoin de frein du tableau de bord : un tambour entre ses deux mâchoires.",
          braking_A_t1, braking_A_t2),
        P("B", "Instrument", "Pédale", "La pédale de frein, large et striée, au bout de son bras.", braking_B_t1, braking_B_t2),
        P("C", "Silhouette", "Disque et étrier", "Un disque de frein pincé par son étrier.", braking_C_t1, braking_C_t2),
    ]},
    "lane-change": {"finition": lane_change_final, "trait": 6.8, "title": "Changement de voie", "directions": [
        P("A", "Manœuvre", "Par-dessus la ligne", "La flèche quitte une voie pour l'autre en passant entre deux tirets.",
          lane_change_A_t1, lane_change_A_t2),
        P("B", "Plan", "À cheval", "La voiture vue du dessus, en biais sur la ligne pointillée.", lane_change_B_t1, lane_change_B_t2),
        P("C", "Manœuvre", "Rabattement", "Une voie rejoint l'autre : se rabattre.", lane_change_C_t1, lane_change_C_t2),
    ]},
}


def build_all():
    report = {}
    f = HERE / "selection.json"
    selection = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
    for key, spec in ICONS.items():
        (OUT / key).mkdir(parents=True, exist_ok=True)
        (TOURS / key).mkdir(parents=True, exist_ok=True)
        report[key] = {"title": spec["title"], "proposals": []}
        for p in spec["directions"]:
            for n, build in enumerate(p["tours"], 1):
                (TOURS / key / f"{p['direction']}-t{n}.svg").write_text(
                    base.svg(build(), f"{spec['title']} — {p['name']} (tour {n})"), encoding="utf-8")
            if spec.get("finition") and selection.get(key, {}).get("retenue") == p["direction"]:
                (TOURS / key / f"{p['direction']}-finition.svg").write_text(
                    base.svg(spec["finition"](), f"{spec['title']} — {p['name']} (finition)"), encoding="utf-8")
            g = p["tours"][-1]()
            (OUT / key / f"{p['direction']}.svg").write_text(
                base.svg(g, f"{spec['title']} — {p['name']}"), encoding="utf-8")
            report[key]["proposals"].append({"direction": p["direction"], "famille": p["famille"], "name": p["name"],
                                             "idea": p["idea"], "tours": len(p["tours"]), **base.metrics(g)})
    (HERE / "propositions.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    return report


if __name__ == "__main__":
    for k, v in build_all().items():
        print(k, " ".join(f"{p['direction']}:{p['ink']}/{p['w']}x{p['h']}" for p in v["proposals"]))
