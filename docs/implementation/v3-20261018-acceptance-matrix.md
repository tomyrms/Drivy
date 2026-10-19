# V3 : matrice exigences, contrôles et observations

Date : 18 octobre 2026. Rapport associé : `v3-20261018-report.md`.

## Niveaux de preuve

- **Réel local** : interfaces publiques du projet, navigateur Edge, OIDC Keycloak, SMTP Mailpit, BFF, API et PostgreSQL. Données et comptes de test isolés, pas production.
- **Intégration PG** : vraie route Fastify, JWT et PostgreSQL, appel injecté dans le serveur, pas mesure réseau.
- **Synthétique** : vrai composant/build dans Edge, transport ou identité simulés, panne volontaire. Ne remplace pas la recette connectée.
- **Statique / bloqué** : inspection sans exécution native. Aucune prétention de validation appareil.

## Traçabilité des changements et sorties publiques

| ID / exigence | Contrôle concret | Observation finale / limite |
|---|---|---|
| A1 : V3 issue de V2, V1 préservée | `git merge-base --is-ancestor 6fe4656 HEAD`, historique V1..V2 et V2..HEAD | Base V2 conservée. Aucun merge sur main/master |
| A2 : cinq commits V2 et diff complet | Historique `7c117cd..6fe4656`, revue des 11 fichiers | Cinq commits identifiés dans le rapport et verdict V2 |
| A3 : runtime Node24 | Binaire officiel v24.22.0, checksum, npm ci isolés, types/tests/builds | Suites finales exécutées après installation des lockfiles finaux |
| A4 : step-up V2 | Tests BFF + deux dernières assertions step-up de `integration-final/result.json` | Sujet différent refusé, compte initial préservé. Même compte accepté avec rotation de session |
| A5 : consentement GPS V2 | `check-audit-v2-regressions.mjs`, dernière assertion GPS de la recette connectée | Panne rendue visible puis vraie reprise BFF/API/PG. GPS physique non testé |
| C1 : N+1 catalogue | `measure-catalogue.ts`, `catalogue-batch.integration.test.ts` | Page100 : 100 lectures de compétences deviennent 1. Test rouge avant, vert après |
| C2 : réponse catalogue inchangée | Hash SHA256 complet des items, pages1/10/50/100 dans `catalogue-measurement-verified.json` | Identité des items avant/après, mêmes tailles de réponse |
| C3 : pagination et ordre | Banc : pages50+50, stabilité des ordres et ex aequo, compétences triées et libellés normalisés | Pas de doublon ni oubli observé. Requête groupée bornée aux IDs de la page réelle |
| C4 : absence de fuite de données | Banc avec autre école, non-membre et moniteur, rôle `drivy_app` | Non-membre403, périmètre autorisé respecté, catalogue vide sans requête de compétences |
| C5 : intégration catalogue réelle HTTP | Recette connectée : sauvegarde catalogue, réponse perdue, AP72 et relecture formations | Un seul tarif durable, pas de seconde commande ni formation supplémentaire, affichage mis à jour |
| C6 : taille web réellement chargée | `measure-web-entry.ts --require-split` avant/après/final, 5 routes | Compte485612 octets contre831254. Mesure de corps JS, gzip estimé. Identité du banc simulée |
| C7 : panne de chunk et reprise | `check-v3-entry.ts`, préférences/console/invitation/ouverture | Loading visible, focus erreur, reprise clavier, aucune boucle. Quatre scénarios réussis sur build final |
| C8 : protection des liens après découpage | Même recette chunk + vraie recette invitation/ouverture OIDC | Fragment nettoyé avant chargement, pas de jeton dans URL HTTP ou stockage. POST BFF légitime réussi après reprise |
| D1 : date distante sans huit flèches | `check-v3-agenda.mjs --before`, puis version après | Avant8 activations. Après1 choix de date +1 confirmation, sur1440clair/390clair/390sombre |
| D2 : saisie non destructive et validation | Recette agenda synthétique | Saisir ne change pas la semaine. Date vide refusée, Entrée valide, lundi normalisé |
| D3 : semaine, fuseau et filtre corrects | `check-v3-agenda-acceptance.ts`, réponse réelle du BFF | 17/02/2027 donne14/02/2027 23hZ à21/02/2027 23hZ, moniteur conservé. Semaine25/10/2026 :169heures |
| D4 : navigation et focus | Recette connectée et synthétique | Focus sur semaine, recherche élève conservée, retour navigateur et reload gardent moniteur/semaine/leçon |
| D5 : panne de lecture agenda | Injection503 ponctuelle, puis passage vers vrais services | Erreur et Réessayer visibles, reprise200 sur la semaine demandée, pas retour silencieux à une autre semaine |
| D6 : bonne destination de leçon | Assertion après les neuf contrôles V3 dans la recette connectée | La leçon ouvre le dossier du bon élève |
| D7 : résultat visuel | Captures avant/après390clair/390sombre/1440clair, captures du build connecté390/1440, contrôle scrollWidth | Labels et commandes visibles, pas de débordement horizontal. Pas de test VoiceOver ou navigateur Safari |
| C9 : dépendance corrigée sans dérive | Diff des deux lockfiles + npm ci + npm audit complet + toutes suites | Seul source-map-js1.2.1→1.2.2. Audits racine/web à0. Exploit de Drivy non démontré |
| E1 : préservation des parcours V1/V2 | 5 V1 +5 V2 +41 interactions, suite connectée91 | Résultats verts, transport synthétique distingué des services réels. Pas de garantie d'absence totale de régression |
| E2 : packaging, types, compilation | Types API/client/serveur et outils explicites, build API, build web | Succès. Avertissement préexistant du script classique theme-init.js documenté. Aucun lint configuré |
| E3 : documentation et secrets | Vérificateur556fichiers, diff final, recherche ciblée dans ajouts et chemins | Documentation canonique inchangée, aucun fichier sensible ou credential production retenu |
| B1 : recette native fonctionnelle et GPS | Recherche outils Apple, inspection ciblée, checklist32scénarios | **Bloqué par absence de runner/appareil**. Zéro test iOS exécuté |
| B2 : performance native, VoiceOver, Dynamic Type | Checklist appareil et Instruments | **Non mesuré, non qualifié**, aucune optimisation native conservée sans preuve |
| F1 : commits cohérents et retour arrière | Revue indépendante, diff coordinateur, historique des huit commits | Proposition et rollback documentés. Aucun merge ou push |
| G1 : déploiement distinct de fusion | Aucun appel de déploiement, plan conditionnel dans rapport | **En attente d'autorisation future distincte**, production non touchée |

## Commandes de reproduction principales

Exécuter depuis le worktree V3, avec le Node24 portable en tête de PATH et des installations locales sans jonction. Les données de recette ne doivent jamais viser la production.

```cmd
set "PATH=C:\Users\jtoma\dv-v3-20261018\artifacts\v3-20261018\tools\node-v24.22.0-win-x64;%PATH%"
node --version
npm run typecheck
npm run test --workspace @drivy/api
npm run build
npm --prefix apps/web run typecheck
npm --prefix apps/web run test
npm --prefix apps/web run build
node node_modules/typescript/bin/tsc --noEmit --module NodeNext --moduleResolution NodeNext --target ES2022 --skipLibCheck --esModuleInterop --strict --noUncheckedIndexedAccess --exactOptionalPropertyTypes scripts/dev/check-v3-entry.ts scripts/dev/measure-web-entry.ts scripts/dev/check-v3-agenda-acceptance.ts
node --import tsx scripts/dev/check-v3-entry.ts
node --import tsx scripts/dev/measure-web-entry.ts --require-split
python -B Drivy_Conception_v3_17_2026-09-20/annexes/verifier-integrite.py
git diff --check
```

Pour l'API, définir `TEST_DATABASE_URL` vers une base locale jetable `drivy_test`. Le banc SQL et la suite modifient cette base : les exécuter séquentiellement. `measure-catalogue.ts` accepte `MEASURE_PHASE=baseline` puis `after` et `OUTPUT` pour comparer les résultats. Ne pas écraser l'archive vérifiée pour comparer une nouvelle expérimentation.

Pour le navigateur synthétique, lancer Vite sur127.0.0.1:5189, définir `DRIVY_REVIEW_ORIGIN`, puis exécuter les scripts `check-audit-regressions.mjs`, `check-audit-v2-regressions.mjs`, `check-web-redesign.mjs --checks-only`, `check-v3-agenda.mjs`. Chaque script accepte `DRIVY_REVIEW_DIRECTORY` pour séparer les preuves.

Pour la recette connectée, préparer uniquement une base locale dédiée vierge et Mailpit, définir `ONBOARDING_E2E_DATABASE_URL` et `DRIVY_BROWSER_CHANNEL=msedge`, puis :

```cmd
node --import tsx scripts/dev/check-school-opening.ts --skip-account-recovery --audit-v2 --v3
```

La récupération de compte est volontairement exclue. Aucun mot de passe utilisateur n'est réinitialisé. La recette démarre et arrête son Keycloak et ses serveurs locaux. Les bases jetables et services possédés doivent être identifiés avant tout nettoyage. Aucun hébergement externe ni runner cloud n'a reçu le code du projet.

## Boucle de validation et décision d'arrêt

Les résultats ne reposent pas uniquement sur des mocks : la suite finale traverse l'OIDC, la vérification e-mail, les invitations, l'activation de l'école, le catalogue, les disponibilités, la création du dossier, l'ouverture de formation, la réservation d'une leçon et l'agenda via les vrais services. Les pannes injectées sont signalées comme telles et leurs reprises retournent aux vrais services. Les mesures utilisent les mêmes données déterministes et comparent les sorties, pas seulement les durées.

Le périmètre web/API modifié est qualifié par ces contrôles locaux. La boucle native reste ouverte, explicitement bloquée par l'environnement. L'étape suivante n'est pas une nouvelle refonte spéculative : c'est la décision de fusion de la branche web/API et l'organisation de la recette Apple. La validation de production et le déploiement restent hors de l'autorisation actuelle.
