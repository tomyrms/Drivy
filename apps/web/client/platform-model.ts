import { z } from 'zod';
import { errorMessage, RequestFailure } from './protocol';

/**
 * Console des opérateurs de la plateforme (R01-T01). Ces schémas décrivent ce que le relais /app/bff/platform/* renvoie ;
 * ils sont volontairement stricts sur les formes et tolérants sur les valeurs que les lots suivants ajouteront.
 */
const id = z.string().uuid();
const iso = z.string().datetime({ offset: true });
const token = z.string().regex(/^[A-Z][A-Z0-9_]{2,63}$/);

export const platformOperatorSchema = z.object({
  id, displayName: z.string().max(200), maskedEmail: z.string().max(254).nullable(), level: token,
  status: z.enum(['ACTIVE', 'REVOKED']), addedVia: z.enum(['BOOTSTRAP', 'INVITATION']), joinedAt: iso, revokedAt: iso.nullable(),
  version: z.number().int().positive(), self: z.boolean(),
});
export const platformInvitationSchema = z.object({
  id, status: z.enum(['AVAILABLE', 'USED', 'REVOKED', 'EXPIRED']), level: token, maskedEmail: z.string().max(254),
  createdAt: iso, expiresAt: iso, version: z.number().int().positive(), usedAt: iso.nullable(), revokedAt: iso.nullable(), createdByName: z.string().max(200).nullable(),
});
export const platformJournalSchema = z.object({
  id, occurredAt: iso, actorKind: z.enum(['OPERATOR', 'SYSTEM']), actorName: z.string().max(200), action: token,
  result: z.enum(['SUCCESS', 'REFUSED']), reasonCode: token.nullable(), schoolId: id.nullable(),
  subject: z.object({ type: z.string().max(80), id: z.string().max(80) }).nullable(), operationId: id.nullable(), changes: z.record(z.string(), z.unknown()),
});
const rights = { level: token, rights: z.array(token).max(40), notGranted: z.array(token).max(40) };

export const platformMeResult = z.object({ data: z.object({ operator: platformOperatorSchema, ...rights }) });
export const platformOperatorsResult = z.object({ data: z.object({ items: z.array(platformOperatorSchema).max(200) }) });
export const platformOperatorResult = z.object({ data: platformOperatorSchema });
export const platformInvitationsResult = z.object({
  data: z.object({ items: z.array(platformInvitationSchema).max(100) }),
  /** Une invitation créée dont le code n'a pas été confié : de quoi la reprendre, jamais le code. */
  pending: z.object({ operationId: id, email: z.string().max(254), validityDays: z.number().int().min(1).max(14).optional() }).optional(),
});
export const platformIssuedResult = z.object({ data: platformInvitationSchema, code: z.string().regex(/^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/) });
export const platformInvitationResult = z.object({ data: platformInvitationSchema });
export const platformJournalResult = z.object({ data: z.object({ items: z.array(platformJournalSchema).max(100), nextCursor: z.string().max(6000).nullable() }) });
export const platformPreviewResult = z.object({
  confirmation: z.string().min(1).max(100),
  data: z.object({ status: z.literal('AVAILABLE'), maskedEmail: z.string().max(254), expiresAt: iso, matchesAccount: z.boolean(), alreadyMember: z.boolean(), ...rights }),
});
export const platformAcceptedResult = z.object({ data: z.object({ operator: platformOperatorSchema, ...rights }) });
export const platformJoinStatus = z.object({ pending: z.boolean(), uncertain: z.boolean(), accepted: z.boolean() });

export type PlatformOperator = z.infer<typeof platformOperatorSchema>;
export type PlatformInvitation = z.infer<typeof platformInvitationSchema>;
export type PlatformJournalEntry = z.infer<typeof platformJournalSchema>;
export type PlatformMe = z.infer<typeof platformMeResult>['data'];
export type PlatformPending = NonNullable<z.infer<typeof platformInvitationsResult>['pending']>;
export type PlatformPreview = z.infer<typeof platformPreviewResult>;

export interface PlatformRoutes { console: string; join: string }
export const platformRoutes: PlatformRoutes = { console: '/app/plateforme', join: '/app/plateforme/rejoindre' };

// --- Saisie ---
export const platformCodePattern = /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/;
/** Le code se lit à voix haute ou se recopie : majuscules, séparateur ajouté, caractères étrangers retirés. */
export function formatPlatformCode(raw: string): string {
  const letters = raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10);
  return letters.length > 5 ? `${letters.slice(0, 5)}-${letters.slice(5)}` : letters;
}
export const isPlatformCode = (value: string) => platformCodePattern.test(value);
export const isInviteeEmail = (value: string) => value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

// --- Libellés ---
export const levelLabel = (level: string) => ({ COMMERCIAL: 'Commercial' } as Record<string, string>)[level] ?? 'Opérateur';
const rightLabels: Record<string, string> = {
  MANAGE_PLATFORM_TEAM: 'Gérer l’équipe de la plateforme',
  MANAGE_SCHOOL_OPENINGS: 'Ouvrir des écoles',
  READ_COMMERCIAL_JOURNAL: 'Lire le journal commercial',
};
const deniedLabels: Record<string, string> = {
  SCHOOL_RECORDS: 'Dossiers des élèves', TRIPS: 'Trajets', MESSAGES: 'Messages', SCHOOL_ROLES: 'Rôles dans une école',
};
export const rightLabel = (right: string) => rightLabels[right] ?? 'Droit commercial';
export const notGrantedLabel = (access: string) => deniedLabels[access] ?? 'Accès scolaire';
export const invitationStatusLabel = (status: PlatformInvitation['status']) =>
  ({ AVAILABLE: 'En attente', USED: 'Acceptée', REVOKED: 'Révoquée', EXPIRED: 'Expirée' })[status];
const actionLabels: Record<string, string> = {
  CREATE_PLATFORM_INVITATION: 'Invitation créée',
  REVOKE_PLATFORM_INVITATION: 'Invitation révoquée',
  REVOKE_PLATFORM_OPERATOR: 'Opérateur retiré',
  ACCEPT_PLATFORM_INVITATION: 'Invitation acceptée',
  BOOTSTRAP_PLATFORM_OPERATOR: 'Opérateur mis en service',
};
export const actionLabel = (action: string) => actionLabels[action] ?? 'Action enregistrée';
const reasonLabels: Record<string, string> = {
  LAST_PLATFORM_OPERATOR: 'Dernier opérateur actif',
  PLATFORM_OPERATOR_REVOKED: 'Opérateur déjà retiré',
  PLATFORM_OPERATOR_EXISTS: 'Déjà opérateur',
  PLATFORM_INVITATION_PENDING: 'Invitation déjà en attente',
  PLATFORM_INVITATION_USED: 'Invitation déjà utilisée',
  PLATFORM_INVITATION_REVOKED: 'Invitation déjà révoquée',
  PLATFORM_INVITATION_CLOSED: 'Invitation fermée',
  PLATFORM_INVITATION_INVALID: 'Code non valide',
  PLATFORM_INVITATION_EMAIL_MISMATCH: 'Autre adresse',
  PLATFORM_ALREADY_MEMBER: 'Déjà dans l’équipe',
  VERSION_CONFLICT: 'Modifié entre-temps',
};
export const reasonLabel = (code: string | null) => (code ? reasonLabels[code] ?? null : null);

/** La modification utile d'une ligne du journal, en une phrase courte ; rien quand l'action se suffit à elle-même. */
export function journalDetail(entry: PlatformJournalEntry, format: (iso: string) => string): string | null {
  const parts: string[] = [];
  const masked = entry.changes.maskedEmail;
  if (typeof masked === 'string') parts.push(masked);
  const expires = entry.changes.expiresAt;
  if (typeof expires === 'string' && iso.safeParse(expires).success) parts.push(`valable jusqu’au ${format(expires)}`);
  if (entry.changes.self === true) parts.push('retrait volontaire');
  const stopped = entry.changes.revokedInvitations;
  if (typeof stopped === 'number' && Number.isInteger(stopped) && stopped > 0) parts.push(stopped === 1 ? '1 invitation révoquée' : `${stopped} invitations révoquées`);
  return parts.length ? parts.join(' · ') : null;
}

// --- Erreurs ---
const failures: Record<string, string> = {
  PLATFORM_OPERATOR_REQUIRED: 'Cet espace est réservé aux opérateurs de la plateforme.',
  VERSION_CONFLICT: 'Cette ligne a changé entre-temps. La liste est à jour : vérifiez, puis recommencez.',
  LAST_PLATFORM_OPERATOR: 'Le dernier opérateur actif ne peut pas être retiré.',
  PLATFORM_OPERATOR_REVOKED: 'Cet opérateur n’a déjà plus d’accès.',
  PLATFORM_OPERATOR_EXISTS: 'Cette adresse appartient déjà à un opérateur actif.',
  PLATFORM_INVITATION_PENDING: 'Une invitation est déjà en attente pour cette adresse. Révoquez-la d’abord.',
  PLATFORM_INVITATION_USED: 'Cette invitation a déjà été utilisée.',
  PLATFORM_INVITATION_REVOKED: 'Cette invitation a été révoquée. Demandez-en une nouvelle.',
  PLATFORM_INVITATION_EXPIRED: 'Cette invitation a expiré. Demandez-en une nouvelle.',
  PLATFORM_INVITATION_CLOSED: 'Cette invitation n’est plus ouverte.',
  PLATFORM_INVITATION_INVALID: 'Ce code n’est pas valide ou n’est plus utilisable.',
  PLATFORM_INVITATION_EMAIL_MISMATCH: 'Cette invitation est destinée à une autre adresse. Connectez-vous avec le compte invité.',
  PLATFORM_ALREADY_MEMBER: 'Ce compte fait déjà partie de l’équipe.',
  PLATFORM_CODE_TAKEN: 'Le code tiré existe déjà. Recommencez.',
  EMAIL_VERIFICATION_REQUIRED: 'Vérifiez votre adresse e-mail auprès du service de connexion, puis reconnectez-vous.',
  INVITATION_CODE_ATTEMPTS: 'Trop d’essais. Patientez un instant avant de saisir un autre code.',
  PLATFORM_INVITE_IN_PROGRESS: 'Une invitation est déjà en cours. Terminez-la avant d’en créer une autre.',
  IDEMPOTENCY_MISMATCH: 'Cette demande ne correspond plus à celle déjà envoyée. Actualisez la page.',
  PLATFORM_JOIN_MISSING: 'Saisissez de nouveau le code pour continuer.',
  PLATFORM_JOIN_IN_PROGRESS: 'Une acceptation est déjà en cours. Attendez sa confirmation.',
  PLATFORM_IDENTITY_CHANGED: 'Cette demande appartient à un autre compte. Reconnectez-vous avec ce compte ou saisissez de nouveau le code.',
  PLATFORM_PREVIEW_CHANGED: 'Les droits proposés ont changé. Relisez-les, puis confirmez à nouveau.',
  SESSION_EXPIRED: 'Votre session a expiré. Reconnectez-vous pour continuer.',
  INVALID_REQUEST: 'Certaines informations ne sont pas valides. Vérifiez-les, puis réessayez.',
};
export function platformFailure(error: unknown): string {
  if (error instanceof RequestFailure) {
    const known = failures[error.code];
    if (known) return known;
    if (error.status === 401) return failures.SESSION_EXPIRED!;
    if (error.status === 429) return 'Trop de demandes ont été envoyées. Patientez un instant avant de réessayer.';
    if (error.status === 403) return 'Cette action n’est pas disponible avec vos accès actuels.';
    if (error.status === 0 || error.status >= 500 || error.code === 'INVALID_RESPONSE' || error.code.startsWith('CSRF_')) return errorMessage(error);
  }
  return 'La demande n’a pas pu être confirmée. Réessayez.';
}
/** Ce que l'écran doit faire d'une erreur : se fermer (plus d'accès), recharger (conflit) ou seulement l'afficher. */
export type PlatformFailureKind = 'denied' | 'conflict' | 'expired' | 'unconfirmed' | 'refused';
export function platformFailureKind(error: unknown): PlatformFailureKind {
  if (!(error instanceof RequestFailure)) return 'unconfirmed';
  if (error.status === 403 && error.code === 'PLATFORM_OPERATOR_REQUIRED') return 'denied';
  if (error.status === 412 || error.code === 'VERSION_CONFLICT') return 'conflict';
  if (error.status === 401 || error.code === 'SESSION_EXPIRED') return 'expired';
  // Réseau, réponse illisible ou panne du service : on ne sait pas si l'opération a eu lieu, seule la même demande le tranche.
  if (error.status === 0 || error.status >= 500 || error.code === 'INVALID_RESPONSE') return 'unconfirmed';
  return 'refused';
}
