import type { CommandKind } from './command-core.js';

/**
 * Which commands change which reads. A section reads a family of resources and asks for a new read when a command of that family was
 * confirmed, not whenever the school confirmed anything. A command missing from a family only delays a refresh until the next
 * navigation; it never shows something confirmed that was not.
 */
export const commandFamilies = {
  invitations: ['createInvitation', 'resendInvitation', 'revokeInvitation'],
  members: ['updateMember', 'deactivateMember'],
  catalogue: ['createOffering', 'createCurriculum', 'createCatalogPolicy', 'createCommercialTerms', 'createServiceProduct', 'createFormation',
    'saveFormationProgramme', 'saveTariff', 'reviseSharedTerms'],
  availability: ['createAvailabilityRule', 'updateAvailabilityRule', 'removeAvailabilityRule', 'createClosure', 'removeClosure'],
  learners: ['createTraining', 'createAssignment', 'transitionTraining', 'endAssignment', 'archiveLearner', 'restoreLearner', 'recordPermitCheck',
    'updateAdministrativeProfile'],
  school: ['updateSchool', 'saveSetup', 'saveSetupDraft', 'applySetupDraft', 'activate', 'saveDataPolicy', 'updateModules', 'createProfilePolicy',
    'publishProfilePolicy'],
} as const satisfies Record<string, readonly CommandKind[]>;

export type CommandFamily = keyof typeof commandFamilies;
export const kindsOf = (...families: CommandFamily[]): CommandKind[] => families.flatMap(family => [...commandFamilies[family]]);

/** The sum is monotonic: it changes exactly when one of these kinds is confirmed again or a followed request is given up. */
export function revisionOf(view: { readonly byKind: Readonly<Record<string, number>>; readonly rereads: number }, kinds: readonly CommandKind[]): number {
  return view.rereads + kinds.reduce((total, kind) => total + (view.byKind[kind] ?? 0), 0);
}

/**
 * What the catalogue reads depend on: its own commands, the school's setup (a preparation creates formations and prices) and the
 * dossiers (the enrolment counts of a formation). Lessons, hours, invitations or exams never read the catalogue again.
 */
export const catalogueReads: readonly CommandKind[] = kindsOf('catalogue', 'learners', 'school');
