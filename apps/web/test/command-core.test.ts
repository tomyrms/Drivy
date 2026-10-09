import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  assignmentIsOpen, availableTrainingOfferings, classifyFailure, commandHeaders, commandMessage, commandSpecs, createCommand, instantToSchoolTime, isEmail, latestPermit, matchesSearch, normalizeSearch,
  parseCents, parseMetadata, permitBody, permitProblem, permitState, profilePolicyProblem, receiptMatches, schoolTimeToInstant, toMetadata,
  trainingTransitions, transitionProblem, type PermitDraft, type ProfileRule,
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
    // Session lost while the school was answering: the command may have been committed.
    expect(classifyFailure(401, 'SESSION_LOST_RESULT_UNKNOWN', true)).toEqual({ type: 'uncertain', code: 'SESSION_LOST_RESULT_UNKNOWN', needsLogin: true });
    expect(classifyFailure(403, 'CSRF_REJECTED', true).type).toBe('uncertain');
  });

  test('tout refus 4xx avec un code est définitif sur un premier envoi ; après incertitude il ne prouve rien', () => {
    for (const [status, code] of [[412, 'VERSION_CONFLICT'], [409, 'LAST_ADMIN'], [409, 'OFFERING_NOT_READY'], [422, 'PROFILE_POLICY_RULE_INVALID'],
      [409, 'INVITATION_DELIVERY_UNAVAILABLE'], [403, 'SETUP_ACCESS_REQUIRED'], [404, 'NOT_FOUND'], [422, 'UN_CODE_QUE_LE_CLIENT_NE_CONNAIT_PAS']] as const) {
      expect(classifyFailure(status, code, true), code).toEqual({ type: 'rejected', code, needsLogin: false });
      expect(classifyFailure(status, code, false), code).toEqual({ type: 'review', code, needsLogin: false });
    }
  });

  test('une session perdue ou une réauthentification demandée est un refus qui propose de se reconnecter', () => {
    for (const code of ['SESSION_EXPIRED', 'REAUTH_REQUIRED']) {
      expect(classifyFailure(401, code, true)).toEqual({ type: 'rejected', code, needsLogin: true });
      expect(classifyFailure(401, code, false)).toEqual({ type: 'review', code, needsLogin: true });
    }
  });

  test('seule une clé déjà utilisée ne prouve rien au premier envoi ; un refus 4xx illisible reste un refus', () => {
    expect(classifyFailure(409, 'IDEMPOTENCY_MISMATCH', true)).toEqual({ type: 'review', code: 'IDEMPOTENCY_MISMATCH', needsLogin: false });
    for (const [status, code] of [[400, 'REQUEST_FAILED'], [400, 'API_UNAVAILABLE'], [413, 'REQUEST_FAILED'], [422, 'INVALID_RESPONSE']] as const) {
      expect(classifyFailure(status, code, true), code).toEqual({ type: 'rejected', code, needsLogin: false });
      expect(classifyFailure(status, code, false), code).toEqual({ type: 'review', code, needsLogin: false });
    }
  });

  test('un délai dépassé (408) laisse le résultat inconnu : la même demande peut être renvoyée', () => {
    expect(classifyFailure(408, 'TIMEOUT', true)).toEqual({ type: 'uncertain', code: 'TIMEOUT', needsLogin: false });
    expect(classifyFailure(408, 'REQUEST_FAILED', false).type).toBe('uncertain');
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

describe('Invitation par code élève', () => {
  const offeringId = randomUUID(), instructorMembershipId = randomUUID();
  const create = () => createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
    body: { delivery: 'CODE', roles: ['LEARNER'], training: { offeringId, instructorMembershipId } } });

  test('la création part de zéro, sans If-Match, avec l’operationId dans le corps et en Idempotency-Key', () => {
    const command = create();
    expect(command.body).toEqual({ delivery: 'CODE', roles: ['LEARNER'], training: { offeringId, instructorMembershipId }, operationId: command.operationId });
    const headers = commandHeaders(command, 'csrf');
    expect(headers['Idempotency-Key']).toBe(command.operationId);
    expect(headers['If-Match']).toBeUndefined();
    expect(commandSpecs.createInvitation).toMatchObject({ method: 'POST', expectedStatus: 201, target: 'created' });
  });

  test('un nouveau code exige la version de l’invitation (If-Match) et répond 200', () => {
    const invitation = randomUUID();
    const renew = createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${invitation}/resend`, ifMatch: 3, resourceId: invitation, resourceVersion: 3, body: {} });
    expect(commandHeaders(renew, 'csrf')['If-Match']).toBe('"3"');
    expect(commandSpecs.resendInvitation).toMatchObject({ method: 'POST', expectedStatus: 200, target: 'resource' });
    const receipt = { operationId: renew.operationId, commandType: 'RESEND_INVITATION', resourceType: 'Invitation', resourceId: invitation,
      committedAt: '2026-09-29T08:00:00Z', resourceVersion: 4 };
    expect(receiptMatches(renew, receipt)).toBe(true);
    expect(receiptMatches(renew, { ...receipt, resourceVersion: 3 })).toBe(false);
    expect(() => createCommand({ schoolId, kind: 'resendInvitation', path: 'invitations/x/resend', body: {}, resourceVersion: 3 })).toThrow();
  });

  test('offre ou moniteur refusés : un premier envoi est libéré pour correction, un renvoi doit être vérifié', () => {
    for (const code of ['INVITATION_TRAINING_INVALID', 'INVITATION_CODE_INVALID'] as const) {
      expect(classifyFailure(422, code, true)).toEqual({ type: 'rejected', code, needsLogin: false });
      expect(classifyFailure(422, code, false)).toEqual({ type: 'review', code, needsLogin: false });
      expect(commandMessage(code)).not.toBe(commandMessage('CODE_INCONNU'));
    }
    expect(commandMessage('INVITATION_TRAINING_INVALID')).toBe('Choisissez une offre ouverte et un moniteur actif.');
    expect(classifyFailure(503, 'INVITATION_DELIVERY_UNAVAILABLE', true).type).toBe('uncertain');
  });

  test('le journal d’une demande ne garde ni l’offre, ni le moniteur, ni aucun code', () => {
    const stored = JSON.stringify(toMetadata(create()));
    expect(stored).not.toContain(offeringId);
    expect(stored).not.toContain(instructorMembershipId);
    expect(stored).not.toContain('CODE');
    expect(stored).not.toContain('training');
    expect(parseMetadata({ ...JSON.parse(stored), code: 'K7Q4-MX2P' })).toBeNull();
    expect(parseMetadata({ ...JSON.parse(stored), training: { offeringId } })).toBeNull();
  });
});

describe('Dossier de l’élève : formation, permis, archivage, accès', () => {
  const training = randomUUID();

  test('une formation active peut être suspendue, terminée ou annulée ; une formation close ne change plus', () => {
    expect(trainingTransitions('ACTIVE').map(item => item.target)).toEqual(['PAUSED', 'COMPLETED', 'CANCELLED']);
    expect(trainingTransitions('PAUSED').map(item => item.target)).toEqual(['ACTIVE', 'COMPLETED', 'CANCELLED']);
    expect(trainingTransitions('COMPLETED').map(item => item.target)).toEqual(['ACTIVE']);
    expect(trainingTransitions('CANCELLED').map(item => item.target)).toEqual(['ACTIVE']);
    const cancel = trainingTransitions('ACTIVE').find(item => item.target === 'CANCELLED')!;
    expect(transitionProblem(cancel, '   ')).not.toBeNull();
    expect(transitionProblem(cancel, 'L’élève a déménagé.')).toBeNull();
    for (const status of ['ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED'] as const) {
      for (const transition of trainingTransitions(status)) {
        expect(transitionProblem(transition, '')).not.toBeNull();
        expect(transitionProblem(transition, 'Demande de l’élève.')).toBeNull();
      }
    }
    expect(transitionProblem(cancel, 'x'.repeat(1001))).not.toBeNull();
  });

  test('les nouvelles commandes visent la bonne ressource avec If-Match et ne se rejouent que sur reçu concordant', () => {
    const assignment = randomUUID(), learner = randomUUID(), member = randomUUID();
    for (const [kind, path, id, type, resource] of [
      ['transitionTraining', `trainings/${training}/transition`, training, 'TRANSITION_TRAINING', 'Training'],
      ['endAssignment', `trainings/${training}/assignments/${assignment}/end`, assignment, 'END_ASSIGNMENT', 'Assignment'],
      ['archiveLearner', `learners/${learner}/archive`, learner, 'ARCHIVE_LEARNER', 'Learner'],
      ['restoreLearner', `learners/${learner}/restore`, learner, 'RESTORE_LEARNER', 'Learner'],
      ['deactivateMember', `members/${member}/deactivate`, member, 'DEACTIVATE_MEMBER', 'Member'],
    ] as const) {
      const command = createCommand({ schoolId, kind, path, ifMatch: 4, resourceId: id, resourceVersion: 4, body: { reason: 'Motif' } });
      expect(commandHeaders(command, 'csrf')['If-Match']).toBe('"4"');
      const receipt = { operationId: command.operationId, commandType: type, resourceType: resource, resourceId: id, committedAt: '2026-09-29T08:00:00Z', resourceVersion: 5 };
      expect(receiptMatches(command, receipt), kind).toBe(true);
      expect(receiptMatches(command, { ...receipt, resourceId: randomUUID() }), kind).toBe(false);
      expect(() => createCommand({ schoolId, kind, path, body: {}, resourceVersion: 4 }), kind).toThrow();
    }
    const modules = createCommand({ schoolId, kind: 'updateModules', path: 'modules', ifMatch: 9, resourceVersion: 9, body: { gpsEnabled: false } });
    expect(commandSpecs.updateModules.method).toBe('PUT');
    expect(receiptMatches(modules, { operationId: modules.operationId, commandType: 'UPDATE_SCHOOL_MODULES', resourceType: 'School', resourceId: schoolId,
      committedAt: '2026-09-29T08:00:00Z', resourceVersion: 10 })).toBe(true);
    const permit = createCommand({ schoolId, kind: 'recordPermitCheck', path: `trainings/${training}/permit-checks`, ifMatch: 3, resourceVersion: 0,
      body: permitBody({ physicalSeen: true, validUntil: '', decision: 'APPROVED', reason: '' }, 'B') });
    expect(commandHeaders(permit, 'csrf')['If-Match']).toBe('"3"');
    expect(commandSpecs.recordPermitCheck).toMatchObject({ target: 'created', expectedStatus: 200 });
  });

  test('une affectation annulée avant son début est déjà terminée', () => {
    const now = Date.parse('2026-09-29T10:00:00Z');
    const past = '2026-09-28T10:00:00Z', future = '2026-09-30T10:00:00Z';
    expect(assignmentIsOpen({ validFrom: past, validUntil: null }, now)).toBe(true);
    expect(assignmentIsOpen({ validFrom: future, validUntil: null }, now)).toBe(true);
    expect(assignmentIsOpen({ validFrom: past, validUntil: future }, now)).toBe(true);
    expect(assignmentIsOpen({ validFrom: past, validUntil: '2026-09-29T10:00:00Z' }, now)).toBe(false);
    expect(assignmentIsOpen({ validFrom: future, validUntil: future }, now)).toBe(false);
  });

  test('une nouvelle version de l’offre ne propose pas une seconde formation active ou en pause', () => {
    const oldB = { id: randomUUID(), offeringKey: 'b-standard' };
    const newB = { id: randomUUID(), offeringKey: 'b-standard' };
    const a = { id: randomUUID(), offeringKey: 'a-standard' };
    const ready = [newB, a], all = [oldB, newB, a];
    for (const status of ['ACTIVE', 'PAUSED'] as const) {
      expect(availableTrainingOfferings(ready, all, [{ offeringId: oldB.id, status }])).toEqual([a]);
    }
    for (const status of ['COMPLETED', 'CANCELLED'] as const) {
      expect(availableTrainingOfferings(ready, all, [{ offeringId: oldB.id, status }])).toEqual(ready);
    }
    expect(availableTrainingOfferings(ready, [], [{ offeringId: newB.id, status: 'ACTIVE' }])).toEqual([a]);
  });

  test('contrôle du permis : original vu et date en vigueur pour approuver, motif pour refuser', () => {
    const draft = (change: Partial<PermitDraft>): PermitDraft => ({ physicalSeen: true, validUntil: '2031-05-04', decision: 'APPROVED', reason: '', ...change });
    const today = '2026-09-29';
    expect(permitProblem(draft({}), today)).toBeNull();
    expect(permitProblem(draft({ validUntil: '' }), today)).toBeNull();
    expect(permitProblem(draft({ physicalSeen: false }), today)).not.toBeNull();
    expect(permitProblem(draft({ validUntil: '2026-09-28' }), today)).not.toBeNull();
    expect(permitProblem(draft({ validUntil: '2026-09-29' }), today)).toBeNull();
    expect(permitProblem(draft({ validUntil: '2026-02-30' }), today)).not.toBeNull();
    expect(permitProblem(draft({ decision: 'REJECTED', physicalSeen: false }), today)).not.toBeNull();
    expect(permitProblem(draft({ decision: 'REJECTED', physicalSeen: false, reason: 'Permis provisoire' }), today)).toBeNull();
    expect(permitBody(draft({ validUntil: '' }), 'B')).toEqual({ documentId: null, physicalSeen: true, categoryCode: 'B', validUntil: null, decision: 'APPROVED', reason: null });
  });

  test('l’état du permis est celui de la dernière décision de la catégorie', () => {
    expect(permitState(undefined)).toBe('none');
    expect(permitState({ decision: 'APPROVED', isExpired: false })).toBe('valid');
    expect(permitState({ decision: 'APPROVED', isExpired: true })).toBe('expired');
    expect(permitState({ decision: 'REJECTED', isExpired: false })).toBe('rejected');
    const history = [{ categoryCode: 'B', n: 1 }, { categoryCode: 'A', n: 2 }, { categoryCode: 'B', n: 3 }];
    expect(latestPermit(history, 'B')?.n).toBe(3);
    expect(latestPermit(history, 'C')).toBeUndefined();
  });

  test('recherche insensible à la casse et aux accents', () => {
    expect(normalizeSearch('  Éloïse ')).toBe('eloise');
    expect(matchesSearch(['Éloïse Müller', 'eloise@example.test'], 'eloi')).toBe(true);
    expect(matchesSearch(['Éloïse Müller', null], 'muller')).toBe(true);
    expect(matchesSearch(['Éloïse Müller', 'eloise@example.test'], 'EXAMPLE')).toBe(true);
    expect(matchesSearch(['Éloïse Müller'], 'zoe')).toBe(false);
    expect(matchesSearch(['Éloïse'], '   ')).toBe(true);
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
