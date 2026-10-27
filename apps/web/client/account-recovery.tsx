import { useEffect, useState } from 'react';
import { z } from 'zod';
import { request, sessionSchema } from './protocol';
import { Notice } from './ui';
import { BrandSymbol } from './BrandSymbol';
import { AccountMenu } from './preferences';

const optionsSchema = z.object({ data: z.discriminatedUnion('available', [
  z.object({ available: z.literal(false), recoveryUrl: z.null() }),
  z.object({ available: z.literal(true), recoveryUrl: z.url() }),
]) });

export function AccountRecoveryPage() {
  const [state, setState] = useState<'loading' | 'available' | 'unavailable' | 'error' | 'opening'>('loading');
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    document.title = 'Mot de passe oublié · Drivy';
    let cancelled = false;
    setState('loading');
    void request('account-recovery/options', optionsSchema).then(result => {
      if (!cancelled) setState(result.data.available ? 'available' : 'unavailable');
    }).catch(() => { if (!cancelled) setState('error'); });
    return () => { cancelled = true; };
  }, [attempt]);
  async function start() {
    setState('opening');
    try {
      const session = await request('session', sessionSchema);
      const result = await request('account-recovery/start', z.object({ url: z.url() }), { csrf: session.csrfToken, body: {} });
      // This URL is constructed by the BFF from its validated identity configuration, never from an e-mail or a return URL.
      window.location.assign(result.url);
    } catch { setState('error'); }
  }
  return <div className="app-shell">
    <a className="skip-link" href="#main">Aller au contenu</a>
    <header className="site-header"><a className="brand" href="/app/"><BrandSymbol /><span>Drivy</span></a><AccountMenu /></header>
    <main id="main" className="main"><section className="sign-in account-entry">
      <h1 tabIndex={-1} ref={element => element?.focus()}>Mot de passe oublié</h1>
      {(state === 'loading' || state === 'opening') && <p role="status">{state === 'loading' ? 'Vérification…' : 'Ouverture…'}</p>}
      {state === 'unavailable' && <Notice tone="error" title="L’envoi du lien de récupération n’est pas encore disponible." />}
      {state === 'error' && <Notice tone="error" title="La récupération est momentanément indisponible.">
        <button className="button secondary" type="button" onClick={() => setAttempt(value => value + 1)}>Réessayer</button>
      </Notice>}
      {state === 'available' && <button className="button primary" type="button" onClick={() => void start()}>Récupérer mon accès</button>}
      <a className="button quiet" href="/app/">Retour à la connexion</a>
    </section></main>
  </div>;
}
