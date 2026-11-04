import type { PoolClient } from 'pg';
import { createHash } from 'node:crypto';
import { ApiError, forbidden } from './errors.js';
import { deviceIdPattern } from './messaging-keys.js';
import { syncLinks } from './messaging-view.js';
import { lockRights, type MessagingActor } from './messaging.js';
import { mediaMaxBytes, mediaReceiptStates, type MediaReceiptState } from './messaging-media-contract.js';

/**
 * Médias de la messagerie : le serveur ne voit que des octets chiffrés opaques, une taille et un SHA-256 du chiffré.
 * Aucun nom, type MIME, légende, clé, IV ni miniature n'est stocké, journalisé ou renvoyé ici.
 * La limite et les états de reçu viennent du contrat exécutable, réexportés pour les appelants historiques.
 */
export { mediaMaxBytes, mediaReceiptStates };
export type { MediaReceiptState };
/** Limite de corps de la route média : plafond + marge d'en-têtes, sans toucher au bodyLimit global de l'API. */
export const mediaBodyLimit = mediaMaxBytes + 8_192;
export const mediaStates = ['UPLOADED', 'ATTACHED', 'PURGED'] as const;
export type MediaState = typeof mediaStates[number];

/** Intention média portée par le message : l'identifiant et la taille déclarée entrent dans l'empreinte d'idempotence. */
export interface MediaIntent { mediaId: string; byteSize: number }
export interface MediaReceipt { mediaId: string; byteSize: number; sha256: string; state: MediaReceiptState }
export interface MediaDownload { bytes: Buffer; byteSize: number; sha256: string }

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const mediaNotFound = () => new ApiError(404, 'MEDIA_NOT_FOUND', 'Pièce jointe introuvable.');
export const invalidMedia = () => new ApiError(400, 'INVALID_MEDIA', 'Pièce jointe invalide.');
export const mediaDeviceRequired = () => new ApiError(403, 'MESSAGING_DEVICE_REQUIRED', 'Appareil de messagerie requis.');
export const mediaPayloadTooLarge = () => new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Le contenu envoyé est trop volumineux.');

export function mediaId(value: string): string {
  if (!uuidPattern.test(value)) throw invalidMedia();
  return value.toLowerCase();
}

export function mediaSize(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > mediaMaxBytes) throw invalidMedia();
  return value;
}

/** SHA-256 du chiffré seulement : aucun hash du clair n'est calculé, conservé ou comparé côté serveur. */
export const ciphertextSha256 = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex');

/**
 * Appareil déclaré par X-Drivy-Device-Id : identifiant, pas preuve de possession cryptographique. La révocation
 * garantit le refus de ce deviceId, pas l'impossibilité de se présenter avec un autre appareil actif du compte.
 */
export async function requireActiveDevice(db: PoolClient, actor: MessagingActor, deviceId: string): Promise<void> {
  if (!deviceIdPattern.test(deviceId)) throw mediaDeviceRequired();
  const active = await db.query(`SELECT 1 FROM drivy.messaging_device
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND revoked_at IS NULL`, [actor.schoolId, actor.personId, deviceId]);
  if (!active.rows[0]) throw mediaDeviceRequired();
}

/** Lecture de la conversation (404 hors périmètre), sources de droits verrouillées, puis verrou de conversation.
 *  Ordre de la fondation : droits → conversation → message → média. */
async function lockConversationForWrite(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<void> {
  const visible = await db.query<{ allowed: boolean }>(
    'SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (visible.rows[0]?.allowed !== true) throw mediaNotFound();
  // Les sources d'autorisation sont tenues jusqu'au COMMIT, comme pour l'envoi d'un message : une fin
  // d'éligibilité ne peut pas se committer entre le contrôle de droit et l'écriture durable du média.
  await lockRights(db, actor, conversationId);
  // Le droit d'écriture est relu APRÈS le verrou des sources, et avant le verrou de conversation : une fin
  // d'éligibilité déjà commitée répond 403 (jamais un 404 de conversation), et le verrou `FOR UPDATE` ne peut
  // pas être filtré par la politique RLS UPDATE de `messaging_conversation`, qui exige `messaging_can_write`.
  if (!(await canWrite(db, actor, conversationId))) throw forbidden();
  const locked = await db.query('SELECT 1 FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2 FOR UPDATE',
    [actor.schoolId, conversationId]);
  if (!locked.rows[0]) throw mediaNotFound();
  await syncLinks(db, actor.schoolId, conversationId);
  // Les liens ont pu être coupés par la synchronisation : le droit est recontrôlé avant toute écriture.
  if (!(await canWrite(db, actor, conversationId))) throw forbidden();
}

async function canWrite(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<boolean> {
  const write = await db.query<{ allowed: boolean }>(
    'SELECT drivy.messaging_can_write($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  return write.rows[0]?.allowed === true;
}

async function assertConversationVisible(db: PoolClient, actor: MessagingActor, conversationId: string): Promise<void> {
  const visible = await db.query<{ allowed: boolean }>(
    'SELECT drivy.messaging_conversation_allowed($1,$2,$3) AS allowed', [actor.schoolId, actor.personId, conversationId]);
  if (visible.rows[0]?.allowed !== true) throw mediaNotFound();
}

interface StoredMedia { sha256: string; byte_size: string; message_id: string | null; conversation_id: string; purged: boolean }

/**
 * Dépôt idempotent : un dépôt identique est reconnu (aucune écriture, created_at inchangé), y compris après attache.
 * Un identifiant déjà purgé n'est jamais ressuscité ; un identifiant pris par un média invisible reste un 404 uniforme.
 */
export async function uploadMedia(db: PoolClient, actor: MessagingActor, conversationId: string, mediaIdValue: string,
  bytes: Buffer): Promise<MediaReceipt> {
  const target = mediaId(mediaIdValue);
  if (bytes.length < 1) throw invalidMedia();
  if (bytes.length > mediaMaxBytes) throw mediaPayloadTooLarge();
  const sha256 = ciphertextSha256(bytes);
  await lockConversationForWrite(db, actor, conversationId);
  // Le verrou de ligne passe par une fonction SECURITY DEFINER : le rôle applicatif n'a aucun privilège UPDATE.
  const existing = await db.query<StoredMedia>(
    'SELECT sha256,byte_size,message_id,conversation_id,purged FROM drivy.messaging_lock_media($1,$2)',
    [actor.schoolId, target]);
  const row = existing.rows[0];
  if (!row) {
    const inserted = await db.query(`INSERT INTO drivy.messaging_media(id,school_id,conversation_id,uploader_person_id,
      byte_size,ciphertext_sha256,ciphertext) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING RETURNING id`,
      [target, actor.schoolId, conversationId, actor.personId, bytes.length, sha256, bytes]);
    if (inserted.rowCount !== 1) throw mediaNotFound();
    return { mediaId: target, byteSize: bytes.length, sha256, state: 'UPLOADED' };
  }
  if (row.conversation_id.toLowerCase() !== conversationId.toLowerCase()) throw mediaNotFound();
  if (row.purged) throw new ApiError(409, 'MEDIA_PURGED', 'Cette pièce jointe a été supprimée et ne peut pas être réutilisée.');
  if (row.sha256 !== sha256 || Number(row.byte_size) !== bytes.length)
    throw new ApiError(409, 'MEDIA_INTENT_CONFLICT', 'Cet identifiant a déjà servi pour d’autres octets.');
  return { mediaId: target, byteSize: Number(row.byte_size), sha256: row.sha256, state: row.message_id ? 'ATTACHED' : 'UPLOADED' };
}

/**
 * Téléchargement : média rattaché, octets présents, message non supprimé, plage de séquence lisible, message non masqué.
 * Toute autre situation répond le même 404, sans révéler hash ni taille.
 */
export async function downloadMedia(db: PoolClient, actor: MessagingActor, conversationId: string,
  mediaIdValue: string): Promise<MediaDownload> {
  const target = mediaId(mediaIdValue);
  await assertConversationVisible(db, actor, conversationId);
  const result = await db.query<{ bytes: Buffer; sha256: string; byteSize: string }>(`SELECT
    md.ciphertext AS bytes,md.ciphertext_sha256 AS sha256,md.byte_size AS "byteSize"
    FROM drivy.messaging_media md
    JOIN drivy.messaging_message m ON m.school_id=md.school_id AND m.id=md.message_id
    WHERE md.school_id=$1 AND md.conversation_id=$2 AND md.id=$3
      AND md.message_id IS NOT NULL AND md.ciphertext IS NOT NULL AND md.purged_at IS NULL
      AND m.deleted_at IS NULL AND drivy.messaging_readable_sequence($1,$4,$2,m.sequence)
      AND NOT EXISTS(SELECT 1 FROM drivy.messaging_hidden_message h
        WHERE h.school_id=m.school_id AND h.message_id=m.id AND h.person_id=$4)`,
    [actor.schoolId, conversationId, target, actor.personId]);
  const row = result.rows[0];
  if (!row) throw mediaNotFound();
  return { bytes: row.bytes, byteSize: Number(row.byteSize), sha256: row.sha256 };
}

/** Annulation avant attache : la conversation de l'URL fait partie du périmètre nommé. La ligne média est verrouillée
 *  et sa conversation comparée sous verrou avant toute purge : un média d'une autre conversation répond le même
 *  404 uniforme, quel que soit son état (UPLOADED, ATTACHED ou PURGED), sans effet ni entrée de journal. */
export async function cancelMedia(db: PoolClient, actor: MessagingActor, conversationId: string, mediaIdValue: string) {
  const target = mediaId(mediaIdValue);
  await lockConversationForWrite(db, actor, conversationId);
  const stored = await db.query<{ conversation_id: string }>(
    'SELECT conversation_id FROM drivy.messaging_lock_media($1,$2)', [actor.schoolId, target]);
  const row = stored.rows[0];
  if (!row || row.conversation_id.toLowerCase() !== conversationId.toLowerCase()) throw mediaNotFound();
  await db.query('SELECT drivy.messaging_purge_media($1,$2,$3)', [actor.schoolId, target, 'CANCELLED']);
  return { mediaId: target, deleted: true };
}

/** Attache transactionnelle, appelée sous le verrou de conversation de l'envoi : message inséré puis média lié. */
export async function attachMedia(db: PoolClient, actor: MessagingActor, conversationId: string, messageId: string,
  intent: MediaIntent): Promise<void> {
  await db.query('SELECT drivy.messaging_attach_media($1,$2,$3,$4,$5)',
    [actor.schoolId, conversationId, mediaId(intent.mediaId), messageId, mediaSize(intent.byteSize)]);
}
