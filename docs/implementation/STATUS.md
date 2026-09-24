# État de la réalisation

Mise à jour : 24 septembre 2026. La refonte est en cours ; G0, G1A et G1B ne constituent pas le produit complet.

**Travail en cours sur `codex/refonte-entree` :** invitations API/iOS, outbox d’email chiffrée et acceptation web React/BFF. L’API passe **89 tests** sur PostgreSQL 16.14 et 17.11 (57 précédents + 32 F02), avec SMTP Mailpit réel. Le web passe **19 tests**, **10 contrôles** de connexion réelle et la [recette complète de 18 contrôles](recette-entree-web.md) SMTP → vérification d’adresse → identité nouvelle → acceptation explicite → un dossier minimal, sans formation. Typecheck/build réussis ; cinq captures d’accueil/compte clair/sombre et mobile relues. Le [run serveur/web `36032834055`](https://github.com/tomyrms/Drivy/actions/runs/36032834055) est réussi. Deux premiers builds Apple ont échoué dans l’inférence des callbacks SwiftUI ; les corrections sont poussées dans `7836441`, avec **27 nouveaux tests Swift et un test de présentation restant à exécuter**. Le code G1C n’est pas encore déployé ; l’IPA livré et la release hébergée décrits ci-dessous restent G1B. Seule l’adaptation du scope OIDC `email` est appliquée. [PR2 en brouillon](https://github.com/tomyrms/Drivy/pull/2), [préparation du déploiement](preparation-deploiement-web.md), [couverture complète](couverture-produit.md), [tranche F02](g1c-invitations.md), [web/BFF](../../apps/web/README.md).

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 conservé, contrat OpenAPI 3.11.0 immuable |
| Données et dépôt | Historique neuf, sans migration de données | `tomyrms/Drivy` public ; `tomyrms/Drivy-old` privé |
| Laboratoire G0 | Compilé et testé sur simulateurs | Séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher |
| Accès scolaire G1A | Client et API implémentés | AppAuth/PKCE, écoles et rôles, élèves et formations en lecture |
| Configuration G1B | Client compilé, serveur déployé | Coordonnées, textes adoptés explicitement, préparation et activation ADMIN ; commandes chiffrées avant émission |
| Serveur | 57 tests réussis | PostgreSQL 16.14 et 17.11 réels ; typecheck/build et CI réussis |
| Tests Apple G0/G1A/G1B | iPhone 69/69, iPad 3/3 | Run `36024174590` entièrement réussi ; zéro échec ou test ignoré |
| IPA connecté | 0.3.0/build 5 disponible | Run `36024174745`, source `c3e5e67`, CRC/hashes/configuration compilée revérifiés |
| Hébergement HTTPS | API, identité et filtrage actifs | CT114, PostgreSQL UTF8 CT113, chemins Caddy CT109 |
| Première école | DRAFT, ADMIN actif | Compte `luc`, « Luc auto école » ; aucune adoption ou activation faite automatiquement |
| Essais physiques | Installation du premier IPA confirmée ; recette restante | Connexion 0.3.0, VoiceOver, interruptions réseau, GPS et budgets à qualifier |
| G1 complet / G2 connecté | À réaliser | Invitations, acceptation des dossiers, formations administrées, planning, leçons et bilans partagés |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web de gestion, exploitation et procédures |

## Preuves serveur

Sous Node 24, `npm run typecheck`, `npm test` et `npm run build` réussissent. Les **57 tests** comprennent 13 tests JWT/configuration/curseurs, 21 tests d'intégration G1A et 23 tests d'intégration G1B ; aucun n'est ignoré. La suite passe sur PostgreSQL 17.11 et 16.14, version hébergée. Le [run `36024174827`](https://github.com/tomyrms/Drivy/actions/runs/36024174827) confirme tests, build et intégrité documentaire.

G1A couvre les six lectures du contrat, les dates et curseurs, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT valide et séparation scolaire sous `drivy_app`. Six réponses PostgreSQL réelles servent de fixtures aux tests Swift.

G1B couvre coordonnées, progression, readiness, adoption versionnée des textes, activation et preuve AP72. Les tests vérifient atomicité effet/preuve/audit, idempotence concurrente, versions obsolètes, refus d'activation prématurée, révocation pendant l'attente, rollback sur échec d'audit et séparation des écoles. L'extension `data-policy` possède son propre schéma machine, sans modifier le canon. La migration 002 a également été éprouvée après 001 et deux écoles existantes sous un propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE. Voir [G1B](g1b-school-setup.md) et [le guide API](../../apps/api/README.md).

## Hébergement et identité

La release API **`c3e5e6733282a77be779f1c99661f0831c74c5d8`** tourne sous Node 24.21.0 dans `/opt/drivy-refonte` sur CT114. Une sauvegarde privée de la seule base `drivy_refonte` a précédé la migration 002. Le processus redémarré utilise le dossier `apps/api` de cette release ; identité et filtrage sont restés actifs. L'ancienne API sur 3000 et les anciennes bases sont conservées.

Les bases `drivy_refonte` et `drivy_identity` sont neuves, UTF8, avec rôles distincts non superutilisateurs. La vraie connexion runtime vérifie les privilèges, le certificat TLS/hostname PostgreSQL, `SET LOCAL ROLE drivy_app` et l'absence de personne visible sans contexte. Les treize tables métier ont ENABLE/FORCE RLS. Les adaptations LXC et les bases de bootstrap SQL_ASCII conservées sont expliquées dans [le déploiement](deploiement-refonte.md).

L'API répond sous `https://drivy.shulker.ch/refonte`, Keycloak 26.7.4 sous `https://drivy.shulker.ch/identity/realms/drivy`. Discovery et JWKS répondent 200 ; les lectures protégées sans jeton répondent 401/no-store. Les chemins admin, master, health et metrics publics répondent 404 ; les ports 3001/8081 refusent les connexions LAN hors proxy. Les accès sensibles sont exclus des journaux Caddy.

Le [contrôle OIDC HTTPS](controle-oidc-deploye.md) a réussi avec une sonde indépendante : PKCE S256 obligatoire, code/jetons/signatures/nonce vérifiés, identité sans lien métier refusée (403), ID token refusé comme accès API (401), renouvellement puis rejeu refusé (400). Sonde, sessions et credentials ont été supprimés, puis l'absence du compte vérifiée. La [preuve datée](proofs/oidc-https-2026-09-24.json) ne contient aucun secret. Le banc OIDC local compte également 29 contrôles réussis et le provisionnement 8 tests réussis.

Le compte initial `luc` et « Luc auto école » proviennent du provisionnement contrôlé, sans élève ni formation. `luc@example.com` est le contact d'essai autorisé par le porteur ; aucun email n'a été envoyé. Un navigateur éphémère a vérifié la connexion et le formulaire obligatoire de changement de mot de passe, sans soumettre un nouveau mot de passe. Le fichier d'accès initial est privé sur le PC ; il n'est jamais inclus dans Git ou les artefacts CI.

La [preuve du déploiement G1B](proofs/g1b-deployment-2026-09-24.json) confirme une école DRAFT, un ADMIN actif, un setup initial et une politique vide non approuvée. Aucune commande, aucun élève ni formation n'a été créé par ce contrôle. Adoption et activation restent des gestes explicites de l'administrateur.

Le client OIDC public `drivy-apple` a reçu le scope `email` le 24 septembre pour préparer F02 : scopes `basic/email/profile`, callback exact et PKCE S256 relus et inchangés. Une requête d’autorisation HTTPS avec `openid profile email` retourne le formulaire 200 sans soumettre d’identifiants. Cette adaptation seule est déjà appliquée ; elle n’est pas une nouvelle preuve de connexion Apple, ni un déploiement G1C.

## IPA et preuves Apple

Le [run IPA `36024174745`](https://github.com/tomyrms/Drivy/actions/runs/36024174745) produit **Drivy 0.3.0/build 5**, minimum iOS/iPadOS 26.0, bundle `ch.drivy.qualification`, source `c3e5e6733282a77be779f1c99661f0831c74c5d8`. Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Les deux binaires sont arm64 appareil et les quatre bundles non signés. SHA-256 : `8d7ecee21aaa72e29e3f6c9b3fb1ca7e9ba8bc4f6ee1601c4314790cb8e0405f`. Après téléchargement, CRC ZIP, hashes du manifeste et des binaires, ainsi que les trois paramètres HTTPS dans Info.plist ont été vérifiés ; `schoolConnectionConfigured=true`.

Le workflow d'essai produit cet IPA indépendamment des tests. Le [run natif G1B `36024174590`](https://github.com/tomyrms/Drivy/actions/runs/36024174590) est entièrement réussi : **69/69 tests iPhone** (66 Swift Testing, deux tests de présentation XCTest et un parcours G0), **3/3 tests iPad**, sans échec ni test ignoré. Les sept tests de stockage des commandes passent individuellement avec le vrai Keychain, chiffrement, barrière de fichier et synchronisation de dossier sur simulateur. Les rapports et captures ont été téléchargés et relus : configuration G1B claire lisible, état non approuvé explicite, contraste de sélection iPad rétabli et navigation G0 visible sous son bandeau. La capture G1B ne qualifie pas encore son apparence sombre sur appareil. Le précédent [run G1A `36020145724`](https://github.com/tomyrms/Drivy/actions/runs/36020145724) avait réussi 43/43 tests iPhone et 2/2 iPad, dont historique et bilan après relance. G1B corrige aussi le contraste de la ligne sélectionnée iPad et le bandeau de retour des essais qui masquait la navigation.

Les rapports G0 joignent un avertissement UIKit sur l'insertion de `UIKitToolbar` dans un `UIHostingController`. Aucun test n'échoue et la navigation reste visible sur les captures ; cet avertissement reste à surveiller dans la recette physique. Les simulateurs étant configurés en anglais, les dates et le nom localisé du fuseau suivent cette locale ; les libellés applicatifs sont français.

Les [commandes scolaires](commandes-ios.md) sont chiffrées et persistées avant chaque émission. Une demande incertaine conserve son UUID, son contenu exact et sa version à travers les relances ; une preuve AP72 peut confirmer le résultat sans renvoi. Un refus lors d'une reprise ne suffit pas à effacer la demande. Les tests de recréation et d'erreur de stockage ne constituent pas des essais physiques de perte d'alimentation.

Le porteur a confirmé l'installation et l'ouverture du premier IPA 0.1.0/build 1 (`ebdb6ca`, run `36013615026`), tout en signalant son faible contenu. Cela ne valide pas encore la connexion AppAuth ni la configuration de 0.3.0 sur appareil. La [recette scolaire](recette-g1b.md) et la [recette G0](recette-g0.md) restent à exécuter sur les appareils concernés.

## Limites de qualification et suite

Le laboratoire G0 n'est pas une capture scolaire ni un bilan partagé. Le produit complet conserve invitations, onboarding, administration des formations, agenda, leçons, bilans publiés, cours collectifs, packs et web de gestion dans son périmètre. Aucun service d'envoi d'emails utilisable n'a été établi par la documentation de l'ancien hébergement ; il reste à raccorder pour les invitations.

Les 434 scénarios métier et 68 scénarios mobiles ne changent pas de statut par simple création de code ou de workflows. G0 complet reste **NOT_QUALIFIED** : tests physiques GPS, autonomie, VoiceOver et budgets à mesurer. Aucune conformité juridique, disponibilité ou performance n'est déduite des tests automatisés.
