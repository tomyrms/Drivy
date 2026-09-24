# ADR 0001 — première réalisation et chaîne Apple

Date : 24 septembre 2026. État : choix de réalisation, qualification en cours.

## Décisions du porteur

Repartir d'une base vide. Développer depuis Windows ; compiler dans le dépôt GitHub avec Actions sur macOS ; produire un IPA signé ensuite par le porteur avec iLoader et installé sur ses appareils. À la demande du porteur, `tomyrms/Drivy` est un nouveau dépôt public avec un historique neuf ; l'ancien dépôt et ses branches sont conservés privés dans `tomyrms/Drivy-old`.

## Premier parcours G0

Le laboratoire local permet de commencer une séance d'essai avec ou sans GPS, de saisir un thème et un statut d'observation, d'arrêter, puis de relire les informations persistées. L'application a été compilée sur Apple et un premier IPA a été installé et ouvert par le porteur. Les preuves détaillées et les parcours restant à qualifier sont tenus dans [l'état courant](STATUS.md). Les observations restent privées et locales. Aucun consentement scolaire, bail serveur, synchronisation ou bilan publié n'est simulé. La sélection volontaire du GPS concerne le trajet d'essai de la personne qui utilise l'appareil.

L'implémentation choisit SQLCipher officiel pour les transactions et le chiffrement ; elle place la clé dans Keychain avec accès après premier déverrouillage, limité à l'appareil. Le code refuse un repli en clair. Cette lecture statique ne démontre pas encore le chiffrement effectif du binaire. Les garanties écran verrouillé, la reprise et les limites de stockage restent à mesurer sur appareils physiques.

Swift 6, SwiftUI, MapKit, Core Location ; iOS/iPadOS 26.0 comme minimum provisoire d'essai. XcodeGen 2.46.0 génère le projet depuis une spécification conservée dans Git. Le workflow fixe le runner et enregistre Xcode, SDK, commit et dépendances. La signature par iLoader doit être éprouvée avec les capacités effectivement utilisées.

## Première tranche serveur G1A

TypeScript/Fastify, PostgreSQL, JWT OIDC vérifié via issuer/audience/JWKS. Les droits viennent de la base Drivy, pas des seuls claims du fournisseur. Six GET sont implémentés : `/v1/me`, école, listes et détails des dossiers/formations autorisés. Les enveloppes proviennent du contrat OpenAPI 3.11.0. Aucun endpoint parallèle de découverte scolaire ni nouveau modèle de mots de passe n'est créé.

La tranche est en lecture uniquement : création d'école, invitation, leçon et publication ne sont pas livrées. Huit tables portent les concepts indispensables ; rôles et grants restent embarqués dans l'appartenance. Les fixtures sont chargées exclusivement par une commande de développement explicite. La RLS garantit le périmètre scolaire ; les requêtes appliquent en plus affectations moniteur et accès à soi. Le [guide API](../../apps/api/README.md) détaille persistance, variables et limites.

Les versions détaillées sont verrouillées par le lockfile après installation. Les fournisseurs de production ne sont pas provisionnés par cette tranche. Le stockage local G0 ne devient pas le schéma scolaire par migration implicite.

## Preuves de sortie

**Exécuté le 24 septembre 2026 :** typecheck et build TypeScript réussis ; 33 tests serveur passent localement, dont 20 avec une vraie PostgreSQL 17.11 isolée. Les tests incluent les schémas OpenAPI originaux, rôles/affectations/révocation, RLS sous rôle applicatif, contraintes scolaires et précision des curseurs. Ces résultats ne supposent aucun fournisseur OIDC de production ni client déjà connecté.

**Complément du 24 septembre 2026 :** compilations appareil et simulateur réussies, 12 tests Swift réussis, IPA produit et vérifié, installation et ouverture confirmées par le porteur. **Reste à qualifier :** parcours XCUITest complet, GPS sous verrouillage, reprise après interruption, autonomie et accessibilité physique. G0 reste `NOT_QUALIFIED` tant que ces preuves requises ne sont pas obtenues. [État courant](STATUS.md).

Sources techniques : [GitHub runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SQLCipher officiel](https://github.com/sqlcipher/SQLCipher.swift), [iLoader](https://github.com/nab138/iloader).
