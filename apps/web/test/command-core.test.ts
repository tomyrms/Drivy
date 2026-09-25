import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  classifyFailure, commandHeaders, createCommand, instantToSchoolTime, isEmail, parseCents, parseMetadata,
  profilePolicyProblem, receiptMatches, schoolTimeToInstant, toMetadata, type ProfileRule,
} from '../client/command-core.js';

const schoolId = randomUUID();

describe('Commande de gestion : même demande jusqu’à confirmation', () => {
  test('operationId = Idempotency-Key, If-Match fort, en-têtes identiques à chaque renvoi', () => {
    const command = createCommand({ schoolId, kind: 'updateSchool', path: '', body: { name: 'École synthétique', operationId: 'ignored' },
      ifMatch: 3, resourceVersion: 3 });
    expect(command.body.operationId).toBe(command.operationId);
    expect(Object.isFrozen(command.body)).toBe(true);
    const first = commandHeaders(command, 'csrf-a');
    expect(first['Idempotency-Key']).toBe(command.operationId);
    expect(first['If-Match']).toBe('"3"');
    expect(commandHeaders(command, 'csrf-a')).toEqual(first);
    const creation = createCommand({ schoolId, kind: 'createOffering', path: 'offerings', body: {}, resourceVersion: 0 });
    expect(commandHeaders(creation, 'csrf')['If-Match']).toBeUndefined();
    expect(() => createCommand({ schoolId, kind: 'createOffering', path: 'offerings', body: {}, resourceVersion: 2 })).toThrow();
    expect(() => createCommand({ schoolId, kind: 'updateMember', path: 'members/x', body: {}, resourceVersion: 2 })).toThrow();
    expect(() => createCommand({ schoolId, kind: 'updateSchool', path: '../me', body: {}, resourceVersion: 2 })).toThrow();
  });

  test('une réponse perdue, un 5xx ou une session perdue gardent la demande incertaine', () => {
    for (const [status, code] of [[0, 'NETWORK_UNAVAILABLE'], [503, 'SERVICE_UNAVAILABLE'], [502, 'API_UNAVAILABLE'], [429, 'RATE_LIMITED'],
      [503, 'INVITATION_DELIVERY_UNAVAILABLE']] as const) {
      expect(classifyFailure(status, code, true)).toEqual({ type: 'uncertain', code, needsLogin: false });
    }
    expect(classifyFailure(401, 'SESSION_EXPIRED', true)).toEqual({ type: 'uncertain', code: 'SESSION_EXPIRED', needsLogin: true });
    expect(classifyFailure(403, 'CSRF_REJECTED', true).type).toBe('uncertain');
  });

  test('un refus métier libère seulement un premier envoi ; après incertitude il ne prouve rien', () => {
    for (const [status, code] of [[412, 'VERSION_CONFLICT'], [409, 'LAST_ADMIN'], [409, 'OFFERING_NOT_READY'], [401, 'REAUTH_REQUIRED'], [422, 'PROFILE_POLICY_RULE_INVALID']] as const) {
      expect(classifyFailure(status, code, true)).toEqual({ type: 'rejected', code });
      expect(classifyFailure(status, code, false)).toEqual({ type: 'review', code });
    }
    expect(classifyFailure(409, 'IDEMPOTENCY_MISMATCH', true)).toEqual({ type: 'review', code: 'IDEMPOTENCY_MISMATCH' });
    expect(classifyFailure(403, 'SETUP_ACCESS_REQUIRED', true).type).toBe('review');
    expect(classifyFailure(404, 'NOT_FOUND', true).type).toBe('review');
  });

  test('reçu AP72 : opération, type, ressource et version postérieure doivent correspondre', () => {
    const member = randomUUID();
    const command = createCommand({ schoolId, kind: 'updateMember', path: `members/${member}`, body: {}, ifMatch: 4, resourceId: member, resourceVersion: 4 });
    const receipt = { operationId: command.operationId.toUpperCase(), commandType: 'UPDATE_MEMBER', resourceType: 'Member', resourceId: member,
      committedAt: '2026-09-25T08:00:00Z', resourceVersion: 5 };
    expect(receiptMatches(command, receipt)).toBe(true);
    expect(receiptMatches(command, { ...receipt, resourceVersion: 4 })).toBe(false);
    expect(receiptMatches(command, { ...receipt, resourceId: randomUUID() })).toBe(false);
    expect(receiptMatches(command, { ...receipt, commandType: 'UPDATE_SCHOOL' })).toBe(false);
    expect(receiptMatches(command, { ...receipt, operationId: randomUUID() })).toBe(false);
    const school = createCommand({ schoolId, kind: 'activate', path: 'activate', body: {}, ifMatch: 7, resourceVersion: 7 });
    expect(receiptMatches(school, { ...receipt, operationId: school.operationId, commandType: 'ACTIVATE_SCHOOL', resourceType: 'School', resourceId: schoolId, resourceVersion: 8 })).toBe(true);
    expect(receiptMatches(school, { ...receipt, operationId: school.operationId, commandType: 'ACTIVATE_SCHOOL', resourceType: 'School', resourceId: randomUUID(), resourceVersion: 8 })).toBe(false);
    const created = createCommand({ schoolId, kind: 'createCurriculum', path: 'curricula', body: {}, resourceVersion: 0 });
    expect(receiptMatches(created, { ...receipt, operationId: created.operationId, commandType: 'CREATE_CURRICULUM_VERSION', resourceType: 'Curriculum', resourceId: randomUUID(), resourceVersion: 1 })).toBe(true);
  });

  test('seuls les identifiants survivent à un rechargement, jamais le contenu saisi', () => {
    const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', body: { email: 'personne@example.test', roles: ['LEARNER'] }, resourceVersion: 0 });
    const stored = JSON.stringify(toMetadata(command));
    expect(stored).not.toContain('personne@example.test');
    expect(parseMetadata(JSON.parse(stored))).toEqual(toMetadata(command));
    expect(parseMetadata({ ...JSON.parse(stored), body: {} })).toBeNull();
    expect(parseMetadata({ ...JSON.parse(stored), kind: 'deleteSchool' })).toBeNull();
    expect(parseMetadata({ ...JSON.parse(stored), operationId: 'x' })).toBeNull();
    expect(parseMetadata({ ...JSON.parse(stored), kind: 'revokeInvitation' })).toBeNull();
  });
});

describe('Règles de saisie', () => {
  test('montants CHF exacts, sans arrondi silencieux', () => {
    expect(parseCents('95')).toBe(9500); expect(parseCents('95,5')).toBe(9550); expect(parseCents(' 0.05 ')).toBe(5);
    for (const value of ['', '-1', '1.005', '1e3', 'abc', '1 000']) expect(parseCents(value), value).toBeNull();
  });
  test('adresse e-mail simple', () => {
    expect(isEmail('ecole@example.test')).toBe(true);
    for (const value of ['ecole', 'a@b', 'a b@example.test', '@example.test']) expect(isEmail(value), value).toBe(false);
  });
  test('heure de l’école convertie par son fuseau, changement d’heure compris', () => {
    expect(schoolTimeToInstant('2026-10-01T08:00', 'Europe/Zurich')).toBe('2026-10-01T06:00:00.000Z');
    expect(schoolTimeToInstant('2026-12-01T08:00', 'Europe/Zurich')).toBe('2026-12-01T07:00:00.000Z');
    expect(schoolTimeToInstant('2026-03-29T02:30', 'Europe/Zurich')).toBeNull();
    expect(schoolTimeToInstant('2026-02-30T08:00', 'Europe/Zurich')).toBeNull();
    expect(instantToSchoolTime('2026-10-01T06:00:00.000Z', 'Europe/Zurich')).toBe('2026-10-01T08:00');
  });
  test('politique de champs : nom et prénom requis à l’entrée, utilités autorisées seulement', () => {
    const name = (field: 'firstName' | 'lastName'): ProfileRule => ({ field, requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier la personne.' });
    expect(profilePolicyProblem([name('firstName'), name('lastName')])).toBeNull();
    expect(profilePolicyProblem([name('firstName')])).not.toBeNull();
    expect(profilePolicyProblem([name('firstName'), name('lastName'), { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'BEFORE_LESSON', purposeCode: 'LESSON_CONTACT', explanation: 'Joindre.' }])).not.toBeNull();
    expect(profilePolicyProblem([name('firstName'), name('lastName'), { field: 'birthDate', requirement: 'REQUIRED', stage: 'BEFORE_COURSE', purposeCode: 'LESSON_CONTACT', explanation: 'Âge.' }])).not.toBeNull();
    expect(profilePolicyProblem([name('firstName'), name('lastName'), { field: 'birthDate', requirement: 'CONDITIONAL', stage: 'BEFORE_COURSE', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Âge minimal.' }])).toBeNull();
  });
});
