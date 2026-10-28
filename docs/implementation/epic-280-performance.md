# EPIC #280 — W29, comparaison de performance courte

Mesures du 28 octobre 2026, à 19:11 UTC. Le candidat affiche le contenu utile environ 50 ms plus tard sur desktop et 81 ms plus tard sur mobile dans ce contrôle local. Les changements de mise en page diminuent en médiane, avec une dispersion notable sur mobile. Aucun gain de vitesse en production n’est établi.

## Périmètre et méthode

- Avant : serveur local `http://127.0.0.1:5186`, révision `e5166404ca06a7bd804ecf032f673a4afe790007` archivée dans `C:/Users/jtoma/AppData/Local/Temp/drivy-web-baseline-e5166404` ; après : worktree non commité `codex/epic-280-web`, candidat EPIC #280 sur `http://127.0.0.1:5187`. Provenance de la base confirmée par le coordinateur après mesure.
- Même Chromium Microsoft Edge `156.0.4314.50`, headless Windows, sans limitation CPU ni réseau des modules. Contexte navigateur neuf à chaque passage, thème clair, mouvement réduit, français suisse et fuseau Europe/Zurich.
- Trois passages par version et largeur, en ordre alterné avant/après puis après/avant : 12 parcours courts au total. Viewports 1440 × 900 et 390 × 900. Pas d’émulation matérielle de téléphone.
- Fixture `page=agenda&agenda=mixed&shell=1`, puis clic sur Élèves et recherche « Éloïse ». Le jeu synthétique contient deux élèves. Les données élèves/leçons/cours comparées ont le même SHA-256 dans les 12 passages.
- Les réponses métier sont simulées dans la fixture, avec une latence identique de 120 ms par requête. Les modules et styles restent servis par Vite en développement sur loopback ; le cache HTTP du navigateur est désactivé par l’interception Playwright. Les serveurs avaient déjà servi les revues visuelles : ce n’est pas une mesure de compilation Vite à froid.
- Instrumentation injectée avant React, sans modifier le produit. `PerformanceObserver` relève les peintures et les `layout-shift`. Les durées d’interaction commencent à l’événement navigateur, pas à l’appel Playwright.

Le **rendu utile** correspond au premier élément d’agenda chargé, sans indicateur de chargement visible dans `main`, puis deux frames d’animation. La **navigation** va du clic sur le lien Élèves à deux lignes d’élèves chargées puis deux frames ; l’ouverture du menu mobile est exclue. La **recherche** va de l’événement `input` contenant le terme complet à l’unique ligne correspondante puis deux frames ; la durée de frappe automatisée est exclue. Ce sont des mesures de parcours définies ici, pas LCP ou INP.

Le **CLS** est la plus grande fenêtre de déplacements, avec au plus une seconde entre événements et une durée maximale de cinq secondes ; les événements `hadRecentInput` sont exclus. La phase initiale se termine après rendu utile, disponibilité des polices et deux frames. Le parcours entier produit ici la même médiane que cette phase initiale.

## Résultats

Médianes de trois passages, en millisecondes sauf CLS :

| Largeur | Mesure | Avant | Après | Écart après − avant |
|---|---|---:|---:|---:|
| 1440 px | Rendu utile | 845,2 | 895,2 | +50,0 |
| 1440 px | Navigation Agenda → Élèves | 148,1 | 157,0 | +8,9 |
| 1440 px | Recherche locale | 7,9 | 7,8 | −0,1 |
| 1440 px | CLS initial | 0,320 | 0,223 | −0,097 |
| 390 px | Rendu utile | 841,8 | 923,0 | +81,2 |
| 390 px | Navigation Agenda → Élèves | 144,5 | 159,2 | +14,7 |
| 390 px | Recherche locale | 7,0 | 11,4 | +4,4 |
| 390 px | CLS initial | 0,203 | 0,184 | −0,018 |

Le rendu utile varie de 828 à 897 ms avant et de 894 à 995 ms après sur desktop ; de 837 à 897 ms avant et de 902 à 929 ms après sur mobile. Le CLS mobile candidat varie de 0,157 à 0,235 : sa baisse médiane n’établit pas une amélioration stable. Les déplacements au chargement restent perceptibles dans cette fixture ; ils ne sont pas présentés comme une qualification réussie du CLS en production.

Dans le viewport mobile de 390 × 900, le haut de la première leçon passe de **775 px à 462 px**, sans défilement. Cet effet de composition est observé dans les trois passages. Sur desktop, le haut de la première leçon passe de 446 à 511 px. L’élément est dans le viewport dans les deux versions, aux deux largeurs.

Les 12 parcours ont abouti, sans erreur JavaScript de page ni erreur de l’instrumentation. Le premier lancement de mise au point a été interrompu après un sélecteur de recherche erroné (`textbox` au lieu de `searchbox`) ; il n’entre pas dans les résultats.

## Interprétation et limites

Le candidat conserve des interactions locales rapides sur ce petit jeu de données, avec un surcoût de premier affichage constaté en mode développement. Les modules de développement, la machine locale partagée et trois échantillons ne permettent pas d’attribuer précisément ce surcoût ni de prévoir les chiffres du bundle livré.

Ce contrôle ne mesure pas les échanges avec l’API réelle, PostgreSQL, le homelab, les volumes importants, un réseau mobile, un appareil physique ou les performances perçues par le porteur. La recherche de deux élèves ne qualifie pas une grande école. La mesure n’inclut pas les thèmes sombres, tous les formulaires ou les autres parcours. Les tailles de bundles sont documentées séparément par le chantier fondation.

La campagne complète #309/#84 et la qualification après essai personnel restent différées selon la demande du porteur. Aucune modification de protection, aucune mutation métier, aucun déploiement n’ont été nécessaires pour cette mesure.

## Reproduction et preuve

- Script : [`scripts/dev/measure-web-280.mjs`](../../scripts/dev/measure-web-280.mjs).
- Résultats bruts, navigateur, timings détaillés et tous les événements CLS : [`proofs/epic-280/performance-comparison.json`](proofs/epic-280/performance-comparison.json).
- SHA-256 des données comparées : `28695214b1753d3dc65c6b6f1f036f10696d667fbba5ff98d30c9a4123fb77af`.

Depuis la racine du worktree, avec les deux serveurs de fixtures déjà actifs :

```powershell
$env:DRIVY_PLAYWRIGHT_MODULE = 'file:///C:/Users/jtoma/Documents/Projects/Drivy/infra/dev/node_modules/playwright-core/index.mjs'
$env:DRIVY_PERF_BEFORE_REVISION = 'e5166404ca06a7bd804ecf032f673a4afe790007'
$env:DRIVY_PERF_AFTER_REVISION = 'codex/epic-280-web, worktree non commité'
node scripts/dev/measure-web-280.mjs
```

Le script limite les origines à loopback et bloque les requêtes vers d’autres origines. Les variables `DRIVY_PERF_BEFORE`, `DRIVY_PERF_AFTER`, `DRIVY_PERF_DIRECTORY` et `DRIVY_BROWSER_CHANNEL` permettent de reproduire ailleurs. `DRIVY_PERF_PASSES` est plafonné à trois. Les sorties contiennent exclusivement des données synthétiques et des métriques.
