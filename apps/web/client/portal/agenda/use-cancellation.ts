import { useEffect, useRef, useState } from 'react';
import { createCommand } from '../../command-core';
import { canEditPlannedLesson, planningLessonSchema, type PlanningLesson } from '../../lesson-planning-model';
import { readSchool } from '../../school-api';
import { readError, useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';

export const cancellationReasons = [
  { value: 'LEARNER_REQUEST', label: 'Demande de l’élève' }, { value: 'INSTRUCTOR_UNAVAILABLE', label: 'Moniteur indisponible' },
  { value: 'SCHOOL_CLOSURE', label: 'Fermeture de l’école' }, { value: 'OTHER', label: 'Autre motif' },
];
export function useCancellation(lesson: PlanningLesson, onSaved: () => void) {
  const { schoolId, membership } = useConsole();
  const [target, setTarget] = useState<PlanningLesson | null>(null), [reason, setReason] = useState('LEARNER_REQUEST'), [comment, setComment] = useState('');
  const [discard, setDiscard] = useState(false), [rereading, setRereading] = useState(false), [problem, setProblem] = useState('');
  const inFlight = useRef(false);
  const reset = () => { setTarget(null); setReason('LEARNER_REQUEST'); setComment(''); setDiscard(false); setProblem(''); };
  const runner = useCommandRunner(() => { reset(); inFlight.current = false; onSaved(); });
  const wasPending = useRef(false);
  useEffect(() => { if (runner.pending) wasPending.current = true; else if (wasPending.current && !runner.busy) { wasPending.current = false; inFlight.current = false; } }, [runner.pending, runner.busy]);
  const locked = runner.busy || !!runner.pending || rereading;
  const dirty = comment.length > 0 || reason !== 'LEARNER_REQUEST';
  useUnsavedChanges(!!target && dirty);
  const authorized = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR') && membership.membershipId === lesson.instructorMembershipId;
  const editable = authorized && canEditPlannedLesson(lesson);
  const close = () => { if (locked || inFlight.current) return; if (dirty) setDiscard(true); else reset(); };
  const cancel = async () => {
    if (!target || !editable || inFlight.current || locked || !cancellationReasons.some(item => item.value === reason) || comment.length > 1000) return;
    inFlight.current = true;
    const result = await runner.run(createCommand({ schoolId, kind: 'cancelLesson', path: `lessons/${target.id}/cancel`, ifMatch: target.version,
      resourceId: target.id, resourceVersion: target.version, body: { reasonCode: reason, comment: comment.trim() || null } }), 'La leçon est annulée.');
    if (result.status === 'rejected') inFlight.current = false;
    if (result.status === 'pending') { setTarget(null); window.requestAnimationFrame(() => document.getElementById('pending-title')?.focus()); }
  };
  const reread = async () => {
    if (inFlight.current || locked) return;
    setRereading(true); setProblem('');
    try {
      const current = await readSchool(schoolId, `lessons/${lesson.id}`, planningLessonSchema);
      const allowed = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR') && membership.membershipId === current.instructorMembershipId;
      if (current.id !== lesson.id || current.schoolId !== schoolId || !allowed || !canEditPlannedLesson(current)) { setProblem('La leçon ne peut plus être annulée. Fermez cette fenêtre et actualisez sa fiche.'); return; }
      setTarget(current); runner.clearOutcome();
    } catch (error) { setProblem(readError(error)); }
    finally { setRereading(false); }
  };
  return { target, reason, setReason, comment, setComment, discard, setDiscard, reset, close, locked, runner, editable, problem, reread, cancel,
    open: () => { if (editable && !locked) { runner.clearOutcome(); setTarget(lesson); } } };
}
