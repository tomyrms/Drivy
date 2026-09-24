# État de la réalisation

Mise à jour : 24 septembre 2026.

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 intact |
| Reprise des données | Sans migration | Décision du porteur : base vide |
| Dépôt | Nouveau `tomyrms/Drivy` public | Historique neuf ; ancien dépôt conservé privé dans `tomyrms/Drivy-old` |
| Code et UI native G0 | Compilés sur Apple | Debug simulateur et Release appareil ; séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher |
| Tests Swift / XCUITest G0 | iPhone : 13 tests réussis ; iPad : sélecteur de test à corriger | Run `36011951663` : 12 tests Swift et parcours UI complet réussis sur iPhone ; iPad atteint la relance puis échoue sur une recherche d'onglet supposant une barre iPhone |
| Chaîne GitHub Actions → IPA | Premier IPA d'essai produit, installé et ouvert | Run `36013615026` réussi, source `ebdb6ca`, version 0.1.0/build 1 ; iOS arm64, signatures retirées, empreintes vérifiées après téléchargement ; installation et ouverture confirmées par le porteur |
| API G1A en lecture | Déployée en HTTPS sur l'hébergement choisi | Six GET OpenAPI 3.11.0 ; typecheck/build et 34 tests réussis, PostgreSQL 17.11 et 16.14 réels |
| Connexion scolaire depuis un client | Code G1A compilé ; IPA configuré 0.2.0/build 4 produit | AppAuth/PKCE, choix d'école, élèves et formations ; compte initial `luc` créé, changement de mot de passe obligatoire vérifié par navigateur réel |
| Fournisseur OIDC réel | Déployé, données UTF8 et connexions DB TLS vérifiées | Keycloak 26.7.4 sur CT114, bases neuves CT113, chemins HTTPS Caddy CT109 ; 29 contrôles OIDC locaux et 8 tests de provisionnement réussis |
| Configuration/activation G1B | En cours d'implémentation | L'école initiale reste DRAFT ; aucune politique ou activation approuvée automatiquement |
| Essais iPhone/iPad physiques | Installation et ouverture confirmées ; recette à exécuter | Retour du porteur le 24 septembre : app installée et consultée, contenu perçu comme très limité ; modèle/version exacte et parcours de recette non relevés |
| G0 complet | NOT_QUALIFIED | Essais physiques et budgets à mesurer |
| G1 complet / G2 connecté | À réaliser | G1A en lecture déployé ; configuration, invitations, acceptation, planning et leçons scolaires restent à livrer |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web/gestion, exploitation et procédures |

## Preuves serveur exécutées localement

Le 24 septembre 2026, sous Node 24, `npm run typecheck`, `npm test` et `npm run build` ont réussi pour `@drivy/api`. Les **34 tests** comprennent 13 tests de JWT/configuration/curseurs et 21 tests d'intégration PostgreSQL ; aucun test de cette suite n'a été ignoré. La suite passe avec PostgreSQL 17.11 et avec PostgreSQL 16.14, version réellement hébergée. Six réponses réelles servent aussi de fixtures de contrat aux tests Swift.

Les preuves couvrent signatures OIDC et issuer/audience, enveloppes et formats du contrat OpenAPI original, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT encore valide, séparation des écoles sous le rôle PostgreSQL `drivy_app`, clés étrangères composites et unicité par clé d'offre. La revue indépendante a identifié puis fait corriger la perte de microsecondes des curseurs ; un test vérifie désormais que les pages d'élèves et de formations ne répètent pas leur dernière ligne.

Ce résultat porte sur six lectures : identité, école, liste/détail élève et liste/détail formation. Les données de tests sont synthétiques. Les commandes d'administration et d'invitation, la synchronisation, la capture scolaire, les bilans publiés et les fonctions commerciales restent hors de cette tranche. Voir [le guide API](../../apps/api/README.md) et [les commandes de vérification](../../README.md#serveur-en-développement).

## Premier IPA et preuves Apple

Le porteur confirme avoir installé et ouvert l'IPA le 24 septembre 2026. Son retour porte sur le très faible contenu fonctionnel visible. Il confirme l'installation, sans valider encore la persistance, le GPS ou l'accessibilité. Le laboratoire n'est pas la livraison du produit demandé : connexion, école, élèves, formations, agenda, leçons scolaires et bilans partagés restent à réaliser. Le prochain incrément doit rendre utilisable le parcours G1A dans le client, puis le parcours G2A de leçon sans GPS ; la qualification des capteurs reste suivie séparément et ne justifie pas de réduire le périmètre demandé.

Le [run IPA d'essai `36013615026`](https://github.com/tomyrms/Drivy/actions/runs/36013615026) a réussi sur macOS, Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Il produit **Drivy Essais 0.1.0/build 1**, minimum iOS/iPadOS 26.0, bundle `ch.drivy.qualification`, à partir du commit `ebdb6ca202defd49de07a41425efe1274ba97b45`. Le binaire principal et SQLCipher sont vérifiés arm64 appareil ; les deux bundles et binaires sont non signés. L'IPA de 1 368 606 octets a pour SHA-256 `b5f3eaad74b9891870635e9fbeb89da7bb504905b2a025a06815d399d4f1c861`. Après téléchargement sous Windows, CRC ZIP, Info.plist et empreintes de l'IPA, des binaires, du manifeste de dépendances et des métadonnées ont été vérifiés.

Le workflow d'essai permet au porteur d'installer l'app pendant que les tests sur simulateurs s'exécutent séparément. Il ne vaut pas réussite de ces tests. Le [run natif `36009515483`](https://github.com/tomyrms/Drivy/actions/runs/36009515483) a exécuté 12 tests Swift avec succès et identifié un défaut d'accès au trousseau dans le simulateur non signé. Des entitlements dédiés au simulateur et une signature ad hoc ont été ajoutés. Le [run natif `36011951663`](https://github.com/tomyrms/Drivy/actions/runs/36011951663), portant sur le même code iOS que l'IPA livré, réussit les **13 tests sur iPhone 17 Pro / iOS 26.4.1** : les 12 tests métier et le parcours sans GPS, observation, clôture, relance, bilan et nouvelle relance. Sur iPad Pro 13 pouces M5 / iPadOS 26.4.1, le scénario atteint la relance puis échoue sur le sélecteur `app.tabBars.buttons["Historique"]` ; l'onglet flottant apparaît comme un bouton hors de cette barre dans la hiérarchie native. La correction du sélecteur est incluse dans la tranche suivante. Le run global reste donc en échec ; aucun succès iPad complet n'est déclaré.

Les 434 scénarios métier et 68 scénarios mobiles de la conception ne changent pas de statut par simple création de tests ou de workflow. Ni la compilation ni les tests serveur ne qualifient le GPS, l'autonomie, l'installation iLoader ou les parcours physiques sur iPhone/iPad.

## Déploiement et incrément connecté G1A

Le porteur a explicitement choisi l'hébergement existant et indiqué le dossier Homelab pour l'accès SSH. La release API `0158f8efa5db338cff9b79fd4e3ab3b6a57c440f` est installée dans `/opt/drivy-refonte` sur CT114, sous Node 24.21.0, à côté de l'ancienne API conservée sur son port 3000. API, Keycloak et filtrage nft dédié sont actifs et activés au démarrage. Les bases `drivy_refonte` et `drivy_identity` sont neuves, en UTF8, avec rôles distincts non superutilisateurs ; huit tables métier ont ENABLE/FORCE RLS. La connexion PostgreSQL vérifie le certificat public et son hostname ; TLS 1.3 observé sur les sessions Keycloak. Les adaptations LXC et le bootstrap SQL_ASCII conservé sont documentés dans [le déploiement](deploiement-refonte.md).

Après validation puis rechargement de Caddy, le discovery et le JWKS sont disponibles sous `https://drivy.shulker.ch/identity/realms/drivy`. `/refonte/v1/me` sans jeton renvoie 401 avec `Cache-Control: no-store`. Les chemins admin, master, health et metrics publics renvoient 404 ; les ports 3001/8081 refusent les connexions LAN hors proxy. Les destinations anciennes et leur réponse 404 initiale restent inchangées. Les accès applicatifs/Keycloak sensibles sont exclus des access logs Caddy.

Le [contrôle OIDC HTTPS](controle-oidc-deploye.md) a réussi avec une sonde indépendante : PKCE S256 obligatoire, code/jetons/signatures/nonce vérifiés, refus d'une identité sans lien métier (403), refus d'un ID token comme accès API (401), renouvellement puis refus du rejeu (400). La sonde, ses sessions et ses credentials ont été supprimés et l'absence du compte vérifiée ; la [preuve datée](proofs/oidc-https-2026-09-24.json) ne contient aucun secret.

Le premier compte `luc` et l'école « Luc auto école » ont été créés par le provisionnement contrôlé, sans élève ni formation. L'adresse de contact `luc@example.com` est une adresse d'essai expressément autorisée ; aucun email n'a été envoyé. L'école reste DRAFT, l'appartenance ADMIN est ACTIVE. Un navigateur éphémère a vérifié la connexion HTTPS du compte et l'affichage obligatoire du formulaire de changement de mot de passe ; aucun nouveau mot de passe n'a été soumis. Le mot de passe temporaire est conservé dans un fichier privé sur le PC, jamais dans Git ou les artefacts CI.

Le [run G1A `36017673076`](https://github.com/tomyrms/Drivy/actions/runs/36017673076) réussit 41 tests Swift (12 Core, 11 Identity, 8 API, 10 Workspace) et le test de présentation iPhone. L'XCUITest échoue à ouvrir la séance persistée depuis l'historique ; les captures montrent que la séance et son observation existent. Le chemin de navigation est désormais porté explicitement par la racine. Le run suivant `36020145724`, commit `30999d6`, a compilé application et tests ; son exécution native est en cours, sans succès iPad annoncé à ce stade.

Le [run IPA configuré `36020145594`](https://github.com/tomyrms/Drivy/actions/runs/36020145594) a réussi : version **0.2.0/build 4**, SHA-256 `5f9e6a645dfcdc00cdd39b4f8d3db72b79d10934d83680df5f86a336ad9a9891`. Après téléchargement, CRC ZIP, empreintes des deux binaires et les trois paramètres réellement compilés dans Info.plist ont été vérifiés. `schoolConnectionConfigured=true`. Cette compilation ne vaut ni réussite du run natif séparé, ni recette iLoader/AppAuth sur appareil physique.
