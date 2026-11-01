import { useId, type ReactNode } from 'react';
import { ArrowRight, Info } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Field, FieldError, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Popover, PopoverContent, PopoverDescription, PopoverHeader, PopoverTitle, PopoverTrigger } from '../../components/ui/popover';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../components/ui/select';
import type { NavigationQuery, PeriodChoice } from '../../console/route';
import { describeComparison, describeReason, formatMeasure, type MeasureComparison } from './measure-format';
import type { MetricDefinition, MetricMeasure } from './metrics-api';
import { periodProblemMessage, type PeriodProblem } from './period-model';
import './pilotage.css';

/** Seul l'inhabituel porte un badge : une mesure complète n'en a pas. */
const coverageBadge = { PARTIAL: 'Partiel', UNAVAILABLE: 'Indisponible', NOT_APPLICABLE: 'Non applicable' } as const;

export interface MetricTileProps {
  label: string;
  measure: MetricMeasure;
  definition?: MetricDefinition | undefined;
  comparison?: MeasureComparison | undefined;
  /** Base déjà nommée de la comparaison (« par rapport à septembre 2026 »). */
  comparisonLabel?: string | undefined;
  action?: { label: string; onClick: () => void } | undefined;
  /** Identifiant du dictionnaire : permet de rendre le focus à la tuile quand on revient de son détail. */
  measureId?: string | undefined;
}

/** Une mesure du serveur : valeur lisible, état de couverture, comparaison nommée et accès à sa définition. */
export function MetricTile({ label, measure, definition, comparison, comparisonLabel, action, measureId }: MetricTileProps) {
  const status = measure.coverage.status;
  const change = describeComparison(comparison, measure.unit);
  return <li className="pilotage-tile" data-coverage={status} data-measure={measureId}>
    <div className="pilotage-tile-head">
      <h3>{label}</h3>
      <MeasureHelp label={label} measure={measure} definition={definition} />
    </div>
    <p className="pilotage-value">{formatMeasure(measure.value, measure.unit)}</p>
    {status !== 'COMPLETE' && <Badge variant="outline">{coverageBadge[status]}</Badge>}
    {change && comparisonLabel && <p className="pilotage-comparison">{change} <span>{comparisonLabel}</span></p>}
    {action && <Button variant="ghost" size="sm" className="pilotage-tile-action" onClick={action.onClick}>{action.label}<ArrowRight data-icon="inline-end" aria-hidden="true" /></Button>}
  </li>;
}

/** « Comment ce chiffre est calculé », à la demande : formule du dictionnaire et parts exclues par la couverture. */
function MeasureHelp({ label, measure, definition }: { label: string; measure: MetricMeasure; definition: MetricDefinition | undefined }) {
  const reasons = measure.coverage.reasons;
  if (!definition && reasons.length === 0) return null;
  return <Popover>
    <PopoverTrigger render={<Button variant="ghost" size="icon-sm" className="pilotage-help" aria-label={`Comment « ${label} » est calculé`} />}>
      <Info aria-hidden="true" />
    </PopoverTrigger>
    <PopoverContent align="end" className="pilotage-help-content">
      <PopoverHeader>
        <PopoverTitle>{label}</PopoverTitle>
        {definition && <PopoverDescription>{definition.formula}</PopoverDescription>}
      </PopoverHeader>
      {definition?.snapshot && <p>Valeur à l’instant du calcul, sans lien avec la période choisie.</p>}
      {reasons.length > 0 && <ul>{reasons.map(reason => <li key={reason.code}>{describeReason(reason.code, reason.count)}</li>)}</ul>}
    </PopoverContent>
  </Popover>;
}

/** Un bloc de page sous un titre ; le titre nomme la région pour les lecteurs d'écran. `action` se place à droite du titre. */
export function PilotageSection({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  const id = useId();
  return <section className="pilotage-section" aria-labelledby={id}>
    {action ? <div className="pilotage-section-head"><h2 id={id}>{title}</h2>{action}</div> : <h2 id={id}>{title}</h2>}
    {children}
  </section>;
}

/** Un groupe de mesures sous un titre. */
export function MetricSection({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return <PilotageSection title={title} action={action}><ul className="pilotage-grid">{children}</ul></PilotageSection>;
}

export interface FilterOption { value: string; label: string }
export type FilterPatch = { [Key in 'period' | 'start' | 'end' | 'instructor' | 'category' | 'product']?: NavigationQuery[Key] };
const periodOptions: readonly FilterOption[] = [
  { value: 'month', label: 'Ce mois' }, { value: 'previous-month', label: 'Mois dernier' },
  { value: 'year', label: 'Cette année' }, { value: 'custom', label: 'Période libre' },
];
const all = 'all';

/** Liste de choix « Tous / un élément » : sans élément à proposer, le filtre n'est pas affiché. */
function FilterSelect({ id, label, allLabel, value, options, onChange }: {
  id: string; label: string; allLabel: string; value: string | undefined; options: readonly FilterOption[]; onChange: (value: string | undefined) => void;
}) {
  if (options.length === 0) return null;
  const items: readonly FilterOption[] = [{ value: all, label: allLabel }, ...options];
  return <Field className="pilotage-filter">
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Select value={value ?? all} items={items} onValueChange={next => { if (next) onChange(next === all ? undefined : next); }}>
      <SelectTrigger id={id} aria-label={label}><SelectValue /></SelectTrigger>
      <SelectContent>{items.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
    </Select>
  </Field>;
}

/** Filtre « Toute l'équipe / un moniteur ». */
export function InstructorSelect({ value, options, onChange }: { value: string | undefined; options: readonly FilterOption[]; onChange: (value: string | undefined) => void }) {
  return <FilterSelect id="pilotage-instructor" label="Moniteur" allLabel="Toute l’équipe" value={value} options={options} onChange={onChange} />;
}

/**
 * Filtres communs des statistiques : une même adresse les porte, un lien vers une autre page les conserve.
 * Permis et prestation sont un second niveau : ils n'apparaissent que si le catalogue de l'école en propose.
 */
export function PilotageFilters({ query, instructors, categories, products, problem, onChange }: {
  query: NavigationQuery;
  instructors: readonly FilterOption[];
  categories: readonly FilterOption[];
  products: readonly FilterOption[];
  problem: PeriodProblem | null;
  onChange: (patch: FilterPatch) => void;
}) {
  const choice = query.period ?? 'month';
  return <div className="pilotage-filters" role="group" aria-label="Filtres des statistiques">
    <Field className="pilotage-filter">
      <FieldLabel htmlFor="pilotage-period">Période</FieldLabel>
      <Select value={choice} items={periodOptions} onValueChange={value => {
        if (!value) return;
        onChange({ period: value === 'month' ? undefined : value as PeriodChoice, ...(value === 'custom' ? {} : { start: undefined, end: undefined }) });
      }}>
        <SelectTrigger id="pilotage-period" aria-label="Période"><SelectValue /></SelectTrigger>
        <SelectContent>{periodOptions.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
      </Select>
    </Field>
    {choice === 'custom' && <>
      <Field className="pilotage-filter" data-invalid={problem !== null}>
        <FieldLabel htmlFor="pilotage-start">Premier jour</FieldLabel>
        <Input id="pilotage-start" type="date" value={query.start ?? ''} aria-invalid={problem !== null} onChange={event => onChange({ start: event.target.value || undefined })} />
      </Field>
      <Field className="pilotage-filter" data-invalid={problem !== null}>
        <FieldLabel htmlFor="pilotage-end">Dernier jour</FieldLabel>
        <Input id="pilotage-end" type="date" value={query.end ?? ''} aria-invalid={problem !== null} onChange={event => onChange({ end: event.target.value || undefined })} />
      </Field>
    </>}
    <InstructorSelect value={query.instructor} options={instructors} onChange={instructor => onChange({ instructor })} />
    <FilterSelect id="pilotage-category" label="Permis" allLabel="Tous les permis" value={query.category} options={categories} onChange={category => onChange({ category })} />
    <FilterSelect id="pilotage-product" label="Prestation" allLabel="Toutes les prestations" value={query.product} options={products} onChange={product => onChange({ product })} />
    {problem && <FieldError className="pilotage-filter-error" role="alert">{periodProblemMessage(problem)}</FieldError>}
  </div>;
}
