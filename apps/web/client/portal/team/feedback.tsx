import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { useConsole, type Loaded, type useCommandRunner } from '../../console/context';

/** Loading skeleton, then a read failure with a retry; nothing once the read succeeded. */
export function ReadFeedback({ loaded, label = 'Chargement' }: { loaded: Pick<Loaded<unknown>, 'status' | 'error' | 'reload' | 'needsLogin'>; label?: string }) {
  const context = useConsole();
  if (loaded.status === 'loading') return <div className="team-loading" role="status" aria-label={label}><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /></div>;
  if (loaded.status !== 'error') return null;
  return <Alert variant="destructive"><AlertTitle>Lecture impossible</AlertTitle><AlertDescription>{loaded.error}</AlertDescription>
    <div className="team-alert-actions"><Button variant="outline" onClick={loaded.reload}>Réessayer</Button>{loaded.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}</div></Alert>;
}

/** Result of the last command and the wait for a request still followed by the store. Errors only; success is the caller's. */
export function CommandFeedback({ runner, showSuccess = true }: { runner: ReturnType<typeof useCommandRunner>; showSuccess?: boolean }) {
  const context = useConsole();
  const outcome = runner.outcome && (showSuccess || runner.outcome.tone !== 'success') ? runner.outcome : null;
  return <>
    {outcome && <Alert variant={outcome.tone === 'error' ? 'destructive' : 'default'}><AlertTitle>{outcome.title}</AlertTitle><AlertDescription>{outcome.message}</AlertDescription>
      {outcome.needsLogin && <div className="team-alert-actions"><Button variant="outline" onClick={() => context.login({ reauthenticate: outcome.code === 'REAUTH_REQUIRED' })}>Se reconnecter</Button></div>}</Alert>}
    {runner.blockedReason && <Alert><AlertTitle>Confirmation en attente</AlertTitle><AlertDescription>{runner.blockedReason}</AlertDescription></Alert>}
  </>;
}
