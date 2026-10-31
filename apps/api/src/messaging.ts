import type { PoolClient } from 'pg';
import { createHash, randomUUID } from 'node:crypto';
import { ApiError, forbidden, notFound } from './errors.js';
import { messageColumns, notHiddenForActor, syncLinks, toView, type MessageView } from './messaging-view.js';

/** Transport format only, not a cryptographic protocol or claim of E2EE. */
export interface OpaqueEnvelope { scheme: string; keyId: string; payload: string }
export interface MessagingActor { personId: string; schoolId: string; membershipId: string }
export interface MessagingContact { personId: string; displayName: string }
export type StoredMessage = MessageView;
export interface PollCreation { optionCount: number; multiple: boolean }

export const messagingUnavailable = () => new ApiError(503, 'MESSAGING_NOT_ENABLED', 'La messagerie n’est pas encore disponible.');
function safeSequence(value: string | number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  return parsed;
}
function assertContext(actor: MessagingActor): void {
  if (!actor.schoolId || !actor.personId || !actor.membershipId) throw forbidden();
}
/** Applique la fin du lien avant tout contrôle : un ancien membre garde sa plage lisible, sans écriture. */
export async function canRead(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<void> {
  assertContext(actor);
  const exists = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (exists.rows[0]?.allowed !== true) throw notFound();
  await syncLinks(db, actor.schoolId, conversationId);
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
/** Écriture : lien ouvert après synchronisation, sinon 403 (lecture seule). */
export async function canWrite(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<void> {
  const check = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_can_write($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (check.rows[0]?.allowed !== true) throw forbidden();
}
/** Annuaire du général : nom, version de photo si visible (#64), administrateur du groupe. */
export async function generalMembers(db: PoolClient, actor: MessagingActor, limit = 50, afterPersonId?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<MessagingContact & { photoVersion: number | null; hasPhoto: boolean; isGroupAdmin: boolean }>(
    `SELECT person_id AS "personId",display_name AS "displayName",photo_version AS "photoVersion",
      (photo_version IS NOT NULL) AS "hasPhoto",is_group_admin AS "isGroupAdmin"
    FROM drivy.messaging_general_directory($1,$2)
    WHERE ($3::uuid IS NULL OR person_id>$3) ORDER BY person_id LIMIT $4`,
    [actor.schoolId, actor.personId, afterPersonId ?? null, limit + 1]);
  return { members: result.rows.slice(0, limit), nextCursor: result.rows.length > limit ? result.rows[limit - 1]!.personId : null };
}
/** Membres retirés du général (administrateurs du groupe) : droits relus et verrouillés dans la fonction SQL. */
export async function generalRemovedMembers(db: PoolClient, actor: MessagingActor, limit = 50, afterPersonId?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<MessagingContact & { photoVersion: number | null; removedAt: Date }>(
    `SELECT person_id AS "personId",display_name AS "displayName",photo_version AS "photoVersion",removed_at AS "removedAt"
    FROM drivy.messaging_general_removed_members($1,$2,$3)`,
    [actor.schoolId, afterPersonId ?? null, limit + 1]);
  const members = result.rows.slice(0, limit).map(row => ({ ...row, removedAt: new Date(row.removedAt).toISOString() }));
  return { members, nextCursor: result.rows.length > limit ? result.rows[limit - 1]!.personId : null };
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
  const created = result.rows[0]?.id;
  const existing = created ? undefined : await db.query<{ id: string }>(`SELECT id FROM drivy.messaging_conversation
    WHERE school_id=$1 AND kind='PRIVATE' AND person_low=$2 AND person_high=$3`, [actor.schoolId, low, high]);
  const conversationId = created ?? existing?.rows[0]?.id;
  if (!conversationId) throw notFound();
  await syncLinks(db, actor.schoolId, conversationId);
  return conversationId;
}
export async function findOrCreateGeneral(db: PoolClient, actor: MessagingActor): Promise<string> {
  assertContext(actor);
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,NULL::uuid)', [actor.schoolId, actor.personId]);
  const result = await db.query<{ id: string }>(`INSERT INTO drivy.messaging_conversation(id,school_id,kind)
    VALUES($1,$2,'GENERAL') ON CONFLICT (school_id) WHERE kind='GENERAL'
    DO NOTHING RETURNING id`, [randomUUID(), actor.schoolId]);
  const created = result.rows[0]?.id;
  const existing = created ? undefined : await db.query<{ id: string }>(`SELECT id FROM drivy.messaging_conversation
    WHERE school_id=$1 AND kind='GENERAL'`, [actor.schoolId]);
  const conversationId = created ?? existing?.rows[0]?.id;
  if (!conversationId) throw notFound();
  await syncLinks(db, actor.schoolId, conversationId);
  // Un membre retiré du général n'y entre pas par cette commande.
  await canWrite(db, actor, conversationId);
  return conversationId;
}
export async function listConversations(db: PoolClient, actor: MessagingActor, limit: number, before?: string) {
  assertContext(actor);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  const result = await db.query<{ id: string; schoolId: string; kind: string; lastSequence: number; peerPersonId: string | null;
    title: string; lastReadSequence: string; mutedUntil: string | null; readStateVersion: number; unreadCount: number; membersEpoch: string }>(`SELECT c.id,c.school_id AS "schoolId",c.kind,
    COALESCE((SELECT max(v.sequence) FROM drivy.messaging_message v WHERE v.school_id=c.school_id AND v.conversation_id=c.id),0) AS "lastSequence",
    c.members_epoch AS "membersEpoch",
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
      lastSequence: safeSequence(row.lastSequence), lastReadSequence: safeSequence(row.lastReadSequence), membersEpoch: safeSequence(row.membersEpoch) })),
    nextCursor: result.rows.length > limit ? result.rows[limit - 1]?.id ?? null : null };
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const reactionPalette = ['👍', '❤️', '😂', '😮', '😢', '🙏'] as const;

function validEnvelope(envelope: OpaqueEnvelope | undefined): boolean {
  return !!envelope && /^[A-Za-z0-9._-]{1,80}$/.test(envelope.scheme) && /^[A-Za-z0-9._:-]{1,128}$/.test(envelope.keyId)
    && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(envelope.payload)
    && envelope.payload.length >= 4 && envelope.payload.length <= 12000;
}
/** Droits de l'acteur dans la conversation, recalculés après synchronisation des liens. */
async function access(db: PoolClient, actor: MessagingActor, conversationId: string) {
  const result = await db.query<{ canWrite: boolean; readableUntilSequence: string | null; isGroupAdmin: boolean }>(`SELECT
    drivy.messaging_can_write($1,$2,$3) AS "canWrite",
    (SELECT CASE WHEN bool_or(l.cut_sequence IS NULL) THEN NULL ELSE max(l.cut_sequence) END FROM drivy.messaging_member_link l
      WHERE l.school_id=$1 AND l.conversation_id=$3 AND l.person_id=$2) AS "readableUntilSequence",
    (c.kind='GENERAL' AND drivy.messaging_actor_is_group_admin($1)) AS "isGroupAdmin"
    FROM drivy.messaging_conversation c WHERE c.school_id=$1 AND c.id=$3`, [actor.schoolId, actor.personId, conversationId]);
  const row = result.rows[0];
  if (!row) throw notFound();
  return { canWrite: row.canWrite, isGroupAdmin: row.isGroupAdmin,
    readableUntilSequence: row.readableUntilSequence === null ? null : safeSequence(row.readableUntilSequence) };
}
export async function pageEnvelopes(db: PoolClient, actor: MessagingActor, conversationId: string, beforeSequence?: number, limit = 50) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || (beforeSequence !== undefined && (!Number.isSafeInteger(beforeSequence) || beforeSequence < 1)))
    throw new ApiError(400, 'INVALID_REQUEST', 'Pagination invalide.');
  await canRead(db, actor, conversationId);
  // La RLS borne la lecture à la plage du lien (readable_after < sequence <= cut_sequence).
  const result = await db.query<MessageView>(`SELECT ${messageColumns} FROM drivy.messaging_message m
    WHERE m.school_id=$1 AND m.conversation_id=$3 AND ($4::bigint IS NULL OR m.sequence<$4) AND ${notHiddenForActor}
    ORDER BY m.sequence DESC LIMIT $5`, [actor.schoolId, actor.personId, conversationId, beforeSequence ?? null, limit + 1]);
  const receipts = await db.query<{ personId: string; lastReadSequence: string }>(`SELECT person_id AS "personId",
    last_read_sequence AS "lastReadSequence" FROM drivy.messaging_read_receipts($1,$2,$3) ORDER BY person_id`,
    [actor.schoolId, actor.personId, conversationId]);
  return { items: result.rows.slice(0, limit).map(toView),
    nextCursor: result.rows.length > limit ? String(safeSequence(result.rows[limit - 1]!.sequence)) : null,
    access: await access(db, actor, conversationId),
    readStates: receipts.rows.map(row => ({ personId: row.personId, lastReadSequence: safeSequence(row.lastReadSequence) })) };
}
export async function resumeEnvelopes(db: PoolClient, actor: MessagingActor, conversationId: string, afterSequence = 0, limit = 50) {
  if (!Number.isSafeInteger(afterSequence) || afterSequence < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100)
    throw new ApiError(400, 'INVALID_REQUEST', 'Pagination invalide.');
  await canRead(db, actor, conversationId);
  const rows = await db.query<MessageView>(`SELECT ${messageColumns} FROM drivy.messaging_message m
    WHERE m.school_id=$1 AND m.conversation_id=$3 AND m.sequence>$4 AND ${notHiddenForActor}
    ORDER BY m.sequence ASC LIMIT $5`, [actor.schoolId, actor.personId, conversationId, afterSequence, limit + 1]);
  const messages = rows.rows.slice(0, limit).map(toView);
  return { messages, nextAfterSequence: messages.at(-1)?.sequence ?? afterSequence, hasMore: rows.rows.length > limit };
}
async function messageById(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string): Promise<MessageView> {
  const result = await db.query<MessageView>(`SELECT ${messageColumns} FROM drivy.messaging_message m
    WHERE m.school_id=$1 AND m.conversation_id=$2 AND m.id=$3`, [actor.schoolId, conversationId, messageId]);
  if (!result.rows[0]) throw notFound();
  return toView(result.rows[0]);
}
/**
 * Ordre des verrous de la fondation pour toute écriture : sources de droits (messaging_lock_rights), puis
 * conversation (messaging_sync_links la verrouille si des liens changent). Aucun verrou de conversation avant
 * celui des droits, sinon deux écritures concurrentes peuvent s'interbloquer.
 */
export async function lockRights(db: PoolClient, actor: MessagingActor, conversationId: string, mentions: string[] = []): Promise<void> {
  assertContext(actor);
  const target = await db.query<{ peerPersonId: string | null }>(`SELECT CASE WHEN kind='PRIVATE'
    THEN CASE WHEN person_low=$3 THEN person_high ELSE person_low END ELSE NULL END AS "peerPersonId"
    FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2`, [actor.schoolId, conversationId, actor.personId]);
  if (!target.rows[0]) throw notFound();
  await db.query('SELECT drivy.messaging_lock_rights($1,$2,$3,$4::uuid[])',
    [actor.schoolId, actor.personId, target.rows[0].peerPersonId, mentions]);
}
/** Droits verrouillés, liens synchronisés, puis lecture (404) et écriture (403) recontrôlées. */
async function lockForWrite(db: PoolClient, actor: MessagingActor, conversationId: string, mentions: string[] = [], write = true) {
  const visible = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (visible.rows[0]?.allowed !== true) throw notFound();
  await lockRights(db, actor, conversationId, mentions);
  await syncLinks(db, actor.schoolId, conversationId);
  const check = await db.query<{ allowed: boolean }>('SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (check.rows[0]?.allowed !== true) throw notFound();
  if (write) await canWrite(db, actor, conversationId);
}
export async function sendEnvelope(db: PoolClient, actor: MessagingActor, conversationId: string,
  intentId: string, envelope: OpaqueEnvelope, mentionPersonIds: string[] = [],
  replyToMessageId: string | null = null, poll: PollCreation | null = null,
  expectedMembersEpoch?: number): Promise<StoredMessage> {
  if (expectedMembersEpoch !== undefined && (!Number.isSafeInteger(expectedMembersEpoch) || expectedMembersEpoch < 0))
    throw new ApiError(400, 'INVALID_REQUEST', 'Époque de chiffrement invalide.');
  if (mentionPersonIds.length > 8 || new Set(mentionPersonIds.map(id => id.toLowerCase())).size !== mentionPersonIds.length)
    throw new ApiError(400, 'INVALID_REQUEST', 'Mentions invalides.');
  if (!uuidPattern.test(intentId) || !validEnvelope(envelope)) throw new ApiError(400, 'INVALID_ENVELOPE', 'Enveloppe invalide.');
  if ((replyToMessageId !== null && !uuidPattern.test(replyToMessageId))
    || (poll && (!Number.isSafeInteger(poll.optionCount) || poll.optionCount < 2 || poll.optionCount > 12 || typeof poll.multiple !== 'boolean')))
    throw new ApiError(400, 'INVALID_REQUEST', 'Message invalide.');
  await lockForWrite(db, actor, conversationId, mentionPersonIds);
  const canonical = JSON.stringify(envelope);
  const fingerprint = createHash('sha256').update(JSON.stringify([envelope, mentionPersonIds.map(id => id.toLowerCase()),
    replyToMessageId?.toLowerCase() ?? null, poll ? [poll.optionCount, poll.multiple] : null])).digest('hex');
  // Le verrou de la conversation rend l'allocation de séquence atomique ; la RLS de mise à jour exige un lien ouvert.
  const conversation = await db.query<{ lastSequence: string }>(`SELECT last_sequence AS "lastSequence" FROM drivy.messaging_conversation
    WHERE school_id=$1 AND id=$2 FOR UPDATE`, [actor.schoolId, conversationId]);
  if (!conversation.rows[0]) throw forbidden();
  // Revérifie après l'attente : une fin de lien pendant la contention n'autorise pas une écriture tardive.
  const membersEpoch = await syncLinks(db, actor.schoolId, conversationId);
  await canWrite(db, actor, conversationId);
  const prior = await db.query<{ id: string; fingerprint: string }>(`SELECT id,fingerprint FROM drivy.messaging_message
    WHERE school_id=$1 AND conversation_id=$2 AND sender_person_id=$3 AND intent_id=$4`,
    [actor.schoolId, conversationId, actor.personId, intentId]);
  if (prior.rows[0]) {
    if (prior.rows[0].fingerprint !== fingerprint) throw new ApiError(409, 'INTENT_CONFLICT', 'Cet envoi a déjà été utilisé avec un autre contenu.');
    return messageById(db, actor, conversationId, prior.rows[0].id);
  }
  // Une réponse perdue déjà acceptée reste idempotente, même pour une archive sans époque.
  // Une intention nouvelle doit correspondre à la même liste de membres que son chiffrement.
  // Le verrou de conversation est conservé jusqu'au COMMIT : aucun départ ne peut s'intercaler.
  if (expectedMembersEpoch === undefined || expectedMembersEpoch !== membersEpoch)
    throw new ApiError(409, 'MESSAGING_MEMBERS_CHANGED', 'Les participants ont changé. Le message n’a pas été envoyé.');
  if (replyToMessageId) {
    const open = await db.query<{ open: boolean }>('SELECT drivy.messaging_message_open($1,$2,$3,$4) AS open',
      [actor.schoolId, actor.personId, conversationId, replyToMessageId]);
    if (open.rows[0]?.open !== true) throw notFound();
  }
  const next = safeSequence(conversation.rows[0].lastSequence) + 1;
  if (!Number.isSafeInteger(next)) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  const advanced = await db.query<{ sequence: string }>(`UPDATE drivy.messaging_conversation SET last_sequence=$3
    WHERE school_id=$1 AND id=$2 RETURNING last_sequence AS sequence`, [actor.schoolId, conversationId, next]);
  if (!advanced.rows[0]) throw forbidden();
  const messageId = randomUUID();
  await db.query(`INSERT INTO drivy.messaging_message(id,school_id,conversation_id,sequence,intent_id,sender_person_id,envelope,
    mention_person_ids,fingerprint,reply_to_message_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
    [messageId, actor.schoolId, conversationId, safeSequence(advanced.rows[0].sequence), intentId, actor.personId, canonical,
      mentionPersonIds, fingerprint, replyToMessageId]);
  if (poll) await db.query(`INSERT INTO drivy.messaging_poll(school_id,conversation_id,message_id,creator_person_id,option_count,multiple)
    VALUES($1,$2,$3,$4,$5,$6)`, [actor.schoolId, conversationId, messageId, actor.personId, poll.optionCount, poll.multiple]);
  return messageById(db, actor, conversationId, messageId);
}

/** Membres en écriture et époque, pour la rotation Megolm (+1 à chaque départ et retour). */
export async function conversationMembers(db: PoolClient, actor: MessagingActor, conversationId: string) {
  await canRead(db, actor, conversationId);
  // Une seule instruction fournit le même snapshot MVCC aux destinataires et à leur époque.
  const snapshot = await db.query<{ members: { personId: string }[]; membersEpoch: string }>(`SELECT
    c.members_epoch AS "membersEpoch",
    COALESCE((SELECT json_agg(json_build_object('personId', m.person_id) ORDER BY m.person_id)
      FROM drivy.messaging_conversation_members($1,$2,$3) m), '[]'::json) AS members
    FROM drivy.messaging_conversation c WHERE c.school_id=$1 AND c.id=$3`,
  [actor.schoolId, actor.personId, conversationId]);
  if (!snapshot.rows[0]) throw notFound();
  return { members: snapshot.rows[0].members, membersEpoch: safeSequence(snapshot.rows[0].membersEpoch) };
}

export async function deleteMessage(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string, scope: 'me' | 'everyone') {
  if (scope === 'everyone') {
    await lockForWrite(db, actor, conversationId, [], false);
    await db.query('SELECT drivy.messaging_delete_for_everyone($1,$2,$3)', [actor.schoolId, conversationId, messageId]);
  } else {
    await canRead(db, actor, conversationId);
    // Supprimer pour soi reste possible en lecture seule : cela ne touche que sa propre vue.
    const inserted = await db.query(`INSERT INTO drivy.messaging_hidden_message(school_id,conversation_id,message_id,person_id)
      SELECT $1,$2,$3,$4 WHERE EXISTS(SELECT 1 FROM drivy.messaging_message m WHERE m.school_id=$1 AND m.conversation_id=$2 AND m.id=$3)
      ON CONFLICT DO NOTHING`, [actor.schoolId, conversationId, messageId, actor.personId]);
    if (inserted.rowCount === 0) {
      const hidden = await db.query('SELECT 1 FROM drivy.messaging_hidden_message WHERE school_id=$1 AND message_id=$2 AND person_id=$3',
        [actor.schoolId, messageId, actor.personId]);
      if (!hidden.rows[0]) throw notFound();
    }
  }
  return { messageId, scope };
}

export async function setReaction(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string, emoji: string, active: boolean) {
  if (!(reactionPalette as readonly string[]).includes(emoji)) throw new ApiError(400, 'INVALID_REQUEST', 'Réaction invalide.');
  await lockForWrite(db, actor, conversationId);
  const open = await db.query<{ open: boolean }>('SELECT drivy.messaging_message_open($1,$2,$3,$4) AS open',
    [actor.schoolId, actor.personId, conversationId, messageId]);
  if (open.rows[0]?.open !== true) throw notFound();
  if (active) await db.query(`INSERT INTO drivy.messaging_reaction(school_id,conversation_id,message_id,person_id,emoji)
    VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, [actor.schoolId, conversationId, messageId, actor.personId, emoji]);
  else await db.query(`DELETE FROM drivy.messaging_reaction WHERE school_id=$1 AND conversation_id=$2 AND message_id=$3
    AND person_id=$4 AND emoji=$5`, [actor.schoolId, conversationId, messageId, actor.personId, emoji]);
  return { messageId, emoji, active };
}
export async function setPinned(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string, pinned: boolean) {
  await lockForWrite(db, actor, conversationId);
  await db.query('SELECT drivy.messaging_set_pinned($1,$2,$3,$4)', [actor.schoolId, conversationId, messageId, pinned]);
  return { messageId, pinned };
}
export async function setPollVotes(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string, optionIndexes: number[]) {
  if (optionIndexes.length > 12 || optionIndexes.some(index => !Number.isSafeInteger(index) || index < 0 || index > 11)
    || new Set(optionIndexes).size !== optionIndexes.length) throw new ApiError(400, 'INVALID_REQUEST', 'Vote invalide.');
  await lockForWrite(db, actor, conversationId);
  await db.query('SELECT drivy.messaging_set_poll_votes($1,$2,$3,$4::integer[])', [actor.schoolId, conversationId, messageId, optionIndexes]);
  return { messageId, optionIndexes: [...optionIndexes].sort((a, b) => a - b) };
}
export async function closePoll(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string) {
  await lockForWrite(db, actor, conversationId);
  await db.query('SELECT drivy.messaging_close_poll($1,$2,$3)', [actor.schoolId, conversationId, messageId]);
  return { messageId, closed: true };
}

/** Administration du général : contrôle et audit dans la base, sous le verrou du général. */
export async function setGroupAdmin(db: PoolClient, actor: MessagingActor, personId: string, admin: boolean) {
  assertContext(actor);
  await db.query('SELECT drivy.messaging_set_group_admin($1,$2,$3)', [actor.schoolId, personId, admin]);
  return { personId, isGroupAdmin: admin };
}
export async function removeGeneralMember(db: PoolClient, actor: MessagingActor, personId: string) {
  assertContext(actor);
  await db.query('SELECT drivy.messaging_remove_general_member($1,$2)', [actor.schoolId, personId]);
  return { personId, removed: true };
}
/** Réintégration : nouveau lien, lecture limitée à ce qui suit, époque des membres +1. */
export async function reinstateGeneralMember(db: PoolClient, actor: MessagingActor, personId: string) {
  assertContext(actor);
  await db.query('SELECT drivy.messaging_reinstate_general_member($1,$2)', [actor.schoolId, personId]);
  return { personId, removed: false };
}

export interface ReportItemInput { messageId: string; ciphertext: OpaqueEnvelope }
export const reportStatuses = ['OPEN', 'HANDLED', 'DISMISSED'] as const;
export type ReportStatus = typeof reportStatuses[number];
/** Cadence documentée dans docs/implementation/messaging-reports-77.md, constantes volontairement simples. */
export const reportLimits = { perConversationPerHour: 3, perSchoolPerDay: 10 } as const;
export const reportRateLimited = () => new ApiError(429, 'REPORT_RATE_LIMITED',
  'Trop de signalements envoyés en peu de temps. Réessaie plus tard.');

/** Seuils de cadence, calculés sous le verrou de la personne : un renvoi identique n'arrive jamais jusqu'ici. */
async function enforceReportCadence(db: PoolClient, actor: MessagingActor, conversationId: string) {
  const counts = await db.query<{ hour: number; day: number }>(`SELECT
    count(*) FILTER(WHERE conversation_id=$3 AND created_at>now()-interval '1 hour')::int AS hour,
    count(*) FILTER(WHERE created_at>now()-interval '24 hours')::int AS day
    FROM drivy.messaging_report WHERE school_id=$1 AND reporter_person_id=$2 AND created_at>now()-interval '24 hours'`,
    [actor.schoolId, actor.personId, conversationId]);
  const row = counts.rows[0];
  if ((row?.hour ?? 0) >= reportLimits.perConversationPerHour || (row?.day ?? 0) >= reportLimits.perSchoolPerDay) throw reportRateLimited();
}

/** Signalement idempotent par clientReportId : seuls les messages choisis, rechiffrés pour les administrateurs de l'école. */
export async function createReport(db: PoolClient, actor: MessagingActor, clientReportId: string, conversationId: string, items: ReportItemInput[]) {
  if (!uuidPattern.test(clientReportId) || items.length < 1 || items.length > 50
    || new Set(items.map(item => item.messageId.toLowerCase())).size !== items.length
    || items.some(item => !uuidPattern.test(item.messageId) || !validEnvelope(item.ciphertext)))
    throw new ApiError(400, 'INVALID_REQUEST', 'Signalement invalide.');
  await canRead(db, actor, conversationId);
  const normalized = [...items].sort((a, b) => a.messageId.toLowerCase().localeCompare(b.messageId.toLowerCase()));
  const fingerprint = createHash('sha256').update(JSON.stringify([conversationId.toLowerCase(),
    normalized.map(item => [item.messageId.toLowerCase(), item.ciphertext])])).digest('hex');
  // Un signalant à la fois : l'idempotence et la cadence se lisent sous le même verrou.
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`messaging.report|${actor.schoolId}|${actor.personId}`]);
  const prior = await db.query<{ id: string; fingerprint: string }>(`SELECT id,fingerprint FROM drivy.messaging_report
    WHERE school_id=$1 AND reporter_person_id=$2 AND client_report_id=$3`, [actor.schoolId, actor.personId, clientReportId]);
  if (prior.rows[0]) {
    if (prior.rows[0].fingerprint !== fingerprint) throw new ApiError(409, 'REPORT_CONFLICT', 'Ce signalement a déjà été envoyé avec un autre contenu.');
    return { reportId: prior.rows[0].id, itemCount: items.length };
  }
  await enforceReportCadence(db, actor, conversationId);
  const kind = await db.query<{ kind: string }>('SELECT kind FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2', [actor.schoolId, conversationId]);
  const reportId = randomUUID();
  const inserted = await db.query<{ id: string }>(`INSERT INTO drivy.messaging_report(id,school_id,conversation_id,reporter_person_id,client_report_id,fingerprint,conversation_kind)
    VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(school_id,reporter_person_id,client_report_id) DO NOTHING RETURNING id`,
    [reportId, actor.schoolId, conversationId, actor.personId, clientReportId, fingerprint, kind.rows[0]?.kind ?? null]);
  if (!inserted.rows[0]) throw new ApiError(409, 'CONCURRENT_REQUEST', 'Une requête identique est en cours. Réessayez.');
  for (const item of normalized) {
    // La RLS n'accepte que les messages de la plage lisible du signalant. Auteur, rang et date : contexte, jamais le contenu.
    const result = await db.query(`INSERT INTO drivy.messaging_report_item(school_id,report_id,message_id,envelope,sender_person_id,message_sequence,message_accepted_at)
      SELECT $1,$2,m.id,$4::jsonb,m.sender_person_id,m.sequence,m.created_at FROM drivy.messaging_message m
      WHERE m.school_id=$1 AND m.conversation_id=$5 AND m.id=$3`,
      [actor.schoolId, reportId, item.messageId, JSON.stringify(item.ciphertext), conversationId]);
    if (result.rowCount !== 1) throw notFound();
  }
  return { reportId, itemCount: items.length };
}

interface ReportRow { id: string; conversationId: string; conversationKind: string | null; reporterPersonId: string; createdAt: string;
  status: ReportStatus; statusUpdatedAt: string;
  items: { messageId: string; ciphertext: OpaqueEnvelope; senderPersonId: string | null; sequence: string | number | null; acceptedAt: string | null }[];
  history: { actorPersonId: string; fromStatus: ReportStatus; toStatus: ReportStatus; createdAt: string }[] }

async function assertSchoolAdmin(db: PoolClient, actor: MessagingActor) {
  assertContext(actor);
  const admin = await db.query<{ admin: boolean }>('SELECT drivy.messaging_actor_school_admin($1) AS admin', [actor.schoolId]);
  if (admin.rows[0]?.admin !== true) throw forbidden();
}

/** Lignes de la boîte avec noms (signalant, auteurs, personnes ayant changé un statut) ; contenu toujours chiffré. */
async function reportView(db: PoolClient, actor: MessagingActor, where: string, params: unknown[], limit: number) {
  const result = await db.query<ReportRow>(`SELECT r.id,r.conversation_id AS "conversationId",r.conversation_kind AS "conversationKind",
    r.reporter_person_id AS "reporterPersonId",r.created_at AS "createdAt",r.status,r.status_updated_at AS "statusUpdatedAt",
    COALESCE((SELECT json_agg(json_build_object('messageId',i.message_id,'ciphertext',i.envelope,'senderPersonId',i.sender_person_id,
      'sequence',i.message_sequence,'acceptedAt',i.message_accepted_at) ORDER BY i.message_sequence NULLS LAST,i.message_id)
      FROM drivy.messaging_report_item i WHERE i.school_id=r.school_id AND i.report_id=r.id),'[]'::json) AS items,
    COALESCE((SELECT json_agg(json_build_object('actorPersonId',e.actor_person_id,'fromStatus',e.from_status,'toStatus',e.to_status,
      'createdAt',e.created_at) ORDER BY e.id) FROM drivy.messaging_report_status_event e
      WHERE e.school_id=r.school_id AND e.report_id=r.id),'[]'::json) AS history
    FROM drivy.messaging_report r WHERE r.school_id=$1 AND ${where} ORDER BY r.created_at DESC,r.id DESC LIMIT ${limit}`,
    [actor.schoolId, ...params]);
  const names = new Map((await db.query<{ personId: string; displayName: string }>(
    'SELECT person_id AS "personId",display_name AS "displayName" FROM drivy.messaging_report_people($1)', [actor.schoolId]))
    .rows.map(row => [row.personId.toLowerCase(), row.displayName]));
  const name = (person: string | null) => (person ? names.get(person.toLowerCase()) ?? null : null);
  return result.rows.map(row => ({ ...row,
    reporterDisplayName: name(row.reporterPersonId),
    items: row.items.map(item => ({ ...item, sequence: item.sequence === null ? null : safeSequence(item.sequence),
      senderDisplayName: name(item.senderPersonId) })),
    history: row.history.map(event => ({ ...event, actorDisplayName: name(event.actorPersonId) })) }));
}

/** Boîte des administrateurs de l'école. Contenu toujours chiffré ; du plus récent au plus ancien, filtre de statut optionnel. */
export async function listReports(db: PoolClient, actor: MessagingActor, limit = 50, before?: string, status?: ReportStatus) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, 'INVALID_REQUEST', 'Limite invalide.');
  await assertSchoolAdmin(db, actor);
  const rows = await reportView(db, actor,
    `($2::text IS NULL OR r.status=$2) AND ($3::uuid IS NULL OR (r.created_at,r.id)<(SELECT b.created_at,b.id FROM drivy.messaging_report b
      WHERE b.school_id=r.school_id AND b.id=$3))`, [status ?? null, before ?? null], limit + 1);
  const open = await db.query<{ count: number }>("SELECT count(*)::int AS count FROM drivy.messaging_report WHERE school_id=$1 AND status='OPEN'", [actor.schoolId]);
  return { reports: rows.slice(0, limit), nextCursor: rows.length > limit ? rows[limit - 1]!.id : null, openCount: open.rows[0]?.count ?? 0 };
}

/** Changement de statut par un administrateur : statut attendu comparé sous verrou, événement écrit avec l'auteur. */
export async function setReportStatus(db: PoolClient, actor: MessagingActor, reportId: string, status: ReportStatus, expectedStatus: ReportStatus) {
  if (!uuidPattern.test(reportId) || !reportStatuses.includes(status) || !reportStatuses.includes(expectedStatus))
    throw new ApiError(400, 'INVALID_REQUEST', 'Statut invalide.');
  await assertSchoolAdmin(db, actor);
  await db.query('SELECT drivy.messaging_set_report_status($1,$2,$3,$4)', [actor.schoolId, reportId, status, expectedStatus]);
  const [report] = await reportView(db, actor, 'r.id=$2', [reportId], 1);
  if (!report) throw notFound();
  return { reportId: report.id, status: report.status, statusUpdatedAt: report.statusUpdatedAt, history: report.history };
}

/** Progression personnelle ; visible des participants via readStates (décision 7), plafonnée à leur propre plage. */
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
