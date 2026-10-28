import { parseCents } from '../../command-core';
import type { Tariff } from '../../formation-api';
import { minutes, tariffTypeLabels, updateTariffBody, updatedValidFrom, type TariffDraft } from '../../console/formation-model';
import type { FieldChange } from '../formations/formation-diff';
import { civilDate, duration, priceLabel } from '../formations/formation-format';

/**
 * Récapitulatif d'un tarif avant confirmation. Le prix saisi n'est jamais interprété autrement que par `parseCents` :
 * un champ vide ou illisible reste « non défini » et n'est jamais présenté comme 0.
 */
const reservations = (enabled: boolean) => enabled ? 'Proposé' : 'Non proposé';
const until = (value: string) => value ? civilDate(value) : 'Sans fin';
const draftPrice = (draft: TariffDraft) => priceLabel(parseCents(draft.price));
const draftDuration = (draft: TariffDraft) => draft.duration.trim() === '' ? 'Non renseignée' : duration(minutes(draft.duration));

export function tariffDifferences(draft: TariffDraft, tariff: Tariff, today: string): FieldChange[] {
  const body = updateTariffBody(draft, tariff, today), head = tariff.head, rows: FieldChange[] = [];
  if (body.label !== head.label) rows.push({ label: 'Nom', before: head.label, after: body.label });
  if (body.type !== head.type) rows.push({ label: 'Type', before: tariffTypeLabels[head.type], after: tariffTypeLabels[body.type] });
  if (body.durationMinutes !== head.durationMinutes) rows.push({ label: 'Durée', before: duration(head.durationMinutes), after: draftDuration(draft) });
  if (body.priceCents !== head.unitPriceCents) rows.push({ label: 'Prix', before: priceLabel(head.unitPriceCents), after: draftPrice(draft) });
  if (body.unitLabel !== head.unitLabel) rows.push({ label: 'Unité facturée', before: head.unitLabel, after: body.unitLabel });
  if (body.validUntil !== head.validUntil) rows.push({ label: 'Valable jusqu’au', before: until(head.validUntil ?? ''), after: until(body.validUntil ?? '') });
  if (body.enabled !== head.enabled) rows.push({ label: 'Réservations', before: reservations(head.enabled), after: reservations(body.enabled) });
  if (body.terms.mode === 'NEW') rows.push({ label: 'Conditions', before: tariff.termsSharedWith > 0 ? 'Conditions communes' : 'Conditions de ce tarif', after: 'Conditions propres à ce tarif' });
  return rows;
}

/** Date à laquelle la version modifiée prend effet : jamais avant aujourd'hui, jamais rétroactive. */
export const effectiveFrom = (tariff: Tariff, today: string) => updatedValidFrom(tariff, today);

export function tariffSummary(draft: TariffDraft): FieldChange[] {
  return [
    { label: 'Nom', before: '', after: draft.label.trim() },
    { label: 'Type', before: '', after: tariffTypeLabels[draft.type] },
    { label: 'Durée', before: '', after: draftDuration(draft) },
    { label: 'Prix', before: '', after: `${draftPrice(draft)} par ${draft.unitLabel.trim() || 'unité'}` },
    { label: 'Valable à partir du', before: '', after: civilDate(draft.validFrom) },
    ...(draft.validUntil ? [{ label: 'Jusqu’au', before: '', after: civilDate(draft.validUntil) }] : []),
    { label: 'Réservations', before: '', after: reservations(draft.enabled) },
  ];
}
