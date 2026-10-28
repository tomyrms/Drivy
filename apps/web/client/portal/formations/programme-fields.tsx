import { useId, useLayoutEffect, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, Plus, Trash2 } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldLabel, FieldLegend, FieldSet } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Switch } from '../../components/ui/switch';
import { Textarea } from '../../components/ui/textarea';
import { competencyProblems, emptyCompetency, moveItem, rulesProblems, type CompetencyDraft, type GeneralDraft, type RulesDraft } from '../../console/formation-model';

/** Nom, état des nouvelles inscriptions et durée habituelle : les seuls réglages généraux d'un parcours. */
export function GeneralFields({ draft, onChange, disabled, problems, showErrors, nameRequired }: {
  draft: GeneralDraft; onChange: (draft: GeneralDraft) => void; disabled: boolean; showErrors: boolean; nameRequired: boolean;
  problems: { label: string | null; duration: string | null };
}) {
  const id = useId();
  return <FieldGroup>
    <Field data-invalid={showErrors && !!problems.label}>
      <FieldLabel htmlFor={`${id}-label`}>Nom du parcours{nameRequired ? '' : ' (facultatif)'}</FieldLabel>
      <Input id={`${id}-label`} value={draft.label} maxLength={120} disabled={disabled} aria-invalid={showErrors && !!problems.label}
        onChange={event => onChange({ ...draft, label: event.target.value })} />
      {showErrors && problems.label && <FieldError>{problems.label}</FieldError>}
    </Field>
    <Field orientation="horizontal" className="cat-switch-field">
      <FieldContent>
        <FieldLabel htmlFor={`${id}-offered`}>Proposé aux nouvelles inscriptions</FieldLabel>
        {!draft.offered && <FieldDescription>Les élèves déjà inscrits poursuivent leur formation ; aucune nouvelle inscription n’est possible.</FieldDescription>}
      </FieldContent>
      <Switch id={`${id}-offered`} checked={draft.offered} disabled={disabled} onCheckedChange={offered => onChange({ ...draft, offered })} />
    </Field>
    <Field data-invalid={showErrors && !!problems.duration}>
      <FieldLabel htmlFor={`${id}-duration`}>Durée habituelle d’une leçon (minutes)</FieldLabel>
      <Input id={`${id}-duration`} inputMode="numeric" value={draft.duration} maxLength={3} disabled={disabled} aria-invalid={showErrors && !!problems.duration}
        onChange={event => onChange({ ...draft, duration: event.target.value })} />
      {showErrors && problems.duration && <FieldError>{problems.duration}</FieldError>}
    </Field>
  </FieldGroup>;
}

/** Liste ordonnée : ajout, retrait et déplacement par de vrais boutons ; l'ordre enregistré est celui affiché. */
export function CompetencyFields({ items, onChange, disabled, showErrors }: { items: CompetencyDraft[]; onChange: (items: CompetencyDraft[]) => void; disabled: boolean; showErrors: boolean }) {
  const problems = competencyProblems(items);
  const list = useRef<HTMLOListElement>(null);
  const pending = useRef<{ uid: string; move?: -1 | 1 } | 'add' | null>(null);
  const [announcement, setAnnouncement] = useState('');
  // Le focus suit l'élément avec le DOM de la nouvelle liste, avant toute saisie suivante.
  useLayoutEffect(() => {
    const target = pending.current; pending.current = null;
    if (!target) return;
    if (target === 'add') { list.current?.parentElement?.querySelector<HTMLElement>('[data-add-competency]')?.focus(); return; }
    const row = list.current?.querySelector<HTMLElement>(`[data-uid="${target.uid}"]`);
    if (target.move) {
      const same = row?.querySelector<HTMLButtonElement>(`[data-move="${target.move}"]`);
      (same && !same.disabled ? same : row?.querySelector<HTMLButtonElement>(`[data-move="${-target.move}"]`))?.focus();
    } else row?.querySelector<HTMLElement>('input')?.focus();
  }, [items]);
  const name = (item: CompetencyDraft, index: number) => item.label.trim() || `compétence ${index + 1}`;
  const move = (index: number, delta: -1 | 1) => {
    const item = items[index]!;
    pending.current = { uid: item.uid, move: delta };
    onChange(moveItem(items, index, delta));
    setAnnouncement(`${name(item, index)} : position ${index + delta + 1} sur ${items.length}.`);
  };
  const remove = (index: number) => {
    const item = items[index]!, next = items[index + 1] ?? items[index - 1];
    pending.current = next ? { uid: next.uid } : 'add';
    onChange(items.filter(entry => entry.uid !== item.uid));
    setAnnouncement(`${name(item, index)} retirée.`);
  };
  const add = () => { const item = emptyCompetency(); pending.current = { uid: item.uid }; onChange([...items, item]); };
  return <FieldSet className="cat-competency-editor">
    <FieldLegend className="sr-only">Compétences enseignées</FieldLegend>
    {showErrors && problems.list && <FieldError>{problems.list}</FieldError>}
    <ol ref={list} className="cat-competency-list">
      {items.map((item, index) => {
        const label = problems.items[index]?.label, description = problems.items[index]?.description;
        return <li key={item.uid} data-uid={item.uid} className="cat-competency">
          <span className="cat-competency-index" aria-hidden="true">{index + 1}</span>
          <FieldGroup className="cat-competency-fields">
            <Field data-invalid={showErrors && !!label}>
              <FieldLabel htmlFor={`competency-${item.uid}`}>Compétence {index + 1}</FieldLabel>
              <Input id={`competency-${item.uid}`} value={item.label} maxLength={200} disabled={disabled} aria-invalid={showErrors && !!label}
                onChange={event => onChange(items.map(entry => entry.uid === item.uid ? { ...entry, label: event.target.value } : entry))} />
              {showErrors && label && <FieldError>{label}</FieldError>}
            </Field>
            <Field data-invalid={showErrors && !!description}>
              <FieldLabel htmlFor={`competency-description-${item.uid}`}>Ce que l’élève apprend</FieldLabel>
              <Textarea id={`competency-description-${item.uid}`} rows={3} maxLength={4000} value={item.description} disabled={disabled} aria-invalid={showErrors && !!description}
                onChange={event => onChange(items.map(entry => entry.uid === item.uid ? { ...entry, description: event.target.value } : entry))} />
              {showErrors && description && <FieldError>{description}</FieldError>}
            </Field>
          </FieldGroup>
          <div className="cat-competency-actions" role="group" aria-label={`Ordre de ${name(item, index)}`}>
            <Button type="button" variant="outline" size="icon" data-move="-1" disabled={disabled || index === 0} onClick={() => move(index, -1)} aria-label={`Monter ${name(item, index)}`}><ArrowUp /></Button>
            <Button type="button" variant="outline" size="icon" data-move="1" disabled={disabled || index === items.length - 1} onClick={() => move(index, 1)} aria-label={`Descendre ${name(item, index)}`}><ArrowDown /></Button>
            <Button type="button" variant="ghost" disabled={disabled} onClick={() => remove(index)} aria-label={`Retirer ${name(item, index)}`}><Trash2 data-icon="inline-start" />Retirer</Button>
          </div>
        </li>;
      })}
    </ol>
    <Button type="button" variant="outline" data-add-competency disabled={disabled || items.length >= 200} onClick={add}><Plus data-icon="inline-start" />Ajouter une compétence</Button>
    <p className="visually-hidden" role="status" aria-live="polite">{announcement}</p>
  </FieldSet>;
}

/** Deux textes distincts ; l'exemple Drivy ne remplace jamais un texte déjà rédigé. */
export function RulesFields({ draft, onChange, disabled, showErrors, example }: {
  draft: RulesDraft; onChange: (draft: RulesDraft) => void; disabled: boolean; showErrors: boolean; example: { procedureText: string; cancellationPolicyText: string } | null;
}) {
  const id = useId();
  const problems = rulesProblems(draft);
  const proposal = (field: 'procedureText' | 'cancellationPolicyText') => example && example[field] && draft[field].trim() === ''
    ? <Button type="button" variant="ghost" className="cat-example" disabled={disabled} onClick={() => onChange({ ...draft, [field]: example[field] })}>Utiliser l’exemple Drivy</Button> : null;
  return <FieldGroup>
    <Field data-invalid={showErrors && !!problems.procedureText}>
      <FieldLabel htmlFor={`${id}-procedure`}>Déroulement d’une leçon</FieldLabel>
      <Textarea id={`${id}-procedure`} rows={7} maxLength={4000} value={draft.procedureText} disabled={disabled} aria-invalid={showErrors && !!problems.procedureText}
        onChange={event => onChange({ ...draft, procedureText: event.target.value })} />
      {showErrors && problems.procedureText && <FieldError>{problems.procedureText}</FieldError>}{proposal('procedureText')}
    </Field>
    <Field data-invalid={showErrors && !!problems.cancellationPolicyText}>
      <FieldLabel htmlFor={`${id}-cancellation`}>Conditions d’annulation</FieldLabel>
      <Textarea id={`${id}-cancellation`} rows={5} maxLength={4000} value={draft.cancellationPolicyText} disabled={disabled} aria-invalid={showErrors && !!problems.cancellationPolicyText}
        onChange={event => onChange({ ...draft, cancellationPolicyText: event.target.value })} />
      {showErrors && problems.cancellationPolicyText && <FieldError>{problems.cancellationPolicyText}</FieldError>}{proposal('cancellationPolicyText')}
    </Field>
    <Collapsible defaultOpen={draft.sources.trim() !== ''} className="cat-collapsible">
      <CollapsibleTrigger render={<Button type="button" variant="ghost" className="cat-collapsible-trigger" />}>Sources{draft.sources.trim() ? ` (${draft.sources.trim().split(/\s*\n\s*/).length})` : ''}</CollapsibleTrigger>
      <CollapsibleContent>
        <Field data-invalid={showErrors && !!problems.sources}>
          <FieldLabel htmlFor={`${id}-sources`}>Liens de référence, un par ligne (facultatif)</FieldLabel>
          <Textarea id={`${id}-sources`} rows={3} value={draft.sources} disabled={disabled} aria-invalid={showErrors && !!problems.sources}
            onChange={event => onChange({ ...draft, sources: event.target.value })} />
          {showErrors && problems.sources && <FieldError>{problems.sources}</FieldError>}
        </Field>
      </CollapsibleContent>
    </Collapsible>
  </FieldGroup>;
}
