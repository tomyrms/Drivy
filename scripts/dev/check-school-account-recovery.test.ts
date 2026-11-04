/** Contrôles ciblés des helpers de la recette #50 : comparaison avant/après et conditions de rôle.
 *  Aucun conteneur, aucun réseau : ces tests qualifient la logique de harnais, pas le parcours lui-même. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  RECOVERY_CONDITIONAL_MESSAGE, RECOVERY_UNAVAILABLE_MESSAGE, requirementGaps, snapshotDifferences,
  type IdentitySnapshot
} from './check-school-account-recovery.js';

function snapshot(overrides: Partial<IdentitySnapshot> = {}): IdentitySnapshot {
  return {
    person: { id: 'personne-1', status: 'ACTIVE', displayName: 'Personne Synthétique' },
    links: ['issuer#subject-1'],
    memberships: [{ schoolId: 'ecole-1', roles: ['ADMIN', 'INSTRUCTOR'], grants: ['CONFIGURE_CATALOG'], status: 'ACTIVE', accessEpoch: 1 }],
    learnerLessons: ['lecon-1'], instructorLessons: ['lecon-1'], trainings: ['formation-1'],
    profiles: ['dossier-1'], availability: ['disponibilite-1'],
    totals: { persons: 3, links: 3, memberships: 3, lessons: 1 },
    ...overrides
  };
}

test('Une récupération qui ne touche rien ne produit aucune différence', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot()), []);
});

test('L’ordre des rattachements et des leçons ne crée pas de fausse différence', () => {
  const before = snapshot({
    memberships: [
      { schoolId: 'ecole-1', roles: ['ADMIN'], grants: [], status: 'ACTIVE', accessEpoch: 1 },
      { schoolId: 'ecole-2', roles: ['LEARNER'], grants: [], status: 'ACTIVE', accessEpoch: 1 }
    ],
    learnerLessons: ['lecon-1', 'lecon-2']
  });
  const after = snapshot({
    memberships: [
      { schoolId: 'ecole-2', roles: ['LEARNER'], grants: [], status: 'ACTIVE', accessEpoch: 1 },
      { schoolId: 'ecole-1', roles: ['ADMIN'], grants: [], status: 'ACTIVE', accessEpoch: 1 }
    ],
    learnerLessons: ['lecon-2', 'lecon-1']
  });
  assert.deepEqual(snapshotDifferences(before, after), []);
});

test('Un rôle ajouté par la récupération est signalé comme changement de droits', () => {
  const after = snapshot({
    memberships: [{ schoolId: 'ecole-1', roles: ['ADMIN', 'INSTRUCTOR', 'LEARNER'], grants: ['CONFIGURE_CATALOG'], status: 'ACTIVE', accessEpoch: 1 }]
  });
  assert.deepEqual(snapshotDifferences(snapshot(), after), ['rattachements, rôles et droits']);
});

test('Une personne recréée avec un autre identifiant est signalée, pas absorbée', () => {
  const after = snapshot({ person: { id: 'personne-2', status: 'ACTIVE', displayName: 'Personne Synthétique' } });
  assert.deepEqual(snapshotDifferences(snapshot(), after), ['identité de personne']);
});

test('Une leçon dupliquée ou perdue est signalée séparément des droits', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ learnerLessons: ['lecon-1', 'lecon-2'] })), ['leçons suivies']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ instructorLessons: [] })), ['leçons données']);
});

test('Une disponibilité, une formation ou un dossier perdus sont chacun signalés', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ availability: [] })), ['disponibilités']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ trainings: [] })), ['formations']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ profiles: [] })), ['dossiers élève']);
});

test('Un lien d’identité déplacé et un total de lignes modifié sont signalés', () => {
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ links: ['issuer#subject-2'] })), ['liens d’identité']);
  assert.deepEqual(snapshotDifferences(snapshot(), snapshot({ totals: { persons: 4, links: 4, memberships: 3, lessons: 1 } })), ['totaux en base']);
});

test('Une identité sans personne liée est un écart, jamais un état valide', () => {
  const unlinked = snapshot({ person: null, links: [], memberships: [], learnerLessons: [], instructorLessons: [], trainings: [], profiles: [], availability: [] });
  assert.deepEqual(snapshotDifferences(snapshot(), unlinked).includes('identité de personne'), true);
  assert.deepEqual(requirementGaps(unlinked, 'ADMIN').includes('aucune personne liée'), true);
});

test('Les trois rôles exigent leurs objets métier réels, pas une étiquette sur un compte vide', () => {
  const admin = snapshot({ memberships: [{ schoolId: 'ecole-1', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], status: 'ACTIVE', accessEpoch: 1 }] });
  assert.deepEqual(requirementGaps(admin, 'ADMIN'), []);
  const instructor = snapshot({
    memberships: [{ schoolId: 'ecole-1', roles: ['INSTRUCTOR'], grants: [], status: 'ACTIVE', accessEpoch: 1 }],
    learnerLessons: [], instructorLessons: [], trainings: [], profiles: []
  });
  assert.deepEqual(requirementGaps(instructor, 'INSTRUCTOR'), []);
  const learner = snapshot({ memberships: [{ schoolId: 'ecole-1', roles: ['LEARNER'], grants: [], status: 'ACTIVE', accessEpoch: 1 }], instructorLessons: [], availability: [] });
  assert.deepEqual(requirementGaps(learner, 'LEARNER'), []);
});

test('Un moniteur qui porte aussi le rôle administrateur ne prouve pas le rôle moniteur', () => {
  const doubled = snapshot({ memberships: [{ schoolId: 'ecole-1', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], status: 'ACTIVE', accessEpoch: 1 }] });
  assert.deepEqual(requirementGaps(doubled, 'INSTRUCTOR'), ['rôle moniteur distinct']);
});

test('Un élève sans formation ni leçon est refusé par la recette', () => {
  const empty = snapshot({ memberships: [{ schoolId: 'ecole-1', roles: ['LEARNER'], grants: [], status: 'ACTIVE', accessEpoch: 1 }], learnerLessons: [], trainings: [], profiles: [] });
  assert.deepEqual(requirementGaps(empty, 'LEARNER'), ['au moins un dossier élève', 'au moins une formation', 'au moins une leçon suivie']);
});

test('Un administrateur qui n’a donné aucune leçon ne prouve pas son rôle', () => {
  const withoutLesson = snapshot({ instructorLessons: [] });
  assert.deepEqual(requirementGaps(withoutLesson, 'ADMIN'), ['au moins une leçon donnée']);
});

test('Un moniteur sans disponibilité réelle ne prouve pas son rôle', () => {
  const withoutAvailability = snapshot({
    memberships: [{ schoolId: 'ecole-1', roles: ['INSTRUCTOR'], grants: [], status: 'ACTIVE', accessEpoch: 1 }], availability: []
  });
  assert.deepEqual(requirementGaps(withoutAvailability, 'INSTRUCTOR'), ['au moins une disponibilité']);
});

test('Un compte qui ne porte pas le rôle demandé est refusé, quel que soit son contenu', () => {
  const learnerOnly = snapshot({
    memberships: [{ schoolId: 'ecole-1', roles: ['LEARNER'], grants: [], status: 'ACTIVE', accessEpoch: 1 }], instructorLessons: []
  });
  assert.deepEqual(requirementGaps(learnerOnly, 'ADMIN'), ['rôle admin', 'au moins une leçon donnée']);
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
