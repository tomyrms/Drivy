import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, CircleAlert, KeyRound, Loader2, RefreshCw } from 'lucide-react';
import { request, sessionSchema } from '../../protocol';
import { Alert, AlertTitle } from '../../components/ui/alert';
import { Button, buttonVariants } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { entryRoutes, recoveryOptionsSchema, recoveryStartFailure, recoveryStartSchema, type EntryRoutes, type RecoveryState } from './entry-model';
import { EntryFrame } from './entry-frame';

/**
 * `/app/recover` with the rebuilt presentation (#319). The BFF says whether the identity provider offers a reset
 * flow; the provider page itself belongs to the identity service and is not part of this rebuild.
 * Opened from the sign-in form in another tab, so the form and its intention stay where they were.
 */
export function PortalRecoveryPage({ routes = entryRoutes, openProvider = url => window.location.assign(url) }: {
  routes?: EntryRoutes; openProvider?: (url: string) => void;
}) {
  const [state, setState] = useState<RecoveryState>('loading');
  const [attempt, setAttempt] = useState(0);
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { document.title = 'Mot de passe oublié · Drivy'; heading.current?.focus({ preventScroll: true }); }, []);
  useEffect(() => {
    let cancelled = false;
    setState('loading');
    void request('account-recovery/options', recoveryOptionsSchema).then(result => {
      if (!cancelled) setState(result.data.available ? 'available' : 'unavailable');
    }).catch(() => { if (!cancelled) setState('error'); });
    return () => { cancelled = true; };
  }, [attempt]);

  async function start() {
    if (state === 'opening') return;
    setState('opening');
    try {
      const session = await request('session', sessionSchema);
      const result = await request('account-recovery/start', recoveryStartSchema, { csrf: session.csrfToken, body: {} });
      openProvider(result.url);
    } catch (cause) { setState(recoveryStartFailure(cause)); }
  }

  return <EntryFrame home={routes.account} busy={state === 'loading'}>
    <section className="entry-auth" aria-labelledby="recovery-title">
      <header className="entry-auth-header">
        <span className="entry-icon-tile entry-icon-accent entry-icon-large"><KeyRound aria-hidden="true" /></span>
        <h1 id="recovery-title" ref={heading} tabIndex={-1}>Mot de passe oublié</h1>
      </header>
      <div className="entry-card">
        {state === 'loading' && <div className="grid gap-3" role="status" aria-label="Vérification…"><Skeleton className="h-12 w-full" /></div>}
        {state === 'unavailable' && <Alert variant="destructive"><CircleAlert aria-hidden="true" /><AlertTitle>L’envoi du lien de récupération n’est pas encore disponible.</AlertTitle></Alert>}
        {state === 'error' && <Alert variant="destructive"><CircleAlert aria-hidden="true" /><AlertTitle>La récupération est momentanément indisponible.</AlertTitle>
          <div className="entry-alert-actions"><Button variant="outline" onClick={() => setAttempt(value => value + 1)}><RefreshCw aria-hidden="true" />Réessayer</Button></div></Alert>}
        {(state === 'available' || state === 'opening') && <Button size="lg" className="entry-submit" disabled={state === 'opening'} focusableWhenDisabled onClick={() => void start()}>
          {state === 'opening' && <Loader2 className="entry-spin" aria-hidden="true" />}{state === 'opening' ? 'Ouverture…' : 'Récupérer mon accès'}
        </Button>}
        <p className="sr-only" role="status">{state === 'opening' ? 'Ouverture du service de connexion…' : ''}</p>
      </div>
      <div className="entry-alternatives">
        <a className={buttonVariants({ variant: 'ghost', size: 'lg' })} href={routes.account}><ArrowLeft aria-hidden="true" />Retour à la connexion</a>
      </div>
    </section>
  </EntryFrame>;
}
