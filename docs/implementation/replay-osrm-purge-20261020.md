# Replay OSRM : purge et protection des calculs en cours

20 octobre 2026. Lot local sur `claude/recalage-suisse-osrm-20261020`. Aucun déploiement de ce lot.

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

Les **55 tests ciblés réussissent** : 19 replay, 2 migrations, 6 notices et 28 tests de géométrie. Typage et build API réussis à 21:05:36 UTC. Premier passage de toute la suite : **546/550 réussis**, avec quatre échecs hors lot : les deux tests SMTP « Mailpit accepte le message » et « deux workers concurrents » faute de serveur Mailpit local, puis les deux tests live « leçon a changé d’auteur » et « author perdu » dans une fixture en cours de correction par l’agent API. Un serveur Mailpit synthétique isolé est préparé pour rejouer la suite complète. Le défaut de typage `speed` du premier passage a été corrigé par cet agent avant la vérification finale.

Commandes de recette, avec `TEST_DATABASE_URL` pointant exclusivement vers la base synthétique locale :

```cmd
npm --prefix apps/api test -- test/matched-route.integration.test.ts test/school-onboarding-migration.integration.test.ts test/text-proposals.test.ts test/track-matching.test.ts < nul
npm --prefix apps/api test < nul
npm --prefix apps/api run typecheck < nul
npm --prefix apps/api run build < nul
```

## Limites et intégration

Node local **26.8.1**, alors que le projet demande Node 24 : la CI sous la version requise reste nécessaire. Le moteur réseau des tests de replay est synthétique. Ces tests qualifient les transactions, le recalcul, le chiffrement et l’isolation, pas la justesse routière ni la fluidité sur iPhone.

Ne pas appliquer cette migration seule en laissant un ancien binaire servir le trafic : sa prise de bail à quatre arguments n’existe plus. Pour une future mise en service autorisée, prévoir sauvegarde, arrêt ou drainage de l’ancienne API, migration et démarrage du nouveau binaire. Aucun déploiement, essai physique GPS, batterie ou VoiceOver n’est revendiqué ici. Le coordinateur conserve la mise à jour de `STATUS.md`.
