"""Notes pondérées des trois propositions de chaque catégorie, puis choix de la famille → selection.json.

Critères (sur 5) et poids : cohérence avec Drivy 30 %, reconnaissance immédiate 25 %, lisibilité à petite taille 20 %,
harmonie entre catégories 15 %, qualité esthétique 10 %. Les notes de base sont celles d'une direction vue sur toute
la planche (planche-1.png) ; les écarts propres à une catégorie sont écrits à côté, avec leur raison.

Usage : python selection.py
"""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
WEIGHTS = {"coherence": 0.30, "reconnaissance": 0.25, "lisibilite": 0.20, "harmonie": 0.15, "esthetique": 0.10}

BASE = {
    # A : contour seul, alors que « Signaler » et la marque sont des aplats ; s'allège trop à 16 pt.
    "A": {"coherence": 3, "reconnaissance": 4, "lisibilite": 3, "harmonie": 4, "esthetique": 3},
    # B : aplats arrondis comme « Signaler », roues = repère annelé de la marque, silhouettes nettes à 16 pt.
    "B": {"coherence": 5, "reconnaissance": 4, "lisibilite": 4, "harmonie": 5, "esthetique": 4},
    # C : lisible, mais chanfreins invisibles sous 24 pt et roues pleines lourdes ; angles vifs étrangers à la trace ronde.
    "C": {"coherence": 3, "reconnaissance": 4, "lisibilite": 4, "harmonie": 3, "esthetique": 3},
}

COMBOS = {"be", "ce", "c1e", "de", "d1e"}
TWO_WHEELS = {"a", "a1", "m"}

ADJUST = {
    # (catégorie, direction): ({critère: note}, raison)
    ("g", "A"): ({"reconnaissance": 5}, "le tracteur au contour se lit d'emblée : grande roue, cabine vitrée"),
    ("g", "B"): ({"reconnaissance": 5}, "grande roue sous la cabine, pot d'échappement : sans ambiguïté"),
    ("d", "B"): ({"reconnaissance": 5}, "rangée de quatre vitres pleines : le car à 16 pt"),
    ("c", "B"): ({"reconnaissance": 5}, "caisse haute, cabine avancée, essieu tandem"),
    ("b", "B"): ({"reconnaissance": 5, "esthetique": 5}, "la voiture de référence de la famille"),
    ("c1", "C"): ({"esthetique": 2}, "la coupe de roue entame la caisse et laisse un angle orphelin"),
    ("f", "A"): ({"reconnaissance": 3}, "le pont ouvert au contour se confond avec une cabine vide"),
}
for k in COMBOS:
    ADJUST[(k, "A")] = ({"lisibilite": 2}, "contour dédoublé : remorque et véhicule fusionnent à 20 pt")
    ADJUST[(k, "B")] = ({"lisibilite": 3}, "ensemble large donc petit ; le timon et la roue de remorque restent lisibles à 20 pt")
    ADJUST[(k, "C")] = ({"lisibilite": 3}, "les roues pleines de la remorque collent à celles du véhicule à 16 pt")
for k in TWO_WHEELS:
    ADJUST[(k, "A")] = ({"coherence": 4, "harmonie": 3}, "un deux-roues est déjà un trait : A et B se rejoignent, roues plus fines en A")
    ADJUST[(k, "C")] = ({"reconnaissance": 3}, "roues pleines : le deux-roues devient deux pastilles à 16 pt")

WHY = {
    "a": "Moto lourde : carénage, réservoir et selle d'un seul profil, grandes roues annelées.",
    "a1": "Même profil que A sans carénage, à l'échelle de A : plus basse, plus légère.",
    "m": "Cadre de vélo avec pédalier et bloc moteur : le cyclomoteur, à l'échelle de A.",
    "b": "La voiture de référence : deux vitres, roues-repères mordues dans la caisse.",
    "b1": "Voiturette à une vitre, plus haute que longue, à l'échelle de B.",
    "be": "La voiture de B attelée à une remorque, timon visible.",
    "c": "Caisse haute, cabine avancée, essieu arrière tandem.",
    "c1": "Le camion de C raccourci, un seul essieu arrière, à l'échelle de C.",
    "ce": "Le camion de C et une remorque à deux essieux.",
    "c1e": "Le camion de C1 et une remorque à un essieu.",
    "d": "Car : quatre vitres alignées, pare-brise avant chanfreiné.",
    "d1": "Minibus : nez court incliné, deux vitres, à l'échelle de D.",
    "de": "Le car de D et une remorque à bagages.",
    "d1e": "Le minibus de D1 et une remorque légère.",
    "f": "Petit utilitaire lent à pont ouvert, à l'échelle d'une voiture (convention : l'OAC ne fixe aucune silhouette).",
    "g": "Tracteur : grande roue arrière sous la cabine vitrée, capot bas, pot d'échappement.",
}


def main():
    data = json.loads((HERE / "propositions.json").read_text(encoding="utf-8"))
    out = {}
    for k in data:
        notes = {}
        for d in "ABC":
            n = dict(BASE[d])
            reason = None
            if (k, d) in ADJUST:
                delta, reason = ADJUST[(k, d)]
                n.update(delta)
            n["total"] = round(sum(n[c] * w for c, w in WEIGHTS.items()), 2)
            if reason:
                n["ecart"] = reason
            notes[d] = n
        best = max("ABC", key=lambda d: notes[d]["total"])
        out[k] = {"retenue": best, "notes": notes, "pourquoi": WHY[k]}
    # Famille : la direction retenue partout doit être la même ; sinon on harmonise vers la majorité.
    picks = [v["retenue"] for v in out.values()]
    family = max(set(picks), key=picks.count)
    for k, v in out.items():
        if v["retenue"] != family:
            v["harmonisee"] = f"meilleure seule : {v['retenue']} ; retenue {family} pour la famille"
            v["retenue"] = family
    (HERE / "selection.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    for k, v in out.items():
        print(k, v["retenue"], {d: v["notes"][d]["total"] for d in "ABC"}, v.get("harmonisee", ""))


if __name__ == "__main__":
    main()
