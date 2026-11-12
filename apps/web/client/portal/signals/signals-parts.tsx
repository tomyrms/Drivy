import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent, PointerEvent as ReactPointerEvent } from 'react';
import { ChevronDown, ChevronUp, CircleAlert, GripVertical } from 'lucide-react';
import { dropIndex, isLastVisible, moveAnnouncement, moveThemeBy, moveThemeTo, toggleAnnouncement, toggleTheme, type ThemeRow } from '../../console/observation-themes-model';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Switch } from '../../components/ui/switch';
import { ThemeIcon } from './theme-icons';
import './signals.css';

type Control = 'handle' | 'up' | 'down';

/**
 * Liste ordonnable des signalements, commune à la page de l'école et aux préférences du compte (R08).
 * `orderable` : poignées et flèches ; `togglable` : interrupteurs d'affichage. Sans interrupteur, un thème masqué le dit en toutes lettres.
 * `disabled` : une demande est en cours, rien ne se modifie. Le parent garde l'état : `onChange` reçoit toujours la liste complète.
 */
export function SortableThemes({ rows, onChange, orderable, togglable, disabled, label }: {
  rows: ThemeRow[]; onChange: (next: ThemeRow[], message: string) => void;
  orderable: boolean; togglable: boolean; disabled: boolean; label: string;
}) {
  const uid = useId();
  const [dragging, setDragging] = useState<string | null>(null);
  const editable = !disabled;
  const onlyOneVisible = rows.filter(row => row.visible).length === 1;
  const items = useRef(new Map<string, HTMLLIElement>());
  const controls = useRef(new Map<string, HTMLButtonElement>());
  const listRef = useRef<HTMLOListElement>(null);
  const focusAfter = useRef<{ key: string; control: Control } | null>(null);
  const rowsRef = useRef(rows); rowsRef.current = rows;
  const changeRef = useRef(onChange); changeRef.current = onChange;

  function emit(next: ThemeRow[], message: string) {
    rowsRef.current = next;
    changeRef.current(next, message);
  }
  function move(key: string, delta: number, control: Control) {
    if (!editable || !orderable) return;
    const next = moveThemeBy(rows, key, delta);
    if (next.every((row, index) => row.key === rows[index]?.key)) return;
    focusAfter.current = { key, control };
    emit(next, moveAnnouncement(next, key));
  }
  function onHandleKey(event: ReactKeyboardEvent, key: string) {
    const delta = event.key === 'ArrowUp' ? -1 : event.key === 'ArrowDown' ? 1 : event.key === 'Home' ? -rows.length : event.key === 'End' ? rows.length : 0;
    if (delta === 0 || event.altKey || event.ctrlKey || event.metaKey) return;
    event.preventDefault();
    move(key, delta, 'handle');
  }
  // Moving the focused node drops its focus: give it back to the control used, or to the handle when that control is disabled.
  useLayoutEffect(() => {
    const target = focusAfter.current;
    if (!target) return;
    focusAfter.current = null;
    let element = controls.current.get(`${target.key}:${target.control}`);
    if (!element || element.disabled) element = controls.current.get(`${target.key}:handle`);
    element?.focus();
  });

  // Pointer drag (mouse, touch, pen); Escape or a cancelled pointer restores the order from before the drag.
  const drag = useRef<{ key: string; grab: number; clientY: number; startRows: ThemeRow[] } | null>(null);
  const teardown = useRef<(() => void) | null>(null);
  const [announcement, setAnnouncement] = useState('');
  function place() {
    const state = drag.current, list = listRef.current, row = state ? items.current.get(state.key) : undefined;
    if (!state || !list || !row) return;
    row.style.transform = `translateY(${state.clientY - list.getBoundingClientRect().top - state.grab - row.offsetTop}px)`;
  }
  useLayoutEffect(() => { if (drag.current) place(); });
  useEffect(() => () => teardown.current?.(), []);

  function startDrag(event: ReactPointerEvent<HTMLButtonElement>, key: string) {
    if (!editable || !orderable || drag.current || (event.pointerType === 'mouse' && event.button !== 0)) return;
    const row = items.current.get(key);
    if (!row) return;
    const pointerId = event.pointerId;
    drag.current = { key, grab: event.clientY - row.getBoundingClientRect().top, clientY: event.clientY, startRows: rowsRef.current };
    setDragging(key);
    const onMove = (moved: PointerEvent) => {
      const state = drag.current, list = listRef.current;
      if (!state || !list || moved.pointerId !== pointerId) return;
      state.clientY = moved.clientY;
      const current = rowsRef.current;
      const held = current.findIndex(item => item.key === state.key);
      const nodes = current.map(item => items.current.get(item.key));
      const middles = nodes.map(node => node ? node.offsetTop + node.offsetHeight / 2 : 0);
      const center = moved.clientY - list.getBoundingClientRect().top - state.grab + (nodes[held]?.offsetHeight ?? 0) / 2;
      const target = dropIndex(middles, held, center);
      if (target !== held) emit(moveThemeTo(current, state.key, target), '');
      place();
    };
    const finish = (cancelled: boolean) => {
      const state = drag.current;
      teardown.current?.();
      if (!state) return;
      const node = items.current.get(state.key);
      if (node) node.style.transform = '';
      drag.current = null; setDragging(null);
      if (cancelled) { emit(state.startRows, 'Déplacement annulé.'); return; }
      const now = rowsRef.current;
      if (now.some((item, index) => item.key !== state.startRows[index]?.key)) setAnnouncement(moveAnnouncement(now, state.key));
    };
    const onUp = (ended: PointerEvent) => { if (ended.pointerId === pointerId) finish(false); };
    const onCancel = (ended: PointerEvent) => { if (ended.pointerId === pointerId) finish(true); };
    const onKey = (pressed: KeyboardEvent) => { if (pressed.key === 'Escape') { pressed.preventDefault(); finish(true); } };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
    window.addEventListener('keydown', onKey);
    teardown.current = () => {
      window.removeEventListener('pointermove', onMove); window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onCancel); window.removeEventListener('keydown', onKey);
      teardown.current = null;
    };
  }

  const title = (key: string) => `${uid}-title-${key}`;
  const register = (key: string, control: Control) => (element: HTMLButtonElement | null) => {
    if (element) controls.current.set(`${key}:${control}`, element); else controls.current.delete(`${key}:${control}`);
  };

  return <div className="signals-editor">
    <p className="sr-only" role="status" aria-live="polite">{announcement}</p>
    {orderable && <p id={`${uid}-help`} className="sr-only">Faites glisser la poignée, ou utilisez les flèches haut et bas ; début et fin vont aux extrémités.</p>}
    <ol className={`signals-list${dragging ? ' is-dragging-list' : ''}`} ref={listRef} aria-label={label}>
      {rows.map((row, index) => {
        const last = isLastVisible(rows, row.key);
        return <li key={row.key} ref={element => { if (element) items.current.set(row.key, element); else items.current.delete(row.key); }}
          className={`signals-row${row.visible ? '' : ' is-hidden'}${dragging === row.key ? ' is-dragging' : ''}`}>
          {orderable && <button type="button" className="signals-handle" ref={register(row.key, 'handle')} disabled={!editable}
            aria-label={`Déplacer ${row.title}, position ${index + 1} sur ${rows.length}`} aria-describedby={`${uid}-help`}
            onPointerDown={event => startDrag(event, row.key)} onKeyDown={event => onHandleKey(event, row.key)}><GripVertical aria-hidden="true" /></button>}
          <div className="signals-name"><ThemeIcon themeKey={row.key} /><span id={title(row.key)}>{row.title}</span></div>
          {orderable && <span className="signals-moves">
            <Button variant="ghost" size="icon" ref={register(row.key, 'up')} disabled={!editable || index === 0}
              aria-label={`Monter ${row.title}`} onClick={() => move(row.key, -1, 'up')}><ChevronUp aria-hidden="true" /></Button>
            <Button variant="ghost" size="icon" ref={register(row.key, 'down')} disabled={!editable || index === rows.length - 1}
              aria-label={`Descendre ${row.title}`} onClick={() => move(row.key, 1, 'down')}><ChevronDown aria-hidden="true" /></Button>
          </span>}
          {togglable
            ? <Switch checked={row.visible} disabled={!editable || last} aria-labelledby={title(row.key)} aria-describedby={last ? `${uid}-last` : undefined}
                onCheckedChange={() => { const next = toggleTheme(rows, row.key); emit(next, toggleAnnouncement(next, row.key)); }} />
            : !row.visible && <span className="signals-state">Masqué</span>}
        </li>;
      })}
    </ol>
    {togglable && onlyOneVisible && <p id={`${uid}-last`} className="signals-hint"><CircleAlert aria-hidden="true" />Au moins un signalement reste affiché.</p>}
  </div>;
}

/** Grille « Signaler » telle que la verra le moniteur : les thèmes affichés, dans l'ordre donné. */
export function SignalsPreview({ tiles, open, onOpenChange, title = 'Aperçu pour le moniteur' }: {
  tiles: readonly { key: string; title: string }[]; open: boolean; onOpenChange: (open: boolean) => void; title?: string;
}) {
  return <Collapsible open={open} onOpenChange={onOpenChange} className="signals-preview">
    <CollapsibleTrigger render={<Button variant="ghost" className="signals-preview-trigger" />}>
      {title}<ChevronDown aria-hidden="true" className={open ? 'rotate-180' : undefined} />
    </CollapsibleTrigger>
    <CollapsibleContent>
      <ol className="signals-tiles" aria-label="Grille Signaler, dans l’ordre">
        {tiles.map(tile => <li key={tile.key}><ThemeIcon themeKey={tile.key} /><span>{tile.title}</span></li>)}
      </ol>
    </CollapsibleContent>
  </Collapsible>;
}

export const previewStartsOpen = () => !(typeof window !== 'undefined' && window.matchMedia?.('(max-width: 1023px)').matches);
