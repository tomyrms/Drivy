# Replay OSRM : purge et protection des calculs en cours

20 octobre 2026. Lot sur `claude/recalage-suisse-osrm-20261020`. Cette tâche couvre le code et la recette locale, sans exécuter de déploiement. Les opérations coordonnées sont suivies dans `STATUS.md`.

## Défaut reproduit

La lecture de `matched-route` ne comparait que la version de reconstruction et la version de l’algorithme. Une ligne `READY` portant `provider=mapbox` était donc servie alors que le moteur configuré était OSRM. Un résultat vide, un échec avec délai de reprise ou un bail actif d’un autre moteur pouvaient aussi empêcher le recalcul.

Avant correction, les régressions PostgreSQL ont effectivement constaté le résultat Mapbox servi, l’absence de recalcul et l’attente d’un ancien bail sans fournisseur. Le test de migration peuplée conservait toutes les lignes au lieu de purger les six dérivés visés. Le test de notice OSRM échouait aussi.

## Décisions d’implémentation

- La migration `035_osrm_matched_route.sql` supprime uniquement les lignes actives de `capture_matched_route` dont le fournisseur est Mapbox ou l’état est `PROCESSING`. Tous les calculs en cours perdent leur bail, y compris les anciens calculs dont le fournisseur est inconnu. Les sauvegardes privées de restauration conservent leur état antérieur : cette purge du cache actif n’est pas un effacement historique des sauvegardes.
- Les résultats OSRM déjà terminés ne sont pas supprimés par la migration. La version d’algorithme passe à **2** : ils seront recalculés à la prochaine lecture autorisée s’ils portent encore la version 1.
- Le moteur est désormais fixé dès la prise du bail. La nouvelle fonction `claim_matched_route` reçoit un cinquième argument `engine`, n’accepte qu’OSRM et exige une version d’algorithme au moins égale à 2. L’ancienne signature à quatre arguments est retirée : un ancien binaire ne peut plus créer de bail sans fournisseur.
- La fin d’un calcul exige le bail courant, le fournisseur OSRM identique à celui du bail et une version au moins égale à 2. Un ancien callback ne recrée pas une ligne supprimée et ne peut pas terminer le nouveau bail.
- La lecture API exige un moteur OSRM actif, la même provenance, la même version d’algorithme et la même version de reconstruction. Cette règle couvre `READY`, `EMPTY`, `FAILED` et `PROCESSING`. Moteur désactivé : aucun cache, même valide et déchiffrable, n’est servi.
- Le client Mapbox dans `map-matching-client.ts` n’est pas modifié par ce lot. Il reste disponible pour la comparaison synthétique, pas pour les trajets réels.
- La proposition de notice OSRM indique un recalage dans l’hébergement de Drivy sans envoi des positions à un service tiers. Apple Plans reste explicitement mentionné pour les fonds de carte. Aucun texte adopté en base n’est réécrit.

La sélection des mesures et la géométrie calculée ne changent pas. Le contrat canonique, la capture, les chunks, les droits de lecture et le replay des mesures sont conservés.

## Preuves exécutées

Environnement isolé coordonné avec l’agent API : PostgreSQL **17.11**, conteneur local `drivy-replay-test`, base synthétique `drivy_test`, port loopback 55435. L’autre agent utilise son propre conteneur et le port 55434. Migrations appliquées par un propriétaire `NOSUPERUSER NOBYPASSRLS`, appels des fonctions sous `drivy_app`.

| Exigence | Vérification |
|---|---|
| Purge ciblée | Base peuplée jusqu’à 034 avec neuf dérivés : quatre Mapbox, deux autres calculs en cours, trois OSRM terminés. Après migration, seuls les trois OSRM terminés restent, identiques. |
| Mesures et notices conservées | Comparaison complète avant/après des chunks chiffrés, captures et notices adoptées. |
| Ancien calcul refusé | Livraison de chaque ancien bail après migration refusée. Ancien bail présenté comme OSRM contre un nouveau bail refusé. Bon bail présenté comme Mapbox refusé. Nouveau bail OSRM accepté. |
| Recalcul réel côté API | Huit cas : Mapbox ou fournisseur inconnu, chacun en `READY`, `EMPTY`, `FAILED`, `PROCESSING`. Réponse initiale sans résultat ancien, puis `READY/osrm`, un seul calcul et chunks inchangés. |
| Version précédente invalidée | Cache OSRM version 1 recalculé en version 2. |
| Moteur désactivé | Caches `EMPTY` et `READY` réellement déchiffrable non servis. |
| Réexécution du migrateur | Registre stable, nouveau résultat OSRM conservé, chunks et notices identiques. |
| Droits et erreurs | Tests existants d’isolation, partage élève, panne moteur, reprise de bail, borne resserrée, retrait et replay brut. |

Les **55 tests ciblés réussissent** : 19 replay, 2 migrations, 6 notices et 28 tests de géométrie. **Recette complète finale terminée le 20 octobre à 21:15:39 UTC : 552/552 tests API, 43/43 fichiers, typage et build API réussis**, code de sortie 0. Passage démarré après stabilisation du correctif live `cf0f316`, avec PostgreSQL 17.11 et Mailpit 1.31.2 locaux. SMTP synthétique sur 11035, API Mailpit sur 18035.

Les passages intermédiaires ne sont pas présentés comme des succès complets :

- Premier passage : 546/550 réussis. Échecs des deux tests SMTP « Mailpit accepte le message » et « deux workers concurrents » sans serveur Mailpit local, puis des deux tests live « leçon a changé d’auteur » et « author perdu » dans les fixtures corrigées ensuite par l’agent API.
- Deuxième passage avec SMTP : 550/552 réussis. Les deux nouvelles régressions live « refuse 1/3 déplacement(s) récent(s) inversé(s) » ont été chargées rouges pendant la correction concurrente. Elles passent toutes deux au dernier passage stabilisé.
- Le défaut de typage `speed` observé au premier contrôle a été corrigé par l’agent API avant les vérifications finales.

Le lot fonctionnel est committé en `a0f8417`. Le client `map-matching-client.ts`, les chunks et les notices adoptées ne sont pas modifiés par ce lot.

Commandes de recette, avec `TEST_DATABASE_URL` pointant exclusivement vers la base synthétique locale :

```cmd
npm --prefix apps/api test -- test/matched-route.integration.test.ts test/school-onboarding-migration.integration.test.ts test/text-proposals.test.ts test/track-matching.test.ts < nul
set "TEST_SMTP_PORT=11035"
set "TEST_MAILPIT_URL=http://127.0.0.1:18035"
npm --prefix apps/api test < nul
npm --prefix apps/api run typecheck < nul
npm --prefix apps/api run build < nul
```

## Limites et intégration

Node local **26.8.1**, alors que le projet demande Node 24 : la CI sous la version requise reste nécessaire. Le moteur réseau des tests de replay est synthétique. Ces tests qualifient les transactions, le recalcul, le chiffrement et l’isolation, pas la justesse routière ni la fluidité sur iPhone.

La prise de bail à quatre arguments n’existe plus : l’ancienne API doit être arrêtée ou drainée avant la migration, puis le nouveau binaire démarré. Aucun déploiement n’a été exécuté par l’agent chargé de cette recette. **Le coordinateur a ensuite intégré le lot au déploiement `cf0f316` du 20 octobre 2026, annoncé réussi à 21:14 UTC**, avec sauvegarde et contrôles détaillés dans la [note principale de recalage suisse](recalage-suisse-20261020.md). Ces opérations sont distinctes des preuves locales ci-dessus. Aucun essai physique GPS, batterie ou VoiceOver n’est revendiqué ici. Le coordinateur conserve la mise à jour de `STATUS.md`.
