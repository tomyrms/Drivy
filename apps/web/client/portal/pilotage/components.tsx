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
}

/** Une mesure du serveur : valeur lisible, état de couverture, comparaison nommée et accès à sa définition. */
export function MetricTile({ label, measure, definition, comparison, comparisonLabel, action }: MetricTileProps) {
  const status = measure.coverage.status;
  const change = describeComparison(comparison, measure.unit);
  return <li className="pilotage-tile" data-coverage={status}>
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

/** Un groupe de mesures sous un titre ; le titre nomme la liste pour les lecteurs d'écran. */
export function MetricSection({ title, children }: { title: string; children: ReactNode }) {
  const id = useId();
  return <section className="pilotage-section" aria-labelledby={id}>
    <h2 id={id}>{title}</h2>
    <ul className="pilotage-grid">{children}</ul>
  </section>;
}

export interface FilterOption { value: string; label: string }
export type FilterPatch = { [Key in 'period' | 'start' | 'end' | 'instructor']?: NavigationQuery[Key] };
const periodOptions: readonly FilterOption[] = [
  { value: 'month', label: 'Ce mois' }, { value: 'previous-month', label: 'Mois dernier' },
  { value: 'year', label: 'Cette année' }, { value: 'custom', label: 'Période libre' },
];
const allInstructors = 'all';

/** Filtres communs des statistiques : une même adresse les porte, un lien vers une autre page les conserve. */
export function PilotageFilters({ query, instructors, problem, onChange }: {
  query: NavigationQuery;
  instructors: readonly FilterOption[];
  problem: PeriodProblem | null;
  onChange: (patch: FilterPatch) => void;
}) {
  const choice = query.period ?? 'month';
  const instructorItems: readonly FilterOption[] = [{ value: allInstructors, label: 'Toute l’équipe' }, ...instructors];
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
    {instructors.length > 0 && <Field className="pilotage-filter">
      <FieldLabel htmlFor="pilotage-instructor">Moniteur</FieldLabel>
      <Select value={query.instructor ?? allInstructors} items={instructorItems} onValueChange={value => { if (value) onChange({ instructor: value === allInstructors ? undefined : value }); }}>
        <SelectTrigger id="pilotage-instructor" aria-label="Moniteur"><SelectValue /></SelectTrigger>
        <SelectContent>{instructorItems.map(option => <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
      </Select>
    </Field>}
    {problem && <FieldError className="pilotage-filter-error" role="alert">{periodProblemMessage(problem)}</FieldError>}
  </div>;
}
