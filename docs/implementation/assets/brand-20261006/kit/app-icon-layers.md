# Drivy : App Icon, découpage en calques (Icon Composer, iOS 26)

Source : `drivy-app-icon.svg` (1024 × 1024, carré plein, aucun coin dessiné : le système applique le masque).
Les trois éléments ont déjà un `id` chacun ; exporter un SVG par calque, canevas 1024 conservé, sans le fond.

## Calques, de l'arrière vers l'avant

| Ordre | Calque | Contenu | Défaut | Sombre | Teinté / clair-transparent |
|---|---|---|---|---|---|
| 0 | Fond | aplat, réglé dans Icon Composer (pas de calque image) | #245BD6 | #10151C | laissé au système |
| 1 | `trace` | bande verticale à fond perdu, x 624 à 784, mordue par un arc de rayon 288 centré (448, 560) | blanc | #91B5FF | gris moyen (#8E8E93) |
| 2 | `repere` | anneau centré (448, 560), rayons 256 / 140, trou réel ; il passe devant la trace et y entre de 80 (la moitié) | blanc | blanc | blanc |

Deux groupes dans Icon Composer : « Trace » (calque 1) et « Repère » (calque 2), pour que le repère reçoive
son propre reflet et son ombre portée au-dessus de la trace. Aucun dégradé, aucune ombre dessinée dans les
fichiers : la profondeur vient du matériau.

## Réglages de départ (à ajuster à l'œil)

- Fond : couleur unie, sans dégradé système.
- Trace : Liquid Glass activé, translucidité faible, pas de flou ; elle doit rester une bande nette.
- Repère : Liquid Glass activé, spéculaire activé, ombre « neutre » légère. C'est le seul élément qui a du relief.
- Mode teinté : la trace à environ 55 % de luminance, le repère à 100 %, pour garder deux niveaux distincts
  une fois la teinte appliquée (`drivy-app-icon-tinted.svg` montre l'intention en niveaux de gris).

## Ce qui a été vérifié ici (rendu Chrome, masque approché par un rayon de 22,37 %)

- Bord droit de la trace à x = 784 : il reste dans la partie droite du masque (le coin commence vers x = 795).
- Lecture à 60, 40 et 29 px : anneau et bande restent séparés ; le halo retenu est de 32 (24 essayé : 0,7 px à 29 px,
  le liseré se brouille ; 32 donne 0,9 px et reste un filet continu). Le « d » se lit aux trois tailles.
- Voisinage : planche `homescreen-sheet.png`, quatre tuiles bleues autour.

## À vérifier sur appareil (non fait, impossible ici)

1. Le masque réel d'iOS 26 (courbure continue) : la bande ne doit pas toucher le début du coin, haut et bas.
2. Liquid Glass : le halo spéculaire sur le bord de la trace ne doit pas combler la morsure ; sinon passer
   l'écart de 32 à 40 dans `tools/build_icons.py` (`gap`).
3. Les six apparences : défaut, sombre, clair transparent, sombre transparent, teinté clair, teinté sombre.
4. Tailles réelles : écran d'accueil (60 pt), Spotlight (40 pt), Réglages (29 pt), notification (20 pt).
5. Fond d'écran clair et chargé en mode transparent : le repère doit rester la forme la plus claire.
6. iPad et bibliothèque d'apps (icône plus grande) : marge gauche du repère (192) contre marge droite (240).
7. Repli iOS 18 : fournir les trois PNG 1024 opaques (`drivy-app-icon-1024.png`, `-dark-1024.png`,
   `-tinted-1024.png`) dans l'AppIcon classique.
