import { formatDuration } from './measure-format';
import type { MetricsAnswer } from './metrics-api';

/** Mesures lues pour la journée ; le total L08 est un contrôle du serveur, jamais une somme refaite ici. */
const usedIds = ['L01', 'L02', 'L03', 'L04', 'L05', 'L06', 'L07', 'L08', 'H01', 'C01'] as const;
/** États affichés, dans l'ordre de lecture ; accord au singulier et au pluriel. */
const states: readonly (readonly [id: string, one: string, many: string])[] = [
  ['L01', 'réalisée', 'réalisées'], ['L06', 'en cours', 'en cours'], ['L07', 'à finaliser', 'à finaliser'], ['L05', 'à vérifier', 'à vérifier'],
  ['L02', 'à venir', 'à venir'], ['L03', 'annulée', 'annulées'], ['L04', 'absence', 'absences'],
];

export interface TodaySummary {
  /** Segments à joindre par un séparateur ; le premier dit le nombre de leçons. */
  segments: string[];
  /** Vrai si une mesure lue est partielle ou indisponible : le résumé ne doit pas se lire comme complet. */
  incomplete: boolean;
}

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

export function summarizeToday(answer: Pick<MetricsAnswer, 'measures'>): TodaySummary {
  const value = (id: string) => answer.measures[id]?.value ?? null;
  const total = value('L08');
  const segments: string[] = [];
  if (total === null) segments.push('Leçons du jour indisponibles');
  else if (total === 0) segments.push('Aucune leçon aujourd’hui');
  else segments.push(`${plural(total, 'leçon', 'leçons')} aujourd’hui`);
  for (const [id, one, many] of states) {
    const count = value(id);
    if (count !== null && count > 0) segments.push(`${count} ${count === 1 ? one : many}`);
  }
  const programmed = value('H01');
  if (programmed !== null && programmed > 0) segments.push(`${formatDuration(programmed)} programmées`);
  const courses = value('C01');
  if (courses !== null && courses > 0) segments.push(plural(courses, 'séance collective', 'séances collectives'));
  const incomplete = usedIds.some(id => {
    const measure = answer.measures[id];
    return measure !== undefined && measure.coverage.status !== 'COMPLETE' && measure.coverage.status !== 'NOT_APPLICABLE';
  });
  return { segments, incomplete };
}
