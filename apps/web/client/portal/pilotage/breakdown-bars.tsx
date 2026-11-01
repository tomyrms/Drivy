import type { ReactNode } from 'react';
import type { BreakdownRow } from './chart-model';
import './pilotage.css';

/**
 * Répartition d'une mesure en barres horizontales (#378). La valeur est écrite à côté de chaque barre : la lecture ne dépend ni de la
 * couleur ni du survol. Les lignes arrivent déjà rangées par nom ; la longueur compare la charge, elle ne classe personne.
 */
export function BreakdownBars({ title, periodText, rows, format, emptyText, action }: {
  title: string;
  periodText: string;
  rows: readonly BreakdownRow[];
  format: (value: number) => string;
  emptyText: string;
  /** Commande propre au graphique, par exemple le choix de la répartition. */
  action?: ReactNode;
}) {
  const max = Math.max(1, ...rows.map(row => row.value));
  return <figure className="pilotage-chart">
    <figcaption><h3>{title}</h3><span>{periodText}</span></figcaption>
    {action}
    {rows.length === 0
      ? <p className="pilotage-chart-empty">{emptyText}</p>
      : <ul className="pilotage-breakdown">{rows.map(row => <li key={row.key}>
        <span className="pilotage-breakdown-label">{row.label}</span>
        <span className="pilotage-breakdown-bar" aria-hidden="true"><span style={{ width: `${Math.max(2, Math.round((row.value / max) * 100))}%` }} /></span>
        <span className="pilotage-breakdown-value">{format(row.value)}</span>
      </li>)}</ul>}
  </figure>;
}
