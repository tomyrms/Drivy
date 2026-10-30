import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { useConsole, type Outcome } from '../../console/context';

export const money = (cents: number) => new Intl.NumberFormat('fr-CH', { style: 'currency', currency: 'CHF' }).format(cents / 100);
export const dateTime = (instant: string, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short', timeZone }).format(new Date(instant));
export const phaseLabels = { planned: 'Planifiée', waiting: 'À démarrer', started: 'En cours', 'to-finish': 'À terminer', completed: 'Terminée', cancelled: 'Annulée', absent: 'Absence' };

export function ReadFeedback({ loaded, label }: { loaded: { status: string; error?: string | null | undefined; needsLogin?: boolean | undefined; reload: () => void }; label: string }) {
  const context = useConsole();
  if (loaded.status === 'loading') return <div className="agenda-loading" role="status" aria-label={label}><Skeleton className="h-6 w-48" /><Skeleton className="h-24 w-full" /></div>;
  if (loaded.status !== 'error') return null;
  return <Alert variant="destructive"><AlertTitle>{label}</AlertTitle><AlertDescription>{loaded.error}</AlertDescription><div className="agenda-actions"><Button variant="outline" onClick={loaded.reload}>Réessayer</Button>{loaded.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}</div></Alert>;
}
export function CommandFeedback({ outcome, blocked }: { outcome: Outcome; blocked?: string | null | undefined }) {
  const context = useConsole();
  return <>{outcome && <Alert variant={outcome.tone === 'error' ? 'destructive' : 'default'}><AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>{outcome.needsLogin && <Button variant="outline" onClick={() => context.login({ reauthenticate: outcome.code === 'REAUTH_REQUIRED' })}>Se reconnecter</Button>}</Alert>}{blocked && <Alert><AlertTitle>Confirmation en attente</AlertTitle><AlertDescription>{blocked}</AlertDescription></Alert>}</>;
}
