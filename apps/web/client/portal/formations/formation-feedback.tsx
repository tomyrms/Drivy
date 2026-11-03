import type { ReactNode } from 'react';
import type { LaneOutcome } from '../../command-lane';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { useConsole } from '../../console/context';

/** Une session perdue n'est pas un refus de l'école : elle propose de se reconnecter, comme partout dans la console. */
function LoginButton({ outcome }: { outcome: LaneOutcome }) {
  const context = useConsole();
  if (!outcome.needsLogin) return null;
  return <Button variant="outline" onClick={() => context.login({ reauthenticate: outcome.code === 'REAUTH_REQUIRED' })}>Se reconnecter</Button>;
}

/**
 * Retour d'une intention de programme sur la voie de commandes (#124). Le succès n'apparaît qu'après la réponse vérifiée ou le reçu
 * (le magasin ne le produit pas autrement), un refus garde toujours la saisie, et « Enregistrement en cours » vit sur la rubrique
 * concernée, pas ici.
 */
export function LaneFeedback({ outcome, onDismiss }: { outcome: LaneOutcome | null; onDismiss?: () => void }) {
  if (!outcome) return null;
  return <Alert variant={outcome.tone === 'error' ? 'destructive' : 'default'}>
    <AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
    <div className="cat-alert-actions"><LoginButton outcome={outcome} />
      {outcome.tone === 'success' && onDismiss && <Button variant="ghost" onClick={onDismiss}>Masquer</Button>}</div>
  </Alert>;
}

/** Une demande refusée après libération de l'éditeur : la saisie revient sur demande, rien d'autre ne bouge. */
export function RefusalBanner({ outcome, onResume, onDismiss, children }: {
  outcome: LaneOutcome; onResume: () => void; onDismiss?: () => void; children?: ReactNode;
}) {
  return <Alert variant="destructive"><AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
    <div className="cat-alert-actions">{children}<LoginButton outcome={outcome} />
      <Button variant="outline" onClick={onResume}>Reprendre la saisie</Button>
      {onDismiss && <Button variant="ghost" onClick={onDismiss}>Ignorer</Button>}
    </div>
  </Alert>;
}
