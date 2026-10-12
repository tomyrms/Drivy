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


def car_rear(cx, top, w=38.0, lights=True, window=True):
    """Voiture vue de l'arrière : pavillon, caisse, roues ; lunette et feux évidés."""
    k = w / 38.0
    cabin = rpoly([(cx - w * 0.30, top), (cx + w * 0.30, top), (cx + w * 0.43, top + 12 * k),
                   (cx - w * 0.43, top + 12 * k)], 3 * k)
    lower = rrect(cx - w / 2, top + 9.5 * k, w, 15.5 * k, 4.5 * k)
    wheels = U(rrect(cx - w / 2 + 2.5 * k, top + 20 * k, 8.5 * k, 9.5 * k, 2.5 * k),
               rrect(cx + w / 2 - 11 * k, top + 20 * k, 8.5 * k, 9.5 * k, 2.5 * k))
    glass = rpoly([(cx - w * 0.235, top + 4 * k), (cx + w * 0.235, top + 4 * k),
                   (cx + w * 0.30, top + 9.2 * k), (cx - w * 0.30, top + 9.2 * k)], 1.0 * k)
    body = U(cabin, lower, wheels)
    if window:
        body = body.difference(glass)
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


# ---------------------------------------------------------------- études D, E, F
# Demandées par le porteur après avoir vu les quatre retenues : trois idées de plus par thème, pour
# choisir sur planche. Des idées nouvelles, pas des variantes de A, B, C ; le plus simple d'abord.

def stepped(x0, x1, y_bottom, y_step, r=6.0):
    """Baïonnette : monte, passe de x0 à x1 par deux angles droits adoucis (rayon r), remonte."""
    sx = 1 if x1 > x0 else -1
    if sx > 0:
        low = arc_pts(x0 + r, y_step + r, r, 180, 270, 16)
        high = arc_pts(x1 - r, y_step - r, r, 90, 0, 16)
    else:
        low = arc_pts(x0 - r, y_step + r, r, 0, -90, 16)
        high = arc_pts(x1 + r, y_step - r, r, 90, 180, 16)
    return [(x0, y_bottom)] + low + high


def indicators_D_t1():
    lamp = ring(32, 32, 27, 21)
    arr = block_arrow((47, 32), 0, hl=13, hw=24, sl=13, sh=9)
    return U(lamp, arr)


def indicators_E_t1():
    car = car_top(26, 32, 20, 38)
    flash = U(rays(36, 16, 7, 15, (-50, -10)), rays(36, 48, 7, 15, (10, 50)))
    return U(car, flash)


def indicators_F_t1():
    column = disc(13, 32, 8.5)
    stalk = line((13, 32), (44, 32), w=7)
    knob = rrect(38, 25.5, 17, 13, 5.5)
    ticks = U(head((46.5, 8), -90, length=9, width=15), head((46.5, 56), 90, length=9, width=15))
    return U(column, stalk, knob, ticks)


def following_D_t1():
    far = car_rear(32, 4, 22, lights=False, window=False)
    near = car_rear(32, 28, 40)
    return U(far, near)


def _chevron(cx, apex_y, half=12.0, w=W):
    dy = half * math.tan(math.radians(30))
    return line((cx - half, apex_y + dy), (cx, apex_y), (cx + half, apex_y + dy), w=w)


def following_E_t1():
    car = car_top(32, 15.5, 18, 24)
    marks = U(_chevron(32, 35), _chevron(32, 48))
    return U(car, marks)


def following_F_t1():
    ours = car_side_mini(-12, 44, 32).intersection(box(4, 0, 64, 64))
    lead = car_side_mini(44, 44, 32).intersection(box(0, 0, 60, 64))
    gap = double_arrow((23.5, 36.5), (40.5, 36.5), w=5, hl=6.5, hw=11.5)
    return U(ours, lead, gap)


def _foot_on_pedal(tilt=22.0, arm=True):
    shoe = rpoly([(0, 0), (38, 0), (38, -8.5), (24, -13.5), (15, -24), (0, -24)], 4.5)
    pedal = line((15, 7.5), (40, 7.5), w=6)
    parts = [shoe, pedal]
    if arm:
        parts.append(line((29, 7.5), (35, 26), w=6))
    return affinity.rotate(U(*parts), tilt, origin=(19, -8))


def braking_D_t1():
    return affinity.translate(_foot_on_pedal(), 12, 30)


def braking_E_t1():
    car = car_rear(32, 16, 30, lights=False)
    y = 16 + 15.4 * 30 / 38
    glow = U(rays(17, y, 5.5, 12, (140, 180, 220)), rays(47, y, 5.5, 12, (-40, 0, 40)))
    return U(car, glow)


def braking_F_t1():
    plate = disc(32, 32, 26).difference(disc(32, 32, 9))
    holes = U(*[disc(*polar(32, 32, 17.5, a), 2.5) for a in range(0, 360, 45)])
    return plate.difference(holes)


def lane_change_D_t1():
    shift = arrow(*stepped(17, 47, 58, 34), (47, 7), hl=11, hw=16)
    lane = U(line((32, 46), (32, 58)), line((32, 6), (32, 22)))
    return U(shift, lane.difference(shift.buffer(G)))


def lane_change_E_t1():
    straight = arrow((18, 58), (18, 7), hl=11, hw=16)
    shift = arrow(*stepped(32, 46, 58, 38), (46, 7), hl=11, hw=16)
    return U(straight, shift)


def lane_change_F_t1():
    lane = U(line((32, 6), (32, 18)), line((32, 46), (32, 58)))
    cross = arrow((9, 32), (55, 32), hl=12, hw=18)
    return U(lane, cross)


# Tour 2 des études : un défaut nommé par dessin ; les traits sont réglés pour valoir 6 une fois
# le glyphe mis à sa taille optique par l'export.

def indicators_D_t2():
    # Défaut nommé : voyant maigre une fois réduit (×0,85), lu « bouton suivant ». Anneau à 7, flèche
    # plus grosse : c'est la flèche du témoin qui porte, l'anneau l'entoure.
    lamp = ring(32, 32, 27.5, 20.5)
    arr = block_arrow((48, 32), 0, hl=14, hw=28, sl=13, sh=11)
    return U(lamp, arr)


def indicators_E_t2():
    # Défaut nommé : quatre grands éclats lus « pattes ». Éclats courts, un à l'horizontale par feu.
    car = car_top(25, 32, 20, 38)
    flash = U(rays(35, 16.5, 7, 13, (-45, 0), w=5.4), rays(35, 47.5, 7, 13, (0, 45), w=5.4))
    return U(car, flash)


def indicators_F_t2():
    # Défaut nommé : lu « curseur ». Le levier sort en biais d'une colonne plus grosse, ses deux
    # sens tout contre la poignée.
    column = disc(14, 40, 10.5)
    tip = polar(14, 40, 34, -20)
    stalk = line((14, 40), tip, w=7)
    knob = line(polar(14, 40, 27, -20), polar(14, 40, 38, -20), w=13)
    ux, uy = math.cos(math.radians(-20)), math.sin(math.radians(-20))
    kx, ky = polar(14, 40, 32.5, -20)
    up = head((kx + uy * 20, ky - ux * 20), -110, length=9, width=15)
    down = head((kx - uy * 20, ky + ux * 20), 70, length=9, width=15)
    return U(column, stalk, knob, up, down)


def following_D_t2():
    # Défaut nommé : la petite voiture coiffait la grande, un seul totem. Plus d'écart, grande voiture
    # moins large : deux voitures, et de l'air entre elles.
    far = car_rear(32, 4, 20, lights=False, window=False)
    near = car_rear(32, 30.5, 36)
    return U(far, near)


def following_E_t2():
    # Défaut nommé : voiture et chevrons empilés, lus « bonhomme » ou « grade ». Chevrons plus larges
    # que la voiture et détachés : un marquage au sol, plus un corps.
    car = car_top(32, 14.5, 17, 23)
    marks = U(_chevron(32, 36.5, half=17), _chevron(32, 49, half=17))
    return U(car, marks)


def following_F_t2():
    # Défaut nommé : deux moitiés de voiture illisibles, lues « pinces ». Les pare-chocs sont réduits
    # à deux barres : il ne reste que l'écart et sa cote.
    bumpers = U(line((8.5, 16), (8.5, 48), w=7), line((55.5, 16), (55.5, 48), w=7))
    gap = double_arrow((17, 32), (47, 32), w=6.2, hl=10, hw=17)
    return U(bumpers, gap)


def braking_D_t2():
    # Défaut nommé : lu « hachoir ». Le talon est au sol, la pointe relevée sur la pédale, dont le bras
    # monte : la jambe pousse vers l'avant.
    shoe = rpoly([(0, 0), (40, 0), (40, -9), (25, -14), (16, -25), (0, -25)], 4.5)
    pad = line((14, 7.6), (43, 7.6), w=6.4)
    low = affinity.rotate(U(shoe, pad), -38, origin=(0, 0))
    end = affinity.rotate(line((43, 7.6), (43.01, 7.6), w=1), -38, origin=(0, 0)).centroid
    arm = line((end.x, end.y), (end.x, end.y - 17), w=6.4)
    return affinity.translate(U(low, arm), 8, 50)


def braking_E_t2():
    # Défaut nommé : six longs éclats lus « crabe ». Voiture plus grande, éclats courts et serrés.
    car = car_rear(32, 15, 34, lights=False)
    y = 15 + 15.4 * 34 / 38
    glow = U(rays(15, y, 5, 10.5, (152, 180, 208), w=4.8), rays(49, y, 5, 10.5, (-28, 0, 28), w=4.8))
    return U(car, glow)


def braking_F_t2():
    # Défaut nommé : trop d'encre, lu « cadran de téléphone ». Piste plus étroite, six perçages : un disque.
    plate = disc(32, 32, 26).difference(disc(32, 32, 12.5))
    holes = U(*[disc(*polar(32, 32, 19.25, a), 2.7) for a in range(0, 360, 60)])
    return plate.difference(holes)


def lane_change_D_t2():
    # Défaut nommé : maigre une fois réduite, tiret du haut collé à la pointe. Trait à 6,3, tiret raccourci.
    shift = arrow(*stepped(17, 47, 58, 34), (47, 6), w=6.3, hl=11.5, hw=16.5)
    lane = U(line((32, 46.5), (32, 58), w=6.3), line((32, 6), (32, 20), w=6.3))
    return U(shift, lane.difference(shift.buffer(G)))


def lane_change_E_t2():
    # Défaut nommé : la file qui se décale s'écartait de l'autre, lue « bifurcation ». Elle se range
    # maintenant à côté de celle qui continue.
    straight = arrow((16, 58), (16, 7), hl=11, hw=16)
    shift = arrow(*stepped(48, 34, 58, 40), (34, 7), hl=11, hw=16)
    return U(straight, shift)


def lane_change_F_t2():
    # Défaut nommé : lu « + ». Tirets courts et décalés à gauche, flèche longue : c'est elle qui domine.
    lane = U(line((25, 6), (25, 14), w=6.9), line((25, 50), (25, 58), w=6.9))
    cross = arrow((7, 32), (57, 32), w=6.9, hl=14, hw=21)
    return U(lane, cross)


ETUDES = {
    "indicators": [
        P("D", "Instrument", "Témoin dans son rond", "Une seule flèche de témoin dans son voyant rond.", indicators_D_t1, indicators_D_t2),
        P("E", "Plan", "La voiture clignote", "La voiture vue du dessus, ses deux clignotants de droite allumés.", indicators_E_t1, indicators_E_t2),
        P("F", "Instrument", "Commodo", "Le levier de clignotant : on le lève ou on l'abaisse.", indicators_F_t1, indicators_F_t2),
    ],
    "following-distance": [
        P("D", "Silhouette", "Deux arrières", "Deux voitures vues de l'arrière, la plus lointaine plus petite.", following_D_t1, following_D_t2),
        P("E", "Plan", "Deux chevrons", "Le véhicule qui précède et deux chevrons au sol jusqu'à lui.", following_E_t1, following_E_t2),
        P("F", "Panneau", "Entre deux pare-chocs", "Une cote entre l'avant d'une voiture et l'arrière de l'autre.", following_F_t1, following_F_t2),
    ],
    "braking": [
        P("D", "Instrument", "Pied sur la pédale", "Un pied appuie sur la pédale de frein.", braking_D_t1, braking_D_t2),
        P("E", "Silhouette", "Feux stop", "L'arrière d'une voiture dont les deux feux stop s'allument.", braking_E_t1, braking_E_t2),
        P("F", "Silhouette", "Disque percé", "Un disque de frein seul, plein, avec ses perçages.", braking_F_t1, braking_F_t2),
    ],
    "lane-change": [
        P("D", "Manœuvre", "Baïonnette", "La flèche change de voie par deux angles droits, entre deux longs tirets.", lane_change_D_t1, lane_change_D_t2),
        P("E", "Manœuvre", "Deux files", "Deux flèches parallèles : l'une continue, l'autre se décale.", lane_change_E_t1, lane_change_E_t2),
        P("F", "Manœuvre", "Ligne franchie", "Une flèche traverse la ligne pointillée entre deux tirets.", lane_change_F_t1, lane_change_F_t2),
    ],
}
for _key, _extra in ETUDES.items():
    ICONS[_key]["directions"] += _extra


# ---------------------------------------------------------------- trois thèmes de plus
# Démarrage, Virages, Éco-conduite : le catalogue passe à dix-huit thèmes. Même méthode, même grammaire.

def ribbon(pts, w0, w1):
    """Ruban plein le long d'une ligne, de largeur w0 au départ à w1 à l'arrivée (route qui s'éloigne)."""
    n = len(pts)
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        x0, y0 = pts[max(i - 1, 0)]
        x1, y1 = pts[min(i + 1, n - 1)]
        L = math.hypot(x1 - x0, y1 - y0) or 1.0
        nx, ny = -(y1 - y0) / L, (x1 - x0) / L
        h = (w0 + (w1 - w0) * i / (n - 1)) / 2
        left.append((x + nx * h, y + ny * h))
        right.append((x - nx * h, y - ny * h))
    return rpoly(left + right[::-1], 1.5)


def moving_off_A_t1():
    start = base.marker(15, 32, 12, 6)
    trace = base.bite(arrow((15, 32), (59, 32), hl=13, hw=24), 15, 32, 12)
    return U(start, trace)


def moving_off_B_t1():
    slope = rpoly([(6, 55), (58, 55), (58, 29)], 3)
    climb = arrow((8.6, 40.3), (45.6, 21.8), hl=11, hw=17)
    return U(slope, climb)


def moving_off_C_t1():
    bow = ring(18, 30, 13, 6.5)
    blade = line((30, 30), (57, 30))
    bits = U(line((45, 30), (45, 40)), line((55, 30), (55, 40)))
    return U(bow, blade, bits)


def _elbow(x, r, top, right=58.0, bottom=58.0, cx=44.0, cy=44.0, w=W):
    """Bordure de virage : monte en x, tourne d'un quart de cercle de rayon r autour de (cx, cy), file à droite."""
    return line(*([(x, bottom)] + arc_pts(cx, cy, r, 180, 270, 32) + [(right, top)]), w=w)


def bends_A_t1():
    outer = _elbow(12, 32, 12)
    inner = _elbow(38, 6, 38)
    return U(outer, inner)


def _winding():
    return (bezier((20, 60), (20, 44), (46, 44), (44, 28))
            + bezier((44, 28), (43, 18), (30, 14), (30, 4))[1:])


def bends_B_t1():
    road = ribbon(_winding(), 19, 9)
    centre = U(*[line(a, b, w=4) for a, b in ((_winding()[6], _winding()[22]), (_winding()[44], _winding()[60]))])
    return road.difference(centre)


def _bend_arrow(sweep=60.0, R=22.0, x=20.0, y0=58.0, y1=42.0, run=14.0, w=W, hl=12.0, hw=18.0):
    pts = [(x, y0)] + arc_pts(x + R, y1, R, 180, 180 + sweep, 24)
    a = math.radians(180 + sweep + 90)
    ex, ey = pts[-1]
    tip = (ex + math.cos(a) * run, ey + math.sin(a) * run)
    return arrow(*pts, tip, w=w, hl=hl, hw=hw)


def bends_C_t1():
    return _bend_arrow()


def _leaf(cx=33.0, cy=30.0, a=27.0, b=14.0, rot=-45.0):
    blade = base._almond(cx, cy, a, b)
    stem = line((cx - a + 2, cy), (cx - a - 9, cy))
    return blade, stem, rot, (cx, cy)


def eco_A_t1():
    blade, stem, rot, c = _leaf()
    rib = U(*[line((x0, 30), (x1, 30), w=4) for x0, x1 in ((18, 24), (31, 37), (44, 48))])
    return affinity.rotate(U(blade.difference(rib), stem), rot, origin=c)


def eco_B_t1():
    gate = U(line((14, 14), (14, 50)), line((32, 14), (32, 50)), line((50, 14), (50, 50)), line((14, 32), (50, 32)))
    knob = disc(50, 14, 8.5)
    return U(gate, knob)


def eco_C_t1():
    body = rrect(11, 8, 27, 48, 5).difference(rrect(17, 14.5, 15, 11, 2.5))
    hose = line((38, 41), (48, 41), (48, 22), (43, 15), w=5.5)
    return U(body, hose)


def moving_off_A_t2():
    # Tour 2 — défaut nommé : un anneau et une flèche, c'est le symbole « ♂ » couché. Le point de
    # départ devient un disque plein, détaché de la trace par une contre-forme.
    start = disc(14, 32, 10)
    trace = arrow((14, 32), (59, 32), hl=13, hw=24).difference(disc(14, 32, 10 + G))
    return U(start, trace)


def moving_off_B_t2():
    # Tour 2 — défaut nommé : la queue de la flèche touchait presque la pointe de la pente à 16 px.
    # Pente à 1 pour 2 exactement, flèche remontée.
    slope = rpoly([(4, 57), (58, 57), (58, 30)], 3)
    climb = arrow((10.4, 37.5), (46.4, 19.5), hl=11.5, hw=17.5)
    return U(slope, climb)


def moving_off_C_t2():
    # Tour 2 — défaut nommé : une clé à anneau se lit « mot de passe ». Tête pleine d'une clé de voiture.
    fob = rrect(5, 17, 25, 27, 8.5).difference(disc(14, 30, 3.4))
    blade = line((30, 30), (57, 30))
    bits = U(line((46, 30), (46, 40.5)), line((56, 30), (56, 40.5)))
    return U(fob, blade, bits)


def bends_A_t2():
    # Tour 2 — défaut nommé : deux bordures seules se lisent « tuyau » ou « coin arrondi ». L'axe en
    # tirets en fait une route ; il suit le même centre que les bordures.
    outer = _elbow(12, 32, 12)
    inner = _elbow(38, 6, 38)
    axis = U(line((25, 50), (25, 58)), arc(44, 44, 19, 207, 243), line((50, 25), (58, 25)))
    return U(outer, inner, axis)


def _winding2():
    return (bezier((18, 60), (18, 42), (50, 46), (46, 28))
            + bezier((46, 28), (43, 16), (28, 16), (30, 3))[1:])


def bends_B_t2():
    # Tour 2 — défaut nommé : en petit, une flamme. Lacets plus marqués, ruban moins effilé, tirets plus gros.
    pts = _winding2()
    road = ribbon(pts, 17, 11)
    centre = U(*[line(pts[a], pts[b], w=4.4) for a, b in ((8, 26), (48, 66), (96, 114))])
    return road.difference(centre)


def bends_C_t2():
    # Tour 2 — défaut nommé : dessin trop petit, grossi par l'export (×1,20, trait à 7,2). Courbe plus
    # ample : rayon 30, soixante degrés exactement.
    return _bend_arrow(sweep=60, R=30, x=14, y0=59, y1=40, run=15, hl=12, hw=18)


def eco_A_t2():
    # Tour 2 — défaut nommé : trois tirets de 4 se ferment à 16 px. Deux tirets plus longs, à 4,8.
    blade, stem, rot, c = _leaf()
    rib = U(line((17, 30), (26, 30), w=4.8), line((35, 30), (46, 30), w=4.8))
    return affinity.rotate(U(blade.difference(rib), stem), rot, origin=c)


def eco_B_t2():
    # Tour 2 — défaut nommé : pommeau trop petit, lu comme un simple bout rond. Pommeau à 9,5.
    gate = U(line((14, 15), (14, 51)), line((32, 15), (32, 51)), line((50, 15), (50, 51)), line((14, 33), (50, 33)))
    knob = disc(50, 14.5, 9.5)
    return U(gate, knob)


def eco_C_t2():
    # Tour 2 — défaut nommé : trop d'encre. Vitre agrandie, tuyau détaché du corps.
    body = rrect(11, 8, 26, 48, 5).difference(rrect(16, 13.5, 16, 14, 2.5))
    hose = line((37, 42), (48.5, 42), (48.5, 23), (43.5, 16), w=5.5)
    return U(body, hose)


def bends_A_t3():
    # Tour 3, pour lever une lecture involontaire : deux bordures et un axe, tous en quarts de cercle
    # de même centre, c'est le pictogramme « flux RSS » ou « wifi ». La chaussée devient un seul aplat,
    # son axe en tirets évidés : plus trois arcs, une route.
    centre = [(25, 59)] + arc_pts(44, 44, 19, 180, 270, 32) + [(59, 25)]
    road = line(*centre, w=22, cap="flat").buffer(-2.5, join_style="round").buffer(2.5, join_style="round")
    axis = U(line((25, 47.5), (25, 54), w=4.8), arc(44, 44, 19, 208, 242, w=4.8), line((47.5, 25), (54, 25), w=4.8))
    return road.difference(axis)


def bends_final():
    # Finition, vue dans la planche de famille : colonne de 30 de large, plus maigre que ses voisines.
    # Même rayon et mêmes soixante degrés ; la flèche file plus loin après la courbe et le trait passe à 6,3.
    return _bend_arrow(sweep=60, R=30, x=11, y0=59, y1=43, run=22, w=6.3, hl=12.5, hw=19)


LOT3 = {
    "moving-off": {"title": "Démarrage", "directions": [
        P("A", "Trace", "Départ", "Le repère du point de départ et la trace qui en part.", moving_off_A_t1, moving_off_A_t2),
        P("B", "Panneau", "En côte", "Une pente et la flèche qui la monte : démarrer en côte.", moving_off_B_t1, moving_off_B_t2),
        P("C", "Instrument", "Clé de contact", "La clé de contact, en aplat.", moving_off_C_t1, moving_off_C_t2),
    ]},
    "bends": {"finition": bends_final, "trait": 6.3, "title": "Virages", "directions": [
        P("A", "Plan", "La route tourne", "Les deux bordures d'une route qui tourne, vues du dessus.", bends_A_t1, bends_A_t2, bends_A_t3),
        P("B", "Silhouette", "Lacets", "Une route pleine qui serpente et s'éloigne, son axe en tirets.", bends_B_t1, bends_B_t2),
        P("C", "Panneau", "Flèche de virage", "La flèche courbe du panneau de virage.", bends_C_t1, bends_C_t2),
    ]},
    "eco-driving": {"title": "Éco-conduite", "directions": [
        P("A", "Silhouette", "Feuille-route", "Une feuille dont la nervure est l'axe en tirets d'une route.", eco_A_t1, eco_A_t2),
        P("B", "Instrument", "Grille de vitesses", "La grille du levier de vitesses, pommeau sur le rapport le plus haut.", eco_B_t1, eco_B_t2),
        P("C", "Silhouette", "Pompe", "Une pompe à essence : ce que l'on consomme.", eco_C_t1, eco_C_t2),
    ]},
}
ICONS.update(LOT3)
LOT1_KEYS = ["indicators", "following-distance", "braking", "lane-change"]
LOT3_KEYS = list(LOT3)


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
