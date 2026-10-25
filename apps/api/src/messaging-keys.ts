import type { PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { ApiError, forbidden, notFound } from './errors.js';
import type { MessagingActor } from './messaging.js';

/**
 * Relais de clés Matrix (Olm/Megolm) sans homeserver. Les objets sont des JSON Matrix publics ou chiffrés
 * produits par matrix-sdk-crypto ; le serveur ne lit ni texte ni clé privée, il vérifie seulement
 * l'identité déclarée, les droits scolaires et les bornes.
 */
export interface KeyActor extends MessagingActor { deviceId: string }
type Json = Record<string, unknown>;

export const deviceIdPattern = /^[A-Z0-9]{10,32}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const keyIdPattern = /^[A-Za-z0-9_.-]{1,64}:[A-Za-z0-9+/=_-]{1,64}$/;
const algorithmPattern = /^[A-Za-z0-9_.-]{1,64}$/;
export const limits = { activeDevicesPerPerson: 10, oneTimeKeysPerUpload: 100, oneTimeKeysPerDevice: 200, queryUsers: 5000, claimDevices: 500,
  toDeviceRecipients: 500, toDeviceContentBytes: 16384, syncEvents: 100, backupSessionsPerPut: 500, backupSessionBytes: 8192 } as const;

const invalid = (message = 'Requête de clés invalide.') => new ApiError(400, 'INVALID_REQUEST', message);
const isObject = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value);
const bytes = (value: unknown) => Buffer.byteLength(JSON.stringify(value), 'utf8');
export const userId = (personId: string) => `@${personId.toLowerCase()}:drivy`;
export function personOf(user: string): string | null {
  const match = /^@([0-9a-f-]{36}):drivy$/.exec(user);
  return match && uuidPattern.test(match[1]!) ? match[1]! : null;
}
function object(value: unknown, maxBytes: number): Json {
  if (!isObject(value) || bytes(value) > maxBytes) throw invalid();
  return value;
}
function safeId(value: string | number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  return parsed;
}
/** Verrou par appareil destinataire : un envoi to-device ne peut pas être acquitté avant d'avoir été vu. */
async function lockQueues(db: PoolClient, schoolId: string, targets: { personId: string; deviceId: string }[]) {
  const keys = [...new Set(targets.map(t => `${schoolId}|${t.personId}|${t.deviceId}`))].sort();
  for (const key of keys) await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`messaging.todevice|${key}`]);
}
/** Ordre des changements de listes d'appareils : les écrivains prennent le verrou exclusif, le sync le partagé. */
async function noteDeviceListChange(db: PoolClient, actor: KeyActor) {
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`messaging.devicelist|${actor.schoolId}`]);
  await db.query('INSERT INTO drivy.messaging_device_list_change(school_id,person_id) VALUES($1,$2)', [actor.schoolId, actor.personId]);
}

/** Enregistre l'appareil au premier appel (lié à la session OIDC du contexte), refuse un appareil révoqué ou au-delà du plafond. */
export async function bindDevice(db: PoolClient, actor: KeyActor): Promise<void> {
  if (!deviceIdPattern.test(actor.deviceId)) throw forbidden();
  const bound = await db.query<{ state: string }>('SELECT drivy.messaging_bind_device($1,$2,$3) AS state',
    [actor.schoolId, actor.deviceId, limits.activeDevicesPerPerson]);
  const state = bound.rows[0]?.state;
  if (state === 'LIMIT') throw new ApiError(409, 'DEVICE_LIMIT_REACHED',
    `Trop d’appareils actifs (${limits.activeDevicesPerPerson} au plus). Révoquez un ancien appareil.`);
  if (state !== 'ACTIVE') throw forbidden();
}

async function oneTimeKeyCounts(db: PoolClient, actor: KeyActor): Promise<Record<string, number>> {
  const rows = await db.query<{ algorithm: string; count: number }>(`SELECT algorithm,count(*)::int AS count FROM drivy.messaging_one_time_key
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3 GROUP BY algorithm`, [actor.schoolId, actor.personId, actor.deviceId]);
  return Object.fromEntries(rows.rows.map(row => [row.algorithm, row.count]));
}

export async function uploadKeys(db: PoolClient, actor: KeyActor, body: unknown) {
  const raw = object(body, 65536);
  if (Object.keys(raw).some(key => !['device_keys', 'one_time_keys', 'fallback_keys'].includes(key))) throw invalid();
  // La liaison FFI de matrix-sdk-crypto (iOS) envoie toujours les trois champs : `device_keys` vaut null
  // dès que le compte est publié (json!({"device_keys": Option<..>, ...})). null signifie « rien à publier ».
  const input = Object.fromEntries(Object.entries(raw).filter(([, value]) => value !== null)) as Json;
  if (input.device_keys !== undefined) {
    const keys = object(input.device_keys, 8192);
    if (keys.user_id !== userId(actor.personId) || keys.device_id !== actor.deviceId || !Array.isArray(keys.algorithms) || !isObject(keys.keys))
      throw invalid('Clés d’appareil invalides.');
    const current = await db.query<{ keys: Json | null }>(`SELECT device_keys AS keys FROM drivy.messaging_device
      WHERE school_id=$1 AND person_id=$2 AND device_id=$3`, [actor.schoolId, actor.personId, actor.deviceId]);
    const previous = current.rows[0]?.keys;
    // Les clés d'identité d'un appareil ne changent jamais : un remplacement serait une usurpation.
    if (previous && JSON.stringify(previous.keys) !== JSON.stringify(keys.keys)) throw new ApiError(409, 'DEVICE_KEYS_CONFLICT', 'Clés d’appareil déjà publiées.');
    if (!previous || JSON.stringify(previous) !== JSON.stringify(keys)) {
      await db.query(`UPDATE drivy.messaging_device SET device_keys=$4 WHERE school_id=$1 AND person_id=$2 AND device_id=$3`,
        [actor.schoolId, actor.personId, actor.deviceId, keys]);
      await noteDeviceListChange(db, actor);
    }
  }
  if (input.one_time_keys !== undefined) {
    const keys = object(input.one_time_keys, 65536);
    const entries = Object.entries(keys);
    if (entries.length > limits.oneTimeKeysPerUpload) throw invalid('Trop de clés à usage unique.');
    for (const [keyId, key] of entries) {
      if (!keyIdPattern.test(keyId) || !(isObject(key) || typeof key === 'string') || bytes(key) > 2048) throw invalid();
      // Idempotent pour un renvoi identique ; une clé différente sous le même identifiant est refusée.
      const inserted = await db.query(`INSERT INTO drivy.messaging_one_time_key(school_id,person_id,device_id,key_id,key)
        VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, [actor.schoolId, actor.personId, actor.deviceId, keyId, JSON.stringify(key)]);
      if (inserted.rowCount === 0) {
        const same = await db.query<{ same: boolean }>(`SELECT key=$5::jsonb AS same FROM drivy.messaging_one_time_key
          WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND key_id=$4`, [actor.schoolId, actor.personId, actor.deviceId, keyId, JSON.stringify(key)]);
        if (same.rows[0] && !same.rows[0].same) throw new ApiError(409, 'ONE_TIME_KEY_CONFLICT', 'Clé à usage unique déjà publiée.');
      }
    }
    const total = await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_one_time_key
      WHERE school_id=$1 AND person_id=$2 AND device_id=$3`, [actor.schoolId, actor.personId, actor.deviceId]);
    if ((total.rows[0]?.count ?? 0) > limits.oneTimeKeysPerDevice) throw invalid('Trop de clés à usage unique.');
  }
  if (input.fallback_keys !== undefined) {
    const keys = object(input.fallback_keys, 8192);
    const entries = Object.entries(keys);
    if (entries.length > 4) throw invalid();
    for (const [keyId, key] of entries) {
      const algorithm = keyId.split(':')[0]!;
      if (!keyIdPattern.test(keyId) || !algorithmPattern.test(algorithm) || !isObject(key) || bytes(key) > 2048) throw invalid();
      await db.query(`INSERT INTO drivy.messaging_fallback_key(school_id,person_id,device_id,algorithm,key_id,key)
        VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT (school_id,person_id,device_id,algorithm) DO UPDATE
        SET key_id=EXCLUDED.key_id,key=EXCLUDED.key,used=CASE WHEN drivy.messaging_fallback_key.key_id=EXCLUDED.key_id
          THEN drivy.messaging_fallback_key.used ELSE false END,updated_at=now()`,
        [actor.schoolId, actor.personId, actor.deviceId, algorithm, keyId, key]);
    }
  }
  return { one_time_key_counts: await oneTimeKeyCounts(db, actor) };
}

/** Personnes demandées et autorisées ; les autres sont omises sans dire si elles existent. */
async function authorizedPeople(db: PoolClient, actor: KeyActor, users: string[]): Promise<Map<string, string>> {
  const people = new Map<string, string>();
  for (const user of users) { const person = personOf(user); if (person) people.set(person, user); }
  if (people.size === 0) return people;
  const allowed = await db.query<{ personId: string }>(`SELECT p.person_id AS "personId" FROM unnest($2::uuid[]) AS p(person_id)
    WHERE drivy.messaging_key_peer($1,p.person_id)`, [actor.schoolId, [...people.keys()]]);
  const ok = new Set(allowed.rows.map(row => row.personId.toLowerCase()));
  return new Map([...people].filter(([person]) => ok.has(person)));
}

export async function queryKeys(db: PoolClient, actor: KeyActor, body: unknown) {
  const input = object(body, 262144);
  const requested = input.device_keys;
  if (!isObject(requested) || Object.keys(requested).length > limits.queryUsers) throw invalid();
  for (const devices of Object.values(requested)) if (!Array.isArray(devices) || devices.length > 100 || devices.some(d => typeof d !== 'string')) throw invalid();
  const people = await authorizedPeople(db, actor, Object.keys(requested));
  const result = { device_keys: {} as Record<string, Record<string, Json>>, failures: {},
    master_keys: {} as Record<string, Json>, self_signing_keys: {} as Record<string, Json>, user_signing_keys: {} as Record<string, Json> };
  if (people.size === 0) return result;
  const devices = await db.query<{ personId: string; deviceId: string; keys: Json }>(`SELECT person_id AS "personId",device_id AS "deviceId",device_keys AS keys
    FROM drivy.messaging_device WHERE school_id=$1 AND person_id=ANY($2::uuid[]) AND revoked_at IS NULL AND device_keys IS NOT NULL
    ORDER BY person_id,device_id`, [actor.schoolId, [...people.keys()]]);
  for (const row of devices.rows) {
    const user = people.get(row.personId.toLowerCase())!;
    const wanted = requested[user] as string[];
    if (wanted.length > 0 && !wanted.includes(row.deviceId)) continue;
    (result.device_keys[user] ??= {})[row.deviceId] = row.keys;
  }
  for (const user of people.values()) result.device_keys[user] ??= {};
  const signing = await db.query<{ personId: string; usage: string; key: Json }>(`SELECT person_id AS "personId",key_usage AS usage,key
    FROM drivy.messaging_cross_signing WHERE school_id=$1 AND person_id=ANY($2::uuid[])`, [actor.schoolId, [...people.keys()]]);
  for (const row of signing.rows) {
    const user = people.get(row.personId.toLowerCase())!;
    if (row.usage === 'master') result.master_keys[user] = row.key;
    else if (row.usage === 'self_signing') result.self_signing_keys[user] = row.key;
    else if (row.personId.toLowerCase() === actor.personId.toLowerCase()) result.user_signing_keys[user] = row.key;
  }
  return result;
}

export async function claimKeys(db: PoolClient, actor: KeyActor, body: unknown) {
  const input = object(body, 65536);
  const requested = input.one_time_keys;
  if (!isObject(requested)) throw invalid();
  const wanted: { user: string; deviceId: string; algorithm: string }[] = [];
  for (const [user, devices] of Object.entries(requested)) {
    if (!isObject(devices)) throw invalid();
    for (const [deviceId, algorithm] of Object.entries(devices)) {
      if (!deviceIdPattern.test(deviceId) || typeof algorithm !== 'string' || !algorithmPattern.test(algorithm)) throw invalid();
      wanted.push({ user, deviceId, algorithm });
    }
  }
  if (wanted.length > limits.claimDevices) throw invalid();
  const people = await authorizedPeople(db, actor, wanted.map(w => w.user));
  const result: Record<string, Record<string, Record<string, unknown>>> = {};
  for (const target of wanted) {
    const personId = personOf(target.user);
    if (!personId || !people.has(personId)) continue;
    // Une clé à usage unique est supprimée dans la même instruction qui la sélectionne : jamais distribuée deux fois.
    const claimed = await db.query<{ keyId: string; key: unknown }>(`SELECT key_id AS "keyId",key
      FROM drivy.messaging_claim_one_time_key($1,$2,$3,$4)`, [actor.schoolId, personId, target.deviceId, target.algorithm]);
    let found = claimed.rows[0];
    if (!found) {
      const fallback = await db.query<{ keyId: string; key: unknown }>(`SELECT key_id AS "keyId",key
        FROM drivy.messaging_use_fallback_key($1,$2,$3,$4)`, [actor.schoolId, personId, target.deviceId, target.algorithm]);
      found = fallback.rows[0];
    }
    if (found) ((result[target.user] ??= {})[target.deviceId] ??= {})[found.keyId] = found.key;
  }
  return { one_time_keys: result, failures: {} };
}

export async function sendToDevice(db: PoolClient, actor: KeyActor, eventType: string, txnId: string, body: unknown) {
  const input = object(body, 262144);
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(eventType) || !/^[A-Za-z0-9._~-]{1,64}$/.test(txnId)) throw invalid();
  if (!isObject(input.messages) || Object.keys(input).length !== 1) throw invalid();
  const fingerprint = createHash('sha256').update(JSON.stringify([eventType, input.messages])).digest('hex');
  // Deux envois concurrents du même txnId : le second attend le premier puis rejoue sa réponse (pas de violation d'unicité).
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
    [`messaging.txn|${actor.schoolId}|${actor.personId}|${actor.deviceId}|${txnId}`]);
  const replay = await db.query<{ fingerprint: string }>(`SELECT fingerprint FROM drivy.messaging_to_device_txn
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND txn_id=$4`, [actor.schoolId, actor.personId, actor.deviceId, txnId]);
  if (replay.rows[0]) {
    if (replay.rows[0].fingerprint !== fingerprint) throw new ApiError(409, 'TRANSACTION_CONFLICT', 'Transaction déjà utilisée.');
    return {};
  }
  const messages: { personId: string; device: string; content: Json }[] = [];
  for (const [user, devices] of Object.entries(input.messages)) {
    if (!isObject(devices)) throw invalid();
    for (const [device, content] of Object.entries(devices)) {
      if ((device !== '*' && !deviceIdPattern.test(device)) || !isObject(content) || bytes(content) > limits.toDeviceContentBytes) throw invalid();
      const personId = personOf(user);
      if (personId) messages.push({ personId, device, content });
    }
  }
  if (messages.length > limits.toDeviceRecipients) throw invalid();
  const people = await authorizedPeople(db, actor, [...new Set(messages.map(m => userId(m.personId)))]);
  const targets: { personId: string; deviceId: string; content: Json }[] = [];
  for (const message of messages.filter(m => people.has(m.personId))) {
    const devices = await db.query<{ deviceId: string }>(`SELECT device_id AS "deviceId" FROM drivy.messaging_device
      WHERE school_id=$1 AND person_id=$2 AND revoked_at IS NULL AND ($3='*' OR device_id=$3)`, [actor.schoolId, message.personId, message.device]);
    for (const device of devices.rows) targets.push({ personId: message.personId, deviceId: device.deviceId, content: message.content });
  }
  if (targets.length > limits.toDeviceRecipients) throw invalid();
  await lockQueues(db, actor.schoolId, targets);
  for (const target of targets) {
    await db.query(`INSERT INTO drivy.messaging_to_device(school_id,recipient_person_id,recipient_device_id,sender_person_id,sender_device_id,event_type,content)
      VALUES($1,$2,$3,$4,$5,$6,$7)`, [actor.schoolId, target.personId, target.deviceId, actor.personId, actor.deviceId, eventType, target.content]);
  }
  await db.query(`INSERT INTO drivy.messaging_to_device_txn(school_id,person_id,device_id,txn_id,fingerprint) VALUES($1,$2,$3,$4,$5)`,
    [actor.schoolId, actor.personId, actor.deviceId, txnId, fingerprint]);
  return {};
}

export function parseSince(since: string | undefined): { toDevice: number; deviceList: number } | null {
  if (since === undefined) return null;
  const match = /^t([0-9]{1,15})_d([0-9]{1,15})$/.exec(since);
  if (!match) throw invalid('Jeton de synchronisation invalide.');
  return { toDevice: Number(match[1]), deviceList: Number(match[2]) };
}

/** Le passage de `since` acquitte les messages to-device livrés au sync précédent (sémantique Matrix). */
export async function sync(db: PoolClient, actor: KeyActor, since: string | undefined) {
  const position = parseSince(since);
  await lockQueues(db, actor.schoolId, [{ personId: actor.personId, deviceId: actor.deviceId }]);
  await db.query('SELECT pg_advisory_xact_lock_shared(hashtextextended($1,0))', [`messaging.devicelist|${actor.schoolId}`]);
  if (position) await db.query(`DELETE FROM drivy.messaging_to_device WHERE school_id=$1 AND recipient_person_id=$2
    AND recipient_device_id=$3 AND id<=$4`, [actor.schoolId, actor.personId, actor.deviceId, position.toDevice]);
  const events = await db.query<{ id: string; type: string; sender: string; content: Json }>(`SELECT id,event_type AS type,
    sender_person_id AS sender,content FROM drivy.messaging_to_device WHERE school_id=$1 AND recipient_person_id=$2 AND recipient_device_id=$3
    AND id>$4 ORDER BY id LIMIT $5`, [actor.schoolId, actor.personId, actor.deviceId, position?.toDevice ?? 0, limits.syncEvents]);
  const lastChange = await db.query<{ id: string }>('SELECT COALESCE(max(id),0) AS id FROM drivy.messaging_device_list_change WHERE school_id=$1', [actor.schoolId]);
  const deviceListPosition = safeId(lastChange.rows[0]?.id ?? 0);
  const peers = await db.query<{ personId: string }>('SELECT person_id AS "personId" FROM drivy.messaging_key_peers($1) LIMIT 10001', [actor.schoolId]);
  if (peers.rows.length > 10000) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  const current = new Set(peers.rows.map(row => row.personId.toLowerCase()));
  const device = await db.query<{ tracked: string[] }>(`SELECT tracked_person_ids AS tracked FROM drivy.messaging_device_tracking
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3`, [actor.schoolId, actor.personId, actor.deviceId]);
  const left = position ? (device.rows[0]?.tracked ?? []).map(p => p.toLowerCase()).filter(p => !current.has(p)) : [];
  let changed: string[] = [];
  if (position) {
    const rows = await db.query<{ personId: string }>(`SELECT DISTINCT c.person_id AS "personId" FROM drivy.messaging_device_list_change c
      WHERE c.school_id=$1 AND c.id>$2 AND c.id<=$3`, [actor.schoolId, position.deviceList, deviceListPosition]);
    changed = rows.rows.map(row => row.personId.toLowerCase()).filter(p => current.has(p));
    // Une personne qui redevient pair doit être relue : ses appareils ont pu changer pendant l'absence.
    const before = new Set((device.rows[0]?.tracked ?? []).map(p => p.toLowerCase()));
    for (const person of current) if (!before.has(person) && !changed.includes(person)) changed.push(person);
  }
  await db.query(`UPDATE drivy.messaging_device_tracking SET tracked_person_ids=$4::uuid[] WHERE school_id=$1 AND person_id=$2 AND device_id=$3`,
    [actor.schoolId, actor.personId, actor.deviceId, [...current]]);
  const lastEvent = events.rows.at(-1);
  const fallback = await db.query<{ algorithm: string }>(`SELECT algorithm FROM drivy.messaging_fallback_key
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND NOT used ORDER BY algorithm`, [actor.schoolId, actor.personId, actor.deviceId]);
  return {
    next_batch: `t${lastEvent ? safeId(lastEvent.id) : position?.toDevice ?? 0}_d${deviceListPosition}`,
    to_device: { events: events.rows.map(row => ({ type: row.type, sender: userId(row.sender), content: row.content })) },
    device_lists: { changed: changed.sort().map(userId), left: left.sort().map(userId) },
    device_one_time_keys_count: await oneTimeKeyCounts(db, actor),
    device_unused_fallback_key_types: fallback.rows.map(row => row.algorithm),
  };
}

export async function uploadDeviceSigning(db: PoolClient, actor: KeyActor, body: unknown) {
  const input = object(body, 32768);
  const usages: Record<string, string> = { master_key: 'master', self_signing_key: 'self_signing', user_signing_key: 'user_signing' };
  if (Object.keys(input).some(key => !(key in usages))) throw invalid();
  const existing = await db.query<{ usage: string }>(`SELECT key_usage AS usage FROM drivy.messaging_cross_signing
    WHERE school_id=$1 AND person_id=$2 AND key_usage='master'`, [actor.schoolId, actor.personId]);
  // Sans authentification interactive, une clé maîtresse existante n'est jamais remplacée.
  if (existing.rows[0] && input.master_key !== undefined) throw new ApiError(409, 'CROSS_SIGNING_CONFLICT', 'Signature croisée déjà configurée.');
  for (const [field, usage] of Object.entries(usages)) {
    if (input[field] === undefined) continue;
    const key = object(input[field], 8192);
    if (key.user_id !== userId(actor.personId) || !Array.isArray(key.usage) || !key.usage.includes(usage) || !isObject(key.keys)) throw invalid();
    await db.query(`INSERT INTO drivy.messaging_cross_signing(school_id,person_id,key_usage,key) VALUES($1,$2,$3,$4)
      ON CONFLICT (school_id,person_id,key_usage) DO UPDATE SET key=EXCLUDED.key,updated_at=now()`, [actor.schoolId, actor.personId, usage, key]);
  }
  await noteDeviceListChange(db, actor);
  return {};
}

function mergeSignatures(target: Json, incoming: Json): Json {
  const signatures = isObject(target.signatures) ? { ...target.signatures } : {};
  if (isObject(incoming.signatures)) for (const [signer, values] of Object.entries(incoming.signatures)) {
    if (!isObject(values)) throw invalid();
    signatures[signer] = { ...(isObject(signatures[signer]) ? signatures[signer] : {}), ...values };
  }
  return { ...target, signatures };
}

/** Seules ses propres clés reçoivent des signatures ; les autres personnes sont renvoyées en échec. */
export async function uploadSignatures(db: PoolClient, actor: KeyActor, body: unknown) {
  const input = object(body, 65536);
  const failures: Record<string, Record<string, Json>> = {};
  let changed = false;
  for (const [user, keys] of Object.entries(input)) {
    if (!isObject(keys)) throw invalid();
    for (const [keyId, signed] of Object.entries(keys)) {
      const fail = () => { (failures[user] ??= {})[keyId] = { errcode: 'M_FORBIDDEN', error: 'Signature refusée.' }; };
      if (user !== userId(actor.personId) || !isObject(signed) || bytes(signed) > 8192) { fail(); continue; }
      const device = await db.query<{ keys: Json | null }>(`SELECT device_keys AS keys FROM drivy.messaging_device
        WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND revoked_at IS NULL FOR UPDATE`, [actor.schoolId, actor.personId, keyId]);
      if (device.rows[0]?.keys) {
        await db.query(`UPDATE drivy.messaging_device SET device_keys=$4 WHERE school_id=$1 AND person_id=$2 AND device_id=$3`,
          [actor.schoolId, actor.personId, keyId, mergeSignatures(device.rows[0].keys, signed)]);
        changed = true; continue;
      }
      const cross = await db.query<{ usage: string; key: Json }>(`SELECT key_usage AS usage,key FROM drivy.messaging_cross_signing
        WHERE school_id=$1 AND person_id=$2 FOR UPDATE`, [actor.schoolId, actor.personId]);
      const match = cross.rows.find(row => isObject(row.key.keys) && Object.values(row.key.keys).includes(keyId));
      if (!match) { fail(); continue; }
      await db.query(`UPDATE drivy.messaging_cross_signing SET key=$4,updated_at=now() WHERE school_id=$1 AND person_id=$2 AND key_usage=$3`,
        [actor.schoolId, actor.personId, match.usage, mergeSignatures(match.key, signed)]);
      changed = true;
    }
  }
  if (changed) await noteDeviceListChange(db, actor);
  return { failures };
}

export async function listOwnDevices(db: PoolClient, actor: KeyActor) {
  const rows = await db.query<{ deviceId: string; createdAt: string }>(`SELECT device_id AS "deviceId",created_at AS "createdAt"
    FROM drivy.messaging_device WHERE school_id=$1 AND person_id=$2 AND revoked_at IS NULL ORDER BY device_id`, [actor.schoolId, actor.personId]);
  return { devices: rows.rows.map(row => ({ ...row, isCurrent: row.deviceId === actor.deviceId })) };
}

/** Révocation : l'appareil ne peut plus appeler le relais, ses clés publiques et sa file disparaissent. Idempotent. */
export async function revokeDevice(db: PoolClient, actor: KeyActor, deviceId: string) {
  if (!deviceIdPattern.test(deviceId)) throw notFound();
  const row = await db.query<{ revoked: boolean }>(`SELECT revoked_at IS NOT NULL AS revoked FROM drivy.messaging_device
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3 FOR UPDATE`, [actor.schoolId, actor.personId, deviceId]);
  if (!row.rows[0]) throw notFound();
  if (row.rows[0].revoked) return { deviceId, revoked: true };
  await db.query(`UPDATE drivy.messaging_device SET revoked_at=now(),device_keys=NULL WHERE school_id=$1 AND person_id=$2 AND device_id=$3`,
    [actor.schoolId, actor.personId, deviceId]);
  await db.query(`UPDATE drivy.messaging_device_tracking SET tracked_person_ids='{}' WHERE school_id=$1 AND person_id=$2 AND device_id=$3`,
    [actor.schoolId, actor.personId, deviceId]);
  for (const table of ['messaging_one_time_key', 'messaging_fallback_key', 'messaging_to_device_txn'])
    await db.query(`DELETE FROM drivy.${table} WHERE school_id=$1 AND person_id=$2 AND device_id=$3`, [actor.schoolId, actor.personId, deviceId]);
  await lockQueues(db, actor.schoolId, [{ personId: actor.personId, deviceId }]);
  await db.query(`DELETE FROM drivy.messaging_to_device WHERE school_id=$1 AND recipient_person_id=$2 AND recipient_device_id=$3`,
    [actor.schoolId, actor.personId, deviceId]);
  await noteDeviceListChange(db, actor);
  return { deviceId, revoked: true };
}

const backupConflict = () => new ApiError(409, 'BACKUP_VERSION_CONFLICT', 'La sauvegarde a changé de version.');
async function currentBackup(db: PoolClient, actor: KeyActor, lock: boolean) {
  const rows = await db.query<{ version: string; algorithm: string; authData: Json; etag: string }>(`SELECT version,algorithm,
    auth_data AS "authData",etag FROM drivy.messaging_key_backup WHERE school_id=$1 AND person_id=$2 AND current
    ${lock ? 'FOR UPDATE' : ''}`, [actor.schoolId, actor.personId]);
  return rows.rows[0];
}
function parseVersion(version: string | undefined): number {
  if (!version || !/^[1-9][0-9]{0,14}$/.test(version)) throw invalid('Version de sauvegarde invalide.');
  return Number(version);
}

/** Nouvelle version : l'ancienne cesse d'être courante. Verrou sur la personne pour sérialiser les créations. */
export async function createBackupVersion(db: PoolClient, actor: KeyActor, body: unknown) {
  const input = object(body, 4096);
  if (typeof input.algorithm !== 'string' || !/^[A-Za-z0-9._-]{1,128}$/.test(input.algorithm) || !isObject(input.auth_data)
    || Object.keys(input).length !== 2) throw invalid();
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`messaging.backup|${actor.schoolId}|${actor.personId}`]);
  const last = await db.query<{ version: string }>('SELECT COALESCE(max(version),0) AS version FROM drivy.messaging_key_backup WHERE school_id=$1 AND person_id=$2',
    [actor.schoolId, actor.personId]);
  // POST est une création, pas une rotation : préserver la clé de récupération et
  // l'historique existants, y compris après une réponse perdue ou depuis un autre appareil.
  if (safeId(last.rows[0]?.version ?? 0) > 0)
    throw new ApiError(409, 'BACKUP_ALREADY_EXISTS', 'Une sauvegarde existe déjà. Restaurez-la avec votre clé de récupération.');
  const version = 1;
  await db.query(`INSERT INTO drivy.messaging_key_backup(school_id,person_id,version,algorithm,auth_data) VALUES($1,$2,$3,$4,$5)`,
    [actor.schoolId, actor.personId, version, input.algorithm, input.auth_data]);
  return { version: String(version) };
}

export async function getBackupVersion(db: PoolClient, actor: KeyActor) {
  const backup = await currentBackup(db, actor, false);
  if (!backup) throw notFound();
  const count = await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_key_backup_session
    WHERE school_id=$1 AND person_id=$2 AND version=$3`, [actor.schoolId, actor.personId, backup.version]);
  return { version: String(safeId(backup.version)), algorithm: backup.algorithm, auth_data: backup.authData,
    etag: String(safeId(backup.etag)), count: count.rows[0]?.count ?? 0 };
}

function better(next: Json, previous: Json): boolean {
  const verified = (v: Json) => v.is_verified === true;
  const index = (v: Json) => typeof v.first_message_index === 'number' ? v.first_message_index : Number.MAX_SAFE_INTEGER;
  const forwarded = (v: Json) => typeof v.forwarded_count === 'number' ? v.forwarded_count : Number.MAX_SAFE_INTEGER;
  if (verified(next) !== verified(previous)) return verified(next);
  if (index(next) !== index(previous)) return index(next) < index(previous);
  return forwarded(next) < forwarded(previous);
}

/** CAS sur la version courante : une version périmée reçoit 409 BACKUP_VERSION_CONFLICT. Idempotent. */
export async function putBackupKeys(db: PoolClient, actor: KeyActor, versionText: string | undefined, body: unknown) {
  const version = parseVersion(versionText);
  const input = object(body, 4_194_304);
  if (!isObject(input.rooms) || Object.keys(input).length !== 1) throw invalid();
  const backup = await currentBackup(db, actor, true);
  if (!backup || safeId(backup.version) !== version) throw backupConflict();
  const sessions: { room: string; session: string; data: Json }[] = [];
  for (const [room, value] of Object.entries(input.rooms)) {
    if (!/^![0-9a-f-]{36}:drivy$/.test(room) || !isObject(value) || !isObject(value.sessions)) throw invalid();
    for (const [session, data] of Object.entries(value.sessions)) {
      if (!/^[A-Za-z0-9+/=_-]{1,128}$/.test(session) || !isObject(data) || !isObject(data.session_data)
        || bytes(data) > limits.backupSessionBytes) throw invalid();
      sessions.push({ room, session, data });
    }
  }
  if (sessions.length > limits.backupSessionsPerPut) throw invalid('Trop de sessions.');
  let changed = false;
  for (const entry of sessions) {
    const existing = await db.query<{ data: Json }>(`SELECT data FROM drivy.messaging_key_backup_session WHERE school_id=$1 AND person_id=$2
      AND version=$3 AND room_id=$4 AND session_id=$5 FOR UPDATE`, [actor.schoolId, actor.personId, version, entry.room, entry.session]);
    if (!existing.rows[0]) {
      await db.query(`INSERT INTO drivy.messaging_key_backup_session(school_id,person_id,version,room_id,session_id,data) VALUES($1,$2,$3,$4,$5,$6)`,
        [actor.schoolId, actor.personId, version, entry.room, entry.session, entry.data]);
      changed = true;
    } else if (better(entry.data, existing.rows[0].data)) {
      await db.query(`UPDATE drivy.messaging_key_backup_session SET data=$6,updated_at=now() WHERE school_id=$1 AND person_id=$2
        AND version=$3 AND room_id=$4 AND session_id=$5`, [actor.schoolId, actor.personId, version, entry.room, entry.session, entry.data]);
      changed = true;
    }
  }
  const etag = await db.query<{ etag: string }>(`UPDATE drivy.messaging_key_backup SET etag=etag+$4 WHERE school_id=$1 AND person_id=$2
    AND version=$3 RETURNING etag`, [actor.schoolId, actor.personId, version, changed ? 1 : 0]);
  const count = await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_key_backup_session
    WHERE school_id=$1 AND person_id=$2 AND version=$3`, [actor.schoolId, actor.personId, version]);
  return { etag: String(safeId(etag.rows[0]?.etag ?? 0)), count: count.rows[0]?.count ?? 0 };
}

export async function getBackupKeys(db: PoolClient, actor: KeyActor, versionText: string | undefined) {
  const version = parseVersion(versionText);
  const backup = await db.query('SELECT 1 FROM drivy.messaging_key_backup WHERE school_id=$1 AND person_id=$2 AND version=$3',
    [actor.schoolId, actor.personId, version]);
  if (!backup.rows[0]) throw notFound();
  const rows = await db.query<{ room: string; session: string; data: Json }>(`SELECT room_id AS room,session_id AS session,data
    FROM drivy.messaging_key_backup_session WHERE school_id=$1 AND person_id=$2 AND version=$3 ORDER BY room_id,session_id LIMIT 5001`,
    [actor.schoolId, actor.personId, version]);
  if (rows.rows.length > 5000) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Sauvegarde trop volumineuse.');
  const rooms: Record<string, { sessions: Record<string, Json> }> = {};
  for (const row of rows.rows) (rooms[row.room] ??= { sessions: {} }).sessions[row.session] = row.data;
  return { rooms };
}
