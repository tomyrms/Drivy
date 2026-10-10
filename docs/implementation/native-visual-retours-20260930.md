# Vérification Apple des retours — 30 septembre 2026

Revue des artefacts GitHub Actions téléchargés dans `artifacts/retours-20260930/`. Les PNG retenus ont été ouverts individuellement avec `view_image`, sans retouche. Aucun fichier produit natif ou web n’a été modifié pendant cette vérification.

## Sources et périmètre

| Run | Source SHA | Résultat et usage |
|---|---|---|
| [36722303236](https://github.com/tomyrms/Drivy/actions/runs/36722303236) | `9c77dd64298f5417845a042d1c0e1f88961fa2e0` | Campagne visuelle réussie. Dossier, leçon, observations, progression et replay retenus. Les quatre anciennes captures planning sont exclues. Tests produit sautés dans ce run visuel. |
| [36723305491](https://github.com/tomyrms/Drivy/actions/runs/36723305491) | `cd5a394dd5f87d219837e570c8043f9c5af7f1ed` | Campagne visuelle planning corrigée réussie. Quatre captures retenues. Tests produit sautés dans ce run visuel. |
| [36722630436](https://github.com/tomyrms/Drivy/actions/runs/36722630436) | `fe9fe6bf655d6ba4ce695aa908bc543b675d83e8` | Compilation réussie ; campagne terminée en échec le 30 septembre à 14:04:18 UTC. iPhone : 212/218 tests passés ; iPad : 10/10. Artefacts téléchargés et résultats lus. |
| [36727211560](https://github.com/tomyrms/Drivy/actions/runs/36727211560) | `e4eea1ca365f021045866d4fe2406ff91a037e54` | Reprise complète réussie. iPhone : 218/218 ; iPad : 10/10. Les six tests corrigés passent. IPA 0.7.0 (129) construite et vérifiée. |

24 captures retenues sur 28 téléchargées : six écrans × iPhone/iPad × clair/sombre. Simulateurs iPhone 17 Pro (1206 × 2622 pixels) et iPad Air 11 pouces M4 (1640 × 2360 pixels), portrait, taille système `large` standard. Il ne s’agit pas d’une taille d’accessibilité. Environnement des captures : Xcode 26.6, build 17F113 ; SDK simulateur iOS 26.5 ; Swift 6.3.3 ; macOS 26.6.2.

Les empreintes SHA-256 des images, métadonnées, exclusions et limites détaillées sont dans [la preuve JSON](proofs/native-retours-20260930.json).

## Constats visuels

Aucun chevauchement ni libellé tronqué certain identifié dans les zones de contenu effectivement visibles et non masquées. Les thèmes clair/sombre et la composition séparant liste et carte du replay sur iPad sont visibles. Cela reste une revue partielle :

- **Progression, iPhone clair :** une notification système Apple Intelligence masque le haut de l’écran et une partie du titre. La liste demeure visible. Cette contamination de la capture n’est pas un défaut Drivy ; la zone masquée n’est pas qualifiée.
- **Observations :** les quatre captures montrent uniquement « Aucune observation ». Le panneau de leçon visible sur iPad est aussi vide. Elles ne prouvent donc pas le rendu compact des observations renseignées ni leur visibilité.
- **Planning corrigé :** formation, moniteur et tarif sont présélectionnés ; les détails du rendez-vous sont repliés ; confirmer reste désactivé avant l’accord commercial. Sur iPhone, le bas du tarif et l’accord sont hors du cadrage initial. Le défilement, les liens de bas de formulaire, le lieu déplié et l’enregistrement ne sont pas contrôlés par ces captures.
- **Carte et replay :** les fixtures utilisent des coordonnées synthétiques autour de l’origine, ce qui donne un fond marin sans route réelle. Les commandes et la rupture de timeline sont visibles. Aucun résultat sur la précision GPS, l’alignement sur les routes, la direction ou le déplacement animé du point ne peut en être tiré.
- **Dossier et progression :** liste de leçons, niveaux à trois points et état « Pas encore vu » visibles. Les menus de filtres et les actions de changement de niveau ne sont pas ouverts dans ces captures.

Entre la source visuelle `9c77dd6` et la source des tests `fe9fe6b`, le changement natif concerne `SchoolCaptureLiveView.swift`, écran non montré par cette campagne. Entre `fe9fe6b` et la capture planning `cd5a394`, le changement natif concerne la fixture `SchoolVisualReview.swift`. Ces différences ont été relevées avec un diff limité aux sources Apple, scripts iOS et workflow iOS ; les preuves ne sont pas attribuées automatiquement au HEAD courant.

## Résultats natifs et reprise

Les résumés `Tests/summary.json` et `iPadTests/summary.json` du run initial déclarent respectivement 218 tests (212 réussis, 6 échoués) et 10 tests réussis, avec zéro test déclaré ignoré. Le script exclut néanmoins explicitement `DrivyUITests/VisualOrientationTests` de cette campagne. Sur iPhone, les 208 tests Swift Testing comportent six échecs ; les trois tests de présentation et les sept tests UI passent. Sur iPad, seuls ces trois tests de présentation et sept tests UI sont exécutés. Les simulateurs de tests utilisent iOS 26.4.1. L’IPA du run initial est sautée à cause de l’échec des tests.

Cinq tests `SchoolPlanningDefaultsTests` échouent avant le comportement visé : la fixture omet les champs nullable obligatoires `contactPhone` et `logoAssetId` de l’école, puis `contactEmail` et `contactPhone` de l’élève. Ils ont été rétablis explicitement dans le transport synthétique. Les tests vérifient maintenant leur précondition de chargement avant les actions.

Le sixième échec porte sur l’assertion inline de refus d’une ancre GPS révoquée. Le diagnostic de macro affiche `()` et un appel non évalué ; les assertions suivantes confirment l’absence d’écriture, l’erreur et l’acceptation du geste suivant sans ancre. L’appel est désormais évalué dans une constante Bool avant l’assertion. Aucun code produit n’a été modifié. L’assertion explicite et le scénario complet passent dans la reprise Apple.

La reprise complète se termine avec **218/218 tests iPhone** : 208 Swift Testing, trois de présentation et sept UI. Les **10/10 tests iPad** comprennent trois tests de présentation et sept UI. Les résumés ne déclarent aucun échec ni test ignoré ; `VisualOrientationTests` reste exclu par le script. La compilation a duré de 14:12:11 à 14:15:10 UTC, l’étape de tests de 14:15:10 à 14:38:26, puis la construction IPA de 14:38:26 à 14:45:18. Le job s’est terminé à 14:45:48 UTC. Les résultats ont été vérifiés depuis les artefacts téléchargés, et leurs empreintes sont conservées dans la preuve JSON.

## IPA de la reprise

L’archive **0.7.0 (129)** est disponible dans `artifacts/retours-20260930/native/36727211560/ipa/Drivy.ipa`, SHA-256 `96ae49c04bee0bffd536aa11229af92166ed45b542c897eb4a26b45fca1e6c06`. Vérification locale : CRC ZIP, empreintes du manifeste et des binaires, arm64/iOS dans les commandes Mach-O, absence de commande de signature et de ressources de signature, configuration compilée identique à l’IPA 87. Les deux binaires extraits, Drivy et SQLCipher, sont **octet pour octet identiques à ceux de l’IPA 87**. Le fichier IPA diffère notamment par son numéro de build ; aucune installation ni signature personnelle n’a été réalisée.

## Limites

Pas de validation physique GPS, batterie, VoiceOver, haptique ou installation iLoader. Pas de qualification paysage, grande taille d’accessibilité, clavier ou interaction par la revue des PNG. Pas de donnée réelle de personne ou de trajet utilisée. L’IPA 87, déjà vérifiée séparément par le responsable d’intégration, sert uniquement de référence binaire et de configuration pour comparer l’IPA 129.
