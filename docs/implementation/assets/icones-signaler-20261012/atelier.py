"""Atelier des icônes « Signaler » — cinq directions par icône, géométrie calculée.

Grammaire commune (une famille, quelle que soit la direction) :
- canevas 64 × 64, zone utile 6–58 ; carrés ≈ 46, cercles ≈ 50, triangles ≈ 54 (même taille optique) ;
- formes pleines, une seule couleur (gabarit) ; trous réels (`evenodd`), jamais une forme blanche posée dessus ;
- épaisseur de trait W = 6 (9,4 % du canevas), bouts et jonctions ronds comme la trace de Drivy ;
- contre-forme minimale G = 4 : elle reste ouverte à 16 px ;
- rayon d'angle des aplats 3 à 10 selon la taille de la pièce.

Les cinq directions :
  A « Plan »        la route vue du dessus, comme sur la carte ;
  B « Panneau »     le langage des panneaux routiers, redessiné ;
  C « Instrument »  l'objet ou le geste du conducteur ;
  D « Silhouette »  un objet unique, plein, lisible de loin ;
  E « Trace »       les deux primitives de la marque, trace et repère.

Usage : python atelier.py  → propositions/<icône>/<direction>.svg
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union
from shapely import affinity

W = 6.0      # épaisseur commune
G = 4.0      # contre-forme minimale
HALO = 2.5   # morsure du repère sur la trace (marque)
Q = 32       # segments par quart de cercle

HERE = Path(__file__).resolve().parent
OUT = HERE / "propositions"


# ---------------------------------------------------------------- primitives

def U(*shapes):
    return unary_union([s for s in shapes if s is not None and not s.is_empty])


def line(*pts, w=W, cap="round"):
    return LineString(pts).buffer(w / 2, quad_segs=Q, cap_style=cap, join_style="round")


def disc(cx, cy, r):
    return Point(cx, cy).buffer(r, quad_segs=Q)


def ring(cx, cy, ro, ri):
    return disc(cx, cy, ro).difference(disc(cx, cy, ri))


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    if r <= 0:
        return box(x, y, x + w, y + h)
    return box(x + r, y + r, x + w - r, y + h - r).buffer(r, quad_segs=Q)


def rpoly(pts, r=0):
    p = Polygon(pts)
    if r <= 0:
        return p
    return p.buffer(-r, join_style="round", quad_segs=Q).buffer(r, join_style="round", quad_segs=Q)


def arc_pts(cx, cy, r, a0, a1, n=96):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def arc(cx, cy, r, a0, a1, w=W, cap="round"):
    return line(*arc_pts(cx, cy, r, a0, a1), w=w, cap=cap)


def bezier(p0, p1, p2, p3, n=96):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def head(tip, direction_deg, length=None, width=None, r=1.2):
    """Pointe de flèche pleine, pointe en `tip`, orientée vers `direction_deg`."""
    length = length or 2.0 * W
    width = width or 2.9 * W
    a = math.radians(direction_deg)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    bx, by = tip[0] - ux * length, tip[1] - uy * length
    pts = [tip, (bx + px * width / 2, by + py * width / 2), (bx - px * width / 2, by - py * width / 2)]
    return rpoly(pts, r)


def arrow(*pts, w=W, hl=None, hw=None):
    """Flèche : fût à bout rond, pointe pleine au dernier point."""
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
    hl = hl or 2.0 * w
    # le fût s'arrête sous la pointe pour ne pas la dépasser
    a = math.radians(ang)
    stop = (x1 - math.cos(a) * hl * 0.6, y1 - math.sin(a) * hl * 0.6)
    shaft = line(*pts[:-1], stop, w=w)
    return U(shaft, head((x1, y1), ang, length=hl, width=hw or 2.9 * w))


def arc_arrow(cx, cy, r, a0, a1, w=W, hl=None, hw=None):
    """Arc fléché de a0 vers a1 (degrés, sens écran)."""
    hl = hl or 2.0 * w
    sweep = a1 - a0
    sign = 1 if sweep > 0 else -1
    # la pointe consomme une part de l'arc
    da = math.degrees(hl / r) * sign
    body = arc(cx, cy, r, a0, a1 - da * 0.6, w=w)
    tip = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    base = (cx + r * math.cos(math.radians(a1 - da)), cy + r * math.sin(math.radians(a1 - da)))
    ang = math.degrees(math.atan2(tip[1] - base[1], tip[0] - base[0]))
    return U(body, head(tip, ang, length=hl, width=hw or 2.9 * w))


def dashes(p0, p1, n, w=W, fill=0.55):
    """n tirets à bouts ronds de p0 à p1 ; `fill` = part pleine."""
    out = []
    x0, y0 = p0
    x1, y1 = p1
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    pitch = L / (n - 1 + fill) if n > 1 else L
    seg = pitch * fill
    for i in range(n):
        s = i * pitch
        a = (x0 + ux * s, y0 + uy * s)
        b = (x0 + ux * (s + seg), y0 + uy * (s + seg))
        cap_len = w / 2
        # les bouts ronds débordent : on raccourcit d'autant
        a2 = (a[0] + ux * cap_len, a[1] + uy * cap_len)
        b2 = (b[0] - ux * cap_len, b[1] - uy * cap_len)
        if math.hypot(b2[0] - a2[0], b2[1] - a2[1]) < 0.01:
            out.append(disc(*a2, w / 2))
        else:
            out.append(line(a2, b2, w=w))
    return U(*out)


def marker(cx, cy, ro=8.5, ri=4.0):
    """Le repère de la marque : disque annelé."""
    return ring(cx, cy, ro, ri)


def bite(shape, cx, cy, ro=8.5):
    """La trace est mordue par le halo du repère."""
    return shape.difference(disc(cx, cy, ro + HALO))


def car_top(cx, cy, w=20, h=34, rot=0):
    """Voiture vue du dessus, avant en haut : caisse pleine, pare-brise et lunette évidés."""
    x, y = cx - w / 2, cy - h / 2
    body = rrect(x, y, w, h, min(7, w * 0.36))
    m = max(2.6, w * 0.16)
    ws_top, ws_bot = y + h * 0.22, y + h * 0.40
    windshield = rpoly([(x + m + 1.2, ws_top), (x + w - m - 1.2, ws_top), (x + w - m, ws_bot), (x + m, ws_bot)], 1.0)
    rw_top, rw_bot = y + h * 0.76, y + h * 0.87
    rear = rpoly([(x + m, rw_top), (x + w - m, rw_top), (x + w - m - 1.2, rw_bot), (x + m + 1.2, rw_bot)], 0.8)
    shape = body.difference(U(windshield, rear))
    if rot:
        shape = affinity.rotate(shape, rot, origin=(cx, cy))
    return shape


def car_side(x0=6, x1=58, base=46):
    """Voiture de profil, avant à droite."""
    lower = rrect(x0, base - 15, x1 - x0, 15, 5)
    cabin = rpoly([(x0 + 10, base - 13), (x0 + 16, base - 27), (x1 - 21, base - 27), (x1 - 11, base - 13)], 3)
    body = U(lower, cabin)
    win1 = rpoly([(x0 + 15.5, base - 15.5), (x0 + 19.5, base - 23.5), (x0 + 26.5, base - 23.5), (x0 + 26.5, base - 15.5)], 1.2)
    win2 = rpoly([(x0 + 30, base - 15.5), (x0 + 30, base - 23.5), (x1 - 23, base - 23.5), (x1 - 16.5, base - 15.5)], 1.2)
    body = body.difference(U(win1, win2))
    wr = 6.5
    w1, w2 = (x0 + 12.5, base), (x1 - 12.5, base)
    body = body.difference(U(disc(*w1, wr + G * 0.65), disc(*w2, wr + G * 0.65)))
    return U(body, disc(*w1, wr), disc(*w2, wr))


def tile(r=10, inset=8):
    return rrect(inset, inset, 64 - 2 * inset, 64 - 2 * inset, r)


def tri_up(cx=32, top=6, bottom=56, r=4):
    h = bottom - top
    half = h / math.sqrt(3)
    return rpoly([(cx, top), (cx + half, bottom), (cx - half, bottom)], r)


def tri_down(cx=32, top=8, bottom=58, r=4):
    h = bottom - top
    half = h / math.sqrt(3)
    return rpoly([(cx - half, top), (cx + half, top), (cx, bottom)], r)


def person(cx, top, scale=1.0, stride=1.0):
    """Piéton qui marche, vers la droite."""
    s = scale
    head_ = disc(cx + 1.5 * s, top + 4.2 * s, 4.2 * s)
    w = 5.2 * s
    torso = line((cx + 0.5 * s, top + 12 * s), (cx - 1.0 * s, top + 25 * s), w=w)
    arm = line((cx - 6 * s, top + 21 * s), (cx - 0.5 * s, top + 13.5 * s), (cx + 6.5 * s, top + 19 * s), w=w * 0.82)
    leg1 = line((cx - 1.0 * s, top + 25 * s), (cx + 5.5 * s * stride, top + 32 * s), (cx + 7 * s * stride, top + 40 * s), w=w * 0.9)
    leg2 = line((cx - 1.0 * s, top + 25 * s), (cx - 7.5 * s * stride, top + 39.5 * s), w=w * 0.9)
    return U(head_, torso, arm, leg1, leg2)


# ---------------------------------------------------------------- icônes
# Chaque fonction rend une géométrie shapely sur le canevas 64.

ICONS: dict[str, dict] = {}


def icon(key, title, *directions):
    ICONS[key] = {"title": title, "directions": directions}


def P(direction, name, idea, build, famille=None):
    return {"direction": direction, "name": name, "idea": idea, "build": build, "famille": famille}


# 1. Maîtrise du véhicule ------------------------------------------------------

def vehicle_A():
    # Tour 2 — défaut nommé : les roues encombraient. La voiture seule, braquée de 15°.
    return car_top(32, 32, 22, 42, rot=15)


def vehicle_B():
    t = tile()
    cabin = rpoly([(21, 18.5), (43, 18.5), (47.5, 31), (16.5, 31)], 3)
    lower = rrect(12.5, 29, 39, 14, 4)
    wheels = U(rrect(15.5, 39, 8, 9.5, 2.5), rrect(40.5, 39, 8, 9.5, 2.5))
    car = U(cabin, lower, wheels)
    shield = rpoly([(23.5, 22.5), (40.5, 22.5), (43.5, 29.5), (20.5, 29.5)], 1)
    lights = U(disc(19.5, 35.8, 2.7), disc(44.5, 35.8, 2.7))
    return U(t.difference(car), shield, lights)


def vehicle_C():
    cx, cy = 32, 32
    rim = ring(cx, cy, 25, 19)
    inner = disc(cx, cy, 19.5)
    plate = U(rrect(10, 30, 44, 7, 3.5), disc(cx, 34, 8.5), rrect(cx - 3.2, 34, 6.4, 22, 3.2)).intersection(inner)
    hub_hole = disc(cx, 34, 3)
    return U(rim, plate).difference(hub_hole)


def vehicle_D():
    return car_side(6, 58, 45)


def vehicle_E():
    pts = bezier((14, 56), (14, 28), (50, 38), (48, 14))
    tr = bite(line(*pts), 48, 14)
    return U(tr, marker(48, 14))


icon("vehicle", "Maîtrise du véhicule",
     P("A", "Volant braqué", "La voiture vue du dessus, braquée : diriger.", vehicle_A),
     P("B", "Face avant", "La face d'une voiture découpée dans un panneau carré.", vehicle_B),
     P("C", "Volant plein", "Un volant moderne à branche basse, en aplat et non en contour.", vehicle_C),
     P("D", "Profil", "Une voiture de profil, roues détachées par une contre-forme.", vehicle_D),
     P("E", "Trajectoire tenue", "Une trace en S maîtrisée qui finit sur un repère.", vehicle_E))


# 2. Observation et contrôles -------------------------------------------------

def observation_A():
    # Tour 2 — défaut nommé : les secteurs pleins se lisaient comme des ailes. Deux arcs de contrôle.
    car = car_top(32, 32, 18, 34)
    checks = []
    for sx in (-1, 1):
        ox, oy = 32, 30
        a0, a1 = (128, 158) if sx < 0 else (22, 52)
        checks.append(arc(ox, oy, 19, a0, a1, w=4.6))
        checks.append(arc(ox, oy, 26, a0 + 2, a1 - 2, w=4.6))
    return U(car, *checks).intersection(box(4, 4, 60, 60))


def _almond(cx, cy, a, b):
    R = (a * a + b * b) / (2 * b)
    d = R - b
    return disc(cx, cy + d, R).intersection(disc(cx, cy - d, R))


def observation_B():
    d = disc(32, 32, 26)
    eye = _almond(32, 32, 19, 11)
    return U(d.difference(eye), disc(32, 32, 6.5))


def observation_C():
    frame = rrect(7, 20, 50, 28, 12)
    inner = rrect(12.5, 25.5, 39, 17, 7)
    stem = rrect(29, 9, 6, 13, 3)
    road = U(line((22, 41), (29.5, 29), w=4.2), line((42, 41), (34.5, 29), w=4.2)).intersection(inner.buffer(-1.8))
    return U(frame.difference(inner), stem, road)


def observation_D():
    eye = _almond(32, 32, 27, 16)
    return U(eye.difference(disc(32, 32, 11.5)), disc(32, 32, 7))


def observation_E():
    a, b = 23, 13
    R = (a * a + b * b) / (2 * b)
    d = R - b
    half = math.degrees(math.asin(a / R))
    upper = arc(32, 32 + d, R, -90 - half, -90 + half)
    lower = arc(32, 32 - d, R, 90 - half, 90 + half)
    lids = bite(U(upper, lower), 32, 32, 9)
    return U(lids, marker(32, 32, 9, 4.2))


icon("observation", "Observation et contrôles",
     P("A", "Angles morts", "La voiture vue du dessus et les deux contrôles d'angle mort.", observation_A),
     P("B", "Œil sur disque", "Un œil découpé dans un disque plein, pupille posée au centre.", observation_B),
     P("C", "Rétroviseur", "Le rétroviseur intérieur qui reflète la route derrière soi.", observation_C),
     P("D", "Regard", "Un œil plein, iris évidé, pupille pleine : regarder.", observation_D),
     P("E", "Œil-repère", "Deux paupières en trace, le repère de la marque comme iris.", observation_E))


# 3. Priorité à droite --------------------------------------------------------

def right_priority_A():
    blocks = U(rrect(7, 7, 17, 17, 4.5), rrect(40, 7, 17, 17, 4.5), rrect(7, 40, 17, 17, 4.5), rrect(40, 40, 17, 17, 4.5))
    arr = arrow((57, 32), (33, 32), w=5, hl=9, hw=12)
    return U(blocks, arr)


def right_priority_B():
    outer = tri_up(32, 5, 57, 5)
    inner = outer.buffer(-W, join_style="round")
    cx, cy = 32, 40.5
    k = 8.5
    x = U(line((cx - k, cy - k), (cx + k, cy + k), w=5.6), line((cx - k, cy + k), (cx + k, cy - k), w=5.6))
    return U(outer.difference(inner), x)


def right_priority_C():
    passing = arrow((57, 22), (9, 22))
    waiting = arrow((32, 58), (32, 35))
    return U(passing, waiting)


def right_priority_D():
    # Tour 2 — défaut nommé : croix de pharmacie. Les branches sortent du cadre : ce sont des routes.
    cross = U(box(23, 0, 41, 64), box(0, 23, 64, 41))
    cross = cross.buffer(5, join_style="round").buffer(-5, join_style="round").intersection(box(5, 5, 59, 59))
    arr = arrow((55, 32), (33, 32), w=4.6, hl=8.5, hw=11)
    return cross.difference(arr.buffer(0.01))


def right_priority_E():
    passing = U(line((56, 22), (14, 22)), head((8, 22), 180))
    waiting = bite(line((32, 58), (32, 44)), 32, 38, 7.5)
    return U(passing, waiting, marker(32, 38, 7.5, 3.4))


icon("right-priority", "Priorité à droite",
     P("A", "Carrefour d'îlots", "Le carrefour dessiné par ses quatre îlots ; la voiture de droite entre.", right_priority_A),
     P("B", "Panneau croix", "Le triangle à croix de Saint-André du code, en anneau épais.", right_priority_B),
     P("C", "Deux flèches", "Celle de droite passe, la nôtre attend sous elle.", right_priority_C),
     P("D", "Carrefour plein", "Les routes du carrefour sortent du cadre ; la flèche de droite est évidée.", right_priority_D),
     P("E", "Trace qui attend", "Notre trace s'arrête sur un repère, l'autre traverse.", right_priority_E))


# 4. Signalisation -------------------------------------------------------------

def signage_A():
    edges = U(line((10, 6), (10, 58)), line((54, 6), (54, 58)))
    centre = dashes((32, 6), (32, 58), 4)
    painted = arrow((43, 54), (43, 14), w=4.6, hl=10, hw=10.5)
    return U(edges, centre, painted)


def signage_B():
    sign = ring(32, 23, 17.5, 10.5)
    post = rrect(29, 43, 6, 15, 3)
    base = rrect(22, 54, 20, 4.5, 2.25)
    return U(sign, post, base)


def signage_C():
    body = rrect(18, 5, 28, 49, 10)
    holes = U(*[disc(32, y, 6) for y in (17, 29.5, 42)])
    lit = disc(32, 17, 3.4)
    post = rrect(29, 54, 6, 5, 1.5)
    return U(body.difference(holes), lit, post)


def signage_D():
    panel = rpoly([(9, 12), (45, 12), (56, 23.5), (45, 35), (9, 35)], 3)
    text = rrect(15, 21, 22, 5, 2.5)
    post = rrect(14, 34, 6, 24, 3)
    return U(panel.difference(text), post)


def signage_E():
    t = tri_up(32, 5, 27, 2.5)
    c = disc(19.5, 44, 12)
    s = rrect(34, 33, 22, 22, 4)
    return U(t, c, s)


icon("signage", "Signalisation",
     P("A", "Marquage au sol", "La chaussée vue du dessus et sa flèche peinte.", signage_A),
     P("B", "Panneau rond", "Un panneau sur son mât, réduit à son anneau.", signage_B),
     P("C", "Feux tricolores", "Le feu, un seul œil allumé.", signage_C),
     P("D", "Panneau directionnel", "Une flèche-panneau pleine sur son mât, une ligne de texte évidée.", signage_D),
     P("E", "Trois formes", "Triangle, rond, carré : la grammaire des panneaux, sans aucun panneau.", signage_E))


# 5. Céder le passage -----------------------------------------------------------

def give_way_A():
    stop = dashes((8, 24), (56, 24), 4)
    painted = tri_down(32, 32, 50, 2)
    edges = U(line((10, 34), (10, 58)), line((54, 34), (54, 58)))
    return U(stop, painted, edges)


def give_way_B():
    outer = tri_down(32, 7, 58, 5)
    return outer.difference(outer.buffer(-7, join_style="round"))


def give_way_C():
    t = tri_down(32, 5, 31, 3)
    car = car_top(32, 47, 15, 22)
    return U(t, car)


def give_way_D():
    outer = tri_down(32, 6, 59, 5)
    ring_ = outer.difference(outer.buffer(-5.5, join_style="round"))
    core = outer.buffer(-5.5 - G, join_style="round")
    return U(ring_, core)


def give_way_E():
    stop = dashes((8, 18), (56, 18), 4)
    tr = bite(line((32, 58), (32, 42)), 32, 35.5, 7.5)
    return U(stop, tr, marker(32, 35.5, 7.5, 3.4))


icon("give-way", "Céder le passage",
     P("A", "Ligne et triangle", "La ligne pointillée et le triangle peint au débouché d'une rue.", give_way_A),
     P("B", "Triangle pointe en bas", "Le panneau du code : un anneau triangulaire épais, rien dedans.", give_way_B),
     P("C", "Devant le triangle", "Notre voiture s'arrête devant le triangle.", give_way_C),
     P("D", "Double triangle", "Le triangle plein, cerné par son propre liseré.", give_way_D),
     P("E", "Repère avant la ligne", "La trace s'arrête sur un repère avant la ligne pointillée.", give_way_E))


# 6. Intersections et giratoires ------------------------------------------------

def intersections_A():
    # Tour 3 — défaut nommé : le « Y » se lisait comme un visage. Quatre routes de biais qui sortent du
    # cadre, raccordées par des congés, autour d'un anneau de chaussée large : un giratoire de carte.
    cx, cy = 32, 32
    arms = [affinity.rotate(rrect(cx - 4.75, cy, 9.5, 40, 0), a, origin=(cx, cy)) for a in (20, 105, 200, 290)]
    road = U(disc(cx, cy, 20), *arms)
    road = road.buffer(4.5, join_style="round").buffer(-4.5, join_style="round").intersection(box(5, 5, 59, 59))
    return road.difference(disc(cx, cy, 10))


def intersections_B():
    d = disc(32, 32, 26.5)
    arrows = U(*[arc_arrow(32, 32, 14, a, a - 88, w=4.6, hl=7.5, hw=11) for a in (100, 220, 340)])
    return d.difference(arrows)


def intersections_C():
    straight = arrow((22, 58), (22, 10))
    turn = U(line((42, 58), (42, 36)), line(*arc_pts(54, 36, 12, 180, 270, 32)),)
    turn = U(line((42, 58), (42, 36)), line(*arc_pts(56, 36, 14, 180, 245, 32)),
             head((56 + 14 * math.cos(math.radians(270)), 36 + 14 * math.sin(math.radians(270))), 0))
    return U(straight, turn)


def intersections_D():
    return U(*[arc_arrow(32, 32, 19, a, a - 92, w=W, hl=11, hw=16) for a in (100, 220, 340)])


def intersections_E():
    # Tour 2 — défaut nommé : se lisait « P ». L'anneau entier en trace, trois branches, le repère au centre.
    cx, cy, r = 32, 32, 16
    loop = ring(cx, cy, r + W / 2, r - W / 2)
    stubs = U(*[line((cx + (r + 2) * math.cos(math.radians(a)), cy + (r + 2) * math.sin(math.radians(a))),
                     (cx + 27 * math.cos(math.radians(a)), cy + 27 * math.sin(math.radians(a)))) for a in (90, 210, 330)])
    return U(loop, stubs, marker(cx, cy, 6.5, 2.8))


icon("intersections", "Intersections et giratoires",
     P("A", "Giratoire en plan", "L'anneau du giratoire et ses quatre branches, vus de la carte.", intersections_A),
     P("B", "Panneau giratoire", "Le disque du code, trois flèches tournantes évidées.", intersections_B),
     P("C", "Choix de voie", "Deux flèches au sol : tout droit ou tourner.", intersections_C),
     P("D", "Trois flèches", "Trois flèches pleines qui tournent : le sens giratoire.", intersections_D),
     P("E", "Le repère comme îlot", "L'anneau en trace, trois branches, le repère comme îlot central.", intersections_E))


# 7. Adaptation de la vitesse ---------------------------------------------------

def speed_A():
    front = car_top(32, 14, 15, 22)
    back = car_top(32, 50, 15, 22)
    gap = U(line((50, 26.5), (50, 37.5), w=4), line((46, 26.5), (54, 26.5), w=4), line((46, 37.5), (54, 37.5), w=4))
    return U(front, back, gap)


def speed_B():
    sign = ring(32, 32, 26.5, 20)
    sw = 4.4
    five = U(line((19.5, 23), (28, 23), w=sw), line((19.5, 23), (19, 30.5), w=sw),
             line(*arc_pts(23.5, 35.5, 5.8, -125, 130, 48), w=sw))
    zero = rrect(33, 20.8, 12, 22.4, 6).difference(rrect(33 + sw, 20.8 + sw, 12 - 2 * sw, 22.4 - 2 * sw, 6 - sw))
    return U(sign, five, zero)


def speed_C():
    cx, cy = 32, 35
    dial = arc(cx, cy, 23, 150, 390)
    needle = line((cx, cy), (cx + 15 * math.cos(math.radians(-50)), cy + 15 * math.sin(math.radians(-50))), w=5.2)
    return U(dial, needle, disc(cx, cy, 5.5))


def speed_D():
    cx, cy = 32, 38
    face = disc(cx, cy, 26).intersection(box(0, 0, 64, 51))
    face = face.buffer(-3, join_style="round").buffer(3, join_style="round")
    ticks = U(*[line((cx + 21 * math.cos(math.radians(a)), cy + 21 * math.sin(math.radians(a))),
                     (cx + 16.5 * math.cos(math.radians(a)), cy + 16.5 * math.sin(math.radians(a))), w=3.6)
                for a in (-170, -135, -90, -45, -10)])
    tip = (cx + 17 * math.cos(math.radians(-55)), cy + 17 * math.sin(math.radians(-55)))
    needle = U(line((cx, cy), tip, w=4.2), disc(cx, cy, 5.2))
    return face.difference(U(ticks, needle.buffer(G * 0.55)))


def speed_E():
    # Tour 2 — défaut nommé : trop léger. La trace monte en diagonale et ses traits raccourcissent jusqu'au repère.
    a = math.radians(-35)
    ux, uy = math.cos(a), math.sin(a)
    o = (7, 50)
    def at(t):
        return (o[0] + ux * t, o[1] + uy * t)
    parts = [line(at(s0 + W / 2), at(s1 - W / 2)) for s0, s1 in ((0, 19), (24, 36), (41, 49))]
    mx, my = at(56.5)
    return U(*parts, marker(mx, my, 7.5, 3.4))


icon("speed", "Adaptation de la vitesse",
     P("A", "Distance de sécurité", "Deux voitures dans la voie et l'écart entre elles.", speed_A),
     P("B", "Limitation", "Le panneau rond de limitation, chiffres dessinés.", speed_B),
     P("C", "Compteur", "Un cadran ouvert, une aiguille, un moyeu : en aplat.", speed_C),
     P("D", "Cadran plein", "Un cadran plein dont l'aiguille et les graduations sont évidées.", speed_D),
     P("E", "Trace qui ralentit", "Les traits de la trace raccourcissent jusqu'au repère.", speed_E))


# 8. Placement sur la chaussée ---------------------------------------------------

def placement_A():
    left = dashes((11, 6), (11, 58), 4)
    right = line((53, 6), (53, 58))
    return U(left, right, car_top(32, 32, 20, 36))


def placement_B():
    t = tile()
    lanes = U(arrow((22.5, 48), (22.5, 16), w=5, hl=8.5, hw=12), arrow((41.5, 48), (41.5, 16), w=5, hl=8.5, hw=12))
    sep = dashes((32, 15), (32, 49), 3, w=3.2)
    return t.difference(U(lanes, sep))


def placement_C():
    k = 11
    corners = U(line((8, 8 + k), (8, 8), (8 + k, 8), w=5), line((56 - k, 8), (56, 8), (56, 8 + k), w=5),
                line((8, 56 - k), (8, 56), (8 + k, 56), w=5), line((56 - k, 56), (56, 56), (56, 56 - k), w=5))
    return U(corners, car_top(32, 32, 17, 30))


def placement_D():
    # Tour 2 — défaut nommé : se lisait « A ». Haut élargi, axe en trois tirets francs.
    road = rpoly([(20, 7), (44, 7), (58, 57), (6, 57)], 3)
    centre = U(rpoly([(30.8, 11), (33.2, 11), (33.8, 19), (30.2, 19)], 0.6),
               rpoly([(30.0, 25), (34.0, 25), (34.9, 36), (29.1, 36)], 0.8),
               rpoly([(28.8, 43), (35.2, 43), (36.2, 57.5), (27.8, 57.5)], 1.0))
    return road.difference(centre)


def placement_E():
    cx, cy = 60, 60
    outer = arc(cx, cy, 50, 180, 270)
    inner = arc(cx, cy, 20, 180, 270)
    a = math.radians(225)
    mx, my = cx + 35 * math.cos(a), cy + 35 * math.sin(a)
    return U(outer, inner, marker(mx, my, 7.5, 3.4)).intersection(box(4, 4, 60, 60))


icon("placement", "Placement sur la chaussée",
     P("A", "Dans sa voie", "La voiture vue du dessus, centrée entre ligne pointillée et ligne continue.", placement_A),
     P("B", "Panneau de voies", "Deux voies fléchées découpées dans un panneau carré.", placement_B),
     P("C", "Cadrage", "La voiture tenue dans quatre équerres : bien placée.", placement_C),
     P("D", "Chaussée en perspective", "La route qui file, son axe en tirets évidés.", placement_D),
     P("E", "Virage", "Un virage et le repère tenu au milieu de la voie.", placement_E))


# 9. Manœuvres --------------------------------------------------------------------

def manoeuvres_A():
    bay = line((14, 26), (14, 56), (50, 56), (50, 26))
    car = car_top(32, 37.5, 17, 25)
    back = arrow((32, 4), (32, 19), w=5, hl=7.5, hw=11)
    car = car.difference(back.buffer(G * 0.6))
    return U(bay, car.difference(bay.buffer(G * 0.6)), back)


def manoeuvres_B():
    t = tile()
    stem = rrect(23, 16, 7, 33, 2)
    bowl = U(rrect(23, 16, 14, 20, 2), disc(36.5, 26, 10))
    hole = U(rrect(30, 22.5, 6.5, 7, 0), disc(36.5, 26, 3.5))
    p = U(stem, bowl).difference(hole)
    return t.difference(p)


def manoeuvres_C():
    car = car_top(32, 22, 18, 30)
    waves = U(*[arc(32, 34, r, 58, 122, w=4.4) for r in (12.5, 19, 25.5)]).difference(disc(32, 34, 11))
    waves = waves.intersection(box(0, 39, 64, 64))
    return U(car, waves)


def manoeuvres_D():
    return U(line((20, 58), (20, 27)), line(*arc_pts(32, 27, 12, 180, 360, 64)),
             arrow((44, 27), (44, 44), hl=11, hw=17))


def manoeuvres_E():
    bay = line((30, 30), (30, 57), (57, 57), (57, 30))
    pts = bezier((7, 7), (30, 7), (43.5, 18), (43.5, 38))
    tr = bite(line(*pts), 43.5, 43, 7)
    return U(bay, tr, marker(43.5, 43, 7, 3.2))


icon("manoeuvres", "Manœuvres",
     P("A", "Créneau en plan", "La place vue du dessus, la voiture y recule.", manoeuvres_A),
     P("B", "P", "Le P du stationnement, dessiné et découpé dans le panneau.", manoeuvres_B),
     P("C", "Radar de recul", "La voiture et les ondes de l'aide au recul.", manoeuvres_C),
     P("D", "Demi-tour", "La flèche du demi-tour, en aplat.", manoeuvres_D),
     P("E", "Trace qui se gare", "La trace entre dans la place et s'y pose.", manoeuvres_E))


# 10. Autoroute --------------------------------------------------------------------

def motorway_A():
    main = U(line((12, 6), (12, 58)), line((36, 6), (36, 58)))
    centre = dashes((24, 6), (24, 58), 4, w=4)
    ramp = line(*bezier((58, 58), (58, 40), (36, 40), (36, 22)))
    ramp = ramp.difference(box(0, 0, 64, 22))
    return U(main, centre, ramp)


def motorway_B():
    t = tile()
    bridge = rrect(13, 24, 38, 6, 3)
    left = line((17, 50), (27.5, 25), w=5)
    right = line((47, 50), (36.5, 25), w=5)
    lanes = U(left, right).difference(bridge.buffer(G * 0.7))
    centre = line((32, 49), (32, 38), w=3)
    return t.difference(U(bridge, lanes, centre))


def motorway_C():
    left = line((8, 57), (26, 8))
    right = line((56, 57), (38, 8))
    centre = U(rpoly([(31.2, 8), (32.8, 8), (33.2, 15), (30.8, 15)], 0.6),
               rpoly([(30.4, 22), (33.6, 22), (34.3, 33), (29.7, 33)], 0.8),
               rpoly([(29.3, 41), (34.7, 41), (35.7, 57.5), (28.3, 57.5)], 1.0))
    return U(left, right, centre)


def motorway_D():
    deck = rrect(5, 15, 54, 9, 3)
    road = rpoly([(26, 24), (38, 24), (55, 58), (9, 58)], 2.5)
    road = road.difference(deck.buffer(G * 0.8))
    centre = rpoly([(30.6, 37), (33.4, 37), (34.2, 52), (29.8, 52)], 0.8)
    return U(deck, road.difference(centre.buffer(0.01)))


def motorway_E():
    main = line((24, 58), (24, 6))
    ramp = line(*bezier((52, 58), (52, 38), (24, 40), (24, 24)))
    tr = bite(U(main, ramp), 24, 20, 7.5)
    return U(tr, marker(24, 20, 7.5, 3.4))


icon("motorway", "Autoroute",
     P("A", "Insertion", "La bretelle d'insertion rejoint la chaussée, vue du dessus.", motorway_A),
     P("B", "Panneau autoroute", "Le pictogramme du code — chaussée et pont — découpé dans le carré.", motorway_B),
     P("C", "Grande route", "Deux bords qui fuient et l'axe en tirets qui grandit.", motorway_C),
     P("D", "Passage sous le pont", "La chaussée pleine qui passe sous le tablier.", motorway_D),
     P("E", "Deux traces qui se rejoignent", "La trace de la bretelle rejoint l'autre au repère.", motorway_E))


# 11. Anticipation ----------------------------------------------------------------

def anticipation_A():
    zebra = U(*[rrect(x, 6, 6, 15, 2) for x in (9, 20, 31, 42, 53)]).intersection(box(6, 0, 58, 64))
    car = car_top(32, 43, 17, 28)
    return U(zebra, car)


def anticipation_B():
    outer = tri_up(32, 4, 57, 5)
    inner = outer.buffer(-5.5, join_style="round")
    p = person(31.5, 21, 0.75)
    return U(outer.difference(inner), p)


def anticipation_C():
    return person(31, 6, 1.28)


def anticipation_D():
    cx, cy, r = 32, 40, 10.5
    wheels = U(ring(14.5, 42, 10.5, 6.2), ring(49.5, 42, 10.5, 6.2))
    frame = line((14.5, 42), (25, 25), (43, 25), (49.5, 42), w=4.2)
    frame = U(frame, line((25, 25), (31.5, 42), (43, 25), w=4.2), line((14.5, 42), (31.5, 42), w=4.2))
    seat = line((21, 19), (28, 19), w=4.2)
    bar = line((40, 18), (43, 25), w=4.2)
    hb = line((37, 17.5), (44, 17.5), w=4.2)
    return U(wheels, frame, seat, bar, hb, line((24, 21), (25, 25), w=4.2))


def anticipation_E():
    # Tour 2 — défaut nommé : se lisait « wifi ». La trace s'écarte à temps d'un repère sur sa route.
    pts = bezier((40, 58), (40, 40), (52, 36), (52, 24)) + bezier((52, 24), (52, 14), (44, 8), (40, 6))[1:]
    tr = line(*pts)
    return U(tr, marker(28, 26, 8.5, 4))


icon("anticipation", "Anticipation",
     P("A", "Passage piéton", "La voiture approche d'un passage piéton, vu du dessus.", anticipation_A),
     P("B", "Panneau piétons", "Le triangle de danger, un piéton dedans.", anticipation_B),
     P("C", "Piéton", "Un piéton qui avance : la personne qu'on anticipe.", anticipation_C),
     P("D", "Cycliste", "Le vélo, l'usager qu'on ne voit pas venir.", anticipation_D),
     P("E", "Trace qui s'écarte", "La trace s'écarte à temps de ce qu'elle a vu venir.", anticipation_E))


# 12. Marquer un moment -------------------------------------------------------------

def marker_A():
    return rpoly([(17, 7), (47, 7), (47, 57), (32, 45.5), (17, 57)], 3.5)


def marker_B():
    pole = rrect(15, 7, 6, 51, 3)
    flag = rpoly([(19, 9), (51, 9), (43, 21), (51, 33), (19, 33)], 2.5)
    return U(pole, flag)


def marker_C():
    face = ring(32, 36, 21, 15)
    crown = U(rrect(27, 6, 10, 5.5, 2.5), rrect(29.5, 9, 5, 7, 1.5))
    hand = line((32, 36), (32, 25), w=4.4)
    lap = rpoly([(32, 36), (32 + 14.5 * math.cos(math.radians(-90)), 36 + 14.5 * math.sin(math.radians(-90)))]
                + arc_pts(32, 36, 14.5, -90, -20, 24), 0.8)
    return U(face, crown, lap, disc(32, 36, 3))


def marker_D():
    cx, cy, r = 32, 25, 18
    t = 45
    tip = (32, 58)
    side = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in (180 - 40, 40)]
    pin = U(disc(cx, cy, r), rpoly([tip, side[1], (cx, cy), side[0]], 2.5))
    return pin.difference(disc(cx, cy, 7))


def marker_E():
    tr = bite(line((6, 32), (58, 32)), 32, 32, 11)
    return U(tr, marker(32, 32, 11, 5.2))


icon("marker", "Marquer un moment",
     P("A", "Signet", "Le signet plein : on revient à cette page de la leçon.", marker_A),
     P("B", "Fanion", "Un fanion planté : ici, quelque chose à revoir.", marker_B),
     P("C", "Chronomètre", "Le chronomètre qui marque un tour : un instant précis.", marker_C),
     P("D", "Épingle", "L'épingle de carte, évidée : un lieu à retrouver.", marker_D),
     P("E", "Repère sur la trace", "Les deux primitives de Drivy : un repère posé sur la trace.", marker_E))


# 13–15. Appréciations ----------------------------------------------------------------

def bang(cx=32, top=10, bottom=40, dot=52, w=8, r=5):
    return U(line((cx, top), (cx, bottom), w=w), disc(cx, dot, r))


def check(w=8, s=1.0, cx=32, cy=32):
    pts = [(-17, 1), (-5.5, 12.5), (18.5, -11.5)]
    return line(*[(cx + x * s, cy + y * s) for x, y in pts], w=w)


def cross(w=8, k=15, cx=32, cy=32):
    return U(line((cx - k, cy - k), (cx + k, cy + k), w=w), line((cx - k, cy + k), (cx + k, cy - k), w=w))


def redo(cx=32, cy=32, r=16, w=7):
    return arc_arrow(cx, cy, r, -50, 235, w=w, hl=10, hw=17)


icon("status-attention", "Attention",
     P("A", "Point d'exclamation", "Un « ! » plein, trait et point de même graisse.", lambda: bang()),
     P("B", "Pastille", "Le « ! » évidé dans un disque.", lambda: disc(32, 32, 26).difference(bang(32, 17, 36, 46, 7, 4.2))),
     P("C", "Triangle", "Le triangle de danger, « ! » évidé : forme et couleur disent la même chose.",
       lambda: tri_up(32, 5, 58, 5).difference(bang(32, 24, 40, 49, 6, 3.6))),
     P("D", "Losange", "Un losange plein, « ! » évidé : distinct du danger.",
       lambda: affinity.rotate(rrect(13, 13, 38, 38, 6), 45, origin=(32, 32)).difference(bang(32, 20, 36, 45, 6, 3.6))),
     P("E", "Trace et repère", "Le trait est une trace, le point est le repère.",
       lambda: U(line((32, 8), (32, 33)), marker(32, 49, 7.5, 3.4))))


icon("status-rework", "À retravailler",
     P("A", "Croix", "Une croix pleine : ce qui n'allait pas.", lambda: cross()),
     P("B", "Croix en pastille", "La croix évidée dans un disque.", lambda: disc(32, 32, 26).difference(cross(6.5, 9.5))),
     P("C", "À reprendre", "Une flèche qui revient sur elle-même : on le refera.", lambda: redo()),
     P("D", "Reprendre en pastille", "La flèche de reprise évidée dans un disque.",
       lambda: disc(32, 32, 26).difference(redo(32, 32, 11.5, 5.2))),
     P("E", "Trace qui boucle", "La trace repasse sur elle-même.",
       lambda: line(*(bezier((6, 44), (26, 44), (40, 40), (40, 26)) + bezier((40, 26), (40, 12), (22, 12), (22, 26))[1:]
                      + bezier((22, 26), (22, 40), (36, 44), (58, 44))[1:]))))


icon("status-positive", "Point positif",
     P("A", "Coche", "Une coche pleine, branche courte et branche longue.", lambda: check()),
     P("B", "Coche en pastille", "La coche évidée dans un disque.", lambda: disc(32, 32, 26).difference(check(6.5, 0.72))),
     P("C", "Coche en carré", "La coche évidée dans un carré arrondi.", lambda: rrect(8, 8, 48, 48, 12).difference(check(6.5, 0.74))),
     P("D", "Un plus", "Un « + » plein : ce qui s'ajoute.", lambda: U(line((32, 12), (32, 52), w=8), line((12, 32), (52, 32), w=8))),
     P("E", "Coche-trace", "La coche est une trace qui finit sur un repère.",
       lambda: U(bite(line((8, 34), (22, 48), (46, 22)), 50, 17.5, 7), marker(50, 17.5, 7, 3.2))))


# ---------------------------------------------------------------- reprise du 12 octobre
# Le porteur a demandé de revoir « Priorité à droite » et « Intersections et giratoires ». Cinq nouvelles
# études chacune, dans le langage des pictogrammes de manœuvre des applications de navigation : la route
# en second calque (35 %), le geste en trait plein.

def crossroads(arm=16, r=3):
    road = U(rrect(32 - arm / 2, 3, arm, 58, r), rrect(3, 32 - arm / 2, 58, arm, r))
    return road.buffer(4, join_style="round").buffer(-4, join_style="round")


def _behind(secondary, primary, gap=2.2):
    return secondary.difference(primary.buffer(gap))


def car_outline(cx, cy, w, h, rot=0):
    body = rrect(cx - w / 2, cy - h / 2, w, h, min(6, w * 0.36))
    hollow = body.difference(body.buffer(-3.2, join_style="round"))
    shield = rrect(cx - w / 2 + 2.5, cy - h / 2 + h * 0.24, w - 5, 3.2, 1.6)
    g = U(hollow, shield)
    return affinity.rotate(g, rot, origin=(cx, cy)) if rot else g


def rp_F():
    primary = U(arrow((58, 32), (11, 32)), line((32, 58), (32, 46.5)), line((25, 43), (39, 43), w=4.6))
    return primary, _behind(crossroads(), primary)


def rp_G():
    # Tour 2 — défaut nommé : voitures qui se touchent. (Rotation −90 vérifiée par calcul : pare-brise
    # à gauche ; vu du dessus, le sens d'une voiture reste pourtant illisible en petit.)
    right = car_top(47, 29, 14, 23, rot=-90)
    ours = car_outline(29, 50, 13, 20)
    primary = U(right, ours)
    return primary, _behind(crossroads(16), primary, 2.6)


def rp_H():
    outer = tri_up(32, 3.5, 58.5, 5.5)
    inner = outer.buffer(-6.4, join_style="round")
    cx, cy, k = 32, 40, 9.2
    x = U(line((cx - k, cy - k), (cx + k, cy + k), w=6), line((cx - k, cy + k), (cx + k, cy - k), w=6))
    return U(outer.difference(inner), x)


def rp_I():
    # Finition de la retenue : réduite à l'export (×0,78), elle perdait sa graisse. Bordures et flèche
    # épaissies pour retrouver l'épaisseur 6 de la famille une fois en place.
    kerbs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            a = (32 + sx * 11.5, 32 + sy * 27)
            b = (32 + sx * 11.5, 32 + sy * 16)
            c = (32 + sx * 16, 32 + sy * 11.5)
            d = (32 + sx * 27, 32 + sy * 11.5)
            kerbs.append(line(a, b, c, d, w=7))
    arr = arrow((60, 32), (28, 32), w=7.5, hl=12.5, hw=18.5)
    return U(*kerbs, arr)


def rp_J():
    # Rotation −90 vérifiée par calcul : pare-brise à gauche. Le sens reste illisible en petit.
    right = car_top(44, 32, 15, 25, rot=-90)
    bar = line((25, 46), (39, 46), w=4.6)
    primary = U(right, bar)
    return primary, _behind(crossroads(), primary)


icon("right-priority-v2", "Priorité à droite — reprise",
     P("F", "Manœuvre", "Le carrefour en second plan ; celui de droite traverse, notre voie s'arrête à la ligne.", rp_F, "Manœuvre"),
     P("G", "Plein et creux", "Au carrefour, la voiture de droite est pleine, la nôtre creuse : elle cède.", rp_G, "Plan"),
     P("H", "AB1 redessiné", "Le panneau du code, anneau plus épais et croix agrandie, centrée optiquement.", rp_H, "Panneau"),
     P("I", "Bordures", "Le carrefour dit par ses quatre bordures ; la flèche entre par la droite.", rp_I, "Plan"),
     P("J", "Elle arrive, on s'arrête", "La voiture de droite entre dans le carrefour, une ligne d'arrêt de notre côté.", rp_J, "Manœuvre"))


def it_F():
    # Tour 2 — défaut nommé : second plan chargé. Seul l'anneau de chaussée reste derrière le trajet.
    cx, cy, r = 32, 32, 13
    path = U(line((cx, 59), (cx, cy + r)), line(*arc_pts(cx, cy, r, 90, -90, 96)),
             arrow((cx, cy - r), (cx, 5), hl=11, hw=16))
    return path, _behind(ring(cx, cy, r + 4, r - 4), path)


def it_G():
    # Tour 2 — défaut nommé : se lisait « rafraîchir ». Trois branches de route en second plan.
    island = disc(32, 32, 8.5)
    loop = arc_arrow(32, 32, 19.5, 110, -190, w=6, hl=11, hw=16)
    primary = U(island, loop)
    stubs = U(*[affinity.rotate(rrect(28, 2, 8, 14, 3), a, origin=(32, 32)) for a in (0, 120, 240)])
    return primary, _behind(stubs, primary)


def it_H():
    # Tour 2 — défaut nommé : la sortie en biais faisait le symbole ♂. Sortie droite vers le haut,
    # anneau fin d'une seule couleur pour la moitié qu'on ne parcourt pas.
    # Finition de la retenue : anneau élargi et trajet plus gras, pour la même présence que la famille.
    cx, cy, r = 32, 33, 15
    path = U(line((cx, 61), (cx, cy + r), w=7), line(*arc_pts(cx, cy, r, 90, -90, 96), w=7),
             arrow((cx, cy - r), (cx, 3), w=7, hl=12, hw=18))
    thin = ring(cx, cy, r + 2.2, r - 2.2)
    return U(path, thin.difference(path.buffer(2.6)))


def it_I():
    cx, cy = 32, 32
    island = disc(cx, cy, 7)
    loop = arc_arrow(cx, cy, 15.5, 135, -150, w=5.6, hl=10, hw=14)
    arms = U(*[affinity.rotate(rrect(cx - 5, 2, 10, 16, 3), a, origin=(cx, cy)) for a in (0, 90, 180, 270)])
    road = U(ring(cx, cy, 20, 11), arms).intersection(box(3, 3, 61, 61))
    primary = U(island, loop)
    return primary, _behind(road, primary)


def it_J():
    turn = U(line((28, 59), (28, 41)), line(*arc_pts(42, 41, 14, 180, 270, 48)),
             arrow((42, 27), (58, 27), hl=10, hw=15))
    return turn, _behind(crossroads(18), turn)


icon("intersections-v2", "Intersections et giratoires — reprise",
     P("F", "Traverser le giratoire", "Comme une consigne de navigation : on entre en bas, on tourne, on sort en haut.", it_F, "Manœuvre"),
     P("G", "Îlot et sens giratoire", "L'îlot plein et une seule flèche qui en fait le tour : le giratoire, sans les trois flèches.", it_G, "Silhouette"),
     P("H", "Sortie du giratoire", "L'anneau fin, le trajet épais qui en sort : une consigne de navigation, d'une couleur.", it_H, "Manœuvre"),
     P("I", "Giratoire en plan", "Les branches et l'anneau en second plan, l'îlot et le sens de rotation au premier.", it_I, "Plan"),
     P("J", "Tourner au carrefour", "Le carrefour en second plan, le virage à droite en trait plein.", it_J, "Manœuvre"))


# ---------------------------------------------------------------- reprise 2 du 12 octobre
# Le porteur garde la priorité à droite (bordures) et refuse encore le giratoire. Le giratoire devient
# son jumeau : mêmes bordures (7), mêmes branches (±11,5), même flèche (7,5), même emprise ; seules
# les bordures s'arrondissent autour d'un îlot.

KERB, ARM, REACH = 7.0, 11.5, 27.0


def roundabout_kerbs(R=22.5):
    """Quatre bordures : droites le long des branches, courbes autour de l'anneau."""
    t = math.degrees(math.asin(ARM / R))
    kerbs = []
    for q in range(4):
        base = -90 + 90 * q            # quart entre deux branches
        a0, a1 = base + t, base + 90 - t
        start = (32 + R * math.cos(math.radians(a0)), 32 + R * math.sin(math.radians(a0)))
        end = (32 + R * math.cos(math.radians(a1)), 32 + R * math.sin(math.radians(a1)))
        ux0, uy0 = math.cos(math.radians(base)), math.sin(math.radians(base))
        ux1, uy1 = math.cos(math.radians(base + 90)), math.sin(math.radians(base + 90))
        lead = (start[0] + ux0 * (REACH - math.sqrt(R * R - ARM * ARM)), start[1] + uy0 * (REACH - math.sqrt(R * R - ARM * ARM)))
        tail = (end[0] + ux1 * (REACH - math.sqrt(R * R - ARM * ARM)), end[1] + uy1 * (REACH - math.sqrt(R * R - ARM * ARM)))
        kerbs.append(line(lead, *arc_pts(32, 32, R, a0, a1, 48), tail, w=KERB))
    return U(*kerbs)


def it3_K():
    island = disc(32, 32, 6.5)
    loop = arc_arrow(32, 32, 13.5, 45, -225, w=6.5, hl=10, hw=15)
    return U(roundabout_kerbs(), island, loop)


def it3_L():
    island = disc(32, 32, 9)
    return U(roundabout_kerbs(), island)


def it3_M():
    island = disc(32, 32, 6.5)
    entry = line((32, 61), (32 + 0, 32 + 13.5))
    path = U(entry, line(*arc_pts(32, 32, 13.5, 90, -90 + 12, 96), w=6.5))
    exit_ = arrow((32 + 13.5 * math.cos(math.radians(-90)), 32 + 13.5 * math.sin(math.radians(-90))), (32, 3), w=6.5, hl=10, hw=15)
    return U(roundabout_kerbs(), island, path.difference(disc(32, 32, 9.5)), exit_)


def it3_N():
    island = disc(32, 32, 6.5)
    arrows = U(*[arc_arrow(32, 32, 13.5, a, a - 95, w=6, hl=8.5, hw=13) for a in (135, 15, -105)])
    return U(roundabout_kerbs(), island, arrows)


def it3_O():
    island = ring(32, 32, 9, 4)
    loop = arc_arrow(32, 32, 15.5, 60, -210, w=6.5, hl=10, hw=15)
    return U(roundabout_kerbs(24.5), island, loop)


icon("intersections-v3", "Intersections et giratoires — reprise 2",
     P("K", "Jumeau, flèche autour", "Les bordures de la priorité à droite s'arrondissent ; une flèche fait le tour de l'îlot.", it3_K, "Bordures"),
     P("L", "Jumeau, îlot seul", "Le giratoire dit seulement par ses bordures courbes et son îlot plein.", it3_L, "Bordures"),
     P("M", "Jumeau, traversée", "On entre en bas, on contourne l'îlot par la droite, on sort en haut.", it3_M, "Bordures"),
     P("N", "Jumeau, trois flèches", "Les trois flèches du panneau giratoire, posées dans l'anneau des bordures.", it3_N, "Bordures"),
     P("O", "Jumeau, îlot-repère", "L'îlot devient le repère annelé de Drivy, la flèche en fait le tour.", it3_O, "Bordures"))


# ---------------------------------------------------------------- reprise 3 du 12 octobre
# Bordures courbes (v3) : quatre larges branches ne laissent presque rien de l'anneau, l'ensemble se lit
# engrenage. On garde au trait près les bordures droites de la priorité à droite ; seul le centre du
# carrefour change : un îlot et le sens giratoire. La différence se joue là où l'œil tombe.

def straight_kerbs():
    kerbs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            kerbs.append(line((32 + sx * 11.5, 32 + sy * 27), (32 + sx * 11.5, 32 + sy * 16),
                              (32 + sx * 16, 32 + sy * 11.5), (32 + sx * 27, 32 + sy * 11.5), w=7))
    return U(*kerbs)


def it4_P():
    return U(straight_kerbs(), disc(32, 32, 4.5), arc_arrow(32, 32, 10, 80, -180, w=5.5, hl=8, hw=12.5))


def it4_Q():
    return U(straight_kerbs(), disc(32, 32, 8))


def it4_R():
    return U(straight_kerbs(), arc_arrow(32, 32, 9.5, 80, -180, w=6, hl=8.5, hw=13))


def it4_S():
    kerbs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = 32 + sx * 19.5, 32 + sy * 19.5
            a_mid = math.degrees(math.atan2(-sy, -sx))
            kerbs.append(line((32 + sx * 11.5, 32 + sy * 27), (32 + sx * 11.5, 32 + sy * 19.5),
                              *arc_pts(cx, cy, 8, a_mid - 45 if sx * sy > 0 else a_mid + 45,
                                       a_mid + 45 if sx * sy > 0 else a_mid - 45, 24),
                              (32 + sx * 19.5, 32 + sy * 11.5), (32 + sx * 27, 32 + sy * 11.5), w=7))
    return U(*kerbs, disc(32, 32, 4.5), arc_arrow(32, 32, 10, 80, -180, w=5.5, hl=8, hw=12.5))


def it4_T():
    r = 10
    a0 = 18
    p0 = (32 + r * math.cos(math.radians(a0)), 32 + r * math.sin(math.radians(a0)))
    entry = line((60, p0[1]), (p0[0] + 2, p0[1]), w=5.5)
    around = arc_arrow(32, 32, r, a0, -170, w=5.5, hl=8, hw=12.5)
    return U(straight_kerbs(), disc(32, 32, 4.5), entry, around)


icon("intersections-v4", "Intersections et giratoires — reprise 3",
     P("P", "Carrefour giratoire", "Les bordures de la priorité à droite, au trait près ; au centre, un îlot et le sens giratoire.", it4_P, "Jumeau"),
     P("Q", "Carrefour à îlot", "Les mêmes bordures, un îlot plein au centre, sans flèche.", it4_Q, "Jumeau"),
     P("R", "Carrefour tournant", "Les mêmes bordures, une flèche qui tourne au centre, sans îlot.", it4_R, "Jumeau"),
     P("S", "Entrées arrondies", "Bordures aux angles arrondis, comme les entrées d'un giratoire ; îlot et sens giratoire.", it4_S, "Jumeau"),
     P("T", "Celle de droite contourne", "La flèche vient de droite comme dans la priorité à droite, mais elle contourne l'îlot.", it4_T, "Jumeau"))


# ---------------------------------------------------------------- reprise 4 du 12 octobre
# Les bordures droites laissent un centre trop petit (îlot et flèche deviennent une spirale). Ce qui dit
# « giratoire », c'est l'anneau autour de l'îlot : il doit l'emporter sur les ouvertures. Même grammaire
# de bordures que la priorité à droite (épaisseur 7, emprise ±27), branches plus étroites pour que les
# arcs dominent.

def ring_kerbs(arm, R, reach=27.0):
    t = math.degrees(math.asin(arm / R))
    lead = reach - math.sqrt(R * R - arm * arm)
    out = []
    for q in range(4):
        base = -90 + 90 * q
        a0, a1 = base + t, base + 90 - t
        p0 = (32 + R * math.cos(math.radians(a0)), 32 + R * math.sin(math.radians(a0)))
        p1 = (32 + R * math.cos(math.radians(a1)), 32 + R * math.sin(math.radians(a1)))
        u0 = (math.cos(math.radians(base)), math.sin(math.radians(base)))
        u1 = (math.cos(math.radians(base + 90)), math.sin(math.radians(base + 90)))
        out.append(line((p0[0] + u0[0] * lead, p0[1] + u0[1] * lead), *arc_pts(32, 32, R, a0, a1, 48),
                        (p1[0] + u1[0] * lead, p1[1] + u1[1] * lead), w=7))
    return U(*out)


def it5_U():
    return U(ring_kerbs(8, 21), disc(32, 32, 8))


def it5_V():
    return U(ring_kerbs(8, 22.5), disc(32, 32, 5.5), arc_arrow(32, 32, 12.5, 60, -210, w=5, hl=7.5, hw=11.5))


def it5_W():
    return U(ring_kerbs(9.5, 23), disc(32, 32, 9.5))


def it5_X():
    return U(ring_kerbs(8, 21), ring(32, 32, 9, 4.5))


def it5_Y():
    r = 12.5
    a0 = 25
    p0 = (32 + r * math.cos(math.radians(a0)), 32 + r * math.sin(math.radians(a0)))
    entry = line((61, p0[1]), (p0[0] + 1.5, p0[1]), w=5)
    around = arc_arrow(32, 32, r, a0, -175, w=5, hl=7.5, hw=11.5)
    return U(ring_kerbs(8, 22.5), disc(32, 32, 5.5), entry, around)


icon("intersections-v5", "Intersections et giratoires — reprise 4",
     P("U", "Anneau et îlot", "Les bordures de la priorité à droite deviennent l'anneau ; l'îlot plein au centre.", it5_U, "Bordures"),
     P("V", "Anneau, îlot, sens", "L'anneau des bordures, l'îlot et le sens giratoire dans la voie.", it5_V, "Bordures"),
     P("W", "Grand îlot", "Branches plus larges, comme la priorité à droite ; un îlot plus grand pour garder l'anneau.", it5_W, "Bordures"),
     P("X", "Îlot-repère", "L'anneau des bordures autour du repère annelé de Drivy.", it5_X, "Bordures"),
     P("Y", "Celle de droite tourne", "La flèche vient de droite, comme dans la priorité à droite, et tourne dans l'anneau.", it5_Y, "Bordures"))


# ---------------------------------------------------------------- sortie SVG

def to_path(geom, ndigits=2):
    geom = geom.simplify(0.02)
    polys = [geom] if isinstance(geom, Polygon) else list(getattr(geom, "geoms", []))
    out = []

    def ring_d(coords):
        pts = list(coords)[:-1]
        if len(pts) < 3:
            return ""
        s = f"M{pts[0][0]:.{ndigits}f} {pts[0][1]:.{ndigits}f}"
        s += "".join(f"L{x:.{ndigits}f} {y:.{ndigits}f}" for x, y in pts[1:])
        return s + "Z"

    for p in polys:
        if not isinstance(p, Polygon) or p.is_empty:
            continue
        out.append(ring_d(p.exterior.coords))
        out.extend(ring_d(i.coords) for i in p.interiors)
    return "".join(out)


SECONDARY_OPACITY = 0.35


def layers(g):
    """Une icône est une géométrie, ou un couple (principale, secondaire) : le second calque garde le
    même bleu à 35 % d'opacité, comme un SF Symbol hiérarchique ; le gabarit reste d'une couleur."""
    return g if isinstance(g, tuple) else (g, None)


def svg(geom, title, color="#245BD6", size=64):
    primary, secondary = layers(geom)
    def path(g, extra=""):
        d = to_path(g).replace(".00", "").replace("L", " L").strip()
        return f'<path fill="{color}"{extra} fill-rule="evenodd" d="{d}"/>'
    body = (path(secondary, f' fill-opacity="{SECONDARY_OPACITY}"') if secondary is not None else "") + path(primary)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64" role="img">'
            f'<title>{title}</title>{body}</svg>\n')


def metrics(geom):
    primary, secondary = layers(geom)
    whole = U(primary, secondary)
    minx, miny, maxx, maxy = whole.bounds
    return {"ink": round(primary.area / 4096 + (secondary.area * SECONDARY_OPACITY / 4096 if secondary is not None else 0), 3),
            "bbox": [round(v, 1) for v in (minx, miny, maxx, maxy)],
            "w": round(maxx - minx, 1), "h": round(maxy - miny, 1)}


def build_all():
    OUT.mkdir(exist_ok=True)
    report = {}
    for key, spec in ICONS.items():
        d = OUT / key
        d.mkdir(exist_ok=True)
        report[key] = {"title": spec["title"], "proposals": []}
        for p in spec["directions"]:
            g = p["build"]()
            (d / f"{p['direction']}.svg").write_text(svg(g, f"{spec['title']} — {p['name']}"), encoding="utf-8")
            m = metrics(g)
            report[key]["proposals"].append({"direction": p["direction"], "name": p["name"], "idea": p["idea"],
                                             "famille": p.get("famille"), **m})
    (HERE / "propositions.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    return report


if __name__ == "__main__":
    rep = build_all()
    for k, v in rep.items():
        print(k, " ".join(f"{p['direction']}:{p['ink']}/{p['w']}x{p['h']}" for p in v["proposals"]))
