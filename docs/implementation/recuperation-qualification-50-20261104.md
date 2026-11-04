# Récupération d’accès — qualification locale des trois rôles (#50)

4 novembre 2026. Lot R3, base `0bdaf32483e3dc4dba9e75056eedb0c74cd43d4e` (lot E intégré).

Ce lot ne change aucun comportement produit : ni `apps/`, ni `infra/`, ni migrations, ni dépendances, ni droits.
Les trois fermetures de production restent en place — indicateur API/BFF désactivé par défaut,
`resetPasswordAllowed:false` du realm déployé, refus 503 du chemin direct `reset-credentials` dans Caddy.
Le choix du relais SMTP réel reste reporté par le porteur : aucun envoi externe, aucun compte réel, aucune
activation. L’issue #50 n’est pas clôturée.

## Portée exécutée

Harnais isolé sur conteneurs jetables, comptes strictement fictifs `@example.invalid` :

- PostgreSQL 17 (`postgres:17-alpine@sha256:b0f9560a…`) sur `127.0.0.1:5432`, base vide `drivy_onboarding_e2e` ;
- Mailpit (`axllent/mailpit:v1.31.2@sha256:74d609a4…`) sur `127.0.0.1:1025/8025` ;
- Keycloak 26.7.4 éphémère démarré par le harnais (provider compilé localement, thème Drivy, realm synthétique) ;
- Node 24.22.2 portable, Chromium déjà installé (aucun téléchargement partagé).

Commandes et résultats réels (dernière exécution) :

| Commande | Résultat |
|---|---|
| `npm ci` | exit 0 |
| `npm ci --prefix apps/web --ignore-scripts` | exit 0 |
| `npm ci --prefix infra/dev --ignore-scripts` | exit 0 |
| `npm run build --prefix apps/web` | exit 0 |
| `npx tsc -p infra/dev/tsconfig.json` | exit 2 — trois diagnostics **préexistants**, dans des fichiers identiques à `HEAD` (`check-v3-agenda-acceptance.ts`, `check-v3-entry.ts`, `measure-web-entry.ts`) |
| `npx tsc -p artifacts/tsconfig-r3-50.json --noUnusedLocals false` (périmètre du lot) | exit 0 |
| `npx tsx --test scripts/dev/check-school-account-recovery.test.ts` | 16/16 réussis, exit 0 |
| `ONBOARDING_E2E_DATABASE_URL=… npx tsx scripts/dev/check-school-opening.ts --extended=recovery` | **150 contrôles réussis, exit 0** (`artifacts/onboarding-web-synthetic/result.json`, `status: PASSED`) |

Le typecheck du lot est donc vert ; l’échec du typecheck global vient de deux simulations d’`IdentityProvider`
antérieures à `password` et d’une variable inutilisée, hors périmètre autorisé.

## Ce que prouvent les trois rôles

Chaque rôle récupère **son propre compte déjà rattaché**, pas une étiquette créée pour la recette. Les objets
sont lus dans le schéma applicatif PostgreSQL (`drivy.person`, `drivy.identity_link`, `drivy.membership`,
`drivy.lesson`, `drivy.training`, `drivy.learner_profile`, `drivy.availability_rule`), pas seulement dans les
jetons du fournisseur.

État durable mesuré après la recette (aucune adresse ni identifiant dans ce tableau) :

| Rôle | Rôles du rattachement | Rattachements | Écoles | Leçons suivies | Leçons données | Formations | Dossiers | Disponibilités |
|---|---|---|---|---|---|---|---|---|
| administrateur | `ADMIN,INSTRUCTOR` | 1 | 1 | 0 | 1 | 0 | 0 | 1 |
| moniteur | `INSTRUCTOR` | 1 | 1 | 0 | 0 | 0 | 0 | 1 |
| élève | `LEARNER` | 1 | 1 | 1 | 0 | 1 | 1 | 0 |

Avant/après, pour chaque rôle, l’instantané complet est comparé section par section : liens d’identité,
identité de personne (`id`, statut, nom d’affichage), rattachements/rôles/droits/`access_epoch`, leçons suivies,
leçons données, formations, dossiers élève, disponibilités, et totaux de lignes de la base. Aucune différence
tolérée ; l’ordre de lecture est normalisé pour ne pas produire de faux écart.

Chaque rôle vérifie en outre :

- l’identité OIDC reste le même utilisateur (`id`, `createdTimestamp`, nom d’utilisateur, adresse toujours
  vérifiée) et les totaux de personnes/liens ne bougent pas → pas de doublon ;
- les droits relus par `GET /v1/me` avec un jeton neuf sont identiques, octet pour octet, à ceux d’avant → pas
  d’élévation ;
- l’ancien mot de passe est refusé, le nouveau accepté (réauthentification réelle par `password grant`) ;
- le lien est à usage unique (rejeu sans formulaire de mot de passe) ;
- la récupération ne crée aucune session BFF (`/app/bff/session` non authentifiée, `/app/bff/me` refusé).

## Sessions

La politique est testée sur les deux branches réelles du fournisseur :

- administrateur et élève, case « Se déconnecter des autres appareils » cochée → le jeton de renouvellement
  antérieur est refusé (400) ;
- moniteur, case non cochée → le renouvellement antérieur reste valide et rien n’est présenté comme révoqué ;
- dans les deux cas, le jeton d’accès déjà émis reste valide jusqu’à son expiration (300 s) : la révocation
  porte sur le renouvellement, pas sur les jetons d’accès en circulation. Cette limite est affirmée, pas masquée.

## Réponses uniformes, expiration, panne, perte de connexion

- adresse connue et adresse inconnue : même phrase conditionnelle, mot pour mot, reprise du thème Drivy
  (`emailSentMessage`) ;
- panne SMTP (relais injoignable) : la même phrase est conservée, aucune livraison annoncée ;
- lien expiré (durée de vie du jeton d’action ramenée à 1 s, attente réelle de 2,1 s) : pas de formulaire ;
- perte de connexion au démarrage du parcours (requête interrompue vers `POST /app/bff/account-recovery/start`) :
  échec honnête « La récupération est momentanément indisponible. », reprise proposée, aucune confirmation
  d’envoi affichée.

## Tests ciblés des helpers (RED/GREEN)

`scripts/dev/check-school-account-recovery.test.ts` couvre la logique du harnais, sans conteneur ni réseau :
normalisation de l’ordre, chaque section de l’instantané, personne absente, rôle manquant, objets métier
obligatoires par rôle (leçon donnée pour administrateur, disponibilité pour moniteur, dossier/formation/leçon
pour élève), phrase conditionnelle réellement lue dans le thème, message de panne réellement présent dans le
portail.

Preuve RED obtenue par mutation locale du helper, puis restauration :

- suppression du contrôle « au moins une leçon donnée » de l’administrateur et du contrôle « au moins une
  disponibilité » du moniteur → trois tests échouent avec `actual: []` / `expected: [… ]`, exit 1 ;
- contrôles restaurés → 16/16 réussis, exit 0.

## Limites par critère de #50

1. **Parcours complet iOS et web** — le web (portail + BFF), l’API et le fournisseur sont qualifiés ici. Le
   parcours iOS, Face ID et les tests Apple restent hors de ce lot : **non qualifié**.
2. **Même compte, mêmes leçons, mêmes écoles** — qualifié localement sur trois comptes synthétiques réels en
   PostgreSQL, avant/après, sans duplication ni élévation. Aucun compte réel n’a été réinitialisé.
3. **Indistinguabilité d’une adresse existante** — qualifiée au niveau de la réponse affichée (connue, inconnue,
   panne SMTP). Les égalités de latence, de taille de réponse ou les sondes directes au fournisseur ne sont pas
   mesurées.
4. **Expiration, rejeu, tentatives excessives, perte de connexion** — expiration, rejeu et perte de connexion
   qualifiés. **Tentatives excessives non qualifiées ici** : les tests web couvrent le compteur BFF (30 entrées
   anonymes / 10 min / préfixe `/64`), mais **ce compteur ne protège pas les appels directs à Keycloak** et ne
   prouve aucune limitation à la frontière `reset-credentials`. La garde directe reste à choisir et à qualifier
   avant activation, avec le refus Caddy maintenu d’ici là.
5. **Politique de sessions et reprise Face ID** — politique de sessions qualifiée sur les deux branches ;
   Face ID reste un verrou local non exercé ici (appareil physique) : **non qualifié**.
6. **Absence de service d’envoi** — qualifiée pour la panne du relais (phrase conditionnelle conservée) et pour
   l’indisponibilité du parcours (échec honnête, reprise). Aucun message n’est fabriqué.
7. **Environnement isolé** — base vide dédiée, conteneurs jetables nommés et supprimés, comptes fictifs,
   aucun accès à un service ou une donnée de production.

Reste hors portée de ce lot, et donc de la clôture : choix et qualification du SMTP réel, limitation directe de
`reset-credentials`, parcours iOS complet, reprise physique Face ID, exécution CI distante.

## Hygiène des artefacts

`artifacts/onboarding-web-synthetic/` (ignoré par Git) ne contient que des captures du parcours d’ouverture
d’école et le bilan `result.json` : libellés de contrôles, statut, version de navigateur. Aucun lien de
récupération, jeton, cookie, adresse, mot de passe ni trace HTTP n’y est écrit ; le contrôle par recherche de
motifs (`eyJ`, `action-token`, `reset-credentials`, `@example.invalid`, `Bearer`, `set-cookie`) ne remonte
qu’un libellé contenant le mot « CSRF ».
