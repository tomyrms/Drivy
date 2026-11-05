# Restauration sans réapparition des retraits — scénario local (#68/#78/#97)

Date : 5 novembre 2026. Worktree `issues-medias-97`. Base de la livraison initiale : `1778ed7d90ec12a4c7de5163ac9b343c5076684e`
(commit `4bbad45243fc3714e232847570d72854e6a7d5cf`), puis **correction 1/2** de la revue groupée
(`sandperch/artifacts/orchestration/revue-restauration-4bbad452.md`) : commit additionnel indiqué en fin de document.
Problème distinct des correctifs média déjà verts. Aucun accès à la production, au homelab ou à un service distant.

## 1. Problème traité

Le préflight I2 (§14.4) prouve qu'un `pg_dump` est restaurable et que son contenu de tables correspond ; il ne prouve
pas qu'une restauration d'un dump antérieur ne ressuscite pas les retraits postérieurs. Le contrat
`medias-exploitation-contrat-20261104.md` §5.4 exige une source indépendante hors de la base restaurée et une
réouverture bloquée jusqu'à preuve de couverture. Cette source n'existe pas en production.

## 2. Ce qui est livré (outillage, jamais chargé par le produit)

| Élément | Rôle |
|---|---|
| `apps/api/scripts/messaging-restore-replay.ts` | export du journal indépendant, validation, rejeu idempotent, vérification, scénario local complet |
| `apps/api/test/messaging-restore-replay.integration.test.ts` | tests PostgreSQL réels : refus, résurrection, rejeu, idempotence, réservation de connexion, preuve négative et preuve positive |

### 2.1 Journal indépendant (format `drivy.messaging.restore-archive/2`)

Écrit **hors de la base restaurée** (fichier `0600`, jamais dans le dump). Il ne contient que des identifiants, des
horodatages, des raisons et des séquences — **aucune clé, aucun IV, aucune enveloppe, aucun octet, aucun nom** :

| Type | Source | Contenu |
|---|---|---|
| `MEDIA_PURGED` | `messaging_media_purge` | école, média, message porteur, raison, date, séquence produit |
| `MESSAGE_DELETED` | `messaging_message.deleted_at` | école, conversation, message, date, auteur |
| `DEVICE_REVOKED` | `messaging_device.revoked_at` | école, personne, appareil, date |
| `MEMBER_LINK_CUT` | `messaging_member_link.cut_sequence` | école, conversation, personne, lien, séquence de coupe, date |
| `GENERAL_REMOVAL` | `messaging_general_removal` | école, adhésion, personne, auteur, date |
| `ASSIGNMENT_ENDED` | `instructor_assignment.valid_until` | école, affectation, formation, adhésion et personnes liées, `valid_from`/`valid_until`, version d'affectation, version et époque d'accès de l'adhésion observées |

`ASSIGNMENT_ENDED` est la **variante fermée** autorisée par l'arbitrage C3 : elle ne couvre que la fin d'affectation
réellement constatée. Les autres causes (fin de formation, changement de rôles, retrait d'adhésion) ne sont **pas**
couvertes et ne sont pas inventées ; le retrait du général garde son entrée distincte.

### 2.2 Validation : refus explicites avant tout rejeu

| Situation | Code |
|---|---|
| source absente/vide | `ARCHIVE_ABSENT` |
| source illisible, entrée malformée, champ consommé invalide (UUID, bornes, raison, identités liées, version) | `ARCHIVE_UNREADABLE` |
| format inconnu | `ARCHIVE_FORMAT` |
| source tronquée (`archivedThrough` ≠ entrées) | `ARCHIVE_TRUNCATED` |
| trou dans la séquence **d'archive** | `ARCHIVE_SEQUENCE_GAP` |
| entrée en double (même identité) | `ARCHIVE_DUPLICATE` |
| empreinte divergente | `ARCHIVE_DIGEST_MISMATCH` |
| périmètre d'écoles différent, entrée hors périmètre | `ARCHIVE_SCOPE_DIVERGENT` |
| couverture média incohérente (zéro purge avec borne non nulle, compte ≠ export, séquence max ≠ borne) | `ARCHIVE_SOURCE_INCONSISTENT` |

La séquence **PostgreSQL** peut avoir des trous légitimes (rollbacks) : seule la séquence d'archive est exigée
contiguë, et la couverture média est comparée au journal exporté, pas à une contiguïté produit.
`replayArchive` revalide la forme **avant toute écriture** ; le scénario rejoue l'objet validé contre la cible
(`validateArchive`), jamais l'objet brut relu.

### 2.3 Rejeu, vérification et décision C3

Rejeu **transactionnel sur une connexion réservée** (`ReservedConnection` = `Client`/`PoolClient`, jamais un `Pool`) et
**idempotent** : chaque entrée applique une mise à jour gardée, puis une seconde exécution ne change plus rien.
L'export lit un instantané `REPEATABLE READ`.

- média purgé : `ciphertext = NULL`, `purged_at`/`purge_reason`, journal réinséré ;
- message supprimé : `envelope = NULL`, `deleted_at`/auteur, épinglage, réactions et sondage retirés ;
- appareil révoqué : `revoked_at`, `device_keys = NULL`, clés/file/suivi supprimés ;
- fin de lien : `cut_sequence`/`cut_at` seulement si le lien est encore ouvert ;
- retrait du général : réinséré si l'adhésion existe dans la cible (absence légitime sinon) ;
- **fin d'affectation** : `valid_until` posé (ou conservé s'il est déjà antérieur), `version = GREATEST(version, observée)`,
  et `version`/`access_epoch` de l'adhésion du moniteur portés aux valeurs **observées** de façon monotone — jamais un
  incrément aveugle, jamais un changement de rôle/grant/statut. Une cible contradictoire (autre `valid_from`, version
  plus récente, `valid_until` postérieur) est **refusée** (`ASSIGNMENT_STATE_AMBIGUOUS`) sans écriture, plutôt
  qu'écrasée.

**Preuve C3 et décision.** Le rejeu de la seule coupe laisse l'éligibilité privée active : `messaging_sync_links`
recrée un lien ouvert (nouveau numéro) pour une personne encore éligible. Le vérificateur contrôle désormais **tout**
lien ouvert de la personne coupée, pas seulement l'ancien numéro, et la paire d'éligibilité de chaque fin d'affectation.
Deux preuves sont conservées :

- **négative** (test) : coupe seule, sans cause ⇒ après synchronisation, le vérificateur signale
  `MEMBER_LINK_CUT:1`, la réouverture est refusée, et un appareil distinct actif permet de constater la réactivation ;
- **positive** (test + scénario `pg_restore` réel) : fin d'affectation acquise par la route métier `END_ASSIGNMENT`,
  puis export/rejeu avant synchronisation ; synchronisation répétée, aucun lien rouvert, aucune plage postérieure,
  écriture refusée, second rejeu sans effet, versions/époques stables.

## 3. Scénario local exécuté (PostgreSQL réel)

Commande (Node 24 portable, conteneur jetable `drivy-t1-97-pg`, PostgreSQL 17.11, boucle locale 55497) :

```
RESTORE_SOURCE_URL=postgres://…@127.0.0.1:55497/postgres RESTORE_DOCKER=drivy-t1-97-pg \
  npx tsx apps/api/scripts/messaging-restore-replay.ts
```

Déroulé : bases créées à noms uniques (sentinelle, source, cible) après refus de collision et contrôle d'identité de
cluster → base synthétique migrée/peuplée → `pg_dump -Fc` → mutations postérieures (suppression pour tout le monde,
annulation de média, révocation d'appareil, **fin d'affectation par `END_ASSIGNMENT`**, synchronisation produit) →
export → `pg_restore` dans une base **isolée** → constat de résurrection → validation (dont sources falsifiées) →
rejeu → synchronisation répétée → vérification → second rejeu → nettoyage des seules bases créées.

Résultat réel (`artifacts/restauration-correction1/scenario-run6.log`, **exit 0**) :

| Étape | Résultat observé |
|---|---|
| cluster | identité identique entre la connexion SQL et le conteneur (`clusterChecked: true`) |
| bases | 3 créées, 3 supprimées (sentinelle comprise) ; aucune base préexistante touchée |
| snapshot | 1 001 434 octets, empreinte `be00a6a7bd35…` |
| base restaurée **avant** rejeu | 2 médias avec octets, 1 message non supprimé, 1 appareil actif, 1 lien ouvert |
| sources falsifiées | `ARCHIVE_ABSENT`, `TRUNCATED`, `SEQUENCE_GAP`, `SCOPE_DIVERGENT`, `SOURCE_INCONSISTENT`, `UNREADABLE` (fin de lien sans conversation) |
| rejeu | 2 purges média, 1 message, 1 appareil, 2 fins de lien, 1 fin d'affectation ; 2 entrées de journal |
| synchronisation répétée | `afterSync.ok: true`, 0 violation |
| second rejeu | 0 application, `versionsStable: true` |
| accès après rejeu | `openLinks: 0`, `canWrite: false`, `readableLast: false`, `pairEligible: false` |
| décision | `reopenAllowed: true` |

Tests PostgreSQL (`npx vitest run test/messaging-restore-replay.integration.test.ts`) : **7 tests réussis**, exit 0
(`artifacts/restauration-correction1/tests.log`). `npx tsc --noEmit` : exit 0. Ils couvrent en plus le rollback complet
après une erreur au milieu sous concurrence, la preuve par `pg_blocking_pids` que le rejeu s'exécute sur la connexion
réservée, la preuve négative de réactivation, la preuve positive avec appareil distinct et l'ambiguïté de cible.

**Distinction des preuves** : le test simule la restauration en rétablissant les valeurs du snapshot dans la base de
test (pas de `pg_dump`) ; le `pg_restore` réel n'existe que dans le scénario ci-dessus.

## 4. Ce que ce scénario prouve — et ce qu'il ne prouve pas

Prouvé **en local, sur données synthétiques** : un dump antérieur ressuscite les retraits (constaté avant rejeu) ; la
source indépendante permet de les rejouer sans réapparition (aucun octet purgé, message, appareil, lien ou retrait du
général, et fin d'affectation rejouée) ; la réouverture est refusée si la couverture manque ; le rejeu est idempotent,
transactionnel, validé avant écriture, et refuse les sources absentes/tronquées/trouées/dupliquées/divergentes/
incohérentes ; le journal ne contient ni clé, ni enveloppe, ni octet (sentinelles testées).

Non prouvé, non revendiqué : **aucun archivage durable de production** (l'export est fait à la demande, sans archiveur
continu, sans `fsync`, sans point d'avancement ni barrière de réouverture) ; **aucune sauvegarde chiffrée** (le
`pg_dump -Fc` est compressé, pas chiffré) ; aucune signature/authentification du journal ; aucune preuve de résidence,
rétention, RPO/RTO ou restauration de production ; les causes de retrait autres que la fin d'affectation et le retrait
du général ne sont pas couvertes.

## 5. Critères actualisés

| Critère | État |
|---|---|
| RES04 — sauvegarde chiffrée puis restauration isolée | **Sauvegarde/restauration synthétique exécutée** (exit 0) ; **critère chiffré NON QUALIFIÉ** |
| RES05 — non-résurrection des droits et données après restauration | **Qualifié pour le scénario couvert** (médias, messages, appareil, fin de lien, fin d'affectation, retrait du général ; 0 violation, réouverture autorisée) ; **non fourni** pour les autres causes et pour la production |
| MED68-07/08/09 | Mécanisme local prouvé pour le scénario couvert ; **NON FOURNI** en production (archive indépendante continue, signée, supervisée absente) |
| #97 — médias purgés jamais resservis après restauration | **Local : prouvé** (SQL `ciphertext = NULL`, HTTP `404`) ; production non exécuté |
| #78 — qualification | Scénario local reproductible ; aucune qualification produit, appareil ou production |

## 6. Décisions restant indispensables (aucune n'est prise ici)

1. Support/hébergement de l'archive durable (volume ou hôte distinct, chiffré, périmètre suisse) ; fournisseur non choisi.
2. Archiveur continu : lecture du journal et des tombstones, écriture append-only, `fsync`, `archived_through`, supervision.
3. Barrière de réouverture : preuve de couverture complète avant de rouvrir, et responsable de son application.
4. Authentification du journal (signature/MAC, clés, rotation).
5. Durées de conservation (tombstones, journal, messages supprimés, révocations) ; aucune durée fixée.
6. RPO/RTO, procédure d'astreinte, preuves conservées.
7. Couverture des autres causes de fin de droit (formation, rôles, adhésion) : variante non couverte à ce jour.
8. Copies hors base (clés, coffres, configuration), non couvertes par le dump.

## 7. Limites du lot

- Données strictement synthétiques, base jetable locale ; aucun homelab, aucune production, aucun secret.
- Le scénario restaure dans une base isolée du même cluster et vérifie en SQL ; il ne redémarre pas l'API sur la base
  restaurée et ne prouve pas une bascule de service.
- Aucun changement produit : ni migration, ni politique de conservation, ni purge automatique, ni second journal en base.
