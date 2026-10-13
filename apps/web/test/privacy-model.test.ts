import { describe, expect, it } from 'vitest';
import { profilePolicyProblem, type ProfileRule } from '../client/command-core.js';
import { matchSchoolRoute } from '../server/school-routes.js';
import { gpsConsentLabel, impactSentences, initialDrafts, rulesOf } from '../client/console/privacy-model.js';
import type { ProfilePolicy, TextProposals } from '../client/school-api.js';

const school = '10000000-0000-4000-8000-000000000001';
const proposals: TextProposals = {
  dataPolicy: { noticeText: 'n'.repeat(50), retentionText: 'r'.repeat(50), contactEmail: 'contact@example.test' },
  profileFields: [
    { field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous reconnaître.' },
    { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous reconnaître.' },
    { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous prévenir.' },
  ],
  procedure: { procedureText: 'Déroulement.', cancellationPolicyText: 'Annulation.' },
  commercialTerms: { label: 'Conditions générales', termsText: 'Conditions.' },
};
const policy = (fields: ProfileRule[]): ProfilePolicy => ({ id: school, schoolId: school, version: 2, status: 'PUBLISHED', effectiveFrom: '2026-01-01T00:00:00.000Z',
  fields, noticeVersionId: school, approvedByMembershipId: school });

describe('Informations demandées en tableau', () => {
  it('les règles proposées donnent une version valide, sans rien de requis avant une leçon', () => {
    const rules = rulesOf(initialDrafts(null, proposals));
    expect(profilePolicyProblem(rules)).toBeNull();
    expect(rules.map(rule => `${rule.field}:${rule.stage}`)).toEqual(['firstName:JOIN', 'lastName:JOIN', 'contactPhone:OPTIONAL']);
  });
  it('« Requis avant une leçon » devient une règle requise avant une leçon, avec son utilité', () => {
    const drafts = initialDrafts(null, proposals);
    drafts.birthDate = { ...drafts.birthDate, choice: 'lesson' };
    const birth = rulesOf(drafts).find(rule => rule.field === 'birthDate');
    expect(birth).toMatchObject({ requirement: 'REQUIRED', stage: 'BEFORE_LESSON', purposeCode: 'CERTIFICATE' });
    expect(profilePolicyProblem(rulesOf(drafts))).toBeNull();
  });
  it('une règle « avant un cours » existante est conservée telle quelle', () => {
    const course: ProfileRule = { field: 'birthDate', requirement: 'CONDITIONAL', stage: 'BEFORE_COURSE', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Âge minimal du cours.' };
    const names = proposals.profileFields.slice(0, 2) as ProfileRule[];
    const rules = rulesOf(initialDrafts(policy([...names, course]), proposals));
    expect(rules).toEqual([...names, course]);
  });
});

describe('Accord GPS dans le dossier', () => {
  const choice = { learnerId: school, status: 'ALLOWED' as const, source: 'SELF' as const, recordedAt: '2026-10-13T08:00:00.000Z', currentNotice: true, lessonScoped: false };
  it('dit le choix en vigueur, et signale seulement l’accord donné sur d’anciens textes', () => {
    expect(gpsConsentLabel(undefined)).toEqual({ text: 'Pas encore donné', renew: false });
    expect(gpsConsentLabel(choice)).toEqual({ text: 'Avec GPS', renew: false });
    expect(gpsConsentLabel({ ...choice, status: 'REFUSED' })).toEqual({ text: 'Sans GPS', renew: false });
    expect(gpsConsentLabel({ ...choice, lessonScoped: true }).text).toBe('Avec GPS · pour une leçon');
    expect(gpsConsentLabel({ ...choice, currentNotice: false })).toEqual({ text: 'À redonner', renew: true });
  });
});

describe('Effet d’une nouvelle version et routes relayées', () => {
  it('chiffre l’effet, ou le dit sans chiffre si la lecture a échoué', () => {
    expect(impactSentences({ gpsAgreements: 23, activeCaptures: 0 })).toEqual(['23 élèves avaient accepté le GPS avec les textes actuels : la question leur sera reposée.']);
    expect(impactSentences({ gpsAgreements: 0, activeCaptures: 0 })).toEqual([]);
    expect(impactSentences(null).length).toBe(1);
  });
  it('le BFF relaie les textes proposés et les accords GPS en lecture seule', () => {
    for (const path of ['text-proposals', 'recording-choices']) {
      expect(matchSchoolRoute('GET', `/schools/${school}/${path}`, '')).toBeDefined();
      expect(matchSchoolRoute('POST', `/schools/${school}/${path}`, '')).toBeUndefined();
    }
  });
});
