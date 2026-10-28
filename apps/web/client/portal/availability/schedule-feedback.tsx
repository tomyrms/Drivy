import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import type { Outcome } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';

/** Codes whose refusal belongs to a field, not to the action bar. */
export const fieldRefusalCodes = ['INVALID_INTERVAL'] as const;
export const isFieldRefusal = (outcome: Outcome) => outcome?.tone === 'error' && (fieldRefusalCodes as readonly string[]).includes(outcome.code ?? '');

/**
 * A refusal of the school, shown next to the buttons that triggered it, with the one useful next step.
 * A refused schedule change never moves an appointment: the school lists them first, the person goes to the agenda.
 */
export function ScheduleRefusal({ outcome, blocked, instructorName, busy, onAgenda, onReread }: {
  outcome: Outcome; blocked?: string | null | undefined; instructorName: string; busy: boolean; onAgenda: () => void; onReread: () => void;
}) {
  if (outcome?.tone === 'error' && outcome.code === 'EXISTING_BOOKINGS') {
    return <Alert variant="destructive"><AlertTitle>Des rendez-vous sont prévus</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
      <div className="schedule-actions"><Button type="button" variant="outline" disabled={busy} onClick={onAgenda}>Voir l’agenda de {instructorName}</Button></div></Alert>;
  }
  if (outcome?.tone === 'error' && outcome.code === 'VERSION_CONFLICT') {
    return <Alert variant="destructive"><AlertTitle>Modifié entre-temps</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
      <div className="schedule-actions"><Button type="button" variant="outline" disabled={busy} onClick={onReread}>Relire, garder ma saisie</Button></div></Alert>;
  }
  if (isFieldRefusal(outcome)) return blocked ? <CommandFeedback outcome={null} blocked={blocked} /> : null;
  return <CommandFeedback outcome={outcome?.tone === 'success' ? null : outcome} blocked={blocked} />;
}

export function DiscardDialog({ open, onCancel, onDiscard }: { open: boolean; onCancel: () => void; onDiscard: () => void }) {
  return <Dialog open={open} onOpenChange={value => { if (!value) onCancel(); }}><DialogContent>
    <DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Votre saisie sera perdue.</DialogDescription></DialogHeader>
    <DialogFooter><Button variant="outline" onClick={onCancel}>Continuer la saisie</Button><Button variant="destructive" onClick={onDiscard}>Abandonner</Button></DialogFooter>
  </DialogContent></Dialog>;
}
