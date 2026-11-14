import { createHmac, hkdfSync, randomBytes } from 'node:crypto';
import { z } from 'zod';
import { openingIdentity } from './school-opening-model.js';

/**
 * Niveau unique de droits commerciaux de la plateforme (R01-T01). Un opérateur administre la relation commerciale
 * avec les écoles ; il n'a aucun rôle scolaire et ne lit ni dossiers, ni trajets, ni messages.
 */
export const platformLevel = 'COMMERCIAL' as const;
export const platformRights = ['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'MANAGE_OFFERS', 'READ_COMMERCIAL_JOURNAL'] as const;
/** Ce que le niveau ne donne jamais : affiché avant l'acceptation d'une invitation, et vérifié par les tests. */
export const platformExcludedAccess = ['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES'] as const;
export type PlatformRight = (typeof platformRights)[number];

export const platformRightsView = () => ({ level: platformLevel, rights: [...platformRights], notGranted: [...platformExcludedAccess] });

/** Premiers comptes : configuration privée de l'exploitation, jamais publiée. Au plus dix identités. */
export const platformBootstrapEntry = openingIdentity.extend({ displayName: z.string().trim().min(1).max(200).optional() }).strict();
export type PlatformBootstrapEntry = z.infer<typeof platformBootstrapEntry>;
export function readPlatformBootstrap(env: NodeJS.ProcessEnv = process.env): PlatformBootstrapEntry[] {
  return z.array(platformBootstrapEntry).max(10).parse(JSON.parse(env.PLATFORM_OPERATORS_BOOTSTRAP_JSON ?? '[]'));
}

// Code d'accès à la plateforme : 10 caractères (32 symboles sans O/0/I/1, soit 50 bits), formé XXXXX-XXXXX.
// Le format diffère des codes d'ouverture (XXXX-XXXX) et d'invitation scolaire : un code n'est jamais résolu à la place d'un autre.
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const platformCodePattern = /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/;
export function generatePlatformCode(): string {
  const chars = Array.from(randomBytes(10), byte => alphabet[byte % 32]).join('');
  return `${chars.slice(0, 5)}-${chars.slice(5)}`;
}
export const normalizePlatformCode = (code: string) => code.trim().toUpperCase().replace(/[\s_]/g, '').replace(/^([A-Z0-9]{5})-?([A-Z0-9]{5})$/, '$1-$2');
export const platformCodeKeyLabel = 'drivy/platform-operator-invitation/v1';
/** Empreinte à clé serveur, dérivée avec une étiquette propre : la même chaîne n'a pas la même empreinte qu'un code d'école. */
export function platformCodeHasher(cursorSecret: string, dedicatedSecret?: string): (code: string) => string {
  const key = Buffer.from(hkdfSync('sha256', dedicatedSecret ?? cursorSecret, Buffer.alloc(0), platformCodeKeyLabel, 32));
  return code => createHmac('sha256', key).update(normalizePlatformCode(code)).digest('hex');
}

const operationId = z.uuid();
export const platformCode = z.string().max(40).describe('Code d’accès XXXXX-XXXXX (alphabet sans O, 0, I, 1) ; normalisé par le service, jamais conservé en clair.')
  .transform(normalizePlatformCode).pipe(z.string().regex(platformCodePattern));
export const platformEmail = z.string().trim().max(254).describe('Adresse e-mail de l’invité, normalisée en minuscules par le service.').transform(value => value.normalize('NFC').toLowerCase()).pipe(z.email());
export const operationBody = z.object({ operationId }).strict();
export const createInvitationBody = z.object({
  operationId, code: platformCode, email: platformEmail, validityDays: z.number().int().min(1).max(14).optional(),
}).strict();
export const previewInvitationBody = z.object({ code: platformCode }).strict();
export const acceptInvitationBody = z.object({ operationId, code: platformCode }).strict();
export const journalQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  cursor: z.string().max(6000).optional(),
  schoolId: z.uuid().optional(),
  result: z.enum(['SUCCESS', 'REFUSED']).optional(),
}).strict();

export interface OperatorRow {
  id: string; issuer: string; subject: string; display_name: string; contact_email: string | null; level: 'COMMERCIAL';
  status: 'ACTIVE' | 'REVOKED'; added_via: 'BOOTSTRAP' | 'INVITATION'; invitation_id: string | null; version: number;
  created_at: Date; revoked_at: Date | null; revoked_by: string | null;
}
export interface InvitationRow {
  id: string; code_hash: string; invitee_email: string; level: 'COMMERCIAL'; status: 'AVAILABLE' | 'USED' | 'REVOKED'; version: number;
  created_by: string; created_at: Date; expires_at: Date; revoked_at: Date | null; revoked_by: string | null; used_at: Date | null; used_by: string | null;
  created_by_name?: string;
  /** Renseigné seulement par la lecture d'un code (aperçu, acceptation) : l'auteur de l'invitation fait encore partie de l'équipe. */
  creator_active?: boolean;
}
export interface JournalRow {
  id: string; occurred_at: Date; actor_kind: 'OPERATOR' | 'SYSTEM'; actor_operator_id: string | null; actor_name: string; action: string;
  result: 'SUCCESS' | 'REFUSED'; reason_code: string | null; school_id: string | null; subject_type: string | null; subject_id: string | null;
  operation_id: string | null; changes: Record<string, unknown>;
}

/** a***@domaine : l'adresse complète n'est jamais renvoyée aux listes ni écrite au journal. */
export function maskEmail(address: string): string {
  const at = address.lastIndexOf('@');
  if (at < 1) return '***';
  return `${address[0]}***${address.slice(at)}`;
}

export const operatorProjection = (row: OperatorRow, selfId: string) => ({
  id: row.id, displayName: row.display_name, maskedEmail: row.contact_email ? maskEmail(row.contact_email) : null, level: row.level,
  status: row.status, addedVia: row.added_via, joinedAt: row.created_at.toISOString(), revokedAt: row.revoked_at?.toISOString() ?? null,
  version: row.version, self: row.id === selfId,
});
export const invitationStatus = (row: InvitationRow, now = Date.now()) =>
  row.status === 'AVAILABLE' && row.expires_at.getTime() <= now ? 'EXPIRED' as const : row.status;
export const invitationProjection = (row: InvitationRow) => ({
  id: row.id, status: invitationStatus(row), level: row.level, maskedEmail: maskEmail(row.invitee_email),
  createdAt: row.created_at.toISOString(), expiresAt: row.expires_at.toISOString(), version: row.version,
  usedAt: row.used_at?.toISOString() ?? null, revokedAt: row.revoked_at?.toISOString() ?? null,
  createdByName: row.created_by_name ?? null,
});
export const journalProjection = (row: JournalRow) => ({
  id: row.id, occurredAt: row.occurred_at.toISOString(), actorKind: row.actor_kind, actorName: row.actor_name, action: row.action,
  result: row.result, reasonCode: row.reason_code, schoolId: row.school_id,
  subject: row.subject_type && row.subject_id ? { type: row.subject_type, id: row.subject_id } : null,
  operationId: row.operation_id, changes: row.changes,
});
