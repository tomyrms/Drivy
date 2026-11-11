import { rebaseConfirmedDraft } from '../../console/draft-model';
import type { SeriesForm } from '../../console/course-model';

/**
 * Brouillon de cours face à une version plus récente de l'école (#422). `base` est le brouillon tel que la version de départ le
 * disait, `latest` ce que l'école dit maintenant, `local` la saisie. Un champ touché d'un seul côté est repris tel quel ; un champ
 * changé des deux côtés reste en conflit et n'avance pas la version utilisée par If-Match sans choix de la personne.
 */
export interface CourseConflict {
  /** Saisie fusionnée : la valeur locale gagne sur chaque champ en conflit. */
  readonly merged: SeriesForm;
  /** Champs changés des deux côtés (clés de SeriesForm). */
  readonly fields: readonly (keyof SeriesForm)[];
  /** Même fusion, mais l'école gagne sur les champs en conflit. */
  readonly theirs: SeriesForm;
}

export const courseFieldLabels: Record<keyof SeriesForm, string> = {
  typeId: 'Type', title: 'Titre', description: 'Description', location: 'Lieu', conditions: 'Conditions', language: 'Langue',
  responsible: 'Responsable', capacity: 'Capacité', minimum: 'Minimum', sessions: 'Séances',
};

export function rebaseCourseDraft(base: SeriesForm, latest: SeriesForm, local: SeriesForm): CourseConflict {
  const { value, conflicts } = rebaseConfirmedDraft(base, latest, local);
  const fields = conflicts.map(path => path.split('.')[0] as keyof SeriesForm).filter((key, index, all) => all.indexOf(key) === index);
  const theirs = { ...value } as SeriesForm;
  for (const key of fields) (theirs as unknown as Record<string, unknown>)[key] = latest[key];
  return { merged: value, fields, theirs };
}
