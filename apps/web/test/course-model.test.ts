import { describe, expect, it } from 'vitest';
import {
  cancellationLabel, capacityProblem, emptyForm, formFromSeries, formatHours, preview, seriesBody, seriesByDay, typeProblem, validate,
  type CourseSeries, type SeriesForm,
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
