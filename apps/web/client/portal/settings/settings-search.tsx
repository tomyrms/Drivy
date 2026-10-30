import { useEffect, useId, useRef, useState } from 'react';
import { ArrowRight, Search } from 'lucide-react';
import { useConsole } from '../../console/context';
import { consolePath, type NavigationQuery } from '../../console/route';
import { searchSettings } from '../../console/settings-search-model';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import './search.css';

/** Search only static destinations. Neither the query nor school content is stored. */
export function PortalSettingsSearch() {
  const { schoolId, navigate, confirmNavigation } = useConsole();
  const [open, setOpen] = useState(false), [query, setQuery] = useState('');
  const input = useRef<HTMLInputElement>(null), trigger = useRef<HTMLButtonElement>(null);
  const navigated = useRef(false);
  const id = useId();
  const results = searchSettings(query);
  const close = () => { setOpen(false); setQuery(''); };
  return <>
    <Button ref={trigger} variant="ghost" className="portal-search-trigger" aria-label="Rechercher un réglage"
      onClick={() => { navigated.current = false; setOpen(true); }}><Search aria-hidden="true" /><span>Rechercher un réglage</span></Button>
    <Dialog open={open} onOpenChange={value => { if (!value) close(); }}>
      <DialogContent className="portal-settings-search" initialFocus={input} finalFocus={() => navigated.current ? false : trigger.current}>
        <DialogHeader><DialogTitle>Rechercher un réglage</DialogTitle></DialogHeader>
        <FieldGroup><Field><FieldLabel htmlFor={id} className="sr-only">Rechercher dans les paramètres</FieldLabel>
          <Input ref={input} id={id} type="search" placeholder="Téléphone, horaires, confidentialité…" autoComplete="off"
            value={query} onChange={event => setQuery(event.target.value)} /></Field></FieldGroup>
        <p className="sr-only" role="status">{results.length} résultat{results.length > 1 ? 's' : ''}</p>
        <ul className="portal-search-results">{results.map(result => {
          const next: NavigationQuery = result.target ? { focus: result.target } : {};
          if (result.section === 'apercu') next.from = 'configuration';
          // Leaving for personal preferences must bring the person back to the same page and context.
          const href = result.section ? consolePath(schoolId, result.section, next)
            : `/app/preferences?returnTo=${encodeURIComponent(`${window.location.pathname}${window.location.search}`)}`;
          return <li key={result.id}><a href={href} onClick={event => {
            if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
            event.preventDefault(); navigated.current = true; close();
            if (result.section) navigate(result.section, next);
            else if (confirmNavigation) confirmNavigation(() => window.location.assign(href));
            else window.location.assign(href);
          }}><span><strong>{result.label}</strong><span>{result.group}</span></span><ArrowRight aria-hidden="true" /></a></li>;
        })}</ul>
        {!results.length && <Empty><EmptyHeader><EmptyTitle>Aucun réglage trouvé</EmptyTitle></EmptyHeader>
          <Button variant="outline" onClick={() => { setQuery(''); input.current?.focus(); }}>Effacer la recherche</Button></Empty>}
      </DialogContent>
    </Dialog>
  </>;
}

/** Deep links wait for the real field, including a lazy page or an editor opened by its query. */
export function PortalSettingsFocus({ target, navigationKey }: { target: string | undefined; navigationKey: string }) {
  useEffect(() => {
    if (!target) return;
    let completed = false;
    const focus = () => {
      // Wait until the closing search popup releases its focus trap and is unmounted.
      if (document.querySelector('[data-slot="dialog-content"]')) return;
      const field = document.getElementById(target);
      if (completed || !field || field.matches(':disabled') || field.closest('[hidden], [inert]')) return;
      if (!field.matches('input,textarea,select,button,a')) field.tabIndex = -1;
      field.focus({ preventScroll: true });
      if (document.activeElement !== field) return; // A closing modal may still keep the page inert.
      completed = true;
      field.scrollIntoView({ block: 'center', behavior: 'instant' });
      observer.disconnect();
      clearInterval(retry);
    };
    const observer = new MutationObserver(focus);
    observer.observe(document.getElementById('portal-content') ?? document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'hidden', 'inert'] });
    const frame = requestAnimationFrame(focus);
    const retry = window.setInterval(focus, 100);
    const timeout = window.setTimeout(() => { observer.disconnect(); clearInterval(retry); }, 15_000);
    return () => { observer.disconnect(); cancelAnimationFrame(frame); clearTimeout(timeout); clearInterval(retry); };
  }, [target, navigationKey]);
  return null;
}
