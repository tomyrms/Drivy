/** Contrôles ciblés des helpers de la recette #50 : projection avant/après et conditions de rôle.
 *  Aucun conteneur, aucun réseau : ces tests qualifient la logique de harnais, pas le parcours lui-même. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  RECOVERY_CONDITIONAL_MESSAGE, RECOVERY_UNAVAILABLE_MESSAGE, requirementGaps, snapshotDifferences,
  type AssignmentState, type AvailabilityState, type IdentitySnapshot, type LessonState, type MembershipState,
  type ProfileState, type TrainingState
} from './check-school-account-recovery.js';

const membership = (overrides: Partial<MembershipState> = {}): MembershipState => ({
  schoolId: 'ecole-1', roles: ['ADMIN', 'INSTRUCTOR'], grants: ['CONFIGURE_CATALOG'], status: 'ACTIVE',
  accessEpoch: 1, version: 1, ...overrides
});
const assignment = (id: string, overrides: Partial<AssignmentState> = {}): AssignmentState => ({
  id, trainingId: 'formation-1', instructorMembershipId: 'rattachement-1', validFrom: '2026-11-01T00:00:00.000Z',
  validUntil: null, ...overrides
});
const lesson = (id: string, overrides: Partial<LessonState> = {}): LessonState => ({
  id, trainingId: 'formation-1', learnerId: 'dossier-1', learnerPersonId: 'personne-1',
  instructorMembershipId: 'rattachement-1', status: 'PLANNED', plannedStart: '2026-11-10T08:00:00.000Z',
  plannedEnd: '2026-11-10T08:50:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Point synthétique',
  priceCents: 9500, bufferMinutes: 0, policyVersionId: 'procedure-1', publicationVersion: 0, version: 1, ...overrides
});
const training = (id: string, overrides: Partial<TrainingState> = {}): TrainingState => ({
  id, learnerId: 'dossier-1', offeringId: 'offre-1', offeringKey: 'permis-b', status: 'ACTIVE',
  startedOn: '2026-11-01', closedOn: null, version: 1, ...overrides
});
const profile = (id: string, overrides: Partial<ProfileState> = {}): ProfileState => ({
  id, profileId: 'profil-administratif-1', administrativePolicyId: 'politique-1',
  profileUpdatedAt: '2026-11-01T10:00:00.000Z', enteredByMembershipId: 'rattachement-1', entrySource: 'INVITATION',
  archived: false, version: 1, ...overrides
});
const availability = (id: string, overrides: Partial<AvailabilityState> = {}): AvailabilityState => ({
  id, instructorMembershipId: 'rattachement-1', weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '18:00',
  validFrom: '2026-11-01', validUntil: null, removed: false, version: 1, ...overrides
});
const personne = (overrides: Partial<NonNullable<IdentitySnapshot['person']>> = {}): NonNullable<IdentitySnapshot['person']> => ({
  id: 'personne-1', status: 'ACTIVE', displayName: 'Personne Synthétique', firstName: 'Camille',
  lastName: 'Synthétique', contactEmail: 'personne@example.invalid', locale: 'fr-CH', version: 1, ...overrides
});

function snapshot(overrides: Partial<IdentitySnapshot> = {}): IdentitySnapshot {
  return {
    person: personne(),
    links: ['issuer|subject-1|personne-1'],
    memberships: [membership()],
    assignments: [assignment('affectation-1')],
    learnerLessons: [lesson('lecon-1')],
    instructorLessons: [lesson('lecon-1')],
    trainings: [training('formation-1')],
    profiles: [profile('dossier-1')],
    availability: [availability('disponibilite-1')],
    totals: { persons: 3, links: 3, memberships: 3, assignments: 3, lessons: 2, trainings: 1, profiles: 1, availability: 1 },
    ...overrides
  };
}

test('Une récupération qui ne touche rien ne produit aucune différence', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot()), []);
});

test('L’ordre des rattachements et des leçons ne crée pas de fausse différence', () => {
  const before = snapshot({
    memberships: [membership({ schoolId: 'ecole-1', roles: ['ADMIN'] }), membership({ schoolId: 'ecole-2', roles: ['LEARNER'] })],
    assignments: [assignment('affectation-1'), assignment('affectation-2', { trainingId: 'formation-2' })],
    learnerLessons: [lesson('lecon-1'), lesson('lecon-2')],
    availability: [availability('disponibilite-1', { weekdays: [1, 2, 3] })]
  });
  const after = snapshot({
    memberships: [membership({ schoolId: 'ecole-2', roles: ['LEARNER'] }), membership({ schoolId: 'ecole-1', roles: ['ADMIN'] })],
    assignments: [assignment('affectation-2', { trainingId: 'formation-2' }), assignment('affectation-1')],
    learnerLessons: [lesson('lecon-2'), lesson('lecon-1')],
    availability: [availability('disponibilite-1', { weekdays: [3, 1, 2] })]
  });
  assert.deepEqual(snapshotDifferences(before, after), []);
});

test('Un rôle ajouté par la récupération est signalé comme changement de droits', () => {
  const after = snapshot({ memberships: [membership({ roles: ['ADMIN', 'INSTRUCTOR', 'LEARNER'] })] });
  assert.deepEqual(snapshotDifferences(snapshot(), after), ['rattachements, rôles et droits']);
});

test('Une personne recréée avec un autre identifiant est signalée, pas absorbée', () => {
  const after = snapshot({ person: personne({ id: 'personne-2' }) });
  assert.deepEqual(snapshotDifferences(snapshot(), after), ['identité de personne']);
});

test('Une personne dont le nom ou l’adresse change à identifiant inchangé est signalée', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ person: personne({ displayName: 'Autre Nom Synthétique' }) })), ['identité de personne']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ person: personne({ contactEmail: 'autre@example.invalid' }) })), ['identité de personne']);
});

test('Une leçon dupliquée ou perdue est signalée séparément des droits', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ learnerLessons: [lesson('lecon-1'), lesson('lecon-2')] })), ['leçons suivies']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ instructorLessons: [] })), ['leçons données']);
});

test('Une disponibilité, une formation ou un dossier perdus sont chacun signalés', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ availability: [] })), ['disponibilités']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ trainings: [] })), ['formations']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ profiles: [] })), ['dossiers élève']);
});

test('Un lien d’identité déplacé et un total de lignes modifié sont signalés', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ links: ['issuer|subject-2|personne-1'] })), ['liens d’identité']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ totals: {
    persons: 4, links: 4, memberships: 3, assignments: 3, lessons: 2, trainings: 1, profiles: 1, availability: 1 }
  })), ['totaux en base']);
});

test('Une identité sans personne liée est un écart, jamais un état valide', () => {
  const unlinked = snapshot({ person: null, links: [], memberships: [], assignments: [], learnerLessons: [],
    instructorLessons: [], trainings: [], profiles: [], availability: [] });
  assert.deepEqual(snapshotDifferences(snapshot(), unlinked).includes('identité de personne'), true);
  assert.deepEqual(requirementGaps(unlinked, 'ADMIN').includes('aucune personne liée'), true);
});

test('Les trois rôles exigent leurs objets métier réels, pas une étiquette sur un compte vide', () => {
  const admin = snapshot({ memberships: [membership({ roles: ['ADMIN', 'INSTRUCTOR'] })] });
  assert.deepEqual(requirementGaps(admin, 'ADMIN'), []);
  const instructor = snapshot({
    memberships: [membership({ roles: ['INSTRUCTOR'] })],
    learnerLessons: [], instructorLessons: [lesson('lecon-moniteur')], trainings: [], profiles: []
  });
  assert.deepEqual(requirementGaps(instructor, 'INSTRUCTOR'), []);
  const learner = snapshot({ memberships: [membership({ roles: ['LEARNER'] })], instructorLessons: [], availability: [] });
  assert.deepEqual(requirementGaps(learner, 'LEARNER'), []);
});

test('Un moniteur qui porte aussi le rôle administrateur ne prouve pas le rôle moniteur', () => {
  const doubled = snapshot({ memberships: [membership({ roles: ['ADMIN', 'INSTRUCTOR'] })] });
  assert.deepEqual(requirementGaps(doubled, 'INSTRUCTOR'), ['rôle moniteur distinct']);
});

test('Un élève sans formation ni leçon est refusé par la recette', () => {
  const empty = snapshot({ memberships: [membership({ roles: ['LEARNER'] })], learnerLessons: [], trainings: [], profiles: [] });
  assert.deepEqual(requirementGaps(empty, 'LEARNER'), ['au moins un dossier élève', 'au moins une formation', 'au moins une leçon suivie']);
});

test('Un administrateur qui n’a donné aucune leçon ne prouve pas son rôle', () => {
  assert.deepEqual(requirementGaps(snapshot({ instructorLessons: [] }), 'ADMIN'), ['au moins une leçon donnée']);
});

test('Un moniteur sans disponibilité réelle ne prouve pas son rôle', () => {
  const withoutAvailability = snapshot({ memberships: [membership({ roles: ['INSTRUCTOR'] })], availability: [] });
  assert.deepEqual(requirementGaps(withoutAvailability, 'INSTRUCTOR'), ['au moins une disponibilité']);
});

test('Un moniteur qui n’a donné aucune leçon ne prouve pas son rôle', () => {
  const withoutLesson = snapshot({ memberships: [membership({ roles: ['INSTRUCTOR'] })], instructorLessons: [] });
  assert.deepEqual(requirementGaps(withoutLesson, 'INSTRUCTOR'), ['au moins une leçon donnée']);
});

test('Un compte qui ne porte pas le rôle demandé est refusé, quel que soit son contenu', () => {
  const learnerOnly = snapshot({ memberships: [membership({ roles: ['LEARNER'] })], instructorLessons: [] });
  assert.deepEqual(requirementGaps(learnerOnly, 'ADMIN'), ['rôle admin', 'au moins une leçon donnée']);
});

test('Une leçon dont le contenu change à identifiant inchangé est signalée, suivie comme donnée', () => {
  const changed = snapshot({
    learnerLessons: [lesson('lecon-1', { meetingPoint: 'Autre point de rendez-vous', status: 'COMPLETED' })],
    instructorLessons: [lesson('lecon-1', { meetingPoint: 'Autre point de rendez-vous', status: 'COMPLETED' })]
  });
  assert.deepEqual(snapshotDifferences(snapshot(), changed), ['leçons suivies', 'leçons données']);
  const moved = snapshot({ learnerLessons: [lesson('lecon-1', { plannedStart: '2026-11-11T08:00:00.000Z' })] });
  assert.deepEqual(snapshotDifferences(snapshot(), moved), ['leçons suivies']);
});

test('Une formation dont le contenu change à identifiant inchangé est signalée', () => {
  const changed = snapshot({ trainings: [training('formation-1', { status: 'PAUSED', closedOn: '2026-11-20', version: 2 })] });
  assert.deepEqual(snapshotDifferences(snapshot(), changed), ['formations']);
});

test('Un dossier élève dont le contenu change à identifiant inchangé est signalé', () => {
  const updated = snapshot({ profiles: [profile('dossier-1', { profileUpdatedAt: '2026-11-02T10:00:00.000Z' })] });
  assert.deepEqual(snapshotDifferences(snapshot(), updated), ['dossiers élève']);
  const archived = snapshot({ profiles: [profile('dossier-1', { archived: true })] });
  assert.deepEqual(snapshotDifferences(snapshot(), archived), ['dossiers élève']);
  const repointed = snapshot({ profiles: [profile('dossier-1', { administrativePolicyId: 'politique-2' })] });
  assert.deepEqual(snapshotDifferences(snapshot(), repointed), ['dossiers élève']);
});

test('Une disponibilité dont l’horaire change à identifiant inchangé est signalée', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ availability: [availability('disponibilite-1', { localStart: '09:00' })] })), ['disponibilités']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ availability: [availability('disponibilite-1', { removed: true })] })), ['disponibilités']);
});

test('Un rattachement dont l’époque ou la version change est signalé, même sans nouveau rôle', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ memberships: [membership({ accessEpoch: 2 })] })), ['rattachements, rôles et droits']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ memberships: [membership({ version: 2 })] })), ['rattachements, rôles et droits']);
});

test('Une affectation de moniteur dont la fenêtre change est signalée', () => {
  const closed = snapshot({ assignments: [assignment('affectation-1', { validUntil: '2026-12-01T00:00:00.000Z' })] });
  assert.deepEqual(snapshotDifferences(snapshot(), closed), ['affectations de moniteur']);
});

test('Le harnais reprend mot pour mot la phrase conditionnelle du thème Drivy', async () => {
  const theme = await readFile(fileURLToPath(new URL('../../infra/identity/themes/drivy/login/messages/messages_fr.properties', import.meta.url)), 'utf8');
  const line = theme.split(/\r?\n/).find(value => value.startsWith('emailSentMessage='));
  assert.equal(line?.slice('emailSentMessage='.length), RECOVERY_CONDITIONAL_MESSAGE);
});

test('La panne annoncée par le harnais est celle que le portail affiche réellement', async () => {
  const page = await readFile(fileURLToPath(new URL('../../apps/web/client/portal/entry/recovery-page.tsx', import.meta.url)), 'utf8');
  assert.equal(page.includes(RECOVERY_UNAVAILABLE_MESSAGE), true);
});
