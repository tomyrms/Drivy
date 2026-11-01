import { useId, useRef, useState, type KeyboardEvent } from 'react';
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '../../components/ui/table';
import './pilotage.css';

/**
 * Histogramme empilé sans bibliothèque (#373) : un intervalle par barre, une série par couche. La distinction entre séries
 * ne repose pas sur la couleur seule (plein ou hachuré), la légende nomme chaque couche, un résumé dit les totaux, chaque barre
 * se lit au toucher, à la souris et au clavier (flèches, début, fin) et le tableau des valeurs est à portée de clavier.
 * Une valeur absente laisse un vide : elle n'est ni dessinée ni comptée comme zéro.
 */
export interface ChartBucket {
  key: string;
  /** Étiquette courte de l'axe. */
  label: string;
  /** Titre complet de l'intervalle, lu avec ses valeurs ; à défaut, l'étiquette. */
  title?: string;
  values: readonly (number | null)[];
}
export interface ChartSeries { label: string; pattern: 'solid' | 'hatch' }

const width = 640, height = 150, left = 60, top = 12, bottom = 22;

export interface StackedBar { key: string; x: number; width: number; slotX: number; slotWidth: number; layers: { y: number; height: number }[] }
/** Géométrie pure : l'échelle part de zéro et le plus haut total remplit la zone ; une barre vide a des couches de hauteur nulle. */
export function stackLayout(buckets: readonly ChartBucket[]): { bars: StackedBar[]; max: number } {
  const totals = buckets.map(bucket => bucket.values.reduce<number>((sum, value) => sum + (value ?? 0), 0));
  const max = Math.max(1, ...totals);
  const slot = (width - left) / Math.max(1, buckets.length), barWidth = Math.max(2, slot * 0.68);
  const scale = (height - top - bottom) / max;
  const bars = buckets.map((bucket, index) => {
    let y = height - bottom;
    const layers = bucket.values.map(value => {
      const layerHeight = Math.max(0, (value ?? 0) * scale);
      y -= layerHeight;
      return { y, height: layerHeight };
    });
    return { key: bucket.key, x: left + index * slot + (slot - barWidth) / 2, width: barWidth, slotX: left + index * slot, slotWidth: slot, layers };
  });
  return { bars, max };
}

const total = (buckets: readonly ChartBucket[], layer: number) => buckets.reduce((sum, bucket) => sum + (bucket.values[layer] ?? 0), 0);

export function StackedBars({ title, periodText, buckets, series, emptyText, format = String, tickFormat = String }: {
  title: string;
  periodText: string;
  buckets: readonly ChartBucket[];
  series: readonly ChartSeries[];
  emptyText: string;
  /** Écriture d'une valeur avec son unité (« 3 h 40 min ») ; par défaut le nombre brut. */
  format?: (value: number) => string;
  /** Écriture courte de l'échelle, à gauche du graphique (« 5 225 CHF ») ; par défaut le nombre brut. */
  tickFormat?: (value: number) => string;
}) {
  const id = useId().replace(/:/g, '');
  const hatch = `${id}-hatch`;
  const [active, setActive] = useState<number | null>(null);
  const [roving, setRoving] = useState(0);
  const bars = useRef<(SVGGElement | null)[]>([]);
  const layout = stackLayout(buckets);
  const totals = series.map((_, layer) => total(buckets, layer));
  const summary = `${title}, ${periodText} : ${series.map((item, layer) => `${format(totals[layer]!)} ${item.label.toLowerCase()}`).join(', ')}.`;
  const reading = (index: number) => {
    const bucket = buckets[index]!;
    return `${bucket.title ?? bucket.label} : ${series.map((item, layer) => {
      const value = bucket.values[layer];
      return `${value === null || value === undefined ? 'donnée absente' : format(value)} ${item.label.toLowerCase()}`;
    }).join(', ')}`;
  };
  const fill = (pattern: ChartSeries['pattern']) => pattern === 'solid' ? 'var(--primary)' : `url(#${hatch})`;
  const step = Math.max(1, Math.ceil(buckets.length / 6));
  const move = (to: number) => {
    const next = Math.max(0, Math.min(buckets.length - 1, to));
    setRoving(next); setActive(next); bars.current[next]?.focus();
  };
  const onKeyDown = (index: number) => (event: KeyboardEvent<SVGGElement>) => {
    const target = event.key === 'ArrowRight' ? index + 1 : event.key === 'ArrowLeft' ? index - 1 : event.key === 'Home' ? 0 : event.key === 'End' ? buckets.length - 1 : null;
    if (target === null) return;
    event.preventDefault(); move(target);
  };
  return <figure className="pilotage-chart">
    <figcaption><h3>{title}</h3><span>{periodText}</span></figcaption>
    {totals.every(value => value === 0)
      ? <p className="pilotage-chart-empty">{emptyText}</p>
      : <>
        <svg viewBox={`0 0 ${width} ${height}`} role="group" aria-label={summary} className="pilotage-chart-svg">
          <defs>
            <pattern id={hatch} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
              <rect width="6" height="6" fill="var(--card)" /><line x1="0" y1="0" x2="0" y2="6" stroke="var(--primary)" strokeWidth="2.5" />
            </pattern>
          </defs>
          <line x1={left} x2={width} y1={height - bottom} y2={height - bottom} stroke="var(--border)" />
          <text x={0} y={top + 4} className="pilotage-chart-tick">{tickFormat(layout.max)}</text>
          <text x={0} y={height - bottom} className="pilotage-chart-tick">0</text>
          {layout.bars.map((bar, index) => <g key={bar.key} ref={node => { bars.current[index] = node; }} role="img" aria-label={reading(index)}
            tabIndex={index === roving ? 0 : -1} data-active={active === index} className="pilotage-chart-bar"
            onFocus={() => { setRoving(index); setActive(index); }} onBlur={() => setActive(null)}
            onMouseEnter={() => setActive(index)} onMouseLeave={() => setActive(null)} onClick={() => setActive(index)} onKeyDown={onKeyDown(index)}>
            <rect className="pilotage-chart-hit" x={bar.slotX} y={top} width={bar.slotWidth} height={height - top - bottom} />
            {bar.layers.map((layer, layerIndex) => layer.height > 0 && <rect key={layerIndex} x={bar.x} y={layer.y} width={bar.width} height={layer.height}
              fill={fill(series[layerIndex]!.pattern)} stroke="var(--primary)" strokeWidth="1" />)}
            {(index % step === 0 || index === layout.bars.length - 1) && <text x={bar.x + bar.width / 2} y={height - 6} textAnchor="middle" className="pilotage-chart-tick">{buckets[index]!.label}</text>}
          </g>)}
        </svg>
        <p className="pilotage-chart-readout" aria-live="polite">{active === null ? ' ' : reading(active)}</p>
        <ul className="pilotage-legend">
          {series.map(item => <li key={item.label}>
            <svg width="14" height="14" aria-hidden="true"><rect x="1" y="1" width="12" height="12" fill={fill(item.pattern)} stroke="var(--primary)" strokeWidth="1" /></svg>
            {item.label}
          </li>)}
        </ul>
        <details className="pilotage-chart-values">
          <summary>Voir les valeurs</summary>
          <Table>
            <TableCaption>{summary}</TableCaption>
            <TableHeader><TableRow><TableHead scope="col">Intervalle</TableHead>{series.map(item => <TableHead scope="col" key={item.label}>{item.label}</TableHead>)}</TableRow></TableHeader>
            <TableBody>{buckets.map(bucket => <TableRow key={bucket.key}>
              <TableHead scope="row">{bucket.title ?? bucket.label}</TableHead>
              {series.map((item, layer) => <TableCell key={item.label}>{bucket.values[layer] === null || bucket.values[layer] === undefined ? '—' : format(bucket.values[layer]!)}</TableCell>)}
            </TableRow>)}</TableBody>
          </Table>
        </details>
      </>}
  </figure>;
}
