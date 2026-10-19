export type AccessKind = 'LEARNER_INVITATION' | 'SCHOOL_OPENING' | 'EMAIL_INVITATION';

/** A server-recognised code keeps its journey after login, wherever the account form was opened. */
export function accountEntryDestination(kind: AccessKind | null): '/app/ouvrir' | '/app/invitation' | null {
  if (kind === 'SCHOOL_OPENING') return '/app/ouvrir';
  if (kind === 'LEARNER_INVITATION' || kind === 'EMAIL_INVITATION') return '/app/invitation';
  return null;
}
