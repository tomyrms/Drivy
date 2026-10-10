import { useEffect, useMemo, useState } from 'react';
import { civilDateIn } from '../agenda-model';
import {
  assignmentIsOpen, availableTrainingOfferings, createCommand, filled, isCivilDate, matchesSearch, latestPermit, permitBody, permitProblem, transitionProblem, trainingTransitions,
  type PermitDraft, type TrainingTransition,
} from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import { activeInstructors, offeringLabel, openOfferings } from '../invitation-model';
import {
  assignmentSchema, curriculumSchema, learnerSchema, memberSchema, offeringSchema, permitSchema, readAll, trainingSchema,
  type Assignment, type Learner, type Permit, type Training,
} from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Loading, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatCivilDate } from '../ui';
import { readError, useCommandRunner, useConsole, useLoad, useRouteSelection } from './context';
import { DirectoryRow } from './directory';
import { permitSummary, TrainingFollowUp } from './dossier';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, ReadRetry, SectionHeading, SplitView } from './layout';

const statusLabels: Record<Training['status'], string> = { ACTIVE: 'En cours', PAUSED: 'En pause', COMPLETED: 'Terminée', CANCELLED: 'Annulée' };
const emptyPermit = (): PermitDraft => ({ physicalSeen: false, validUntil: '', decision: 'APPROVED', reason: '' });

type Dialog =
  | { kind: 'transition'; training: Training; transition: TrainingTransition }
  | { kind: 'end'; training: Training; assignment: Assignment }
  | { kind: 'permit'; training: Training }
  | { kind: 'archive' }
  | { kind: 'restore' }
  | null;
type Dossier = { assignments: Assignment[]; permits: Permit[] | null; permitError: string | null };

/** Élèves : dossier, formations, moniteurs, permis et suivi. Les leçons se planifient dans l'app. */
export function LearnersSection() {
  const { schoolId, school, membership, navigate, routeQuery } = useConsole();
  const { revision } = useCommandSnapshot();
  const [selected, setSelected] = useRouteSelection();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<'active' | 'archived' | 'all'>('active');
  const [offeringId, setOfferingId] = useState('');
  const schoolToday = () => civilDateIn(school.timeZone);
  const [startedOn, setStartedOn] = useState(schoolToday);
  const [instructorFor, setInstructorFor] = useState<Record<string, string>>({});
  const [dialog, setDialog] = useState<Dialog>(null);
  const [reason, setReason] = useState('');
  const [permit, setPermit] = useState<PermitDraft>(emptyPermit());
  const [acknowledged, setAcknowledged] = useState(false);
  // Une fois l'école a confirmé, les choix saisis ne doivent pas rester : sinon le moniteur affecté disparaît de la liste tout en restant « choisi ».
  const runner = useCommandRunner(() => { setOfferingId(''); setStartedOn(schoolToday()); setInstructorFor({}); setDialog(null); setReason(''); setPermit(emptyPermit()); });
  useEffect(() => { setDialog(null); setReason(''); setPermit(emptyPermit()); setOfferingId(''); }, [selected]);
  const loaded = useLoad(async () => {
    const [learners, trainings, offerings, members, curricula] = await Promise.all([
      readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }), readAll(schoolId, 'trainings', trainingSchema),
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'curricula', curriculumSchema)]);
    return { learners: learners.items, trainings: trainings.items, offerings: offerings.items, members: members.items, curricula: curricula.items,
      truncated: learners.truncated || trainings.truncated };
  }, [schoolId, revision]);
  const dossier = useLoad(async (): Promise<Record<string, Dossier>> => {
    const trainings = (loaded.data?.trainings ?? []).filter(training => training.learnerId === selected);
    const entries = await Promise.all(trainings.map(async training => {
      const [assignments, permitResult] = await Promise.all([readAll(schoolId, `trainings/${training.id}/assignments`, assignmentSchema),
        readAll(schoolId, `trainings/${training.id}/permit-checks`, permitSchema)
          .then(list => ({ items: list.items, error: null }), error => ({ items: null, error: readError(error) }))]);
      return [training.id, { assignments: assignments.items, permits: permitResult.items, permitError: permitResult.error }] as const;
    }));
    return Object.fromEntries(entries);
  }, [schoolId, selected, loaded.data], `${schoolId}/${selected ?? ''}`);

  const data = loaded.data;
  const learners = useMemo(() => [...(data?.learners ?? [])]
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [data]);
  const visible = learners.filter(learner => (statusFilter === 'all' || (statusFilter === 'archived') === !!learner.archivedAt)
    && matchesSearch([learner.displayName, learner.contactEmail], search));
  // Seule la dernière version active de chaque offre ouvre une formation (règle partagée avec les invitations par code).
  const offerings = useMemo(() => openOfferings(data?.offerings ?? []), [data]);
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const competencies = useMemo(() => new Map((data?.curricula ?? []).flatMap(curriculum => curriculum.competencies.map(item => [item.id, item.label] as const))), [data]);
  const name = (membershipId: string) => data?.members.find(member => member.id === membershipId)?.displayName ?? 'Moniteur';
  const trainingsOf = (learnerId: string) => (data?.trainings ?? []).filter(training => training.learnerId === learnerId);
  const offeringOf = (training: Training) => data?.offerings.find(item => item.id === training.offeringId);
  const category = (training: Training) => training.categoryCode ?? offeringOf(training)?.categoryCode ?? '';
  const title = (training: Training) => { const offer = offeringOf(training); return offer ? offeringLabel(offer, data?.offerings ?? []) : `Permis ${category(training)}`; };
  const current = learners.find(learner => learner.id === selected) ?? null;
  const canWrite = school.status === 'ACTIVE' && loaded.status === 'ready' && !runner.pending && !runner.busy;
  const canEdit = canWrite && !current?.archivedAt;
  const availableOfferings = availableTrainingOfferings(offerings, data?.offerings ?? [], current ? trainingsOf(current.id) : []);
  const canReviewPermit = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR');
  const canArchive = membership.roles.includes('ADMIN');
  const notReady = (learner: Learner) => learner.profileReadiness === 'MINIMAL' || learner.profileReadiness === 'ACTION_REQUIRED';

  function ask(next: Dialog) { runner.clearOutcome(); setReason(''); setPermit(emptyPermit()); setAcknowledged(false); setDialog(next); }
  async function openTraining() {
    if (!canEdit || !current || !availableOfferings.some(offering => offering.id === offeringId) || !isCivilDate(startedOn)) return;
    await runner.run(createCommand({ schoolId, kind: 'createTraining', path: 'trainings', resourceVersion: 0,
      body: { learnerId: current.id, offeringId, startedOn } }), 'La formation est ouverte.');
  }
  async function assign(training: Training) {
    const instructorMembershipId = instructorFor[training.id];
    if (!canEdit || dossier.status !== 'ready' || !dossier.data?.[training.id] || !instructorMembershipId) return;
    await runner.run(createCommand({ schoolId, kind: 'createAssignment', path: `trainings/${training.id}/assignments`, resourceVersion: 0,
      body: { instructorMembershipId, validFrom: new Date().toISOString(), validUntil: null } }), 'Le moniteur est affecté.');
  }
  const permitError = dialog?.kind === 'permit' ? permitProblem(permit, schoolToday()) : null;
  const transitionError = dialog?.kind === 'transition' ? transitionProblem(dialog.transition, reason) : null;
  const archiveError = (dialog?.kind === 'archive' || dialog?.kind === 'restore') && !filled(reason, 1000) ? 'Indiquez le motif (1 000 caractères au plus).' : null;
  async function confirm() {
    if (!dialog || !current || !canWrite) return;
    if (dialog.kind !== 'restore' && !canEdit) return;
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
      if (result.status === 'confirmed') setSelected(null);
    } else if (dialog.kind === 'restore' && !archiveError && membership.roles.includes('ADMIN')) {
      result = await runner.run(createCommand({ schoolId, kind: 'restoreLearner', path: `learners/${current.id}/restore`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: reason.trim() } }), 'Le dossier est restauré.');
      if (result.status === 'confirmed') setStatusFilter('active');
    }
    if (result && result.status !== 'rejected') setDialog(null);
  }

  return (
    <div className="section-stack">
      {routeQuery?.from === 'agenda' && <div className="button-row"><button type="button" className="button quiet" onClick={() => navigate('agenda', { week: routeQuery.week, instructor: routeQuery.instructor })}><Symbol kind="back" bare />Retour à l’agenda</button></div>}
      <SectionHeading title="Élèves" actions={!selected && <button type="button" className="button primary" onClick={() => navigate('invitations', { audience: 'learners' })}><Symbol kind="plus" bare />Inviter un élève</button>} />
      {!dialog && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des élèves…">{value => <SplitView mobileDetail={!!selected} onBack={() => setSelected(null)} backLabel="Tous les élèves"
        list={<>
          {value.truncated && <Notice tone="warning" title="Liste partielle" live={false}><p>L’école compte plus d’élèves que cette page n’en charge : la recherche ne porte que sur ceux affichés.</p></Notice>}
          <div className="list-toolbar directory-toolbar">
            <TextField label="Rechercher un élève" value={search} onChange={setSearch} placeholder="Nom ou e-mail" />
            <SelectField label="Dossiers" value={statusFilter} onChange={setStatusFilter}
              options={[{ value: 'active', label: 'Actifs' }, { value: 'archived', label: 'Archivés' }, { value: 'all', label: 'Tous' }]} />
            {search && <button type="button" className="button quiet" onClick={() => setSearch('')}>Effacer la recherche</button>}
          </div>
          {visible.length === 0 ? <EmptyState symbol="users" title={learners.length ? 'Aucun élève trouvé' : 'Aucun élève'} message={learners.length ? '' : 'Créez un code pour inviter un élève.'} />
            : <ul className="directory-list" aria-label="Dossiers élèves">{visible.map(learner => {
              const categories = trainingsOf(learner.id).filter(training => training.status === 'ACTIVE').map(category).filter(Boolean);
              return <DirectoryRow key={learner.id} title={learner.displayName} selected={learner.id === selected}
                onSelect={() => { runner.clearOutcome(); setOfferingId(''); setSelected(learner.id); }}
                detail={learner.archivedAt ? <StatusBadge tone="neutral" symbol="file">Archivé</StatusBadge>
                  : categories.length ? `Permis ${[...new Set(categories)].join(', ')}` : <span className="row-meta">Sans formation en cours</span>}
                badge={notReady(learner) ? <StatusBadge tone="warning" symbol="alert">Profil à compléter</StatusBadge> : undefined} />;
            })}</ul>}
        </>}
        detail={current ? <DetailPanel focusKey={current.id} title={current.displayName} meta={current.contactEmail ?? undefined}
          badge={current.archivedAt ? <StatusBadge tone="neutral" symbol="file">Archivé</StatusBadge>
            : notReady(current) ? <StatusBadge tone="warning" symbol="alert">Profil à compléter</StatusBadge> : undefined}
          actions={current.archivedAt ? membership.roles.includes('ADMIN') && <button type="button" className="button secondary" disabled={!canWrite}
            onClick={() => ask({ kind: 'restore' })}>Restaurer le dossier</button>
            : canArchive ? <button type="button" className="button quiet danger" disabled={!canEdit} onClick={() => ask({ kind: 'archive' })}>Archiver le dossier…</button> : undefined}>
          <div className="detail-links"><button type="button" className="button quiet" onClick={() => navigate('trajets', { learner: current.id, from: 'eleves', week: routeQuery?.week, instructor: routeQuery?.instructor })}><Symbol kind="route" bare />Voir les trajets</button></div>
          {dossier.status === 'error' && <Notice tone="error" title="Dossier incomplet" live={false}
            actions={<ReadRetry loaded={dossier} />}><p>{dossier.error ?? readError(null)}</p></Notice>}
          {trainingsOf(current.id).length === 0 && <p className="caption">Aucune formation.</p>}
          {dossier.status === 'loading' && trainingsOf(current.id).length > 0 && <Loading label="Chargement des moniteurs et permis…" />}
          <ul className="row-list training-list">{trainingsOf(current.id).map(training => {
            const detail = dossier.data?.[training.id];
            const detailReady = dossier.status === 'ready' && detail !== undefined;
            const assigned = (detail?.assignments ?? []).filter(item => assignmentIsOpen(item));
            const inProgress = training.status === 'ACTIVE' || training.status === 'PAUSED';
            const permitInfo = permitSummary(detail?.permits ? latestPermit(detail.permits, category(training)) : undefined);
            return <li key={training.id}>
              <div className="row-text">
                <div className="training-summary"><h3 className="row-title">{title(training)}</h3>
                  {training.status !== 'ACTIVE' && <StatusBadge tone="neutral" symbol="dot">{statusLabels[training.status]}</StatusBadge>}
                </div>
                <p className="row-meta">{detailReady ? assigned.length ? assigned.map(item => name(item.instructorMembershipId)).join(', ') : 'Aucun moniteur' : 'Moniteurs à vérifier'}
                  {training.startedOn ? ` · depuis le ${formatCivilDate(training.startedOn)}` : ''}</p>
                {inProgress && detail?.permits && <p className="row-meta with-badge">{permitInfo.text}
                  {permitInfo.badge && <StatusBadge tone={permitInfo.badge.tone} symbol="alert">{permitInfo.badge.label}</StatusBadge>}</p>}
                {inProgress && detailReady && detail.permitError && <Notice tone="error" title="Permis non consultable" live={false}
                  actions={<button type="button" className="button retry" onClick={dossier.reload}>Réessayer</button>}><p>{detail.permitError}</p></Notice>}
                <TrainingFollowUp schoolId={schoolId} training={training} competencies={competencies} timeZone={school.timeZone} />
                <details className="disclosure"><summary>Gérer cette formation</summary>
                {assigned.length > 0 && inProgress && <ul className="plain-list">{assigned.map(item => <li key={item.id}>
                  <span>{name(item.instructorMembershipId)}</span>
                  <button type="button" className="button quiet danger" disabled={!canEdit || !detailReady} aria-label={`Retirer ${name(item.instructorMembershipId)} de la formation ${title(training)}`}
                    onClick={() => ask({ kind: 'end', training, assignment: item })}>Retirer</button>
                </li>)}</ul>}
                {training.status === 'ACTIVE' && !current.archivedAt && <div className="form-row">
                  <SelectField label="Moniteur" value={instructorFor[training.id] ?? ''} disabled={!canEdit || !detailReady} placeholder="Choisir"
                    onChange={value => setInstructorFor(map => ({ ...map, [training.id]: value }))}
                    options={instructors.filter(member => !assigned.some(item => item.instructorMembershipId === member.id)).map(member => ({ value: member.id, label: member.displayName }))} />
                  <button type="button" className="button secondary" disabled={!canEdit || !detailReady || !instructorFor[training.id]} onClick={() => void assign(training)}>Affecter</button>
                </div>}
                {!current.archivedAt && <div className="button-row compact">
                  {inProgress && canReviewPermit && <button type="button" className="button secondary" disabled={!canEdit || !detailReady || detail.permits === null} onClick={() => ask({ kind: 'permit', training })}>Consigner le permis</button>}
                  {trainingTransitions(training.status).map(transition => <button key={transition.target} type="button" className={transition.danger ? 'button quiet danger' : 'button quiet'}
                    disabled={!canEdit} aria-label={`${transition.label} : ${title(training)}`} onClick={() => ask({ kind: 'transition', training, transition })}>{transition.label}{transition.danger ? '…' : ''}</button>)}
                </div>}
                </details>
              </div>
            </li>;
          })}</ul>
          {!current.archivedAt && availableOfferings.length > 0 && <details className="disclosure"><summary>{trainingsOf(current.id).length ? 'Ouvrir une autre formation' : 'Ouvrir une formation'}</summary><form className="form-grid" onSubmit={event => { event.preventDefault(); void openTraining(); }}>
            <div className="form-row">
              <SelectField label="Nouvelle formation" value={offeringId} disabled={!canWrite} placeholder="Choisir une offre" onChange={setOfferingId}
                options={availableOfferings.map(item => ({ value: item.id, label: offeringLabel(item, offerings) }))} />
              <TextField label="Début" type="date" value={startedOn} disabled={!canWrite} onChange={setStartedOn} />
            </div>
            <button type="submit" className="button primary" disabled={!canWrite || !availableOfferings.some(offering => offering.id === offeringId) || !isCivilDate(startedOn)}>Ouvrir la formation</button>
          </form></details>}
        </DetailPanel> : <Placeholder>Choisissez un élève.</Placeholder>} />}
      </LoadState>
      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog?.kind === 'transition' ? dialog.transition.label : dialog?.kind === 'end' ? 'Retirer le moniteur' : dialog?.kind === 'permit' ? 'Consigner le permis' : dialog?.kind === 'restore' ? 'Restaurer le dossier' : 'Archiver le dossier'}
        confirmLabel={dialog?.kind === 'transition' ? dialog.transition.label : dialog?.kind === 'end' ? 'Retirer' : dialog?.kind === 'permit' ? 'Consigner' : dialog?.kind === 'restore' ? 'Restaurer' : 'Archiver'}
        disabledReason={runner.busy ? null : !canWrite ? 'Actualisez le dossier avant de confirmer.' : permitError ?? transitionError ?? archiveError}
        {...(dialog?.kind === 'archive' || (dialog?.kind === 'transition' && dialog.transition.danger)
          ? { acknowledgement: dialog.kind === 'archive' ? 'Je confirme l’archivage de ce dossier.' : 'Je confirme l’annulation de cette formation.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
        {dialog?.kind === 'transition' && <>
          <p className="dialog-lead">{title(dialog.training)}</p>
          <TextArea label="Motif" required={dialog.transition.reasonRequired} rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={runner.busy} />
        </>}
        {dialog?.kind === 'end' && <p className="dialog-lead">{name(dialog.assignment.instructorMembershipId)} · {title(dialog.training)}</p>}
        {dialog?.kind === 'permit' && <>
          <p className="dialog-lead">{title(dialog.training)} · catégorie {category(dialog.training)}</p>
          <SelectField label="Décision" value={permit.decision} disabled={runner.busy} onChange={decision => setPermit({ ...permit, decision })}
            options={[{ value: 'APPROVED', label: 'Permis valable' }, { value: 'REJECTED', label: 'Permis refusé' }]} />
          {permit.decision === 'APPROVED' && <>
            <CheckField label="J’ai vu l’original du permis" checked={permit.physicalSeen} disabled={runner.busy} onChange={physicalSeen => setPermit({ ...permit, physicalSeen })} />
            <TextField label="Valable jusqu’au" type="date" required={false} value={permit.validUntil} disabled={runner.busy} onChange={validUntil => setPermit({ ...permit, validUntil })} />
          </>}
          <TextArea label="Motif" required={permit.decision === 'REJECTED'} rows={2} maxLength={2000} value={permit.reason} onChange={value => setPermit({ ...permit, reason: value })} disabled={runner.busy} />
        </>}
        {(dialog?.kind === 'archive' || dialog?.kind === 'restore') && current && <>
          <p className="dialog-lead">{current.displayName}</p>
          <TextArea label="Motif" rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={runner.busy} />
        </>}
      </ConfirmDialog>
    </div>
  );
}
