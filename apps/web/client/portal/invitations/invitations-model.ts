import { commandMessage, isEmail, matchesSearch } from '../../command-core';
import type { Invitation } from '../../invitation-model';
import type { Role } from '../../protocol';

/** Pure rules of the invitation lists and forms. No React, no network: tested alone. */
export type InvitationStatus = Invitation['status'];
export type InvitationStatusFilter = 'all' | InvitationStatus;
export const invitationStatuses: readonly InvitationStatus[] = ['PENDING', 'ACCEPTED', 'EXPIRED', 'REVOKED'];
export const invitationStatusLabels: Record<InvitationStatus, string> = { PENDING: 'En attente', ACCEPTED: 'Acceptée', EXPIRED: 'Expirée', REVOKED: 'Révoquée' };
export const invitationPageSize = 25;

/** An invitation to the school's staff (administration or instructors), as opposed to an invitation of a learner. */
export const isStaffInvitation = (invitation: Pick<Invitation, 'roles'>) => invitation.roles.includes('ADMIN') || invitation.roles.includes('INSTRUCTOR');

/** The invitations of one audience, the most recent first (the school lists them oldest first). */
export function audienceInvitations<T extends Pick<Invitation, 'roles'>>(items: readonly T[], team: boolean): T[] {
  return items.filter(item => isStaffInvitation(item) === team).reverse();
}

/** Only a waiting or expired invitation can be renewed or revoked; the school remains the authority. */
export const isActionable = (invitation: Pick<Invitation, 'status'>) => invitation.status === 'PENDING' || invitation.status === 'EXPIRED';

export function filterInvitations<T extends Pick<Invitation, 'status'>>(items: readonly T[], labelOf: (item: T) => string,
  options: { status: InvitationStatusFilter; search: string }): T[] {
  return items.filter(item => (options.status === 'all' || item.status === options.status) && matchesSearch([labelOf(item)], options.search));
}

/** Roles that may be proposed by e-mail: the team is invited by administrators only, learners by their own role. */
export function proposableRoles(team: boolean, viewerIsAdmin: boolean): Role[] {
  return team ? viewerIsAdmin ? ['ADMIN', 'INSTRUCTOR'] : [] : ['LEARNER'];
}

export const emailProblem = (email: string): string | null => isEmail(email.trim()) ? null : 'Indiquez l’adresse e-mail de la personne invitée.';
export const rolesProblem = (selected: readonly Role[], proposable: readonly Role[]): string | null =>
  selected.length > 0 && selected.every(role => proposable.includes(role)) ? null : 'Choisissez au moins un rôle.';
/** At most 16 open offers, each really offered, and an active instructor. */
export function trainingProblem(offeringIds: readonly string[], instructorId: string, offeringsOpen: readonly { id: string }[], instructors: readonly { id: string }[]): string | null {
  const valid = offeringIds.length > 0 && offeringIds.length <= 16 && offeringIds.every(id => offeringsOpen.some(item => item.id === id))
    && instructors.some(item => item.id === instructorId);
  return valid ? null : commandMessage('INVITATION_TRAINING_INVALID');
}

/** « Expire le … » while waiting, « Expirée le … » once past; the expiry of an accepted or revoked invitation says nothing. */
export function expiryLead(status: InvitationStatus): string | null {
  return status === 'PENDING' ? 'Expire le' : status === 'EXPIRED' ? 'Expirée le' : null;
}

/** Date and time in the school's time zone. */
export function formatDateTime(value: string, timeZone: string): string {
  return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeStyle: 'short', timeZone }).format(new Date(value));
}
