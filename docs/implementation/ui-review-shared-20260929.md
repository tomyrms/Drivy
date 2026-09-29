# Revue des composants natifs communs — 29 septembre 2026

Statut : **source inspectée et contrastes déclarés calculés**. Aucun rendu, parcours VoiceOver, test de clavier iPad ou essai physique n’est qualifié par cette revue. Les captures Apple sont suivies séparément.

Périmètre : `apps/ios/Drivy/UI/DrivyTheme.swift`, `DrivyComponents.swift`, `DrivyComponents+Accueil.swift`, `DrivyComponents+Agenda.swift`, `DrivyComponents+Ecole.swift`, `DrivyComponents+Seance.swift`, `DrivyObservationStyle.swift`, avec lecture du contexte de composition dans `SchoolCaptureUI/SchoolCaptureReplayView.swift`. Guides installés consultés : `better-layout`, `better-colors` et son annexe `contrast.md`, `better-typography`, `better-ui`, `better-accessibility`, puis `swiftui-ui-patterns` et son annexe formulaire. Les règles CSS des guides sont traduites vers les mécanismes SwiftUI pertinents ; aucune police web, animation CSS ou couche ARIA n’est ajoutée au natif.

## Couleurs mesurées

La [preuve de calcul](proofs/ui-shared-contrast-20260929.json) conserve les valeurs hexadécimales, le thème, le rapport arrondi à quatre décimales et la décision prise avant arrondi, ainsi que les empreintes des sources. Méthode : luminance relative sRGB WCAG 2, seuil 4,5:1 pour les textes courants et 3:1 pour les contrôles graphiques. Les valeurs inactives sont mesurées à titre informatif ; ce n’est pas une assertion d’obligation pour un contrôle désactivé. Les filets purement décoratifs ne sont pas utilisés comme texte ni soumis au seuil d’un contrôle.

| Paire déclarée | Clair | Sombre | Vérification |
| --- | ---: | ---: | --- |
| `muted` / `surface` | 6,3066 | 8,3318 | Calculée, passe 4,5 |
| `onAccent` / `accent` | 5,9281 | 7,2932 | Calculée, passe 4,5 |
| `accent` / `accentSoft` | 5,1924 | 5,7581 | Calculée, passe 4,5 |
| `danger` / `dangerSurface` | 5,6737 | 7,8187 | Calculée, passe 4,5 |
| `controlBorder` / `surface` | 3,7003 | 4,1918 | Calculée, passe 3 |
| Rail `controlBorder` à 45 % sur `surface` | 1,6747 | 1,8963 | Composition alpha déclarée, échoue 3 |

Les 60 paires opaques contrôlées passent leur seuil de référence. Les six autres mesures conservent les compositions alpha initiales. Avant correction, le bouton danger pressé à 85 % sur la surface blanche donnait 4,4043:1 et sur le canevas clair 4,4261:1, sous 4,5. L’alpha global des styles danger/tuile a été retiré et le rail utilise maintenant `controlBorder` opaque : les paires corrigées retrouvent respectivement 5,6737/7,8187 et 3,7003/4,1918. Aucun token de palette n’a changé. Le bloc `postCorrection` de la preuve distingue ces contrôles des mesures historiques. Ces valeurs sont calculées depuis les déclarations ; les pixels réellement composités par SwiftUI restent **Not verified**. Les surfaces Liquid Glass sur une carte n’ont pas de fond unique déductible de ces tokens : contraste réel **Not verified**.

## Constats transmis aux responsables des vues

| Gravité | Emplacement initial | Avant | Après constaté dans la source | Pourquoi |
| --- | --- | --- | --- | --- |
| MEDIUM corrigé | `UI/DrivyComponents+Seance.swift:515` | Rail non lu à `controlBorder.opacity(0.45)` | Token opaque ; contrôle visuel ensuite | La portion restante de la chronologie était sous 3:1 dans les deux thèmes. |
| MEDIUM corrigé | `UI/DrivyComponents+Seance.swift:397`, `UI/DrivyObservationStyle.swift:33` | Opacité de tout le bouton à 85 % pendant l’appui | Alpha retiré ; retour d’appui par échelle conservé | L’alpha global abaissait le texte danger clair sous 4,5:1. Palette conservée. |
| MEDIUM corrigé | `UI/DrivyComponents+Seance.swift:590`, contexte `SchoolCaptureUI/SchoolCaptureReplayView.swift:232` | Transport sur une seule ligne, largeur intrinsèque minimale 320 pt | `ViewThatFits` avec variante sur deux lignes | Les cinq contrôles totalisaient 272 pt, avec six espacements de 8 pt. À 375 pt, le dock et les marges proposent 311 pt ; rendu effectif **Not verified**. |
| MEDIUM corrigé | `UI/DrivyComponents+Seance.swift:474`, contexte `SchoolCaptureUI/SchoolCaptureReplayView.swift:428` | Ajustement accessible change l’instant sans appeler `onScrubStart` | Callback appelé avant l’ajustement, comme pour le glisser | La lecture est mise en pause et la sélection effacée au même endroit. Parcours physique **Not verified**. |
| MEDIUM corrigé | `UI/DrivyComponents+Accueil.swift:121` | Erreur uniquement dans l’indice accessible ; label d’erreur masqué de l’arbre | Erreur exposée comme élément indépendant ; retirée du hint ; valeur du champ inchangée | La lecture de l’erreur ne dépend plus de l’activation des indices. Usages noms/e-mail/téléphone inspectés. Annonce automatique et parcours effectif **Not verified**. |
| LOW ouvert | `UI/DrivyComponents.swift:455` | Retour de sélection à 0,98, boutons principaux à 0,96 | À harmoniser si la différence n’est pas intentionnelle | Cohérence du mouvement ; les deux respectent déjà Réduire les animations. |

Le bilan commun affichait trois rubriques vides avec le nouveau contrat facultatif. Ce point a été transmis au responsable des leçons : la source `DrivyReportBody` masque maintenant chaque rubrique vide et présente un état vide commun si les trois textes sont absents. Aucune validation de rendu n’est induite.

## États et structure constatés dans la source

| Famille | Constat de source | Ce qui reste à vérifier |
| --- | --- | --- |
| Boutons primaire / secondaire | Rôles de couleur centralisés ; état pressé ; état désactivé explicite ; hauteur minimale 52 pt ; `Button` natif ; échelle supprimée avec Réduire les animations | Libellés longs, Dynamic Type maximal, retour visible au clavier iPad |
| Badges et messages | Texte et symbole accompagnent la couleur ; badges multilignes aux tailles accessibles ; regroupement accessible | Prononciation, ordre et changement d’état annoncés |
| Titres et lecture | `largeTitle` gras, `title2` gras, `title3` semi-gras ; styles système ; colonne de lecture plafonnée à 720 pt ; chiffres tabulaires pour heures et compteurs | Mesure de lignes, troncature réelle, zoom, césure et longueurs réalistes |
| Lignes et valeurs | Cibles minimales de 44/56/64 pt selon le composant ; empilement des détails aux tailles accessibles ; icônes décoratives masquées | Chevauchement des cibles, parcours intégral au clavier et VoiceOver |
| Cartes et surfaces | Rayons communs ; rayon extérieur dérivé du rayon intérieur et du padding ; contraste augmenté emploie `controlBorder` | Contraste des surfaces système, transparence réduite, hiérarchie visuelle |
| Chargement / erreurs / résultat incertain | `DrivyLoadingState` nommé ; messages persistants ; référence technique derrière une divulgation ; rejouer et vérifier sont des boutons distincts | Annonce dynamique et restauration du focus après mutation |
| Chronologie | Temps tabulaires ; interruptions pointillées ; élément accessible ajustable ; accès alternatif aux observations par boutons précédent/suivant et liste | Cibles de repères rapprochés, focus et ajustement pendant la lecture |

Conclusion : **Approve uniquement les paires mesurées après correction et les mécanismes de source inspectés**. Le point LOW reste ouvert. Compilation Swift des derniers changements, rendu visuel, tailles extrêmes, clavier iPad, VoiceOver et transparence de la carte : **Not verified** par cette revue, à relier à la recette Apple distincte.
