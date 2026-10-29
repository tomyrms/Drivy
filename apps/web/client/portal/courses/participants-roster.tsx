import { useState } from 'react';
import { ChevronDown, UserPlus } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Users } from 'lucide-react';
import { enrollableLearners, sourceLabel, type CourseEnrollment, type CourseSeries } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { learnerSchema, readAll } from '../../school-api';
import { PortalSelect } from '../components/portal-select';
import { ReadFeedback } from '../agenda/presentation';
import { instantDateTime, keptMessage } from './course-presentation';
import { offerState, rosterSplit } from './participants-model';
import { ActionDialog } from './participants-dialogs';
import { FeedbackText } from './participants-parts';
import { feedbackKey, type CourseParticipants } from './use-course-participants';

/** Enrolment, seat and waiting list are three different facts. Staff can enrol; nobody here can push a waiting entry onto a seat. */
export function RosterTab({ state, series, now }: { state: CourseParticipants; series: CourseSeries; now: number }) {
  const [enrolling, setEnrolling] = useState(false);
  const [cancelling, setCancelling] = useState<CourseEnrollment | null>(null);
  const { school } = useConsole();
  const roster = state.rosterRead.data;
  if (!roster) return <ReadFeedback loaded={state.rosterRead} label="Lecture des inscrits" />;
  const { active, cancelled } = rosterSplit(roster);
  const full = series.remainingSeats === 0;
  return <div className="participants-tab">
    <ReadFeedback loaded={state.rosterRead} label="Lecture des inscrits" />
    <div className="participants-head"><h2>Inscrits</h2>
      <Button disabled={state.locked} onClick={() => setEnrolling(true)}><UserPlus data-icon="inline-start" />Inscrire un élève</Button></div>
    {active.length === 0 ? <Empty className="participants-empty"><EmptyHeader><EmptyMedia variant="icon"><Users /></EmptyMedia><EmptyTitle>Aucun inscrit</EmptyTitle></EmptyHeader>
      <EmptyContent><Button variant="outline" disabled={state.locked} onClick={() => setEnrolling(true)}>Inscrire un élève</Button></EmptyContent></Empty>
      : <ul className="participants-list">{active.map(item => <li key={item.id}>
        <div className="participants-main"><strong>{item.learnerDisplayName || 'Élève'}</strong>
          <span className="course-muted">{sourceLabel(item.source)} · annulation libre jusqu’au {instantDateTime(item.selfCancelDeadline, school.timeZone)}</span>
          <FeedbackText feedback={state.feedback[feedbackKey('roster', item.id)]} /></div>
        <Button variant="ghost" disabled={state.locked} aria-label={`Annuler l’inscription de ${item.learnerDisplayName || 'cet élève'}`} onClick={() => setCancelling(item)}>Annuler l’inscription</Button>
      </li>)}</ul>}
    {roster.waitlist.length > 0 && <section aria-labelledby="participants-waitlist"><h2 id="participants-waitlist">Liste d’attente</h2>
      <ol className="participants-list participants-waitlist">{roster.waitlist.map(entry => {
        const offer = offerState(entry, now);
        return <li key={entry.id}><span className="participants-rank" aria-label={`Rang ${entry.position}`}>{entry.position}</span>
          <div className="participants-main"><strong>{entry.learnerDisplayName || 'Élève'}</strong>
            {offer === 'offered' && entry.offerExpiresAt && <span className="course-muted">Place proposée jusqu’au {instantDateTime(entry.offerExpiresAt, school.timeZone)}</span>}
            {offer === 'expired' && <span className="course-muted">Offre expirée le {instantDateTime(entry.offerExpiresAt!, school.timeZone)}</span>}</div>
          {offer === 'offered' && <Badge variant="secondary">Place proposée</Badge>}{offer === 'expired' && <Badge variant="outline">Offre expirée</Badge>}</li>;
      })}</ol></section>}
    {cancelled.length > 0 && <Collapsible className="participants-cancelled">
      <CollapsibleTrigger render={<Button variant="ghost" className="participants-cancelled-trigger" />}>Inscriptions annulées ({cancelled.length})<ChevronDown data-icon="inline-end" /></CollapsibleTrigger>
      <CollapsibleContent><ul className="participants-list">{cancelled.map(item => <li key={item.id} data-muted="true"><div className="participants-main"><strong>{item.learnerDisplayName || 'Élève'}</strong>
        <span className="course-muted">{item.cancelledAt ? `Annulée le ${instantDateTime(item.cancelledAt, school.timeZone)}` : 'Annulée'}{item.cancelReason ? ` · ${item.cancelReason}` : ''}</span></div><Badge variant="outline">Annulée</Badge></li>)}</ul></CollapsibleContent>
    </Collapsible>}
    {enrolling && <EnrollDialog state={state} series={series} full={full} roster={roster} onClose={() => setEnrolling(false)} />}
    <ActionDialog open={cancelling !== null} title="Annuler l’inscription" subject={cancelling?.learnerDisplayName || 'Élève'} withReason destructive confirmLabel="Annuler l’inscription" state={state}
      facts={[['Cours', series.title], ['Portée', 'Toute la série']]} consequence="Aucun remboursement n’est effectué par cette action."
      onClose={() => setCancelling(null)} onConfirm={reason => cancelling ? state.cancelEnrollment(cancelling, reason) : Promise.resolve({ status: 'rejected' as const, message: 'Inscription introuvable.' })} />
  </div>;
}

/** Choose a student the school may enrol: the list is the school's own, with the places left said plainly. The school decides the rest. */
function EnrollDialog({ state, series, full, roster, onClose }: { state: CourseParticipants; series: CourseSeries; full: boolean; roster: Parameters<typeof enrollableLearners>[1]; onClose: () => void }) {
  const { schoolId } = useConsole();
  const learners = useLoad(() => readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }), [schoolId], undefined, 'learners/status=ALL');
  const [learner, setLearner] = useState<string | null>(null);
  const [refusal, setRefusal] = useState<string | null>(null);
  const candidates = enrollableLearners(learners.data?.items ?? [], roster);
  const references = homonymReferences(candidates.map(item => ({ id: item.id, label: item.displayName })));
  const options = candidates.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
  const partial = learners.data?.truncated === true;
  const ready = learners.status === 'ready' && !partial;
  async function enroll() {
    if (!learner || state.locked || !ready) return;
    setRefusal(null);
    const result = await state.enroll(learner);
    if (result.status === 'rejected') { setRefusal(result.message); return; }
    onClose();
  }
  return <Dialog open onOpenChange={(next, details) => { if (state.locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!state.locked}>
    <DialogHeader><DialogTitle>Inscrire un élève</DialogTitle><DialogDescription>{series.title}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void enroll(); }}>
      <ReadFeedback loaded={learners} label="Lecture des élèves" />
      <PortalSelect id="enroll-learner" label="Élève" value={learner} onValueChange={value => { setRefusal(null); setLearner(value); }} options={options} searchable placeholder="Choisir un élève"
        emptyText="Aucun élève à inscrire" disabled={state.locked || !ready} />
      {partial && <Alert><AlertTitle>Répertoire partiel</AlertTitle><AlertDescription>Les élèves admissibles ne sont pas tous disponibles : l’inscription attend une lecture complète.</AlertDescription></Alert>}
      <dl className="participants-facts"><div><dt>Places</dt><dd>{full ? 'Complet' : `${series.remainingSeats} libres sur ${series.capacity}`}</dd></div></dl>
      {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription></Alert>}
      <DialogFooter><Button type="button" variant="outline" disabled={state.locked} onClick={onClose}>Annuler</Button>
        <Button type="submit" disabled={state.locked || !learner || !ready || Boolean(state.runner.blockedReason)}>{state.runner.busy ? 'Confirmation…' : 'Inscrire'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
