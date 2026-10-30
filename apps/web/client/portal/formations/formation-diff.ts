import type { Programme } from '../../formation-api';
import { generalChanges, type CompetencyDraft, type GeneralDraft, type RulesDraft } from '../../console/formation-model';
import { rulesPayload } from '../../console/formation-model';
import { duration } from './formation-format';

/** Différences présentées avant confirmation : calculées contre la version enregistrée, jamais contre un état local. */
export interface Competency { key: string; label: string; description: string }
export interface CompetencyChanges {
  added: { item: Competency | { key: null; label: string; description: string }; position: number }[];
  removed: Competency[];
  edited: { before: Competency; after: Competency }[];
  /** L'ordre relatif des compétences conservées a changé. */
  reordered: boolean;
  total: number;
}
export function competencyChanges(before: readonly Competency[], after: readonly CompetencyDraft[]): CompetencyChanges {
  const known = new Map(before.map(item => [item.key, item]));
  const kept = new Set(after.flatMap(item => item.key !== null && known.has(item.key) ? [item.key] : []));
  const added = after.flatMap((item, index) => item.key === null || !known.has(item.key)
    ? [{ item: { key: item.key, label: item.label.trim(), description: item.description.trim() } as CompetencyChanges['added'][number]['item'], position: index + 1 }] : []);
  const removed = before.filter(item => !kept.has(item.key));
  const edited = after.flatMap(item => {
    const previous = item.key === null ? undefined : known.get(item.key);
    return previous && (previous.label !== item.label.trim() || previous.description !== item.description.trim())
      ? [{ before: previous, after: { key: previous.key, label: item.label.trim(), description: item.description.trim() } }] : [];
  });
  const order = (keys: readonly (string | null)[]) => keys.filter((key): key is string => key !== null && kept.has(key)).join('\u0000');
  return { added, removed, edited, reordered: order(before.map(item => item.key)) !== order(after.map(item => item.key)), total: after.length };
}
export const competencyChangeCount = (changes: CompetencyChanges) => changes.added.length + changes.removed.length + changes.edited.length + (changes.reordered ? 1 : 0);

export interface TextChange { field: 'procedureText' | 'cancellationPolicyText' | 'sources'; label: string; before: string; after: string }
export function rulesChanges(current: { procedureText: string; cancellationPolicyText: string; sourceUrls: readonly string[] } | null, draft: RulesDraft): TextChange[] {
  const next = rulesPayload(draft);
  const rows: TextChange[] = [
    { field: 'procedureText', label: 'Déroulement d’une leçon', before: current?.procedureText ?? '', after: next.procedureText },
    { field: 'cancellationPolicyText', label: 'Conditions d’annulation', before: current?.cancellationPolicyText ?? '', after: next.cancellationPolicyText },
    { field: 'sources', label: 'Sources', before: (current?.sourceUrls ?? []).join('\n'), after: next.sourceUrls.join('\n') },
  ];
  return rows.filter(row => row.before !== row.after);
}

export interface FieldChange { label: string; before: string; after: string }
export function generalDifferences(draft: GeneralDraft, programme: Programme): FieldChange[] {
  const changes = generalChanges(draft, programme), rows: FieldChange[] = [];
  if ('label' in changes) rows.push({ label: 'Nom du parcours', before: programme.head.label ?? 'Sans nom', after: changes.label ?? 'Sans nom' });
  if ('enabled' in changes) rows.push({ label: 'Nouvelles inscriptions', before: programme.head.enabled ? 'Proposée' : 'Non proposée', after: changes.enabled ? 'Proposée' : 'Non proposée' });
  if ('defaultDurationMinutes' in changes) rows.push({ label: 'Durée habituelle', before: duration(programme.head.defaultDurationMinutes), after: duration(changes.defaultDurationMinutes ?? null) });
  return rows;
}
