import type { ReactNode } from 'react';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group';
import type { BreakdownRow } from './chart-model';
import './pilotage.css';

/**
 * Répartition d'une mesure en barres horizontales (#378). La valeur est écrite à côté de chaque barre : la lecture ne dépend ni de la
 * couleur ni du survol. Les lignes arrivent déjà rangées par nom ; la longueur compare la charge, elle ne classe personne.
 */
export function BreakdownBars({ title, periodText, rows, format, emptyText, action, notice }: {
  title: string;
  /** Période lue, dite aux lecteurs d'écran avec le titre ; la page l'affiche déjà une fois. */
  periodText: string;
  /** `null` tant que la répartition n'est pas lue : seul l'avis (chargement, erreur) s'affiche. */
  rows: readonly BreakdownRow[] | null;
  format: (value: number) => string;
  emptyText: string;
  /** Commande propre au graphique, par exemple le choix de la répartition. */
  action?: ReactNode;
  /** Chargement ou erreur d'une mise à jour : les lignes déjà lues restent affichées sous cet avis. */
  notice?: ReactNode;
}) {
  const max = Math.max(1, ...(rows ?? []).map(row => row.value));
  return <figure className="pilotage-chart" aria-label={`${title}, ${periodText}`}>
    <figcaption><h3>{title}</h3>{action}</figcaption>
    {notice}
    {rows !== null && (rows.length === 0
      ? <p className="pilotage-chart-empty">{emptyText}</p>
      : <ul className="pilotage-breakdown">{rows.map(row => <li key={row.key}>
        <span className="pilotage-breakdown-label">{row.label}</span>
        <span className="pilotage-breakdown-bar" aria-hidden="true"><span style={{ width: `${Math.max(2, Math.round((row.value / max) * 100))}%` }} /></span>
        <span className="pilotage-breakdown-value">{format(row.value)}</span>
      </li>)}</ul>)}
  </figure>;
}

/** Choix de la répartition d'un graphique : le même contrôle segmenté que Jour / Semaine dans l'agenda. */
export function BreakdownChoice<Value extends string>({ label, value, options, onChange }: {
  label: string;
  value: Value;
  options: readonly { value: Value; label: string }[];
  onChange: (value: Value) => void;
}) {
  return <ToggleGroup className="pilotage-choice" variant="outline" aria-label={label} value={[value]}
    onValueChange={values => { const next = options.find(option => option.value === values[0]); if (next) onChange(next.value); }}>
    {options.map(option => <ToggleGroupItem key={option.value} value={option.value}>{option.label}</ToggleGroupItem>)}
  </ToggleGroup>;
}
