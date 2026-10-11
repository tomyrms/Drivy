# Couleurs de l’échelle d’appréciation en thème clair — 12 octobre 2026

## Constat du porteur

Dans « Signaler », en thème clair, « À retravailler », « Attention » et « Point positif » sortaient bordeaux, brun moutarde et vert bouteille. Le thème sombre convenait.

## Cause

Aucune transparence, aucun matériau, aucun `colorScheme` mal propagé : la feuille et la palette posée sur la carte résolvent bien leurs couleurs en clair. La cause est un **rôle de token** : les pictogrammes, anneaux, pastilles et repères de l’échelle étaient peints avec `success` / `warning` / `danger`, qui sont des **encres de texte** réglées pour 4,5:1 sur blanc (#17633D 7,3:1, #7A4D00 7,3:1, #B02B37 6,5:1). Une encre aussi profonde, posée en forme pleine, se lit brune et terne. En sombre, les mêmes tokens sont des pastels clairs : le défaut n’y apparaît pas.

La même correspondance appréciation → couleur était en outre réécrite à cinq endroits (feuille, formulaire d’observation, bilan, résumé d’agenda, glyphes).

## Décision

- Trois tokens de **signal** dans `DrivyTheme`, pour l’appréciation *dessinée* : `successSignal` #26A058, `warningSignal` #D1760E, `dangerSignal` #E5484D en clair. Même luminosité OKLCH (≈ 0,62–0,65) pour qu’aucun état ne pèse plus qu’un autre ; au moins 3:1 (WCAG 1.4.11) sur la page, le bloc, le halo de carte et le fond teinté de leur état, et sous un glyphe clair (badge de carte, élément en cours du rail). Ni fluorescents ni saturés au maximum (chroma ≈ 0,15–0,19).
- Le sombre garde exactement ses valeurs (#7CCFA0, #E5BE7A, #FF9DA3).
- `DrivyTone.signal` : la teinte d’un état dessiné ; `foreground` reste l’encre des mots. Neutre et accent ne changent pas.
- Une seule correspondance : `SchoolObservationStatus.tone` / `ObservationStatus.tone`. Les copies locales sont supprimées.
- Dans « Signaler », le pictogramme d’appréciation reste nu, sans pastille (refusée par le porteur le 12 octobre) ; une appréciation pressée prend sa propre teinte au lieu du bleu de sélection.
- Les valeurs claires existantes ne bougent pas : texte d’état, messages, erreurs gardent leurs encres.

Un jaune vrai ne peut pas atteindre 3:1 sur blanc : « Attention » est un ambre chaud, celui d’un panneau de danger, et non plus un brun.

## Audit global

| Endroit | Avant | Après |
|---|---|---|
| Signaler (feuille et palette sur la carte) | glyphe à l’encre, sans fond | glyphe signal, sans fond |
| Marqueur de carte (direct, replay, aperçu) | anneau et badge à l’encre | signal |
| Rail du replay (pastilles, élément en cours) et frise (épingles, traits) | encre | signal |
| Fil des observations du bilan, résumé d’agenda, formulaire d’observation | encre | signal |
| `DrivyMapStatusLabel` (alerte GPS), résultat du trajet | symbole et texte à l’encre | symbole signal, texte à l’encre |
| `DrivyStatusDot` | point à l’encre | point signal |

Relevé sans changement : messages et statuts déjà « calmes » (neutres) depuis `94899c0` ; erreurs de champ et texte critique en `danger` (encre adaptée au texte) ; `Color.black` présent uniquement comme masque ; marque « La trace » non concernée ; aucun `preferredColorScheme` ni matériau sur ces écrans.

## Vérification

- `python3 scripts/ios/theme-contrast.py` étendu aux 3 tokens et 21 couples par mode : clair existant inchangé, tous les couples au-dessus de leur seuil.
- Captures simulateur clair et sombre avant / après : voir STATUS.md.
- Non qualifié : rendu sur appareil, en plein soleil, et avec Contraste accru.
