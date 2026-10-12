"""Atelier des icônes de catégories de permis — trois directions par catégorie, géométrie calculée.

Les 16 catégories de l'OAC (RS 741.51, art. 3) : A, B, C, D, BE, CE, DE ; sous-catégories A1, B1, C1, D1, C1E, D1E ;
catégories spéciales F, G, M. Restrictions (A limitée à 35 kW), qualifications (OACP, TPP 121) et offres d'école
ne sont pas des catégories : elles n'ont pas d'icône.

Grammaire commune, sœur de la famille « Signaler » (docs/implementation/icones-signaler-20261012.md) :
- canevas 64 × 64, une couleur (gabarit), trous réels (`evenodd`), aucun fond ;
- véhicule de profil, l'avant à droite (le sens de lecture), roues posées sur un sol commun ;
- une remorque s'attelle toujours à gauche, timon visible : « E » se lit sans libellé ;
- une sous-catégorie « 1 » reprend la silhouette de sa catégorie, plus courte, à l'échelle de la catégorie mère ;
- contre-forme minimale G = 4 (comme « Signaler ») : elle reste ouverte à 16 pt.

Les trois directions :
  A « Natif »        contour d'épaisseur constante, roues annelées : l'esprit d'un SF Symbol ;
  B « Signature »    silhouette pleine arrondie ; chaque roue est le repère annelé de Drivy, mordu dans la caisse ;
  C « Géométrique »  blocs rectangulaires chanfreinés à 45°, cabine et caisse séparées d'un joint, roues pleines.

Usage : python atelier.py  → propositions/<catégorie>/<A|B|C>.svg + propositions.json
"""
from __future__ import annotations

import json
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

W = 5.0       # trait des pièces filaires (fourche, timon, cadre)
WA = 4.5      # contour de la direction A
G = 4.0       # contre-forme minimale
HALO = 2.5    # morsure du repère dans la caisse (marque)
Q = 24
BASE = 50.0   # sol commun
FIT_W, FIT_H = 56.0, 44.0

HERE = Path(__file__).resolve().parent
OUT = HERE / "propositions"


def U(*shapes):
    return unary_union([s for s in shapes if s is not None and not s.is_empty])


def line(*pts, w=W, cap="round", join="round"):
    return LineString(pts).buffer(w / 2, quad_segs=Q, cap_style=cap, join_style=join)


def disc(cx, cy, r):
    return Point(cx, cy).buffer(r, quad_segs=Q)


def ring(cx, cy, ro, ri):
    return disc(cx, cy, ro).difference(disc(cx, cy, ri))


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def rounded(g, r):
    return g.buffer(-r, join_style="round", quad_segs=Q).buffer(r, join_style="round", quad_segs=Q) if r > 0 else g


def chamfer(g, c):
    return g.buffer(-c, join_style="mitre").buffer(c, join_style="bevel")


# ---------------------------------------------------------------- véhicules (espace modèle, sol y = 50)
# Un véhicule : des groupes de pièces (cabine, caisse, châssis), des vitres, des roues (x, r), des traits,
# un point d'attelage à l'arrière. Les rendus ne voient que cette description.

class V:
    def __init__(self, groups, windows=(), wheels=(), lines=(), hitch=None, solid_lines=False, base=BASE, smooth=None):
        self.groups = groups            # [(nom, [polygones])]
        self.windows = list(windows)
        self.wheels = list(wheels)      # [(cx, r)] posées sur le sol
        self.lines = list(lines)        # [[points]]
        self.hitch = hitch
        self.solid_lines = solid_lines  # deux-roues : le cadre fait la silhouette
        self.base = base
        self.smooth = smooth            # arrondi propre (deux-roues : cols étroits)

    def transform(self, s, dx, dy):
        f = lambda p: (p[0] * s + dx, p[1] * s + dy)
        return V([(n, [[f(p) for p in poly] for poly in polys]) for n, polys in self.groups],
                 [[f(p) for p in w] for w in self.windows],
                 [(cx * s + dx, r * s) for cx, r in self.wheels],
                 [[f(p) for p in l] for l in self.lines],
                 f(self.hitch) if self.hitch else None, self.solid_lines, self.base * s + dy,
                 None if self.smooth is None else self.smooth * s)

    def bounds(self):
        xs, ys = [], []
        for _, polys in self.groups:
            for poly in polys:
                xs += [p[0] for p in poly]; ys += [p[1] for p in poly]
        for l in self.lines:
            xs += [p[0] for p in l]; ys += [p[1] for p in l]
        for cx, r in self.wheels:
            xs += [cx - r, cx + r]; ys += [self.base - 2 * r, self.base]
        return min(xs), min(ys), max(xs), max(ys)


def car():
    return V([("caisse", [rect(6, 31, 58, 45), [(15, 32), (22.5, 19), (41, 19), (50, 32)]])],
             [[(20.2, 30), (24.2, 23), (30.5, 23), (30.5, 30)], [(34.5, 30), (34.5, 23), (40.2, 23), (45.4, 30)]],
             [(17, 6.5), (47, 6.5)], hitch=(6, 41))


def quadricycle():
    # B1 : la voiturette, une seule vitre, empattement court, plus haute que longue.
    return V([("caisse", [rect(13, 30, 51, 45), [(15, 31), (20, 17), (38, 17), (46, 31)]])],
             [[(20.2, 28.5), (23.4, 21), (35.9, 21), (40.23, 28.5)]],
             [(21.5, 6), (42.5, 6)], hitch=(13, 41))


def truck():
    return V([("caisse", [rect(6, 11, 40, 38)]),
              ("cabine", [[(43, 15), (53.4, 15), (58, 23), (58, 45), (43, 45)], rect(8, 38, 45, 44)])],
             [[(46.5, 19), (51.5, 19), (54.7, 24.5), (54.7, 28), (46.5, 28)]],
             [(14, 6), (27, 6), (50.5, 6)], hitch=(6, 41))


def light_truck():
    return V([("caisse", [rect(10, 18, 38, 38)]),
              ("cabine", [[(41, 21), (50, 21), (55, 28), (55, 45), (41, 45)], rect(16, 38, 43, 44)])],
             [[(44.5, 25), (49, 25), (51.3, 29), (51.3, 32), (44.5, 32)]],
             [(22, 6), (48, 6)], hitch=(10, 41))


def bus():
    wins = [rect(x, 18, x + 8, 28) for x in (10, 22, 34, 46)]
    return V([("caisse", [[(6, 13), (54, 13), (58, 18), (58, 45), (6, 45)]])],
             wins, [(16, 6.5), (48, 6.5)], hitch=(6, 41))


def minibus():
    return V([("caisse", [[(8, 16), (40, 16), (48, 26), (56, 29), (56, 45), (8, 45)]])],
             [rect(12, 20, 21, 28), rect(25, 20, 34, 28), [(38, 20), (40, 20), (45.2, 27), (45.2, 28), (38, 28)]],
             [(19, 6), (45.5, 6)], hitch=(8, 41))


def tractor():
    # G : grande roue arrière sous la cabine, petite roue avant, capot bas, pot d'échappement.
    return V([("cabine", [rect(10, 5, 34, 27)]),
              ("capot", [[(31, 27), (52, 27), (56, 30), (56, 41), (31, 41)]])],
             [rect(14.5, 9.5, 29.5, 19.5)],
             [(20, 11.5), (48, 7)], lines=[[(46, 26), (46, 16)]], hitch=(8, 41))


def slow_utility():
    # F : petit utilitaire lent (≤ 45 km/h) — cabine courte et pont ouvert, roues petites.
    return V([("pont", [rect(9, 29, 32, 41)]),
              ("cabine", [[(35, 17), (46, 17), (53, 27), (53, 45), (35, 45)]])],
             [[(38.5, 20.5), (44.3, 20.5), (49, 27.5), (49, 30), (38.5, 30)]],
             [(19, 5.5), (45, 5.5)], hitch=(9, 41))


def motorcycle():
    # A : la moto lourde — carénage avant, réservoir et selle d'un seul profil, grandes roues.
    return V([("caisse", [[(6, 24.75), (20, 28.5), (28, 28.5), (30.9, 23.5), (42, 22.5), (46, 27), (41, 33.5),
                           (24, 34.5), (16, 33), (7.5, 28.5)],
                          [(24, 33), (40, 33), (37.59, 42), (27, 42)],
                          [(42, 19.5), (48.5, 16.5), (51.5, 24.5), (45.5, 29.5)]])],
             wheels=[(13, 9), (51, 9)],
             lines=[[(13, 41), (28, 38.5)], [(51, 41), (45.9, 22)]], solid_lines=True, smooth=1.2)


def light_motorcycle():
    # A1 : la moto légère — même profil, sans carénage, plus basse, roues plus petites.
    return V([("caisse", [[(10, 29), (22, 31), (29, 31), (32, 27), (41, 26.5), (44, 30), (40, 35),
                           (25, 36), (18, 35), (11, 31.5)],
                          [(26, 34.5), (38, 34.5), (35.86, 42.5), (28, 42.5)]])],
             wheels=[(16, 8), (49, 8)],
             lines=[[(16, 42), (29, 40)], [(49, 42), (44.18, 24)], [(44.18, 24), (39.5, 22.75)]], solid_lines=True, smooth=1.2)


def moped():
    # M : le cyclomoteur — un cadre de vélo (pédalier, haubans), une selle, un petit bloc moteur.
    return V([("caisse", [rect(31, 31.5, 39.5, 38), rect(19.5, 23.5, 30, 27)])],
             wheels=[(14, 8), (50, 8)],
             lines=[[(14, 42), (30, 42)], [(14, 42), (26.5, 29.5)], [(30, 42), (25, 27)], [(30, 42), (44, 26)],
                    [(44, 26), (50, 42)], [(44, 26), (42, 20.5), (46.5, 20)]],
             solid_lines=True, smooth=0.6)


# ---------------------------------------------------------------- remorques

def trailer(kind):
    if kind == "light":     # derrière une voiture, un minibus
        return V([("remorque", [rect(0, 29, 20, 43)])], wheels=[(10, 5.5)], hitch=(20, 41))
    if kind == "mid":       # derrière un camion léger
        return V([("remorque", [rect(0, 20, 22, 38), rect(2, 38, 22, 44)])], wheels=[(11, 6)], hitch=(22, 41))
    if kind == "heavy":     # derrière un camion
        return V([("remorque", [rect(0, 13, 27, 38), rect(1, 38, 27, 44)])], wheels=[(7.5, 6), (20, 6)], hitch=(27, 41))
    if kind == "bus":       # remorque à bagages derrière un car
        return V([("remorque", [rect(0, 25, 19, 43)])], wheels=[(9.5, 5.5)], hitch=(19, 41))
    raise ValueError(kind)


def couple(vehicle, kind, drawbar=8.0):
    """Remorque à gauche, timon visible jusqu'à l'attelage du véhicule."""
    t = trailer(kind)
    hx = vehicle.hitch[0]
    t = t.transform(1, hx - drawbar - t.hitch[0], 0)
    # La remorque d'abord : en direction C, le véhicule passe devant elle au joint.
    groups = t.groups + vehicle.groups
    bar = [(t.hitch[0] - 1, vehicle.hitch[1]), (hx + 1, vehicle.hitch[1])]
    return V(groups, vehicle.windows + t.windows, vehicle.wheels + t.wheels,
             vehicle.lines + t.lines + [bar], hitch=None, solid_lines=vehicle.solid_lines, smooth=vehicle.smooth)


CATEGORIES = {
    # clé: (libellé officiel abrégé, fabrique, catégorie dont l'échelle est reprise)
    "a":   ("Motocycles", motorcycle, None),
    "a1":  ("Motocycles légers (≤ 125 cm³, 11 kW)", light_motorcycle, "a"),
    "b":   ("Voitures automobiles (≤ 3 500 kg, 8 places)", car, None),
    "b1":  ("Quadricycles et tricycles à moteur (≤ 550 kg à vide)", quadricycle, "b"),
    "be":  ("Voiture et remorque", lambda: couple(car(), "light"), None),
    "c":   ("Camions (> 3 500 kg)", truck, None),
    "c1":  ("Camions légers (3 500 à 7 500 kg)", light_truck, "c"),
    "ce":  ("Camion et remorque (> 750 kg)", lambda: couple(truck(), "heavy"), None),
    "c1e": ("Camion léger et remorque (≤ 12 000 kg)", lambda: couple(light_truck(), "mid"), None),
    "d":   ("Autocars (plus de 8 places)", bus, None),
    "d1":  ("Minibus (9 à 16 places)", minibus, "d"),
    "de":  ("Autocar et remorque (> 750 kg)", lambda: couple(bus(), "bus"), None),
    "d1e": ("Minibus et remorque (≤ 12 000 kg)", lambda: couple(minibus(), "light"), None),
    "f":   ("Véhicules automobiles lents (≤ 45 km/h)", slow_utility, "b"),
    "g":   ("Véhicules agricoles et forestiers (≤ 30 km/h)", tractor, None),
    "m":   ("Cyclomoteurs", moped, "a"),
}


def fit_scale(v):
    x0, y0, x1, y1 = v.bounds()
    return min(FIT_W / (x1 - x0), FIT_H / (y1 - y0))


def placed(key):
    """Le véhicule à l'échelle du canevas. Une sous-catégorie garde l'échelle de sa catégorie mère :
    A1 paraît plus léger que A, C1 plus court que C."""
    _, make, ref = CATEGORIES[key]
    v = make()
    s = fit_scale(CATEGORIES[ref][1]() if ref else v)
    x0, y0, x1, y1 = v.bounds()
    return v.transform(s, 32 - (x0 + x1) / 2 * s, 32 - (y0 + y1) / 2 * s)


# ---------------------------------------------------------------- rendus

def wheel_y(v, r):
    return v.base - r


def render_A(v):
    """Natif : contour d'épaisseur constante, vitres pleines dans l'habitacle, roues annelées."""
    body = rounded(U(*[Polygon(p) for _, polys in v.groups for p in polys]), v.smooth if v.smooth is not None else 2.5)
    cut = U(*[disc(cx, wheel_y(v, r), r + 2.5) for cx, r in v.wheels])
    outline = body if v.solid_lines else body.difference(body.buffer(-WA))
    glass = rounded(U(*[Polygon(w) for w in v.windows]).intersection(body.buffer(-(WA + 2.0))), 0.8)
    wheels = U(*[ring(cx, wheel_y(v, r), r, max(r - WA, r * 0.38)) for cx, r in v.wheels])
    lines = U(*[line(*l, w=WA) for l in v.lines])
    return U(U(outline, glass, lines).difference(cut), wheels)


def render_B(v):
    """Signature : silhouette pleine arrondie, vitres évidées, roues = repère annelé mordu dans la caisse."""
    body = rounded(U(*[Polygon(p) for _, polys in v.groups for p in polys]), v.smooth if v.smooth is not None else 3.0)
    holes = rounded(U(*[Polygon(w) for w in v.windows]), 1.0)
    lines = U(*[line(*l, w=W) for l in v.lines])
    cut = U(*[disc(cx, wheel_y(v, r), r + HALO) for cx, r in v.wheels])
    wheels = U(*[ring(cx, wheel_y(v, r), r, r * 0.45) for cx, r in v.wheels])
    return U(U(body.difference(holes), lines).difference(cut), wheels)


SEAM = 2.5


def render_C(v):
    """Géométrique : blocs chanfreinés à 45°, un joint entre les blocs, roues pleines."""
    c = 2.5 if v.smooth is None else v.smooth
    parts = [chamfer(U(*[Polygon(p) for p in polys]), c) for _, polys in v.groups]
    shaped = []
    for i, g in enumerate(parts):
        later = U(*parts[i + 1:])
        shaped.append(g if later.is_empty else g.difference(later.buffer(SEAM, join_style="mitre")))
    body = U(*shaped)
    holes = U(*[Polygon(w) for w in v.windows])
    lines = U(*[line(*l, w=WA, cap="flat", join="mitre") for l in v.lines])
    cut = U(*[disc(cx, wheel_y(v, r), r + G * 0.75) for cx, r in v.wheels])
    wheels = U(*[disc(cx, wheel_y(v, r), r) for cx, r in v.wheels])
    return U(U(body.difference(holes), lines).difference(cut), wheels)


DIRECTIONS = {
    "A": ("Natif", "Contour constant et roues annelées, comme un SF Symbol de la même graisse.", render_A),
    "B": ("Signature", "Silhouette pleine arrondie ; chaque roue est le repère annelé de la marque.", render_B),
    "C": ("Géométrique", "Blocs chanfreinés à 45°, joint entre cabine et caisse, roues pleines.", render_C),
}


# ---------------------------------------------------------------- sortie SVG (même écriture que « Signaler »)

def to_path(geom, nd=2):
    geom = geom.simplify(0.02)
    polys = [geom] if isinstance(geom, Polygon) else list(getattr(geom, "geoms", []))
    out = []

    def ring_d(coords):
        pts = list(coords)[:-1]
        if len(pts) < 3:
            return ""
        return f"M{pts[0][0]:.{nd}f} {pts[0][1]:.{nd}f}" + "".join(f" L{x:.{nd}f} {y:.{nd}f}" for x, y in pts[1:]) + "Z"

    for p in polys:
        if isinstance(p, Polygon) and not p.is_empty:
            out.append(ring_d(p.exterior.coords))
            out.extend(ring_d(i.coords) for i in p.interiors)
    return "".join(out).replace(".00", "")


def clean(g, min_area=8.0):
    """Retire les éclats laissés par les coupes (une miette de châssis entre deux roues)."""
    polys = [g] if isinstance(g, Polygon) else list(getattr(g, "geoms", []))
    return U(*[p for p in polys if p.area >= min_area])


def svg(geom, title, color="#245BD6", size=64):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64" role="img">'
            f'<title>{title}</title><path fill="{color}" fill-rule="evenodd" d="{to_path(geom)}"/></svg>\n')


def metrics(g):
    x0, y0, x1, y1 = g.bounds
    return {"ink": round(g.area / 4096, 3), "bbox": [round(v, 1) for v in (x0, y0, x1, y1)],
            "w": round(x1 - x0, 1), "h": round(y1 - y0, 1)}


def build(key, direction):
    return clean(DIRECTIONS[direction][2](placed(key)))


def build_all():
    OUT.mkdir(exist_ok=True)
    report = {}
    for key, (title, _, ref) in CATEGORIES.items():
        d = OUT / key
        d.mkdir(exist_ok=True)
        report[key] = {"code": key.upper(), "title": title, "scale_ref": ref, "proposals": []}
        for k, (name, idea, _) in DIRECTIONS.items():
            g = build(key, k)
            (d / f"{k}.svg").write_text(svg(g, f"Catégorie {key.upper()} — {name}"), encoding="utf-8")
            report[key]["proposals"].append({"direction": k, "name": name, "idea": idea, **metrics(g)})
    (HERE / "propositions.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    return report


if __name__ == "__main__":
    for k, v in build_all().items():
        print(k, " ".join(f"{p['direction']}:{p['ink']}/{p['w']}x{p['h']}" for p in v["proposals"]))
