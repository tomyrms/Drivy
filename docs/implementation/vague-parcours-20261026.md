# Vague parcours du 26 octobre 2026

Le porteur a demandé la réalisation des cinq lots proposés dans le chat : bilan (#162/#163), fondations de réactivité et pilote réglages (#106/#107/#119), finalisation de la réactivité Messages (#104), formulaires et cours (#143/#99), récupération d'accès et planning web (#50/#51).

## Base et coordination

- Branche de réalisation : `codex/bilans-reactivite-parcours-20261026`, worktree isolé. Les changements non commités du checkout du porteur ne sont pas importés.
- Base : travail messagerie jusqu'à `da7f8f3` (dont #169/#170/#141), fusion de `origin/master` à `71390e9` (agenda #178). Ces correctifs préexistants sont conservés.
- Dossier de conception conservé. Les décisions du 28 septembre sur le partage automatique priment sur les anciens textes de publication.
- Propriétaires distincts : bilan/messagerie/identité/intégration ; fondations web ; fondations natives ; cours et formulaires natifs.

## Périmètre et preuve attendue

| Lot | État initial de cette vague | Livraison attendue |
|---|---|---|
| #162/#163 | À réaliser | Conservation du brouillon vérifiée, erreur sans fermeture, action terminale explicite. |
| #106/#107/#119 | À réaliser, mécanismes existants à réutiliser | Socles minimaux par dépendance réelle, lectures autorisées, adoption complète du pilote préférences ; autres parcours documentés pour adoption progressive. |
| #104 | Déjà partiellement implémenté | Intentions protégées après relance, reprise/convergence et recette sous latence. |
| #143/#99 | À réaliser | Sorties des formulaires sans perte silencieuse et points A30/A31/A32/A33/A34/A37/A38/A39. |
| #50 | À réaliser | Récupération via fournisseur d'identité existant, canal vérifié et tests isolés. |
| #51 | À réaliser | Création/déplacement/annulation de leçons dans le bureau web avec commandes métier existantes. |

## Vérification

Tests ciblés utiles pendant les lots, compilation Apple et IPA non signée sur GitHub Actions. Campagne intégrée #84 après intégration du périmètre retenu. Les résultats, SHA et limites sont ajoutés au fil de l'exécution dans les rapports de lot et `STATUS.md`. Aucun test physique ni VoiceOver réel ne peut être déduit d'un simulateur. Les déploiements ne sont pas des effets implicites d'une compilation.

## État avant campagne intégrée

- Bilan : implémenté, 101 tests Swift réussis au premier candidat ; reprise des tests UI après correction de sélecteurs XCTest. Le test supplémentaire d'indépendance bilan/invitation sera inclus dans la campagne intégrée.
- Socles et réglages : implémentés, 79 tests natifs ciblés réussis et pilotes web/SQL qualifiés. L'adoption par toutes les pages reste progressive ; #106/#107 ne sont pas déclarées universellement terminées.
- Messagerie : journal scellé et reçu serveur atomique implémentés. Les tests PostgreSQL couvrent les requêtes concurrentes et tardives ; qualification Apple du protocole final encore attendue. `MessagingLatencyUITests` ajoute des réponses synthétiques retardées de 1, 5 et 15 secondes, un refus et un retrait rapide. Les temps sont relevés par XCTest, sans les confondre avec une mesure réseau physique.
- Cours/formulaires : implémentés. 65 tests métier agenda réussis (69 exécutions paramétrées) sur `bd5cbdc` ; preuves UI et recette physique encore distinctes.
- Récupération : intégration prête, 158 contrôles de parcours navigateur réussis dont les huit scénarios de récupération Keycloak/Mailpit. À la demande du porteur, choix SMTP reporté ; activation réelle désactivée. La protection de l'endpoint direct du fournisseur doit être qualifiée avant cette activation.
- Planification web : création, déplacement et annulation en revue finale. La console conserve sa frontière ADMIN conformément au mandat bureau ; l'accès web du moniteur mentionné dans #51 reste non livré. Les règles API existantes de #61 sont conservées.

Les travaux messagerie antérieurs à cette vague, jusqu'à `da7f8f3`, sont inclus dans la branche car ils constituent sa base. Aucun dépôt ancien ni export de conversation n'est importé. Les issues restent ouvertes tant que leurs critères non couverts ne sont pas qualifiés.
