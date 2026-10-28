import { useEffect, useId, useRef } from 'react';
import type { ReactNode } from 'react';
import { Alert, AlertDescription, AlertTitle } from './components/ui/alert';
import { Badge } from './components/ui/badge';
import { Button } from './components/ui/button';
import { Dialog, DialogClose, DialogContent, DialogHeader, DialogTitle, DialogFooter } from './components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from './components/ui/empty';
import { Field, FieldLabel, FieldDescription, FieldError } from './components/ui/field';
import { Input } from './components/ui/input';
import { Skeleton } from './components/ui/skeleton';
import { Textarea } from './components/ui/textarea';

export type SymbolKind = 'account' | 'school' | 'alert' | 'check' | 'refresh' | 'lock' | 'mail' | 'shield' | 'clock'
  | 'home' | 'settings' | 'list' | 'layers' | 'book' | 'file' | 'tag' | 'receipt' | 'users' | 'plus' | 'edit' | 'send'
  | 'ban' | 'back' | 'info' | 'dot' | 'menu' | 'calendar' | 'route' | 'chevron' | 'chevron-up' | 'grip' | 'search';

const symbolPaths: Record<SymbolKind, ReactNode> = {
  search: <><circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 5 5" /></>,
  account: <><circle cx="12" cy="8" r="3.5" /><path d="M5 21v-3a7 7 0 0 1 14 0v3" /></>,
  school: <path d="M4 21V5l8-3 8 3v16M2 21h20M9 21v-5h6v5M8 7h1m6 0h1M8 11h1m6 0h1" />,
  alert: <><path d="M10.3 4 2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 4a2 2 0 0 0-3.4 0Z" /><path d="M12 9.5v4M12 17h.01" /></>,
  check: <><circle cx="12" cy="12" r="9" /><path d="m8 12.4 2.7 2.7L16 9.8" /></>,
  refresh: <><path d="M20 12a8 8 0 1 1-2.34-5.66" /><path d="M20 4v5h-5" /></>,
  lock: <><rect x="5" y="10.5" width="14" height="10" rx="2" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /></>,
  mail: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3.5 6.5 8.5 6.5 8.5-6.5" /></>,
  shield: <><path d="M12 3 5 6v5.5c0 4.4 3 8.1 7 9.5 4-1.4 7-5.1 7-9.5V6Z" /><path d="m9 12 2.2 2.2L15 10.4" /></>,
  clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7.5V12l3 2" /></>,
  home: <><path d="M3 11 12 4l9 7" /><path d="M5.5 9.5V20h13V9.5M10 20v-5h4v5" /></>,
  settings: <><circle cx="12" cy="12" r="3" /><path d="M12 2.5v3M12 18.5v3M4.2 5.2l2.1 2.1M17.7 16.7l2.1 2.1M2.5 12h3M18.5 12h3M4.2 18.8l2.1-2.1M17.7 7.3l2.1-2.1" /></>,
  list: <><path d="M9 6h11M9 12h11M9 18h11" /><path d="M4 6h.01M4 12h.01M4 18h.01" /></>,
  layers: <><path d="m12 3 9 5-9 5-9-5Z" /><path d="m3 13 9 5 9-5" /></>,
  book: <><path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2Z" /><path d="M4 21V5M8 7h7" /></>,
  file: <><path d="M6 3h8l5 5v13H6Z" /><path d="M14 3v5h5M9 13h6M9 17h6" /></>,
  tag: <><path d="M3 12V4h8l10 10-8 8Z" /><circle cx="7.5" cy="8.5" r="1.3" /></>,
  receipt: <><path d="M6 3h12v18l-3-2-3 2-3-2-3 2Z" /><path d="M9 8h6M9 12h6" /></>,
  users: <><circle cx="9" cy="8" r="3.2" /><path d="M3 20v-1.5a6 6 0 0 1 12 0V20" /><path d="M16 5a3 3 0 0 1 0 6M18 20v-1.5a5.5 5.5 0 0 0-2.5-4.6" /></>,
  plus: <path d="M12 5v14M5 12h14" />,
  edit: <><path d="M4 20h4L19 9l-4-4L4 16Z" /><path d="m13.5 6.5 4 4" /></>,
  send: <><path d="M21 3 10 14" /><path d="m21 3-7 18-4-7-7-4Z" /></>,
  ban: <><circle cx="12" cy="12" r="9" /><path d="m5.7 5.7 12.6 12.6" /></>,
  back: <path d="M15 5 8 12l7 7" />,
  info: <><circle cx="12" cy="12" r="9" /><path d="M12 11v6M12 7.5h.01" /></>,
  dot: <circle cx="12" cy="12" r="4" />,
  menu: <path d="M4 6h16M4 12h16M4 18h16" />,
  calendar: <><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M7 3v4M17 3v4M3 10h18M7 14h3M14 14h3M7 17h3" /></>,
  route: <><circle cx="5" cy="18" r="2" /><circle cx="19" cy="6" r="2" /><path d="M5 16v-5a3 3 0 0 1 3-3h3a3 3 0 0 1 0 6h2a6 6 0 0 0 6-6" /></>,
  chevron: <path d="m7 10 5 5 5-5" />,
  'chevron-up': <path d="m7 14 5-5 5 5" />,
  grip: <path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01" strokeWidth="2.6" />,
};

/** Decorative outline symbol; every meaning it carries is also written in text. */
export function Symbol({ kind, tile = false, bare = false }: { kind: SymbolKind; tile?: boolean; bare?: boolean }) {
  const className = bare ? 'symbol bare' : tile ? 'symbol tile' : 'symbol';
  return <span className={className} aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{symbolPaths[kind]}</svg></span>;
}

export type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger';
/** Exceptional status: symbol + text + tone, never color alone. */
export function StatusBadge({ tone, symbol, children }: { tone: Tone; symbol: SymbolKind; children: ReactNode }) {
  return <Badge variant="outline" className={`badge ${tone}`}><Symbol kind={symbol} bare />{children}</Badge>;
}

export function Notice({ tone, title, children, actions, live }: {
  tone: 'error' | 'success' | 'warning' | 'info'; title: string; children?: ReactNode; actions?: ReactNode; live?: boolean;
}) {
  const symbol: SymbolKind = tone === 'success' ? 'check' : tone === 'info' ? 'info' : 'alert';
  const role = live === false ? undefined : tone === 'error' ? 'alert' : 'status';
  return (
    <Alert className={`notice ${tone}`} role={role}>
      <Symbol kind={symbol} />
      <div className="notice-body">
        <AlertTitle>{title}</AlertTitle>
        {children && <AlertDescription>{children}</AlertDescription>}
        {actions && <div className="notice-actions">{actions}</div>}
      </div>
    </Alert>
  );
}

export function Loading({ label, skeleton = false }: { label: string; skeleton?: boolean }) {
  return <div className="load-state" aria-busy="true">
    <p className="loading" role="status"><span className="spinner" aria-hidden="true" />{label}</p>
    {skeleton && <div className="load-skeleton" aria-hidden="true"><Skeleton /><Skeleton /><Skeleton /></div>}
  </div>;
}

export function EmptyState({ symbol, title, message, action }: { symbol: SymbolKind; title: string; message?: string; action?: ReactNode }) {
  return (
    <Empty className="empty-state">
      <EmptyHeader>
        <EmptyMedia variant="icon"><Symbol kind={symbol} bare /></EmptyMedia>
        <EmptyTitle><h3>{title}</h3></EmptyTitle>
        {message && <EmptyDescription>{message}</EmptyDescription>}
      </EmptyHeader>
      {action && <EmptyContent>{action}</EmptyContent>}
    </Empty>
  );
}

type FieldProps = { id?: string; label: string; hint?: string | undefined; error?: string | null | undefined; disabled?: boolean | undefined; required?: boolean | undefined };

function FieldFrame({ id, label, hint, error, required, disabled, children, counter }: FieldProps & { id: string; children: ReactNode; counter?: ReactNode }) {
  return (
    <Field className={error ? 'field invalid' : 'field'} data-invalid={!!error} data-disabled={!!disabled}>
      <FieldLabel htmlFor={id}>{label}{required === false && <span className="optional">Facultatif</span>}</FieldLabel>
      {children}
      {(hint || counter) && <FieldDescription className="caption field-hint" id={`${id}-hint`}>{hint}{counter}</FieldDescription>}
      {error && <FieldError className="field-error" id={`${id}-error`}><Symbol kind="alert" bare />{error}</FieldError>}
    </Field>
  );
}

const describedBy = (id: string, hint?: string, error?: string | null, counter?: boolean) =>
  [hint || counter ? `${id}-hint` : '', error ? `${id}-error` : ''].filter(Boolean).join(' ') || undefined;

export function TextField({ id: suppliedId, label, value, onChange, hint, error, disabled, required, type = 'text', maxLength, autoComplete, inputMode, placeholder, readOnly, name }: FieldProps & {
  value: string; onChange: (value: string) => void; type?: 'text' | 'email' | 'password' | 'tel' | 'date' | 'time' | 'datetime-local' | 'url' | 'number';
  maxLength?: number; autoComplete?: string; inputMode?: 'text' | 'decimal' | 'numeric' | 'email' | 'tel'; placeholder?: string; readOnly?: boolean; name?: string;
}) {
  const generatedId = useId(), id = suppliedId ?? generatedId;
  return (
    <FieldFrame id={id} label={label} hint={hint} error={error} required={required} disabled={disabled}>
      <Input id={id} name={name} type={type} value={value} disabled={disabled} readOnly={readOnly} required={required} placeholder={placeholder}
        autoComplete={autoComplete ?? 'off'} inputMode={inputMode} maxLength={maxLength}
        aria-invalid={error ? true : undefined} aria-describedby={describedBy(id, hint, error)}
        onChange={event => onChange(event.target.value)} />
    </FieldFrame>
  );
}

export function TextArea({ id: suppliedId, label, value, onChange, hint, error, disabled, required, maxLength, rows = 5, name }: FieldProps & {
  value: string; onChange: (value: string) => void; maxLength?: number; rows?: number; name?: string;
}) {
  const generatedId = useId(), id = suppliedId ?? generatedId;
  const length = [...value].length;
  const counter = maxLength && length > maxLength * .8
    ? <span className={length > maxLength ? 'counter over' : 'counter'}> {length.toLocaleString('fr-CH')} / {maxLength.toLocaleString('fr-CH')} caractères</span> : null;
  return (
    <FieldFrame id={id} label={label} hint={hint} error={error} required={required} disabled={disabled} counter={counter}>
      <Textarea id={id} name={name} value={value} disabled={disabled} required={required} rows={rows}
        aria-invalid={error ? true : undefined} aria-describedby={describedBy(id, hint, error, counter !== null)}
        onChange={event => onChange(event.target.value)} />
    </FieldFrame>
  );
}

export { SelectField, SegmentField } from './choice-field';

/** Native checkbox with one drawing across settings, permissions and confirmations. */
export function CheckField({ label, description, checked, onChange, disabled, indeterminate = false, variant = 'plain' }: {
  label: ReactNode; description?: string; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean;
  indeterminate?: boolean; variant?: 'plain' | 'confirmation';
}) {
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { if (input.current) input.current.indeterminate = indeterminate; }, [indeterminate]);
  return (
    <label className={`check-field${variant === 'confirmation' ? ' check-confirmation' : ''}`} htmlFor={id}>
      <span className="check-control"><input ref={input} id={id} type="checkbox" checked={checked} disabled={disabled}
        onChange={event => { event.target.indeterminate = indeterminate; onChange(event.target.checked); }}
        aria-labelledby={`${id}-label`} aria-describedby={description ? `${id}-description` : undefined} />
        <svg className="check-mark" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="m4 9 3.2 3.2L14 5.8" /></svg>
        <svg className="check-mixed" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 9h10" /></svg>
      </span>
      <span className="check-text">
        <span className="check-label" id={`${id}-label`}>{label}</span>
        {description && <span className="caption" id={`${id}-description`}>{description}</span>}
      </span>
    </label>
  );
}

/** Review a durable write with one Base UI modal, at every viewport size. */
export function ConfirmDialog({ open, title, confirmLabel, onConfirm, onCancel, busy, acknowledgement, acknowledged, onAcknowledge, children, disabledReason, disabled = false, busyLabel = 'Confirmation par l’école…' }: {
  open: boolean; title: string; confirmLabel: string; onConfirm: () => void; onCancel: () => void; busy: boolean;
  acknowledgement?: string; acknowledged?: boolean; onAcknowledge?: (value: boolean) => void; children: ReactNode; disabledReason?: string | null; disabled?: boolean; busyLabel?: string;
}) {
  const titleHeading = useRef<HTMLHeadingElement>(null);
  const opener = useRef<HTMLElement | null>(null);
  useEffect(() => {
    // A pending command can disable all controls; keep the focus inside its review.
    if (open && busy) titleHeading.current?.focus({ preventScroll: true });
  }, [open, busy]);
  const restoreFocus = () => opener.current?.isConnected && !opener.current.matches(':disabled')
    ? opener.current : document.querySelector<HTMLElement>('main h1');
  const blocked = busy || disabled || (acknowledgement !== undefined && !acknowledged) || !!disabledReason;
  return <Dialog open={open} disablePointerDismissal onOpenChange={(next, details) => {
    if (busy) { details.cancel(); return; }
    if (!next) onCancel();
  }}>
    <DialogContent className="confirm-dialog" showCloseButton={false} initialFocus={() => {
      // Capture before the popup moves focus, including imperatively opened reviews.
      opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      return titleHeading.current;
    }} finalFocus={restoreFocus}>
      <DialogHeader><DialogTitle ref={titleHeading} tabIndex={-1}>{title}</DialogTitle></DialogHeader>
      <div className="dialog-body">
        {children}
        {acknowledgement !== undefined && onAcknowledge &&
          <CheckField variant="confirmation" label={acknowledgement} checked={!!acknowledged} onChange={onAcknowledge} disabled={busy} />}
        {disabledReason && <p className="caption">{disabledReason}</p>}
      </div>
      <DialogFooter>
        <DialogClose disabled={busy} render={<Button variant="outline" />}>Retour</DialogClose>
        <Button onClick={onConfirm} disabled={blocked} aria-busy={busy}>
          {busy && <span className="spinner on-accent" aria-hidden="true" />}{busy ? busyLabel : confirmLabel}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}

export function Facts({ items }: { items: readonly (readonly [string, ReactNode])[] }) {
  return <dl className="facts">{items.map(([term, value]) => <div key={term}><dt>{term}</dt><dd>{value}</dd></div>)}</dl>;
}

export function formatDateTime(value: string, timeZone?: string): string {
  try { return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short', ...(timeZone ? { timeZone } : {}) }).format(new Date(value)); }
  catch { return 'Date indisponible'; }
}

export function formatCivilDate(value: string | null): string {
  if (!value) return 'Sans fin';
  const [year, month, day] = value.split('-');
  return `${day}.${month}.${year}`;
}

export function formatDuration(minutes: number | null): string {
  if (minutes === null) return 'Non renseignée';
  const hours = Math.floor(minutes / 60), rest = minutes % 60;
  return hours ? `${hours} h${rest ? ` ${String(rest).padStart(2, '0')}` : ''}` : `${minutes} min`;
}
