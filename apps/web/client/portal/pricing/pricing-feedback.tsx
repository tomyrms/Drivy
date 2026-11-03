import type { ReactNode } from 'react';
import type { LaneOutcome } from '../../command-lane';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import type { useCommandRunner } from '../../console/context';

/**
 * Retour d'une intention de catalogue sur la voie de commandes (#124). Le succès n'apparaît qu'après la réponse vérifiée ou le reçu
 * (le magasin ne le produit pas autrement), un refus garde toujours la saisie, et « Enregistrement en cours » vit sur la ligne
 * concernée, pas ici.
 */
export function LaneFeedback({ outcome, onDismiss }: { outcome: LaneOutcome | null; onDismiss?: () => void }) {
  if (!outcome) return null;
  return <Alert variant={outcome.tone === 'error' ? 'destructive' : 'default'}>
    <AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
    {outcome.tone === 'success' && onDismiss && <div className="cat-alert-actions"><Button variant="ghost" onClick={onDismiss}>Masquer</Button></div>}
  </Alert>;
}

/** Une demande refusée après libération du formulaire : la saisie revient sur demande, rien d'autre ne bouge. */
export function RefusalBanner({ outcome, onResume, onDismiss, children }: {
  outcome: LaneOutcome; onResume: () => void; onDismiss?: () => void; children?: ReactNode;
}) {
  return <Alert variant="destructive"><AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
    <div className="cat-alert-actions">{children}
      <Button variant="outline" onClick={onResume}>Reprendre la saisie</Button>
      {onDismiss && <Button variant="ghost" onClick={onDismiss}>Ignorer</Button>}
    </div>
  </Alert>;
}

/**
 * Les composants de retour du catalogue (`CommandFeedback`, `ReviewDialog`) attendent le coureur unique. La voie de commandes fournit
 * son résultat par étiquette et cette section le rend elle-même : cet adaptateur ne montre rien et n'envoie rien, il laisse seulement
 * ces composants inchangés plutôt que d'en inventer un second.
 */
export function quietRunner(busy: boolean): ReturnType<typeof useCommandRunner> {
  return { run: () => Promise.reject(new Error('La voie de commandes ne passe pas par ce coureur.')), busy, pending: undefined,
    outcome: null, clearOutcome: () => {}, blockedReason: null };
}
