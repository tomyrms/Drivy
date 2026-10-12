# Classement intelligent des signalements — conception, contrat et simulations (13 octobre 2026)

Référence commune de l'API et de l'app iOS. Détail iOS : [classement-intelligent-ios-20261013.md](classement-intelligent-ios-20261013.md). Ordre manuel et catalogue : [signalements-configurables-20261012.md](signalements-configurables-20261012.md).

## Ce qui existait

- L'ordre des signalements est **celui de l'école** : une ligne par école (`drivy.observation_theme_settings`), réglée par l'administration ou un moniteur portant `MANAGE_OBSERVATION_THEMES`. Aucun ordre par moniteur.
- « Signaler » montre les thèmes affichés dans cet ordre, sur trois colonnes, neuf tuiles visibles, le reste en défilant. La palette prend un instantané à chaque ouverture.
- Chaque signalement qualifié est une ligne de `drivy.geo_observation` avec son auteur, sa leçon, son instant et la clé stable de son thème (`theme_key`). Une demande renvoyée par le réseau ne crée pas de seconde ligne (preuve d'opération), et un signalement annulé porte `removed_at`.

## Décisions

1. **L'ordre manuel reste celui de l'école ; le classement intelligent est une préférence par moniteur** (par adhésion). Il se pose au-dessus de l'ordre manuel et ne l'écrit jamais : le désactiver rend l'ordre manuel tel quel.
2. **Désactivé par défaut**, pour tous. Chaque moniteur l'active dans Paramètres → Signalements.
3. **Le serveur classe, l'app applique.** Un seul moteur (`apps/api/src/observation-ranking-engine.ts`), pur et testé sans base ; l'app ne calcule aucun score. Deux appareils du même compte lisent le même ordre.
4. **Aucune table de compteurs.** Les usages se lisent dans `geo_observation` : isolement par auteur et par école, dédoublonnage et annulation sont déjà garantis par l'existant. Un historique accumulé en mode manuel sert dès l'activation.
5. **Le classement porte sur tous les thèmes affichés.** La fenêtre de neuf tuiles n'apparaît dans le moteur que comme une donnée du biais de position ; aucune règle ne distingue les neuf premiers des suivants.
6. **Un reclassement par jour au plus**, à la première lecture du jour (date locale de l'école), sur les usages **des jours précédents**. Les leçons du jour ne déplacent rien le jour même.
7. **Figé pendant la leçon, côté app** : l'ordre est pris à la première ouverture de « Signaler » d'une leçon, gardé sur l'appareil pour cette leçon, et retrouvé après un passage en arrière-plan, un arrêt de l'app ou une reprise.

Non retenu : un ordre manuel personnel à chaque moniteur. La demande parle de « son dernier ordre manuel » ; l'ordre manuel existant est celui de l'école, et un moniteur sans droit de gestion ne le règle pas. Lui donner un ordre personnel serait une autre fonction. **À confirmer par le porteur.**

## Moteur

Entrées : l'ordre manuel des thèmes affichés, le classement précédent, les usages du moniteur (thème, leçon, jour local, nombre, rang de la tuile au moment du geste).

### Score d'un thème

```
score = a_priori + preuve × confiance
preuve    = Σ leçons  min(log2(1 + usages), 3) × poids_position × 2^(−âge / 12)
confiance = n / (n + 2)        n : nombre de leçons où le thème a servi, pondéré de la même décroissance
a_priori  = 1 − rang_manuel / nombre_de_thèmes
```

| Mécanisme | Paramètre | Pourquoi |
|---|---|---|
| **Fréquence saturée par leçon** | `log2(1 + usages)`, plafond 3 | Une leçon vaut 1 pour un usage, 2 pour trois, 3 à partir de sept. Quarante répétitions dans une leçon pèsent autant que sept : une leçon ne bouleverse pas le classement. |
| **Récence** : moyenne mobile exponentielle | demi-vie de **12 jours d'activité** | L'âge se compte en jours où le moniteur a signalé, pas en jours de calendrier. Douze jours d'activité, c'est un peu plus de deux semaines de travail à temps plein : les habitudes des dernières semaines dominent celles d'il y a plusieurs mois. Des vacances n'érodent rien, et un moniteur occasionnel s'adapte pour la même quantité de leçons qu'un moniteur très actif. Fenêtre : 120 jours d'activité (poids restant : 0,1 %), 400 jours de calendrier au plus. |
| **Seuil d'observations** | 2 leçons distinctes | Un usage isolé ne compte pas du tout. |
| **Lissage bayésien** (rétrécissement) | constante de 2 leçons | La preuve est multipliée par `n / (n + 2)` : 50 % de son poids à deux leçons, 83 % à dix. Un thème rarement utilisé n'est pas survalorisé par quelques usages. |
| **A priori** | de 1 (premier de l'ordre manuel) à 0 | Sans historique, le classement est l'ordre manuel. Les thèmes jamais utilisés gardent entre eux l'ordre de l'école. Dès qu'un thème sert régulièrement, sa preuve (plusieurs unités) domine cet a priori. |
| **Biais de position** | +25 % par rangée à défiler, plafond ×2 | Voir plus bas. |

### Stabilité

À partir du classement précédent, chaque thème monte juste au-dessus du plus haut thème qu'il **domine nettement** ; il ne descend que parce qu'un autre le dépasse.

- **Hystérésis statistique.** A domine B si `score(A) − score(B) > 1,5 × √((preuve(A) + preuve(B)) / 2) + 0,3`. La racine est l'écart-type du bruit de la différence (une somme décroissante d'usages a une variance proche de sa moitié) : un dépassement n'a lieu que si l'écart est significatif, à environ 1,5 écart-type. Pour deux thèmes très utilisés, la marge vaut une dizaine de pour cent ; pour deux thèmes peu utilisés, elle est proportionnellement plus large, là où le bruit l'est aussi. La même marge vaut dans les deux sens : une fois A passé devant B, B doit à son tour dominer A pour revenir. Deux thèmes aux scores proches gardent donc leur ordre. Le terme fixe de 0,3 empêche les thèmes sans usage de permuter.
- **Limite de montée.** Six places (deux rangées) par jour écoulé depuis le dernier classement. Ce n'est pas un plafond d'adaptation : un thème peut passer de la 25e à la 1re place en quatre jours si ses usages le justifient, et la limite grandit avec l'absence. Elle écarte seulement le saut de dix places d'un jour au lendemain.
- **À l'activation**, il n'y a pas de classement précédent : le tri repart des scores seuls (égalités départagées par l'ordre manuel).
- **Déterminisme.** Mêmes entrées, même sortie ; recalculer sans nouvel usage ne change rien (testé).

### Biais de position

Une tuile visible sans défiler est plus utilisée, à habitude égale, qu'une tuile qu'il faut aller chercher : les premiers resteraient premiers. Correction retenue, sans aucun hasard ni réorganisation exploratoire :

- le service note sur chaque signalement le **rang de la tuile au moment du geste** (`geo_observation.palette_position`), d'après l'ordre effectif du moniteur ; l'app n'envoie rien de plus ;
- un usage fait sous la fenêtre pèse davantage : ×1,25 pour la première rangée à défiler, ×1,5, ×1,75, puis ×2 au plus. C'est une pondération par l'inverse de la propension, **bornée** (pratique courante pour ne pas amplifier le bruit) : aller chercher une tuile en défilant dit plus qu'un toucher sur une tuile sous le doigt ;
- dans la fenêtre visible, toutes les positions pèsent 1 : neuf tuiles à un toucher, sans différence d'accès mesurable.

Dans les simulations, cette correction fait entrer plus vite dans la fenêtre un thème qui devient habituel (15 jours travaillés au lieu de 17 depuis la 25e place) et améliore la fenêtre des premières semaines. Effet de bord accepté : en queue de classement, un thème peu utilisé mais atteint en défilant peut précéder un voisin à peine plus utilisé. Le rang noté est celui du classement connu du service ; pendant une leçon ouverte la veille d'un reclassement, l'app peut montrer l'ordre figé précédent (écart d'un jour au plus).

### Cas traités

| Cas | Comportement |
|---|---|
| Nouveau moniteur, aucun historique | Le classement est l'ordre de l'école. |
| Un usage isolé | Aucun déplacement (seuil de deux leçons). |
| Répétitions dans une leçon | Preuve plafonnée à 3 pour la leçon. |
| Périodes sans utilisation | Aucun déplacement : l'âge se compte en jours d'activité. |
| Thème rarement utilisé | Preuve rétrécie ; il reste près de son rang manuel. |
| Changement progressif ou brutal | La preuve ancienne perd la moitié de son poids tous les douze jours d'activité. |
| Moniteur très actif ou occasionnel | Même adaptation pour une même quantité de leçons. |
| Thème masqué par l'école | Retiré aussitôt du classement publié ; ses usages restent en base. |
| Thème réaffiché ou ajouté | S'il n'est plus dans le classement enregistré : en fin le jour même, puis placé d'après son score au reclassement suivant, sans limite de montée (aucune place apprise à préserver). |
| Thème renommé | La clé est stable : rien ne change. |
| Clé inconnue (catalogue plus récent ou plus ancien) | Ignorée ; l'app range en fin les thèmes affichés absents de l'ordre reçu. |
| Demande réseau dupliquée | Une seule ligne d'observation (preuve d'opération existante). |
| Signalement annulé | `removed_at` : il ne compte plus. |
| Ordre de l'école modifié | L'a priori suit au reclassement suivant ; les thèmes utilisés ne bougent pas pour autant. |

Limite : une compétence d'un référentiel propre à l'école qu'aucun thème du catalogue ne désigne (moto, remorque) garde sa tuile générique après les thèmes classés, comme aujourd'hui. Elle n'a pas de clé de thème, donc pas de statistique.

## Données

Migration `028_observation_ranking.sql` :

- `drivy.observation_ranking` — une ligne par adhésion, créée au premier réglage : `mode` (`MANUAL`/`SMART`), `ranked_order` (dernier classement), `ranked_on` (date locale), `version`. RLS forcée : chacun ne lit et n'écrit que sa ligne, dans son école ; ni un collègue ni l'administration n'y accèdent.
- `geo_observation.palette_position` — rang de la tuile au moment du geste, noté par le service ; absent pour l'existant.
- `drivy.observation_theme_usage(school, zone)` — fonction qui rend, pour le compte courant, ses usages par thème, leçon et jour local jusqu'à la veille (signalements faits dans la palette, non annulés). Elle ne rend que des compteurs de ses propres gestes et ne dépend pas de l'attribution actuelle de l'élève : un changement de moniteur n'efface pas les habitudes de celui qui a signalé.
- Index `geo_observation_author_theme` pour cette lecture.
- Commandes `SAVE_OBSERVATION_RANKING` et `REFRESH_OBSERVATION_RANKING`, audit `ObservationRankingSaved` et `ObservationRankingRefreshed`.

| Ce qu'il faut garder | Où |
|---|---|
| Mode choisi | `observation_ranking.mode` |
| Ordre manuel | `observation_theme_settings` (inchangé, jamais écrit par le classement) |
| Statistiques d'usage | `geo_observation` (`theme_key`, auteur, leçon, instant, `palette_position`, `removed_at`) |
| Classement global | `observation_ranking.ranked_order`, `ranked_on` |
| Ordre figé d'une leçon | sur l'appareil, par leçon |

## API

### Lire

`GET /v1/schools/{schoolId}/observation-ranking`

```json
{"data": {"id": "<membershipId>", "schoolId": "<schoolId>", "membershipId": "<membershipId>", "version": 4,
          "mode": "SMART", "order": ["indicators", "speed", "vehicle"], "rankedOn": "2026-10-13"},
 "requestId": "...", "serverTime": "..."}
```

- `mode` vaut `MANUAL` tant que le moniteur n'a rien activé (`version` 1, `order` vide, `rankedOn` nul). En-tête `ETag: "<version>"`.
- En mode `SMART`, `order` contient **toutes** les clés des thèmes affichés par l'école, dans l'ordre du classement.
- En mode `SMART`, la première lecture d'un jour refait le classement et le garde, dans une commande à part (`REFRESH_OBSERVATION_RANKING`, identifiant d'opération dérivé de l'adhésion et du passage d'un jour au suivant) : deux lectures simultanées donnent un seul reclassement et la même réponse. `version` n'augmente que si l'ordre a changé. Les lectures suivantes du jour ne calculent rien.
- 403 pour un élève seul ou un compte étranger à l'école.

### Changer de mode

`PUT /v1/schools/{schoolId}/observation-ranking` avec `If-Match: "<version>"` et `Idempotency-Key: <operationId>`

```json
{"operationId": "<uuid>", "mode": "SMART"}
```

- 200 : la même projection, `version` augmentée de 1. Activer classe aussitôt d'après l'historique. Désactiver ne publie plus d'ordre ; le dernier classement reste en base sans effet, l'ordre de l'école n'a jamais été touché.
- 412 `VERSION_CONFLICT` (changé depuis un autre appareil, ou reclassé entre-temps : relire), 428 sans `If-Match`, 400 pour toute autre forme, 403 sans rôle `ADMIN` ou `INSTRUCTOR`.
- Rejouable avec le même `operationId` ; consultable par son auteur via `GET /operations/{operationId}`.

Une API antérieure répond 404 : l'app n'affiche alors pas l'option.

### Observations

Le contrat de `POST /lessons/{lessonId}/geo-observations` ne change pas. Le service note `palette_position` pour un signalement `LIVE` portant un `themeKey`.

## Déploiement

1. Sauvegarde de la base, migration 028, puis API.
2. L'app ensuite. Une app plus récente que l'API reçoit 404 et masque l'option ; une app plus ancienne ignore la route.

Rien n'est déployé.

## Simulations

`apps/api/scripts/simulate-observation-ranking.ts` (résultats ci-dessous) et `apps/api/test/observation-ranking.test.ts` (les mêmes scénarios en assertions, dans `npm run test:unit`). Moniteur simulé : préférences de Zipf sans rapport avec l'ordre manuel, 6 leçons par jour travaillé (5 jours sur 7), 4 signalements par leçon en moyenne ; quand la tuile voulue demande de défiler, il renonce dans 20 % des cas par rangée (60 % au plus) et se rabat alors une fois sur deux sur une tuile visible. Huit graines par scénario.

Stratégies comparées :

- `count` — tri par nombre total d'usages ;
- `ewma` — tri par usages pondérés d'une demi-vie de trente jours de calendrier ;
- `engine-no-hysteresis` — le score retenu, trié sans hystérésis ni limite ;
- `engine-no-position` — le moteur sans correction du biais de position ;
- `engine-no-cap` — le moteur sans limite de montée ;
- `engine` — **le moteur retenu**.

« Fenêtre utile » : part des signalements voulus dont la tuile était visible sans défiler, rapportée au mieux possible (les neuf thèmes les plus voulus toujours dans la fenêtre).

### Régime établi, 9 thèmes (6 leçons/jour, 4 signalements/leçon, 20 semaines)

| Stratégie | Fenêtre utile, sem. 1-4 | Fenêtre utile, sem. 13-20 | Tuiles déplacées / jour (sem. 13-20) | Jours sans aucun mouvement |
|---|---|---|---|---|
| count | 100.0 % | 100.0 % | 0.17 | 92 % |
| ewma | 100.0 % | 100.0 % | 0.48 | 78 % |
| engine-no-hysteresis | 100.0 % | 100.0 % | 1.02 | 55 % |
| engine-no-position | 100.0 % | 100.0 % | 0.08 | 96 % |
| engine-no-cap | 100.0 % | 100.0 % | 0.08 | 96 % |
| engine | 100.0 % | 100.0 % | 0.08 | 96 % |

### Régime établi, 18 thèmes (6 leçons/jour, 4 signalements/leçon, 20 semaines)

| Stratégie | Fenêtre utile, sem. 1-4 | Fenêtre utile, sem. 13-20 | Tuiles déplacées / jour (sem. 13-20) | Jours sans aucun mouvement |
|---|---|---|---|---|
| count | 94.2 % | 98.9 % | 0.74 | 69 % |
| ewma | 94.5 % | 99.7 % | 2.18 | 34 % |
| engine-no-hysteresis | 94.7 % | 98.3 % | 4.42 | 9 % |
| engine-no-position | 88.3 % | 97.7 % | 0.41 | 84 % |
| engine-no-cap | 92.1 % | 98.6 % | 0.69 | 74 % |
| engine | 91.2 % | 98.8 % | 0.63 | 76 % |

### Régime établi, 30 thèmes (6 leçons/jour, 4 signalements/leçon, 20 semaines)

| Stratégie | Fenêtre utile, sem. 1-4 | Fenêtre utile, sem. 13-20 | Tuiles déplacées / jour (sem. 13-20) | Jours sans aucun mouvement |
|---|---|---|---|---|
| count | 85.2 % | 98.1 % | 3.63 | 18 % |
| ewma | 87.2 % | 99.9 % | 6.56 | 10 % |
| engine-no-hysteresis | 87.5 % | 99.7 % | 10.85 | 1 % |
| engine-no-position | 76.2 % | 97.8 % | 1.18 | 71 % |
| engine-no-cap | 83.9 % | 99.8 % | 2.68 | 48 % |
| engine | 81.0 % | 99.6 % | 2.51 | 49 % |

### Montée de la 25e place et déclin de la 2e (30 thèmes ; le changement s’étale sur six semaines à partir du jour 56)

| Stratégie | Jours travaillés pour entrer dans les 9 | … dans les 3 | Plus grand saut en un jour | Place finale du thème monté | Jours travaillés pour que l’ancien 2e quitte les 9 | Place finale de l’ancien 2e |
|---|---|---|---|---|---|---|
| count | 22 | 42 | 5 | 2.0 | jamais | 5.1 |
| ewma | 15 | 27 | 12 | 1.0 | 77 | 13.0 |
| engine-no-hysteresis | 12 | 23 | 11 | 1.1 | 50 | 23.4 |
| engine-no-position | 17 | 26 | 6 | 1.3 | 61 | 14.3 |
| engine-no-cap | 16 | 25 | 8 | 1.4 | 57 | 18.6 |
| engine | 15 | 25 | 6 | 1.3 | 57 | 18.8 |

### Deux thèmes à égalité (18 thèmes, 20 semaines) : échanges de place entre eux

| Stratégie | Échanges (moyenne) | Échanges (maximum) |
|---|---|---|
| count | 2.8 | 8 |
| ewma | 6.8 | 21 |
| engine-no-hysteresis | 7.3 | 16 |
| engine-no-position | 0.5 | 2 |
| engine-no-cap | 0.6 | 2 |
| engine | 0.6 | 2 |

### Changement brutal des habitudes au jour 70 (18 thèmes)

| Stratégie | Fenêtre utile, 2 semaines après | … 4 semaines après | … 8 semaines après | Tuiles déplacées / jour (4 semaines après) |
|---|---|---|---|---|
| count | 74.6 % | 82.9 % | 89.4 % | 2.13 |
| ewma | 78.7 % | 92.8 % | 95.1 % | 3.77 |
| engine-no-hysteresis | 85.4 % | 96.5 % | 98.0 % | 6.00 |
| engine-no-position | 79.7 % | 89.8 % | 94.1 % | 2.24 |
| engine-no-cap | 84.8 % | 93.2 % | 96.3 % | 2.73 |
| engine | 84.8 % | 91.8 % | 95.4 % | 2.88 |

### Quatre semaines sans utilisation (jours 70 à 97), 18 thèmes

| Stratégie | Tuiles déplacées pendant l’absence | Tuiles déplacées le jour de la reprise |
|---|---|---|
| count | 0.0 | 1.6 |
| ewma | 0.0 | 2.5 |
| engine-no-hysteresis | 0.0 | 4.3 |
| engine-no-position | 0.0 | 0.5 |
| engine-no-cap | 0.0 | 0.0 |
| engine | 0.0 | 0.0 |

### Une leçon avec 40 répétitions du dernier thème (18 thèmes, jour 70)

| Stratégie | Place avant | Place le lendemain | Place une semaine après |
|---|---|---|---|
| count | 16.4 | 7.5 | 8.0 |
| ewma | 17.0 | 4.5 | 4.9 |
| engine-no-hysteresis | 16.8 | 14.0 | 14.0 |
| engine-no-position | 16.9 | 16.9 | 16.6 |
| engine-no-cap | 16.6 | 15.9 | 15.1 |
| engine | 16.9 | 16.1 | 15.4 |

### Moniteur très actif (8 leçons/jour, 5 j/7) et occasionnel (2 leçons/jour, 2 j/7) : montée d’un thème de la 16e place (18 thèmes, moteur retenu)

| Moniteur | Jours de calendrier pour entrer dans les 9 | Jours travaillés | Tuiles déplacées / jour travaillé |
|---|---|---|---|
| très actif | 3.5 | 3.3 | 0.7 |
| occasionnel | 18.8 | 5.1 | 0.8 |

Paramètres : {"halfLifeActiveDays":12,"windowActiveDays":120,"lessonCap":3,"foldSize":9,"columns":3,"rowBoost":0.25,"maxPositionWeight":2,"minimumLessons":2,"confidenceLessons":2,"priorSpan":1,"significance":1.5,"absoluteMargin":0.3,"climbPerDay":6}

### Lecture

- **Stabilité.** À 18 thèmes, le moteur déplace 0,6 tuile par jour en régime établi et ne change rien trois jours sur quatre ; le même score trié sans hystérésis en déplace 4,4 et bouge neuf jours sur dix. Deux thèmes à égalité échangent leur place 0,6 fois en vingt semaines, contre 2,8 (fréquence) et 6,8 (moyenne mobile).
- **Adaptation.** Un thème parti de la 25e place sur 30 entre dans la fenêtre en trois semaines de travail et dans les trois premiers en cinq, pendant que ses usages montent ; le tri par fréquence met plus de huit semaines et ne fait jamais sortir l'ancien deuxième de la fenêtre. Après un changement brutal, la fenêtre retrouve 85 % de son utilité en deux semaines et 92 % en quatre.
- **Robustesse.** Quarante répétitions dans une leçon font gagner moins d'une place ; le tri par fréquence en fait gagner neuf, la moyenne mobile douze. Quatre semaines d'absence ne déplacent rien.
- **Prix de la stabilité.** Les quatre premières semaines d'un moniteur parti sans historique sont un peu moins bonnes qu'avec un tri nu (91 % contre 94 % à 18 thèmes) : l'hystérésis attend que l'écart soit significatif. Un moniteur qui active l'option avec un historique n'attend pas : le premier classement part des scores seuls.
- **Stratégies écartées.** Le tri par fréquence ne s'adapte pas et cède aux répétitions. La moyenne mobile seule s'adapte mais bouge sans cesse. Sans la correction de position, la fenêtre des premières semaines est moins bonne et la montée plus lente. Sans la limite de montée, les résultats sont proches ; elle est gardée pour borner le plus grand saut (6 places au lieu de 8 d'un jour ouvré au suivant).

Ces chiffres valent pour le moniteur simulé : ils comparent des stratégies, ils ne mesurent pas un usage réel. Les paramètres sont regroupés dans `rankingParameters` et pourront être ajustés sur des usages observés.

## Vérification

| Sujet | Vérifié par |
|---|---|
| Moteur, pour 1 à 64 thèmes ; seuil, saturation, récence, absence, position, hystérésis, limite, déterminisme | `observation-ranking.test.ts` (25 tests, exécutés) |
| 9, 18 et 30 thèmes ; montée de la 25e place ; déclin de la 2e ; égalité ; absence ; changement brutal ; répétitions ; actif et occasionnel ; historique de plusieurs milliers de signalements ; coût | mêmes tests (simulations à graines fixes, exécutées) |
| Désactivé par défaut ; activation par un moniteur sans droit de gestion ; version, idempotence, audit, conflit | `observation-ranking.integration.test.ts` (PostgreSQL, sur la CI) |
| Retour au mode manuel sans toucher à l'ordre de l'école | idem |
| Un reclassement par jour ; deux lectures simultanées (deux appareils) : même ordre, un seul calcul | idem |
| Signalement du jour sans effet le jour même ; rang de tuile noté | idem |
| Thème masqué puis réaffiché | idem |
| Isolement entre moniteurs, avec l'administration et entre écoles, en base (RLS) | idem |
| Ordre figé pendant la leçon, reprise, hors ligne, écran de réglage | tests Swift (voir la note iOS) |

Coût mesuré : 0,7 ms pour classer 30 thèmes sur 31 798 signalements (12 650 lignes d'usage). En service, le calcul a lieu une fois par jour et par moniteur ; ouvrir « Signaler » ne calcule rien.

## Limites connues

- Rien n'est déployé ; la migration 028 n'a tourné que sur la CI.
- Les tuiles génériques d'un référentiel propre à l'école ne sont pas classées.
- Le web n'a pas de réglage : la préférence appartient au moniteur, sur le terrain. La console de l'école continue de régler l'ordre manuel.
- La position notée est celle que le service connaît, pas celle que l'app a réellement montrée (formation dont le référentiel ne porte pas tous les thèmes, ordre figé de la veille).
- Les paramètres viennent de simulations, pas d'usages mesurés.
