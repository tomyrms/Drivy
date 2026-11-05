# Restauration sans réapparition des retraits — scénario local (#68/#78/#97)

Date : 5 novembre 2026. Worktree `issues-medias-97`, tête `1778ed7d90ec12a4c7de5163ac9b343c5076684e`.
Problème distinct des correctifs média déjà verts. Aucun accès à la production, au homelab ou à un service distant.

## 1. Problème traité

Le préflight I2 (§14.4 de `../issues-deploiement-preflight-20261105/docs/implementation/deploiement-i2-preflight-20261105.md`)
prouve qu'un `pg_dump` est restaurable et que son contenu de tables correspond. Il ne prouve **pas** qu'une restauration
d'un dump antérieur ne ressuscite pas les retraits postérieurs : messages supprimés pour tout le monde, médias purgés,
appareils révoqués, membres sortis. Le contrat `medias-exploitation-contrat-20261104.md` §5.4 exige une **source
indépendante hors de la base restaurée** et une réouverture bloquée jusqu'à preuve de couverture. Cette source n'existe
pas en production : le journal `drivy.messaging_media_purge` est dans la même base et les tombstones de messages, les
révocations d'appareils et les fins de lien n'ont aucun journal indépendant.

## 2. Ce qui est livré (outillage, jamais chargé par le produit)

| Élément | Rôle |
|---|---|
| `apps/api/scripts/messaging-restore-replay.ts` | export du journal indépendant, validation, rejeu idempotent, vérification, scénario local complet |
| `apps/api/test/messaging-restore-replay.integration.test.ts` | tests PostgreSQL réels : refus des sources invalides, résurrection prouvée, rejeu, idempotence, aucune réactivation |

### 2.1 Journal indépendant exporté

Format `drivy.messaging.restore-archive/1`, écrit **hors de la base restaurée** (fichier `0600`, jamais dans le dump).
Il ne contient que des identifiants, des horodatages, des raisons et des séquences — **aucune clé, aucun IV, aucune
enveloppe, aucun octet, aucun nom, aucune légende** :

| Type d'entrée | Source | Contenu |
|---|---|---|
| `MEDIA_PURGED` | `messaging_media_purge` (séquence produit) | école, média, message porteur, raison, date, séquence produit |
| `MESSAGE_DELETED` | `messaging_message.deleted_at` | école, conversation, message, date, auteur |
| `DEVICE_REVOKED` | `messaging_device.revoked_at` | école, personne, appareil, date |
| `MEMBER_LINK_CUT` | `messaging_member_link.cut_sequence` | école, conversation, personne, lien, séquence de coupe, date |
| `GENERAL_REMOVAL` | `messaging_general_removal` | école, adhésion, personne, auteur, date |

Chaque entrée porte une séquence d'archive 1…N ; le fichier porte `archivedThrough = N`, le périmètre des écoles et
l'empreinte SHA-256 des entrées, ainsi que la séquence média maximale observée (`source.mediaPurgeThrough`) et le
nombre de purges exportées.

### 2.2 Validation : refus explicites avant tout rejeu

| Situation | Code de refus |
|---|---|
| source absente ou vide | `ARCHIVE_ABSENT` |
| source illisible ou entrée malformée | `ARCHIVE_UNREADABLE` |
| format inconnu | `ARCHIVE_FORMAT` |
| source tronquée (`archivedThrough` ≠ nombre d'entrées) | `ARCHIVE_TRUNCATED` |
| trou de séquence d'archive | `ARCHIVE_SEQUENCE_GAP` |
| empreinte des entrées divergente | `ARCHIVE_DIGEST_MISMATCH` |
| périmètre d'écoles différent de la base cible, ou entrée hors périmètre | `ARCHIVE_SCOPE_DIVERGENT` |
| séquences média incohérentes avec la source | `ARCHIVE_SOURCE_INCONSISTENT` |

**Portée honnête de l'empreinte** : elle détecte une corruption ou une troncature accidentelle. Sans signature, une
source réécrite avec une empreinte recalculée n'est pas détectée : l'authentification du journal est une décision
ouverte (§6), pas une garantie de ce lot.

### 2.3 Rejeu et vérification

Le rejeu est **transactionnel** et **idempotent** : chaque entrée applique une mise à jour gardée (`WHERE` sur l'état
non-retiré), puis une seconde exécution ne change plus rien (`applied` = 0, horodatages inchangés). Il ne réactive
jamais rien :

- média purgé : `ciphertext = NULL`, `purged_at`/`purge_reason` posés, entrée de journal réinsérée (`ON CONFLICT DO NOTHING`) ;
- message supprimé : `envelope = NULL`, `deleted_at`/auteur posés, épinglage retiré, réactions et sondage supprimés ;
- appareil révoqué : `revoked_at` posé, `device_keys = NULL`, clés à usage unique, clés de repli, file to-device et suivi supprimés ;
- fin de lien : `cut_sequence`/`cut_at` posés seulement si le lien était encore ouvert ;
- retrait du général : ligne réinsérée si absente.

Puis la vérification compte les violations **par type** (aucun identifiant dans le diagnostic) : octets purgés
présents, message non supprimé, appareil actif, lien ouvert, retrait manquant. Une seule violation rend la
restauration **non validée**.

Le scénario ne rouvre jamais la messagerie : il refuse de déclarer la restauration valide tant que validation, rejeu
et vérification n'ont pas réussi. En production, la porte de qualification doit rester fermée pendant toute la
procédure (décision opérationnelle, §6).

## 3. Scénario local exécuté (PostgreSQL réel)

Commande (Node 24 portable, conteneur jetable `drivy-t1-97-pg`, PostgreSQL 17.11, boucle locale 55497) :

```
RESTORE_SOURCE_URL=postgres://…/drivy_restore_src RESTORE_DOCKER=drivy-t1-97-pg \
  npx tsx apps/api/scripts/messaging-restore-replay.ts
```

Déroulé : base synthétique migrée et peuplée (école, moniteur, élève, formation, affectation, conversation privée,
deux messages, trois médias, deux appareils) → `pg_dump -Fc` (snapshot) → mutations postérieures (suppression pour
tout le monde via `messaging_delete_for_everyone`, annulation d'un média orphelin via `messaging_purge_media`,
révocation d'appareil, fin de lien) → export du journal → restauration du snapshot dans une base **isolée** →
constat de résurrection → validation (dont sources falsifiées) → rejeu → vérification → second rejeu → nettoyage.

Résultat réel (sortie JSON du script, exit code **0**) :

| Étape | Résultat observé |
|---|---|
| snapshot | 847 236 octets, empreinte `020b93f27902…` |
| base restaurée **avant** rejeu | 2 médias avec octets, 1 message non supprimé, 1 appareil actif, 1 lien ouvert (résurrection constatée) |
| sources falsifiées | `ARCHIVE_ABSENT`, `ARCHIVE_TRUNCATED`, `ARCHIVE_SEQUENCE_GAP`, `ARCHIVE_SCOPE_DIVERGENT`, `ARCHIVE_SOURCE_INCONSISTENT` |
| source réelle | `ACCEPTED` (5 entrées, empreinte `476f792e6a3e…`) |
| rejeu | 2 purges média, 1 message, 1 appareil, 1 lien ; 2 entrées de journal réinsérées |
| vérification | `ok: true`, 0 violation sur les 5 entrées vérifiées |
| second rejeu | 0 application, 0 entrée de journal, vérification toujours `ok` |
| nettoyage | bases source et cible supprimées, aucune ressource laissée |

Tests PostgreSQL associés (`npx vitest run test/messaging-restore-replay.integration.test.ts`) : **2 tests réussis**,
exit 0. Ils couvrent en plus le retrait du général et le parcours HTTP après rejeu : média purgé → `404 MEDIA_NOT_FOUND`,
appareil révoqué → `403 MESSAGING_DEVICE_REQUIRED`, message supprimé → `ciphertext: null` et `media.deleted: true`,
média conservé → toujours `deleted: false`. `npx tsc --noEmit` : exit 0.

## 4. Ce que ce scénario prouve — et ce qu'il ne prouve pas

Prouvé **en local, sur données synthétiques** :

- un dump antérieur ressuscite effectivement les retraits (le scénario le constate avant rejeu) ;
- une source indépendante exportée hors base permet de les rejouer sans réapparition : aucun octet purgé, aucun
  message, aucun appareil, aucun lien, aucun retrait du général ;
- le rejeu est idempotent et transactionnel, et refuse les sources absentes, tronquées, trouées ou hors périmètre ;
- le journal ne contient ni clé, ni enveloppe, ni octet de média (vérifié par sentinelles dans les tests).

Non prouvé, et non revendiqué :

- **aucun archivage durable de production** : l'export est fait à la demande par l'outillage, pas par un archiveur
  continu avec `fsync` et point d'avancement ; aucune barrière de commit n'est implémentée ;
- aucune signature ni authentification du journal (voir §2.2) ;
- aucune preuve de résidence, de rétention, de RPO/RTO, de restauration de production, ni de reprise des clés hors base ;
- les tombstones/révocations ne sont pas journalisés par le produit : le scénario les exporte depuis l'état de la base
  au moment de l'archivage. En production, cette exportation doit devenir un flux continu et fiable, ce qui reste à
  livrer (#68).

## 5. Critères actualisés

| Critère | État après ce lot |
|---|---|
| RES04 — sauvegarde puis restauration isolée avec messages et médias synthétiques | **Local : exécuté** (scénario ci-dessus, exit 0) ; **production : non exécuté** |
| RES05 — retrait après sauvegarde, restauration ancienne, non-résurrection des droits et données | **Local : mécanisme prouvé** (rejeu + vérification, 0 violation) ; **production : non fourni** (archive durable absente) |
| MED68-07/08/09 — non-résurrection après restauration | **Mécanisme local prouvé** ; reste **NON FOURNI** pour la production tant que l'archive indépendante continue, signée et supervisée n'existe pas |
| #97 — médias purgés jamais resservis après restauration | **Local : prouvé** (SQL `ciphertext = NULL`, HTTP `404`) ; production non exécuté |
| #78 — qualification | Scénario local reproductible ; aucune qualification produit, appareil ou production |

## 6. Décisions restant indispensables (aucune n'est prise ici)

1. **Support et hébergement de l'archive durable** : volume distinct ou hôte distinct, chiffré, dans le périmètre
   suisse ; fournisseur et emplacement non choisis.
2. **Archiveur continu** : lecture du journal et de l'état des tombstones, écriture append-only, `fsync`, point
   d'avancement `archived_through`, supervision des retards et des trous.
3. **Barrière de réouverture** : condition explicite (couverture prouvée de toutes les séquences émises, sans trou)
   avant de rouvrir la messagerie après restauration, et qui l'applique.
4. **Authentification du journal** : signature ou MAC, clés et rotation, pour que l'empreinte ne protège pas seulement
   des corruptions accidentelles.
5. **Durées de conservation** : tombstones de médias, entrées de journal, messages supprimés, révocations ; aucune
   durée n'est fixée par ce lot.
6. **RPO/RTO et procédure d'astreinte** : qui restaure, qui rejoue, qui vérifie, avec quelles preuves conservées.
7. **Copies hors base** : clés, coffres d'appareils, configuration ; non couvertes par le dump.

## 7. Limites du lot

- Données strictement synthétiques, base jetable locale ; aucun homelab, aucune production, aucun secret.
- Le scénario restaure dans une base isolée du même cluster et vérifie en SQL ; il ne redémarre pas l'API sur la base
  restaurée et ne prouve pas une bascule de service.
- Aucun changement produit : ni migration, ni politique de conservation, ni purge automatique, ni second journal en
  base. Aucune installation, aucun push, aucune CI.
