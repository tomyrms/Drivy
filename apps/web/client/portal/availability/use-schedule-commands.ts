import { useRef, useState } from 'react';
import { createCommand } from '../../command-core';
import type { SubmitResult } from '../../command-store';
import type { Availability, Closure } from '../../school-api';
import { useCommandRunner } from '../../console/context';
import { absenceBody, REMOVAL_REASON, ruleBody, type AbsenceDraft, type RuleDraft } from './schedule-model';
import type { ScheduleState } from './use-schedule';

export type Removal = { kind: 'rule'; value: Availability } | { kind: 'absence'; value: Closure };

/**
 * Hours and absences are written only through the shared command engine: one operation per intention, the version read
 * with the row, no success shown before the school's receipt. A schedule change never moves an existing appointment:
 * the school refuses it (EXISTING_BOOKINGS) and the refusal stays next to the fields.
 */
export function useScheduleCommands(state: ScheduleState) {
  const { schoolId, school } = state.context;
  const [removing, setRemoving] = useState<Removal | null>(null);
  const runner = useCommandRunner(() => { state.setView(null); setRemoving(null); state.refresh(); });
  const guard = useRef(false);
  const locked = runner.busy || Boolean(runner.pending);
  const once = async (work: () => Promise<SubmitResult>): Promise<SubmitResult | null> => {
    if (guard.current || locked || !state.writable) return null;
    guard.current = true;
    try { return await work(); } finally { guard.current = false; }
  };

  const saveRule = (draft: RuleDraft, target: Availability | null) => once(() => {
    const body = ruleBody(draft, state.instructor);
    return runner.run(createCommand(target
      ? { schoolId, kind: 'updateAvailabilityRule', path: `availability-rules/${target.id}`, resourceId: target.id, resourceVersion: target.version, ifMatch: target.version, body }
      : { schoolId, kind: 'createAvailabilityRule', path: 'availability-rules', resourceVersion: 0, body }), target ? 'L’horaire est modifié.' : 'L’horaire est ajouté.');
  });
  const saveAbsence = (draft: AbsenceDraft) => once(async () => {
    const body = absenceBody(draft, state.instructor, school.timeZone);
    if (!body) return { status: 'rejected', code: 'INVALID_REQUEST', message: 'Vérifiez les dates de l’absence.', needsLogin: false };
    return runner.run(createCommand({ schoolId, kind: 'createClosure', path: 'closures', resourceVersion: 0, body }), 'L’absence est ajoutée.');
  });
  const remove = () => once(async () => {
    if (!removing) return { status: 'rejected', code: 'NOT_FOUND', message: 'Rien à retirer.', needsLogin: false };
    const { kind, value } = removing;
    const result = await runner.run(createCommand({ schoolId, kind: kind === 'rule' ? 'removeAvailabilityRule' : 'removeClosure',
      path: `${kind === 'rule' ? 'availability-rules' : 'closures'}/${value.id}/remove`, resourceId: value.id, resourceVersion: value.version, ifMatch: value.version,
      body: { reason: REMOVAL_REASON } }), kind === 'rule' ? 'L’horaire est retiré.' : 'L’absence est retirée.');
    if (result.status === 'pending') setRemoving(null);
    return result;
  });
  return { runner, locked, removing, setRemoving, saveRule, saveAbsence, remove };
}
export type ScheduleCommands = ReturnType<typeof useScheduleCommands>;
