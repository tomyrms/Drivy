import { useEffect, useMemo, useRef, useState } from 'react';
import { civilDateIn } from '../agenda-model';
import { overlappingHours } from '../availability-model';
import { createCommand, isCivilDate, schoolTimeToInstant } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { availabilitySchema, closureSchema, memberSchema, readAll, type Availability, type Closure } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Notice, SelectField, Symbol, TextArea, TextField, formatCivilDate, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { distinctLabel, homonymReferences } from '../person-reference';
import './planning-workspace.css';

const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'] as const;
const removal = 'Retirée depuis la gestion web.';
function dayRange(weekdays: readonly number[]): string {
  const sorted = [...weekdays].sort((a, b) => a - b);
  const contiguous = sorted.every((day, index) => index === 0 || day === sorted[index - 1]! + 1);
  return contiguous && sorted.length > 2 ? `${days[sorted[0]! - 1]}–${days[sorted.at(-1)! - 1]}` : sorted.map(day => days[day - 1]).join(', ');
}
type Removal = { kind: 'rule'; value: Availability } | { kind: 'absence'; value: Closure };

/** All changes still go through versioned commands; a schedule never moves an existing appointment. */
export function AvailabilitySection({ section = 'availability' }: { section?: 'availability' | 'absences' } = {}) {
  const { schoolId, school, membership, routeQuery, setRouteQuery, navigate, confirmNavigation } = useConsole();
  const { revision } = useCommandSnapshot();
  const addition = useRef<'rule' | 'absence' | null>(null);
  const runner = useCommandRunner(() => {
    if (addition.current === 'rule') { setDirty(false); setRuleOpen(false); setEditing(null); setRuleSubmitted(false); }
    if (addition.current === 'absence') { setDirty(false); setAbsenceStart(''); setAbsenceEnd(''); setAbsenceReason(''); setAbsenceOpen(false); setAbsenceSubmitted(false); }
    addition.current = null; setRemoving(null);
  });
  const loaded = useLoad(async () => {
    const [members, rules, closures] = await Promise.all([readAll(schoolId, 'members', memberSchema),
      readAll(schoolId, 'availability-rules', availabilitySchema), readAll(schoolId, 'closures', closureSchema)]);
    return { members: members.items, rules: rules.items, closures: closures.items, truncated: members.truncated || rules.truncated || closures.truncated };
  }, [schoolId, revision]);
  const instructors = useMemo(() => (loaded.data?.members ?? []).filter(member => member.status === 'ACTIVE' && member.roles.includes('INSTRUCTOR'))
    .sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [loaded.data]);
  const references = useMemo(() => homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName }))), [instructors]);
  const [localChosen, setLocalChosen] = useState('');
  const chosen = routeQuery ? routeQuery.instructor ?? '' : localChosen;
  const instructor = instructors.some(item => item.id === chosen) ? chosen
    : instructors.some(item => item.id === membership.membershipId) ? membership.membershipId : instructors[0]?.id ?? '';
  const [weekdays, setWeekdays] = useState<number[]>([1, 2, 3, 4, 5]);
  const [start, setStart] = useState('08:00'), [end, setEnd] = useState('18:00');
  const [from, setFrom] = useState(() => civilDateIn(school.timeZone)), [until, setUntil] = useState('');
  const [absenceStart, setAbsenceStart] = useState(''), [absenceEnd, setAbsenceEnd] = useState(''), [absenceReason, setAbsenceReason] = useState('');
  const [ruleOpen, setRuleOpen] = useState(false), [absenceOpen, setAbsenceOpen] = useState(false);
  const [ruleSubmitted, setRuleSubmitted] = useState(false), [absenceSubmitted, setAbsenceSubmitted] = useState(false);
  const [editing, setEditing] = useState<Availability | null>(null);
  const [dirty, setDirty] = useState(false), [discarding, setDiscarding] = useState(false);
  const [removing, setRemoving] = useState<Removal | null>(null);
  const releaseGuard = useUnsavedChanges(dirty);
  const reset = () => {
    setDirty(false); setRuleOpen(false); setAbsenceOpen(false); setEditing(null); setRemoving(null);
    setAbsenceStart(''); setAbsenceEnd(''); setAbsenceReason(''); setWeekdays([1, 2, 3, 4, 5]);
    setStart('08:00'); setEnd('18:00'); setFrom(civilDateIn(school.timeZone)); setUntil(''); setRuleSubmitted(false); setAbsenceSubmitted(false);
  };
  useEffect(reset, [instructor, school.timeZone, section]);
  const selectInstructor = (id: string) => {
    if (id === instructor) return;
    const proceed = () => { releaseGuard(); reset(); setLocalChosen(id); setRouteQuery?.({ ...routeQuery, instructor: id || undefined }, false, true); };
    if (confirmNavigation) confirmNavigation(proceed); else proceed();
  };
  const locked = runner.busy || Boolean(runner.pending);
  const canWrite = school.status === 'ACTIVE' && loaded.status === 'ready' && !loaded.data?.truncated && !locked && instructors.some(item => item.id === instructor);
  const rules = (loaded.data?.rules ?? []).filter(rule => rule.instructorMembershipId === instructor)
    .sort((a, b) => a.weekdays[0]! - b.weekdays[0]! || a.localStart.localeCompare(b.localStart));
  const absences = (loaded.data?.closures ?? []).filter(item => item.instructorMembershipId === instructor && Date.parse(item.endsAt) > Date.now())
    .sort((a, b) => a.startsAt.localeCompare(b.startsAt));
  const ruleValid = weekdays.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end) && end > start && isCivilDate(from) && (!until || isCivilDate(until) && until >= from);
  const overlap = ruleValid ? overlappingHours(rules.filter(rule => rule.id !== editing?.id), { weekdays, localStart: start, localEnd: end, validFrom: from, validUntil: until || null }) : null;
  const absenceFrom = absenceStart ? schoolTimeToInstant(absenceStart, school.timeZone) : null;
  const absenceUntil = absenceEnd ? schoolTimeToInstant(absenceEnd, school.timeZone) : null;
  const absenceValid = absenceFrom !== null && absenceUntil !== null && Date.parse(absenceUntil) > Date.parse(absenceFrom);
  const editRule = (rule: Availability) => {
    const proceed = () => { releaseGuard(); reset(); setEditing(rule); setWeekdays([...rule.weekdays]); setStart(rule.localStart); setEnd(rule.localEnd); setFrom(rule.validFrom); setUntil(rule.validUntil ?? ''); setRuleOpen(true); };
    if (confirmNavigation) confirmNavigation(proceed); else proceed();
  };
  const closeEditor = () => { if (dirty) setDiscarding(true); else reset(); };

  async function saveRule() {
    setRuleSubmitted(true);
    if (!ruleValid || overlap || !canWrite) return;
    addition.current = 'rule';
    const body = { instructorMembershipId: instructor, weekdays: [...weekdays].sort(), localStart: start, localEnd: end, validFrom: from, validUntil: until || null };
    const result = await runner.run(createCommand(editing
      ? { schoolId, kind: 'updateAvailabilityRule', path: `availability-rules/${editing.id}`, resourceId: editing.id, resourceVersion: editing.version, ifMatch: editing.version, body }
      : { schoolId, kind: 'createAvailabilityRule', path: 'availability-rules', resourceVersion: 0, body }), editing ? 'La disponibilité est modifiée.' : 'La disponibilité est ajoutée.');
    if (result.status === 'confirmed') { releaseGuard(); reset(); }
    if (result.status === 'rejected') addition.current = null;
  }
  async function addAbsence() {
    setAbsenceSubmitted(true);
    if (!absenceValid || !canWrite) return;
    addition.current = 'absence';
    const result = await runner.run(createCommand({ schoolId, kind: 'createClosure', path: 'closures', resourceVersion: 0,
      body: { instructorMembershipId: instructor, startsAt: absenceFrom, endsAt: absenceUntil, reason: absenceReason.trim() || null } }), 'L’absence est ajoutée.');
    if (result.status === 'confirmed') { releaseGuard(); reset(); }
    if (result.status === 'rejected') addition.current = null;
  }
  async function remove() {
    if (!removing || !canWrite) return;
    addition.current = null;
    const { value, kind } = removing;
    const result = await runner.run(createCommand({ schoolId, kind: kind === 'rule' ? 'removeAvailabilityRule' : 'removeClosure',
      path: `${kind === 'rule' ? 'availability-rules' : 'closures'}/${value.id}/remove`, resourceId: value.id, resourceVersion: value.version, ifMatch: value.version,
      body: { reason: removal } }), kind === 'rule' ? 'La disponibilité est retirée.' : 'L’absence est retirée.');
    if (result.status === 'confirmed' || result.status === 'pending') setRemoving(null);
  }

  return <div className="section-stack availability-workspace">
    <SectionHeading context="Planning" title={section === 'absences' ? 'Absences' : 'Disponibilités'} actions={routeQuery?.from === 'equipe'
      ? <button type="button" className="button quiet" onClick={() => navigate('equipe', { selection: routeQuery.instructor })}>Retour au membre</button> : undefined} />
    <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
    <LoadState loaded={loaded} label={section === 'absences' ? 'Lecture des absences…' : 'Lecture des disponibilités…'}>{() => instructors.length === 0
      ? <EmptyState symbol="users" title="Aucun moniteur" action={<button type="button" className="button secondary" onClick={() => navigate('equipe')}>Ouvrir l’équipe</button>} />
      : <>
        <div className="availability-toolbar">
          {instructors.length > 1 ? <SelectField label="Moniteur" value={instructor} onChange={selectInstructor} search appearance="filter" disabled={locked}
            options={instructors.map(member => ({ value: member.id, label: distinctLabel(member.displayName, references.get(member.id)) }))} />
            : <p className="row-title">{instructors.find(member => member.id === instructor)?.displayName ?? 'Moniteur indisponible'}</p>}
          <button type="button" className="button secondary" onClick={() => navigate('agenda', { instructor })}><Symbol kind="calendar" bare />Voir le planning</button>
        </div>
        {loaded.data?.truncated && <Notice tone="warning" title="Horaires partiellement chargés"><p>L’édition attend une lecture complète pour éviter de masquer un chevauchement.</p></Notice>}
        <div className="planning-tabs" role="group" aria-label="Horaires du moniteur">
          <button type="button" className="button quiet" aria-pressed={section === 'availability'} onClick={() => navigate('disponibilites', { ...routeQuery, instructor })}>Disponibilités</button>
          <button type="button" className="button quiet" aria-pressed={section === 'absences'} onClick={() => navigate('absences', { ...routeQuery, instructor })}>Absences</button>
        </div>
        {section === 'availability' && <section className="schedule-section" aria-labelledby="weekly-title">
          <div className="section-head"><h2 id="weekly-title" className="section-title">Horaires hebdomadaires</h2>
            {!ruleOpen && <button type="button" className="button primary" disabled={!canWrite} onClick={() => setRuleOpen(true)}><Symbol kind="plus" bare />Ajouter un horaire</button>}</div>
          {!ruleOpen && (rules.length === 0 ? <EmptyState symbol="clock" title="Aucun horaire de conduite" />
            : <ul className="schedule-list">{rules.map(rule => <li key={rule.id} className="schedule-card">
              <div className="schedule-card-main"><div className="schedule-days" aria-label={dayRange(rule.weekdays)}>{days.map((day, index) => <span key={day} data-active={rule.weekdays.includes(index + 1)} aria-hidden="true">{day}</span>)}</div>
                <h3 className="schedule-hours">{rule.localStart}<span aria-hidden="true"> – </span><span className="visually-hidden"> à </span>{rule.localEnd}</h3>
                <p className="row-meta">{formatCivilDate(rule.validFrom)}{rule.validUntil ? ` – ${formatCivilDate(rule.validUntil)}` : ' · Sans date de fin'}</p>
              </div>
              <div className="schedule-card-actions"><button type="button" className="button secondary" disabled={!canWrite} onClick={() => editRule(rule)}>Modifier</button>
                <button type="button" className="button quiet" disabled={!canWrite} aria-label={`Retirer l’horaire ${dayRange(rule.weekdays)}, ${rule.localStart}–${rule.localEnd}`} onClick={() => setRemoving({ kind: 'rule', value: rule })}>Retirer</button></div>
            </li>)}</ul>)}
          {ruleOpen && <form className="schedule-editor section-stack" onChangeCapture={() => setDirty(true)} onSubmit={event => { event.preventDefault(); void saveRule(); }}>
            <div className="section-head"><h3 className="section-title">{editing ? 'Modifier l’horaire' : 'Nouvel horaire'}</h3><button type="button" className="button quiet" disabled={locked} onClick={closeEditor}>Fermer</button></div>
            <fieldset className="fieldset" aria-describedby={ruleSubmitted && weekdays.length === 0 ? 'weekly-days-error' : undefined}><legend>Jours de conduite</legend>
              <div className="day-picker">{days.map((label, index) => <CheckField key={label} label={label} checked={weekdays.includes(index + 1)} disabled={!canWrite}
                onChange={checked => { setDirty(true); setWeekdays(current => checked ? [...current, index + 1] : current.filter(day => day !== index + 1)); }} />)}</div>
              {ruleSubmitted && weekdays.length === 0 && <p id="weekly-days-error" className="field-error" role="alert">Choisissez au moins un jour.</p>}
            </fieldset>
            <div className="planning-form-grid"><TextField label="Début" type="time" required value={start} disabled={!canWrite} onChange={setStart} />
              <TextField label="Fin" type="time" required value={end} disabled={!canWrite} onChange={setEnd} error={ruleSubmitted && end <= start ? 'Choisissez une fin après le début.' : null} />
              <TextField label="Valable dès le" type="date" required value={from} disabled={!canWrite} onChange={setFrom} />
              <TextField label="Date de fin (facultatif)" type="date" value={until} disabled={!canWrite} onChange={setUntil} error={ruleSubmitted && until && until < from ? 'Choisissez une fin après le début de validité.' : null} /></div>
            {ruleSubmitted && overlap && <Notice tone="error" title="Cet horaire chevauche un autre créneau"><p>{dayRange(overlap.weekdays)} · {overlap.localStart}–{overlap.localEnd}</p></Notice>}
            <div className="planning-form-actions"><button type="submit" className="button primary" disabled={!canWrite} aria-busy={runner.busy}>{editing ? 'Enregistrer l’horaire' : 'Ajouter l’horaire'}</button></div>
          </form>}
        </section>}
        {section === 'absences' && <section className="schedule-section" aria-labelledby="absence-title">
          <div className="section-head"><h2 id="absence-title" className="section-title">Absences prévues</h2>{!absenceOpen && <button type="button" className="button primary" disabled={!canWrite} onClick={() => setAbsenceOpen(true)}><Symbol kind="plus" bare />Ajouter une absence</button>}</div>
          {!absenceOpen && (absences.length === 0 ? <EmptyState symbol="calendar" title="Aucune absence prévue" />
            : <ul className="schedule-list">{absences.map(item => <li key={item.id} className="schedule-card"><div className="schedule-card-main">
              <h3 className="row-title"><time dateTime={item.startsAt}>{formatDateTime(item.startsAt, school.timeZone)}</time></h3>
              <p className="row-meta">Jusqu’au <time dateTime={item.endsAt}>{formatDateTime(item.endsAt, school.timeZone)}</time></p>{item.reason && <p className="schedule-reason">{item.reason}</p>}
              </div><button type="button" className="button quiet" disabled={!canWrite} aria-label={`Retirer l’absence du ${formatDateTime(item.startsAt, school.timeZone)}`} onClick={() => setRemoving({ kind: 'absence', value: item })}>Retirer</button></li>)}</ul>)}
          {absenceOpen && <form className="schedule-editor section-stack" onChangeCapture={() => setDirty(true)} onSubmit={event => { event.preventDefault(); void addAbsence(); }}>
            <div className="section-head"><h3 className="section-title">Nouvelle absence</h3><button type="button" className="button quiet" disabled={locked} onClick={closeEditor}>Fermer</button></div>
            <div className="planning-form-grid"><TextField label={`Du (${school.timeZone})`} type="datetime-local" required value={absenceStart} disabled={!canWrite} onChange={setAbsenceStart}
              error={absenceSubmitted && absenceStart && !absenceFrom ? 'Cette heure n’existe pas dans le fuseau de l’école.' : null} />
              <TextField label="Au" type="datetime-local" required value={absenceEnd} disabled={!canWrite} onChange={setAbsenceEnd}
                error={absenceSubmitted && absenceEnd && !absenceUntil ? 'Cette heure n’existe pas dans le fuseau de l’école.' : absenceSubmitted && absenceStart && absenceEnd && !absenceValid ? 'Choisissez une fin après le début.' : null} /></div>
            <TextArea label="Motif (facultatif)" maxLength={1000} value={absenceReason} disabled={!canWrite} onChange={setAbsenceReason} />
            <div className="planning-form-actions"><button type="submit" className="button primary" disabled={!canWrite} aria-busy={runner.busy}>Ajouter l’absence</button></div>
          </form>}
        </section>}
      </>}
    </LoadState>
    <ConfirmDialog open={removing !== null} title={removing?.kind === 'rule' ? 'Retirer cet horaire ?' : 'Retirer cette absence ?'} confirmLabel="Confirmer le retrait" busy={locked} disabledReason={runner.blockedReason} onCancel={() => setRemoving(null)} onConfirm={() => void remove()}>
      <p>{instructors.find(item => item.id === instructor)?.displayName}</p>
      {removing?.kind === 'rule' ? <><p>{dayRange(removing.value.weekdays)} · {removing.value.localStart}–{removing.value.localEnd}</p><p>Ce créneau ne sera plus proposé. Les rendez-vous confirmés ne seront pas déplacés.</p></>
        : removing && <><p>{formatDateTime(removing.value.startsAt, school.timeZone)} – {formatDateTime(removing.value.endsAt, school.timeZone)}</p><p>Le moniteur pourra de nouveau être proposé sur cette période selon ses horaires.</p></>}
      <OutcomeNotice outcome={runner.outcome} />
    </ConfirmDialog>
    <ConfirmDialog open={discarding} title="Quitter sans enregistrer ?" confirmLabel="Abandonner les modifications" busy={false} onCancel={() => setDiscarding(false)} onConfirm={() => { releaseGuard(); reset(); setDiscarding(false); }}><p>Les modifications de cet horaire seront perdues.</p></ConfirmDialog>
  </div>;
}
