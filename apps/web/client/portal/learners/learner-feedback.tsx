import { Alert, AlertTitle, AlertDescription } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { useConsole, type Loaded, type useCommandRunner } from '../../console/context';

export function ReadFeedback({ loaded }: { loaded: Pick<Loaded<unknown>, 'status' | 'error' | 'reload' | 'needsLogin'> }) {
  const context = useConsole();
  if (loaded.status === 'loading') return <div className="student-loading" role="status" aria-label="Chargement"><Skeleton className="h-6 w-48" /><Skeleton className="h-20 w-full" /></div>;
  if (loaded.status !== 'error') return null;
  return <Alert variant="destructive"><AlertTitle>Lecture impossible</AlertTitle><AlertDescription>{loaded.error}</AlertDescription><Button variant="outline" onClick={loaded.reload}>Réessayer</Button>{loaded.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}</Alert>;
}
export function CommandFeedback({ runner }: { runner: ReturnType<typeof useCommandRunner> }) {
  const context = useConsole();
  return <>{runner.outcome && <Alert variant={runner.outcome.tone === 'error' ? 'destructive' : 'default'}><AlertTitle>{runner.outcome.title}</AlertTitle><AlertDescription>{runner.outcome.message}</AlertDescription>{runner.outcome.needsLogin && <Button variant="outline" onClick={() => context.login({ reauthenticate: runner.outcome?.code === 'REAUTH_REQUIRED' })}>Se reconnecter</Button>}</Alert>}
    {runner.blockedReason && <Alert><AlertTitle>Confirmation en attente</AlertTitle><AlertDescription>{runner.blockedReason}</AlertDescription></Alert>}</>;
}
