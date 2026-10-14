import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent, PointerEvent as ReactPointerEvent } from 'react';
import { createCommand } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { readObservationThemes, type ObservationThemes } from '../school-api';
import { Notice, Symbol } from '../ui';
import { useCommandRunner, useConsole, useLoad, useSectionDraft } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import {
  counterLabel, draftProblem, dropIndex, isDefaultConfiguration, isDefaultOrder, isDirty, isLastVisible, moveAnnouncement, moveThemeBy, moveThemeTo,
  previewTiles, resetAll, resetOrder, saveBody, settingsOf, toggleAnnouncement, toggleTheme, type ThemeRow,
} from './observation-themes-model';
import { ThemeIcon } from './theme-icons';

type Draft = { version: number; rows: ThemeRow[] };
type Control = 'handle' | 'up' | 'down';
const toRow = (theme: ObservationThemes['themes'][number]): ThemeRow => ({
  key: theme.key, title: theme.title, visible: theme.visible, defaultVisible: theme.defaultVisible, defaultPosition: theme.defaultPosition,
});

/** Signalements de la leçon : ordre et affichage des thèmes, réglés pour toute l'école et versionnés (If-Match). */
export function ObservationThemesSection() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readObservationThemes(schoolId), [schoolId, revision]);
  return (
    <div className="section-stack">
      <SectionHeading context="Réglages" title="Signalements" />
      <LoadState loaded={loaded} label="Lecture des signalements…">{data => <ThemesEditor data={data} reload={loaded.reload} />}</LoadState>
    </div>
  );
}

function ThemesEditor({ data, reload }: { data: ObservationThemes; reload: () => void }) {
  const { schoolId } = useConsole();
  const uid = useId();
  const [saved, setSaved] = useState(false);
  const runner = useCommandRunner(() => setSaved(true));
  const baseline = useMemo(() => data.themes.map(toRow), [data]);
  const [draft, setDraft] = useSectionDraft<Draft>('observation-themes', candidate =>
    !saved && candidate.version === data.version && isDirty(settingsOf(candidate.rows), settingsOf(baseline)));
  const [notice, setNotice] = useState<'conflict' | 'forbidden' | null>(null);
  const [announcement, setAnnouncement] = useState('');
  const [dragging, setDragging] = useState<string | null>(null);

  // Un brouillon d'une version plus ancienne n'est jamais rejoué sur une configuration plus récente.
  const rows = draft && draft.version === data.version ? draft.rows : baseline;
  const dirty = isDirty(settingsOf(rows), settingsOf(baseline));
  const canManage = data.canManage && notice !== 'forbidden';
  const editable = canManage && !runner.pending && !runner.busy;
  const problem = draftProblem(rows);
  const tiles = previewTiles(rows);

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

  /* ---------- Clavier et boutons ---------- */
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
  // Déplacer un nœud qui a le focus le lui retire : on le rend à la commande utilisée (la poignée si elle ne peut plus servir).
  useLayoutEffect(() => {
    const target = focusAfter.current;
    if (!target) return;
    focusAfter.current = null;
    let element = controls.current.get(`${target.key}:${target.control}`);
    if (!element || element.disabled) element = controls.current.get(`${target.key}:handle`);
    element?.focus();
  });

  /* ---------- Glisser-déposer (souris, toucher, stylet) ---------- */
  const drag = useRef<{ key: string; grab: number; clientY: number; startRows: ThemeRow[] } | null>(null);
  const teardown = useRef<(() => void) | null>(null);
  function place() {
    const state = drag.current, list = listRef.current, row = state ? items.current.get(state.key) : undefined;
    if (!state || !list || !row) return;
    row.style.transform = `translateY(${state.clientY - list.getBoundingClientRect().top - state.grab - row.offsetTop}px)`;
  }
  // La rangée tenue suit le pointeur : après chaque réordonnancement, sa place d'origine a changé.
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

  /* ---------- Enregistrement ---------- */
  async function save() {
    if (!editable || !dirty || saved || problem) return;
    runner.clearOutcome(); setNotice(null); setSaved(false);
    const command = createCommand({ schoolId, kind: 'saveObservationThemes', path: 'observation-themes',
      ifMatch: data.version, resourceVersion: data.version, body: saveBody(rows) });
    const result = await runner.run(command, 'Les signalements sont enregistrés.');
    if (result.status === 'confirmed') { setSaved(true); return; }
    if (result.status !== 'rejected') return;
    if (result.code === 'VERSION_CONFLICT' || result.code === 'PRECONDITION_REQUIRED') {
      // Quelqu'un a enregistré entre-temps : on repart de sa version, sans rien écraser.
      runner.clearOutcome(); setNotice('conflict'); setDraft(null); reload();
    } else if (['OBSERVATION_THEMES_ACCESS_REQUIRED', 'FORBIDDEN', 'ACCESS_DENIED'].includes(result.code)) {
      runner.clearOutcome(); setNotice('forbidden'); setDraft(null); reload();
    }
  }

  const status = runner.busy ? { text: 'Enregistrement en cours…', tone: 'busy' }
    : runner.pending ? { text: 'Résultat à vérifier', tone: 'warning' }
    : saved ? { text: 'Enregistré', tone: 'success' }
    : dirty ? { text: 'Modifications non enregistrées', tone: 'warning' }
    : { text: 'Aucune modification', tone: 'neutral' };
  const title = (key: string) => `${uid}-title-${key}`;
  const register = (key: string, control: Control) => (element: HTMLButtonElement | null) => {
    if (element) controls.current.set(`${key}:${control}`, element); else controls.current.delete(`${key}:${control}`);
  };

  return <>
    <p className="visually-hidden" role="status" aria-live="polite">{announcement}</p>
    {!canManage && <Notice tone="info" title="Lecture seule" live={false}><p>Vos accès ne permettent pas de modifier les signalements.</p></Notice>}
    {notice === 'conflict' && <Notice tone="warning" title="Configuration rechargée"><p>Les signalements ont changé entre-temps : la configuration est rechargée et vos modifications n’ont pas été enregistrées.</p></Notice>}
    {/* Le succès se lit dans l'état d'enregistrement : pas de second message. */}
    <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
    {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

    <div className="themes-layout">
      <section className="themes-editor" aria-labelledby={`${uid}-order`}>
        <div className="themes-toolbar">
          <h2 id={`${uid}-order`} className="section-title">Ordre et affichage</h2>
          <p className="themes-counter">{counterLabel(rows)}</p>
        </div>
        {canManage && <div className="themes-resets">
          <button type="button" className="button quiet" disabled={!editable || isDefaultOrder(rows)}
            onClick={() => edit(resetOrder(rows), 'Ordre d’origine rétabli.')}>Réinitialiser l’ordre</button>
          <button type="button" className="button quiet" disabled={!editable || isDefaultConfiguration(rows)}
            onClick={() => edit(resetAll(rows), 'Configuration d’origine rétablie.')}>Rétablir la configuration d’origine</button>
        </div>}
        {canManage && <p id={`${uid}-help`} className="visually-hidden">Faites glisser la poignée, ou utilisez les flèches haut et bas ; début et fin vont aux extrémités.</p>}
        <ol className={`theme-list${dragging ? ' is-dragging-list' : ''}`} ref={listRef} aria-label="Signalements, dans l’ordre d’affichage">
          {rows.map((row, index) => {
            const last = isLastVisible(rows, row.key);
            return <li key={row.key} ref={element => { if (element) items.current.set(row.key, element); else items.current.delete(row.key); }}
              className={`theme-row${row.visible ? '' : ' is-hidden'}${dragging === row.key ? ' is-dragging' : ''}`}>
              {canManage && <button type="button" className="theme-handle" ref={register(row.key, 'handle')} disabled={!editable}
                aria-label={`Déplacer ${row.title}, position ${index + 1} sur ${rows.length}`} aria-describedby={`${uid}-help`}
                onPointerDown={event => startDrag(event, row.key)} onKeyDown={event => onHandleKey(event, row.key)}><Symbol kind="grip" bare /></button>}
              <ThemeIcon themeKey={row.key} />
              <span id={title(row.key)} className="theme-title">{row.title}</span>
              {canManage && <span className="theme-moves">
                <button type="button" className="button quiet" ref={register(row.key, 'up')} disabled={!editable || index === 0}
                  aria-label={`Monter ${row.title}`} onClick={() => move(row.key, -1, 'up')}><Symbol kind="chevron-up" bare /></button>
                <button type="button" className="button quiet" ref={register(row.key, 'down')} disabled={!editable || index === rows.length - 1}
                  aria-label={`Descendre ${row.title}`} onClick={() => move(row.key, 1, 'down')}><Symbol kind="chevron" bare /></button>
              </span>}
              <label className="theme-switch">
                <input type="checkbox" role="switch" checked={row.visible} disabled={!editable || last} aria-labelledby={title(row.key)}
                  aria-describedby={last ? `${uid}-last` : undefined}
                  onChange={() => { const next = toggleTheme(rows, row.key); edit(next, toggleAnnouncement(next, row.key)); }} />
                <span className="theme-switch-text" aria-hidden="true">{row.visible ? 'Affiché' : 'Masqué'}</span>
              </label>
            </li>;
          })}
        </ol>
        {canManage && visibleOnly(rows) && <p id={`${uid}-last`} className="caption with-symbol"><Symbol kind="info" bare />Au moins un signalement reste affiché.</p>}
      </section>

      <section className="theme-preview" aria-labelledby={`${uid}-preview`}>
        <h2 id={`${uid}-preview`} className="section-title">Aperçu pour le moniteur</h2>
        <ol className="theme-tiles" aria-label="Grille Signaler, dans l’ordre">
          {tiles.map(tile => <li key={tile.key} className="theme-tile"><ThemeIcon themeKey={tile.key} /><span>{tile.title}</span></li>)}
        </ol>
      </section>
    </div>

    {canManage && <div className="themes-savebar">
      <p className={`themes-status ${status.tone}`} role="status" aria-live="polite">
        {status.tone === 'busy' ? <span className="spinner" aria-hidden="true" /> : status.tone === 'success' ? <Symbol kind="check" bare /> : status.tone === 'warning' ? <Symbol kind="alert" bare /> : null}
        {status.text}
      </p>
      <div className="button-row compact">
        <button type="button" className="button primary" disabled={!editable || !dirty || saved || problem !== null} aria-busy={runner.busy} onClick={() => void save()}>Enregistrer</button>
        <button type="button" className="button quiet" disabled={!editable || !dirty || saved} onClick={() => { setDraft(null); setSaved(false); setAnnouncement('Modifications annulées.'); }}>Annuler les modifications</button>
      </div>
    </div>}
  </>;
}

/** Un seul thème affiché : la commande qui le masquerait est indisponible, et la page le dit. */
const visibleOnly = (rows: readonly ThemeRow[]): boolean => rows.filter(row => row.visible).length === 1;
