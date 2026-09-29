import { useMemo, useState } from 'react';
import { civilDateIn } from '../agenda-model';
import {
  createCommand, filled, isCivilDate, matchesSearch, latestPermit, permitBody, permitProblem, transitionProblem, trainingTransitions,
  type PermitDraft, type TrainingTransition,
} from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { activeInstructors, offeringLabel, openOfferings } from '../invitation-model';
import {
  assignmentSchema, curriculumSchema, learnerSchema, memberSchema, offeringSchema, permitSchema, readAll, trainingSchema,
  type Assignment, type Learner, type Permit, type Training,
} from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatCivilDate } from '../ui';
import { readError, useCommandRunner, useConsole, useLoad } from './context';
import { permitSummary, TrainingFollowUp } from './dossier';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';

const statusLabels: Record<Training['status'], string> = { ACTIVE: 'En cours', PAUSED: 'En pause', COMPLETED: 'Terminée', CANCELLED: 'Annulée' };
const emptyPermit = (): PermitDraft => ({ physicalSeen: false, validUntil: '', decision: 'APPROVED', reason: '' });

type Dialog =
  | { kind: 'transition'; training: Training; transition: TrainingTransition }
  | { kind: 'end'; training: Training; assignment: Assignment }
  | { kind: 'permit'; training: Training }
  | { kind: 'archive' }
  | null;
type Dossier = { assignments: Assignment[]; permits: Permit[] | null };

/** Élèves : dossier, formations, moniteurs, permis et suivi. Les leçons se planifient dans l'app. */
export function LearnersSection() {
  const { schoolId, school, membership } = useConsole();
  const { revision } = useCommandSnapshot();
  const [selected, setSelected] = useState<string | null>(null);
  const [search, setSearch] = useState('');
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
  const loaded = useLoad(async () => {
    const [learners, trainings, offerings, members, curricula] = await Promise.all([
      readAll(schoolId, 'learners', learnerSchema), readAll(schoolId, 'trainings', trainingSchema),
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'curricula', curriculumSchema)]);
    return { learners: learners.items, trainings: trainings.items, offerings: offerings.items, members: members.items, curricula: curricula.items,
      truncated: learners.truncated || trainings.truncated };
  }, [schoolId, revision]);
  const dossier = useLoad(async (): Promise<Record<string, Dossier>> => {
    const trainings = (loaded.data?.trainings ?? []).filter(training => training.learnerId === selected);
    const entries = await Promise.all(trainings.map(async training => {
      const [assignments, permits] = await Promise.all([readAll(schoolId, `trainings/${training.id}/assignments`, assignmentSchema),
        // Sans droit de lecture, l'API répond 404 : le permis reste simplement absent de l'écran.
        readAll(schoolId, `trainings/${training.id}/permit-checks`, permitSchema).then(list => list.items, () => null)]);
      return [training.id, { assignments: assignments.items, permits }] as const;
    }));
    return Object.fromEntries(entries);
  }, [schoolId, selected, loaded.data]);

  const data = loaded.data;
  const learners = useMemo(() => [...(data?.learners ?? [])].filter(learner => !learner.archivedAt)
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [data]);
  const visible = learners.filter(learner => matchesSearch([learner.displayName, learner.contactEmail], search));
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
  const canWrite = !runner.pending && !runner.busy;
  const canReviewPermit = membership.grants.includes('permit_review');
  const canArchive = membership.grants.includes('MANAGE_LEARNER_ARCHIVES');
  const notReady = (learner: Learner) => learner.profileReadiness === 'MINIMAL' || learner.profileReadiness === 'ACTION_REQUIRED';

  function ask(next: Dialog) { runner.clearOutcome(); setReason(''); setPermit(emptyPermit()); setAcknowledged(false); setDialog(next); }
  async function openTraining() {
    if (!current || !offeringId || !isCivilDate(startedOn)) return;
    await runner.run(createCommand({ schoolId, kind: 'createTraining', path: 'trainings', resourceVersion: 0,
      body: { learnerId: current.id, offeringId, startedOn } }), 'La formation est ouverte.');
  }
  async function assign(training: Training) {
    const instructorMembershipId = instructorFor[training.id];
    if (!instructorMembershipId) return;
    await runner.run(createCommand({ schoolId, kind: 'createAssignment', path: `trainings/${training.id}/assignments`, resourceVersion: 0,
      body: { instructorMembershipId, validFrom: new Date().toISOString(), validUntil: null } }), 'Le moniteur est affecté.');
  }
  const permitError = dialog?.kind === 'permit' ? permitProblem(permit, schoolToday()) : null;
  const transitionError = dialog?.kind === 'transition' ? transitionProblem(dialog.transition, reason) : null;
  const archiveError = dialog?.kind === 'archive' && !filled(reason, 1000) ? 'Indiquez le motif de l’archivage.' : null;
  async function confirm() {
    if (!dialog || !current) return;
    if (dialog.kind === 'transition' && !transitionError) {
      const { training, transition } = dialog;
      await runner.run(createCommand({ schoolId, kind: 'transitionTraining', path: `trainings/${training.id}/transition`, ifMatch: training.version,
        resourceId: training.id, resourceVersion: training.version,
        body: { targetStatus: transition.target, ...(reason.trim() ? { reason: reason.trim() } : {}) } }),
      transition.target === 'CANCELLED' ? 'La formation est annulée.' : transition.target === 'COMPLETED' ? 'La formation est terminée.' : transition.target === 'PAUSED' ? 'La formation est en pause.' : 'La formation reprend.');
    } else if (dialog.kind === 'end') {
      const { training, assignment } = dialog;
      await runner.run(createCommand({ schoolId, kind: 'endAssignment', path: `trainings/${training.id}/assignments/${assignment.id}/end`, ifMatch: assignment.version,
        resourceId: assignment.id, resourceVersion: assignment.version, body: {} }), 'L’affectation est terminée.');
    } else if (dialog.kind === 'permit' && !permitError) {
      const { training } = dialog;
      await runner.run(createCommand({ schoolId, kind: 'recordPermitCheck', path: `trainings/${training.id}/permit-checks`, ifMatch: training.version,
        resourceVersion: 0, body: permitBody(permit, category(training)) }), permit.decision === 'APPROVED' ? 'Le permis est consigné.' : 'Le refus est consigné.');
    } else if (dialog.kind === 'archive' && !archiveError) {
      const result = await runner.run(createCommand({ schoolId, kind: 'archiveLearner', path: `learners/${current.id}/archive`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: reason.trim() } }), 'Le dossier est archivé.');
      if (result.status === 'confirmed') setSelected(null);
    }
    setDialog(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Personnes" title="Élèves" />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des élèves…">{value => <SplitView
        list={<>
          {value.truncated && <Notice tone="warning" title="Liste partielle" live={false}><p>L’école compte plus d’élèves que cette page n’en charge : la recherche ne porte que sur ceux affichés.</p></Notice>}
          <div className="list-toolbar"><TextField label="Rechercher un élève" value={search} onChange={setSearch} placeholder="Nom ou e-mail" /></div>
          {visible.length === 0 ? <EmptyState symbol="users" title={learners.length ? 'Aucun élève trouvé' : 'Aucun élève'} message={learners.length ? 'Modifiez la recherche.' : 'Créez un code pour inviter un élève.'} />
            : <table className="data-table">
              <caption className="visually-hidden">Élèves</caption>
              <thead><tr><th scope="col">Élève</th><th scope="col">Formation</th></tr></thead>
              <tbody>{visible.map(learner => <tr key={learner.id} className={learner.id === selected ? 'selected' : undefined}>
                <th scope="row"><RowButton selected={learner.id === selected} onSelect={() => { runner.clearOutcome(); setOfferingId(''); setSelected(learner.id); }}>{learner.displayName}</RowButton>
                  {notReady(learner) && <span className="caption block"><StatusBadge tone="warning" symbol="alert">Profil à compléter</StatusBadge></span>}</th>
                <td>{trainingsOf(learner.id).filter(training => training.status === 'ACTIVE').map(category).join(', ') || '—'}</td>
              </tr>)}</tbody>
            </table>}
        </>}
        detail={current ? <DetailPanel focusKey={current.id} title={current.displayName} meta={current.contactEmail ?? undefined}
          badge={notReady(current) ? <StatusBadge tone="warning" symbol="alert">Profil à compléter</StatusBadge> : undefined}
          actions={canArchive ? <button type="button" className="button quiet danger" disabled={!canWrite} onClick={() => ask({ kind: 'archive' })}>Archiver le dossier…</button> : undefined}>
          {dossier.status === 'error' && <Notice tone="error" title="Dossier incomplet" live={false}
            actions={<button type="button" className="button retry" onClick={dossier.reload}><Symbol kind="refresh" bare />Réessayer</button>}><p>{dossier.error ?? readError(null)}</p></Notice>}
          {trainingsOf(current.id).length === 0 && <p className="caption">Aucune formation.</p>}
          <ul className="row-list">{trainingsOf(current.id).map(training => {
            const detail = dossier.data?.[training.id];
            const assigned = (detail?.assignments ?? []).filter(item => !item.validUntil || Date.parse(item.validUntil) > Date.now());
            const inProgress = training.status === 'ACTIVE' || training.status === 'PAUSED';
            const permitInfo = permitSummary(detail?.permits ? latestPermit(detail.permits, category(training)) : undefined);
            return <li key={training.id}>
              <div className="row-text">
                <h3 className="row-title">{title(training)}</h3>
                <p className="row-meta">{assigned.length ? assigned.map(item => name(item.instructorMembershipId)).join(', ') : 'Aucun moniteur'}
                  {training.startedOn ? ` · depuis le ${formatCivilDate(training.startedOn)}` : ''}</p>
                {inProgress && detail?.permits && <p className="row-meta with-badge">{permitInfo.text}
                  {permitInfo.badge && <StatusBadge tone={permitInfo.badge.tone} symbol="alert">{permitInfo.badge.label}</StatusBadge>}</p>}
                {assigned.length > 0 && inProgress && <ul className="plain-list">{assigned.map(item => <li key={item.id}>
                  <span>{name(item.instructorMembershipId)}</span>
                  <button type="button" className="button quiet danger" disabled={!canWrite} aria-label={`Retirer ${name(item.instructorMembershipId)} de la formation ${title(training)}`}
                    onClick={() => ask({ kind: 'end', training, assignment: item })}>Retirer</button>
                </li>)}</ul>}
                {training.status === 'ACTIVE' && <div className="form-row">
                  <SelectField label="Moniteur" value={instructorFor[training.id] ?? ''} disabled={!canWrite} placeholder="Choisir"
                    onChange={value => setInstructorFor(map => ({ ...map, [training.id]: value }))}
                    options={instructors.filter(member => !assigned.some(item => item.instructorMembershipId === member.id)).map(member => ({ value: member.id, label: member.displayName }))} />
                  <button type="button" className="button secondary" disabled={!canWrite || !instructorFor[training.id]} onClick={() => void assign(training)}>Affecter</button>
                </div>}
                {inProgress && <div className="button-row compact">
                  {canReviewPermit && <button type="button" className="button secondary" disabled={!canWrite} onClick={() => ask({ kind: 'permit', training })}>Consigner le permis</button>}
                  {trainingTransitions(training.status).map(transition => <button key={transition.target} type="button" className={transition.danger ? 'button quiet danger' : 'button quiet'}
                    disabled={!canWrite} aria-label={`${transition.label} : ${title(training)}`} onClick={() => ask({ kind: 'transition', training, transition })}>{transition.label}{transition.danger ? '…' : ''}</button>)}
                </div>}
                <TrainingFollowUp schoolId={schoolId} training={training} competencies={competencies} timeZone={school.timeZone} />
              </div>
              {training.status !== 'ACTIVE' && <StatusBadge tone="neutral" symbol="dot">{statusLabels[training.status]}</StatusBadge>}
            </li>;
          })}</ul>
          <form className="form-grid" onSubmit={event => { event.preventDefault(); void openTraining(); }}>
            <div className="form-row">
              <SelectField label="Nouvelle formation" value={offeringId} disabled={!canWrite} placeholder="Choisir une offre" onChange={setOfferingId}
                options={offerings.map(item => ({ value: item.id, label: offeringLabel(item, offerings) }))} />
              <TextField label="Début" type="date" value={startedOn} disabled={!canWrite} onChange={setStartedOn} />
            </div>
            <button type="submit" className="button primary" disabled={!canWrite || !offeringId || !isCivilDate(startedOn)}>Ouvrir la formation</button>
          </form>
        </DetailPanel> : <Placeholder>Choisissez un élève.</Placeholder>} />}
      </LoadState>
      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog?.kind === 'transition' ? dialog.transition.label : dialog?.kind === 'end' ? 'Retirer le moniteur' : dialog?.kind === 'permit' ? 'Consigner le permis' : 'Archiver le dossier'}
        confirmLabel={dialog?.kind === 'transition' ? dialog.transition.label : dialog?.kind === 'end' ? 'Retirer' : dialog?.kind === 'permit' ? 'Consigner' : 'Archiver'}
        disabledReason={permitError ?? transitionError ?? archiveError}
        {...(dialog?.kind === 'archive' || (dialog?.kind === 'transition' && dialog.transition.danger)
          ? { acknowledgement: dialog.kind === 'archive' ? 'Je confirme l’archivage de ce dossier.' : 'Je confirme l’annulation de cette formation.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
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
        {dialog?.kind === 'archive' && current && <>
          <p className="dialog-lead">{current.displayName}</p>
          <TextArea label="Motif" rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={runner.busy} />
        </>}
      </ConfirmDialog>
    </div>
  );
}
