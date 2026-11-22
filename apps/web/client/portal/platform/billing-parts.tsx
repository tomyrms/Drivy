import type { ReactNode } from 'react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import type { PlatformConsoleState } from './use-platform-console';

export const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
/** Un jour civil reste ce jour-là, quel que soit le fuseau du navigateur. */
export const civil = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`));
export const by = (name: string | null) => (name ? ` · par ${name}` : '');
export const selectError = (message: string | undefined) => (message ? { error: message } : {});
export const reasonProblem = (text: string) => {
  const trimmed = text.trim();
  if (trimmed.length < 3) return 'Indiquez le motif en quelques mots.';
  return trimmed.length > 500 ? 'Ce texte est limité à 500 caractères.' : null;
};
export const dayPattern = /^\d{4}-\d{2}-\d{2}$/;

export function Fact({ label, children }: { label: string; children: ReactNode }) {
  return <div><dt>{label}</dt><dd>{children}</dd></div>;
}
export function Failure({ state, title }: { state: PlatformConsoleState; title: string }) {
  return state.error ? <Alert variant="destructive"><AlertTitle>{title}</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert> : null;
}
export function Footer({ state, label, busyLabel = 'Enregistrement…', destructive = false, cancel = 'Annuler', onCancel, disabled = false }: {
  state: PlatformConsoleState; label: string; busyLabel?: string; destructive?: boolean; cancel?: string; onCancel?: () => void; disabled?: boolean;
}) {
  return <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={onCancel ?? state.billing.stop}>{cancel}</Button>
    <Button type="submit" variant={destructive ? 'destructive' : 'default'} disabled={state.busy || disabled} aria-busy={state.busy}>{state.busy ? busyLabel : label}</Button></DialogFooter>;
}
export function TextField({ id, label, value, onChange, error, type = 'text', disabled, inputMode, autoComplete }: {
  id: string; label: string; value: string; onChange: (value: string) => void; error?: string | null | undefined; type?: string; disabled: boolean;
  inputMode?: 'decimal' | 'numeric' | 'email'; autoComplete?: string;
}) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Input id={id} name={id} type={type} inputMode={inputMode} autoComplete={autoComplete ?? 'off'} value={value} disabled={disabled} aria-invalid={!!error}
      aria-describedby={error ? `${id}-error` : undefined} onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}
export function ReasonField({ id, value, onChange, error, disabled, label = 'Motif' }: {
  id: string; value: string; onChange: (value: string) => void; error: string | null; disabled: boolean; label?: string;
}) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Textarea id={id} name={id} rows={3} maxLength={500} value={value} disabled={disabled} aria-invalid={!!error}
      aria-describedby={error ? `${id}-error` : undefined} onChange={event => onChange(event.target.value)} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}
export function NotFound() {
  return <DialogHeader><DialogTitle>Document introuvable</DialogTitle><DialogDescription>L’écran a été actualisé.</DialogDescription></DialogHeader>;
}
