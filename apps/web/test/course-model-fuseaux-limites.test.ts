import { describe, expect, it } from 'vitest';
import { instantToSchoolTime } from '../client/command-core.js';
import {
  canMarkAttendance, canValidateRow, cancellationLabel, capacityProblem, courseRosterSchema, courseSheetRowSchema, emptySession, enrollableLearners,
  formFromSeries, occurrenceStarted, paymentProblem, policyBody, policyProblems, preview, rescheduleBody, seriesBody, seriesByDay, sessionInterval, validate,
  type CourseSeries, type SeriesForm, type SessionForm,
} from '../client/console/course-model.js';

/**
 * Modèles de cours (#83) : changement d'heure Europe/Zurich et bornes des règles locales.
 * Aucune horloge réelle : les dates sont fixes. Changements d'heure 2027 : dimanche 28 mars (02:00 → 03:00, heure d'été)
 * et dimanche 31 octobre (03:00 → 02:00, retour à l'heure d'hiver ; 02:00 à 02:59 existe deux fois).
 */
const zone = 'Europe/Zurich';
const instructor = '11111111-1111-4111-8111-111111111111';
const type = '22222222-2222-4222-8222-222222222222';

const session = (key: string, date: string, start: string, end: string, patch: Partial<SessionForm> = {}): SessionForm =>
  ({ key, date, start, end, instructor, attendanceRequired: true, ...patch });
const form = (sessions: SessionForm[], patch: Partial<SeriesForm> = {}): SeriesForm => ({
  typeId: type, title: 'Cours de sensibilisation', description: '', location: 'Salle 1', conditions: '', language: '',
  responsible: instructor, capacity: '12', minimum: '', sessions, ...patch,
});
const occurrences = (body: Record<string, unknown> | null) => (body!.occurrences as { startsAt: string; endsAt: string }[]).map(item => [item.startsAt, item.endsAt]);

describe('séries à cheval sur le changement d’heure : même heure murale, instants décalés', () => {
  it('passage à l’heure d’été : 18:00 vaut 17:00 UTC avant, 16:00 UTC après', () => {
    const body = seriesBody(form([session('a', '2027-03-27', '18:00', '20:00'), session('b', '2027-03-28', '18:00', '20:00'), session('c', '2027-03-29', '18:00', '20:00')]), zone);
    expect(occurrences(body)).toEqual([
      ['2027-03-27T17:00:00.000Z', '2027-03-27T19:00:00.000Z'],
      ['2027-03-28T16:00:00.000Z', '2027-03-28T18:00:00.000Z'],
      ['2027-03-29T16:00:00.000Z', '2027-03-29T18:00:00.000Z'],
    ]);
  });
  it('retour à l’heure d’hiver : 18:00 vaut 16:00 UTC avant, 17:00 UTC après', () => {
    const body = seriesBody(form([session('a', '2027-10-30', '18:00', '20:00'), session('b', '2027-10-31', '18:00', '20:00'), session('c', '2027-11-01', '18:00', '20:00')]), zone);
    expect(occurrences(body)).toEqual([
      ['2027-10-30T16:00:00.000Z', '2027-10-30T18:00:00.000Z'],
      ['2027-10-31T17:00:00.000Z', '2027-10-31T19:00:00.000Z'],
      ['2027-11-01T17:00:00.000Z', '2027-11-01T19:00:00.000Z'],
    ]);
  });
  it('séances saisies dans le désordre : triées par instant réel, y compris de part et d’autre de la bascule', () => {
    const body = seriesBody(form([session('b', '2027-03-29', '09:00', '10:00'), session('a', '2027-03-27', '09:00', '10:00')]), zone);
    expect(occurrences(body).map(([start]) => start)).toEqual(['2027-03-27T08:00:00.000Z', '2027-03-29T07:00:00.000Z']);
  });
  it('la relecture puis la réécriture d’une série ne dérive pas d’une heure (hors heure doublée)', () => {
    for (const days of [['2027-03-27', '2027-03-28', '2027-03-29'], ['2027-10-30', '2027-10-31', '2027-11-01']]) {
      const original = seriesBody(form(days.map((date, index) => session(`s${index}`, date, '18:00', '20:00'))), zone)!;
      const series = { ...original, id: type, schoolId: type, version: 1, status: 'DRAFT', occurrences: (original.occurrences as Record<string, unknown>[]).map((item, index) => ({
        ...item, id: `o${index}`, position: index + 1, timeZone: zone, instructorDisplayName: 'A' })) } as unknown as CourseSeries;
      const reread = formFromSeries(series, zone);
      expect(reread.sessions.map(item => [item.date, item.start, item.end])).toEqual(days.map(date => [date, '18:00', '20:00']));
      expect(seriesBody(reread, zone)!.occurrences).toEqual(original.occurrences);
    }
  });
  it('reprogrammation de part et d’autre de la bascule : positions gardées, instants recalculés', () => {
    const series = { occurrences: [1, 2].map(position => ({ id: type, position, startsAt: `2027-10-2${5 + position}T16:00:00Z`, endsAt: `2027-10-2${5 + position}T18:00:00Z`, timeZone: zone, instructorMembershipId: instructor, instructorDisplayName: 'A', attendanceRequired: true })) };
    const body = rescheduleBody(series, [session('a', '2027-10-30', '18:00', '20:00'), session('b', '2027-11-01', '18:00', '20:00')], zone);
    expect(body?.occurrences.map(item => [item.position, item.startsAt, item.endsAt])).toEqual([
      [1, '2027-10-30T16:00:00.000Z', '2027-10-30T18:00:00.000Z'],
      [2, '2027-11-01T17:00:00.000Z', '2027-11-01T19:00:00.000Z'],
    ]);
    // Une nouvelle date sur l'heure sautée est refusée avant tout envoi.
    expect(rescheduleBody(series, [session('a', '2027-03-28', '02:30', '03:30'), session('b', '2027-11-01', '18:00', '20:00')], zone)).toBeNull();
  });
  it('« semaine suivante » reste un calcul de date civile, indifférent au changement d’heure', () => {
    const next = emptySession(session('a', '2027-03-24', '18:00', '20:00', { attendanceRequired: false }));
    expect(next).toMatchObject({ date: '2027-03-31', start: '18:00', end: '20:00', instructor, attendanceRequired: false });
    expect(emptySession(session('a', '2027-10-27', '18:00', '20:00')).date).toBe('2027-11-03');
    expect(emptySession(session('a', '2027-12-28', '18:00', '20:00')).date).toBe('2028-01-04');
    expect(emptySession(session('a', '', '18:00', '20:00')).date).toBe('');
  });
  it('l’agenda range une séance dans son jour local, pas dans son jour UTC', () => {
    const dayOf = (instant: string) => instantToSchoolTime(instant, zone).slice(0, 10);
    const series = { occurrences: [
      { id: 'a', startsAt: '2027-03-27T22:30:00Z', endsAt: '2027-03-27T23:30:00Z' },   // samedi 23:30 (UTC+1)
      { id: 'b', startsAt: '2027-03-28T22:30:00Z', endsAt: '2027-03-28T23:30:00Z' },   // lundi 00:30 (UTC+2) : le dimanche n'a pas de séance
    ] } as unknown as CourseSeries;
    const days = seriesByDay([series], dayOf, Date.parse('2027-03-27T00:00:00Z'), Date.parse('2027-03-30T00:00:00Z'));
    expect([...days.keys()]).toEqual(['2027-03-27', '2027-03-29']);
  });
});

describe('séance qui enjambe la bascule : durées et limite en temps écoulé', () => {
  it('heure d’été : 01:30 à 03:30 murales ne font qu’une heure', () => {
    const night = form([session('a', '2027-03-28', '01:30', '03:30')]);
    expect(validate(night, zone)).toEqual({ fields: {}, sessions: {} });
    expect(preview(night, zone).totalMinutes).toBe(60);
  });
  it('heure d’hiver : 01:30 à 03:30 murales font trois heures', () => {
    const night = form([session('a', '2027-10-31', '01:30', '03:30')]);
    expect(validate(night, zone)).toEqual({ fields: {}, sessions: {} });
    expect(preview(night, zone).totalMinutes).toBe(180);
  });
  it('la limite de 12 heures compte le temps écoulé, pas la durée affichée', () => {
    const limit = (date: string, end: string) => validate(form([session('a', date, '00:00', end)]), zone).sessions.a;
    // Heure d'été : 13 h murales = 12 h écoulées (accepté) ; 13 h 30 murales = 12 h 30 (refusé).
    expect(limit('2027-03-28', '13:00')).toBeUndefined();
    expect(limit('2027-03-28', '13:30')).toBe('12 heures au plus.');
    // Heure d'hiver : 11 h murales = 12 h écoulées (accepté) ; 12 h murales = 13 h écoulées (refusé).
    expect(limit('2027-10-31', '11:00')).toBeUndefined();
    expect(limit('2027-10-31', '12:00')).toBe('12 heures au plus.');
    // Un jour ordinaire n'est pas décalé.
    expect(limit('2027-06-15', '12:00')).toBeUndefined();
    expect(limit('2027-06-15', '12:01')).toBe('12 heures au plus.');
  });
});

describe('heure sautée et heure doublée', () => {
  it('refuse toute heure comprise dans l’heure sautée, début ou fin, et accepte les voisines', () => {
    const problem = (start: string, end: string) => validate(form([session('a', '2027-03-28', start, end)]), zone).sessions.a;
    expect(problem('02:00', '04:00')).toBe('Cette heure n’existe pas ce jour-là.');
    expect(problem('02:59', '04:00')).toBe('Cette heure n’existe pas ce jour-là.');
    expect(problem('01:00', '02:30')).toBe('Cette heure n’existe pas ce jour-là.');
    expect(problem('01:59', '03:00')).toBeUndefined();
    expect(problem('03:00', '04:00')).toBeUndefined();
    expect(sessionInterval(session('a', '2027-03-28', '02:30', '03:30'), zone)).toBeNull();
  });
  it('heure doublée : le formulaire choisit toujours la seconde occurrence (heure d’hiver), sans avertir', () => {
    // 02:30 existe à 00:30 UTC (heure d'été) et à 01:30 UTC (heure d'hiver). Le modèle retient la seconde, de façon constante.
    const interval = sessionInterval(session('a', '2027-10-31', '02:30', '03:30'), zone)!;
    expect(new Date(interval.start).toISOString()).toBe('2027-10-31T01:30:00.000Z');
    expect(new Date(interval.end).toISOString()).toBe('2027-10-31T02:30:00.000Z');
    expect(validate(form([session('a', '2027-10-31', '02:30', '03:30')]), zone).sessions).toEqual({});
  });
  // DÉFAUT P3 (cas limite) : une séance placée par l'API ou l'app à 02:30 d'été (00:30 UTC) est relue « 02:30 » puis réécrite
  // à 01:30 UTC par le formulaire web : son début glisse d'une heure (ici 00:30-02:30 UTC devient 01:30-02:30 UTC, durée réduite
  // de 2 h à 1 h) à l'enregistrement d'un brouillon ou d'une reprogrammation, sans que rien ne le signale. Le correctif attendu est de conserver l'instant d'origine tant que l'heure affichée n'est pas
  // modifiée (ou de demander laquelle des deux occurrences). Ce test doit passer le jour où le défaut est corrigé.
  it.fails('une séance dans la première occurrence de l’heure doublée garde son instant après relecture du formulaire', () => {
    const original = { startsAt: '2027-10-31T00:30:00.000Z', endsAt: '2027-10-31T02:30:00.000Z' };
    const series = { id: type, schoolId: type, version: 1, status: 'DRAFT', typeId: type, title: 'T', description: '', location: '', conditions: '', teachingLanguage: null,
      responsibleMembershipId: instructor, capacity: 8, minParticipants: null,
      occurrences: [{ ...original, id: 'o1', position: 1, timeZone: zone, instructorMembershipId: instructor, instructorDisplayName: 'A', attendanceRequired: true }] } as unknown as CourseSeries;
    const rewritten = seriesBody(formFromSeries(series, zone), zone);
    expect(occurrences(rewritten)).toEqual([[original.startsAt, original.endsAt]]);
  });
});

describe('bornes des règles locales', () => {
  const taken = (seatsTaken: number, capacity = 10, minParticipants: number | null = null) => ({ seatsTaken, capacity, minParticipants });
  it('capacité : égale aux places prises acceptée, inchangée signalée, bornes 1 et 200', () => {
    expect(capacityProblem('4', taken(4))).toBeNull();
    expect(capacityProblem('3', taken(4))).toBe('4 places sont déjà prises.');
    expect(capacityProblem('10', taken(4))).toBe('Capacité inchangée.');
    expect(capacityProblem('200', taken(4))).toBeNull();
    expect(capacityProblem('201', taken(4))).toBe('Entre 1 et 200 places.');
    expect(capacityProblem('0', taken(0))).toBe('Entre 1 et 200 places.');
    expect(capacityProblem('1.5', taken(0))).toBe('Entre 1 et 200 places.');
    expect(capacityProblem('-3', taken(0))).toBe('Entre 1 et 200 places.');
    expect(capacityProblem('', taken(0))).toBe('Entre 1 et 200 places.');
    expect(capacityProblem(' 7 ', taken(0))).toBeNull();
    expect(capacityProblem('6', taken(0, 10, 6))).toBeNull();
    expect(capacityProblem('5', taken(0, 10, 6))).toBe('La capacité passe sous le minimum.');
  });
  it('libellé de l’échéance : heures jusqu’à 47, jours pour les multiples de 24 h dès 48 h', () => {
    expect(cancellationLabel(0)).toBe('Annulation libre jusqu’au début de la première séance');
    expect(cancellationLabel(1)).toBe('Annulation libre jusqu’à 1 h avant la première séance');
    expect(cancellationLabel(24)).toBe('Annulation libre jusqu’à 24 h avant la première séance');
    expect(cancellationLabel(36)).toBe('Annulation libre jusqu’à 36 h avant la première séance');
    expect(cancellationLabel(47)).toBe('Annulation libre jusqu’à 47 h avant la première séance');
    expect(cancellationLabel(48)).toBe('Annulation libre jusqu’à 2 jours avant la première séance');
    expect(cancellationLabel(72)).toBe('Annulation libre jusqu’à 3 jours avant la première séance');
    expect(cancellationLabel(96 + 1)).toBe('Annulation libre jusqu’à 97 h avant la première séance');
    expect(cancellationLabel(720)).toBe('Annulation libre jusqu’à 30 jours avant la première séance');
  });
  it('réglages : bornes de l’échéance (0 à 720 h) et de la réponse (15 à 10 080 min, vide = file fermée)', () => {
    const problems = (selfCancelHours: string, offerResponseMinutes: string) => policyProblems({ selfCancelHours, offerResponseMinutes });
    expect(problems('0', '')).toEqual({});
    expect(problems('720', '15')).toEqual({});
    expect(problems('721', '').selfCancelHours).toBe('Entre 0 et 720 heures.');
    for (const bad of ['', '-1', '1.5', 'abc', '12345']) expect(problems(bad, '').selfCancelHours, bad).toBe('Entre 0 et 720 heures.');
    expect(problems('24', '10080')).toEqual({});
    expect(problems('24', '14').offerResponseMinutes).toBe('Entre 15 et 10080 minutes.');
    expect(problems('24', '10081').offerResponseMinutes).toBe('Entre 15 et 10080 minutes.');
    expect(problems('24', '12.5').offerResponseMinutes).toBe('Entre 15 et 10080 minutes.');
    expect(problems('24', '   ')).toEqual({});
    expect(policyBody({ selfCancelHours: ' 48 ', offerResponseMinutes: ' 720 ' })).toEqual({ selfCancelHours: 48, offerResponseMinutes: 720 });
    expect(policyBody({ selfCancelHours: '721', offerResponseMinutes: '' })).toBeNull();
  });
  it('une présence se saisit à l’instant exact du début, pas une milliseconde avant', () => {
    const start = '2027-11-03T17:00:00Z', at = Date.parse(start);
    const sheet = { rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true } };
    const row = courseSheetRowSchema.parse({ enrollmentId: type, learnerId: instructor, learnerDisplayName: 'Ana', status: 'ACTIVE', cancelledAt: null,
      attendance: [], requirements: { required: 1, present: 0, missing: 1 }, payments: [], completion: null });
    expect(occurrenceStarted({ startsAt: start }, at)).toBe(true);
    expect(occurrenceStarted({ startsAt: start }, at - 1)).toBe(false);
    expect(canMarkAttendance(sheet, row, { startsAt: start }, at)).toBe(true);
    expect(canMarkAttendance(sheet, row, { startsAt: start }, at - 1)).toBe(false);
  });
  it('une inscription annulée ne se valide jamais, même avec toutes les séances marquées présentes', () => {
    const sheet = { rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true } };
    const complete = { requirements: { required: 2, present: 2, missing: 0 }, completion: null };
    expect(canValidateRow(sheet, { status: 'ACTIVE', ...complete })).toBe(true);
    expect(canValidateRow(sheet, { status: 'CANCELLED', ...complete })).toBe(false);
  });
  it('un élève dont l’inscription est annulée peut être inscrit de nouveau ; un élève en attente ou inscrit ne le peut pas', () => {
    const entry = (learnerId: string, status: 'ACTIVE' | 'CANCELLED') => ({ id: type, seriesId: type, learnerId, version: 1, status, source: 'SELF', selfCancelDeadline: '2027-11-01T17:00:00Z',
      createdAt: '2027-10-01T17:00:00Z', cancelledAt: status === 'CANCELLED' ? '2027-10-02T17:00:00Z' : null, cancelKind: status === 'CANCELLED' ? 'SELF' : null, cancelReason: null, learnerDisplayName: 'x' });
    const roster = courseRosterSchema.parse({ items: [entry('a1111111-1111-4111-8111-111111111111', 'CANCELLED'), entry('b1111111-1111-4111-8111-111111111111', 'ACTIVE')], waitlist: [] });
    const learners = ['a1111111-1111-4111-8111-111111111111', 'b1111111-1111-4111-8111-111111111111'].map((id, index) => ({ id, displayName: index ? 'Ben' : 'Ana', archivedAt: null }));
    expect(enrollableLearners(learners, roster).map(item => item.displayName)).toEqual(['Ana']);
  });
  it('règlement sur place : note de 500 caractères acceptée, 501 refusée, montant absent refusé', () => {
    expect(paymentProblem(12000, 'x'.repeat(500))).toBeNull();
    expect(paymentProblem(12000, 'x'.repeat(501))).toBe('500 caractères au plus.');
    expect(paymentProblem(0, '')).toBeNull();
    expect(paymentProblem(null, '')).toContain('CHF');
  });
  it('séances : 64 au plus, la 65e est refusée ; titre de 200 caractères accepté, 201 refusé', () => {
    const many = (count: number) => Array.from({ length: count }, (_, index) => session(`s${index}`, '2027-06-15', '08:00', '09:00'));
    expect(validate(form(many(64)), zone).fields.sessions).toBeUndefined();
    expect(validate(form(many(65)), zone).fields.sessions).toBe('64 séances au plus.');
    expect(validate(form([session('a', '2027-06-15', '08:00', '09:00')], { title: 'x'.repeat(200) }), zone).fields.title).toBeUndefined();
    expect(validate(form([session('a', '2027-06-15', '08:00', '09:00')], { title: 'x'.repeat(201) }), zone).fields.title).toBe('200 caractères au plus.');
    expect(validate(form([session('a', '2027-06-15', '08:00', '09:00')], { title: '   ' }), zone).fields.title).toBe('Indiquez un titre.');
  });
});
