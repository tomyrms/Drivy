# Récupération d’accès — qualification locale des trois rôles (#50)

4 novembre 2026. Lot R3, base `0bdaf32483e3dc4dba9e75056eedb0c74cd43d4e` (lot E intégré).
Correction 1/2 après revue indépendante du commit `a2f562523a8e06686955d88881ae29ea296d1ae5` :
le moniteur distinct reçoit une vraie leçon, et la comparaison avant/après porte désormais sur des
projections métier explicites au lieu d’un ensemble d’identifiants.

Ce lot ne change aucun comportement produit : ni `apps/`, ni `infra/`, ni migrations, ni dépendances, ni droits.
Les trois fermetures de production restent en place — indicateur API/BFF désactivé par défaut,
`resetPasswordAllowed:false` du realm déployé, refus 503 du chemin direct `reset-credentials` dans Caddy.
Le choix du relais SMTP réel reste reporté : aucun envoi externe, aucun compte réel, aucune activation.
L’issue #50 n’est pas clôturée.

## Portée exécutée

Harnais isolé sur conteneurs jetables, comptes strictement fictifs `@example.invalid` :

- PostgreSQL 17 (`postgres:17-alpine@sha256:b0f9560a…`) sur `127.0.0.1:5432`, base neuve `drivy_onboarding_e2e` ;
- Mailpit (`axllent/mailpit:v1.31.2@sha256:74d609a4…`) sur `127.0.0.1:1025/8025` ;
- Keycloak 26.7.4 éphémère démarré par le harnais (provider compilé localement, thème Drivy, realm synthétique) ;
- Node 24.22.2 portable, Chromium déjà installé (aucun téléchargement partagé) ;
- conteneurs `drivy-r3-50-pg` et `drivy-r3-50-mailpit` inventoriés puis créés à mon nom, supprimés après la recette.

Commandes et résultats réels de cette correction :

| Commande | Résultat |
|---|---|
| `npx tsx --test scripts/dev/check-school-account-recovery.test.ts` | 24/24 réussis, exit 0 |
| `npx tsc -p artifacts/tsconfig-r3-50.json --noUnusedLocals false` (périmètre du lot) | exit 0 |
| `npm run build --prefix apps/web` | exit 0 (aucun fichier produit modifié) |
| `ONBOARDING_E2E_DATABASE_URL=… npx tsx scripts/dev/check-school-opening.ts --extended=recovery` | **151 contrôles réussis, exit 0** (`result.json` PASSED, 2026-11-04T14:56:52Z) |
| `npx tsc -p infra/dev/tsconfig.json` | exit 2 — uniquement les trois diagnostics préexistants, dans des fichiers identiques à `HEAD` |

Dépendances déjà verrouillées installées (`npm ci`, `npm ci --prefix apps/web --ignore-scripts`,
`npm ci --prefix infra/dev --ignore-scripts`, exit 0 au lot précédent) ; aucun verrou ni paquet global modifié.

## Fixture du rôle moniteur

Le compte moniteur ne portait aucune leçon : le rôle n’aurait été qu’une étiquette sur un compte sans objet
métier. Le harnais crée donc, avant toute comparaison, une vraie leçon **donnée par ce moniteur distinct** :

1. il lit, en base, la formation active du dossier élève et la sélection commerciale de la leçon existante
   (produit, conditions, prix figé, procédure) ;
2. il affecte le moniteur à cette formation par `POST /v1/schools/{school}/trainings/{training}/assignments`
   (refus `ASSIGNMENT_CONFLICT` toléré, tout autre refus échoue) ;
3. il demande un créneau réel par `GET /v1/schools/{school}/lessons/next-slot`, puis réserve par
   `POST /v1/schools/{school}/lessons` avec cette sélection commerciale.

La leçon de l’administrateur et celle de l’élève ne sont ni déplacées ni remplacées : la recette vérifie que
l’administrateur conserve sa leçon en même temps que le moniteur reçoit la sienne. Aucune leçon n’est fabriquée
en SQL ; les refus de droits restent ceux de l’API.

## Ce que prouvent les trois rôles

État durable mesuré après la recette (aucune adresse ni identifiant dans ce tableau) :

| Rôle | Rôles du rattachement | Rattachements | Écoles | Leçons suivies | Leçons données | Formations | Dossiers | Disponibilités | Affectations |
|---|---|---|---|---|---|---|---|---|---|
| administrateur | `ADMIN,INSTRUCTOR` | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 1 |
| moniteur | `INSTRUCTOR` | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 1 |
| élève | `LEARNER` | 1 | 1 | 2 | 0 | 1 | 1 | 0 | 0 |

### Projection exactement comparée

Les deux instantanés sont lus dans le schéma applicatif, avec la connexion d’administration du harnais
(`drivy_test`, non filtrée par RLS), et non dans les jetons du fournisseur. La comparaison porte sur ces champs,
et seulement sur eux :

- **liens d’identité** : émetteur, sujet, personne liée ;
- **identité de personne** : identifiant, statut, nom d’affichage, prénom, nom, adresse de contact, locale, version ;
- **rattachements, rôles et droits** : école, rôles, droits, statut, `access_epoch`, version ;
- **affectations de moniteur** : identifiant, formation, rattachement moniteur, début, fin ;
- **leçons suivies et leçons données** : identifiant, formation, dossier, personne élève, rattachement moniteur,
  statut, début, fin, fuseau, point de rencontre, prix figé, tampon, procédure, version de publication, version ;
- **formations** : identifiant, dossier, offre, clé d’offre, statut, début, fin, version ;
- **dossiers élève** : identifiant, profil administratif, politique administrative, date de mise à jour du profil,
  rattachement ayant saisi, source de saisie, archivage, version ;
- **disponibilités** : identifiant, rattachement moniteur, jours, début, fin, validité, retrait, version ;
- **totaux en base** : nombre de lignes des huit tables ci-dessus.

Cette projection n’est pas un instantané exhaustif de la base : tout champ non listé et toute autre table
(hors totaux) ne sont pas comparés. L’ordre de lecture est normalisé (tri par identifiant, rôles et jours triés)
pour qu’un simple changement d’ordre ne produise pas de faux écart. Aucune valeur, aucun identifiant et aucune
adresse ne sortent de la comparaison : seuls des libellés anonymes de section sont produits.

Chaque rôle vérifie en outre :

- l’identité OIDC reste le même utilisateur (`id`, `createdTimestamp`, nom d’utilisateur, adresse toujours
  vérifiée) et les totaux de personnes/liens ne bougent pas → pas de doublon ;
- les droits relus par `GET /v1/me` avec un jeton neuf sont identiques, octet pour octet, à ceux d’avant →
  pas d’élévation ;
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

- adresse connue et adresse inconnue : même phrase conditionnelle, mot pour mot, reprise du thème Drivy ;
- panne SMTP (relais injoignable) : la même phrase est conservée, aucune livraison annoncée ;
- lien expiré (durée de vie du jeton d’action ramenée à 1 s, attente réelle de 2,1 s) : pas de formulaire ;
- perte de connexion au démarrage du parcours : échec honnête « La récupération est momentanément
  indisponible. », reprise proposée, aucune confirmation d’envoi.

## Tests ciblés des helpers (RED/GREEN)

Le fichier de tests couvre la logique du harnais, sans conteneur ni réseau : normalisation de l’ordre, chaque
section de la projection, personne absente, rôle manquant, objets métier obligatoires par rôle, et **contenu
modifié à identifiant inchangé** pour la personne, la leçon, la formation, le dossier élève, la disponibilité,
le rattachement et l’affectation.

Preuves RED obtenues en dégradant localement le helper, puis restauration :

- garde de rôle du moniteur retirée → `actual: []` / `expected: ['au moins une leçon donnée']`, exit 1 ;
- projection réduite aux seuls identifiants (comportement de l’ancien harnais) → cinq tests de contenu
  échouent (`leçons suivies`/`leçons données`, `formations`, `dossiers élève`, `disponibilités`,
  `affectations de moniteur`), exit 1 ; projection complète restaurée → 24/24, exit 0.

Une première exécution réelle a aussi révélé que `drivy.learner_profile` ne porte plus `display_name`,
`contact_email` ni `profile_readiness` : la projection a été corrigée sur les colonnes réellement présentes
(`profile_id`, `administrative_policy_id`, `profile_updated_at`, `entered_by_membership_id`, `entry_source`,
`archived_at`, `version`), et l’identité nominative reste lue sur `drivy.person`.

## Limites par critère de #50

1. **Parcours complet iOS et web** — web (portail + BFF), API et fournisseur qualifiés ici. Parcours iOS et
   tests Apple hors de ce lot : **non qualifié**.
2. **Même compte, mêmes leçons, mêmes écoles** — qualifié localement sur trois comptes synthétiques réels en
   PostgreSQL, avant/après, sur la projection listée ci-dessus. Aucun compte réel n’a été réinitialisé.
3. **Indistinguabilité d’une adresse existante** — qualifiée au niveau de la réponse affichée (connue, inconnue,
   panne SMTP). Latence, taille de réponse et sondes directes au fournisseur ne sont pas mesurées.
4. **Expiration, rejeu, tentatives excessives, perte de connexion** — expiration, rejeu et perte de connexion
   qualifiés. **Tentatives excessives non qualifiées ici** : les tests web couvrent le compteur BFF
   (30 entrées anonymes / 10 min / préfixe `/64`), mais **ce compteur ne protège pas les appels directs à
   Keycloak** et ne prouve aucune limitation à la frontière `reset-credentials`. La garde directe reste à
   choisir et à qualifier avant activation, avec le refus Caddy maintenu d’ici là.
5. **Politique de sessions et reprise Face ID** — politique de sessions qualifiée sur les deux branches ;
   Face ID reste un verrou local non exercé ici (appareil physique) : **non qualifié**.
6. **Absence de service d’envoi** — qualifiée pour la panne du relais (phrase conditionnelle conservée) et pour
   l’indisponibilité du parcours (échec honnête, reprise). Aucun message n’est fabriqué.
7. **Environnement isolé** — base vide dédiée, conteneurs jetables nommés, comptes fictifs, aucun accès à un
   service ou une donnée de production.

Reste hors portée de ce lot, et donc de la clôture : choix et qualification du SMTP réel, limitation directe de
`reset-credentials`, parcours iOS complet, reprise physique Face ID, exécution CI distante.

## Hygiène des artefacts

`artifacts/onboarding-web-synthetic/` (ignoré par Git) ne contient que des captures du parcours d’ouverture
d’école et le bilan `result.json` : libellés de contrôles, statut, version de navigateur. Aucun lien de
récupération, jeton, cookie, adresse, mot de passe ni trace HTTP n’y est écrit ; le contrôle par recherche de
motifs (`eyJ`, `action-token`, `reset-credentials`, `@example.invalid`, `Bearer`, `set-cookie`) ne remonte
qu’un libellé contenant le mot « CSRF ».
