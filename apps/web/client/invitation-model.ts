import { z } from 'zod';

/**
 * Invitation read model and the pure rules around it (single-use learner codes included).
 * Zod only, no relative import: type-checked for the browser and for the Node unit tests.
 */
const id = z.string().uuid();

export const invitationSchema = z.object({
  id, schoolId: id, version: z.number().int().positive(), delivery: z.enum(['EMAIL', 'CODE']), maskedEmail: z.string().nullable(),
  /** Only present in the response of the command that creates or renews the code, never in a list read. */
  code: z.string().min(1).max(24).optional(),
  /** Offer and instructor a CODE invitation opens a formation with; absent or null for an EMAIL invitation. */
  training: z.object({ offeringId: id, instructorMembershipId: id }).nullable().optional(),
  roles: z.array(z.enum(['ADMIN', 'INSTRUCTOR', 'LEARNER'])).min(1).max(3),
  status: z.enum(['PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED']), expiresAt: z.string().datetime({ offset: true }),
});
export type Invitation = z.infer<typeof invitationSchema>;

export const invitationCodeValidityDays = 7;

const envelope = z.object({ data: invitationSchema, requestId: z.string().min(1), serverTime: z.string().datetime({ offset: true }) });

/**
 * The invitation carried by the response of a create or renew command, fully validated.
 * Null on any mismatch (shape, school, targeted invitation, status): a code read from a body
 * that does not prove it belongs to this very command is never shown.
 */
export function parseInvitationResponse(body: unknown, expected: { schoolId: string; invitationId?: string }): Invitation | null {
  const parsed = envelope.safeParse(body);
  if (!parsed.success) return null;
  const invitation = parsed.data.data;
  if (invitation.schoolId.toLowerCase() !== expected.schoolId.toLowerCase()) return null;
  if (expected.invitationId !== undefined && invitation.id.toLowerCase() !== expected.invitationId.toLowerCase()) return null;
  return invitation;
}

/** The code to display for a response, or null when the response carries none (or a code for another invitation). */
export function issuedCodeOf(invitation: Invitation | null): { invitationId: string; code: string; expiresAt: string } | null {
  return invitation && invitation.delivery === 'CODE' && invitation.status === 'PENDING' && invitation.code
    ? { invitationId: invitation.id, code: invitation.code, expiresAt: invitation.expiresAt } : null;
}

export interface OfferingLike { readonly id: string; readonly offeringKey: string; readonly version: number; readonly enabled: boolean; readonly categoryCode: string }
export interface MemberLike { readonly id: string; readonly displayName: string; readonly status: string; readonly roles: readonly string[] }

/** Only the latest version of each offer can open a formation, and only when it is enabled. */
export function openOfferings<T extends OfferingLike>(offerings: readonly T[]): T[] {
  const latest = new Map<string, T>();
  for (const item of offerings) if ((latest.get(item.offeringKey)?.version ?? 0) < item.version) latest.set(item.offeringKey, item);
  return [...latest.values()].filter(item => item.enabled)
    .sort((a, b) => a.categoryCode.localeCompare(b.categoryCode, 'fr') || a.offeringKey.localeCompare(b.offeringKey, 'fr'));
}

/** « Permis B », followed by the offer reference when several offers of the same category exist. */
export function offeringLabel(offering: OfferingLike, offerings: readonly OfferingLike[]): string {
  const keys = new Set(offerings.filter(item => item.categoryCode === offering.categoryCode).map(item => item.offeringKey));
  return keys.size > 1 ? `Permis ${offering.categoryCode} · ${offering.offeringKey}` : `Permis ${offering.categoryCode}`;
}

export function activeInstructors<T extends MemberLike>(members: readonly T[]): T[] {
  return members.filter(member => member.status === 'ACTIVE' && member.roles.includes('INSTRUCTOR'))
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr'));
}

/** The signed-in member when he is himself an active instructor, nobody otherwise. */
export function defaultInstructorId(membershipId: string, instructors: readonly { readonly id: string }[]): string {
  return instructors.find(item => item.id.toLowerCase() === membershipId.toLowerCase())?.id ?? '';
}

/** « Code élève · Permis B · Moniteur » for a code invitation, the masked address otherwise. */
export function invitationLabel(invitation: Pick<Invitation, 'delivery' | 'maskedEmail' | 'training'>,
  offerings: readonly OfferingLike[], members: readonly MemberLike[]): string {
  if (invitation.delivery !== 'CODE') return invitation.maskedEmail ?? 'Invitation';
  const offering = invitation.training ? offerings.find(item => item.id === invitation.training!.offeringId) : undefined;
  const instructor = invitation.training ? members.find(item => item.id === invitation.training!.instructorMembershipId) : undefined;
  const parts = ['Code élève', offering ? offeringLabel(offering, offerings) : null, instructor ? instructor.displayName : null];
  return parts.filter((part): part is string => part !== null).join(' · ');
}

/** The single line the administration sends to the learner. */
export function invitationCodeMessage(code: string, expiry: string, schoolName: string): string {
  return `Votre code pour rejoindre ${schoolName} sur Drivy : ${code}. Valable jusqu’au ${expiry}.`;
}
