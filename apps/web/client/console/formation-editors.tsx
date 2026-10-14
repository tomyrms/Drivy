import { useRef, useState, type ReactNode } from 'react';
import { formatCents, parseCents } from '../command-core';
import type { TariffType } from '../formation-api';
import { Notice, SegmentField, SelectField, Symbol, TextArea, TextField, formatCivilDate } from '../ui';
import {
  competencyProblems, emptyCompetency, moveItem, rulesProblems, tariffProblems, tariffTypeLabels, defaultUnit,
  type CompetencyDraft, type GeneralDraft, type RulesDraft, type TariffDraft,
} from './formation-model';

/*
 * Éditeurs contrôlés, partagés par la fiche d'une formation et par l'assistant de création :
 * mêmes champs, mêmes validations, aucun état propre en dehors du focus.
 */

/** Liste ordonnée : ajout, retrait et déplacement par de vrais boutons ; l'ordre enregistré est celui affiché. */
export function CompetenciesEditor({ items, onChange, disabled, showErrors }: {
  items: CompetencyDraft[]; onChange: (items: CompetencyDraft[]) => void; disabled: boolean; showErrors: boolean;
}) {
  const problems = competencyProblems(items);
  const list = useRef<HTMLOListElement>(null);
  const [announcement, setAnnouncement] = useState('');
  const focusLater = (selector: string) => window.requestAnimationFrame(() => list.current?.querySelector<HTMLElement>(selector)?.focus());
  const move = (index: number, delta: -1 | 1) => {
    const item = items[index]!;
    onChange(moveItem(items, index, delta));
    setAnnouncement(`${item.label.trim() || 'Compétence'} : position ${index + delta + 1} sur ${items.length}.`);
    // Le focus suit l'élément déplacé : même sens s'il reste possible, sinon l'autre.
    window.requestAnimationFrame(() => {
      const row = list.current?.querySelector<HTMLElement>(`[data-uid="${item.uid}"]`);
      const same = row?.querySelector<HTMLButtonElement>(`[data-move="${delta}"]`);
      (same && !same.disabled ? same : row?.querySelector<HTMLButtonElement>(`[data-move="${-delta}"]`))?.focus();
    });
  };
  const remove = (index: number) => {
    const item = items[index]!, next = items[index + 1] ?? items[index - 1];
    onChange(items.filter(entry => entry.uid !== item.uid));
    setAnnouncement(`${item.label.trim() || 'Compétence'} retirée.`);
    if (next) focusLater(`[data-uid="${next.uid}"] input`); else window.requestAnimationFrame(() => list.current?.parentElement?.querySelector<HTMLElement>('[data-add-competency]')?.focus());
  };
  const add = () => {
    const item = emptyCompetency();
    onChange([...items, item]);
    focusLater(`[data-uid="${item.uid}"] input`);
  };
  return <fieldset className="fieldset competency-editor" aria-invalid={showErrors && problems.list ? true : undefined}>
    <legend>Compétences enseignées</legend>
    {showErrors && problems.list && <p className="field-error"><Symbol kind="alert" bare />{problems.list}</p>}
    <ol ref={list} className="competency-list">
      {items.map((item, index) => {
        const name = item.label.trim() || `compétence ${index + 1}`;
        return <li key={item.uid} data-uid={item.uid} className="competency-row">
          <span className="competency-index" aria-hidden="true">{index + 1}</span>
          <div className="competency-fields">
            <TextField label={`Compétence ${index + 1}`} value={item.label} maxLength={200} disabled={disabled}
              onChange={label => onChange(items.map(entry => entry.uid === item.uid ? { ...entry, label } : entry))} error={showErrors ? problems.items[index]?.label : null} />
            <TextArea label="Ce que l’élève apprend" rows={2} maxLength={4000} value={item.description} disabled={disabled}
              onChange={description => onChange(items.map(entry => entry.uid === item.uid ? { ...entry, description } : entry))} error={showErrors ? problems.items[index]?.description : null} />
          </div>
          <div className="competency-actions" role="group" aria-label={`Ordre de ${name}`}>
            <button type="button" className="button quiet compact icon-only" data-move="-1" disabled={disabled || index === 0} onClick={() => move(index, -1)}
              aria-label={`Monter ${name}`}><Symbol kind="chevron-up" bare /></button>
            <button type="button" className="button quiet compact icon-only" data-move="1" disabled={disabled || index === items.length - 1} onClick={() => move(index, 1)}
              aria-label={`Descendre ${name}`}><Symbol kind="chevron" bare /></button>
            <button type="button" className="button quiet compact" disabled={disabled} onClick={() => remove(index)} aria-label={`Retirer ${name}`}>Retirer</button>
          </div>
        </li>;
      })}
    </ol>
    <button type="button" className="button secondary" data-add-competency disabled={disabled || items.length >= 200} onClick={add}><Symbol kind="plus" bare />Ajouter une compétence</button>
    <p className="visually-hidden" role="status" aria-live="polite">{announcement}</p>
  </fieldset>;
}

/** Deux textes distincts dans le même contexte ; l'exemple Drivy ne remplace jamais un texte déjà rédigé. */
export function RulesEditor({ draft, onChange, disabled, showErrors, example }: {
  draft: RulesDraft; onChange: (draft: RulesDraft) => void; disabled: boolean; showErrors: boolean;
  example?: { procedureText: string; cancellationPolicyText: string } | null;
}) {
  const problems = rulesProblems(draft);
  const proposal = (field: 'procedureText' | 'cancellationPolicyText') => example && example[field] && <div className="example-text">
    {draft[field].trim() === ''
      ? <button type="button" className="button quiet compact" disabled={disabled} onClick={() => onChange({ ...draft, [field]: example[field] })}>Utiliser l’exemple Drivy</button>
      : draft[field].trim() !== example[field].trim() && <details className="disclosure compact"><summary>Exemple Drivy</summary><p className="policy-copy">{example[field]}</p></details>}
  </div>;
  return <div className="rules-editor">
    <div className="rules-field"><TextArea label="Déroulement d’une leçon" rows={5} maxLength={4000} value={draft.procedureText} disabled={disabled}
      onChange={procedureText => onChange({ ...draft, procedureText })} error={showErrors ? problems.procedureText : null} />{proposal('procedureText')}</div>
    <div className="rules-field"><TextArea label="Conditions d’annulation" rows={4} maxLength={4000} value={draft.cancellationPolicyText} disabled={disabled}
      onChange={cancellationPolicyText => onChange({ ...draft, cancellationPolicyText })} error={showErrors ? problems.cancellationPolicyText : null} />{proposal('cancellationPolicyText')}</div>
    <details className="disclosure compact" open={draft.sources.trim() !== '' && showErrors && problems.sources !== null ? true : undefined}>
      <summary>Sources {draft.sources.trim() ? `(${draft.sources.trim().split(/\s*\n\s*/).length})` : ''}</summary>
      <TextArea label="Liens de référence, un par ligne" required={false} rows={3} value={draft.sources} disabled={disabled}
        onChange={sources => onChange({ ...draft, sources })} error={showErrors ? problems.sources : null} />
    </details>
  </div>;
}

export function GeneralEditor({ draft, onChange, disabled, problems, showErrors, nameRequired }: {
  draft: GeneralDraft; onChange: (draft: GeneralDraft) => void; disabled: boolean; showErrors: boolean; nameRequired: boolean;
  problems: { label: string | null; duration: string | null };
}) {
  return <div className="form-grid general-editor">
    <TextField label="Nom du parcours" value={draft.label} maxLength={120} disabled={disabled} required={nameRequired ? undefined : false}
      onChange={label => onChange({ ...draft, label })} error={showErrors ? problems.label : null} />
    <SegmentField label="Nouvelles inscriptions" value={draft.offered ? 'yes' : 'no'} disabled={disabled}
      options={[{ value: 'yes', label: 'Proposée' }, { value: 'no', label: 'Non proposée' }]} onChange={value => onChange({ ...draft, offered: value === 'yes' })} />
    {!draft.offered && <p className="caption">Les élèves déjà inscrits poursuivent leur formation ; aucune nouvelle inscription n’est possible.</p>}
    <TextField label="Durée habituelle d’une leçon (minutes)" inputMode="numeric" value={draft.duration} maxLength={3} disabled={disabled}
      onChange={duration => onChange({ ...draft, duration })} error={showErrors ? problems.duration : null} />
  </div>;
}

/** Formulaire d'un tarif : le permis est déjà déterminé par la fiche (ou absent pour une prestation sans permis). */
export function TariffFields({ draft, onChange, disabled, showErrors, mode, today, types, start, sharedTerms }: {
  draft: TariffDraft; onChange: (draft: TariffDraft) => void; disabled: boolean; showErrors: boolean; mode: 'CREATE' | 'UPDATE';
  today: string; types: readonly TariffType[]; start?: string; sharedTerms?: number; children?: ReactNode;
}) {
  const problems = tariffProblems(draft, mode, today, start ?? draft.validFrom);
  const cents = parseCents(draft.price);
  return <div className="form-grid tariff-editor">
    <TextField label="Nom du tarif" value={draft.label} maxLength={200} placeholder="Par exemple « Leçon de 45 minutes »" disabled={disabled}
      onChange={label => onChange({ ...draft, label })} error={showErrors ? problems.label : null} />
    {types.length > 1 && <SelectField label="Type" value={draft.type} disabled={disabled} options={types.map(type => ({ value: type, label: tariffTypeLabels[type] }))}
      onChange={type => onChange({ ...draft, type, unitLabel: draft.unitLabel === defaultUnit[draft.type] ? defaultUnit[type] : draft.unitLabel })} />}
    <div className="field-pair">
      <TextField label="Durée (minutes)" inputMode="numeric" value={draft.duration} maxLength={4} disabled={disabled} required={draft.type === 'INDIVIDUAL_LESSON' ? undefined : false}
        onChange={duration => onChange({ ...draft, duration })} error={showErrors ? problems.duration : null} />
      <TextField label="Unité facturée" value={draft.unitLabel} maxLength={100} disabled={disabled} onChange={unitLabel => onChange({ ...draft, unitLabel })} error={showErrors ? problems.unitLabel : null} />
    </div>
    <TextField label="Prix (CHF)" inputMode="decimal" value={draft.price} maxLength={16} disabled={disabled} placeholder="95.00"
      hint={cents !== null ? `${formatCents(cents)} par ${draft.unitLabel.trim() || 'unité'}${cents === 0 ? ' : prestation offerte' : ''}` : '0 pour une prestation offerte.'}
      onChange={price => onChange({ ...draft, price })} error={showErrors ? problems.price : null} />
    {mode === 'CREATE'
      ? <div className="field-pair">
          <TextField label="Valable à partir du" type="date" value={draft.validFrom} disabled={disabled} onChange={validFrom => onChange({ ...draft, validFrom })} error={showErrors ? problems.validFrom : null} />
          <TextField label="Jusqu’au" type="date" required={false} value={draft.validUntil} disabled={disabled} onChange={validUntil => onChange({ ...draft, validUntil })} error={showErrors ? problems.validUntil : null} />
        </div>
      : <>
          <TextField label="Valable jusqu’au" type="date" required={false} value={draft.validUntil} disabled={disabled}
            hint={start && start > today ? `Ce tarif commence le ${formatCivilDate(start)}.` : 'La modification s’applique dès aujourd’hui.'}
            onChange={validUntil => onChange({ ...draft, validUntil })} error={showErrors ? problems.validUntil : null} />
          <SegmentField label="Réservations" value={draft.enabled ? 'yes' : 'no'} disabled={disabled}
            options={[{ value: 'yes', label: 'Proposé' }, { value: 'no', label: 'Non proposé' }]} onChange={value => onChange({ ...draft, enabled: value === 'yes' })} />
        </>}
    <TextArea label="Conditions commerciales" rows={6} maxLength={20_000} value={draft.termsText} disabled={disabled}
      onChange={termsText => onChange({ ...draft, termsText })} error={showErrors ? problems.termsText : null} />
    {sharedTerms !== undefined && sharedTerms > 0 && <Notice tone="info" title="Conditions partagées" live={false}>
      <p>Ces conditions servent aussi à {sharedTerms} autre{sharedTerms > 1 ? 's' : ''} tarif{sharedTerms > 1 ? 's' : ''}. Les modifier ici crée des conditions propres à ce tarif ; les autres restent inchangés.</p>
    </Notice>}
  </div>;
}

/** Barre d'enregistrement d'une édition : périmètre explicite, effet annoncé, annulation. */
export function SaveBar({ busy, dirty, disabled, saveLabel, onCancel, effect, status }: {
  busy: boolean; dirty: boolean; disabled: boolean; saveLabel: string; onCancel: () => void; effect?: ReactNode; status?: string;
}) {
  return <div className="form-save-bar formation-save-bar">
    {effect && <p className="caption save-effect">{effect}</p>}
    <p className="save-state" role="status">{busy ? 'Enregistrement…' : status ?? (dirty ? 'Modifications non enregistrées' : 'Aucune modification')}</p>
    <div className="button-row compact">
      <button type="submit" className="button primary" disabled={disabled || !dirty} aria-busy={busy}>{busy ? 'Enregistrement…' : saveLabel}</button>
      <button type="button" className="button quiet" disabled={busy} onClick={onCancel}>Annuler</button>
    </div>
  </div>;
}
