import { useEffect, useId, useRef } from 'react';
import type { ReactNode } from 'react';

export type SymbolKind = 'account' | 'school' | 'alert' | 'check' | 'refresh' | 'lock' | 'mail' | 'shield' | 'clock'
  | 'home' | 'settings' | 'list' | 'layers' | 'book' | 'file' | 'tag' | 'receipt' | 'users' | 'plus' | 'edit' | 'send'
  | 'ban' | 'back' | 'info' | 'dot';

const symbolPaths: Record<SymbolKind, ReactNode> = {
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
};

/** Decorative outline symbol; every meaning it carries is also written in text. */
export function Symbol({ kind, tile = false, bare = false }: { kind: SymbolKind; tile?: boolean; bare?: boolean }) {
  const className = bare ? 'symbol bare' : tile ? 'symbol tile' : 'symbol';
  return <span className={className} aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{symbolPaths[kind]}</svg></span>;
}

export type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger';
/** Status pill shared with the Apple client: symbol + text + tone, never color alone. */
export function StatusBadge({ tone, symbol, children }: { tone: Tone; symbol: SymbolKind; children: ReactNode }) {
  return <span className={`badge ${tone}`}><Symbol kind={symbol} bare />{children}</span>;
}

export function Notice({ tone, title, children, actions, live }: {
  tone: 'error' | 'success' | 'warning' | 'info'; title: string; children?: ReactNode; actions?: ReactNode; live?: boolean;
}) {
  const symbol: SymbolKind = tone === 'success' ? 'check' : tone === 'info' ? 'info' : 'alert';
  const role = live === false ? undefined : tone === 'error' ? 'alert' : 'status';
  return (
    <div className={`notice ${tone}`} role={role}>
      <Symbol kind={symbol} />
      <div className="notice-body">
        <strong>{title}</strong>
        {children}
        {actions && <div className="notice-actions">{actions}</div>}
      </div>
    </div>
  );
}

export function Loading({ label }: { label: string }) {
  return <p className="loading" role="status"><span className="spinner" aria-hidden="true" />{label}</p>;
}

export function EmptyState({ symbol, title, message, action }: { symbol: SymbolKind; title: string; message: string; action?: ReactNode }) {
  return (
    <div className="empty-state">
      <Symbol kind={symbol} />
      <div className="row-text">
        <h3 className="row-title">{title}</h3>
        <p className="row-meta">{message}</p>
        {action}
      </div>
    </div>
  );
}

type FieldProps = { label: string; hint?: string | undefined; error?: string | null | undefined; disabled?: boolean | undefined; required?: boolean | undefined };

function FieldFrame({ id, label, hint, error, required, children, counter }: FieldProps & { id: string; children: ReactNode; counter?: ReactNode }) {
  return (
    <div className={error ? 'field invalid' : 'field'}>
      <label htmlFor={id}>{label}{required === false && <span className="optional"> · facultatif</span>}</label>
      {children}
      {(hint || counter) && <p className="caption field-hint" id={`${id}-hint`}>{hint}{counter}</p>}
      {error && <p className="field-error" id={`${id}-error`}><Symbol kind="alert" bare />{error}</p>}
    </div>
  );
}

const describedBy = (id: string, hint?: string, error?: string | null, counter?: boolean) =>
  [hint || counter ? `${id}-hint` : '', error ? `${id}-error` : ''].filter(Boolean).join(' ') || undefined;

export function TextField({ label, value, onChange, hint, error, disabled, required, type = 'text', maxLength, autoComplete, inputMode, placeholder, readOnly }: FieldProps & {
  value: string; onChange: (value: string) => void; type?: 'text' | 'email' | 'tel' | 'date' | 'datetime-local' | 'url' | 'number';
  maxLength?: number; autoComplete?: string; inputMode?: 'text' | 'decimal' | 'numeric' | 'email' | 'tel'; placeholder?: string; readOnly?: boolean;
}) {
  const id = useId();
  return (
    <FieldFrame id={id} label={label} hint={hint} error={error} required={required}>
      <input id={id} type={type} value={value} disabled={disabled} readOnly={readOnly} required={required} placeholder={placeholder}
        autoComplete={autoComplete ?? 'off'} inputMode={inputMode} maxLength={maxLength}
        aria-invalid={error ? true : undefined} aria-describedby={describedBy(id, hint, error)}
        onChange={event => onChange(event.target.value)} />
    </FieldFrame>
  );
}

export function TextArea({ label, value, onChange, hint, error, disabled, required, maxLength, rows = 5 }: FieldProps & {
  value: string; onChange: (value: string) => void; maxLength?: number; rows?: number;
}) {
  const id = useId();
  const length = [...value].length;
  const counter = maxLength && length > maxLength * .8
    ? <span className={length > maxLength ? 'counter over' : 'counter'}> {length.toLocaleString('fr-CH')} / {maxLength.toLocaleString('fr-CH')} caractères</span> : null;
  return (
    <FieldFrame id={id} label={label} hint={hint} error={error} required={required} counter={counter}>
      <textarea id={id} value={value} disabled={disabled} required={required} rows={rows}
        aria-invalid={error ? true : undefined} aria-describedby={describedBy(id, hint, error, counter !== null)}
        onChange={event => onChange(event.target.value)} />
    </FieldFrame>
  );
}

export function SelectField<T extends string>({ label, value, onChange, options, hint, error, disabled, required, placeholder }: FieldProps & {
  value: T | ''; onChange: (value: T) => void; options: readonly { value: T; label: string; disabled?: boolean }[]; placeholder?: string;
}) {
  const id = useId();
  return (
    <FieldFrame id={id} label={label} hint={hint} error={error} required={required}>
      <select id={id} value={value} disabled={disabled} required={required} aria-invalid={error ? true : undefined}
        aria-describedby={describedBy(id, hint, error)} onChange={event => onChange(event.target.value as T)}>
        {placeholder !== undefined && <option value="" disabled>{placeholder}</option>}
        {options.map(option => <option key={option.value} value={option.value} disabled={option.disabled}>{option.label}</option>)}
      </select>
    </FieldFrame>
  );
}

/** The single selection pattern (DrivySelectionCardStyle): native checkbox, soft accent when checked. */
export function CheckField({ label, description, checked, onChange, disabled }: {
  label: string; description?: string; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean;
}) {
  const id = useId();
  return (
    <label className="check-field" htmlFor={id}>
      <input id={id} type="checkbox" checked={checked} disabled={disabled} onChange={event => onChange(event.target.checked)}
        aria-describedby={description ? `${id}-description` : undefined} />
      <span className="check-text">
        <span className="check-label">{label}</span>
        {description && <span className="caption" id={`${id}-description`}>{description}</span>}
      </span>
    </label>
  );
}

/**
 * Review before a durable write. Native modal dialog: focus stays inside, Échap cancels,
 * focus returns to the control that opened it. The confirm button waits for the school.
 */
export function ConfirmDialog({ open, title, confirmLabel, onConfirm, onCancel, busy, acknowledgement, acknowledged, onAcknowledge, children, disabledReason }: {
  open: boolean; title: string; confirmLabel: string; onConfirm: () => void; onCancel: () => void; busy: boolean;
  acknowledgement?: string; acknowledged?: boolean; onAcknowledge?: (value: boolean) => void; children: ReactNode; disabledReason?: string | null;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const opener = useRef<Element | null>(null);
  const titleId = useId();
  useEffect(() => {
    const element = dialog.current;
    if (!element) return;
    if (open && !element.open) { opener.current = document.activeElement; element.showModal(); }
    if (!open && element.open) {
      element.close();
      if (opener.current instanceof HTMLElement && opener.current.isConnected && !opener.current.matches(':disabled')) opener.current.focus();
    }
  }, [open]);
  const blocked = busy || (acknowledgement !== undefined && !acknowledged) || !!disabledReason;
  return (
    <dialog ref={dialog} className="confirm-dialog" aria-labelledby={titleId}
      onCancel={event => { event.preventDefault(); if (!busy) onCancel(); }}>
      <div className="dialog-header">
        <h2 id={titleId}>{title}</h2>
      </div>
      <div className="dialog-body">
        {children}
        {acknowledgement !== undefined && onAcknowledge &&
          <CheckField label={acknowledgement} checked={!!acknowledged} onChange={onAcknowledge} disabled={busy} />}
        {disabledReason && <p className="caption">{disabledReason}</p>}
      </div>
      <div className="dialog-actions">
        <button type="button" className="button secondary" onClick={onCancel} disabled={busy}>Retour</button>
        <button type="button" className="button primary" onClick={onConfirm} disabled={blocked} aria-busy={busy}>
          {busy && <span className="spinner on-accent" aria-hidden="true" />}{busy ? 'Confirmation par l’école…' : confirmLabel}
        </button>
      </div>
    </dialog>
  );
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
