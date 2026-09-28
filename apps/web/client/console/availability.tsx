import { useMemo, useState } from 'react';
import { createCommand, isCivilDate, schoolTimeToInstant } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { availabilitySchema, closureSchema, memberSchema, readAll, type Availability, type Closure } from '../school-api';
import { CheckField, EmptyState, SelectField, TextField, formatCivilDate, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';

const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'] as const;
const today = () => new Date().toLocaleDateString('sv-SE');
const removal = 'Retirée depuis la gestion web.';

function dayRange(weekdays: readonly number[]): string {
  const sorted = [...weekdays].sort((a, b) => a - b);
  const contiguous = sorted.every((day, index) => index === 0 || day === sorted[index - 1]! + 1);
  return contiguous && sorted.length > 2 ? `${days[sorted[0]! - 1]}–${days[sorted.at(-1)! - 1]}` : sorted.map(day => days[day - 1]).join(', ');
}

/** Disponibilités et absences des moniteurs : la planification dans l'app s'y appuie. */
export function AvailabilitySection() {
  const { schoolId, school, membership } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner();
  const loaded = useLoad(async () => {
    const [members, rules, closures] = await Promise.all([readAll(schoolId, 'members', memberSchema),
      readAll(schoolId, 'availability-rules', availabilitySchema), readAll(schoolId, 'closures', closureSchema)]);
    return { members: members.items, rules: rules.items, closures: closures.items };
  }, [schoolId, revision]);
  const instructors = useMemo(() => (loaded.data?.members ?? []).filter(member => member.status === 'ACTIVE' && member.roles.includes('INSTRUCTOR'))
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [loaded.data]);
  const [chosen, setChosen] = useState<string>('');
  const instructor = chosen || (instructors.some(item => item.id === membership.membershipId) ? membership.membershipId : instructors[0]?.id ?? '');
  const [weekdays, setWeekdays] = useState<number[]>([1, 2, 3, 4, 5]);
  const [start, setStart] = useState('08:00');
  const [end, setEnd] = useState('18:00');
  const [from, setFrom] = useState(today());
  const [absenceStart, setAbsenceStart] = useState('');
  const [absenceEnd, setAbsenceEnd] = useState('');
  const canWrite = !runner.pending && !runner.busy && instructor !== '';

  const rules = (loaded.data?.rules ?? []).filter(rule => rule.instructorMembershipId === instructor)
    .sort((a, b) => a.weekdays[0]! - b.weekdays[0]! || a.localStart.localeCompare(b.localStart));
  const absences = (loaded.data?.closures ?? []).filter(item => item.instructorMembershipId === instructor && Date.parse(item.endsAt) > Date.now())
    .sort((a, b) => a.startsAt.localeCompare(b.startsAt));
  const ruleValid = weekdays.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end) && end > start && isCivilDate(from);
  const absenceFrom = absenceStart ? schoolTimeToInstant(absenceStart, school.timeZone) : null;
  const absenceUntil = absenceEnd ? schoolTimeToInstant(absenceEnd, school.timeZone) : null;
  const absenceValid = absenceFrom !== null && absenceUntil !== null && Date.parse(absenceUntil) > Date.parse(absenceFrom);

  async function addRule() {
    if (!ruleValid || !canWrite) return;
    await runner.run(createCommand({ schoolId, kind: 'createAvailabilityRule', path: 'availability-rules', resourceVersion: 0,
      body: { instructorMembershipId: instructor, weekdays: [...weekdays].sort(), localStart: start, localEnd: end, validFrom: from, validUntil: null } }),
      'La disponibilité est ajoutée.');
  }
  async function removeRule(rule: Availability) {
    await runner.run(createCommand({ schoolId, kind: 'removeAvailabilityRule', path: `availability-rules/${rule.id}/remove`,
      resourceId: rule.id, resourceVersion: rule.version, ifMatch: rule.version, body: { reason: removal } }), 'La disponibilité est retirée.');
  }
  async function addAbsence() {
    if (!absenceValid || !canWrite) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'createClosure', path: 'closures', resourceVersion: 0,
      body: { instructorMembershipId: instructor, startsAt: absenceFrom, endsAt: absenceUntil, reason: null } }), 'L’absence est ajoutée.');
    if (result.status === 'confirmed') { setAbsenceStart(''); setAbsenceEnd(''); }
  }
  async function removeAbsence(closure: Closure) {
    await runner.run(createCommand({ schoolId, kind: 'removeClosure', path: `closures/${closure.id}/remove`,
      resourceId: closure.id, resourceVersion: closure.version, ifMatch: closure.version, body: { reason: removal } }), 'L’absence est retirée.');
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Planning" title="Disponibilités" />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      <LoadState loaded={loaded} label="Lecture des disponibilités…">{() => instructors.length === 0
        ? <EmptyState symbol="users" title="Aucun moniteur" message="Donnez le rôle Moniteur à un membre dans Équipe et accès." />
        : <>
          {instructors.length > 1 && <SelectField label="Moniteur" value={instructor} onChange={setChosen}
            options={instructors.map(member => ({ value: member.id, label: member.displayName }))} />}
          <section className="panel" aria-labelledby="weekly-title">
            <h2 id="weekly-title" className="section-title">Chaque semaine</h2>
            {rules.length === 0 ? <p className="caption">Aucune disponibilité : aucune leçon ne peut être planifiée.</p>
              : <ul className="row-list">{rules.map(rule => <li key={rule.id}>
                <div className="row-text">
                  <h3 className="row-title">{dayRange(rule.weekdays)} · {rule.localStart}–{rule.localEnd}</h3>
                  <p className="row-meta">Dès le {formatCivilDate(rule.validFrom)}{rule.validUntil ? ` jusqu’au ${formatCivilDate(rule.validUntil)}` : ''}</p>
                </div>
                <button type="button" className="button quiet" disabled={!canWrite} onClick={() => void removeRule(rule)}>Retirer</button>
              </li>)}</ul>}
            <form className="form-grid" onSubmit={event => { event.preventDefault(); void addRule(); }}>
              <fieldset className="fieldset">
                <legend>Jours</legend>
                <div className="day-picker">{days.map((label, index) => <CheckField key={label} label={label} checked={weekdays.includes(index + 1)} disabled={!canWrite}
                  onChange={checked => setWeekdays(current => checked ? [...current, index + 1] : current.filter(day => day !== index + 1))} />)}</div>
              </fieldset>
              <div className="form-row">
                <TextField label="De" type="time" value={start} disabled={!canWrite} onChange={setStart} />
                <TextField label="À" type="time" value={end} disabled={!canWrite} onChange={setEnd} error={end <= start ? 'La fin suit le début.' : null} />
                <TextField label="Dès le" type="date" value={from} disabled={!canWrite} onChange={setFrom} />
              </div>
              <button type="submit" className="button primary" disabled={!canWrite || !ruleValid}>Ajouter</button>
            </form>
          </section>
          <section className="panel" aria-labelledby="absence-title">
            <h2 id="absence-title" className="section-title">Absences</h2>
            {absences.length === 0 ? <p className="caption">Aucune absence prévue.</p>
              : <ul className="row-list">{absences.map(item => <li key={item.id}>
                <div className="row-text">
                  <h3 className="row-title">{formatDateTime(item.startsAt, school.timeZone)} → {formatDateTime(item.endsAt, school.timeZone)}</h3>
                  {item.reason && <p className="row-meta">{item.reason}</p>}
                </div>
                <button type="button" className="button quiet" disabled={!canWrite} onClick={() => void removeAbsence(item)}>Retirer</button>
              </li>)}</ul>}
            <form className="form-grid" onSubmit={event => { event.preventDefault(); void addAbsence(); }}>
              <div className="form-row">
                <TextField label="Du" type="datetime-local" value={absenceStart} disabled={!canWrite} onChange={setAbsenceStart} />
                <TextField label="Au" type="datetime-local" value={absenceEnd} disabled={!canWrite} onChange={setAbsenceEnd}
                  error={absenceStart && absenceEnd && !absenceValid ? 'La fin suit le début.' : null} />
              </div>
              <button type="submit" className="button secondary" disabled={!canWrite || !absenceValid}>Ajouter une absence</button>
            </form>
          </section>
        </>}
      </LoadState>
    </div>
  );
}
