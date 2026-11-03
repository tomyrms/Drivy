import { useEffect, useMemo, useRef, useState } from 'react';
import { civilDateIn } from '../../agenda-model';
import { learnerFilterContext } from '../../console-filter-model';
import { assignmentIsOpen, availableTrainingOfferings, createCommand, filled, isCivilDate, matchesSearch, permitBody, permitProblem, transitionProblem, trainingTransitions, type PermitDraft, type SchoolCommand, type TrainingTransition } from '../../command-core';
import { refusalOutcome } from '../../command-lane';
import { kindsOf } from '../../command-families';
import { useCommandRevision, useCommandSnapshot } from '../../command-store';
import { activeInstructors, offeringLabel, openOfferings } from '../../invitation-model';
import { assignmentSchema, curriculumSchema, learnerSchema, memberSchema, offeringSchema, permitSchema, readAll, readSchool, trainingSchema, type Assignment, type Learner, type Permit, type Training } from '../../school-api';
import { readError, useCommandLane, useConsole, useLoad, useRouteSelection, useUnsavedChanges, type Outcome } from '../../console/context';
import { useListState } from '../../console/list-state';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { RequestFailure } from '../../protocol';
import { followedFor, projectAssignments, projectLearner, projectTrainings, visibleIntentions, type LearnerIntention, type Mark } from './learner-projection';

export const trainingStatusLabels: Record<Training['status'], string> = { ACTIVE: 'En cours', PAUSED: 'En pause', COMPLETED: 'Terminée', CANCELLED: 'Annulée' };
const emptyPermit = (): PermitDraft => ({ physicalSeen: false, validUntil: '', decision: 'APPROVED', reason: '' });
export type LearnerDialog =
  | { kind: 'transition'; training: Training; transition: TrainingTransition }
  | { kind: 'end'; training: Training; assignment: Assignment }
  | { kind: 'permit'; training: Training }
  | { kind: 'archive' } | { kind: 'restore' } | null;
type Dossier = { assignments: Assignment[]; permits: Permit[] | null; permitError: string | null };
/** A request the school refused after its form had been released: the typed content comes back with the refusal. */
export interface LearnerRefusal { readonly intention: LearnerIntention; readonly outcome: NonNullable<Outcome> }
/** Where a refused creation comes back: the form of a new formation, or the assignment review of a formation. */
export type Reopen = { kind: 'training-create' } | { kind: 'assignment-create'; trainingId: string } | null;

/** Memory only, in the console's drafts: renewed with the account, school, membership and access epoch; never written to browser storage. */
const INTENTIONS_KEY = 'learners/intentions';
const WAITING = 'Une demande sur ce dossier attend sa confirmation (voir en haut de la page).';
/** Reads that change when a dossier, a formation or an assignment is confirmed; lessons, hours and invitations are not read again for them. */
const dossierReads = kindsOf('learners');
const referenceReads = kindsOf('members', 'catalogue');

/**
 * Existing school commands, version guards and scoped reads, one request followed at a time per dossier and independent of every
 * other dossier and of the rest of the page. Once a request is kept the form is released and the line says « à confirmer »: the
 * formation is not official, no access is granted and the dossier is not archived before the school's receipt. A refusal keeps the
 * rest of the page as it is and brings the typed content back.
 */
export function useLearnerController() {
  const { schoolId, school, membership, navigate, routeQuery, setRouteQuery, drafts } = useConsole();
  const { entries } = useCommandSnapshot();
  const revision = useCommandRevision(dossierReads);
  const referencesRevision = useCommandRevision(referenceReads);
  const [selected, selectLearner] = useRouteSelection();
  const setSelected = (selection: string | null) => {
    if (routeQuery?.lesson && setRouteQuery) setRouteQuery({ ...routeQuery, selection: selection ?? undefined, lesson: undefined });
    else selectLearner(selection);
  };
  const [search, setSearch] = useListState('learners/search', '');
  const [statusFilter, setStatusFilter] = useListState<'active' | 'archived' | 'all'>('learners/status', 'active');
  const [readinessFilter, setReadinessFilter] = useListState<'all' | 'incomplete'>('learners/readiness', 'all');
  const [sort, setSort] = useListState<'name-asc' | 'name-desc'>('learners/sort', 'name-asc');
  const [page, setPage] = useListState('learners/page', 1);
  const [offeringId, setOfferingId] = useState('');
  const schoolToday = () => civilDateIn(school.timeZone);
  const [startedOn, setStartedOn] = useState(schoolToday);
  const [instructorFor, setInstructorFor] = useState<Record<string, string>>({});
  const [dialog, setDialog] = useState<LearnerDialog>(null);
  const [reason, setReasonRaw] = useState('');
  const [permit, setPermitRaw] = useState<PermitDraft>(emptyPermit());
  const [acknowledged, setAcknowledged] = useState(false);
  const [restored, setRestored] = useState<NonNullable<Outcome> | null>(null);
  const [refusals, setRefusals] = useState<LearnerRefusal[]>([]);
  const [reopen, setReopen] = useState<Reopen>(null);
  const setReason = (value: string) => { setRestored(null); setReasonRaw(value); };
  const setPermit = (update: PermitDraft | ((value: PermitDraft) => PermitDraft)) => { setRestored(null); setPermitRaw(update); };

  const stored = useRef<LearnerIntention[]>((drafts?.get(INTENTIONS_KEY) as LearnerIntention[] | undefined) ?? []);
  const [intentionList, setIntentionList] = useState<LearnerIntention[]>(stored.current);
  const change = (next: (list: LearnerIntention[]) => LearnerIntention[]) => {
    stored.current = next(stored.current);
    drafts?.set(INTENTIONS_KEY, stored.current);
    setIntentionList(stored.current);
  };
  const lane = useCommandLane(intent => {
    const settled = stored.current.find(item => item.operationId === intent.operationId);
    change(list => list.map(item => item.operationId === intent.operationId && item.settledAt === undefined ? { ...item, settledAt: Date.now() } : item));
    // The dossier is archived or restored for good: the person leaves it (archive) or sees it among the active ones (restore), as before.
    if (settled?.kind === 'learner-archive') { if (latest.current.selected === settled.learnerId) setSelected(null); }
    else if (settled?.kind === 'learner-restore') setStatusFilter('active');
  });
  const latest = useRef({ selected });
  latest.current = { selected };

  const dirty = !!(offeringId || Object.values(instructorFor).some(Boolean) || reason || permit.physicalSeen || permit.validUntil || permit.reason || permit.decision !== 'APPROVED');
  const releaseChanges = useUnsavedChanges(dirty);
  useEffect(() => { setDialog(null); setReasonRaw(''); setPermitRaw(emptyPermit()); setOfferingId(''); setInstructorFor({}); setRestored(null); }, [selected]);

  // Un enrichissement indisponible ne rend pas l’annuaire des élèves indisponible. Known data stays on screen while a read is renewed.
  const loaded = useLoad(() => readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }), [schoolId, revision], schoolId, 'learners');
  const listTrainings = useLoad(() => readAll(schoolId, 'trainings', trainingSchema), [schoolId, revision], schoolId, 'trainings');
  const resources = useLoad(async () => {
    const [offerings, members, curricula] = await Promise.all([
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'curricula', curriculumSchema)]);
    return { offerings: offerings.items, members: members.items, curricula: curricula.items, truncated: offerings.truncated || members.truncated || curricula.truncated };
  }, [schoolId, referencesRevision, revision], schoolId, 'learner-references');
  const listedCurrent = loaded.data?.items.find(learner => learner.id === selected) ?? null;
  const selectedLearner = useLoad(async (): Promise<Learner | null> => {
    if (!selected || listedCurrent) return null;
    const learner = await readSchool(schoolId, `learners/${selected}`, learnerSchema);
    if (learner.id !== selected || learner.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return learner;
  }, [schoolId, selected, listedCurrent, revision], `${schoolId}/${selected ?? ''}`);
  const selectedTrainings = useLoad(async () => {
    if (!selected) return { items: [] as Training[], truncated: false };
    const result = await readAll(schoolId, 'trainings', trainingSchema, { learnerId: selected });
    if (result.items.some(training => training.learnerId !== selected || training.schoolId !== schoolId)) throw new RequestFailure('INVALID_RESPONSE');
    return result;
  }, [schoolId, selected, revision], `${schoolId}/${selected ?? ''}`, 'selected-trainings');
  const dossier = useLoad(async (): Promise<Record<string, Dossier>> => {
    const trainings = selectedTrainings.data?.items ?? [];
    const entriesRead = await Promise.all(trainings.map(async training => {
      const [assignments, permitResult] = await Promise.all([readAll(schoolId, `trainings/${training.id}/assignments`, assignmentSchema),
        readAll(schoolId, `trainings/${training.id}/permit-checks`, permitSchema)
          .then(list => {
            if (list.items.some(permit => permit.trainingId !== training.id)) throw new RequestFailure('INVALID_RESPONSE');
            return list.truncated ? { items: null, error: 'L’historique est partiellement chargé. Le dernier contrôle ne peut pas être établi.' } : { items: list.items, error: null };
          }).catch(error => ({ items: null, error: readError(error) }))]);
      if (assignments.truncated || assignments.items.some(assignment => assignment.trainingId !== training.id)) throw new RequestFailure('INVALID_RESPONSE');
      return [training.id, { assignments: assignments.items, permits: permitResult.items, permitError: permitResult.error }] as const;
    }));
    return Object.fromEntries(entriesRead);
  }, [schoolId, selected, selectedTrainings.data], `${schoolId}/${selected ?? ''}`, 'dossier');

  // Requests the store follows for this school, and the intentions that still show next to what the school lists.
  const followed = useMemo(() => new Set([...entries.values()].filter(entry => entry.meta.schoolId === schoolId).map(entry => entry.meta.operationId)), [entries, schoolId]);
  const readAts = [loaded.readAt, listTrainings.readAt, selectedTrainings.readAt, selected ? dossier.readAt : Infinity];
  const readAt = readAts.every(value => value !== undefined) ? Math.min(...(readAts as number[])) : undefined;
  const intentions = useMemo(() => visibleIntentions(intentionList, followed, readAt), [intentionList, followed, readAt]);

  const data = resources.data;
  const projected = useMemo(() => new Map((loaded.data?.items ?? []).map(learner => [learner.id, projectLearner(learner, intentions)] as const)), [loaded.data, intentions]);
  const learners = useMemo(() => [...projected.values()].map(item => item.learner)
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)), [projected]);
  // Two dossiers with the same name are told apart by a short reference derived from the identifier, which stays the key of every action.
  const references = useMemo(() => homonymReferences(learners.map(learner => ({ id: learner.id, label: learner.displayName }))), [learners]);
  const labelOf = (learner: Pick<Learner, 'id' | 'displayName'>) => distinctLabel(learner.displayName, references.get(learner.id));
  const notReady = (learner: Learner) => learner.profileReadiness === 'MINIMAL' || learner.profileReadiness === 'ACTION_REQUIRED';
  const visible = learners.filter(learner => (statusFilter === 'all' || (statusFilter === 'archived') === !!learner.archivedAt)
    && (readinessFilter === 'all' || (!learner.archivedAt && notReady(learner)))
    && matchesSearch([learner.displayName, learner.contactEmail, learner.contactPhone], search))
    .sort((a, b) => (sort === 'name-desc' ? -1 : 1) * (a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)));
  const pageSize = 25;
  const currentPage = Math.max(1, Math.min(page, Math.ceil(visible.length / pageSize) || 1));
  const filterContext = learnerFilterContext({ search, statusFilter, readinessFilter });
  const pageRows = visible.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  useEffect(() => { if (loaded.status === 'ready' && page !== currentPage) setPage(currentPage); }, [loaded.status, page, currentPage, setPage]);
  // Seule la dernière version active de chaque offre ouvre une formation (règle partagée avec les invitations par code).
  const offerings = useMemo(() => openOfferings(data?.offerings ?? []), [data]);
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const competencies = useMemo(() => new Map((data?.curricula ?? []).flatMap(curriculum => curriculum.competencies.map(item => [item.id, item.label] as const))), [data]);
  const name = (membershipId: string) => data?.members.find(member => member.id === membershipId)?.displayName ?? 'Moniteur';

  const trainingView = (learnerId: string) => projectTrainings(learnerId === selected ? selectedTrainings.data?.items ?? [] : (listTrainings.data?.items ?? []), intentions, learnerId);
  const trainingsOf = (learnerId: string) => trainingView(learnerId).trainings;
  /** The dossier line or formation of a request still to be confirmed. */
  const learnerMark = (learnerId: string): Mark | undefined => projected.get(learnerId)?.mark;
  const assignmentsOf = (trainingId: string) => projectAssignments(dossier.data?.[trainingId]?.assignments ?? [], intentions, trainingId, Date.now());
  const offeringOf = (training: Training) => data?.offerings.find(item => item.id === training.offeringId);
  const category = (training: Training) => training.categoryCode ?? offeringOf(training)?.categoryCode ?? '';
  const title = (training: Training) => { const offer = offeringOf(training); return offer ? offeringLabel(offer, data?.offerings ?? []) : `Permis ${category(training)}`; };
  const current = (listedCurrent ? projected.get(listedCurrent.id)?.learner : undefined) ?? selectedLearner.data ?? null;
  const currentReady = listedCurrent ? loaded.status === 'ready' : selectedLearner.status === 'ready';
  // Reading is complete and the school is active: nothing here waits for another dossier's request.
  const canWrite = school.status === 'ACTIVE' && currentReady && resources.status === 'ready' && !resources.data?.truncated
    && selectedTrainings.status === 'ready' && !selectedTrainings.data?.truncated;
  const canEdit = canWrite && !current?.archivedAt;
  // The school orders what touches the same dossier: the next request waits, its form stays a draft.
  const waiting = !!current && (lane.blocked({ kind: 'createTraining', scope: current.id }) || followedFor(intentions, current.id));
  const waitingReason = waiting ? WAITING : null;
  const availableOfferings = availableTrainingOfferings(offerings, data?.offerings ?? [], current ? trainingsOf(current.id) : []);
  const canReviewPermit = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR');
  const canArchive = membership.roles.includes('ADMIN');

  function ask(next: LearnerDialog) { lane.clearOutcome(); setRestored(null); setReasonRaw(''); setPermitRaw(emptyPermit()); setAcknowledged(false); setDialog(next); }
  const dialogTag = !current ? null : dialog?.kind === 'transition' ? `training:${dialog.training.id}` : dialog?.kind === 'end' ? `assignment:${dialog.assignment.id}`
    : dialog?.kind === 'permit' ? `permit:${dialog.training.id}` : dialog ? `learner:${current.id}` : null;
  const outcomeFor = (tag: string | null): NonNullable<Outcome> | null => restored ?? (tag ? (lane.outcomes.get(tag) as NonNullable<Outcome> | undefined) ?? null : null);
  const dialogOutcome = outcomeFor(dialogTag);

  /** Hands the request to the store. Refused locally: the form stays as it is. Kept: the form is released and the line says so. */
  function keep(command: SchoolCommand, success: string, intention: LearnerIntention): 'kept' | 'refused' {
    lane.clearOutcome();
    const started = lane.run(command, success, intention.tag);
    if (!started.admitted) { void started.result; return 'refused'; }
    change(list => [...list.filter(item => item.settledAt === undefined ? followed.has(item.operationId) : (readAt ?? 0) < item.settledAt), intention]);
    releaseChanges(); setDialog(null); setReasonRaw(''); setPermitRaw(emptyPermit()); setAcknowledged(false); setRestored(null);
    void started.result.then(result => {
      if (result.status !== 'rejected') return;
      change(list => list.filter(item => item.operationId !== intention.operationId));
      setRefusals(list => [...list, { intention, outcome: refusalOutcome(result) as NonNullable<Outcome> }]);
    });
    return 'kept';
  }

  function openTraining(): 'kept' | 'refused' | 'invalid' {
    if (!canEdit || !current || !availableOfferings.some(offering => offering.id === offeringId) || !isCivilDate(startedOn)) return 'invalid';
    const command = createCommand({ schoolId, kind: 'createTraining', path: 'trainings', resourceVersion: 0, scope: current.id,
      body: { learnerId: current.id, offeringId, startedOn } });
    const result = keep(command, 'La formation est ouverte.', { kind: 'training-create', tag: `training:new:${current.id}`, operationId: command.operationId, learnerId: current.id, offeringId, startedOn });
    if (result === 'kept') { setOfferingId(''); setStartedOn(schoolToday()); }
    return result;
  }
  function assign(training: Training): 'kept' | 'refused' | 'invalid' {
    const instructorMembershipId = instructorFor[training.id];
    const own = assignmentsOf(training.id).assignments;
    if (!canEdit || !current || training.status !== 'ACTIVE' || dossier.status !== 'ready' || !dossier.data?.[training.id] || !instructors.some(member => member.id === instructorMembershipId)
      || own.some(assignment => assignment.instructorMembershipId === instructorMembershipId && assignmentIsOpen(assignment))) return 'invalid';
    const command = createCommand({ schoolId, kind: 'createAssignment', path: `trainings/${training.id}/assignments`, resourceVersion: 0, scope: current.id,
      body: { instructorMembershipId, validFrom: new Date().toISOString(), validUntil: null } });
    const result = keep(command, 'Le moniteur est affecté.', { kind: 'assignment-create', tag: `assignment:new:${training.id}`, operationId: command.operationId,
      learnerId: current.id, trainingId: training.id, instructorId: instructorMembershipId! });
    if (result === 'kept') setInstructorFor(values => ({ ...values, [training.id]: '' }));
    return result;
  }
  const permitError = dialog?.kind === 'permit' ? permitProblem(permit, schoolToday()) : null;
  const transitionError = dialog?.kind === 'transition' ? transitionProblem(dialog.transition, reason) : null;
  const archiveError = (dialog?.kind === 'archive' || dialog?.kind === 'restore') && !filled(reason, 1000) ? 'Indiquez le motif (1 000 caractères au plus).' : null;
  function confirm(): 'kept' | 'refused' | 'invalid' {
    if (!dialog || !current || !canWrite) return 'invalid';
    if (dialog.kind !== 'restore' && !canEdit) return 'invalid';
    if ((dialog.kind === 'archive' || dialog.kind === 'restore') && !canArchive) return 'invalid';
    if (dialog.kind === 'permit' && !canReviewPermit) return 'invalid';
    if ((dialog.kind === 'archive' || dialog.kind === 'transition' && dialog.transition.danger) && !acknowledged) return 'invalid';
    const learnerId = current.id;
    if (dialog.kind === 'transition' && !transitionError) {
      const { training, transition } = dialog;
      const command = createCommand({ schoolId, kind: 'transitionTraining', path: `trainings/${training.id}/transition`, ifMatch: training.version,
        resourceId: training.id, resourceVersion: training.version, scope: learnerId, body: { targetStatus: transition.target, reason: reason.trim() } });
      return keep(command, transition.target === 'CANCELLED' ? 'La formation est annulée.' : transition.target === 'COMPLETED' ? 'La formation est terminée.' : transition.target === 'PAUSED' ? 'La formation est en pause.' : 'La formation reprend.',
        { kind: 'training-transition', tag: `training:${training.id}`, operationId: command.operationId, learnerId, trainingId: training.id, target: transition.target, label: transition.label, reason });
    }
    if (dialog.kind === 'end') {
      const { training, assignment } = dialog;
      const command = createCommand({ schoolId, kind: 'endAssignment', path: `trainings/${training.id}/assignments/${assignment.id}/end`, ifMatch: assignment.version,
        resourceId: assignment.id, resourceVersion: assignment.version, scope: learnerId, body: {} });
      return keep(command, 'L’affectation est terminée.', { kind: 'assignment-end', tag: `assignment:${assignment.id}`, operationId: command.operationId, learnerId, trainingId: training.id, assignmentId: assignment.id });
    }
    if (dialog.kind === 'permit' && !permitError) {
      const { training } = dialog;
      const command = createCommand({ schoolId, kind: 'recordPermitCheck', path: `trainings/${training.id}/permit-checks`, ifMatch: training.version,
        resourceVersion: 0, scope: learnerId, body: permitBody(permit, category(training)) });
      return keep(command, permit.decision === 'APPROVED' ? 'Le permis est consigné.' : 'Le refus est consigné.',
        { kind: 'permit-check', tag: `permit:${training.id}`, operationId: command.operationId, learnerId, trainingId: training.id, draft: { ...permit } });
    }
    if (dialog.kind === 'archive' && !archiveError) {
      const command = createCommand({ schoolId, kind: 'archiveLearner', path: `learners/${learnerId}/archive`, ifMatch: current.version,
        resourceId: learnerId, resourceVersion: current.version, scope: learnerId, body: { reason: reason.trim() } });
      return keep(command, 'Le dossier est archivé.', { kind: 'learner-archive', tag: `learner:${learnerId}`, operationId: command.operationId, learnerId, reason });
    }
    if (dialog.kind === 'restore' && !archiveError && membership.roles.includes('ADMIN')) {
      const command = createCommand({ schoolId, kind: 'restoreLearner', path: `learners/${learnerId}/restore`, ifMatch: current.version,
        resourceId: learnerId, resourceVersion: current.version, scope: learnerId, body: { reason: reason.trim() } });
      return keep(command, 'Le dossier est restauré.', { kind: 'learner-restore', tag: `learner:${learnerId}`, operationId: command.operationId, learnerId, reason });
    }
    return 'invalid';
  }

  /** Takes a refused request up again: the form, the review or the dialog comes back with what was typed and the school's refusal. */
  function resume(refusal: LearnerRefusal) {
    const { intention, outcome } = refusal;
    setRefusals(list => list.filter(item => item !== refusal));
    lane.clearOutcome();
    if (selected !== intention.learnerId) setSelected(intention.learnerId);
    const trainings = trainingsOf(intention.learnerId);
    if (intention.kind === 'training-create') { setOfferingId(intention.offeringId); setStartedOn(intention.startedOn); setReopen({ kind: 'training-create' }); setRestored(outcome); }
    else if (intention.kind === 'assignment-create') { setInstructorFor(values => ({ ...values, [intention.trainingId]: intention.instructorId })); setReopen({ kind: 'assignment-create', trainingId: intention.trainingId }); setRestored(outcome); }
    else if (intention.kind === 'learner-archive' || intention.kind === 'learner-restore') {
      setDialog({ kind: intention.kind === 'learner-archive' ? 'archive' : 'restore' }); setReasonRaw(intention.reason); setAcknowledged(intention.kind === 'learner-archive'); setRestored(outcome);
    } else {
      const training = trainings.find(item => item.id === intention.trainingId);
      if (!training) return;
      if (intention.kind === 'training-transition') {
        const transition = trainingTransitions(training.status).find(item => item.target === intention.target);
        if (!transition) return;
        setDialog({ kind: 'transition', training, transition }); setReasonRaw(intention.reason); setAcknowledged(transition.danger); setRestored(outcome);
      } else if (intention.kind === 'permit-check') { setDialog({ kind: 'permit', training }); setPermitRaw(intention.draft); setRestored(outcome); }
      else {
        const assignment = dossier.data?.[intention.trainingId]?.assignments.find(item => item.id === intention.assignmentId);
        if (!assignment) return;
        setDialog({ kind: 'end', training, assignment }); setRestored(outcome);
      }
    }
  }
  const dismiss = (refusal: LearnerRefusal) => setRefusals(list => list.filter(item => item !== refusal));
  const confirmation = [...lane.outcomes.values()].filter(item => item.tone === 'success').at(-1) as NonNullable<Outcome> | undefined ?? null;

  return { schoolId, school, membership, navigate, routeQuery, selected, setSelected,
    search, setSearch, statusFilter, setStatusFilter, readinessFilter, setReadinessFilter,
    sort, setSort, currentPage, setPage, pageSize, pageRows, visible, filterContext,
    labelOf, loaded, listTrainings, resources, selectedLearner, selectedTrainings, dossier,
    current, currentReady, canWrite, canEdit, canReviewPermit, canArchive, notReady,
    offerings, availableOfferings, instructors, competencies, name, trainingsOf, trainingView, assignmentsOf, learnerMark, category, title,
    offeringId, setOfferingId, startedOn, setStartedOn, instructorFor, setInstructorFor,
    ask, dialog, reason, setReason, permit, setPermit, acknowledged, setAcknowledged,
    permitError, transitionError, archiveError, openTraining, assign, confirm,
    waiting, waitingReason, dialogOutcome, outcomeFor, confirmation, clearOutcome: () => { lane.clearOutcome(); setRestored(null); },
    refusals, resume, dismiss, reopen, consumeReopen: () => setReopen(null) };
}
export type LearnerController = ReturnType<typeof useLearnerController>;
