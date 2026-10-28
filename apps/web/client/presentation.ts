/** Rebuilt management presentation, opt-in per browser while #311 replaces the historical console. */
export type Presentation = 'portal' | 'legacy';
const storageKey = 'drivy.web.presentation';

/** Read `?presentation=nouvelle|ancienne` once, remember it, and drop it from the address. Never touches the fragment. */
export function readPresentation(): Presentation {
  const params = new URLSearchParams(window.location.search);
  const asked = params.get('presentation');
  if (asked === 'nouvelle' || asked === 'ancienne') {
    choosePresentation(asked === 'nouvelle' ? 'portal' : 'legacy');
    params.delete('presentation');
    const search = params.toString();
    window.history.replaceState(window.history.state, '', `${window.location.pathname}${search ? `?${search}` : ''}`);
  }
  try { return window.localStorage.getItem(storageKey) === 'portal' ? 'portal' : 'legacy'; }
  catch { return asked === 'nouvelle' ? 'portal' : 'legacy'; }
}

export function choosePresentation(next: Presentation) {
  try { window.localStorage.setItem(storageKey, next); } catch { /* Not persisted: this page keeps its current presentation. */ }
}
