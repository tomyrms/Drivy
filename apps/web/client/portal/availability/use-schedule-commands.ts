import { useMemo, useState } from 'react';
import { createCommand, type SchoolCommand } from '../../command-core';
import { refusalOutcome } from '../../command-lane';
import { useCommandSnapshot } from '../../command-store';
import type { Availability, Closure } from '../../school-api';
import { useCommandLane, type Outcome } from '../../console/context';
import { useJournal } from '../../console/session-journal';
import { absenceBody, REMOVAL_REASON, ruleBody, type AbsenceDraft, type RuleDraft } from './schedule-model';
import { projectAbsences, projectRules, visibleIntentions, type ScheduleIntention } from './schedule-projection';
import type { ScheduleState } from './use-schedule';

export type Removal = { kind: 'rule'; value: Availability } | { kind: 'absence'; value: Closure };
/** A request that had been kept and that the school refused: what was typed comes back with the refusal. */
export interface ScheduleRefusal { readonly intention: ScheduleIntention; readonly outcome: NonNullable<Outcome> }

/** Memory only, in the console's drafts: renewed with the account, school, membership and access epoch; never written to browser storage. */
const INTENTIONS_KEY = 'schedule/intentions';
const REFUSALS_KEY = 'schedule/refusals';
export const ruleTag = (ruleId: string | null) => `rule:${ruleId ?? 'new'}`;
export const ABSENCE_TAG = 'absence:new';
export const removalTag = (id: string) => `remove:${id}`;
const BLOCKED = 'Une demande sur ces horaires attend sa confirmation (voir en haut de la page).';

/**
 * Hours and absences go through the shared command engine, one intention at a time per instructor and per kind (hours, absences),
 * and independently of everything else: a slow save never blocks another instructor, an absence, or reading the agenda.
 * Once a request is kept the form is released and the row shows « À confirmer »; nothing is confirmed, freed or bookable before the
 * school's receipt. A refusal brings the form back with what was typed; a schedule change never moves an existing appointment
 * (the school refuses it: EXISTING_BOOKINGS).
 */
export function useScheduleCommands(state: ScheduleState) {
  const { schoolId, school } = state.context;
  const { entries } = useCommandSnapshot();
  const [removing, setRemoving] = useState<Removal | null>(null);
  const [removalOutcome, setRemovalOutcome] = useState<NonNullable<Outcome> | null>(null);
  // Intentions et refus partagent la durée de vie du journal de session : une réponse tardive y écrit même page quittée (#430).
  const [refusals, setRefusals] = useJournal<ScheduleRefusal>(REFUSALS_KEY);
  const [intentionList, change] = useJournal<ScheduleIntention>(INTENTIONS_KEY);
  const settle = (operationId: string) => change(list => list.map(item => item.operationId === operationId && item.settledAt === undefined ? { ...item, settledAt: Date.now() } : item));
  const lane = useCommandLane(intent => settle(intent.operationId));

  const followed = useMemo(() => new Set([...entries.values()].filter(entry => entry.meta.schoolId === schoolId).map(entry => entry.meta.operationId)), [entries, schoolId]);
  const intentions = useMemo(() => visibleIntentions(intentionList, followed, state.loaded.readAt), [intentionList, followed, state.loaded.readAt]);
  const rules = useMemo(() => projectRules(state.loaded.data?.rules ?? [], intentions, state.instructor), [state.loaded.data, intentions, state.instructor]);
  const absences = useMemo(() => {
    const projected = projectAbsences(state.loaded.data?.closures ?? [], intentions, state.instructor, school.timeZone);
    const now = state.now;
    return { ...projected, absences: projected.absences.filter(item => Date.parse(item.endsAt) > now).sort((a, b) => a.startsAt.localeCompare(b.startsAt)) };
  }, [state.loaded.data, intentions, state.instructor, school.timeZone, state.now]);

  // A request on the same instructor and the same kind (hours, absences) still followed makes the next one wait: the school orders them.
  const blockedRules = lane.blocked({ kind: 'createAvailabilityRule', scope: state.instructor });
  const blockedAbsences = lane.blocked({ kind: 'createClosure', scope: state.instructor });
  const blockedReason = (family: 'rules' | 'closures') => (family === 'rules' ? blockedRules : blockedAbsences) ? BLOCKED : null;

  /** Hands the request to the store. Refused locally: the form stays as it is. Kept: the form is released and the row says so. */
  function keep(command: SchoolCommand, success: string, intention: ScheduleIntention): 'kept' | 'refused' {
    lane.clearOutcome();
    const started = lane.run(command, success, intention.tag);
    if (!started.admitted) { void started.result; return 'refused'; }
    change(list => [...list.filter(item => item.settledAt === undefined ? followed.has(item.operationId) : (state.loaded.readAt ?? 0) < item.settledAt), intention]);
    state.setView(null); setRemoving(null); setRemovalOutcome(null);
    void started.result.then(result => {
      if (result.status !== 'rejected') return;
      change(list => list.filter(item => item.operationId !== intention.operationId));
      setRefusals(list => [...list, { intention, outcome: refusalOutcome(result) as NonNullable<Outcome> }]);
    });
    return 'kept';
  }

  const saveRule = (draft: RuleDraft, target: Availability | null): 'kept' | 'refused' => {
    if (!state.writable) return 'refused';
    const command = createCommand(target
      ? { schoolId, kind: 'updateAvailabilityRule', path: `availability-rules/${target.id}`, resourceId: target.id, resourceVersion: target.version, ifMatch: target.version,
        body: ruleBody(draft, state.instructor), scope: state.instructor }
      : { schoolId, kind: 'createAvailabilityRule', path: 'availability-rules', resourceVersion: 0, body: ruleBody(draft, state.instructor), scope: state.instructor });
    const base = { tag: ruleTag(target?.id ?? null), operationId: command.operationId, instructor: state.instructor, draft };
    return keep(command, target ? 'L’horaire est modifié.' : 'L’horaire est ajouté.',
      target ? { ...base, kind: 'rule-update', ruleId: target.id, base: target } : { ...base, kind: 'rule-create' });
  };

  const saveAbsence = (draft: AbsenceDraft): 'kept' | 'refused' | 'invalid' => {
    if (!state.writable) return 'refused';
    const body = absenceBody(draft, state.instructor, school.timeZone);
    if (!body) return 'invalid';
    const command = createCommand({ schoolId, kind: 'createClosure', path: 'closures', resourceVersion: 0, body, scope: state.instructor });
    return keep(command, 'L’absence est ajoutée.', { tag: ABSENCE_TAG, operationId: command.operationId, kind: 'absence-create', instructor: state.instructor, draft });
  };

  const remove = (): 'kept' | 'refused' => {
    if (!removing || !state.writable) return 'refused';
    const { kind, value } = removing;
    const command = createCommand({ schoolId, kind: kind === 'rule' ? 'removeAvailabilityRule' : 'removeClosure',
      path: `${kind === 'rule' ? 'availability-rules' : 'closures'}/${value.id}/remove`, resourceId: value.id, resourceVersion: value.version, ifMatch: value.version,
      body: { reason: REMOVAL_REASON }, scope: state.instructor });
    const base = { tag: removalTag(value.id), operationId: command.operationId, instructor: state.instructor };
    return keep(command, kind === 'rule' ? 'L’horaire est retiré.' : 'L’absence est retirée.',
      kind === 'rule' ? { ...base, kind: 'rule-remove', ruleId: value.id } : { ...base, kind: 'absence-remove', closureId: value.id });
  };

  /** Takes a refused request up again: the form (or the removal) comes back with what was typed and the school's refusal. */
  function resume(refusal: ScheduleRefusal) {
    const { intention, outcome } = refusal;
    setRefusals(list => list.filter(item => item !== refusal));
    lane.clearOutcome();
    if (intention.kind === 'rule-create') state.setView({ kind: 'rule', ruleId: null, restored: { draft: intention.draft, outcome } });
    else if (intention.kind === 'rule-update') state.setView({ kind: 'rule', ruleId: intention.ruleId, restored: { draft: intention.draft, outcome, ...(intention.base ? { base: intention.base } : {}) } });
    else if (intention.kind === 'absence-create') state.setView({ kind: 'absence', restored: { draft: intention.draft, outcome } });
    else {
      const row = intention.kind === 'rule-remove' ? state.rules.find(item => item.id === intention.ruleId) : (state.loaded.data?.closures ?? []).find(item => item.id === intention.closureId);
      if (!row) return;
      setRemoving(intention.kind === 'rule-remove' ? { kind: 'rule', value: row as Availability } : { kind: 'absence', value: row as Closure });
      setRemovalOutcome(outcome);
    }
  }
  const dismiss = (refusal: ScheduleRefusal) => setRefusals(list => list.filter(item => item !== refusal));

  const outcomeFor = (tag: string): NonNullable<Outcome> | null => lane.outcomes.get(tag) as NonNullable<Outcome> | undefined ?? null;
  const confirmation = [...lane.outcomes.values()].filter(item => item.tone === 'success').at(-1) as NonNullable<Outcome> | undefined ?? null;

  return {
    rules: rules.rules, ruleMarks: rules.marks, absences: absences.absences, absenceMarks: absences.marks,
    blockedRules, blockedAbsences, blockedReason, removing, setRemoving: (next: Removal | null) => { setRemoving(next); setRemovalOutcome(null); lane.clearOutcome(); },
    removalOutcome: removalOutcome ?? (removing ? outcomeFor(removalTag(removing.value.id)) : null),
    saveRule, saveAbsence, remove, outcomeFor, clearOutcome: (tag?: string) => lane.clearOutcome(tag), confirmation,
    refusals: refusals.filter(item => item.intention.instructor === state.instructor), resume, dismiss,
  };
}
export type ScheduleCommands = ReturnType<typeof useScheduleCommands>;
