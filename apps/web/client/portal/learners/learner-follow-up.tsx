import { useEffect, useState } from 'react';
import { ArrowLeft, ArrowUpRight, CalendarDays, ChevronRight, FileText, MapPin } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Badge } from '../../components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import type { Lesson, Report } from '../../school-api';
import { PortalSelect } from '../components/portal-select';
import type { LearnerController } from './learner-controller';
import { dateTime, levelLabels, useExactLesson, usePublishedReport, useTrainingFollowUp } from './dossier-controller';
import { ReadFeedback } from './learner-feedback';

const lessonStatuses = { PLANNED: 'Planifiée', COMPLETED: 'Réalisée', CANCELLED: 'Annulée', NO_SHOW: 'Absence' };

export function LearnerFollowUp({ state }: { state: LearnerController }) {
  const trainings = state.current ? state.trainingsOf(state.current.id) : [];
  const [choice, setChoice] = useState<string | null>(null);
  const [reportLesson, setReportLesson] = useState<Lesson | null>(null);
  const training = trainings.find(item => item.id === choice) ?? trainings.find(item => item.status === 'ACTIVE') ?? trainings[0];
  const follow = useTrainingFollowUp(training?.id ?? null);
  const exact = useExactLesson(state.current?.id ?? null, state.routeQuery?.lesson);
  useEffect(() => { setReportLesson(null); }, [training?.id, state.current?.id]);
  const lessons = follow.loaded.data?.lessons ?? [];
  const upcoming = [...lessons].filter(lesson => lesson.status === 'PLANNED' && Date.parse(lesson.plannedEnd) >= Date.now()).sort((a, b) => Date.parse(a.plannedStart) - Date.parse(b.plannedStart))[0];
  const latest = follow.history.reported[0] ?? null;
  const report = usePublishedReport(reportLesson ?? latest);
  const currentReport = report.data?.latest;
  if (reportLesson) return <section className="student-subpage"><Button variant="ghost" onClick={() => setReportLesson(null)}><ArrowLeft />Retour au suivi</Button><header className="student-section-heading"><div><p className="student-eyebrow">Bilan de leçon</p><h2>{dateTime(reportLesson.plannedStart, reportLesson.timeZone)}</h2></div></header><LessonContext lesson={reportLesson} state={state} /><ReadFeedback loaded={report} />{currentReport && <ReportDetail report={currentReport} state={state} />}{report.data && !currentReport && <p className="student-muted">Aucun bilan publié pour cette leçon.</p>}{report.data?.truncated && <p className="student-warning">L’historique des révisions est partiellement chargé.</p>}{(report.data?.items.length ?? 0) > 1 && <section className="student-section"><h3>Révisions précédentes</h3>{report.data?.items.filter(item => item.id !== currentReport?.id).sort((a, b) => b.sequence - a.sequence).map(item => <article key={item.id} className="student-history-revision"><h4>Révision {item.sequence} · {dateTime(item.publishedAt, reportLesson.timeZone)}</h4><ReportDetail report={item} state={state} /></article>)}</section>}</section>;
  return <div className="student-follow-up">
    <ReadFeedback loaded={state.selectedTrainings} />
    {trainings.length > 1 && <div className="student-training-picker"><PortalSelect id="follow-training" label="Formation suivie" value={training?.id ?? null} onValueChange={setChoice} options={trainings.map(item => ({ value: item.id, label: state.title(item) }))} /></div>}
    {state.routeQuery?.lesson && <section className="student-section student-context-lesson"><h2>Leçon sélectionnée dans l’agenda</h2><ReadFeedback loaded={exact} />{exact.data && <><LessonContext lesson={exact.data} state={state} />{exact.data.currentPublishedRevisionId && <Button variant="outline" onClick={() => setReportLesson(exact.data!)}>Lire le bilan<FileText /></Button>}</>}</section>}
    {!training && state.selectedTrainings.status === 'ready' ? <div className="student-empty"><CalendarDays aria-hidden="true" /><h2>Aucune formation ouverte</h2><p>Les formations et leur historique apparaîtront ici.</p></div> : <>
      <ReadFeedback loaded={follow.loaded} />
      <div className="student-follow-grid"><main className="student-follow-main">
        <section className="student-section"><div className="student-section-heading"><h2>Prochaine leçon</h2>{upcoming && <Button variant="ghost" size="sm" onClick={() => state.navigate('agenda', { lesson: upcoming.id })}>Voir l’agenda<ArrowUpRight /></Button>}</div>
          {upcoming ? <div className="student-next-lesson"><span className="student-date-icon"><CalendarDays aria-hidden="true" /></span><div><h3>{dateTime(upcoming.plannedStart, upcoming.timeZone)}</h3><p>{state.name(upcoming.instructorMembershipId)}</p><span><MapPin aria-hidden="true" />{upcoming.meetingPoint}</span></div></div> : follow.loaded.status === 'ready' ? <p className="student-muted">Aucune leçon à venir dans les données chargées.</p> : null}
        </section>
        <section className="student-section"><div className="student-section-heading"><h2>À travailler ensuite</h2>{latest && <Button variant="ghost" size="sm" onClick={() => setReportLesson(latest)}>Dernier bilan<ChevronRight /></Button>}</div><ReadFeedback loaded={report} />{currentReport ? <p className="student-next-step">{currentReport.nextStep || 'Aucun objectif renseigné dans ce bilan.'}</p> : report.status === 'ready' && <p className="student-muted">Aucun bilan publié pour cette formation.</p>}</section>
        <section className="student-section"><div className="student-section-heading"><h2>Progression</h2><span className="student-muted">{training && state.category(training)}</span></div>
          {follow.loaded.data?.progress.items.length ? <div className="student-progress-list">{follow.loaded.data.progress.items.map(item => <article key={item.competencyId}><div className="student-progress-title"><h3>{item.label}</h3><span className="student-level" data-level={item.level}>{levelLabels[item.level]}</span></div><p>{item.context}</p><div className="student-progress-source"><span>{dateTime(item.observedAt, state.school.timeZone)}</span>{lessons.some(lesson => lesson.id === item.sourceLessonId) && <Button variant="ghost" size="sm" onClick={() => setReportLesson(lessons.find(lesson => lesson.id === item.sourceLessonId)!)}>Voir l’observation<ChevronRight /></Button>}</div></article>)}</div> : follow.loaded.status === 'ready' && <p className="student-muted">Aucune observation publiée.</p>}
          {!!follow.loaded.data?.progress.unobservedCompetencyIds.length && <div className="student-unobserved"><h3>Pas encore observé</h3><ul>{follow.loaded.data.progress.unobservedCompetencyIds.map(id => <li key={id}>{state.competencies.get(id) ?? 'Compétence non chargée'}</li>)}</ul></div>}
        </section>
      </main><aside className="student-follow-aside"><section className="student-section"><h2>Bilans des leçons</h2>
        {follow.loaded.data?.truncated && <Alert><AlertTitle>Historique partiel</AlertTitle><AlertDescription>Les filtres sont désactivés : tous les bilans ne sont pas chargés.</AlertDescription></Alert>}
        {follow.history.reported.length > 0 && <div className="student-history-filters"><PortalSelect id="report-year" label="Année" value={follow.year} onValueChange={value => follow.setYear(value ?? '')} disabled={!follow.history.canFilter} options={[{ value: '', label: 'Toutes' }, ...follow.history.years.map(year => ({ value: year, label: year }))]} /><PortalSelect id="report-month" label="Mois" value={follow.month} onValueChange={value => follow.setMonth(value ?? '')} disabled={!follow.history.canFilter} options={[{ value: '', label: 'Tous' }, ...Array.from({ length: 12 }, (_, index) => ({ value: String(index + 1).padStart(2, '0'), label: new Intl.DateTimeFormat('fr-CH', { month: 'long' }).format(new Date(2026, index, 1)) }))]} /></div>}
        <div className="student-history-list">{follow.history.filtered.map(lesson => <button type="button" key={lesson.id} onClick={() => setReportLesson(lesson)}><FileText aria-hidden="true" /><span><strong>{dateTime(lesson.plannedStart, lesson.timeZone)}</strong><span>{state.name(lesson.instructorMembershipId)}</span></span><ChevronRight aria-hidden="true" /></button>)}</div>{follow.loaded.status === 'ready' && !follow.history.filtered.length && <p className="student-muted">Aucun bilan dans cette période.</p>}
      </section></aside></div>
    </>}
  </div>;
}

function LessonContext({ lesson, state }: { lesson: Lesson; state: LearnerController }) {
  return <div className="student-lesson-context"><Badge variant="secondary">{lessonStatuses[lesson.status]}</Badge><span>{state.name(lesson.instructorMembershipId)}</span><span><MapPin aria-hidden="true" />{lesson.meetingPoint}</span>{lesson.permitWarning && <Badge variant="outline">Permis à vérifier</Badge>}</div>;
}
function ReportDetail({ report, state }: { report: Report; state: LearnerController }) {
  return <article className="student-report"><div className="student-report-meta">Publié le {dateTime(report.publishedAt, state.school.timeZone)} · {state.name(report.authorMembershipId)} · Révision {report.sequence}</div>{report.correctionReason && <Alert><AlertTitle>Bilan corrigé</AlertTitle><AlertDescription>{report.correctionReason}</AlertDescription></Alert>}<section><h3>Travail réalisé</h3><p>{report.workedOn || 'Non renseigné'}</p></section><section><h3>Observations partagées</h3><p>{report.observationText || 'Non renseigné'}</p></section><section><h3>Prochaine étape</h3><p>{report.nextStep || 'Non renseignée'}</p></section>{report.observations.length > 0 && <section><h3>Compétences observées</h3>{report.observations.map((item, index) => <div className="student-report-observation" key={`${item.competencyId}/${index}`}><strong>{state.competencies.get(item.competencyId) ?? 'Compétence non chargée'}</strong><span className="student-level" data-level={item.level}>{levelLabels[item.level]}</span><p>{item.context}</p></div>)}</section>}</article>;
}
