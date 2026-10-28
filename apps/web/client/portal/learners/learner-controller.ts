import { useEffect, useMemo, useState } from 'react';
import { civilDateIn } from '../../agenda-model';
import { learnerFilterContext } from '../../console-filter-model';
import { assignmentIsOpen, availableTrainingOfferings, createCommand, filled, isCivilDate, matchesSearch, permitBody, permitProblem, transitionProblem, type PermitDraft, type TrainingTransition } from '../../command-core';
import { useCommandSnapshot, type SubmitResult } from '../../command-store';
import { activeInstructors, offeringLabel, openOfferings } from '../../invitation-model';
import { assignmentSchema, curriculumSchema, learnerSchema, memberSchema, offeringSchema, permitSchema, readAll, readSchool, trainingSchema, type Assignment, type Learner, type Permit, type Training } from '../../school-api';
import { readError, useCommandRunner, useConsole, useLoad, useRouteSelection, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import { RequestFailure } from '../../protocol';

export const trainingStatusLabels: Record<Training['status'], string> = { ACTIVE: 'En cours', PAUSED: 'En pause', COMPLETED: 'Terminée', CANCELLED: 'Annulée' };
const emptyPermit = (): PermitDraft => ({ physicalSeen: false, validUntil: '', decision: 'APPROVED', reason: '' });
export type LearnerDialog =
  | { kind: 'transition'; training: Training; transition: TrainingTransition }
  | { kind: 'end'; training: Training; assignment: Assignment }
  | { kind: 'permit'; training: Training }
  | { kind: 'archive' } | { kind: 'restore' } | null;
type Dossier = { assignments: Assignment[]; permits: Permit[] | null; permitError: string | null };
/** Existing school commands, version guards and scoped reads extracted without presentation. */
export function useLearnerController() {
  const { schoolId, school, membership, navigate, routeQuery, setRouteQuery } = useConsole();
  const { revision } = useCommandSnapshot();
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
  const [reason, setReason] = useState('');
  const [permit, setPermit] = useState<PermitDraft>(emptyPermit());
  const [acknowledged, setAcknowledged] = useState(false);
  // Une fois l'école a confirmé, les choix saisis ne doivent pas rester : sinon le moniteur affecté disparaît de la liste tout en restant « choisi ».
  const runner = useCommandRunner(() => { releaseChanges(); setOfferingId(''); setStartedOn(schoolToday()); setInstructorFor({}); setDialog(null); setReason(''); setPermit(emptyPermit()); });
  const releaseChanges = useUnsavedChanges(!runner.busy && !runner.pending && !!(offeringId || Object.values(instructorFor).some(Boolean) || reason
    || permit.physicalSeen || permit.validUntil || permit.reason || permit.decision !== 'APPROVED'));
  useEffect(() => { setDialog(null); setReason(''); setPermit(emptyPermit()); setOfferingId(''); setInstructorFor({}); }, [selected]);
  // Un enrichissement indisponible ne rend pas l’annuaire des élèves indisponible.
  const loaded = useLoad(() => readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }), [schoolId, revision]);
  const listTrainings = useLoad(() => readAll(schoolId, 'trainings', trainingSchema), [schoolId, revision]);
  const resources = useLoad(async () => {
    const [offerings, members, curricula] = await Promise.all([
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'curricula', curriculumSchema)]);
    return { offerings: offerings.items, members: members.items, curricula: curricula.items, truncated: offerings.truncated || members.truncated || curricula.truncated };
  }, [schoolId, revision]);
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
  }, [schoolId, selected, revision], `${schoolId}/${selected ?? ''}`);
  const dossier = useLoad(async (): Promise<Record<string, Dossier>> => {
    const trainings = selectedTrainings.data?.items ?? [];
    const entries = await Promise.all(trainings.map(async training => {
      const [assignments, permitResult] = await Promise.all([readAll(schoolId, `trainings/${training.id}/assignments`, assignmentSchema),
        readAll(schoolId, `trainings/${training.id}/permit-checks`, permitSchema)
          .then(list => {
            if (list.items.some(permit => permit.trainingId !== training.id)) throw new RequestFailure('INVALID_RESPONSE');
            return list.truncated ? { items: null, error: 'L’historique est partiellement chargé. Le dernier contrôle ne peut pas être établi.' } : { items: list.items, error: null };
          }).catch(error => ({ items: null, error: readError(error) }))]);
      if (assignments.truncated || assignments.items.some(assignment => assignment.trainingId !== training.id)) throw new RequestFailure('INVALID_RESPONSE');
      return [training.id, { assignments: assignments.items, permits: permitResult.items, permitError: permitResult.error }] as const;
    }));
    return Object.fromEntries(entries);
  }, [schoolId, selected, selectedTrainings.data], `${schoolId}/${selected ?? ''}`);

  const data = resources.data;
  const learners = useMemo(() => [...(loaded.data?.items ?? [])]
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)), [loaded.data]);
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
  const trainingsOf = (learnerId: string) => learnerId === selected
    ? selectedTrainings.data?.items ?? [] : (listTrainings.data?.items ?? []).filter(training => training.learnerId === learnerId);
  const offeringOf = (training: Training) => data?.offerings.find(item => item.id === training.offeringId);
  const category = (training: Training) => training.categoryCode ?? offeringOf(training)?.categoryCode ?? '';
  const title = (training: Training) => { const offer = offeringOf(training); return offer ? offeringLabel(offer, data?.offerings ?? []) : `Permis ${category(training)}`; };
  const current = listedCurrent ?? selectedLearner.data ?? null;
  const currentReady = listedCurrent ? loaded.status === 'ready' : selectedLearner.status === 'ready';
  const canWrite = school.status === 'ACTIVE' && currentReady && resources.status === 'ready' && !resources.data?.truncated
    && selectedTrainings.status === 'ready' && !selectedTrainings.data?.truncated && !runner.pending && !runner.busy;
  const canEdit = canWrite && !current?.archivedAt;
  const availableOfferings = availableTrainingOfferings(offerings, data?.offerings ?? [], current ? trainingsOf(current.id) : []);
  const canReviewPermit = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR');
  const canArchive = membership.roles.includes('ADMIN');

  function ask(next: LearnerDialog) { runner.clearOutcome(); setReason(''); setPermit(emptyPermit()); setAcknowledged(false); setDialog(next); }
  async function openTraining() {
    if (!canEdit || !current || !availableOfferings.some(offering => offering.id === offeringId) || !isCivilDate(startedOn)) return;
    await runner.run(createCommand({ schoolId, kind: 'createTraining', path: 'trainings', resourceVersion: 0,
      body: { learnerId: current.id, offeringId, startedOn } }), 'La formation est ouverte.');
  }
  async function assign(training: Training) {
    const instructorMembershipId = instructorFor[training.id];
    if (!canEdit || training.status !== 'ACTIVE' || dossier.status !== 'ready' || !dossier.data?.[training.id] || !instructors.some(member => member.id === instructorMembershipId)
      || dossier.data[training.id]!.assignments.some(assignment => assignment.instructorMembershipId === instructorMembershipId && assignmentIsOpen(assignment))) return;
    await runner.run(createCommand({ schoolId, kind: 'createAssignment', path: `trainings/${training.id}/assignments`, resourceVersion: 0,
      body: { instructorMembershipId, validFrom: new Date().toISOString(), validUntil: null } }), 'Le moniteur est affecté.');
  }
  const permitError = dialog?.kind === 'permit' ? permitProblem(permit, schoolToday()) : null;
  const transitionError = dialog?.kind === 'transition' ? transitionProblem(dialog.transition, reason) : null;
  const archiveError = (dialog?.kind === 'archive' || dialog?.kind === 'restore') && !filled(reason, 1000) ? 'Indiquez le motif (1 000 caractères au plus).' : null;
  async function confirm() {
    if (!dialog || !current || !canWrite) return;
    if (dialog.kind !== 'restore' && !canEdit) return;
    if ((dialog.kind === 'archive' || dialog.kind === 'restore') && !canArchive) return;
    if (dialog.kind === 'permit' && !canReviewPermit) return;
    if ((dialog.kind === 'archive' || dialog.kind === 'transition' && dialog.transition.danger) && !acknowledged) return;
    let result: SubmitResult | undefined;
    if (dialog.kind === 'transition' && !transitionError) {
      const { training, transition } = dialog;
      result = await runner.run(createCommand({ schoolId, kind: 'transitionTraining', path: `trainings/${training.id}/transition`, ifMatch: training.version,
        resourceId: training.id, resourceVersion: training.version,
        body: { targetStatus: transition.target, reason: reason.trim() } }),
      transition.target === 'CANCELLED' ? 'La formation est annulée.' : transition.target === 'COMPLETED' ? 'La formation est terminée.' : transition.target === 'PAUSED' ? 'La formation est en pause.' : 'La formation reprend.');
    } else if (dialog.kind === 'end') {
      const { training, assignment } = dialog;
      result = await runner.run(createCommand({ schoolId, kind: 'endAssignment', path: `trainings/${training.id}/assignments/${assignment.id}/end`, ifMatch: assignment.version,
        resourceId: assignment.id, resourceVersion: assignment.version, body: {} }), 'L’affectation est terminée.');
    } else if (dialog.kind === 'permit' && !permitError) {
      const { training } = dialog;
      result = await runner.run(createCommand({ schoolId, kind: 'recordPermitCheck', path: `trainings/${training.id}/permit-checks`, ifMatch: training.version,
        resourceVersion: 0, body: permitBody(permit, category(training)) }), permit.decision === 'APPROVED' ? 'Le permis est consigné.' : 'Le refus est consigné.');
    } else if (dialog.kind === 'archive' && !archiveError) {
      result = await runner.run(createCommand({ schoolId, kind: 'archiveLearner', path: `learners/${current.id}/archive`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: reason.trim() } }), 'Le dossier est archivé.');
      if (result.status === 'confirmed') { releaseChanges(); setSelected(null); }
    } else if (dialog.kind === 'restore' && !archiveError && membership.roles.includes('ADMIN')) {
      result = await runner.run(createCommand({ schoolId, kind: 'restoreLearner', path: `learners/${current.id}/restore`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: reason.trim() } }), 'Le dossier est restauré.');
      if (result.status === 'confirmed') setStatusFilter('active');
    }
    if (result && result.status !== 'rejected') setDialog(null);
  }

  return { schoolId, school, membership, navigate, routeQuery, selected, setSelected,
    search, setSearch, statusFilter, setStatusFilter, readinessFilter, setReadinessFilter,
    sort, setSort, currentPage, setPage, pageSize, pageRows, visible, filterContext,
    loaded, listTrainings, resources, selectedLearner, selectedTrainings, dossier,
    current, currentReady, canWrite, canEdit, canReviewPermit, canArchive, notReady,
    offerings, availableOfferings, instructors, competencies, name, trainingsOf, category, title,
    offeringId, setOfferingId, startedOn, setStartedOn, instructorFor, setInstructorFor,
    runner, ask, dialog, reason, setReason, permit, setPermit, acknowledged, setAcknowledged,
    permitError, transitionError, archiveError, openTraining, assign, confirm };
}
export type LearnerController = ReturnType<typeof useLearnerController>;
