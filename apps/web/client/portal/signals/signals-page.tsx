import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent, PointerEvent as ReactPointerEvent } from 'react';
import { Check, ChevronDown, ChevronUp, CircleAlert, GripVertical, RotateCcw } from 'lucide-react';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { readObservationThemes, type ObservationThemes } from '../../school-api';
import { useCommandRunner, useConsole, useLoad, useSectionDraft } from '../../console/context';
import {
  counterLabel, draftProblem, dropIndex, isDefaultConfiguration, isDefaultOrder, isDirty, isLastVisible, moveAnnouncement, moveThemeBy, moveThemeTo,
  previewTiles, resetAll, resetOrder, saveBody, settingsOf, toggleAnnouncement, toggleTheme, type ThemeRow,
} from '../../console/observation-themes-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '../../components/ui/dropdown-menu';
import { Switch } from '../../components/ui/switch';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import { ThemeIcon } from './theme-icons';
import './signals.css';

type Draft = { version: number; rows: ThemeRow[] };
type Control = 'handle' | 'up' | 'down';
const toRow = (theme: ObservationThemes['themes'][number]): ThemeRow => ({
  key: theme.key, title: theme.title, visible: theme.visible, defaultVisible: theme.defaultVisible, defaultPosition: theme.defaultPosition,
});

/** Lesson observation themes: order and visibility for the whole school, versioned with If-Match (#331). */
export function SignalsPilot() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readObservationThemes(schoolId), [schoolId, revision]);
  return <section className="signals-page">
    {loaded.status === 'ready' && loaded.data ? <SignalsEditor data={loaded.data} reload={loaded.reload} /> : <>
      <header className="signals-heading"><h1>Signalements</h1></header>
      <ReadFeedback loaded={loaded} label="Lecture des signalements" />
    </>}
  </section>;
}

function SignalsEditor({ data, reload }: { data: ObservationThemes; reload: () => void }) {
  const { schoolId } = useConsole();
  const uid = useId();
  const [saved, setSaved] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(() => !window.matchMedia('(max-width: 1023px)').matches);
  const runner = useCommandRunner(() => setSaved(true));
  const baseline = useMemo(() => data.themes.map(toRow), [data]);
  const [draft, setDraft] = useSectionDraft<Draft>('observation-themes', candidate =>
    !saved && candidate.version === data.version && isDirty(settingsOf(candidate.rows), settingsOf(baseline)));
  const [notice, setNotice] = useState<'conflict' | 'forbidden' | null>(null);
  const [announcement, setAnnouncement] = useState('');
  const [dragging, setDragging] = useState<string | null>(null);

  // A draft from an older version is never replayed over a newer configuration.
  const rows = draft && draft.version === data.version ? draft.rows : baseline;
  const dirty = isDirty(settingsOf(rows), settingsOf(baseline));
  const canManage = data.canManage && notice !== 'forbidden';
  const editable = canManage && !runner.pending && !runner.busy;
  const problem = draftProblem(rows);
  const tiles = previewTiles(rows);
  const onlyOneVisible = rows.filter(row => row.visible).length === 1;

  const items = useRef(new Map<string, HTMLLIElement>());
  const controls = useRef(new Map<string, HTMLButtonElement>());
  const listRef = useRef<HTMLOListElement>(null);
  const focusAfter = useRef<{ key: string; control: Control } | null>(null);
  const rowsRef = useRef(rows); rowsRef.current = rows;

  function edit(next: ThemeRow[], message: string) {
    setSaved(false); setNotice(null); runner.clearOutcome();
    rowsRef.current = next;
    setDraft({ version: data.version, rows: next });
    if (message) setAnnouncement(message);
  }
  const editRef = useRef(edit); editRef.current = edit;

  function move(key: string, delta: number, control: Control) {
    if (!editable) return;
    const next = moveThemeBy(rows, key, delta);
    if (next.every((row, index) => row.key === rows[index]?.key)) return;
    focusAfter.current = { key, control };
    edit(next, moveAnnouncement(next, key));
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
  function place() {
    const state = drag.current, list = listRef.current, row = state ? items.current.get(state.key) : undefined;
    if (!state || !list || !row) return;
    row.style.transform = `translateY(${state.clientY - list.getBoundingClientRect().top - state.grab - row.offsetTop}px)`;
  }
  useLayoutEffect(() => { if (drag.current) place(); });
  useEffect(() => () => teardown.current?.(), []);

  function startDrag(event: ReactPointerEvent<HTMLButtonElement>, key: string) {
    if (!editable || drag.current || (event.pointerType === 'mouse' && event.button !== 0)) return;
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
      if (target !== held) editRef.current(moveThemeTo(current, state.key, target), '');
      place();
    };
    const finish = (cancelled: boolean) => {
      const state = drag.current;
      teardown.current?.();
      if (!state) return;
      const node = items.current.get(state.key);
      if (node) node.style.transform = '';
      drag.current = null; setDragging(null);
      if (cancelled) { editRef.current(state.startRows, 'Déplacement annulé.'); return; }
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

  async function save() {
    if (!editable || !dirty || saved || problem) return;
    runner.clearOutcome(); setNotice(null); setSaved(false);
    const command = createCommand({ schoolId, kind: 'saveObservationThemes', path: 'observation-themes',
      ifMatch: data.version, resourceVersion: data.version, body: saveBody(rows) });
    const result = await runner.run(command, 'Les signalements sont enregistrés.');
    if (result.status === 'confirmed') { setSaved(true); return; }
    if (result.status !== 'rejected') return;
    if (result.code === 'VERSION_CONFLICT' || result.code === 'PRECONDITION_REQUIRED') {
      // Someone saved meanwhile: start again from their version, overwrite nothing.
      runner.clearOutcome(); setNotice('conflict'); setDraft(null); reload();
    } else if (['OBSERVATION_THEMES_ACCESS_REQUIRED', 'FORBIDDEN', 'ACCESS_DENIED'].includes(result.code)) {
      runner.clearOutcome(); setNotice('forbidden'); setDraft(null); reload();
    }
  }

  const status = runner.busy ? 'Enregistrement…' : runner.pending ? 'Résultat à vérifier' : saved ? 'Enregistré' : dirty ? 'Modifications non enregistrées' : null;
  const title = (key: string) => `${uid}-title-${key}`;
  const register = (key: string, control: Control) => (element: HTMLButtonElement | null) => {
    if (element) controls.current.set(`${key}:${control}`, element); else controls.current.delete(`${key}:${control}`);
  };

  return <>
    <header className="signals-heading">
      <div><h1>Signalements</h1><p className="signals-counter">{counterLabel(rows)}</p></div>
      {canManage && <DropdownMenu>
        <DropdownMenuTrigger render={<Button variant="outline" disabled={!editable || isDefaultConfiguration(rows)} />}><RotateCcw aria-hidden="true" />Réinitialiser<ChevronDown aria-hidden="true" /></DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-64">
          <DropdownMenuItem disabled={isDefaultOrder(rows)} onClick={() => edit(resetOrder(rows), 'Ordre d’origine rétabli.')}>Rétablir l’ordre d’origine</DropdownMenuItem>
          <DropdownMenuItem onClick={() => edit(resetAll(rows), 'Configuration d’origine rétablie.')}>Rétablir la configuration d’origine</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>}
    </header>
    <p className="sr-only" role="status" aria-live="polite">{announcement}</p>
    {!canManage && <Alert><AlertTitle>Lecture seule</AlertTitle><AlertDescription>Vos accès ne permettent pas de modifier les signalements.</AlertDescription></Alert>}
    {notice === 'conflict' && <Alert><AlertTitle>Configuration rechargée</AlertTitle><AlertDescription>Les signalements ont changé entre-temps ; vos modifications n’ont pas été enregistrées.</AlertDescription></Alert>}
    <CommandFeedback runner={runner} showSuccess={false} />

    <div className="signals-layout">
      <div className="signals-editor">
        {canManage && <p id={`${uid}-help`} className="sr-only">Faites glisser la poignée, ou utilisez les flèches haut et bas ; début et fin vont aux extrémités.</p>}
        <ol className={`signals-list${dragging ? ' is-dragging-list' : ''}`} ref={listRef} aria-label="Signalements, dans l’ordre d’affichage">
          {rows.map((row, index) => {
            const last = isLastVisible(rows, row.key);
            return <li key={row.key} ref={element => { if (element) items.current.set(row.key, element); else items.current.delete(row.key); }}
              className={`signals-row${row.visible ? '' : ' is-hidden'}${dragging === row.key ? ' is-dragging' : ''}`}>
              {canManage && <button type="button" className="signals-handle" ref={register(row.key, 'handle')} disabled={!editable}
                aria-label={`Déplacer ${row.title}, position ${index + 1} sur ${rows.length}`} aria-describedby={`${uid}-help`}
                onPointerDown={event => startDrag(event, row.key)} onKeyDown={event => onHandleKey(event, row.key)}><GripVertical aria-hidden="true" /></button>}
              <div className="signals-name"><ThemeIcon themeKey={row.key} /><span id={title(row.key)}>{row.title}</span></div>
              {canManage && <span className="signals-moves">
                <Button variant="ghost" size="icon" ref={register(row.key, 'up')} disabled={!editable || index === 0}
                  aria-label={`Monter ${row.title}`} onClick={() => move(row.key, -1, 'up')}><ChevronUp aria-hidden="true" /></Button>
                <Button variant="ghost" size="icon" ref={register(row.key, 'down')} disabled={!editable || index === rows.length - 1}
                  aria-label={`Descendre ${row.title}`} onClick={() => move(row.key, 1, 'down')}><ChevronDown aria-hidden="true" /></Button>
              </span>}
              <Switch checked={row.visible} disabled={!editable || last} aria-labelledby={title(row.key)} aria-describedby={last ? `${uid}-last` : undefined}
                onCheckedChange={() => { const next = toggleTheme(rows, row.key); edit(next, toggleAnnouncement(next, row.key)); }} />
            </li>;
          })}
        </ol>
        {canManage && onlyOneVisible && <p id={`${uid}-last`} className="signals-hint"><CircleAlert aria-hidden="true" />Au moins un signalement reste affiché.</p>}
      </div>

      <Collapsible open={previewOpen} onOpenChange={setPreviewOpen} className="signals-preview">
        <CollapsibleTrigger render={<Button variant="ghost" className="signals-preview-trigger" />}>
          Aperçu pour le moniteur<ChevronDown aria-hidden="true" className={previewOpen ? 'rotate-180' : undefined} />
        </CollapsibleTrigger>
        <CollapsibleContent>
          <ol className="signals-tiles" aria-label="Grille Signaler, dans l’ordre">
            {tiles.map(tile => <li key={tile.key}><ThemeIcon themeKey={tile.key} /><span>{tile.title}</span></li>)}
          </ol>
        </CollapsibleContent>
      </Collapsible>
    </div>

    {canManage && (dirty || status) && <div className="signals-savebar">
      <p role="status" aria-live="polite" className="signals-status">{saved && <Check aria-hidden="true" />}{status}</p>
      <div className="signals-actions">
        <Button variant="outline" disabled={!editable || !dirty || saved} onClick={() => { setDraft(null); setSaved(false); setAnnouncement('Modifications annulées.'); }}>Annuler</Button>
        <Button disabled={!editable || !dirty || saved || problem !== null} aria-busy={runner.busy} onClick={() => void save()}>Enregistrer</Button>
      </div>
    </div>}
  </>;
}
