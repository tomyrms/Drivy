import { useMemo, useState } from 'react';
import { createCommand, isCivilDate } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { assignmentSchema, learnerSchema, memberSchema, offeringSchema, readAll, trainingSchema, type Training } from '../school-api';
import { EmptyState, SelectField, StatusBadge, TextField, formatCivilDate } from '../ui';
import { useCommandRunner, useConsole, useLoad } from './context';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';

const statusLabels: Record<Training['status'], string> = { ACTIVE: 'En cours', PAUSED: 'En pause', COMPLETED: 'Terminée', CANCELLED: 'Annulée' };
const today = () => new Date().toLocaleDateString('sv-SE');

/** Élèves : ouvrir une formation et lui affecter un moniteur. Le reste du dossier vit dans l'app. */
export function LearnersSection() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const [selected, setSelected] = useState<string | null>(null);
  const [offeringId, setOfferingId] = useState('');
  const [startedOn, setStartedOn] = useState(today());
  const [instructorFor, setInstructorFor] = useState<Record<string, string>>({});
  const runner = useCommandRunner();
  const loaded = useLoad(async () => {
    const [learners, trainings, offerings, members] = await Promise.all([
      readAll(schoolId, 'learners', learnerSchema), readAll(schoolId, 'trainings', trainingSchema),
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema)]);
    return { learners: learners.items, trainings: trainings.items, offerings: offerings.items, members: members.items };
  }, [schoolId, revision]);
  const assignments = useLoad(async () => {
    const trainings = (loaded.data?.trainings ?? []).filter(training => training.learnerId === selected);
    const lists = await Promise.all(trainings.map(training => readAll(schoolId, `trainings/${training.id}/assignments`, assignmentSchema)));
    return lists.flatMap(list => list.items);
  }, [schoolId, selected, loaded.data]);

  const data = loaded.data;
  const learners = useMemo(() => [...(data?.learners ?? [])].filter(learner => !learner.archivedAt)
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [data]);
  // Seule la dernière version active de chaque offre ouvre une formation.
  const offerings = useMemo(() => {
    const latest = new Map<string, NonNullable<typeof data>['offerings'][number]>();
    for (const item of data?.offerings ?? []) if ((latest.get(item.offeringKey)?.version ?? 0) < item.version) latest.set(item.offeringKey, item);
    return [...latest.values()].filter(item => item.enabled);
  }, [data]);
  const instructors = useMemo(() => (data?.members ?? []).filter(member => member.status === 'ACTIVE' && member.roles.includes('INSTRUCTOR'))
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [data]);
  const name = (membershipId: string) => data?.members.find(member => member.id === membershipId)?.displayName ?? 'Moniteur';
  const trainingsOf = (learnerId: string) => (data?.trainings ?? []).filter(training => training.learnerId === learnerId);
  const category = (training: Training) => training.categoryCode ?? offerings.find(item => item.id === training.offeringId)?.categoryCode ?? '';
  const current = learners.find(learner => learner.id === selected) ?? null;
  const canWrite = !runner.pending && !runner.busy;

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

  return (
    <div className="section-stack">
      <SectionHeading context="Personnes" title="Élèves" />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      <LoadState loaded={loaded} label="Lecture des élèves…">{() => <SplitView
        list={learners.length === 0 ? <EmptyState symbol="users" title="Aucun élève" message="Invitez un élève pour ouvrir son dossier." />
          : <table className="data-table">
            <caption className="visually-hidden">Élèves</caption>
            <thead><tr><th scope="col">Élève</th><th scope="col">Formation</th></tr></thead>
            <tbody>{learners.map(learner => <tr key={learner.id} className={learner.id === selected ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={learner.id === selected} onSelect={() => { runner.clearOutcome(); setSelected(learner.id); }}>{learner.displayName}</RowButton></th>
              <td>{trainingsOf(learner.id).filter(training => training.status === 'ACTIVE').map(category).join(', ') || '—'}</td>
            </tr>)}</tbody>
          </table>}
        detail={current ? <DetailPanel focusKey={current.id} title={current.displayName} meta={current.contactEmail ?? undefined}>
          {trainingsOf(current.id).length === 0 && <p className="caption">Aucune formation.</p>}
          <ul className="row-list">{trainingsOf(current.id).map(training => {
            const assigned = (assignments.data ?? []).filter(item => item.trainingId === training.id && (!item.validUntil || Date.parse(item.validUntil) > Date.now()));
            return <li key={training.id}>
              <div className="row-text">
                <h3 className="row-title">Permis {category(training)}</h3>
                <p className="row-meta">{assigned.length ? assigned.map(item => name(item.instructorMembershipId)).join(', ') : 'Aucun moniteur'}
                  {training.startedOn ? ` · depuis le ${formatCivilDate(training.startedOn)}` : ''}</p>
                {training.status === 'ACTIVE' && <div className="form-row">
                  <SelectField label="Moniteur" value={instructorFor[training.id] ?? ''} disabled={!canWrite} placeholder="Choisir"
                    onChange={value => setInstructorFor(map => ({ ...map, [training.id]: value }))}
                    options={instructors.filter(member => !assigned.some(item => item.instructorMembershipId === member.id)).map(member => ({ value: member.id, label: member.displayName }))} />
                  <button type="button" className="button secondary" disabled={!canWrite || !instructorFor[training.id]} onClick={() => void assign(training)}>Affecter</button>
                </div>}
              </div>
              {training.status !== 'ACTIVE' && <StatusBadge tone="neutral" symbol="dot">{statusLabels[training.status]}</StatusBadge>}
            </li>;
          })}</ul>
          <form className="form-grid" onSubmit={event => { event.preventDefault(); void openTraining(); }}>
            <div className="form-row">
              <SelectField label="Nouvelle formation" value={offeringId} disabled={!canWrite} placeholder="Choisir une offre" onChange={setOfferingId}
                options={offerings.map(item => ({ value: item.id, label: `Permis ${item.categoryCode}` }))} />
              <TextField label="Début" type="date" value={startedOn} disabled={!canWrite} onChange={setStartedOn} />
            </div>
            <button type="submit" className="button primary" disabled={!canWrite || !offeringId || !isCivilDate(startedOn)}>Ouvrir la formation</button>
          </form>
        </DetailPanel> : <Placeholder>Choisissez un élève.</Placeholder>} />}
      </LoadState>
    </div>
  );
}
