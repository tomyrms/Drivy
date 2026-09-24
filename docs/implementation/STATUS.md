# État de la réalisation

Mise à jour : 24 septembre 2026.

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 intact |
| Reprise des données | Sans migration | Décision du porteur : base vide |
| Dépôt | Nouveau `tomyrms/Drivy` public | Historique neuf ; ancien dépôt conservé privé dans `tomyrms/Drivy-old` |
| Code et UI native G0 | Compilés sur Apple | Debug simulateur et Release appareil ; séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher |
| Tests Swift / XCUITest | 12 tests Swift réussis ; UI en cours de qualification | Run `36009515483` : 12 réussites métier et 1 échec UI au chargement du trousseau ; correctif simulateur compilé, nouvelle exécution `36011951663` en cours à la livraison de l'IPA |
| Chaîne GitHub Actions → IPA | Premier IPA d'essai produit, installé et ouvert | Run `36013615026` réussi, source `ebdb6ca`, version 0.1.0/build 1 ; iOS arm64, signatures retirées, empreintes vérifiées après téléchargement ; installation et ouverture confirmées par le porteur |
| API G1A en lecture | Implémentée et vérifiée localement | Six GET OpenAPI 3.11.0 ; typecheck/build réussis ; 33 tests passent avec PostgreSQL 17.11 réel |
| Connexion scolaire depuis un client | À réaliser | Fournisseur OIDC à configurer, liens d'identité à provisionner ; aucun parcours G0 → API connecté livré |
| Essais iPhone/iPad physiques | Installation et ouverture confirmées ; recette à exécuter | Retour du porteur le 24 septembre : app installée et consultée, contenu perçu comme très limité ; modèle/version exacte et parcours de recette non relevés |
| G0 complet | NOT_QUALIFIED | Essais physiques et budgets à mesurer |
| G1/G2 connecté | À réaliser | Aucun parcours scolaire publié annoncé |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web/gestion, exploitation et procédures |

## Preuves serveur exécutées localement

Le 24 septembre 2026, sous Node 24 et PostgreSQL 17.11 dans le conteneur isolé `drivy-refonte`, `npm run typecheck`, `npm test` et `npm run build` ont réussi pour `@drivy/api`. Les **33 tests** comprennent 13 tests de JWT/configuration/curseurs et 20 tests d'intégration PostgreSQL ; aucun test de cette suite n'a été ignoré.

Les preuves couvrent signatures OIDC et issuer/audience, enveloppes et formats du contrat OpenAPI original, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT encore valide, séparation des écoles sous le rôle PostgreSQL `drivy_app`, clés étrangères composites et unicité par clé d'offre. La revue indépendante a identifié puis fait corriger la perte de microsecondes des curseurs ; un test vérifie désormais que les pages d'élèves et de formations ne répètent pas leur dernière ligne.

Ce résultat porte sur six lectures : identité, école, liste/détail élève et liste/détail formation. Les données de tests sont synthétiques. Les commandes d'administration et d'invitation, la synchronisation, la capture scolaire, les bilans publiés et les fonctions commerciales restent hors de cette tranche. Voir [le guide API](../../apps/api/README.md) et [les commandes de vérification](../../README.md#serveur-en-développement).

## Premier IPA et preuves Apple

Le porteur confirme avoir installé et ouvert l'IPA le 24 septembre 2026. Son retour porte sur le très faible contenu fonctionnel visible. Il confirme l'installation, sans valider encore la persistance, le GPS ou l'accessibilité. Le laboratoire n'est pas la livraison du produit demandé : connexion, école, élèves, formations, agenda, leçons scolaires et bilans partagés restent à réaliser. Le prochain incrément doit rendre utilisable le parcours G1A dans le client, puis le parcours G2A de leçon sans GPS ; la qualification des capteurs reste suivie séparément et ne justifie pas de réduire le périmètre demandé.

Le [run IPA d'essai `36013615026`](https://github.com/tomyrms/Drivy/actions/runs/36013615026) a réussi sur macOS, Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Il produit **Drivy Essais 0.1.0/build 1**, minimum iOS/iPadOS 26.0, bundle `ch.drivy.qualification`, à partir du commit `ebdb6ca202defd49de07a41425efe1274ba97b45`. Le binaire principal et SQLCipher sont vérifiés arm64 appareil ; les deux bundles et binaires sont non signés. L'IPA de 1 368 606 octets a pour SHA-256 `b5f3eaad74b9891870635e9fbeb89da7bb504905b2a025a06815d399d4f1c861`. Après téléchargement sous Windows, CRC ZIP, Info.plist et empreintes de l'IPA, des binaires, du manifeste de dépendances et des métadonnées ont été vérifiés.

Le workflow d'essai permet au porteur d'installer l'app pendant que les tests sur simulateurs s'exécutent séparément. Il ne vaut pas réussite de ces tests. Le [run natif `36009515483`](https://github.com/tomyrms/Drivy/actions/runs/36009515483) a exécuté 12 tests Swift avec succès et identifié un défaut d'accès au trousseau dans le simulateur non signé. Des entitlements dédiés au simulateur et une signature ad hoc ont été ajoutés ; leur présence a été vérifiée dans le produit compilé. Le [run natif `36011951663`](https://github.com/tomyrms/Drivy/actions/runs/36011951663), portant sur le même code iOS que l'IPA livré, reste en cours au moment de cette mise à jour. Aucun succès UI complet n'est encore déclaré.

Les 434 scénarios métier et 68 scénarios mobiles de la conception ne changent pas de statut par simple création de tests ou de workflow. Ni la compilation ni les tests serveur ne qualifient le GPS, l'autonomie, l'installation iLoader ou les parcours physiques sur iPhone/iPad.
