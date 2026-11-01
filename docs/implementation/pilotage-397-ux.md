# Pilotage, Statistiques et Finances : passe UX #397

1er novembre 2026, branche `claude/pilotage-397-ux`, base `master` `ddf9329b` (pilotage #373 déployé en web seul). Fusionné par la PR #398 (`6884dcc7`) et déployé en web seul le même soir (section 8). Web seulement : aucune modification d'API, de contrat OpenAPI, de migration, de calcul ni de droit.

## 1. Méthode

- **Impeccable** (`.claude/skills/impeccable`) : chargement de contexte (`impeccable context`, DESIGN.md web #311 trouvé, pas de PRODUCT.md : travail à partir du code), méthode `critique` (heuristiques de Nielsen, charge cognitive, personas), puis `layout` et `distill` pour la recomposition, socle `craft-floor` relu avant toute modification, détecteur mécanique en fin de travail.
- **Critique en un seul contexte** : la méthode d'Impeccable veut deux sous-agents isolés. Le porteur a demandé de traiter une issue à la fois sans agents (30 octobre) : critique menée seul, d'abord la lecture de conception, ensuite seulement le détecteur.
- **Uncodixfy** : absent de la machine et du registre ui-skills. Lu depuis son dépôt public `cyxzdev/Uncodixfy` (commit `e0e028058b52`, licence MIT), puis installé à la demande du porteur dans `Drivy/.claude/skills/uncodixfy/` (non versionné, comme Impeccable) et chargé par l'outil Skill. Une règle n'est volontairement pas suivie : « pas de bleu ». Le cobalt #245BD6 est la couleur figée de la marque, et Uncodixfy place lui-même la palette du projet en premier.
- **Détecteur Impeccable** : en ligne de commande sur `apps/web/client/portal/pilotage` et injecté dans l'aperçu (3 vues, 1440 et 390 px, clair et sombre), avant et après : **aucun motif mécanique** (ni dégradé, ni lueur, ni vitre). Les défauts étaient de composition, ce que le détecteur ne voit pas.

## 2. Constat avant modification

Captures : `.local/captures-397/avant/` (non versionné).

| # | Heuristique | Note | Constat principal |
|---|---|---|---|
| 1 | État du système | 3 | « calculé à », badges Partiel, chargement nommé ; bon |
| 2 | Correspondance au réel | 3 | vocabulaire métier juste ; « vs le 1 octobre » au lieu de « 1er » |
| 3 | Contrôle et liberté | 3 | filtres dans l'adresse, retour du détail avec focus |
| 4 | Cohérence | 2 | tuiles, listes et graphiques sans langage commun ; onglets soulignés en tête, onglets en pilule dans les graphiques ; ligne de portée placée différemment selon la page ; une boîte par jour de rendez-vous |
| 5 | Prévention des erreurs | 3 | période libre validée |
| 6 | Reconnaissance | 2 | en Finances, la relation réalisé + à venir = attendu n'est pas visible ; valeurs dispersées dans des cartes, impossibles à comparer verticalement |
| 7 | Efficacité | 2 | graphique au clavier, mais 14 « Voir le détail » à parcourir |
| 8 | Esthétique minimaliste | 2 | 14 cartes en Activité, rangées à moitié vides (Élèves : une carte), mobile de 3 872 px |
| 9 | Reprise après erreur | 3 | « Réessayer », chiffres connus conservés avec leur heure |
| 10 | Aide | 3 | formule de chaque mesure à la demande |
| | **Total** | **26/40** | |

**Spécificité** : la mosaïque de cartes « grand chiffre, petit libellé » est le gabarit de tableau de bord générique ; rien n'y dit « relevé d'auto-école ».

**Problèmes prioritaires**

1. **[P1] Mosaïque de cartes KPI** (Uncodixfy : « KPI cards in a grid as the default dashboard layout », « No metric-card grid as the first instinct » ; Impeccable : « hero-metric template », « identical card grids »). Correctif : relevé à lignes, valeurs alignées à droite.
2. **[P1] Finances : la somme est invisible.** Trois cartes égales pour réalisé, à venir et attendu ; « En attente de constat, hors du total » est un groupe à part qui ressemble aux autres. Correctif : ligne de total sous un filet, termes signés, l'attente après le total.
3. **[P2] Mobile en « long sandwich »** (Uncodixfy) : Activité 3 872 px, une carte par mesure.
4. **[P2] Vocabulaire incohérent** : onglets en pilule (Uncodixfy : « Tabs: no pill backgrounds ») dans les graphiques, alors que l'agenda utilise un contrôle segmenté ; cinq boîtes pour les rendez-vous d'une semaine.
5. **[P3] Graphiques** : une seule graduation (le maximum brut, par exemple 2 850 CHF), hachure dense qui vibre sur un mois entièrement à venir, ligne de lecture vide réservée sous chaque graphique, période répétée sur chaque graphique alors que la page la dit déjà.

**Personas.** *Direction pressée (power user)* : doit lire 14 cartes pour retrouver un chiffre, sans comparaison verticale. *Secrétariat occasionnel* : en Finances, rien ne dit que le total attendu est la somme des deux premières cartes, ni que l'attente n'en fait pas partie, sauf à ouvrir l'aide.

## 3. Composition retenue : le relevé

- **Mesures en lignes** (`MeasureRow`, `MeasureList`, `MeasureGroups`) : libellé et aide à gauche, valeur à droite en chiffres tabulaires, comparaison nommée sous la valeur (sous le libellé sur téléphone), badge seulement pour l'inhabituel. La valeur d'une mesure détaillable est le bouton (chevron = ouvrir, comme `DrivyNavigationRow`) ; son nom accessible dit « Leçons annulées : 3. Voir le détail ». Une valeur sans détail garde la place du chevron : toutes les valeurs d'un groupe tombent sur le même bord.
- **Deux colonnes sur écran large** : Activité, leçons, non finalisées et élèves | heures et cours collectifs ; Finances, valeur des leçons | règlements enregistrés et cours collectifs. Une colonne sur téléphone ; seul « Élèves » y passe avant « Heures ».
- **Finances** : « Valeur des leçons réalisées », « + Valeur des leçons à venir », puis « Total attendu selon le planning » sous un filet plein, puis « Valeur en attente de constat · hors du total » en ton atténué, après le total. Le signe est décoratif (`aria-hidden`). Cette mise en somme reprend la définition du serveur, sans rien recalculer : `moneyMeasures` (`apps/api/src/school-metrics.ts`) calcule F03 comme la somme des valeurs connues de F01 et F02, partielle si l'une ne l'est pas ; le dictionnaire le dit (« Réalisé plus à venir »). Les règlements (F05, F06) sont dans l'autre colonne, sous leur titre « par date de saisie ». Les quatre notions restent séparées et nommées par le dictionnaire.
- **Tableau de bord** : la phrase du jour garde sa forme, le nombre de leçons en gras ; « À traiter » devient des lignes avec « Ouvrir l'agenda » (une action d'une autre nature garde un bouton nommé) et « Rien à traiter » une ligne calme ; les rendez-vous forment une seule liste à bandeaux de jour ; « Ce mois-ci » et « Finances du mois » sont côte à côte (la seconde seulement avec le droit), l'évolution du mois dessous, pleine largeur.
- **Graphiques** : graduations rondes (1, 2 ou 5 fois une puissance de dix, au plus quatre intervalles, `niceScale`) avec repères pointillés ; hachure plus calme sur fond `accent` ; une seule ligne sous le dessin, légende au repos et lecture de la barre active, la lecture restant annoncée par une région polie masquée ; la période n'est plus répétée sur chaque graphique (elle reste dans le résumé et le tableau des valeurs) ; « Par date de saisie » reste visible sur les règlements. Choix de répartition : le contrôle segmenté de l'agenda (`ToggleGroup` outline) au lieu d'onglets en pilule.
- **Statistiques** : barre d'onglets Activité / Finances sur toute la largeur avec son filet, filtres dessous, sans chevauchement.
- **Dates** : « 1er » pour le premier du mois (`formatCivil`, `formatSpan`), tests mis à jour et complétés.
- **Mutualisation** : une seule ligne de mesure au lieu de la tuile, une seule liste cadrée (`.pilotage-list`) pour les rendez-vous et les lignes d'une mesure, `coverageBadge` partagé avec le détail.

## 4. Ce qui ne change pas

Calculs et valeurs (affichées telles que le serveur les rend), droits (`metricRights` et conditions d'affichage inchangées), adresses et filtres, libellés du dictionnaire, règles de comparaison (`comparisonPlan`, `comparableToDate`), aide au calcul, détail et export, états de lecture. Les titres de niveau 2 « Aujourd'hui » et « Prochains rendez-vous » qu'attend `scripts/dev/check-school-opening.ts` sont conservés.

## 5. Avant / après (aperçu synthétique, Edge)

| Vue | 1440 px avant → après | 390 px avant → après |
|---|---|---|
| Tableau de bord | 2 325 → 2 106 px | 3 261 → 2 720 px |
| Statistiques · Activité | 2 124 → 1 676 px | 3 872 → 2 790 px |
| Statistiques · Finances | 2 059 → 1 541 px | 3 198 → 2 617 px |

Captures : `.local/captures-397/avant/`, `apres/` (16 images, clair et sombre, avec le détail d'une mesure) et `etats/` (chargement, erreur, vide).

Auto-évaluation après coup, sur les mêmes heuristiques (ce n'est pas une seconde critique indépendante) : cohérence 3, reconnaissance 3, esthétique 3, soit 29/40.

## 6. Vérification exécutée (locale)

- `npm run typecheck` (web) : sans erreur. `npx vitest run` (web) : 57 fichiers, 593 tests réussis, 1 échec attendu déjà présent. Build de production et build de l'aperçu : réussis.
- Captures 1440 et 390 px, clair et sombre, quatre vues : aucun défilement horizontal, aucune erreur JavaScript, aucun texte de graphique sous 9 px.
- `etats.py` (Edge, aperçu synthétique) : **32 contrôles PASS** : zoom 200 % et 400 % (largeurs 720 et 360), paysage 844×390 et 320 px sans défilement horizontal ; montants Finances identiques à ceux du serveur ; F02 terme, F03 total, F04 hors du total ; règlements dans l'autre colonne ; F07 tiret et badge ; signe masqué aux lecteurs d'écran ; nom accessible de la valeur ouvrante ; Entrée ouvre le détail, retour avec focus sur la ligne d'origine ; flèche droite lit la barre suivante, région polie, légende rendue au départ du focus ; chargement nommé sans ligne d'une autre période ; erreur sans zéro ni ligne, reprise par « Réessayer » ; période à zéro : aucun détail ouvrable, graphiques vides nommés ; tableau de bord « Rien à traiter » ; aucune erreur JavaScript. Script et journal dans `.local/captures-397/`.
- Détecteur Impeccable sur les fichiers modifiés : aucun motif.

## 7. Limites et reste à qualifier

- **Non exécuté avant la PR** : CI GitHub et déploiement (faits ensuite, section 8) ; vraie API et vraies données (aperçu synthétique seulement) ; lecteur d'écran réel (NVDA, VoiceOver), appareil physique, texte agrandi par le système ; `prefers-contrast: more` et `forced-colors` (règles écrites, pas capturées) ; test navigateur `check-school-opening.ts`.
- **Droits** : l'aperçu tourne en administrateur, la vue sans droit financier n'a pas été regardée ; le code des droits n'a pas changé.
- **Restes visibles** : sur téléphone, l'aide d'un libellé long passe à la ligne ; les quatre filtres de Statistiques restent empilés (environ 320 px) ; l'onglet « Tableau de bord » et le titre de page se répètent (cadre commun du portail, hors périmètre) ; le mois sans donnée affiche toujours « 0 vs le 1er octobre » (comparaison zéro contre zéro, remarque du 1er novembre non traitée).
- **À valider à l'œil par le porteur** : le relevé à la place des cartes ; le signe et le filet de total en Finances ; « Finances du mois » à côté de « Ce mois-ci » ; le contrôle segmenté des répartitions.

## 8. Fusion et déploiement

- PR #398 : CI verte (Web et BFF, contrats documentaires, test navigateur `check-school-opening.ts` sur la vraie pile OIDC · BFF · API · PostgreSQL), fusionnée en `6884dcc7`.
- Déployé en web seul le 1er novembre 2026 vers 20 h 13, à la demande du porteur : reçu `20261101T191307Z-6884dcc7b367`, sauvegarde `/root/drivy_refonte-before-web311-20261101T191307Z.dump`, précédent `8d6350c5`. SHA servi vérifié sur https://drivy.shulker.ch/app/. Aperçu synthétique republié (`20261101T191425Z-6884dcc7b367`).
- Retour arrière : `deploy-web-311.py --rollback 20261101T191307Z-6884dcc7b367` puis `--execute`.
- Reste : l'essai du porteur en production avec une vraie école et ses chiffres réels.
