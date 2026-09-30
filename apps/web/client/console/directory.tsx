import type { ReactNode } from 'react';
import { Symbol } from '../ui';

/** A directory entry selects its detail. The entire row is one native keyboard target. */
export function DirectoryRow({ title, meta, detail, badge, selected, onSelect }: {
  title: string; meta?: ReactNode; detail?: ReactNode; badge?: ReactNode; selected: boolean; onSelect: () => void;
}) {
  return <li className="directory-item">
    <button type="button" className="directory-row" aria-current={selected ? 'true' : undefined} onClick={onSelect}>
      <span className="directory-identity"><span className="row-title">{title}</span>
        {meta && <span className="row-meta">{meta}</span>}{badge}
      </span>
      {detail && <span className="directory-detail">{detail}</span>}
      <span className="directory-arrow" aria-hidden="true"><Symbol kind="back" bare /></span>
    </button>
  </li>;
}
