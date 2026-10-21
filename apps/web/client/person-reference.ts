/**
 * Short, non-secret references that tell apart records sharing the same visible label
 * (two members called « Marie Rochat », two invitations to « m***@ecole.ch »).
 * The reference is derived from the record's technical identifier: it reveals no personal
 * data and never replaces the identifier as the key of an action.
 * Pure module, no relative import: type-checked for the browser and for the Node unit tests.
 */
const minimumLength = 4;

const fold = (label: string) => label.normalize('NFD').replace(/\p{Diacritic}/gu, '').trim().replace(/\s+/g, ' ').toLocaleLowerCase('fr');
const compact = (id: string) => id.replace(/-/g, '').toUpperCase();

/**
 * For every record whose label is shared with another one, the shortest ending of its identifier
 * (at least four characters, the random part of both UUIDv4 and UUIDv7) that differs from all its homonyms. Records with a unique label are absent.
 */
export function homonymReferences(records: readonly { readonly id: string; readonly label: string }[]): Map<string, string> {
  const groups = new Map<string, string[]>();
  for (const record of records) {
    const key = fold(record.label);
    const ids = groups.get(key) ?? [];
    if (!ids.includes(record.id)) ids.push(record.id);
    groups.set(key, ids);
  }
  const references = new Map<string, string>();
  for (const ids of groups.values()) {
    if (ids.length < 2) continue;
    const values = ids.map(compact);
    let length = minimumLength;
    while (length < 32 && new Set(values.map(value => value.slice(-length))).size < values.length) length += 1;
    ids.forEach((id, index) => references.set(id, values[index]!.slice(-length)));
  }
  return references;
}

/** « Marie Rochat · Réf. 3F2A » when a homonym exists, the label alone otherwise. */
export function distinctLabel(label: string, reference: string | undefined): string {
  return reference ? `${label} · Réf. ${reference}` : label;
}
