import { useContext, useEffect, useId, useRef } from 'react';
import type { ReactNode } from 'react';
import { Loading, Notice, Symbol } from '../ui';
import { ConsoleContext, useConsole, type Loaded, type Outcome } from './context';
import { workspaces } from './navigation';

/** Section title. Receives focus when the section opens, so screen readers announce the new page. */
export function SectionHeading({ title, context, actions }: { title: string; context?: string; actions?: ReactNode }) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, []);
  return (
    <div className="section-head">
      <div className="section-head-text">
        {context && !workspaces.some(workspace => workspace.label === context) && <p className="context">{context}</p>}
        <h1 ref={heading} tabIndex={-1}>{title}</h1>
      </div>
      {actions && <div className="section-head-actions">{actions}</div>}
    </div>
  );
}

/** A refusal caused by the session (or a step-up demand) offers to sign in again; `beforeLogin` keeps the unsent form. */
export function OutcomeNotice({ outcome, onDismiss, actions, beforeLogin }: { outcome: Outcome; onDismiss?: () => void; actions?: ReactNode; beforeLogin?: () => void }) {
  const { login } = useConsole();
  if (!outcome) return null;
  const reconnect = outcome.needsLogin === true || outcome.code === 'REAUTH_REQUIRED';
  return (
    <Notice tone={outcome.tone} title={outcome.title} actions={<>
      {actions}
      {reconnect && <button type="button" className="button secondary" onClick={() => { beforeLogin?.(); login({ reauthenticate: outcome.code === 'REAUTH_REQUIRED' }); }}>Se reconnecter</button>}
      {onDismiss && outcome.tone === 'success' && <button type="button" className="button quiet" onClick={onDismiss}>Masquer</button>}
    </>}>
      <p>{outcome.message}</p>
    </Notice>
  );
}

/** The way out of a failed read: sign in again when the session ended (retrying could not succeed), retry otherwise. */
export function ReadRetry({ loaded }: { loaded: Pick<Loaded<unknown>, 'needsLogin' | 'reload'> }) {
  const shell = useContext(ConsoleContext);
  return loaded.needsLogin && shell
    ? <button type="button" className="button retry" onClick={() => shell.login()}><Symbol kind="lock" bare />Se reconnecter</button>
    : <button type="button" className="button retry" onClick={loaded.reload}><Symbol kind="refresh" bare />Réessayer</button>;
}

/** Loading, error and stale states of one read; `children` renders once data exists. */
export function LoadState<T>({ loaded, label, children }: { loaded: Loaded<T>; label: string; children: (data: T) => ReactNode }) {
  return <>
    {loaded.status === 'loading' && <Loading label={label} />}
    {loaded.status === 'error' && <Notice tone="error" title="Lecture impossible" actions={<ReadRetry loaded={loaded} />}>
      <p>{loaded.error}{loaded.data !== undefined ? ' Les informations affichées peuvent être anciennes.' : ''}</p>
    </Notice>}
    {loaded.data !== undefined && children(loaded.data)}
  </>;
}

/** List on the left, detail or form on the right; stacked on narrow screens. */
export function SplitView({ list, detail, mobileDetail = false, onBack, backLabel = 'Retour à la liste' }: {
  list: ReactNode; detail: ReactNode; mobileDetail?: boolean; onBack?: () => void; backLabel?: string;
}) {
  const listRef = useRef<HTMLDivElement>(null);
  const returnToList = () => {
    const selectedRow = listRef.current?.querySelector<HTMLElement>('[aria-current="true"]');
    onBack?.();
    window.requestAnimationFrame(() => {
      const target = selectedRow?.isConnected ? selectedRow : listRef.current?.querySelector<HTMLElement>('input,button,a,select') ?? listRef.current;
      target?.focus();
    });
  };
  return <div className={`split-view${onBack ? ' has-mobile-navigation' : ''}${mobileDetail ? ' shows-detail' : ''}`}>
    <div className="split-list" ref={listRef} tabIndex={-1}>{list}</div>
    <div className="split-detail">
      {onBack && mobileDetail && <button type="button" className="button quiet detail-back" onClick={returnToList}><Symbol kind="back" bare />{backLabel}</button>}
      {detail}
    </div>
  </div>;
}

/** Detail panel with a focusable title, so a selection from the list lands here for keyboard users. */
export function DetailPanel({ title, meta, badge, children, actions, focusKey }: {
  title: string; meta?: ReactNode; badge?: ReactNode; children: ReactNode; actions?: ReactNode; focusKey?: string;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  const first = useRef(true);
  const titleId = useId();
  useEffect(() => {
    if (first.current) { first.current = false; if (focusKey === undefined) return; }
    heading.current?.focus({ preventScroll: false });
  }, [focusKey]);
  return (
    <section className="detail-panel" aria-labelledby={titleId}>
      <div className="detail-head">
        <div className="row-text">
          <h2 id={titleId} ref={heading} tabIndex={-1}>{title}</h2>
          {meta && <p className="row-meta">{meta}</p>}
          {badge}
        </div>
      </div>
      <div className="detail-body">{children}</div>
      {actions && <div className="detail-actions">{actions}</div>}
    </section>
  );
}

export function Placeholder({ children }: { children: ReactNode }) {
  return <div className="detail-placeholder"><Symbol kind="info" /><p className="row-meta">{children}</p></div>;
}

/** Row selector inside a table: a real button, with the current row marked for assistive technology. */
export function RowButton({ selected, onSelect, children }: { selected: boolean; onSelect: () => void; children: ReactNode }) {
  return <button type="button" className="row-button" aria-current={selected ? 'true' : undefined} onClick={onSelect}>{children}</button>;
}
