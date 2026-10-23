import type { PoolClient } from 'pg';
import { createHash, randomUUID } from 'node:crypto';
import { ApiError, forbidden, notFound } from './errors.js';

/** Transport format only, not a cryptographic protocol or claim of E2EE. */
export interface OpaqueEnvelope { scheme: string; keyId: string; payload: string }
export interface MessagingActor { personId: string; schoolId: string; membershipId: string }
export interface MessagingContact { personId: string; displayName: string }
export interface StoredMessage { id: string; schoolId: string; conversationId: string; sequence: number;
  clientMessageId: string; senderId: string; ciphertext: OpaqueEnvelope; mentionPersonIds: string[]; acceptedAt: string }

export const messagingUnavailable = () => new ApiError(503, 'MESSAGING_NOT_ENABLED', 'La messagerie n’est pas encore disponible.');
function safeSequence(value: string | number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  return parsed;
}
function assertContext(actor: MessagingActor): void {
  if (!actor.schoolId || !actor.personId || !actor.membershipId) throw forbidden();
}
async function canRead(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<void> {
  assertContext(actor);
  const check = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (check.rows[0]?.allowed !== true) throw notFound();
}
export async function eligibleContacts(db: PoolClient, actor: MessagingActor, limit = 50, afterPersonId?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<MessagingContact>(
    `SELECT person_id AS "personId", display_name AS "displayName" FROM drivy.messaging_contacts($1,$2)
      WHERE ($3::uuid IS NULL OR person_id>$3) ORDER BY person_id LIMIT $4`,
    [actor.schoolId, actor.personId, afterPersonId ?? null, limit + 1]);
  return { contacts: result.rows.slice(0, limit), nextCursor: result.rows.length > limit ? result.rows[limit - 1]!.personId : null };
}
export async function generalMembers(db: PoolClient, actor: MessagingActor, limit = 50, afterPersonId?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<MessagingContact>(`SELECT person_id AS "personId",display_name AS "displayName"
    FROM drivy.messaging_general_members($1,$2)
    WHERE ($3::uuid IS NULL OR person_id>$3) ORDER BY person_id LIMIT $4`,
    [actor.schoolId, actor.personId, afterPersonId ?? null, limit + 1]);
  return { members: result.rows.slice(0, limit), nextCursor: result.rows.length > limit ? result.rows[limit - 1]!.personId : null };
}
export async function findOrCreatePrivate(db: PoolClient, actor: MessagingActor, peerId: string): Promise<string> {
  assertContext(actor);
  if (peerId.toLowerCase() === actor.personId.toLowerCase()) throw forbidden();
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,$3)', [actor.schoolId, actor.personId, peerId]);
  const allowed = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_private_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, peerId]);
  if (allowed.rows[0]?.allowed !== true) throw forbidden();
  const [low, high] = [actor.personId.toLowerCase(), peerId.toLowerCase()].sort();
  const result = await db.query<{ id: string }>(`INSERT INTO drivy.messaging_conversation(id,school_id,kind,person_low,person_high)
    VALUES($1,$2,'PRIVATE',$3,$4) ON CONFLICT (school_id,person_low,person_high) WHERE kind='PRIVATE'
    DO NOTHING RETURNING id`, [randomUUID(), actor.schoolId, low, high]);
  if (result.rows[0]) return result.rows[0].id;
  const existing = await db.query<{ id: string }>(`SELECT id FROM drivy.messaging_conversation
    WHERE school_id=$1 AND kind='PRIVATE' AND person_low=$2 AND person_high=$3`, [actor.schoolId, low, high]);
  if (!existing.rows[0]) throw notFound();
  return existing.rows[0].id;
}
export async function findOrCreateGeneral(db: PoolClient, actor: MessagingActor): Promise<string> {
  assertContext(actor);
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,NULL::uuid)', [actor.schoolId, actor.personId]);
  const result = await db.query<{ id: string }>(`INSERT INTO drivy.messaging_conversation(id,school_id,kind)
    VALUES($1,$2,'GENERAL') ON CONFLICT (school_id) WHERE kind='GENERAL'
    DO NOTHING RETURNING id`, [randomUUID(), actor.schoolId]);
  if (result.rows[0]) return result.rows[0].id;
  const existing = await db.query<{ id: string }>(`SELECT id FROM drivy.messaging_conversation
    WHERE school_id=$1 AND kind='GENERAL'`, [actor.schoolId]);
  if (!existing.rows[0]) throw notFound();
  return existing.rows[0].id;
}
export async function listConversations(db: PoolClient, actor: MessagingActor, limit: number, before?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<{ id: string; schoolId: string; kind: string; lastSequence: number; peerPersonId: string | null;
    title: string; lastReadSequence: string; mutedUntil: string | null; readStateVersion: number; unreadCount: number }>(`SELECT c.id,c.school_id AS "schoolId",c.kind,c.last_sequence AS "lastSequence",
    CASE WHEN c.kind='PRIVATE' THEN CASE WHEN c.person_low=$2 THEN c.person_high ELSE c.person_low END ELSE NULL END AS "peerPersonId",
    CASE WHEN c.kind='GENERAL' THEN 'Général' ELSE COALESCE(peer.display_name,'Conversation privée') END AS title,
    COALESCE(s.last_read_sequence,0) AS "lastReadSequence",s.muted_until AS "mutedUntil",
    COALESCE(s.version,0) AS "readStateVersion",
    (SELECT count(*)::int FROM drivy.messaging_message m WHERE m.school_id=c.school_id AND m.conversation_id=c.id
      AND m.sequence>COALESCE(s.last_read_sequence,0) AND m.sender_person_id<>$2) AS "unreadCount"
    FROM drivy.messaging_conversation c LEFT JOIN drivy.messaging_read_state s
      ON s.school_id=c.school_id AND s.conversation_id=c.id AND s.person_id=$2
    LEFT JOIN LATERAL (SELECT contact.display_name FROM drivy.messaging_contacts($1,$2) contact
      WHERE c.kind='PRIVATE' AND contact.person_id=CASE WHEN c.person_low=$2 THEN c.person_high ELSE c.person_low END) peer ON true
    WHERE c.school_id=$1 AND ($3::uuid IS NULL OR c.id<$3)
    AND drivy.messaging_conversation_allowed($1,$2,c.id)
    ORDER BY c.id DESC LIMIT $4`, [actor.schoolId, actor.personId, before ?? null, limit + 1]);
  return { items: result.rows.slice(0, limit).map(row => ({ ...row,
      lastSequence: safeSequence(row.lastSequence), lastReadSequence: safeSequence(row.lastReadSequence) })),
    nextCursor: result.rows.length > limit ? result.rows[limit - 1]?.id ?? null : null };
}
export async function pageEnvelopes(db: PoolClient, actor: MessagingActor, conversationId: string, beforeSequence?: number, limit = 50) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || (beforeSequence !== undefined && (!Number.isSafeInteger(beforeSequence) || beforeSequence < 1)))
    throw new ApiError(400, 'INVALID_REQUEST', 'Pagination invalide.');
  await canRead(db, actor, conversationId);
  const result = await db.query<StoredMessage>(`SELECT id,school_id AS "schoolId",conversation_id AS "conversationId",sequence,
    intent_id AS "clientMessageId",sender_person_id AS "senderId",envelope AS ciphertext,
    mention_person_ids AS "mentionPersonIds",created_at AS "acceptedAt"
    FROM drivy.messaging_message WHERE school_id=$1 AND conversation_id=$2 AND ($3::bigint IS NULL OR sequence<$3)
    ORDER BY sequence DESC LIMIT $4`, [actor.schoolId, conversationId, beforeSequence ?? null, limit + 1]);
  return { items: result.rows.slice(0, limit).map(row => ({ ...row, sequence: safeSequence(row.sequence) })),
    nextCursor: result.rows.length > limit ? String(safeSequence(result.rows[limit - 1]!.sequence)) : null };
}
export async function resumeEnvelopes(db: PoolClient, actor: MessagingActor, conversationId: string, afterSequence = 0, limit = 50) {
  if (!Number.isSafeInteger(afterSequence) || afterSequence < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100)
    throw new ApiError(400, 'INVALID_REQUEST', 'Pagination invalide.');
  await canRead(db, actor, conversationId);
  const rows = await db.query<StoredMessage>(`SELECT id,school_id AS "schoolId",conversation_id AS "conversationId",sequence,
    intent_id AS "clientMessageId",sender_person_id AS "senderId",envelope AS ciphertext,
    mention_person_ids AS "mentionPersonIds",created_at AS "acceptedAt" FROM drivy.messaging_message
    WHERE school_id=$1 AND conversation_id=$2 AND sequence>$3 ORDER BY sequence ASC LIMIT $4`,
    [actor.schoolId, conversationId, afterSequence, limit + 1]);
  const messages = rows.rows.slice(0, limit).map(row => ({ ...row, sequence: safeSequence(row.sequence) }));
  return { messages, nextAfterSequence: messages.at(-1)?.sequence ?? afterSequence, hasMore: rows.rows.length > limit };
}
export async function sendEnvelope(db: PoolClient, actor: MessagingActor, conversationId: string,
  intentId: string, envelope: OpaqueEnvelope, mentionPersonIds: string[] = []): Promise<StoredMessage> {
  await canRead(db, actor, conversationId);
  if (mentionPersonIds.length > 8 || new Set(mentionPersonIds.map(id => id.toLowerCase())).size !== mentionPersonIds.length)
    throw new ApiError(400, 'INVALID_REQUEST', 'Mentions invalides.');
  const target = await db.query<{ peerPersonId: string | null }>(`SELECT CASE WHEN kind='PRIVATE'
    THEN CASE WHEN person_low=$3 THEN person_high ELSE person_low END ELSE NULL END AS "peerPersonId"
    FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2`, [actor.schoolId, conversationId, actor.personId]);
  if (!target.rows[0]) throw notFound();
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,$3,$4::uuid[])',
    [actor.schoolId, actor.personId, target.rows[0].peerPersonId, mentionPersonIds]);
  await canRead(db, actor, conversationId);
  const mentionsAllowed = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_mentions_allowed($1,$2,$3,$4::uuid[]) AS allowed',
    [actor.schoolId, actor.personId, conversationId, mentionPersonIds]);
  if (!mentionsAllowed.rows[0]?.allowed) throw forbidden();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(intentId)
    || !envelope || !/^[A-Za-z0-9._-]{1,80}$/.test(envelope.scheme)
    || !/^[A-Za-z0-9._:-]{1,128}$/.test(envelope.keyId)
    || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(envelope.payload)
    || envelope.payload.length < 4 || envelope.payload.length > 12000)
    throw new ApiError(400, 'INVALID_ENVELOPE', 'Enveloppe invalide.');
  const canonical = JSON.stringify(envelope);
  const fingerprint = createHash('sha256').update(JSON.stringify([envelope, mentionPersonIds.map(id => id.toLowerCase())])).digest('hex');
  // Serialization on the conversation row makes sequence allocation atomic across concurrent senders.
  const conversation = await db.query<{ lastSequence: number }>(`SELECT last_sequence AS "lastSequence" FROM drivy.messaging_conversation
    WHERE school_id=$1 AND id=$2 FOR UPDATE`, [actor.schoolId, conversationId]);
  if (!conversation.rows[0]) throw notFound();
  // Recheck after waiting for a lock: revocation during contention must not authorize a late write.
  await canRead(db, actor, conversationId);
  const prior = await db.query<StoredMessage & { fingerprint: string }>(`SELECT id,school_id AS "schoolId",conversation_id AS "conversationId",sequence,
    intent_id AS "clientMessageId",sender_person_id AS "senderId",envelope AS ciphertext,
    mention_person_ids AS "mentionPersonIds",created_at AS "acceptedAt",fingerprint
    FROM drivy.messaging_message WHERE school_id=$1 AND conversation_id=$2 AND sender_person_id=$3 AND intent_id=$4`,
    [actor.schoolId, conversationId, actor.personId, intentId]);
  if (prior.rows[0]) {
    if (prior.rows[0].fingerprint !== fingerprint) throw new ApiError(409, 'INTENT_CONFLICT', 'Cet envoi a déjà été utilisé avec un autre contenu.');
    const { fingerprint: _unused, ...message } = prior.rows[0]; return { ...message, sequence: safeSequence(message.sequence) };
  }
  const next = safeSequence(conversation.rows[0].lastSequence) + 1;
  if (!Number.isSafeInteger(next)) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  // Counter first: if rights disappear, UPDATE RETURNING yields no row and no message can be committed.
  // A later denied INSERT rolls the counter back in the same transaction.
  const advanced = await db.query<{ sequence: string }>(`UPDATE drivy.messaging_conversation SET last_sequence=$3
    WHERE school_id=$1 AND id=$2 RETURNING last_sequence AS sequence`, [actor.schoolId, conversationId, next]);
  if (!advanced.rows[0]) throw notFound();
  const sequence = safeSequence(advanced.rows[0].sequence);
  const inserted = await db.query<StoredMessage>(`INSERT INTO drivy.messaging_message(id,school_id,conversation_id,sequence,intent_id,sender_person_id,envelope,mention_person_ids,fingerprint)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id,school_id AS "schoolId",conversation_id AS "conversationId",sequence,
      intent_id AS "clientMessageId",sender_person_id AS "senderId",envelope AS ciphertext,
      mention_person_ids AS "mentionPersonIds",created_at AS "acceptedAt"`,
    [randomUUID(), actor.schoolId, conversationId, sequence, intentId, actor.personId, canonical, mentionPersonIds, fingerprint]);
  if (!inserted.rows[0]) throw notFound();
  return { ...inserted.rows[0], sequence: safeSequence(inserted.rows[0].sequence) };
}

/** Internal per-person reading progress, not a delivery receipt or a visible read receipt. */
export async function updateReadState(db: PoolClient, actor: MessagingActor, conversationId: string,
  sequence: number, mutedUntil?: string | null, expectedVersion?: number) {
  if (!Number.isSafeInteger(sequence) || sequence < 0) throw new ApiError(400, 'INVALID_REQUEST', 'Progression invalide.');
  if (mutedUntil !== undefined && (!Number.isSafeInteger(expectedVersion) || expectedVersion! < 0))
    throw new ApiError(400, 'INVALID_REQUEST', 'Version de silence requise.');
  await canRead(db, actor, conversationId);
  const target = await db.query<{ peerPersonId: string | null }>(`SELECT CASE WHEN kind='PRIVATE'
    THEN CASE WHEN person_low=$3 THEN person_high ELSE person_low END ELSE NULL END AS "peerPersonId"
    FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2`, [actor.schoolId, conversationId, actor.personId]);
  if (!target.rows[0]) throw notFound();
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,$3)', [actor.schoolId, actor.personId, target.rows[0].peerPersonId]);
  await canRead(db, actor, conversationId);
  const current = await db.query<{ lastSequence: string }>(`SELECT last_sequence AS "lastSequence" FROM drivy.messaging_conversation
    WHERE school_id=$1 AND id=$2`, [actor.schoolId, conversationId]);
  if (!current.rows[0] || sequence > safeSequence(current.rows[0].lastSequence))
    throw new ApiError(400, 'INVALID_REQUEST', 'Progression invalide.');
  if (mutedUntil !== undefined) {
    const state = await db.query<{ version: number }>(`SELECT version FROM drivy.messaging_read_state
      WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 FOR UPDATE`,
      [actor.schoolId, conversationId, actor.personId]);
    if ((state.rows[0]?.version ?? 0) !== expectedVersion)
      throw new ApiError(409, 'READ_STATE_CONFLICT', 'Le silence a changé sur un autre appareil. Rechargez la conversation.');
  }
  const result = await db.query<{ lastReadSequence: string; mutedUntil: string | null; readStateVersion: number }>(`INSERT INTO drivy.messaging_read_state
    (school_id,conversation_id,person_id,last_read_sequence,muted_until) VALUES($1,$2,$3,$4,$5)
    ON CONFLICT(school_id,conversation_id,person_id) DO UPDATE SET
      last_read_sequence=GREATEST(drivy.messaging_read_state.last_read_sequence,EXCLUDED.last_read_sequence),
      muted_until=CASE WHEN $6::boolean THEN EXCLUDED.muted_until ELSE drivy.messaging_read_state.muted_until END,
      version=drivy.messaging_read_state.version+CASE WHEN $6::boolean THEN 1 ELSE 0 END,updated_at=now()
    WHERE (NOT $6::boolean OR drivy.messaging_read_state.version=$7::integer)
    RETURNING last_read_sequence AS "lastReadSequence",muted_until AS "mutedUntil",version AS "readStateVersion"`,
    [actor.schoolId, conversationId, actor.personId, sequence, mutedUntil ?? null, mutedUntil !== undefined, expectedVersion ?? null]);
  if (!result.rows[0]) throw new ApiError(409, 'READ_STATE_CONFLICT', 'Le silence a changé sur un autre appareil. Rechargez la conversation.');
  return { ...result.rows[0], lastReadSequence: safeSequence(result.rows[0].lastReadSequence) };
}
