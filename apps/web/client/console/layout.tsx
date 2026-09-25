import { useEffect, useRef } from 'react';
import type { ReactNode } from 'react';
import { Loading, Notice, Symbol } from '../ui';
import type { Loaded, Outcome } from './context';

/** Section title. Receives focus when the section opens, so screen readers announce the new page. */
export function SectionHeading({ title, context, description, actions }: { title: string; context?: string; description?: string; actions?: ReactNode }) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, []);
  return (
    <div className="section-head">
      <div className="section-head-text">
        {context && <p className="context">{context}</p>}
        <h1 ref={heading} tabIndex={-1}>{title}</h1>
        {description && <p className="lead">{description}</p>}
      </div>
      {actions && <div className="section-head-actions">{actions}</div>}
    </div>
  );
}

export function OutcomeNotice({ outcome, onDismiss, actions }: { outcome: Outcome; onDismiss?: () => void; actions?: ReactNode }) {
  if (!outcome) return null;
  return (
    <Notice tone={outcome.tone} title={outcome.title} actions={<>
      {actions}
      {onDismiss && outcome.tone === 'success' && <button type="button" className="button quiet" onClick={onDismiss}>Masquer</button>}
    </>}>
      <p>{outcome.message}</p>
    </Notice>
  );
}

/** Loading, error and stale states of one read; `children` renders once data exists. */
export function LoadState<T>({ loaded, label, children }: { loaded: Loaded<T>; label: string; children: (data: T) => ReactNode }) {
  return <>
    {loaded.status === 'loading' && <Loading label={label} />}
    {loaded.status === 'error' && <Notice tone="error" title="Lecture impossible"
      actions={<button type="button" className="button retry" onClick={loaded.reload}><Symbol kind="refresh" bare />Réessayer</button>}>
      <p>{loaded.error}{loaded.data !== undefined ? ' Les informations affichées peuvent être anciennes.' : ''}</p>
    </Notice>}
    {loaded.data !== undefined && children(loaded.data)}
  </>;
}

/** List on the left, detail or form on the right; stacked on narrow screens. */
export function SplitView({ list, detail }: { list: ReactNode; detail: ReactNode }) {
  return <div className="split-view"><div className="split-list">{list}</div><div className="split-detail">{detail}</div></div>;
}

/** Detail panel with a focusable title, so a selection from the list lands here for keyboard users. */
export function DetailPanel({ title, meta, badge, children, actions, focusKey }: {
  title: string; meta?: ReactNode; badge?: ReactNode; children: ReactNode; actions?: ReactNode; focusKey?: string;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; if (focusKey === undefined) return; }
    heading.current?.focus({ preventScroll: false });
  }, [focusKey]);
  return (
    <section className="detail-panel" aria-labelledby="detail-title">
      <div className="detail-head">
        <div className="row-text">
          <h2 id="detail-title" ref={heading} tabIndex={-1}>{title}</h2>
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
