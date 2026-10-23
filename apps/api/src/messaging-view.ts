import type { PoolClient } from 'pg';
import { ApiError, forbidden, notFound } from './errors.js';

/** Métadonnées visibles du serveur (décision 1). Le contenu reste une enveloppe opaque, null après suppression pour tout le monde. */
export interface MessageReaction { emoji: string; personIds: string[] }
export interface MessagePoll { optionCount: number; multiple: boolean; closed: boolean; creatorId: string;
  votes: { optionIndex: number; personIds: string[] }[] }
export interface MessageView { id: string; schoolId: string; conversationId: string; sequence: number; clientMessageId: string;
  senderId: string; ciphertext: { scheme: string; keyId: string; payload: string } | null; mentionPersonIds: string[]; acceptedAt: string;
  replyToMessageId: string | null; deletedForEveryone: boolean; pinned: boolean; reactions: MessageReaction[]; poll: MessagePoll | null }

/** $1 school, $2 actor. Alias de table : m. Les politiques RLS bornent déjà la lecture à la plage du lien. */
export const messageColumns = `m.id,m.school_id AS "schoolId",m.conversation_id AS "conversationId",m.sequence,
  m.intent_id AS "clientMessageId",m.sender_person_id AS "senderId",m.envelope AS ciphertext,
  m.mention_person_ids AS "mentionPersonIds",m.created_at AS "acceptedAt",
  m.reply_to_message_id AS "replyToMessageId",(m.deleted_at IS NOT NULL) AS "deletedForEveryone",(m.pinned_at IS NOT NULL) AS pinned,
  COALESCE((SELECT json_agg(json_build_object('emoji',r.emoji,'personIds',r.ids) ORDER BY r.emoji)
    FROM (SELECT emoji,array_agg(person_id ORDER BY person_id) AS ids FROM drivy.messaging_reaction
      WHERE school_id=m.school_id AND message_id=m.id GROUP BY emoji) r),'[]'::json) AS reactions,
  (SELECT json_build_object('optionCount',p.option_count,'multiple',p.multiple,'closed',p.closed_at IS NOT NULL,
      'creatorId',p.creator_person_id,'votes',COALESCE((SELECT json_agg(json_build_object('optionIndex',v.option_index,'personIds',v.ids) ORDER BY v.option_index)
        FROM (SELECT option_index,array_agg(person_id ORDER BY person_id) AS ids FROM drivy.messaging_poll_vote
          WHERE message_id=p.message_id GROUP BY option_index) v),'[]'::json))
    FROM drivy.messaging_poll p WHERE p.message_id=m.id) AS poll`;
/** Filtre « supprimé pour moi ». */
export const notHiddenForActor = `NOT EXISTS(SELECT 1 FROM drivy.messaging_hidden_message h
  WHERE h.school_id=m.school_id AND h.message_id=m.id AND h.person_id=$2)`;

export function safeSequence(value: string | number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new ApiError(503, 'SERVICE_UNAVAILABLE', 'Service temporairement indisponible.');
  return parsed;
}
export function toView(row: MessageView): MessageView {
  return { ...row, sequence: safeSequence(row.sequence), ciphertext: row.deletedForEveryone ? null : row.ciphertext };
}

/** Traduit les refus levés par les fonctions SQL et la RLS. Aucune donnée de la requête n'est reprise. */
export function mapDatabaseError(error: unknown): unknown {
  const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code?: unknown }).code : undefined;
  if (code === 'DV403' || code === '42501') return forbidden();
  if (code === 'DV404') return notFound();
  if (code === '22023') return new ApiError(400, 'INVALID_REQUEST', 'Requête invalide.');
  if (code === 'DV409') return new ApiError(409, 'MESSAGING_STATE_CONFLICT', 'La conversation a changé. Actualisez avant de réessayer.');
  // Course perdue sur une clé d'unicité : le renvoi de la même requête est idempotent.
  if (code === '23505' || code === '40001' || code === '40P01')
    return new ApiError(409, 'CONCURRENT_REQUEST', 'Une requête identique est en cours. Réessayez.');
  return error;
}

/** Applique arrivées, départs et retours ; renvoie l'époque des membres. */
export async function syncLinks(db: PoolClient, schoolId: string, conversationId: string): Promise<number> {
  const result = await db.query<{ epoch: string }>('SELECT drivy.messaging_sync_links($1,$2) AS epoch', [schoolId, conversationId]);
  return safeSequence(result.rows[0]?.epoch ?? 0);
}
