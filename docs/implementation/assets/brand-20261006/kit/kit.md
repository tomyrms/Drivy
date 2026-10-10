# Drivy : kit logo « La trace »

## Construction
Canevas 256, grille de 8, deux primitives remplies.
- **Repère** : anneau centré (118, 156), rayons 72 et 40 (épaisseur 32, trou 56 %). Il passe devant la trace.
- **Trace** : capsule verticale large de 40, x 170 à 210, y 28 à 228, bouts de rayon 20.
- **Morsure** : l'anneau entre de 20 dans la capsule (la moitié) ; un disque de rayon 77, de même centre, est soustrait (booléen skia-pathops, un seul contour, pas d'éclat). Halo de 5, taille de la hampe 15 ; la morsure entame le bout rond inférieur.

## Passes
1. **Trou trop petit** (51 %) : l'anneau se lisait cible. Porté à 59 %.
2. **Lecture « o l »**, marque trop légère face à l'ancien d et au d en deux pièces. Anneau agrandi à 72, épaissi à 32, chevauchant la hampe de 8, tout sur la grille. Chevauchement de 10 et plus rejeté : le pied devient une pointe.
3. **Lecture « o l » persistante** au test de lettre : le repère s'écartait de la trace. Il passe maintenant devant : entrée de 20 au lieu de 8, halo de 5 au lieu de 8. Résultat : « d » lu dès 20 px (`compare-passe3.png`).
4. **Optique** : dépassement sous la base rejeté. Blanc aminci de 0,75 par bord.

## Tests réellement faits
- `svg_audit.py` : 100/100 sur les symboles, 99 sur lockups et icônes. Un avertissement d'angle sur le mot seul vient du dessin d'Outfit.
- 16 / 24 / 32 / 48 px agrandis au pixel : le maître se lit « d » à 24 et 20 ; à 16 le halo devient un gris. Coupe petite taille (sans morsure, anneau 80/48 entrant de moitié dans la hampe) pour 16 à 20 px.
- Miroir « b », rotation 180° « p » : rien de gênant.
- Comparaison (`work/compare-peers.png`) : faite sur la passe 2 ; elle a motivé la passe 3. À 16 px l'ancien d reste plus massif.
- Icône à 60 / 40 / 29 px sous masque approché, et parmi quinze tuiles dont quatre bleues.

## Wordmark
Trois voies rendues dans douze caractères (`work/typestudy.png`).
- Horizontal retenu : le symbole est le « d », suivi de « rivy » ; le mot se lit « drivy » en bas de casse.
- Empilé : symbole au-dessus de « Drivy ». Mot seul : « Drivy ».
- Caractère : **Outfit**, graisse 540 (hampe 34, entre anneau et trace), SIL OFL 1.1, `brand.py fonts audit` passé. Source Sans 3 essayé : r à ergot et y courbe jurent avec l'anneau ; il reste le caractère de texte du web.
- Vectorisation : police instanciée par `typelib.resolve_font`, contours extraits avec fontTools (`tools/typo.py`), crénage GPOS. Aucun `<text>`.

## Zone de protection et tailles minimales
Marge = diamètre du trou de l'anneau (0,4 × hauteur du symbole), incluse dans les fichiers de lockup.
Minimums trouvés par rendu : symbole 24 px, coupe petite taille 16 px, horizontal 80 px de large, empilé 42 px de haut. Impression (calculé, non éprouvé) : 8, 4, 27 et 14 mm.

## Mésusages
Étirer, ajouter un dégradé, incliner ; et deux propres à la marque : combler la morsure, détacher le repère (l'ancienne construction).

## Pictogrammes
Cinq glyphes, trait 3,2 sur grille 64. Plus dépouillés que les douze existants : visible sur `glyph-sheet.png`.

## Reste à faire par un humain
- **Antériorité** : « Drivy » fut le nom du service d'autopartage devenu Getaround. Recherche de marques (IPI, EUIPO) et image inversée avant tout dépôt.
- Valider le lockup en bas de casse alors que le nom s'écrit « Drivy ».
- Essai de l'icône sur appareil : voir `app-icon-layers.md`.
- Pantone et CMJN du cobalt ; épreuve des tailles en mm.
