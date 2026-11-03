import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import type { LessonRefusal } from './lesson-intentions-model';

/**
 * Demandes de planification refusées après que le formulaire a été rendu à la consultation : la saisie revient sur demande,
 * avec la raison de l'école, et rien d'autre ne bouge. Un refus n'est jamais une confirmation et ne déplace aucune leçon.
 */
export function LessonRefusals({ refusals, onResume, onDismiss }: {
  refusals: readonly LessonRefusal[]; onResume: (refusal: LessonRefusal) => void; onDismiss: (refusal: LessonRefusal) => void;
}) {
  return <>
    {refusals.map(refusal => <Alert key={refusal.intention.operationId} variant="destructive">
      <AlertTitle>{refusal.outcome.title}</AlertTitle>
      <AlertDescription>{refusal.outcome.message}</AlertDescription>
      <div className="agenda-actions">
        <Button type="button" variant="outline" onClick={() => onResume(refusal)}>Reprendre la saisie</Button>
        <Button type="button" variant="ghost" onClick={() => onDismiss(refusal)}>Ignorer</Button>
      </div>
    </Alert>)}
  </>;
}
