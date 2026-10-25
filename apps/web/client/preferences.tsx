import { useEffect, useId, useRef, useState } from 'react';
import { BrandSymbol } from './BrandSymbol';
import { Symbol } from './ui';
import { type ThemePreference, useTheme } from './theme';
import { NotificationPreferencesSection } from './notification-preferences';
import './console/settings-studio.css';

const themes: { value: ThemePreference; label: string }[] = [
  { value: 'light', label: 'Clair' }, { value: 'dark', label: 'Sombre' }, { value: 'system', label: 'Système' },
];
export function ThemeControl({ compact = false }: { compact?: boolean }) {
  const { preference, storageError, setTheme } = useTheme();
  const name = useId();
  const [changed, setChanged] = useState(false);
  return <fieldset className={`theme-control${compact ? ' compact' : ''}`}>
    <legend>Apparence</legend>
    <div className="theme-options">{themes.map(theme => <label className="theme-option" key={theme.value}>
      <input type="radio" name={name} value={theme.value} checked={preference === theme.value}
        onChange={() => { setTheme(theme.value); setChanged(true); }} />
      {!compact && <span className={`theme-preview preview-${theme.value}`} aria-hidden="true">
        <span className="theme-preview-rail"><i /><i /><i /></span>
        <span className="theme-preview-content"><i /><i /><i /><i /></span>
      </span>}
      <span>{theme.label}</span>
    </label>)}</div>
    <p className={storageError ? 'field-error' : 'visually-hidden'} role="status">{storageError
      ? 'Le thème est appliqué, mais ce navigateur ne permet pas de conserver votre choix.'
      : changed ? 'Préférence enregistrée sur ce navigateur.' : ''}</p>
  </fieldset>;
}

/** Ordinary disclosure, not an ARIA menu: links and radio controls keep their native keyboard behavior. */
export function AccountMenu({ name = 'Mon compte', authenticated = false, busy = false, onLogout, beforeNavigate }: {
  name?: string; authenticated?: boolean; busy?: boolean; onLogout?: () => void; beforeNavigate?: (proceed: () => void) => void;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null), trigger = useRef<HTMLButtonElement>(null);
  const id = useId();
  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('pointerdown', outside);
    return () => document.removeEventListener('pointerdown', outside);
  }, [open]);
  const go = (href: string) => { const action = () => window.location.assign(href); beforeNavigate ? beforeNavigate(action) : action(); setOpen(false); };
  const returnTo = `${window.location.pathname}${window.location.search}`;
  const preferences = `/app/preferences${returnTo.startsWith('/app/gestion/') ? `?returnTo=${encodeURIComponent(returnTo)}` : ''}`;
  return <div className="account-menu" ref={root} onKeyDown={event => { if (event.key === 'Escape') { setOpen(false); trigger.current?.focus(); } }}>
    <button type="button" className="button quiet account-trigger" ref={trigger} aria-expanded={open} aria-controls={id}
      onClick={() => setOpen(value => !value)}><Symbol kind="account" bare /><span>{name}</span><Symbol kind="chevron" bare /></button>
    {open && <div id={id} className="account-popover" onBlur={event => { if (event.relatedTarget && !root.current?.contains(event.relatedTarget as Node)) setOpen(false); }}>
      <a href="/app/" onClick={event => { if (event.ctrlKey || event.metaKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); go('/app/'); }}>Mon compte et mes écoles</a>
      <a href={preferences} onClick={event => { if (event.ctrlKey || event.metaKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); go(preferences); }}>Préférences personnelles</a>
      <ThemeControl compact />
      {authenticated && onLogout && <button type="button" className="button quiet" disabled={busy} onClick={() => { onLogout(); setOpen(false); }}>Se déconnecter</button>}
    </div>}
  </div>;
}

export function PreferencesPage() {
  const requested = new URLSearchParams(window.location.search).get('returnTo') ?? '';
  // Only an internal console URL may be offered as a return destination.
  const back = /^\/app\/gestion\/[\da-f-]{36}\/[a-z-]+(?:\?[^#]*)?$/i.test(requested) ? requested : '/app/';
  useEffect(() => { document.title = 'Préférences personnelles · Drivy'; }, []);
  return <div className="app-shell personal-preferences settings-studio">
    <a className="skip-link" href="#main">Aller au contenu</a>
    <header className="site-header"><a className="brand" href="/app/"><BrandSymbol /><span>Drivy</span></a><AccountMenu /></header>
    <main id="main" className="main">
      <a className="button quiet preference-back" href={back}><Symbol kind="back" bare />{back === '/app/' ? 'Retour à mon compte' : 'Retour à l’école'}</a>
      <div className="preferences-heading"><Symbol kind="settings" bare /><h1>Préférences personnelles</h1></div>
      <section className="settings-section"><div className="settings-section-heading"><h2>Affichage</h2></div>
        <div className="settings-section-body"><ThemeControl /></div>
      </section>
      <NotificationPreferencesSection />
    </main>
  </div>;
}
