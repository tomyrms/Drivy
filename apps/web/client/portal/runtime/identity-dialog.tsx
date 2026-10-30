import { useEffect, useRef, useState } from 'react';
import { okSchema, request, RequestFailure, sessionSchema, type Session } from '../../protocol';
import { identityConfirmationMessage } from '../../identity-confirmation-model';
import { Alert, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';

/** Same flow as the historical dialog. Memory only: no password in a draft, a command journal or the URL. */
export function PortalIdentityDialog({ mode, initialEmail, onConfirmed, onCancel }: {
  mode: 'confirm' | 'login'; initialEmail: string; onConfirmed: (session: Session) => void | Promise<void>; onCancel: () => void;
}) {
  const [email, setEmail] = useState(initialEmail), [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const submitting = useRef(false), mounted = useRef(true);
  const passwordInput = useRef<HTMLInputElement>(null);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
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
  return <Dialog open onOpenChange={(open, details) => { if (busy) details.cancel(); else if (!open) onCancel(); }}>
    <DialogContent showCloseButton={!busy} initialFocus={passwordInput}>
      <DialogHeader><DialogTitle>{mode === 'confirm' ? 'Confirmer votre identité' : 'Se connecter à Drivy'}</DialogTitle></DialogHeader>
      {error && <Alert variant="destructive"><AlertTitle>{error}</AlertTitle></Alert>}
      <form id="portal-identity" noValidate onSubmit={event => { event.preventDefault(); void submit(); }}>
        <FieldGroup>
          <Field><FieldLabel htmlFor="portal-identity-email">E-mail</FieldLabel>
            <Input id="portal-identity-email" name="email" type="email" value={email} onChange={event => setEmail(event.target.value)} autoComplete="username" inputMode="email" maxLength={254} required disabled={busy} /></Field>
          <Field><FieldLabel htmlFor="portal-identity-password">Mot de passe</FieldLabel>
            <Input ref={passwordInput} id="portal-identity-password" name="password" type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="current-password" maxLength={128} required disabled={busy} /></Field>
        </FieldGroup>
      </form>
      <DialogFooter>
        <Button variant="outline" disabled={busy} onClick={onCancel}>Annuler</Button>
        <Button type="submit" form="portal-identity" disabled={busy || !email.trim() || !password}>{busy ? 'Vérification…' : mode === 'confirm' ? 'Confirmer mon identité' : 'Se connecter'}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}
