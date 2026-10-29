import { z } from 'zod';
import { errorMessage, RequestFailure, roleLabel, type InvitationPreview, type Me, type Member, type Role, type Session } from '../../protocol';
import type { AccessKind } from '../../account-entry-route';

/**
 * Pure rules of the rebuilt entry (#319): sign-in, code, account creation, linked schools, invitation and recovery.
 * Same behaviour as the historical `App`, `account-entry` and `account-recovery` views, without their rendering.
 */
export type { AccessKind } from '../../account-entry-route';
export { accountEntryDestination } from '../../account-entry-route';

/** What a code opens, as the server read it. */
export const accessCodeSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING']), schoolName: z.string().max(200).optional(), expiresAt: z.string() });
export const createdAccountSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING', 'EMAIL_INVITATION']) });
/** The BFF says whether the identity provider offers a reset flow; the page never guesses it. */
export const recoveryOptionsSchema = z.object({ data: z.discriminatedUnion('available', [
  z.object({ available: z.literal(false), recoveryUrl: z.null() }),
  z.object({ available: z.literal(true), recoveryUrl: z.url() }),
]) });
/** Built by the BFF from its validated identity configuration, never from an e-mail or a return address. */
export const recoveryStartSchema = z.object({ url: z.url() });

export type EntryStep = 'login' | 'code' | 'register';
export type EntryPageKind = 'account' | 'invitation';

/** Where each entry link leads. The synthetic preview replaces them with its own pages. */
export interface EntryRoutes {
  account: string;
  invitation: string;
  recover: string;
  opening: string;
  preferences: string;
  school: (schoolId: string) => string;
}
export const entryRoutes: EntryRoutes = {
  account: '/app/', invitation: '/app/invitation', recover: '/app/recover', opening: '/app/ouvrir', preferences: '/app/preferences',
  school: schoolId => `/app/gestion/${schoolId}`,
};

export function entryPageFromPath(pathname: string): EntryPageKind {
  return pathname.replace(/\/+$/, '') === '/app/invitation' ? 'invitation' : 'account';
}

/** A signed-in person only types a code; an opening link or an invitation link starts with the account form. */
export function initialEntryStep(options: { signedIn?: boolean; invitation?: boolean; initialCode?: string }): EntryStep {
  if (options.signedIn) return 'code';
  return options.initialCode || options.invitation ? 'register' : 'login';
}

export function initialAccessKind(options: { invitation?: boolean; initialCode?: string }): AccessKind | null {
  if (options.initialCode) return 'SCHOOL_OPENING';
  return options.invitation ? 'EMAIL_INVITATION' : null;
}

/**
 * A pasted link keeps only its code: `…/ouvrir#token=…` (opening) or the typed `XXXX-XXXX`.
 * Anything else is sent as typed and the server answers whether it is a code.
 */
export function codeFromInput(value: string): string {
  const trimmed = value.trim();
  const fragment = /#token=([A-Za-z0-9_-]+)$/.exec(trimmed);
  return fragment?.[1] ?? trimmed;
}

const entryMessages: Record<string, string> = {
  INVALID_CREDENTIALS: 'E-mail ou mot de passe incorrect.',
  ACCESS_CODE_INVALID: 'Ce code n’est pas valide ou n’est plus utilisable.',
  ACCESS_CODE_ATTEMPTS: 'Trop de tentatives. Réessayez dans quelques minutes.',
  ACCOUNT_EXISTS: 'Un compte existe déjà avec cette adresse. Connectez-vous : votre code sera repris.',
  EMAIL_INVITATION_MISMATCH: 'Utilisez l’adresse à laquelle l’école a envoyé l’invitation.',
  ACCOUNT_PASSWORD_REJECTED: 'Ce mot de passe n’est pas accepté. Choisissez-en un plus long ou moins courant.',
  ACCOUNT_CREATION_UNAVAILABLE: 'La création de compte est momentanément indisponible. Réessayez plus tard.',
  INVALID_REQUEST: 'Vérifiez les champs puis réessayez.',
  RATE_LIMITED: 'Trop de tentatives. Réessayez dans quelques minutes.',
  OPENING_IN_PROGRESS: 'Une ouverture d’école est déjà en cours avec un autre code. Terminez-la avant d’en saisir un nouveau.',
};

/** Message of a failed sign-in, code or account creation; other failures keep the shared protocol wording. */
export function entryFailureMessage(cause: unknown): string {
  return cause instanceof RequestFailure && entryMessages[cause.code] ? entryMessages[cause.code]! : errorMessage(cause);
}

/** An e-mail invitation names its account by the link: a refused code then means another address was used. */
export function accountCreationFailure(kind: AccessKind | null, cause: unknown): unknown {
  return kind === 'EMAIL_INVITATION' && cause instanceof RequestFailure && cause.code === 'ACCESS_CODE_INVALID'
    ? new RequestFailure('EMAIL_INVITATION_MISMATCH', 404) : cause;
}

export const passwordMinimum = 8;
export interface SignInDraft { email: string; password: string }
export interface AccountDraft extends SignInDraft { firstName: string; lastName: string }
export type DraftProblems<T> = Partial<Record<keyof T, string>>;

/** Problems shown only after a submission; nothing is sent while one remains. */
export function signInProblems(draft: SignInDraft): DraftProblems<SignInDraft> {
  return {
    ...(!draft.email.trim() ? { email: 'Saisissez votre e-mail.' } : {}),
    ...(!draft.password ? { password: 'Saisissez votre mot de passe.' } : {}),
  };
}
export function accountProblems(draft: AccountDraft): DraftProblems<AccountDraft> {
  return {
    ...(!draft.firstName.trim() ? { firstName: 'Saisissez votre prénom.' } : {}),
    ...(!draft.lastName.trim() ? { lastName: 'Saisissez votre nom.' } : {}),
    ...(!draft.email.trim() ? { email: 'Saisissez votre e-mail.' } : {}),
    ...(draft.password.length < passwordMinimum ? { password: `${passwordMinimum} caractères au moins.` } : {}),
  };
}
export function codeProblem(code: string): string | null {
  return code.trim() ? null : 'Saisissez le code ou collez le lien reçu.';
}
export const hasProblems = (problems: object) => Object.keys(problems).length > 0;

/** An e-mail invitation is accepted only with an address the identity provider verified. A code does not need it. */
export function invitationNeedsVerifiedEmail(preview: InvitationPreview | null | undefined, session: Session | null): boolean {
  return !!preview && preview.delivery !== 'CODE' && session?.user?.emailVerified !== true;
}
export function canAcceptInvitation(preview: InvitationPreview | null | undefined, session: Session | null, reviewed: boolean): boolean {
  return !!preview && !!session?.csrfToken && reviewed && !invitationNeedsVerifiedEmail(preview, session);
}

/** A new link refused only because a preceding acceptance is still unknown: recover that intention instead. */
export function admissionNeedsCheck(cause: unknown): boolean {
  return cause instanceof RequestFailure && ['INVITATION_IN_PROGRESS', 'INVITATION_RESULT_UNKNOWN'].includes(cause.code);
}

/**
 * What an acceptance failure leaves on screen. A changed preview must be read again; a lost or server-side failure
 * keeps the same request, to be checked, never replaced.
 */
export function acceptanceFailure(cause: unknown): { dropPreview: boolean; uncertain: boolean } {
  if (!(cause instanceof RequestFailure)) return { dropPreview: false, uncertain: false };
  return { dropPreview: cause.code === 'INVITATION_PREVIEW_CHANGED', uncertain: cause.status === 0 || cause.status >= 500 };
}

/** A refused session forgets everything personal on the page. */
export function sessionLost(cause: unknown): boolean {
  return cause instanceof RequestFailure && (cause.status === 401 || cause.code === 'CSRF_REJECTED');
}

export function rolesLabel(roles: readonly Role[]): string {
  return roles.map(roleLabel).join(' · ');
}
export function managesSchool(member: Pick<Member, 'roles'>): boolean {
  return member.roles.includes('ADMIN');
}
export function schoolsHeading(me: Me | null): string {
  if (!me) return 'Vos écoles';
  return me.memberships.length === 1 ? 'Une école liée' : `${me.memberships.length} écoles liées`;
}
export function personInitials(name: string): string {
  return name.trim().split(/\s+/).slice(0, 2).map(part => part.charAt(0)).join('').toLocaleUpperCase('fr');
}
export function formatInvitationDate(value: string): string {
  return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(value));
}

/** The recovery page states, from the real provider availability. */
export type RecoveryState = 'loading' | 'available' | 'unavailable' | 'error' | 'opening';
export function recoveryStartFailure(cause: unknown): RecoveryState {
  return cause instanceof RequestFailure && cause.code === 'ACCOUNT_RECOVERY_UNAVAILABLE' ? 'unavailable' : 'error';
}
