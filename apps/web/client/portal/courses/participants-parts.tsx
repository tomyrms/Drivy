import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import type { ParticipantsRefusal, RowFeedback } from './use-course-participants';

/** The state of the last send for one row, in words, announced politely and shown beside the person it concerns. */
export function FeedbackText({ feedback }: { feedback: RowFeedback | undefined }) {
  if (!feedback) return null;
  return <span className="participants-feedback" data-tone={feedback.tone} role={feedback.tone === 'error' ? 'alert' : 'status'}>{feedback.text}</span>;
}

/**
 * A gesture the school has not answered yet, marked next to the value it does not replace: the mark is text, never the only
 * colour, and it names the person's own line so a disabled control can point at it.
 */
export function MarkText({ text, id }: { text: string; id?: string | undefined }) {
  return <span className="participants-feedback" data-tone="pending" {...(id ? { id } : {})}>{text}</span>;
}

/**
 * Requests the school refused after the form had been released: what was typed comes back on demand, nothing else changes.
 * A refusal is never a confirmation and never alters a row.
 */
export function ParticipantRefusals({ refusals, onResume, onDismiss }: {
  refusals: readonly ParticipantsRefusal[]; onResume: (refusal: ParticipantsRefusal) => void; onDismiss: (refusal: ParticipantsRefusal) => void;
}) {
  return <>{refusals.map((item, index) => <Alert key={`${item.intention.tag}:${index}`} variant="destructive">
    <AlertTitle>{item.outcome.title}</AlertTitle><AlertDescription>{item.outcome.message}</AlertDescription>
    <div className="course-actions">
      <Button type="button" variant="outline" onClick={() => onResume(item)}>Reprendre la saisie</Button>
      <Button type="button" variant="ghost" onClick={() => onDismiss(item)}>Ignorer</Button>
    </div>
  </Alert>)}</>;
}
