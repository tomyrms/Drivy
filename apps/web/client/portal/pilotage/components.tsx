import { useId, type ReactNode } from 'react';
import { ArrowRight, ChevronRight, Info } from 'lucide-react';
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
export const coverageBadge = { PARTIAL: 'Partiel', UNAVAILABLE: 'Indisponible', NOT_APPLICABLE: 'Non applicable' } as const;

export interface MeasureRowProps {
  label: string;
  measure: MetricMeasure;
  definition?: MetricDefinition | undefined;
  comparison?: MeasureComparison | undefined;
  /** Base déjà nommée de la comparaison (« vs le 1er octobre »). */
  comparisonLabel?: string | undefined;
  /** Ouvre les lignes de la mesure : la valeur devient le bouton, chevron à droite. */
  onOpen?: (() => void) | undefined;
  /** Action d'une autre nature (ouvrir l'agenda) : un bouton nommé, la valeur reste du texte. */
  action?: { label: string; onClick: () => void } | undefined;
  /** Précision courte après le libellé (« hors du total »). */
  note?: string | undefined;
  /** `term` : terme d'une somme, précédé d'un signe ; `total` : la somme, sous un filet ; `outside` : lue à part, après le total. */
  position?: 'term' | 'total' | 'outside' | undefined;
  /** Identifiant du dictionnaire : permet de rendre le focus à la ligne quand on revient de son détail. */
  measureId?: string | undefined;
}

/**
 * Une mesure du serveur, en ligne de relevé : libellé à gauche, valeur alignée à droite pour se comparer d'une ligne à l'autre,
 * comparaison nommée sous la valeur (sous le libellé sur un téléphone). La définition s'ouvre à la demande, le détail depuis la valeur.
 */
export function MeasureRow({ label, measure, definition, comparison, comparisonLabel, onOpen, action, note, position, measureId }: MeasureRowProps) {
  const status = measure.coverage.status;
  const change = describeComparison(comparison, measure.unit);
  const value = formatMeasure(measure.value, measure.unit);
  return <li className="pilotage-row" data-coverage={status} data-measure={measureId} data-role={position}>
    <div className="pilotage-row-label">
      <span className="pilotage-row-name">{label}</span>
      <MeasureHelp label={label} measure={measure} definition={definition} />
      {note && <span className="pilotage-row-note">{note}</span>}
      {status !== 'COMPLETE' && <Badge variant="outline">{coverageBadge[status]}</Badge>}
    </div>
    {change && comparisonLabel && <p className="pilotage-row-change">{change} <span>{comparisonLabel}</span></p>}
    <div className="pilotage-row-value">
      {position === 'term' && <span className="pilotage-row-sign" aria-hidden="true">+</span>}
      {onOpen
        ? <Button variant="ghost" size="sm" className="pilotage-row-open" onClick={onOpen} aria-label={`${label} : ${value}. Voir le détail`}>
          <span>{value}</span><ChevronRight data-icon="inline-end" aria-hidden="true" />
        </Button>
        : <span className="pilotage-row-figure">{value}</span>}
    </div>
    {action && <Button variant="ghost" size="sm" className="pilotage-row-action" onClick={action.onClick}>{action.label}<ArrowRight data-icon="inline-end" aria-hidden="true" /></Button>}
  </li>;
}

/** « Comment ce chiffre est calculé », à la demande : formule du dictionnaire et parts exclues par la couverture. */
function MeasureHelp({ label, measure, definition }: { label: string; measure: MetricMeasure; definition: MetricDefinition | undefined }) {
  const reasons = measure.coverage.reasons;
  if (!definition && reasons.length === 0) return null;
  return <Popover>
    <PopoverTrigger render={<Button variant="ghost" size="icon-xs" className="pilotage-help" aria-label={`Comment « ${label} » est calculé`} />}>
      <Info aria-hidden="true" />
    </PopoverTrigger>
    <PopoverContent align="start" className="pilotage-help-content">
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
export function PilotageSection({ title, action, children, className }: { title: string; action?: ReactNode; children: ReactNode; className?: string }) {
  const id = useId();
  return <section className={className ? `pilotage-section ${className}` : 'pilotage-section'} aria-labelledby={id}>
    <div className="pilotage-section-head"><h2 id={id}>{title}</h2>{action}</div>
    {children}
  </section>;
}

/** Des lignes de relevé sous un titre. */
export function MeasureList({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return <PilotageSection title={title} action={action}><ul className="pilotage-rows">{children}</ul></PilotageSection>;
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
