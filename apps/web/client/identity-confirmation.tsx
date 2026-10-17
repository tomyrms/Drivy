import { useEffect, useRef, useState } from 'react';
import { okSchema, request, RequestFailure, sessionSchema, type Session } from './protocol';
import { ConfirmDialog, Notice, TextField } from './ui';
import { identityConfirmationMessage } from './identity-confirmation-model';

/** Memory only: same-origin form, no external navigation and no password in a draft or command journal. */
export function IdentityConfirmationDialog({ mode, initialEmail, onConfirmed, onCancel }: {
  mode: 'confirm' | 'login'; initialEmail: string; onConfirmed: (session: Session) => void | Promise<void>; onCancel: () => void;
}) {
  const [email, setEmail] = useState(initialEmail), [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const submitting = useRef(false);
  const mounted = useRef(true);
  const form = useRef<HTMLFormElement>(null);
  useEffect(() => {
    mounted.current = true;
    form.current?.querySelector<HTMLInputElement>('input[name="password"]')?.focus();
    return () => { mounted.current = false; };
  }, []);
  async function submit() {
    if (submitting.current || !email.trim() || !password) return;
    submitting.current = true; setBusy(true); setError(null);
    try {
      const session = await request('session', sessionSchema);
      if (!mounted.current) return;
      await request(mode === 'confirm' ? 'reauthenticate' : 'password-login', okSchema, { csrf: session.csrfToken, body: { email, password } });
      if (!mounted.current) return;
      setPassword('');
      const next = await request('session', sessionSchema);
      if (!mounted.current) return;
      if (!next.authenticated) throw new RequestFailure('SESSION_EXPIRED', 401);
      if (mode === 'confirm' && next.reauthenticationRequired !== false) throw new RequestFailure('REAUTH_PROOF_UNAVAILABLE', 503);
      await onConfirmed(next);
    } catch (cause) { if (mounted.current) { setPassword(''); setError(identityConfirmationMessage(cause)); } }
    finally { submitting.current = false; if (mounted.current) setBusy(false); }
  }
  return <ConfirmDialog open title={mode === 'confirm' ? 'Confirmer votre identité' : 'Se connecter à Drivy'}
    confirmLabel={mode === 'confirm' ? 'Confirmer mon identité' : 'Se connecter'} busyLabel="Vérification…" busy={busy}
    onCancel={onCancel} onConfirm={() => void submit()} disabled={!email.trim() || !password}>
    {error && <Notice tone="error" title={error} />}
    <form ref={form} className="form-grid" noValidate onSubmit={event => { event.preventDefault(); void submit(); }}>
      <TextField name="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="username" inputMode="email" maxLength={254} required disabled={busy} />
      <TextField name="password" label="Mot de passe" type="password" value={password} onChange={setPassword} autoComplete="current-password" maxLength={128} required disabled={busy} />
      <button type="submit" hidden disabled={busy}>Confirmer</button>
    </form>
  </ConfirmDialog>;
}
