import { useId, useState } from 'react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Switch } from '../../components/ui/switch';
import { Textarea } from '../../components/ui/textarea';
import type { Tariff, TariffType } from '../../formation-api';
import { parseCents } from '../../command-core';
import { defaultUnit, tariffTypeLabels, type TariffDraft } from '../../console/formation-model';
import { PortalSelect } from '../components/portal-select';
import { priceLabel, shortDate } from '../formations/formation-format';
import type { TariffEditor } from './pricing-controllers';

/**
 * Le cas courant tient en trois champs : nom, durée, prix. Le reste (unité, dates, conditions) est un second niveau
 * qui s'ouvre de lui-même quand une erreur s'y trouve. Le prix n'est jamais complété : vide ou illisible reste une erreur.
 */
export function TariffForm({ editor, types, sharedWith, current, today, disabled }: { editor: TariffEditor; types: readonly TariffType[]; sharedWith: number; current: Tariff | undefined; today: string; disabled: boolean }) {
  const id = useId();
  const draft = editor.draft!, problems = editor.problems!, show = editor.attempted;
  const [open, setOpen] = useState(false);
  const optionErrors = show && !!(problems.unitLabel || problems.validFrom || problems.validUntil || problems.termsText);
  const update = (patch: Partial<TariffDraft>) => editor.update({ ...draft, ...patch });
  const cents = parseCents(draft.price);
  const create = editor.mode === 'CREATE';
  const error = (key: keyof typeof problems) => show && problems[key] ? problems[key] as string : null;
  const lesson = draft.type === 'INDIVIDUAL_LESSON';
  return <FieldGroup className="cat-tariff-form">
    {editor.rebased && <Alert><AlertTitle>Ce tarif a changé pendant votre modification</AlertTitle>
      <AlertDescription>Une autre version a été enregistrée entre-temps. Votre saisie est conservée : relisez-la avant d’enregistrer.</AlertDescription></Alert>}
    <Field data-invalid={!!error('label')}>
      <FieldLabel htmlFor={`${id}-label`}>Nom du tarif</FieldLabel>
      <Input disabled={disabled} id={`${id}-label`} value={draft.label} maxLength={200} placeholder="Par exemple Leçon de 45 minutes" aria-invalid={!!error('label')} onChange={event => update({ label: event.target.value })} />
      {error('label') && <FieldError>{error('label')}</FieldError>}
    </Field>
    <div className="cat-field-pair">
      <Field data-invalid={!!error('duration')}>
        <FieldLabel htmlFor={`${id}-duration`}>Durée (minutes){lesson ? '' : ' · facultatif'}</FieldLabel>
        <Input disabled={disabled} id={`${id}-duration`} inputMode="numeric" value={draft.duration} maxLength={4} aria-invalid={!!error('duration')} onChange={event => update({ duration: event.target.value })} />
        {error('duration') && <FieldError>{error('duration')}</FieldError>}
      </Field>
      <Field data-invalid={!!error('price')}>
        <FieldLabel htmlFor={`${id}-price`}>Prix (CHF)</FieldLabel>
        <Input disabled={disabled} id={`${id}-price`} inputMode="decimal" value={draft.price} maxLength={16} aria-invalid={!!error('price')} aria-describedby={`${id}-price-hint`} onChange={event => update({ price: event.target.value })} />
        <FieldDescription id={`${id}-price-hint`}>{cents !== null ? `${priceLabel(cents)} par ${draft.unitLabel.trim() || 'unité'}` : 'Un prix de 0 rend la prestation offerte.'}</FieldDescription>
        {error('price') && <FieldError>{error('price')}</FieldError>}
      </Field>
    </div>
    <Collapsible open={open || optionErrors} onOpenChange={setOpen} className="cat-collapsible">
      <CollapsibleTrigger render={<Button type="button" variant="ghost" className="cat-collapsible-trigger" />}>Autres options</CollapsibleTrigger>
      <CollapsibleContent>
        <FieldGroup className="cat-options">
          {types.length > 1 && <PortalSelect disabled={disabled} id={`${id}-type`} label="Type" value={draft.type} options={types.map(type => ({ value: type, label: tariffTypeLabels[type] }))}
            onValueChange={type => { if (type) update({ type: type as TariffType, unitLabel: draft.unitLabel === defaultUnit[draft.type] ? defaultUnit[type as TariffType] : draft.unitLabel }); }} />}
          <Field data-invalid={!!error('unitLabel')}>
            <FieldLabel htmlFor={`${id}-unit`}>Unité facturée</FieldLabel>
            <Input disabled={disabled} id={`${id}-unit`} value={draft.unitLabel} maxLength={100} aria-invalid={!!error('unitLabel')} onChange={event => update({ unitLabel: event.target.value })} />
            {error('unitLabel') && <FieldError>{error('unitLabel')}</FieldError>}
          </Field>
          {create && <Field data-invalid={!!error('validFrom')}>
            <FieldLabel htmlFor={`${id}-from`}>Valable à partir du</FieldLabel>
            <Input disabled={disabled} id={`${id}-from`} type="date" value={draft.validFrom} aria-invalid={!!error('validFrom')} onChange={event => update({ validFrom: event.target.value })} />
            {error('validFrom') && <FieldError>{error('validFrom')}</FieldError>}
          </Field>}
          <Field data-invalid={!!error('validUntil')}>
            <FieldLabel htmlFor={`${id}-until`}>Valable jusqu’au · facultatif</FieldLabel>
            <Input disabled={disabled} id={`${id}-until`} type="date" value={draft.validUntil} aria-invalid={!!error('validUntil')} aria-describedby={`${id}-until-hint`} onChange={event => update({ validUntil: event.target.value })} />
            <FieldDescription id={`${id}-until-hint`}>{create ? 'Sans date, le tarif reste valable jusqu’à nouvel ordre.'
              : editor.start > today ? `Ce tarif commence le ${shortDate(editor.start)}.` : 'Une modification s’applique dès aujourd’hui, jamais aux réservations déjà confirmées.'}</FieldDescription>
            {error('validUntil') && <FieldError>{error('validUntil')}</FieldError>}
          </Field>
          {!create && <Field orientation="horizontal" className="cat-switch-field">
            <FieldContent><FieldLabel htmlFor={`${id}-enabled`}>Proposé à la réservation</FieldLabel></FieldContent>
            <Switch disabled={disabled} id={`${id}-enabled`} checked={draft.enabled} onCheckedChange={enabled => update({ enabled })} />
          </Field>}
          <Field data-invalid={!!error('termsText')}>
            <FieldLabel htmlFor={`${id}-terms`}>Conditions commerciales</FieldLabel>
            <Textarea disabled={disabled} id={`${id}-terms`} rows={8} maxLength={20_000} value={draft.termsText} aria-invalid={!!error('termsText')} onChange={event => update({ termsText: event.target.value })} />
            {error('termsText') && <FieldError>{error('termsText')}</FieldError>}
            {current && sharedWith > 0 && <FieldDescription>Ces conditions servent aussi à {sharedWith} autre{sharedWith > 1 ? 's' : ''} tarif{sharedWith > 1 ? 's' : ''}. Les modifier ici crée des conditions propres à ce tarif ; les autres restent inchangés.</FieldDescription>}
          </Field>
        </FieldGroup>
      </CollapsibleContent>
    </Collapsible>
  </FieldGroup>;
}
