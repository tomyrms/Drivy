# Écoles clientes et codes d'ouverture — R01-T02 (#454)

Décisions d'implémentation du deuxième lot de l'épic #452 (administration commerciale de la plateforme). Date : 13 novembre 2026 ; la migration porte la date 20261114 pour se classer après celles du lot précédent. Branche `tomyrms/r01-t02-ecoles-codes`, issue de `tomyrms/r01-t01-operateurs` puis mise à jour avec `master` (T01 fusionné). Rien n'est déployé.

## Périmètre

L'opérateur de la plateforme tient l'annuaire de ses écoles clientes, ouvre une fiche, crée un code d'ouverture pour cette fiche et suit ce code jusqu'à l'école créée. Le destinataire du code ouvre son école dans l'app (parcours iPhone/iPad existant) : l'école et son premier ADMIN sont alors reliés une seule fois à la fiche et au code, et l'opérateur retrouve l'école, son contact et sa progression sans voir aucun contenu pédagogique. Les écoles pilotes déjà ouvertes ne sont ni recréées ni modifiées : un rattachement explicite les relie à une fiche.

Ce lot réutilise le point d'entrée du lot précédent (`platformCommand`, `platformRead`, `recordPlatformAction`) : identité confirmée en base, clé d'idempotence, reçu durable, version, journal commercial. Aucune offre, aucune échéance, aucun prix : seuls des emplacements sont réservés pour #455 et #456.

## Modèle de données

Migration `apps/api/migrations/20261114_platform_clients.sql` (datée, hors compteur des migrations numérotées ; la RLS est prouvée dans `platform-clients.integration.test.ts`). Aucune donnée n'est créée ni modifiée par la migration.

- **`platform_client`** : la fiche. Tous les champs de contact, de facturation et de notes sont facultatifs (aucune saisie exhaustive n'est exigée). `school_id` unique relie l'école ; `link_source` vaut `OPENING_CODE` ou `EXISTING_SCHOOL` ; `opened_via_link_id` et `first_admin_membership_id` (uniques) gardent le code et le premier ADMIN ; des contraintes `CHECK` rendent ces colonnes solidaires (tout ou rien). `commercial_state` n'admet que `NOT_CONFIGURED` ; `version` est incrémentée par déclencheur. RLS forcée.
- **`school_opening_link`** reçoit `client_id` (fiche du code) et `issued_by_operator_id` (émetteur). Les codes distribués avant ce lot n'ont ni l'un ni l'autre et restent valables : leur fiche naît à l'ouverture.
- **`platform_client_guard`** (déclencheur) : fiche jamais supprimée, identité et date de création figées, école et origine immuables une fois reliées, rattachement d'une école existante écrit par l'opérateur qui le fait, et refus si un code encore utilisable réserve déjà l'école (`platform_client_code_pending`).
- **`platform_client_opened`** (déclencheur sur la ligne du code, transition AVAILABLE vers USED seulement) : relie l'école, le premier ADMIN et le code à la fiche dans la transaction même qui crée l'école, crée la fiche pour un code d'avant ce lot, et écrit l'événement `SCHOOL_OPENED_FROM_CODE` (acteur SYSTEM, sans le code) au journal. Un rejeu ne relie, ne crée et n'écrit rien de plus : la transition n'a lieu qu'une fois.
- **Lectures `SECURITY DEFINER` à projection fixe** : `platform_client_overview`, `platform_code_overview`, `platform_unattached_schools`. Elles exigent un opérateur actif relu en base et ne rendent que le nom de l'école, son statut, son contact et sa progression de mise en place (étape, nombre d'étapes faites) : jamais un dossier, un trajet, un message ni une personne. Aucune politique d'école n'est élargie.

## Routes

Sous `/v1/platform/…`, toutes réservées à un opérateur actif :

| Route | Rôle |
| --- | --- |
| `GET /clients` | Annuaire : recherche `q` (nom, contact, adresse, école), filtre de préparation, pagination par curseur (25 par défaut, 100 au plus par page), total. |
| `POST /clients` | Création d'une fiche, idempotente (reçu durable). |
| `GET /clients/:id` | Fiche : école, contact, facturation, notes, préparation, offre et échéances réservées, 50 derniers codes. |
| `PATCH /clients/:id` | Modification versionnée (`If-Match`), champs vidés par `null`. |
| `POST /clients/:id/attach-school` | Rattachement explicite d'une école existante. |
| `GET /unattached-schools` | Écoles ouvertes qu'aucune fiche ne relie encore. |
| `GET /school-codes` | Suivi des codes (état, fiche, émetteur, école, progression), filtres et curseur. |
| `POST /school-codes` | « Créer un code » : sur une fiche existante ou en créant la fiche dans la même demande. |
| `POST /school-codes/:id/revoke` | Révocation. |

Journal commercial (actions ajoutées) : `CREATE_PLATFORM_CLIENT`, `UPDATE_PLATFORM_CLIENT`, `ATTACH_EXISTING_SCHOOL`, `CREATE_SCHOOL_OPENING_CODE`, `REVOKE_SCHOOL_OPENING_CODE`, et l'événement système `SCHOOL_OPENED_FROM_CODE`. Chaque ligne porte `schoolId` quand l'école est connue ; aucune ne contient le code, le lien ni une coordonnée. Extension de contrat : `apps/api/contracts/platform-clients.json` (OpenAPI canonique 3.11.0 inchangé).

## Code d'ouverture

- Forme `XXXX-XXXX`, alphabet `A-HJ-NP-Z2-9` (sans O, 0, I, 1), 8 caractères sur 32 symboles ; lien `<origine>/app/ouvrir#token=CODE` (le code reste dans le fragment, jamais envoyé au serveur par le navigateur). Les liens déjà distribués (forme longue) restent compatibles : l'API accepte les deux.
- Validité : 7 jours par défaut, 1, 3, 7, 14 ou 30 jours proposés (30 au plus en base). Un code est AVAILABLE, USED, REVOKED, ou EXPIRED (dérivé de la date, jamais stocké).
- Un seul code utilisable à la fois par fiche ; « Créer un code » reste l'action principale d'une fiche sans école. Un code utilisé ne se révoque pas (409 `OPENING_LINK_USED`) ; une révocation et une utilisation en course : une seule l'emporte.
- Le code naît dans le relais web, n'est montré qu'à la création (copie manuelle du code et du lien, sans envoi : ni WhatsApp ni courriel), reste en mémoire de session le temps d'une réponse perdue puis s'efface ; l'API n'en garde que l'empreinte. Un code « non transmis » se reprend à l'écran tant que la session vit.
- Le destinataire ne choisit ni offre ni privilège : l'école naît en préparation (DRAFT) avec un premier ADMIN, comme avant ce lot.

## Préparation et état commercial

La préparation est dérivée des faits existants, jamais saisie : `AWAITING_SCHOOL` (aucune école reliée), `IN_PREPARATION` (école reliée, statut DRAFT), `ACTIVE` (statut ACTIVE), `ARCHIVED`. Elle est distincte de l'état commercial (`NOT_CONFIGURED` pour l'instant), de l'essai, de l'impayé et de la suspension, que #455 et #456 définiront : ces états-là ne la modifient pas.

## Écoles pilotes

Aucune école existante n'est touchée par la migration. L'opérateur voit les écoles sans fiche (`unattached-schools`) et les rattache explicitement à une fiche, existante ou créée à l'instant : l'école garde son accès, ses données et son statut ; rien n'est recréé, remis à zéro, facturé ni suspendu. La liaison est immuable ensuite (déclencheur). Si un code encore utilisable réserve la fiche, le rattachement est refusé jusqu'à sa révocation, pour que la même école n'existe pas deux fois.

## Concurrence et idempotence

- Chaque mutation porte `Idempotency-Key` et, sur une fiche, `If-Match` ; reçu durable, relu après une réponse perdue.
- Deux destinataires en concurrence sur un code : un seul gagne (201), l'autre reçoit 409 `OPENING_LINK_USED` sans rien apprendre de l'école ; une seule école, une seule fiche liée, un seul premier ADMIN (trois tours dans le test).
- Le rejeu du même compte, y compris avec une demande neuve après un redémarrage du service, rend la même école : jamais une deuxième.
- Le relais web garde le même code pour une même opération tant que le résultat n'est pas confirmé, et en tire un autre seulement après un refus définitif.

## Console web

Onglet « Écoles » (premier, par défaut) de `/app/plateforme`, avant Équipe, Invitations et Journal. Annuaire : recherche, filtres de préparation, « Afficher plus » (curseur), état de chaque code lisible par un badge seulement quand il est inhabituel (code expiré, révoqué). Fiche : école, contact, progression, offre (« Non configurée ») et échéances (« Aucune ») réservées, codes, facturation, notes ; modification enregistrée avec la seule différence (une zone vidée passe à null, une adresse invalide est signalée sur sa zone) ; création de code et rattachement seulement quand ils ont un sens. Les écrans n'ont aucun lien de navigation : tout est action (bouton) ou lecture, donc aucun contrôle de rôle `link` à poser ici. Relais `/app/bff/platform/*` à liste fermée étendue (toute route d'API appelée par le web doit y figurer, sinon 404 en production : voir la note sur la passerelle).

Contrôle navigateur reproductible : `scripts/dev/check-platform-console.mjs` (63 vérifications sur l'aperçu synthétique, Edge, bureau 1280 x 900 et mobile 390 x 844, clair et sombre) ; l'aperçu sert 45 écoles fictives, 3 écoles à rattacher, des codes factices et rejoue la réponse perdue. L'aperçu est fictif : ce n'est ni un essai contre la vraie API ni une qualification sur appareil.

Recette sur la chaîne réelle : `scripts/dev/check-platform-clients.ts`, appelée par `scripts/dev/check-school-opening.ts` juste après la création de l'école par un code. L'opérateur retrouve l'école par la recherche, lit sa fiche (ouverture par un code, offre « Non configurée », échéances « Aucune », aucun contenu pédagogique), la base ne porte qu'une fiche liée avec le premier administrateur et le code utilisé, le journal retient l'ouverture ; il crée ensuite une fiche et un code depuis l'interface (code court, lien avec fragment, aucune école créée, code absent de toutes les tables de la plateforme) puis le révoque. Cette étape a été écrite sans avoir été jouée (pas de Keycloak sur le poste) et n'a jamais tourné : voir `STATUS.md`.

## Parcours iPhone / iPad

Le parcours existe déjà et n'a pas été modifié (Swift non touché, rien ne compile sur ce poste) : saisie ou lien de code, aperçu, création de l'école (`SchoolOpeningView`, `SchoolOpeningClient`), message « Ton école est créée. Termine sa préparation sur le portail web. » (retour clair vers le web), messages distincts pour code invalide, déjà utilisé et expiré ou révoqué (même texte, pour ne rien révéler), « Réessayer » qui renvoie la même demande. Jugé par lecture et par les tests existants (`NativeAccountTests`) ; non exécuté.

## Arbitrages hors énoncé

1. **État commercial** : un seul emplacement `NOT_CONFIGURED`, contrainte `CHECK` à élargir par #455/#456. Offre et échéances sont projetées vides et tolérées par le schéma web.
2. **Codes d'avant ce lot** : ils ne reçoivent une fiche qu'à leur utilisation (fiche sans nom) ; on ne fabrique pas de fiches pour des codes jamais utilisés.
3. **Écoles pilotes sans fiche** : listées au rattachement explicite plutôt que fichées d'office par la migration.
4. **Pas de liste d'élèves ni de moniteurs** pour l'opérateur : seulement école, contact, progression de mise en place.
5. **Fiche** : au plus les 50 derniers codes ; corps de requête de 16 Kio ; notes de 4 000 caractères.
6. **Validité** : 7 jours par défaut, options 1, 3, 7, 14, 30.
7. **Onglet Écoles premier et par défaut** ; la recette du lot précédent clique « Équipe » avant ses étapes.
8. **Création de code et rattachement** proposés seulement sur une fiche sans école et sans code disponible.

## Limites connues

- `platform_client_already_linked` (déclencheur d'ouverture) n'est pas traduit en message d'erreur amical dans `createSchool` : cas très rare, gardé par la règle « un seul code utilisable par fiche » et par un verrou consultatif ; il remonterait comme une erreur générique sans rien écrire.
- Aucun test n'est exécuté avant la fin de l'épic R01 (règle du porteur du 13 novembre 2026) : ce qui a tourné avant la règle et ce qui n'a jamais tourné sont distingués dans `STATUS.md`. La reprise après fermeture ou redémarrage de l'app est prouvée côté API et relais (tests) et par lecture côté iOS ; elle n'est pas rejouée dans l'aperçu (l'état de l'aperçu repart à zéro à chaque chargement).
- L'identifiant d'opération de l'app iOS vit en mémoire : après un arrêt de l'app, la reprise passe par l'identité (même compte, même code : même école), pas par l'identifiant du premier envoi.
- Pas de SMTP : le code est transmis par l'opérateur hors de la console.
- Non vérifié : appareil physique, VoiceOver, GPS, iOS (Swift jamais compilé ici).

## À savoir pour #455 (offres et modules) et #456 (conditions)

- Brancher les offres sur `platform_client` : élargir le `CHECK` de `commercial_state`, ajouter les colonnes ou tables d'offre et d'échéances, remplir `offer` et `dueDates` des projections (déjà réservés dans le contrat, la fiche et le schéma web, rendus « Non configurée » et « Aucune »).
- Les droits scolaires et la suspension se lisent à côté de la préparation, jamais dedans ; ne pas déduire une restriction de `NOT_CONFIGURED`.
- Toute mutation passe par `platformCommand` avec `schoolId` quand l'école est connue ; les journaux existent déjà.
- Une route d'API appelée par le web doit figurer dans la liste fermée de `apps/web/server/platform-routes.ts`, et dans le contrat par `generate-platform-contract.ts` (le test de contrat échoue sinon).
- La fiche ne liste que les 50 derniers codes ; une nouvelle liste liée à la fiche reprend le même modèle de curseur que `GET /clients`.

## Suite donnée par #455

Offres, modules et droits par école sont livrés sur `tomyrms/r01-t03-offres-modules` (`docs/implementation/offres-modules-20261115.md`). Écart avec la première puce ci-dessus : le `CHECK` de `platform_client.commercial_state` n'a pas été élargi et la colonne n'est pas touchée ; l'état affiché (`NOT_CONFIGURED` ou `OFFER_ACTIVE`) est dérivé des attributions par `platform_client_entitlement_core`. `offer` est maintenant rempli (offre en vigueur, plus `scheduledOffer` et `entitlementVersion`) ; `dueDates` reste vide, réservé à #456. La préparation reste distincte des droits : une école en préparation n'est jamais restreinte par elle.
