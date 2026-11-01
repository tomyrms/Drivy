import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react';
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

const defaultWidth = 640, height = 150, left = 60, top = 12, bottom = 22;

/**
 * Graduation lisible : au plus quatre intervalles d'un pas rond (1, 2 ou 5 fois une puissance de dix, jamais sous 1),
 * et un sommet qui couvre la plus haute valeur. Les valeurs étant des entiers (leçons, secondes, centimes), chaque graduation l'est aussi.
 */
export function niceScale(peak: number): { max: number; ticks: number[] } {
  if (peak <= 1) return { max: 1, ticks: [0, 1] };
  const power = 10 ** Math.floor(Math.log10(peak));
  const step = [1, 2, 5, 10].map(factor => factor * power).find(candidate => Math.ceil(peak / candidate) <= 4) ?? power * 10;
  const intervals = Math.ceil(peak / step);
  return { max: step * intervals, ticks: Array.from({ length: intervals + 1 }, (_, index) => index * step) };
}

export interface StackedBar { key: string; x: number; width: number; slotX: number; slotWidth: number; layers: { y: number; height: number }[] }
/** Géométrie pure : l'échelle part de zéro et monte à la graduation qui couvre le plus haut total ; une barre vide a des couches de hauteur nulle. */
export function stackLayout(buckets: readonly ChartBucket[], width = defaultWidth): { bars: StackedBar[]; max: number; ticks: number[] } {
  const totals = buckets.map(bucket => bucket.values.reduce<number>((sum, value) => sum + (value ?? 0), 0));
  const { max, ticks } = niceScale(Math.max(1, ...totals));
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
  return { bars, max, ticks };
}

const total = (buckets: readonly ChartBucket[], layer: number) => buckets.reduce((sum, bucket) => sum + (bucket.values[layer] ?? 0), 0);

export function StackedBars({ title, note, periodText, buckets, series, emptyText, format = String, tickFormat = String }: {
  title: string;
  /** Précision visible sous le titre quand elle change la lecture (« Par date de saisie ») ; la période, elle, est dite une fois par la page. */
  note?: string;
  /** Période lue, reprise dans le résumé et le tableau des valeurs. */
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
  // Le dessin prend la largeur réelle de son cadre : les chiffres de l'axe gardent leur corps sur un téléphone au lieu d'être réduits avec l'image.
  const frame = useRef<HTMLElement>(null);
  const [width, setWidth] = useState(defaultWidth);
  useEffect(() => {
    const node = frame.current;
    if (!node || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(entries => { const next = Math.floor(entries[0]?.contentRect.width ?? defaultWidth); if (next >= 200) setWidth(next); });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const layout = stackLayout(buckets, width);
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
  const yOf = (value: number) => height - bottom - (value / layout.max) * (height - top - bottom);
  const step = Math.max(1, Math.ceil(buckets.length / Math.max(2, Math.floor(width / 64))));
  const move = (to: number) => {
    const next = Math.max(0, Math.min(buckets.length - 1, to));
    setRoving(next); setActive(next); bars.current[next]?.focus();
  };
  const onKeyDown = (index: number) => (event: KeyboardEvent<SVGGElement>) => {
    const target = event.key === 'ArrowRight' ? index + 1 : event.key === 'ArrowLeft' ? index - 1 : event.key === 'Home' ? 0 : event.key === 'End' ? buckets.length - 1 : null;
    if (target === null) return;
    event.preventDefault(); move(target);
  };
  const swatch = (pattern: ChartSeries['pattern']) => <svg width="14" height="14" aria-hidden="true"><rect x="1" y="1" width="12" height="12" rx="2" fill={fill(pattern)} stroke="var(--primary)" strokeWidth="1" /></svg>;
  return <figure ref={frame} className="pilotage-chart">
    <figcaption>
      <div className="pilotage-chart-title"><h3>{title}</h3>{note && <p>{note}</p>}</div>
    </figcaption>
    {totals.every(value => value === 0)
      ? <p className="pilotage-chart-empty">{emptyText}</p>
      : <>
        <div className="pilotage-chart-frame">
          <svg viewBox={`0 0 ${width} ${height}`} width={width} height={height} role="group" aria-label={summary} className="pilotage-chart-svg">
            <defs>
              <pattern id={hatch} width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                <rect width="5" height="5" fill="var(--accent)" /><line x1="0" y1="0" x2="0" y2="5" stroke="var(--primary)" strokeWidth="1.5" />
              </pattern>
            </defs>
            {layout.ticks.map(tick => <g key={tick} aria-hidden="true">
              <line x1={left} x2={width} y1={yOf(tick)} y2={yOf(tick)} className={tick === 0 ? 'pilotage-chart-axis' : 'pilotage-chart-grid'} />
              <text x={left - 8} y={yOf(tick) + 4} textAnchor="end" className="pilotage-chart-tick">{tick === 0 ? '0' : tickFormat(tick)}</text>
            </g>)}
            {layout.bars.map((bar, index) => <g key={bar.key} ref={node => { bars.current[index] = node; }} role="img" aria-label={reading(index)}
              tabIndex={index === roving ? 0 : -1} data-active={active === index} className="pilotage-chart-bar"
              onFocus={() => { setRoving(index); setActive(index); }} onBlur={() => setActive(null)}
              onMouseEnter={() => setActive(index)} onMouseLeave={() => setActive(null)} onClick={() => setActive(index)} onKeyDown={onKeyDown(index)}>
              <rect className="pilotage-chart-hit" x={bar.slotX} y={top} width={bar.slotWidth} height={height - top - bottom} />
              {bar.layers.map((layer, layerIndex) => layer.height > 0 && <rect key={layerIndex} x={bar.x} y={layer.y} width={bar.width} height={layer.height}
                fill={fill(series[layerIndex]!.pattern)} stroke={series[layerIndex]!.pattern === 'hatch' ? 'var(--primary)' : 'none'} strokeWidth="1" />)}
              {(index % step === 0 || index === layout.bars.length - 1) && <text x={bar.x + bar.width / 2} y={height - 6} textAnchor="middle" className="pilotage-chart-tick">{buckets[index]!.label}</text>}
            </g>)}
          </svg>
        </div>
        {/* Une seule ligne sous le dessin : la légende au repos, la lecture de la barre touchée ou survolée, qui nomme elle-même ses séries. */}
        <div className="pilotage-chart-foot">
          {active === null
            ? <ul className="pilotage-legend">{series.map(item => <li key={item.label}>{swatch(item.pattern)}{item.label}</li>)}</ul>
            : <p className="pilotage-chart-readout" aria-hidden="true">{reading(active)}</p>}
        </div>
        <p className="sr-only" aria-live="polite">{active === null ? '' : reading(active)}</p>
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
