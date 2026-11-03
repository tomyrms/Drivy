import { useRef, useState } from 'react';
import { createCommand } from '../../command-core';
import { canEditPlannedLesson, planningLessonSchema, type PlanningLesson } from '../../lesson-planning-model';
import { readSchool } from '../../school-api';
import { readError, useCommandLane, useConsole, useUnsavedChanges, type Outcome } from '../../console/context';

export const cancellationReasons = [
  { value: 'LEARNER_REQUEST', label: 'Demande de l’élève' }, { value: 'INSTRUCTOR_UNAVAILABLE', label: 'Moniteur indisponible' },
  { value: 'SCHOOL_CLOSURE', label: 'Fermeture de l’école' }, { value: 'OTHER', label: 'Autre motif' },
];

/**
 * Annulation d'une leçon par la voie de commandes (#109) : dès que la demande est conservée le dialogue se libère, la leçon
 * reste à sa place marquée « Annulation en cours » et aucun créneau n'est libéré avant la réponse vérifiée ou le reçu.
 * Un refus rouvre la confirmation avec le motif et le commentaire saisis.
 * `requestId` : la demande d'annulation de l'élève que cette annulation accepte ; l'école la ferme avec la leçon.
 */
export function useCancellation(lesson: PlanningLesson, onSaved: () => void, requestId?: string) {
  const { schoolId, membership } = useConsole();
  const [target, setTarget] = useState<PlanningLesson | null>(null), [reason, setReason] = useState('LEARNER_REQUEST'), [comment, setComment] = useState('');
  const [discard, setDiscard] = useState(false), [rereading, setRereading] = useState(false), [problem, setProblem] = useState('');
  const tag = `lesson:${lesson.id}:cancel`;
  const saved = useRef(onSaved);
  saved.current = onSaved;
  const lane = useCommandLane(intent => {
    if (intent.tag !== tag) return;
    setReason('LEARNER_REQUEST'); setComment(''); setDiscard(false);
    saved.current();
  });
  const outcome: Outcome = (lane.outcomes.get(tag) as Outcome | undefined) ?? null;
  const reset = () => { setTarget(null); setReason('LEARNER_REQUEST'); setComment(''); setDiscard(false); setProblem(''); };
  const busy = lane.busy;
  const blocked = lane.blocked({ kind: 'cancelLesson', resourceId: lesson.id });
  const locked = rereading;
  const dirty = comment.length > 0 || reason !== 'LEARNER_REQUEST';
  useUnsavedChanges(!!target && dirty);
  const authorized = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR') && membership.membershipId === lesson.instructorMembershipId;
  const editable = authorized && canEditPlannedLesson(lesson);
  const close = () => { if (locked) return; if (dirty) setDiscard(true); else reset(); };
  const cancel = () => {
    if (!target || !editable || busy || !cancellationReasons.some(item => item.value === reason) || comment.length > 1000) return;
    const attempted = target;
    const command = createCommand({ schoolId, kind: 'cancelLesson', path: `lessons/${attempted.id}/cancel`, ifMatch: attempted.version,
      resourceId: attempted.id, resourceVersion: attempted.version, body: { reasonCode: reason, comment: comment.trim() || null, ...(requestId ? { changeRequestId: requestId } : {}) } });
    const started = lane.run(command, 'La leçon est annulée.', tag);
    // Refusée localement (une planification attend déjà, double appui) : rien n'est envoyé, le dialogue reste tel quel.
    if (!started.admitted) return;
    setTarget(null);
    void started.result.then(result => {
      // Refus définitif : la confirmation revient avec le motif et le commentaire saisis.
      if (result.status === 'rejected') setTarget(attempted);
    });
  };
  const reread = async () => {
    if (rereading) return;
    setRereading(true); setProblem('');
    try {
      const current = await readSchool(schoolId, `lessons/${lesson.id}`, planningLessonSchema);
      const allowed = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR') && membership.membershipId === current.instructorMembershipId;
      if (current.id !== lesson.id || current.schoolId !== schoolId || !allowed || !canEditPlannedLesson(current)) { setProblem('La leçon ne peut plus être annulée. Fermez cette fenêtre et actualisez sa fiche.'); return; }
      setTarget(current); lane.clearOutcome();
    } catch (error) { setProblem(readError(error)); }
    finally { setRereading(false); }
  };
  return { target, reason, setReason, comment, setComment, discard, setDiscard, reset, close, locked, outcome, busy, blocked,
    blockedReason: blocked ? 'Une demande de planification attend sa confirmation (voir en haut de la page).' : null,
    editable, problem, reread, cancel,
    open: () => { if (editable && !busy) { lane.clearOutcome(); setTarget(lesson); } } };
}
