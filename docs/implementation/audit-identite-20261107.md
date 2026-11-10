# Audit identité du 7 novembre 2026 — lot C serveur (#421, #450)

Ce document décrit la correction côté API. Il ne ferme aucune issue : #450 n'est résolue qu'après le raccord des clients (iOS, web).

## #421 — écrasement de l'identité entre routes et entre écoles

### Cause

L'identité (nom, e-mail, téléphone, date de naissance, adresse) vit sur `drivy.person`, mais se lit et s'écrit par deux familles de routes :

- `/v1/me/profile` (If-Match = `person.version`) ;
- `/v1/schools/{id}/learners/{id}` et `.../administrative-profile` (If-Match = `learner_profile.version`, propre à chaque école).

Une écriture par une route faisait avancer `person.version` (et, pour la route scolaire, la version du seul dossier de l'école concernée). Les dossiers des **autres** écoles de la personne gardaient leur version : un formulaire ouvert avant la modification était accepté et écrasait la valeur plus récente. L'écriture de `/me` ne faisait pas avancer les dossiers scolaires du tout.

### Inventaire des écrivains de `drivy.person` (`apps/api/src`)

| Écrivain | Champs d'identité | Version |
| --- | --- | --- |
| `profiles.ts` `saveProfile` (PATCH dossier, route historique et `administrative-profile`) | oui | `person.version+1` et `learner_profile.version+1` du dossier courant |
| `self-profile.ts` PATCH `/me/profile` | oui | `person.version+1` |
| `invitations.ts` `createLearnerProfile` (complète les champs vides) | oui | `person.version+1` |
| `school-opening.ts` (nom affiché à l'ouverture d'école) | `display_name` | `person.version+1` |
| `self-profile.ts` PUT/DELETE photo | non | `person.version+1` |

Lecteurs : les mêmes routes, plus les projections de dossier. Aucune version n'est recalculée côté client.

### Correction (migration `20261107_identity_versions_photo_generation.sql`)

Trigger `person_identity_bumps_profiles` (`AFTER UPDATE`, uniquement si `version` change et qu'un champ d'identité change) : il fait avancer de 1 la version de **tous** les `learner_profile` de la personne, hors le dossier que la commande en cours incrémente déjà (variable de transaction `app.identity_origin_profile`, posée par `profiles.ts` et `invitations.ts`).

- Les versions restent numériques et ne font que croître : aucun client existant ne change de sens.
- Les photos ne touchent pas à ces champs : elles ne périment pas les dossiers.
- Verrouillage : les dossiers sont verrouillés `ORDER BY id FOR UPDATE`, donc un ordre unique entre écritures simultanées (pas d'interblocage observé en test).
- La fonction est `SECURITY DEFINER` (la RLS empêche `drivy_app` de voir les dossiers des autres écoles), `search_path` figé, `EXECUTE` retiré à `PUBLIC`. Elle ne lit ni n'expose rien : elle incrémente seulement.
- Droits par champ, politique de profil, RLS et rejeu idempotent (même `operationId`, même contenu → même réponse sans nouvelle version) sont inchangés ; testés.

### Ce qui reste visible côté client

Un 412 `VERSION_CONFLICT` là où l'écrasement passait silencieusement. Le client relit, résout, puis réécrit (comportement déjà géré pour les conflits scolaires).

## #450 — génération de photo monotone

### Cause

`photo_version` servait à la fois de drapeau de présence (0 = aucune photo) et de compteur de contenu. Le retrait le remettait à 0 ; le remplacement suivant réutilisait donc 1. Un appareil gardant en cache la génération 1 d'avant le retrait croyait sa photo à jour.

### Correction

- Colonne `person.photo_generation integer NOT NULL DEFAULT 0` : dernier compteur émis, jamais diminué ni remis à 0 (trigger `guard_photo_generation`, `CHECK photo_generation >= photo_version`).
- `photo_version` garde son sens : génération de la photo **présente**, 0 si aucune. L'AAD des portraits chiffrés (`photoAAD(person.id, photo_version)`) est inchangé : les portraits existants restent lisibles sans réécriture. Rattrapage de la migration : `photo_generation = photo_version` pour les photos présentes.
- PUT : nouvelle génération = `photo_generation + 1`. DELETE : `photo_version = 0`, `photo_generation` conservé.
- Chiffrement AES-256-GCM, bornes d'image (64–1024 px, 256 Kio) et absence de clair : inchangés.

### Contrat client — additif, compatible (`self-profile.json` passe à `:4`)

Champ ajouté aux réponses de `GET/PATCH /v1/me/profile`, `PUT/DELETE /v1/me/profile/photo` : `photoGeneration` (entier ≥ 0). OpenAPI canonique 3.11.0 conservé. Un client qui l'ignore reste correct.

Sans photo (jamais ou après retrait) :

```json
{ "personId": "…", "displayName": "Alice Exemple", "photoVersion": null, "photoGeneration": 2, "version": 9 }
```

Avec photo :

```json
{ "personId": "…", "displayName": "Alice Exemple", "photoVersion": 3, "photoGeneration": 3, "version": 10 }
```

`GET /v1/people/{personId}/photo` répond 404 après retrait, et 200 avec `ETag: "photo-<photoVersion>"` après remplacement.

Règles pour le client :

1. Le cache d'un portrait est indexé par `(personId, photoVersion)`.
2. `photoVersion == null` ⇒ purger le cache de cette personne.
3. `photoVersion` ≠ valeur en cache ⇒ charger la nouvelle photo. Comme la génération n'est jamais réutilisée, un cycle suppression/remplacement produit toujours une valeur différente.
4. Une intention ancienne (PUT/DELETE avec l'ancien `If-Match`) est refusée en 412 : chaque changement de photo avance `person.version`.
5. Pour détecter « une photo a existé puis a disparu » sans la photo, comparer `photoGeneration` à la dernière valeur vue.

## Migration et retour arrière

Migration additive, appliquée dans une transaction ; la politique RLS temporaire de rattrapage est supprimée dans la même migration.

Retour arrière (non automatisé, à jouer sur sauvegarde) :

```sql
DROP TRIGGER person_identity_bumps_profiles ON drivy.person;
DROP FUNCTION drivy.bump_identity_dependents();
DROP TRIGGER person_photo_generation_guard ON drivy.person;
DROP FUNCTION drivy.guard_photo_generation();
ALTER TABLE drivy.person DROP CONSTRAINT person_photo_generation_covers_version;
ALTER TABLE drivy.person DROP COLUMN photo_generation;
```

Le code précédent ignore `photo_generation` : il fonctionne sur le schéma migré (déploiement API après base, retour arrière du code possible sans toucher la base, avec la réserve que le remplacement suivant un retrait reprendrait alors la numérotation d'avant — d'où l'ordre : retirer le code avant la colonne).

## Qualification

Tests : `apps/api/test/identity-versions.integration.test.ts` (12 cas, vraie PostgreSQL 17, données synthétiques) : inter-routes dans les deux sens, route historique, deux écoles dans les deux sens, photo sans effet sur les dossiers, élève tiers non concerné, droits par champ et isolation d'école, rejeu idempotent, écritures simultanées sans 5xx, génération monotone, appareil périmé, portraits existants. Non qualifié ici : raccord iOS/web, déploiement, appareils réels.
