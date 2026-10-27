import { describe, expect, it } from 'vitest';
import {
  courseErrorMessage, courseRosterSchema, enrollableLearners, policyBody, policyForm, policyProblems, reasonProblem, rescheduleBody, sourceLabel,
  cancellationLabel, capacityProblem, emptyForm, formFromSeries, formatHours, preview, seriesBody, seriesByDay, typeProblem, validate,
  type CourseSeries, type SeriesForm,
  activePayments, attendanceBody, attendanceCell, canMarkAttendance, canValidateRow, courseSheetRowSchema, courseSheetSchema, paymentProblem, requirementLabel,
  type CourseSheetRow,
} from '../client/console/course-model.js';

const zone = 'Europe/Zurich';
const instructor = '11111111-1111-4111-8111-111111111111';
const type = '22222222-2222-4222-8222-222222222222';

const form = (patch: Partial<SeriesForm> = {}): SeriesForm => ({
  typeId: type, title: 'Cours de sensibilisation', description: '', location: 'Salle 1', conditions: '', language: '',
  responsible: instructor, capacity: '12', minimum: '', sessions: [
    { key: 'a', date: '2026-11-03', start: '18:00', end: '20:00', instructor, attendanceRequired: true },
    { key: 'b', date: '2026-11-05', start: '18:00', end: '20:00', instructor, attendanceRequired: true },
  ], ...patch,
});

describe('cours collectifs : validation locale', () => {
  it('accepte une saisie complète', () => {
    expect(validate(form(), zone)).toEqual({ fields: {}, sessions: {} });
  });
  it('refuse une fin avant le début', () => {
    const result = validate(form({ sessions: [{ key: 'a', date: '2026-11-03', start: '20:00', end: '18:00', instructor, attendanceRequired: true }] }), zone);
    expect(result.sessions.a).toBe('La fin doit suivre le début.');
  });
  it('refuse deux séances qui se chevauchent', () => {
    const result = validate(form({ sessions: [
      { key: 'a', date: '2026-11-03', start: '18:00', end: '20:00', instructor, attendanceRequired: true },
      { key: 'b', date: '2026-11-03', start: '19:30', end: '21:00', instructor, attendanceRequired: true },
    ] }), zone);
    expect(result.sessions.b).toBe('Chevauche une autre séance.');
    expect(result.sessions.a).toBeUndefined();
  });
  it('accepte deux séances bout à bout', () => {
    const result = validate(form({ sessions: [
      { key: 'a', date: '2026-11-03', start: '18:00', end: '19:00', instructor, attendanceRequired: true },
      { key: 'b', date: '2026-11-03', start: '19:00', end: '20:00', instructor, attendanceRequired: true },
    ] }), zone);
    expect(result.sessions).toEqual({});
  });
  it('refuse un minimum supérieur à la capacité', () => {
    expect(validate(form({ capacity: '5', minimum: '6' }), zone).fields.minimum).toBe('Le minimum dépasse la capacité.');
    expect(validate(form({ capacity: '5', minimum: '5' }), zone).fields.minimum).toBeUndefined();
  });
  it('exige titre, capacité valide, moniteur et au moins une séance', () => {
    const result = validate(form({ title: ' ', capacity: '0', sessions: [] }), zone);
    expect(Object.keys(result.fields).sort()).toEqual(['capacity', 'sessions', 'title']);
    const noInstructor = validate(form({ sessions: [{ key: 'a', date: '2026-11-03', start: '18:00', end: '20:00', instructor: '', attendanceRequired: true }] }), zone);
    expect(noInstructor.sessions.a).toBe('Choisissez un moniteur.');
  });
  it('refuse une heure sautée par le passage à l’heure d’été', () => {
    const result = validate(form({ sessions: [{ key: 'a', date: '2027-03-28', start: '02:30', end: '03:30', instructor, attendanceRequired: true }] }), zone);
    expect(result.sessions.a).toBe('Cette heure n’existe pas ce jour-là.');
  });
});

describe('cours collectifs : corps et aperçu', () => {
  it('construit le corps dans le fuseau de l’école, séances triées', () => {
    const body = seriesBody(form({ minimum: '4', language: 'fr', sessions: [...form().sessions].reverse() }), zone)!;
    expect(body).toMatchObject({ typeId: type, capacity: 12, minParticipants: 4, teachingLanguage: 'fr', timeZone: zone });
    expect(body.occurrences).toEqual([
      { startsAt: '2026-11-03T17:00:00.000Z', endsAt: '2026-11-03T19:00:00.000Z', instructorMembershipId: instructor, attendanceRequired: true },
      { startsAt: '2026-11-05T17:00:00.000Z', endsAt: '2026-11-05T19:00:00.000Z', instructorMembershipId: instructor, attendanceRequired: true },
    ]);
  });
  it('ne construit rien pour une saisie invalide', () => {
    expect(seriesBody(form({ capacity: '' }), zone)).toBeNull();
  });
  it('totalise les heures', () => {
    expect(preview(form(), zone).totalMinutes).toBe(240);
    expect(formatHours(240)).toBe('4 h');
    expect(formatHours(90)).toBe('1 h 30');
  });
  it('formule l’échéance d’annulation', () => {
    expect(cancellationLabel(24)).toBe('Annulation libre jusqu’à 24 h avant la première séance');
    expect(cancellationLabel(72)).toBe('Annulation libre jusqu’à 3 jours avant la première séance');
  });
  it('relit une série en heures murales', () => {
    const series = {
      id: type, typeId: type, title: 'T', description: '', location: '', conditions: '', teachingLanguage: 'de', responsibleMembershipId: instructor,
      capacity: 8, minParticipants: null,
      occurrences: [{ id: type, position: 1, startsAt: '2026-11-03T17:00:00Z', endsAt: '2026-11-03T19:15:00Z', timeZone: zone, instructorMembershipId: instructor, instructorDisplayName: 'A', attendanceRequired: false }],
    } as unknown as CourseSeries;
    const result = formFromSeries(series, zone);
    expect(result).toMatchObject({ capacity: '8', minimum: '', language: 'de' });
    expect(result.sessions[0]).toMatchObject({ date: '2026-11-03', start: '18:00', end: '20:15', attendanceRequired: false });
    // La protection de fermeture compare le formulaire au cours relu : les clés ne créent pas de faux changement.
    expect(formFromSeries(series, zone)).toEqual(result);
    expect(result.sessions[0]!.key).toBe(type);
  });
  it('prépare un formulaire vide avec le seul moniteur', () => {
    const result = emptyForm({ types: [], instructors: [{ membershipId: instructor, displayName: 'A' }] });
    expect(result.sessions[0]!.instructor).toBe(instructor);
  });
});

describe('cours collectifs : capacité, types et agenda', () => {
  it('refuse une capacité sous les places prises ou le minimum', () => {
    expect(capacityProblem('3', { seatsTaken: 4, minParticipants: null, capacity: 10 })).toBe('4 places sont déjà prises.');
    expect(capacityProblem('5', { seatsTaken: 0, minParticipants: 6, capacity: 10 })).toBe('La capacité passe sous le minimum.');
    expect(capacityProblem('12', { seatsTaken: 4, minParticipants: 6, capacity: 10 })).toBeNull();
  });
  it('refuse un type sans nom ou déjà présent', () => {
    const existing = [{ id: type, schoolId: null, stableKey: null, title: 'Premiers secours', description: '', version: 1, predefined: true }];
    expect(typeProblem('', '', existing)).toBe('Indiquez un nom.');
    expect(typeProblem(' premiers secours ', '', existing)).toBe('Ce type existe déjà.');
    expect(typeProblem('Atelier', '', existing)).toBeNull();
  });
  it('place chaque séance de la semaine à son jour', () => {
    const series = { occurrences: [
      { id: 'o1', startsAt: '2026-11-03T17:00:00Z', endsAt: '2026-11-03T19:00:00Z' },
      { id: 'o2', startsAt: '2026-11-12T17:00:00Z', endsAt: '2026-11-12T19:00:00Z' },
    ] } as unknown as CourseSeries;
    const days = seriesByDay([series], instant => instant.slice(0, 10), Date.parse('2026-11-02T00:00:00Z'), Date.parse('2026-11-09T00:00:00Z'));
    expect([...days.keys()]).toEqual(['2026-11-03']);
  });
});

describe('cours collectifs : inscrits, dates et réglages', () => {
  const occurrence = (position: number) => ({ id: type, position, startsAt: '2026-11-03T17:00:00Z', endsAt: '2026-11-03T19:00:00Z', timeZone: zone, instructorMembershipId: instructor, instructorDisplayName: 'A', attendanceRequired: true });
  it('reprogramme avec le même nombre de séances, positions d’origine', () => {
    const series = { occurrences: [occurrence(1), occurrence(2)] };
    const body = rescheduleBody(series, form().sessions, zone);
    expect(body?.occurrences).toEqual([
      { position: 1, startsAt: '2026-11-03T17:00:00.000Z', endsAt: '2026-11-03T19:00:00.000Z', instructorMembershipId: instructor },
      { position: 2, startsAt: '2026-11-05T17:00:00.000Z', endsAt: '2026-11-05T19:00:00.000Z', instructorMembershipId: instructor },
    ]);
    expect(rescheduleBody({ occurrences: [occurrence(1)] }, form().sessions, zone)).toBeNull();
    expect(rescheduleBody(series, form({ sessions: [form().sessions[0]!, { ...form().sessions[1]!, start: '21:00' }] }).sessions, zone)).toBeNull();
  });
  it('exige un motif borné', () => {
    expect(reasonProblem('  ')).toBe('Indiquez le motif.');
    expect(reasonProblem('x'.repeat(1001))).not.toBeNull();
    expect(reasonProblem('Maladie')).toBeNull();
  });
  it('propose seulement les élèves actifs ni inscrits ni en file', () => {
    const learner = (id: string, displayName: string, archivedAt: string | null = null) => ({ id, displayName, archivedAt });
    const roster = courseRosterSchema.parse({ items: [{ id: type, seriesId: type, learnerId: 'a1111111-1111-4111-8111-111111111111', version: 1, status: 'ACTIVE', source: 'STAFF', selfCancelDeadline: '2026-11-01T17:00:00Z', createdAt: '2026-10-01T17:00:00Z', cancelledAt: null, cancelKind: null, cancelReason: null, learnerDisplayName: 'Ana' }],
      waitlist: [{ id: type, learnerId: 'b1111111-1111-4111-8111-111111111111', learnerDisplayName: 'Ben', position: 1, status: 'OFFERED', queuedAt: '2026-10-01T17:00:00Z', offerExpiresAt: '2026-10-02T05:00:00Z' }] });
    const result = enrollableLearners([learner('a1111111-1111-4111-8111-111111111111', 'Ana'), learner('b1111111-1111-4111-8111-111111111111', 'Ben'), learner('c', 'Zoé'), learner('d', 'Élie'), learner('e', 'Old', '2026-01-01T00:00:00Z')], roster);
    expect(result.map(item => item.displayName)).toEqual(['Élie', 'Zoé']);
    expect(sourceLabel('OFFER')).toBe('Liste d’attente');
  });
  it('lit et valide les réglages ; vide désactive la liste d’attente', () => {
    expect(policyForm({ selfCancelHours: 48, offerResponseMinutes: null })).toEqual({ selfCancelHours: '48', offerResponseMinutes: '' });
    expect(policyBody({ selfCancelHours: '48', offerResponseMinutes: '' })).toEqual({ selfCancelHours: 48, offerResponseMinutes: null });
    expect(policyBody({ selfCancelHours: '0', offerResponseMinutes: '720' })).toEqual({ selfCancelHours: 0, offerResponseMinutes: 720 });
    expect(policyProblems({ selfCancelHours: '721', offerResponseMinutes: '10' })).toEqual({ selfCancelHours: 'Entre 0 et 720 heures.', offerResponseMinutes: 'Entre 15 et 10080 minutes.' });
    expect(policyBody({ selfCancelHours: '', offerResponseMinutes: '' })).toBeNull();
  });
  it('traduit le conflit d’agenda des nouvelles dates', () => {
    expect(courseErrorMessage('COURSE_SCHEDULE_CONFLICT')).toContain('rendez-vous');
    expect(courseErrorMessage('COURSE_FULL')).toBe('Ce cours est complet.');
  });
});

describe('cours collectifs : feuille du cours', () => {
  const enrollment = 'e1111111-1111-4111-8111-111111111111', occurrence = 'f1111111-1111-4111-8111-111111111111';
  const row = (patch: Partial<CourseSheetRow> = {}): CourseSheetRow => courseSheetRowSchema.parse({
    enrollmentId: enrollment, learnerId: instructor, learnerDisplayName: 'Ana', status: 'ACTIVE', cancelledAt: null,
    attendance: [], requirements: { required: 3, present: 2, missing: 1 }, payments: [], completion: null, ...patch,
  });
  const all = { rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true } };
  it('laisse vide une cellule absente, jamais déduite', () => {
    expect(attendanceCell(row(), occurrence)).toEqual({ occurrenceId: occurrence, status: null, version: null, recordedAt: null });
  });
  it('première saisie sans version, correction avec la version lue, rien si inchangé', () => {
    expect(attendanceBody(attendanceCell(row(), occurrence), 'PRESENT')).toEqual({ status: 'PRESENT', expectedVersion: null, note: null });
    const marked = row({ attendance: [{ occurrenceId: occurrence, status: 'ABSENT', version: 4, recordedAt: '2026-11-03T18:00:00Z' }] });
    expect(attendanceBody(attendanceCell(marked, occurrence), 'EXCUSED')).toEqual({ status: 'EXCUSED', expectedVersion: 4, note: null });
    expect(attendanceBody(attendanceCell(marked, occurrence), 'ABSENT')).toBeNull();
  });
  it('saisie seulement avec le droit, séance commencée et inscription active', () => {
    const now = Date.parse('2026-11-03T18:00:00Z');
    expect(canMarkAttendance(all, row(), { startsAt: '2026-11-03T17:00:00Z' }, now)).toBe(true);
    expect(canMarkAttendance(all, row(), { startsAt: '2026-11-05T17:00:00Z' }, now)).toBe(false);
    expect(canMarkAttendance({ rights: { ...all.rights, canTakeAttendance: false } }, row(), { startsAt: '2026-11-03T17:00:00Z' }, now)).toBe(false);
    expect(canMarkAttendance(all, row({ status: 'CANCELLED' }), { startsAt: '2026-11-03T17:00:00Z' }, now)).toBe(false);
  });
  it('compte les séances obligatoires', () => {
    expect(requirementLabel({ required: 3, present: 2, missing: 1 })).toBe('2 sur 3 séances obligatoires');
    expect(requirementLabel({ required: 1, present: 0, missing: 1 })).toBe('0 sur 1 séance obligatoire');
  });
  it('valide seulement sans séance manquante, avec le droit, sans validation active', () => {
    expect(canValidateRow(all, row())).toBe(false);
    const complete = row({ requirements: { required: 3, present: 3, missing: 0 } });
    expect(canValidateRow(all, complete)).toBe(true);
    expect(canValidateRow({ rights: { ...all.rights, canValidate: false } }, complete)).toBe(false);
    expect(canValidateRow(all, row({ ...complete, completion: { id: occurrence, validatedAt: '2026-11-05T19:00:00Z', seriesId: null, revokedAt: null } }))).toBe(false);
    expect(canValidateRow(all, row({ requirements: { required: 0, present: 0, missing: 0 } }))).toBe(false);
  });
  it('ignore les règlements annulés et borne la note', () => {
    const payments = [
      { id: occurrence, amountCents: 12000, recordedAt: '2026-11-03T18:00:00Z', note: null, voidedAt: null, voidReason: null },
      { id: enrollment, amountCents: 5000, recordedAt: '2026-11-03T18:05:00Z', note: null, voidedAt: '2026-11-03T18:10:00Z', voidReason: 'Erreur' },
    ];
    expect(activePayments(row({ payments })).map(item => item.amountCents)).toEqual([12000]);
    expect(paymentProblem(null, '')).toContain('CHF');
    expect(paymentProblem(12000, 'x'.repeat(501))).toBe('500 caractères au plus.');
    expect(paymentProblem(12000, '')).toBeNull();
  });
  it('lit la feuille et traduit les refus', () => {
    expect(courseSheetSchema.safeParse({ series: {}, rights: all.rights, rows: [] }).success).toBe(false);
    expect(courseErrorMessage('COURSE_REQUIREMENTS_MISSING')).toBe('Des séances obligatoires manquent.');
    expect(courseErrorMessage('COURSE_OCCURRENCE_NOT_STARTED')).toBe('Cette séance n’a pas encore commencé.');
  });
});
