/**
 * Cours collectifs (#38) : contrat lu de l'API, saisie du formulaire et règles locales.
 * Pas de DOM, pas de réseau. Les règles locales évitent un aller-retour inutile ; l'API reste seule juge.
 */
import { z } from 'zod';
import { instantToSchoolTime, schoolTimeToInstant } from '../command-core.js';

const id = z.string().uuid();
const version = z.number().int().positive();
const timestamp = z.string().datetime({ offset: true });

export const courseTypeSchema = z.object({
  id, schoolId: id.nullable(), stableKey: z.enum(['AWARENESS', 'FIRST_AID']).nullable(), title: z.string().max(120),
  description: z.string().max(2000), version, predefined: z.boolean(),
});
export const coursePolicySchema = z.object({
  version, selfCancelHours: z.number().int().min(0).max(720), offerResponseMinutes: z.number().int().nullable(),
});
export const courseCatalogueSchema = z.object({
  schoolId: id, canManage: z.boolean(), types: z.array(courseTypeSchema).max(500), policy: coursePolicySchema,
  instructors: z.array(z.object({ membershipId: id, displayName: z.string() })).max(1000),
});
export const courseOccurrenceSchema = z.object({
  id, position: z.number().int().positive(), startsAt: timestamp, endsAt: timestamp, timeZone: z.string(),
  instructorMembershipId: id, instructorDisplayName: z.string(), attendanceRequired: z.boolean(),
});
export const courseStatuses = ['DRAFT', 'PUBLISHED', 'CANCELLED', 'CLOSED'] as const;
export const courseSeriesSchema = z.object({
  id, schoolId: id, version, status: z.enum(courseStatuses), typeId: id, typeTitle: z.string(), title: z.string(), description: z.string(),
  location: z.string(), conditions: z.string(), teachingLanguage: z.string().nullable(), responsibleMembershipId: id,
  responsibleDisplayName: z.string(), capacity: z.number().int(), seatsTaken: z.number().int().min(0), remainingSeats: z.number().int().min(0),
  minParticipants: z.number().int().nullable(), policyVersion: z.number().int(), selfCancelHours: z.number().int().min(0),
  selfCancellationDeadline: timestamp, firstStartsAt: timestamp, lastEndsAt: timestamp, totalMinutes: z.number().int().min(0),
  publishedAt: timestamp.nullable(), occurrences: z.array(courseOccurrenceSchema).max(64), canManage: z.boolean(),
});
export const courseSeriesListSchema = z.object({ items: z.array(courseSeriesSchema).max(200) });
export type CourseType = z.infer<typeof courseTypeSchema>;
export type CourseCatalogue = z.infer<typeof courseCatalogueSchema>;
export type CourseSeries = z.infer<typeof courseSeriesSchema>;

export const LIMITS = { title: 200, description: 4000, location: 500, conditions: 4000, typeTitle: 120, typeDescription: 2000, capacity: 200, sessions: 64 } as const;
export const languages = [
  { value: 'fr', label: 'Français' }, { value: 'de', label: 'Allemand' }, { value: 'it', label: 'Italien' }, { value: 'en', label: 'Anglais' },
] as const;
export type Language = typeof languages[number]['value'];

/** Une séance telle que saisie : date et heures murales de l'école. */
export interface SessionForm { key: string; date: string; start: string; end: string; instructor: string; attendanceRequired: boolean }
export interface SeriesForm {
  typeId: string; title: string; description: string; location: string; conditions: string; language: Language | '';
  responsible: string; capacity: string; minimum: string; sessions: SessionForm[];
}

let sequence = 0;
export const sessionKey = (): string => `s${++sequence}`;

export function emptySession(previous?: SessionForm): SessionForm {
  return { key: sessionKey(), date: previous ? addWeek(previous.date) : '', start: previous?.start ?? '', end: previous?.end ?? '',
    instructor: previous?.instructor ?? '', attendanceRequired: previous?.attendanceRequired ?? true };
}
function addWeek(civil: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(civil);
  if (!match) return '';
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + 7)).toISOString().slice(0, 10);
}

export function emptyForm(catalogue: Pick<CourseCatalogue, 'types' | 'instructors'>, responsible = ''): SeriesForm {
  const instructor = catalogue.instructors.length === 1 ? catalogue.instructors[0]!.membershipId : '';
  return { typeId: catalogue.types[0]?.id ?? '', title: '', description: '', location: '', conditions: '', language: '',
    responsible, capacity: '', minimum: '', sessions: [{ ...emptySession(), instructor }] };
}

export function formFromSeries(series: CourseSeries, timeZone: string): SeriesForm {
  const language = languages.some(item => item.value === series.teachingLanguage) ? series.teachingLanguage as Language : '';
  return {
    typeId: series.typeId, title: series.title, description: series.description, location: series.location, conditions: series.conditions,
    language, responsible: series.responsibleMembershipId, capacity: String(series.capacity), minimum: series.minParticipants === null ? '' : String(series.minParticipants),
    sessions: series.occurrences.map(occurrence => {
      const start = instantToSchoolTime(occurrence.startsAt, timeZone), end = instantToSchoolTime(occurrence.endsAt, timeZone);
      return { key: sessionKey(), date: start.slice(0, 10), start: start.slice(11, 16), end: end.slice(11, 16),
        instructor: occurrence.instructorMembershipId, attendanceRequired: occurrence.attendanceRequired };
    }),
  };
}

export type FieldKey = 'typeId' | 'title' | 'description' | 'location' | 'conditions' | 'responsible' | 'capacity' | 'minimum' | 'sessions';
export type Problems = { fields: Partial<Record<FieldKey, string>>; sessions: Record<string, string> };

const whole = (text: string): number | null => /^\d{1,4}$/.test(text.trim()) ? Number(text.trim()) : null;
const length = (text: string) => [...text.trim()].length;

/** Intervalle réel d'une séance ; null si la date ou une heure manque ou n'existe pas (changement d'heure). */
export function sessionInterval(session: SessionForm, timeZone: string): { start: number; end: number } | null {
  if (!session.date || !session.start || !session.end) return null;
  const start = schoolTimeToInstant(`${session.date}T${session.start}`, timeZone), end = schoolTimeToInstant(`${session.date}T${session.end}`, timeZone);
  return start && end ? { start: Date.parse(start), end: Date.parse(end) } : null;
}

export function validate(form: SeriesForm, timeZone: string): Problems {
  const fields: Problems['fields'] = {}, sessions: Problems['sessions'] = {};
  if (!form.typeId) fields.typeId = 'Choisissez un type.';
  if (!length(form.title)) fields.title = 'Indiquez un titre.';
  else if (length(form.title) > LIMITS.title) fields.title = `${LIMITS.title} caractères au plus.`;
  if (length(form.description) > LIMITS.description) fields.description = `${LIMITS.description} caractères au plus.`;
  if (length(form.location) > LIMITS.location) fields.location = `${LIMITS.location} caractères au plus.`;
  if (length(form.conditions) > LIMITS.conditions) fields.conditions = `${LIMITS.conditions} caractères au plus.`;
  if (!form.responsible) fields.responsible = 'Choisissez un responsable.';
  const capacity = whole(form.capacity);
  if (capacity === null || capacity < 1 || capacity > LIMITS.capacity) fields.capacity = `Entre 1 et ${LIMITS.capacity} places.`;
  if (form.minimum.trim()) {
    const minimum = whole(form.minimum);
    if (minimum === null || minimum < 1 || minimum > LIMITS.capacity) fields.minimum = `Entre 1 et ${LIMITS.capacity}.`;
    else if (capacity !== null && minimum > capacity) fields.minimum = 'Le minimum dépasse la capacité.';
  }
  if (!form.sessions.length) fields.sessions = 'Ajoutez au moins une séance.';
  else if (form.sessions.length > LIMITS.sessions) fields.sessions = `${LIMITS.sessions} séances au plus.`;
  const intervals: { key: string; start: number; end: number }[] = [];
  for (const session of form.sessions) {
    if (!session.date || !session.start || !session.end) { sessions[session.key] = 'Date et heures requises.'; continue; }
    const interval = sessionInterval(session, timeZone);
    if (!interval) { sessions[session.key] = 'Cette heure n’existe pas ce jour-là.'; continue; }
    if (interval.end <= interval.start) { sessions[session.key] = 'La fin doit suivre le début.'; continue; }
    if (interval.end - interval.start > 12 * 3_600_000) { sessions[session.key] = '12 heures au plus.'; continue; }
    if (!session.instructor) { sessions[session.key] = 'Choisissez un moniteur.'; continue; }
    intervals.push({ key: session.key, ...interval });
  }
  intervals.sort((a, b) => a.start - b.start);
  for (let index = 1; index < intervals.length; index++) {
    if (intervals[index]!.start < intervals[index - 1]!.end) sessions[intervals[index]!.key] = 'Chevauche une autre séance.';
  }
  return { fields, sessions };
}
export const hasProblems = (problems: Problems): boolean => Object.keys(problems.fields).length > 0 || Object.keys(problems.sessions).length > 0;

/** Corps de POST/PUT course-series, sans operationId (ajouté par la commande). Null si la saisie est invalide. */
export function seriesBody(form: SeriesForm, timeZone: string): Record<string, unknown> | null {
  if (hasProblems(validate(form, timeZone))) return null;
  const occurrences = form.sessions.map(session => ({ session, interval: sessionInterval(session, timeZone)! }))
    .sort((a, b) => a.interval.start - b.interval.start)
    .map(({ session, interval }) => ({ startsAt: new Date(interval.start).toISOString(), endsAt: new Date(interval.end).toISOString(),
      instructorMembershipId: session.instructor, attendanceRequired: session.attendanceRequired }));
  return {
    typeId: form.typeId, title: form.title.trim(), description: form.description.trim(), location: form.location.trim(), conditions: form.conditions.trim(),
    teachingLanguage: form.language || null, responsibleMembershipId: form.responsible, capacity: Number(form.capacity.trim()),
    minParticipants: form.minimum.trim() ? Number(form.minimum.trim()) : null, timeZone, occurrences,
  };
}

/** Séances valides, dans l'ordre, et leur durée totale. */
export function preview(form: SeriesForm, timeZone: string): { sessions: { key: string; start: number; end: number }[]; totalMinutes: number } {
  const sessions = form.sessions.flatMap(session => {
    const interval = sessionInterval(session, timeZone);
    return interval && interval.end > interval.start ? [{ key: session.key, ...interval }] : [];
  }).sort((a, b) => a.start - b.start);
  return { sessions, totalMinutes: sessions.reduce((sum, item) => sum + Math.round((item.end - item.start) / 60_000), 0) };
}

export function formatHours(minutes: number): string {
  const hours = Math.floor(minutes / 60), rest = minutes % 60;
  return rest ? `${hours} h ${String(rest).padStart(2, '0')}` : `${hours} h`;
}

export function cancellationLabel(hours: number): string {
  if (hours === 0) return 'Annulation libre jusqu’au début de la première séance';
  return hours % 24 === 0 && hours >= 48
    ? `Annulation libre jusqu’à ${hours / 24} jours avant la première séance`
    : `Annulation libre jusqu’à ${hours} h avant la première séance`;
}

export function capacityProblem(text: string, series: Pick<CourseSeries, 'seatsTaken' | 'minParticipants' | 'capacity'>): string | null {
  const value = whole(text);
  if (value === null || value < 1 || value > LIMITS.capacity) return `Entre 1 et ${LIMITS.capacity} places.`;
  if (value < series.seatsTaken) return `${series.seatsTaken} places sont déjà prises.`;
  if (series.minParticipants !== null && value < series.minParticipants) return 'La capacité passe sous le minimum.';
  if (value === series.capacity) return 'Capacité inchangée.';
  return null;
}

export function typeProblem(title: string, description: string, existing: readonly CourseType[]): string | null {
  if (!length(title)) return 'Indiquez un nom.';
  if (length(title) > LIMITS.typeTitle) return `${LIMITS.typeTitle} caractères au plus.`;
  if (length(description) > LIMITS.typeDescription) return `Description : ${LIMITS.typeDescription} caractères au plus.`;
  const normalized = title.trim().toLocaleLowerCase('fr-CH');
  if (existing.some(type => type.title.trim().toLocaleLowerCase('fr-CH') === normalized)) return 'Ce type existe déjà.';
  return null;
}

/** Séries de la semaine regroupées par jour de séance (une série de plusieurs séances apparaît à chacune). */
export function seriesByDay(series: readonly CourseSeries[], dayOf: (instant: string) => string, from: number, to: number) {
  const days = new Map<string, { series: CourseSeries; occurrence: CourseSeries['occurrences'][number] }[]>();
  for (const item of series) for (const occurrence of item.occurrences) {
    if (Date.parse(occurrence.endsAt) <= from || Date.parse(occurrence.startsAt) >= to) continue;
    const day = dayOf(occurrence.startsAt);
    days.set(day, [...(days.get(day) ?? []), { series: item, occurrence }]);
  }
  for (const list of days.values()) list.sort((a, b) => Date.parse(a.occurrence.startsAt) - Date.parse(b.occurrence.startsAt));
  return days;
}

/** Messages courts des refus de l'API ; la saisie reste en place. */
export function courseErrorMessage(code: string): string | null {
  const messages: Record<string, string> = {
    COURSE_ACCESS_REQUIRED: 'Vos accès ne permettent pas de gérer les cours.',
    COURSE_INSTRUCTOR_CONFLICT: 'Un moniteur est déjà pris pendant une séance.',
    COURSE_OCCURRENCES_OVERLAP: 'Deux séances se chevauchent.',
    COURSE_OCCURRENCES_REQUIRED: 'Ajoutez au moins une séance.',
    COURSE_IN_PAST: 'La première séance est déjà passée.',
    COURSE_NOT_DRAFT: 'Ce cours est déjà publié.',
    COURSE_NOT_PUBLISHED: 'Ce cours n’est pas publié.',
    COURSE_CAPACITY_BELOW_TAKEN: 'Capacité inférieure aux places prises.',
    COURSE_CAPACITY_BELOW_MINIMUM: 'Capacité inférieure au minimum.',
    COURSE_TYPE_EXISTS: 'Ce type existe déjà.',
    COURSE_TYPE_UNKNOWN: 'Ce type n’est plus disponible.',
    COURSE_CONFLICT: 'Conflit avec l’agenda.',
    INSTRUCTOR_NOT_ACTIVE: 'Un moniteur n’est plus actif.',
    RESPONSIBLE_NOT_ACTIVE: 'Le responsable n’est plus actif.',
    INVALID_INTERVAL: 'Une séance finit avant son début ou dure plus de 12 h.',
    INVALID_TIME_ZONE: 'Le fuseau de l’école a changé. Rechargez.',
    VERSION_CONFLICT: 'Ce cours a changé entre-temps. Rechargez.',
  };
  return messages[code] ?? null;
}
