import { useState } from 'react';
import { permitState, type PermitState } from '../command-core';
import { lessonSchema, progressSchema, readAll, readSchool, reportSchema, type Lesson, type Permit, type Progress, type Report, type Training } from '../school-api';
import { EmptyState, Loading, Notice, StatusBadge, formatCivilDate, formatDateTime, type Tone } from '../ui';
import { readError, useLoad } from './context';

const levelLabels = { DISCOVERING: 'Découverte', GUIDED: 'Avec guidage', INDEPENDENT: 'Autonome' } as const;
const levelTones: Record<keyof typeof levelLabels, Tone> = { DISCOVERING: 'neutral', GUIDED: 'accent', INDEPENDENT: 'success' };

/** « Permis vu » : catégorie et validité de la dernière décision, ou l'absence de contrôle. */
export function permitSummary(permit: Permit | undefined): { state: PermitState; text: string; badge: { tone: Tone; label: string } | null } {
  const state = permitState(permit);
  if (!permit || state === 'none') return { state, text: 'Permis non vu', badge: null };
  const validity = permit.validUntil ? `valable jusqu’au ${formatCivilDate(permit.validUntil)}` : 'sans date de validité';
  if (state === 'rejected') return { state, text: `Permis ${permit.categoryCode} refusé`, badge: { tone: 'danger', label: 'Refusé' } };
  if (state === 'expired') return { state, text: `Permis ${permit.categoryCode} vu · ${validity}`, badge: { tone: 'warning', label: 'Expiré' } };
  return { state, text: `Permis ${permit.categoryCode} vu · ${validity}`, badge: null };
}

function ReportBody({ report, competencies }: { report: Report; competencies: ReadonlyMap<string, string> }) {
  return (
    <div className="report-body">
      {report.workedOn && <><h4>Travaillé</h4><p className="policy-copy">{report.workedOn}</p></>}
      {report.observationText && <><h4>Observations</h4><p className="policy-copy">{report.observationText}</p></>}
      {report.nextStep && <><h4>Prochaine étape</h4><p className="policy-copy">{report.nextStep}</p></>}
      {report.observations.length > 0 && <ul className="plain-list">{report.observations.map(item => <li key={item.competencyId}>
        <span className="row-title">{competencies.get(item.competencyId) ?? 'Compétence'}</span>
        <StatusBadge tone={levelTones[item.level]} symbol="dot">{levelLabels[item.level]}</StatusBadge>
        {item.context && <span className="row-meta">{item.context}</span>}
      </li>)}</ul>}
    </div>
  );
}

/** Bilan publié d'une leçon, lu à la demande (dernière révision). */
function LessonReport({ schoolId, lesson, competencies, timeZone }: { schoolId: string; lesson: Lesson; competencies: ReadonlyMap<string, string>; timeZone: string }) {
  const [open, setOpen] = useState(false);
  const loaded = useLoad(async () => open ? (await readAll(schoolId, `lessons/${lesson.id}/reports`, reportSchema)).items : null, [schoolId, lesson.id, open]);
  const latest = loaded.data?.at(-1);
  return (
    <li className="report-row">
      <button type="button" className="button quiet" aria-expanded={open} onClick={() => setOpen(value => !value)}>
        Bilan du {formatDateTime(lesson.plannedStart, timeZone)}
      </button>
      {open && loaded.status === 'loading' && !loaded.data && <Loading label="Lecture du bilan…" />}
      {open && loaded.status === 'error' && <Notice tone="error" title="Bilan indisponible" live={false}><p>{loaded.error}</p></Notice>}
      {open && loaded.data && (latest ? <ReportBody report={latest} competencies={competencies} /> : <p className="caption">Aucun bilan publié.</p>)}
    </li>
  );
}

/** Progression par compétence et bilans publiés d'une formation, en lecture seule. */
export function TrainingFollowUp({ schoolId, training, competencies, timeZone }: {
  schoolId: string; training: Training; competencies: ReadonlyMap<string, string>; timeZone: string;
}) {
  const [open, setOpen] = useState(false);
  const loaded = useLoad(async (): Promise<{ progress: Progress; lessons: Lesson[] } | null> => {
    if (!open) return null;
    const [progress, lessons] = await Promise.all([readSchool(schoolId, `trainings/${training.id}/progress`, progressSchema),
      readAll(schoolId, 'lessons', lessonSchema, { trainingId: training.id })]);
    return { progress, lessons: lessons.items };
  }, [schoolId, training.id, open]);
  const data = loaded.data;
  const total = data ? data.progress.items.length + data.progress.unobservedCompetencyIds.length : 0;
  const reported = (data?.lessons ?? []).filter(lesson => lesson.currentPublishedRevisionId).sort((a, b) => Date.parse(b.plannedStart) - Date.parse(a.plannedStart));
  return (
    <details className="disclosure" onToggle={event => setOpen(event.currentTarget.open)}>
      <summary>Progression et bilans</summary>
      {open && loaded.status === 'loading' && !data && <Loading label="Lecture de la progression…" />}
      {open && loaded.status === 'error' && <Notice tone="error" title="Lecture impossible" live={false}><p>{loaded.error ?? readError(null)}</p></Notice>}
      {data && <div className="follow-up">
        <h3>{data.progress.items.length} compétence{data.progress.items.length > 1 ? 's' : ''} observée{data.progress.items.length > 1 ? 's' : ''} sur {total}</h3>
        {data.progress.items.length > 0 && <ul className="plain-list">{[...data.progress.items].sort((a, b) => a.label.localeCompare(b.label, 'fr')).map(item => <li key={item.competencyId}>
          <span className="row-title">{item.label}</span>
          <StatusBadge tone={levelTones[item.level]} symbol="dot">{levelLabels[item.level]}</StatusBadge>
          <span className="row-meta">{formatDateTime(item.observedAt, timeZone)}</span>
        </li>)}</ul>}
        <h3>Bilans</h3>
        {reported.length === 0 ? <EmptyState symbol="file" title="Aucun bilan" message="Aucune leçon de cette formation n’a de bilan publié." />
          : <ul className="report-list">{reported.map(lesson => <LessonReport key={lesson.id} schoolId={schoolId} lesson={lesson} competencies={competencies} timeZone={timeZone} />)}</ul>}
      </div>}
    </details>
  );
}
