# État de la réalisation

Mise à jour : 24 septembre 2026.

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 intact |
| Reprise des données | Sans migration | Décision du porteur : base vide |
| Dépôt | Nouveau `tomyrms/Drivy` public | Historique neuf ; ancien dépôt conservé privé dans `tomyrms/Drivy-old` |
| Code et UI native G0 | Écrits, non compilés sur Apple | Séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher ; revue statique effectuée |
| Tests Swift / XCUITest | NOT_EXECUTED | Sources présentes ; résultats natifs à obtenir sur runner Apple |
| Chaîne GitHub Actions → IPA | Configurée, résultat non obtenu | Aucune compilation Apple réussie ni IPA validé à cette mise à jour ; signature iLoader ensuite |
| API G1A en lecture | Implémentée et vérifiée localement | Six GET OpenAPI 3.11.0 ; typecheck/build réussis ; 33 tests passent avec PostgreSQL 17.11 réel |
| Connexion scolaire depuis un client | À réaliser | Fournisseur OIDC à configurer, liens d'identité à provisionner ; aucun parcours G0 → API connecté livré |
| Essais iPhone/iPad physiques | NOT_EXECUTED | Installation et recette avec le porteur |
| G0 complet | NOT_QUALIFIED | Essais physiques et budgets à mesurer |
| G1/G2 connecté | À réaliser | Aucun parcours scolaire publié annoncé |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web/gestion, exploitation et procédures |

## Preuves serveur exécutées localement

Le 24 septembre 2026, sous Node 24 et PostgreSQL 17.11 dans le conteneur isolé `drivy-refonte`, `npm run typecheck`, `npm test` et `npm run build` ont réussi pour `@drivy/api`. Les **33 tests** comprennent 13 tests de JWT/configuration/curseurs et 20 tests d'intégration PostgreSQL ; aucun test de cette suite n'a été ignoré.

Les preuves couvrent signatures OIDC et issuer/audience, enveloppes et formats du contrat OpenAPI original, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT encore valide, séparation des écoles sous le rôle PostgreSQL `drivy_app`, clés étrangères composites et unicité par clé d'offre. La revue indépendante a identifié puis fait corriger la perte de microsecondes des curseurs ; un test vérifie désormais que les pages d'élèves et de formations ne répètent pas leur dernière ligne.

Ce résultat porte sur six lectures : identité, école, liste/détail élève et liste/détail formation. Les données de tests sont synthétiques. Les commandes d'administration et d'invitation, la synchronisation, la capture scolaire, les bilans publiés et les fonctions commerciales restent hors de cette tranche. Voir [le guide API](../../apps/api/README.md) et [les commandes de vérification](../../README.md#serveur-en-développement).

Les résultats natifs et de CI seront ajoutés lorsqu'ils seront effectivement disponibles. Les 434 scénarios métier et 68 scénarios mobiles de la conception ne changent pas de statut par simple création de tests ou de workflow. Les tests serveur réussis ne qualifient ni le GPS, ni SQLCipher sur iPhone/iPad, ni l'interface native.
