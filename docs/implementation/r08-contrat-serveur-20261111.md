# Contrat serveur R08 — politique de l'école et préférences de signalements du compte

Date : 11 novembre 2026. Epic #465, tâches #466 (R08-T01) et #467 (R08-T02). Branche `tomyrms/r08-serveur`.
Public : les agents web (#468) et iOS (#469), qui partent de ce contrat. Contrat machine : `apps/api/contracts/observation-preferences.json`
(OpenAPI canonique 3.11.0 conservé : ces routes ne figurent pas au canon, comme les autres extensions de `apps/api/contracts/`).
Méthode du classement (score, hystérésis, biais de position) : inchangée.

## 1. Ce qui change

| Avant | Maintenant |
| --- | --- |
| L'ordre et l'affichage des signalements sont à l'école ; un moniteur muni du droit `MANAGE_OBSERVATION_THEMES` peut les écrire. | L'école garde une **référence** et une **politique** ; seul l'**administrateur** de l'école écrit l'une et l'autre. Le droit `MANAGE_OBSERVATION_THEMES` reste enregistré mais n'ouvre plus rien. |
| Le classement intelligent est propre à chaque adhésion (une école = un classement). | Le classement est propre au **compte** (la personne), commun à toutes ses écoles et à tous ses appareils. |
| Aucun ordre ni affichage personnels. | Si l'école l'autorise, le compte a son ordre et son affichage ; sinon la liste de l'école s'applique. |
| Pas de remise à zéro de l'apprentissage. | « Recommencer l'apprentissage » pose une borne durable. |

## 2. Modèle de données (migration `20261111_observation_preferences.sql`)

- `observation_theme_settings.personalization_allowed boolean NOT NULL DEFAULT false` : la politique. Toutes les écoles existantes passent à `false`
  (visibilité imposée), avec leur configuration intacte.
- `person_observation_preference` (nouvelle, RLS forcée, une ligne par personne, version 1 = absente) : `theme_order`, `hidden_themes`
  (NULL tant que la personne n'a rien établi), `mode` (`MANUAL`/`SMART`), `ranked_order`, `ranked_on`, `learning_generation`, `learning_since`.
  Aucune clé d'école : changer ou quitter une école ne touche à rien.
- `can_manage_observation_themes(school)` devient « ADMIN actif de l'école » : les politiques RLS de l'école suivent sans être réécrites.
- Fonctions `SECURITY DEFINER` : `observation_staff`, `observation_account_usage(zone)`, `observation_adoption_candidates()`,
  `adopt_legacy_observation_rankings()`.
- `observation_ranking` (par adhésion) n'est plus modifiable par le service (`REVOKE INSERT, UPDATE`) ; elle reste lisible pour la reprise.
- RLS forcée sur la nouvelle table. Les inventaires `capture*.integration.test.ts` n'appliquent que les migrations numérotées (`NNN_`) : leur compteur (67) ne voit pas cette migration datée et reste inchangé.

## 3. Droits (relus côté serveur à chaque commande)

| Action | Qui |
| --- | --- |
| Lire les préférences du compte, lire la configuration de l'école | moniteur ou administrateur de l'école ouverte |
| Écrire la configuration et la politique de l'école | administrateur de l'école seul (`403 OBSERVATION_THEMES_ACCESS_REQUIRED` sinon) |
| Changer le mode (manuel/intelligent), recommencer l'apprentissage | moniteur ou administrateur |
| Enregistrer ordre/affichage personnels, rétablir la présentation | moniteur ou administrateur **si l'école autorise la personnalisation** ; sinon `403 OBSERVATION_PERSONALIZATION_DISABLED` |
| Lire ou écrire les préférences d'un tiers | personne (RLS : chacun ne voit que sa ligne, administration comprise) |

Un élève et un compte étranger à l'école n'ont aucun accès (403, ou 404 pour un compte sans adhésion).

## 4. Routes

Toutes sous `/v1/schools/{schoolId}/`. `{schoolId}` désigne l'école **ouverte** : sa politique et sa configuration servent à calculer la palette ;
les préférences lues et écrites sont celles du compte. Écritures : `If-Match: "<version>"` obligatoire (428 sinon, 412 `VERSION_CONFLICT` si périmé),
`Idempotency-Key` égale à `operationId`. Un rejeu avec le même contenu rend l'état **actuel** ; un autre contenu sous le même
`operationId` donne `409 IDEMPOTENCY_MISMATCH`. Réponse : enveloppe `{data, requestId, serverTime}` et en-tête `ETag: "<version>"`.

### `GET observation-preferences`
`data` : `id` (personne), `schoolId`, `version`, `personalizationAllowed`, `customized`, `mode`, `themes` (18 thèmes `{key,title,competencyKeys,visible,defaultVisible,defaultPosition}`
dans l'ordre manuel en vigueur : base de l'écran de réglage), `palette` (clés affichées dans « Signaler », **dans l'ordre à afficher**), `rankedOn`,
`learning {generation, since}`, `adoption` (voir § 7). Au premier passage du jour en mode intelligent, la lecture refait et garde le classement
(une opération `REFRESH_OBSERVATION_RANKING` par compte et par jour, rejouée par un second appareil).

### `PUT observation-preferences`
Corps `{operationId, mode?, themes?}`, au moins un des deux. `themes` : les 18 clés du catalogue, sans doublon, au moins une visible, `{key, visible}` dans l'ordre voulu.
Commande `SAVE_OBSERVATION_PRESENTATION`, audit `ObservationPresentationSaved`. Passer en `SMART` repart des scores seuls (jamais de l'ordre vu la veille).

### `POST observation-preferences/presentation-reset`
Corps `{operationId}`. Le compte retrouve la configuration de l'école (`theme_order` et `hidden_themes` remis à vide) ; mode et apprentissage ne bougent pas.
Commande `RESET_OBSERVATION_PRESENTATION`, audit `ObservationPresentationReset`. Refusé si l'école impose sa visibilité.

### `POST observation-preferences/learning-reset`
Corps `{operationId}`. Voir § 6. Commande `RESET_OBSERVATION_LEARNING`, audit `ObservationLearningReset`.

### `GET/PUT observation-themes` (école) — compatibles
La réponse gagne `personalizationAllowed`. Le corps du `PUT` accepte `personalizationAllowed` **facultatif** : absent (ancien client), la politique reste telle quelle.
`canManage` ne vaut plus `true` que pour l'administrateur.

### `GET/PUT observation-ranking` (ancienne route) — compatibles
Forme d'origine conservée (`id` et `membershipId` = adhésion, `order` vide en mode manuel). Elle lit et écrit désormais le compte : sa `version` est celle des préférences.
Aucune ligne par école n'est plus créée. Les apps déjà installées continuent de fonctionner.

## 5. Palette effective

Calculée par le serveur à chaque lecture, **jamais réécrite dans les préférences** :

1. liste de référence : si l'école autorise la personnalisation **et** que le compte a établi son ordre, c'est le sien (`customized: true`) ; sinon celle de l'école ;
2. si le mode est `SMART`, le classement enregistré est ramené à cette liste (thème disparu retiré, nouveau en fin).

Une école qui impose sa visibilité garde donc sa liste et son ordre ; les réglages personnels restent **en réserve**, intacts, et reprennent si la politique s'ouvre.
Le classement intelligent s'applique dans tous les cas à la liste affichée. Le rang noté sur un signalement (`palette_position`) est le rang dans cette palette.

## 6. « Recommencer l'apprentissage »

La commande incrémente `learning_generation` et pose `learning_since = now()`. La fonction d'usage (`observation_account_usage`) ne lit **aucun geste observé avant cette borne**
(`coalesce(observed_at, created_at)`), quel que soit son chemin : reclassement du jour, réactivation du mode, geste ancien reçu après coup depuis une file hors ligne.
En mode `SMART`, le classement repart des références seules (daté d'aujourd'hui) ; en mode manuel, rien n'est classé. **Aucune donnée pédagogique n'est supprimée**
(observations, leçons, progression). La génération entre dans l'identifiant de l'opération quotidienne et est relue sous verrou : un rafraîchissement en vol
au moment de la remise à zéro est ignoré.

Les gestes comptent sur **toutes les écoles actives** du compte, dans un jour de classement unique `Europe/Zurich` (le fuseau d'une école ne s'applique plus).

## 7. Reprise de l'existant et divergences

La migration reprend sur le compte le classement **intelligent** d'une personne quand ses adhésions n'en portent qu'un, ou plusieurs identiques. Elle est répétable et ne remplace jamais
un compte déjà initialisé. Des classements contradictoires (intelligent dans une école, manuel dans l'autre, ou deux ordres appris différents) ne sont **pas départagés** :
le compte démarre en mode manuel et `GET` publie `adoption: {candidates: [{schoolId, schoolName, mode, themes}]}` (au moins deux entrées) tant que la personne n'a rien enregistré.
Le client peut proposer ces configurations pour préremplir ; la première écriture est un choix explicite. L'ordre et l'affichage manuels de l'école ne sont **pas** recopiés sur le compte
(il suit l'école tant qu'il n'a rien établi).

## 8. Décisions conservatrices à valider (hors énoncé)

1. **Visibilité imposée** : l'ordre *et* l'affichage de l'école s'appliquent ; seul le classement intelligent reste personnel. Les actions de personnalisation sont refusées pour tous, administrateur compris (il change la politique de l'école, pas son compte).
2. L'ancien droit `MANAGE_OBSERVATION_THEMES` n'est pas supprimé des adhésions : il est simplement sans effet.
3. Divergence : le serveur ne choisit jamais à la place de la personne (§ 7).
4. Jour de classement fixe `Europe/Zurich`.
5. Un geste sans `observed_at` est daté de sa réception pour la borne d'apprentissage.
6. Le corps de la première personnalisation est la liste complète des 18 thèmes (le client part de `themes`).

## 9. Ce que web et iOS doivent faire

- Web : déclarer dans `apps/web/server/school-routes.ts` les quatre routes `observation-preferences` (GET ; PUT `ifMatch`, `bodyLimit` 4_096 ; POST `presentation-reset` `ifMatch`, `bodyLimit` 1_024 ; POST `learning-reset` `ifMatch`, `bodyLimit` 1_024), sinon 404 en production. `observation-themes` est déjà déclaré. Ajouter la politique à l'écran d'administration de l'école. `observation-ranking` n'est pas déclaré et n'a pas à l'être.
- iOS : lire `palette` pour « Signaler » (plus de calcul local de l'ordre) ; écrire via `observation-preferences` ; l'ancienne route reste valable pour les versions installées.

## 10. Vérifications

Voir la section « 11 novembre 2026 — R08 serveur » de `STATUS.md` : suites exécutées, résultats, et ce qui reste à qualifier (le garde de génération d'une opération quotidienne périmée n'est couvert que par le code et la borne SQL, sans test dédié).
