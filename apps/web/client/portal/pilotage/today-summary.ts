import { formatDuration } from './measure-format';
import type { MetricsAnswer } from './metrics-api';

/** Mesures lues pour la journée ; le total L08 est un contrôle du serveur, jamais une somme refaite ici. */
const usedIds = ['L01', 'L02', 'L03', 'L04', 'L05', 'L06', 'L07', 'L08', 'H01', 'C01'] as const;
/**
 * États affichés, dans l'ordre de lecture ; accord au singulier et au pluriel. `kind` dit comment la barre de la journée les dessine :
 * réalisé (plein), en cours, à traiter, à venir (tireté, prévu) et écarté (annulée, absence).
 */
export type DayStateKind = 'done' | 'live' | 'attention' | 'upcoming' | 'off';
const states: readonly (readonly [id: string, one: string, many: string, kind: DayStateKind])[] = [
  ['L01', 'réalisée', 'réalisées', 'done'], ['L06', 'en cours', 'en cours', 'live'], ['L07', 'à finaliser', 'à finaliser', 'attention'], ['L05', 'à vérifier', 'à vérifier', 'attention'],
  ['L02', 'à venir', 'à venir', 'upcoming'], ['L03', 'annulée', 'annulées', 'off'], ['L04', 'absence', 'absences', 'off'],
];

/** Un état présent de la journée : son nombre tel que le serveur le donne, son texte accordé et son rôle dans la barre. */
export interface DayState { id: string; count: number; text: string; kind: DayStateKind }
/**
 * La journée en parties : le nombre de leçons (sous un titre qui dit déjà « Aujourd'hui »), les états présents, puis les heures et les séances.
 * `incomplete` est vrai si une mesure lue est partielle ou indisponible : le résumé ne doit pas se lire comme complet.
 */
export interface TodayOverview { count: string; states: DayState[]; extras: string[]; incomplete: boolean }

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

export function overviewToday(answer: Pick<MetricsAnswer, 'measures'>): TodayOverview {
  const value = (id: string) => answer.measures[id]?.value ?? null;
  const total = value('L08');
  const count = total === null ? 'Leçons du jour indisponibles' : total === 0 ? 'Aucune leçon' : plural(total, 'leçon', 'leçons');
  const present: DayState[] = [];
  for (const [id, one, many, kind] of states) {
    const amount = value(id);
    if (amount !== null && amount > 0) present.push({ id, count: amount, text: `${amount} ${amount === 1 ? one : many}`, kind });
  }
  const extras: string[] = [];
  const programmed = value('H01');
  if (programmed !== null && programmed > 0) extras.push(`${formatDuration(programmed)} programmées`);
  const courses = value('C01');
  if (courses !== null && courses > 0) extras.push(plural(courses, 'séance collective', 'séances collectives'));
  const incomplete = usedIds.some(id => {
    const measure = answer.measures[id];
    return measure !== undefined && measure.coverage.status !== 'COMPLETE' && measure.coverage.status !== 'NOT_APPLICABLE';
  });
  return { count, states: present, extras, incomplete };
}
