import { useEffect, useId, useRef, useState } from 'react';
import { Symbol } from '../ui';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from '../components/ui/dialog';
import { consolePath, type NavigationQuery } from './route';
import { searchSettings } from './settings-search-model';
import type { SectionKey } from './sections';

export function SettingsSearch({ schoolId, navigate, beforeNavigate }: {
  schoolId: string; navigate: (section: SectionKey, query?: NavigationQuery) => void; beforeNavigate: (proceed: () => void) => void;
}) {
  const [open, setOpen] = useState(false), [query, setQuery] = useState('');
  const trigger = useRef<HTMLButtonElement>(null), input = useRef<HTMLInputElement>(null);
  const navigated = useRef(false);
  const fieldId = useId();
  const results = searchSettings(query);
  const close = () => { setOpen(false); setQuery(''); };
  return <>
    <button type="button" ref={trigger} className="settings-search-trigger" onClick={() => { navigated.current = false; setOpen(true); }}><Symbol kind="search" bare /><span>Rechercher un réglage</span></button>
    <Dialog open={open} onOpenChange={next => { if (!next) close(); }}>
    <DialogContent className="settings-search" showCloseButton={false} initialFocus={input} finalFocus={() => navigated.current ? false : trigger.current}>
      <DialogHeader><DialogTitle>Rechercher un réglage</DialogTitle><DialogClose render={<Button variant="ghost" />}>Fermer</DialogClose></DialogHeader>
      <div className="dialog-body"><label className="visually-hidden" htmlFor={fieldId}>Rechercher dans les paramètres</label>
        <Input ref={input} id={fieldId} type="search" placeholder="Téléphone, horaires, confidentialité…" autoComplete="off" value={query} onChange={event => setQuery(event.target.value)} />
        <p className="visually-hidden" role="status">{results.length} résultat{results.length > 1 ? 's' : ''}</p>
        <ul className="search-results">{results.map(result => {
          const query: NavigationQuery = result.target ? { focus: result.target } : {};
          if (result.section === 'apercu') query.from = 'configuration';
          const href = result.section ? consolePath(schoolId, result.section, query) : `/app/preferences?returnTo=${encodeURIComponent(window.location.pathname)}`;
          return <li key={result.id}><a className="settings-result" href={href} onClick={event => {
            if (event.ctrlKey || event.metaKey || event.shiftKey || event.button !== 0) return;
            event.preventDefault(); navigated.current = true; close();
            if (result.section) navigate(result.section, query); else beforeNavigate(() => window.location.assign(href));
          }}><span className="result-label">{result.label}</span><span className="result-path">{result.group}</span></a></li>;
        })}</ul>
        {!results.length && <div className="settings-search-empty"><h3>Aucun réglage trouvé</h3><p>Essayez un autre mot, par exemple « horaires » ou « données ».</p><button type="button" className="button secondary" onClick={() => { setQuery(''); input.current?.focus(); }}>Effacer la recherche</button></div>}
      </div>
    </DialogContent>
    </Dialog>
  </>;
}

/** Wait for asynchronously loaded fields, then reveal their section and move keyboard focus. */
export function SettingsFocus({ section, target, navigationKey }: { section: SectionKey; target?: string | undefined; navigationKey: number }) {
  useEffect(() => {
    if (!target) return;
    let completed = false;
    const focus = () => {
      const element = document.getElementById(target);
      if (!element || element.matches(':disabled') || completed) return;
      completed = true;
      let parent: HTMLElement | null = element;
      while (parent) { if (parent instanceof HTMLDetailsElement) parent.open = true; parent = parent.parentElement; }
      if (!element.matches('input,textarea,select,button,a')) element.setAttribute('tabindex', '-1');
      element.focus({ preventScroll: true }); element.scrollIntoView({ block: 'center', behavior: 'instant' });
      element.classList.add('setting-target');
      observer.disconnect();
    };
    const observer = new MutationObserver(focus);
    observer.observe(document.getElementById('main') ?? document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled'] });
    // Page heading effects run before this frame; the field gets the final focus.
    const frame = requestAnimationFrame(focus);
    const timeout = window.setTimeout(() => observer.disconnect(), 15_000);
    return () => { observer.disconnect(); cancelAnimationFrame(frame); clearTimeout(timeout); document.getElementById(target)?.classList.remove('setting-target'); };
  }, [section, target, navigationKey]);
  return null;
}
