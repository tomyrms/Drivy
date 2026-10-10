import { useState } from 'react';
import { permitState, type PermitState } from '../command-core';
import { reportHistory } from '../dossier-model';
import { lessonSchema, progressSchema, readAll, readSchool, reportSchema, type Lesson, type Permit, type Progress, type Report, type Training } from '../school-api';
import { EmptyState, Loading, Notice, SelectField, formatCivilDate, formatDateTime, type Tone } from '../ui';
import { readError, useLoad } from './context';
import { ReadRetry } from './layout';

const levelLabels = { DISCOVERING: 'En découverte', GUIDED: 'Avec accompagnement', INDEPENDENT: 'En autonomie' } as const;
const levelCount = { DISCOVERING: 1, GUIDED: 2, INDEPENDENT: 3 } as const;
const months = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

function CompetencyLevel({ level }: { level: keyof typeof levelLabels | null }) {
  return <span className="competency-level">
    <span className="competency-dots" aria-hidden="true">{[1, 2, 3].map(dot => <i key={dot} className={dot <= (level ? levelCount[level] : 0) ? 'is-filled' : undefined} />)}</span>
    <span>{level ? levelLabels[level] : 'Pas encore vu'}</span>
  </span>;
}

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
      {report.workedOn && <div className="report-copy"><h5>Travaillé</h5><p>{report.workedOn}</p></div>}
      {report.observationText && <div className="report-copy"><h5>Observations</h5><p>{report.observationText}</p></div>}
      {report.nextStep && <div className="report-copy"><h5>Prochaine étape</h5><p>{report.nextStep}</p></div>}
      {report.observations.length > 0 && <ul className="competency-progress">{report.observations.map(item => <li key={item.competencyId} className="competency-row">
        <span className="row-text"><span className="row-title">{competencies.get(item.competencyId) ?? 'Compétence'}</span>
          {item.context && <span className="row-meta">{item.context}</span>}</span>
        <CompetencyLevel level={item.level} />
      </li>)}</ul>}
    </div>
  );
}

/** Bilan publié d'une leçon, lu à la demande (dernière révision). */
function LessonReport({ schoolId, lesson, competencies }: { schoolId: string; lesson: Lesson; competencies: ReadonlyMap<string, string> }) {
  const [open, setOpen] = useState(false);
  const loaded = useLoad(async () => open ? (await readAll(schoolId, `lessons/${lesson.id}/reports`, reportSchema)).items : null, [schoolId, lesson.id, open], `${schoolId}/${lesson.id}`);
  // La dernière révision publiée : la plus haute séquence, quel que soit l’ordre de lecture.
  const latest = loaded.data?.reduce<Report | undefined>((best, item) => !best || item.sequence > best.sequence ? item : best, undefined);
  return (
    <li className="report-row">
      <details className="disclosure report-disclosure" onToggle={event => setOpen(event.currentTarget.open)}>
      <summary><time dateTime={lesson.plannedStart}>{formatDateTime(lesson.plannedStart, lesson.timeZone)}</time></summary>
      {open && loaded.status === 'loading' && !loaded.data && <Loading label="Lecture du bilan…" />}
      {open && loaded.status === 'error' && <Notice tone="error" title="Bilan indisponible" live={false} actions={<ReadRetry loaded={loaded} />}><p>{loaded.error}</p></Notice>}
      {open && loaded.data && (latest ? <ReportBody report={latest} competencies={competencies} /> : <p className="caption">Aucun bilan publié.</p>)}
      </details>
    </li>
  );
}

/** Progression par compétence et bilans publiés d'une formation, en lecture seule. */
export function TrainingFollowUp({ schoolId, training, competencies, timeZone }: {
  schoolId: string; training: Training; competencies: ReadonlyMap<string, string>; timeZone: string;
}) {
  const [open, setOpen] = useState(false);
  const [year, setYear] = useState('');
  const [month, setMonth] = useState('');
  const loaded = useLoad(async (): Promise<{ progress: Progress; lessons: Lesson[]; truncated: boolean } | null> => {
    if (!open) return null;
    const [progress, lessons] = await Promise.all([readSchool(schoolId, `trainings/${training.id}/progress`, progressSchema),
      readAll(schoolId, 'lessons', lessonSchema, { trainingId: training.id })]);
    return { progress, lessons: lessons.items, truncated: lessons.truncated };
  }, [schoolId, training.id, open], `${schoolId}/${training.id}`);
  const data = loaded.data;
  const { reported, years, filtered, canFilter } = reportHistory(data?.lessons ?? [], { year, month }, data?.truncated ?? false);
  const observedIds = new Set(data?.progress.items.map(item => item.competencyId));
  const progression = data ? [
    ...data.progress.items.map(item => ({ id: item.competencyId, label: item.label, level: item.level, observedAt: item.observedAt, context: item.context,
      timeZone: data.lessons.find(lesson => lesson.id === item.sourceLessonId)?.timeZone ?? timeZone })),
    ...data.progress.unobservedCompetencyIds.filter(id => !observedIds.has(id)).map(id => ({ id, label: competencies.get(id) ?? 'Compétence', level: null, observedAt: null, context: '', timeZone })),
  ].sort((a, b) => a.label.localeCompare(b.label, 'fr')) : [];
  return (
    <details className="disclosure" onToggle={event => setOpen(event.currentTarget.open)}>
      <summary>Progression et bilans</summary>
      {open && loaded.status === 'loading' && !data && <Loading label="Lecture de la progression…" />}
      {open && loaded.status === 'error' && <Notice tone="error" title="Lecture impossible" live={false} actions={<ReadRetry loaded={loaded} />}><p>{loaded.error ?? readError(null)}</p></Notice>}
      {data && <div className="follow-up">
        <h4 className="section-title">Compétences</h4>
        {progression.length > 0 ? <ul className="competency-progress">{progression.map(item => <li key={item.id} className="competency-row">
          <span className="row-text"><span className="row-title">{item.label}</span>
            {item.observedAt && <span className="row-meta">{formatDateTime(item.observedAt, item.timeZone)}{item.context ? ` · ${item.context}` : ''}</span>}</span>
          <CompetencyLevel level={item.level} />
        </li>)}</ul>
          : <p className="caption">Aucune compétence dans cette formation.</p>}
        <h4 className="section-title">Bilans</h4>
        {data.truncated && <Notice tone="warning" title="Historique partiel" live={false}><p>Seule une partie des leçons a pu être chargée. Les filtres de période sont indisponibles.</p></Notice>}
        {canFilter && reported.length > 0 && <div className="report-filters">
          <SelectField label="Année" value={year} onChange={setYear} options={[{ value: '', label: 'Toutes les années' }, ...years.map(value => ({ value, label: value }))]} />
          <SelectField label="Mois" value={month} onChange={setMonth} options={[{ value: '', label: 'Tous les mois' }, ...months.map((label, index) => ({ value: String(index + 1).padStart(2, '0'), label }))]} />
          {(year || month) && <button type="button" className="button quiet" onClick={() => { setYear(''); setMonth(''); }}>Effacer les filtres</button>}
        </div>}
        {filtered.length === 0 ? <EmptyState symbol="file" title={reported.length ? 'Aucun bilan pour cette période' : 'Aucun bilan'} message="" />
          : <ul className="report-list">{filtered.map(lesson => <LessonReport key={lesson.id} schoolId={schoolId} lesson={lesson} competencies={competencies} />)}</ul>}
      </div>}
    </details>
  );
}
