# Logo Drivy — skill logo-design, 4 octobre 2026

## Mandat et provenance

Le porteur demande l’installation du [skill logo-design](https://github.com/kaankiziltug/logo-design-skill), puis son emploi pour améliorer le logo. Il a déjà demandé de sélectionner le meilleur candidat : la sélection et l’intégration restent autorisées sans nouveau point d’approbation. Le périmètre est le symbole et l’image de l’application ; aucun kit marketing complet n’est demandé.

Skill installé dans `C:/Users/jtoma/.codex/skills/logo-design`, depuis `skills/logo-design` à la révision `0ecf52e9a4b3ac92b714f7cc6e3148ab8c774134`, avec le programme du skill-installer. Instructions de redesign, brief, construction SVG, techniques visuelles et tests lues ; critique et bibliothèque étudiées en parallèle.

## Choix et fabrication

Les cinq images ImageGen initiales restent conservées dans [la première exploration](native-icon-signal-review-20261004.md). Leurs pointillés routiers s’affaiblissaient en petite taille. La reprise garde le cobalt et le d, mais remplace ces détails par une contreforme unique.

Dix idées ont été évaluées, trois construites en noir : A « d continu », B « virage partagé » et C « D ouvert ». Le [brief et les fichiers](assets/drivy-logo-skill-20261004) conservent les idées et les deux passes. A est retenu : le d se lit immédiatement et la contreforme angulaire évoque un virage. B évoquait davantage un angle d’interface ; C restait plus rigide et dépendait d’une fente fragile en réduction. Les scores du brief sont des jugements de sélection, pas une mesure de qualité objective.

Les références Airbnb, Khan Academy, Dashlane, Pagekit et Precursor ont été étudiées dans la bibliothèque du skill pour leur construction. Aucun tracé n’a été repris. Cette bibliothèque n’est ni un état complet du marché ni une recherche de disponibilité de marque.

La seconde passe relève le symbole de 2 unités sur le canevas 256. Le centrage horizontal est conservé : la tige à droite compense les marges géométriques inégales. La réserve blanche réduit le poids du ruban d’environ 3,6 % pour éviter qu’il paraisse plus épais sur le cobalt.

## Contrôles effectués

Deux planches réellement rendues et inspectées : les trois concepts, puis la comparaison v1/v2/réserve, tailles 64/32/24/16, miroir, rotation 180° et masque d’application. Le PNG 1024 final a également été inspecté. Une relecture indépendante confirme le centrage, la lisibilité et l’absence de défaut concret à corriger. La rotation donne naturellement un p ; le symbole à l’endroit se lit comme un d.

L’audit SVG final est conservé dans `audit-final.txt` : aucune police vivante, raster, filtre ou trait non développé dans les masters. Les remarques de centrage géométrique sont connues et relues optiquement. Les notes de l’audit ne constituent pas une certification graphique.

Le moteur de navigateur a refusé une URL locale `file:` : le HTML de test n’est donc pas qualifié. Les contrôles suivants ont employé uniquement la rasterisation statique SVG avec Sharp/librsvg et la lecture directe des PNG, sans exécuter de HTML.

## Fichiers et usage

- `drivy-symbol-black.svg`, `drivy-symbol-blue.svg`, `drivy-symbol-white.svg` : masters vectoriels.
- `drivy-app-icon.svg` : source du carré cobalt ; `drivy-app-icon.png` : export opaque 1024 × 1024.
- L’export PNG est identique dans `AppIcon.appiconset` et `DrivyBrand.imageset`.
- Couleurs : cobalt `#245BD6`, blanc `#FFFFFF`, noir `#111111`.
- Garder une réserve extérieure d’au moins la moitié de l’épaisseur du ruban ; le carré d’app possède sa propre marge. Ne pas ajouter de contour, ombre, pointillés ou déformation.
- Symbole autonome : minimum 16 px dans les contextes contrôlés ; conserver les libellés accessibles des commandes. L’icône d’application ne remplace pas un pictogramme d’action.

Les douze pictogrammes des signalements restent la famille affinée et validée séparément. Résultats Apple et limites physiques : [revue native](native-ui-review-20261004.md) et [STATUS](STATUS.md).
