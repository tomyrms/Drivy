/**
 * Règles pures de la section « Signalements » : ordre et affichage des thèmes du catalogue.
 * Pas de DOM, pas de réseau, aucun import : ce fichier est vérifié pour le navigateur et pour Node.
 * Un brouillon est une liste ordonnée de thèmes ; rien n'est modifié en place.
 */

export interface ThemeRow {
  readonly key: string;
  readonly title: string;
  readonly visible: boolean;
  readonly defaultVisible: boolean;
  readonly defaultPosition: number;
}

/** Ce qui compte pour la comparaison et l'envoi : la clé et l'affichage, dans l'ordre. */
export interface ThemeSetting { readonly key: string; readonly visible: boolean }

export const visibleCount = (rows: readonly ThemeRow[]): number => rows.filter(row => row.visible).length;

/** Au moins un thème reste affiché : le dernier affiché ne se masque pas. */
export const isLastVisible = (rows: readonly ThemeRow[], key: string): boolean =>
  visibleCount(rows) === 1 && rows.some(row => row.key === key && row.visible);

export function counterLabel(rows: readonly ThemeRow[]): string {
  const shown = visibleCount(rows);
  return `${shown} ${shown > 1 ? 'affichés' : 'affiché'} sur ${rows.length}`;
}

/** Place le thème `from` à la position `to` (les autres glissent). Hors bornes : la liste est rendue telle quelle. */
export function moveTheme<T>(rows: readonly T[], from: number, to: number): T[] {
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || from >= rows.length) return [...rows];
  const target = Math.min(Math.max(to, 0), rows.length - 1);
  if (target === from) return [...rows];
  const next = [...rows];
  const [moved] = next.splice(from, 1);
  next.splice(target, 0, moved!);
  return next;
}

/** Déplacement relatif d'un thème désigné par sa clé (flèches, boutons « Monter » / « Descendre »). */
export function moveThemeBy(rows: readonly ThemeRow[], key: string, delta: number): ThemeRow[] {
  const index = rows.findIndex(row => row.key === key);
  return index < 0 ? [...rows] : moveTheme(rows, index, index + delta);
}

/** Déplacement vers une position donnée, par clé (glisser-déposer). */
export function moveThemeTo(rows: readonly ThemeRow[], key: string, position: number): ThemeRow[] {
  const index = rows.findIndex(row => row.key === key);
  return index < 0 ? [...rows] : moveTheme(rows, index, position);
}

/** Bascule l'affichage d'un thème ; masquer le dernier thème affiché est refusé (liste inchangée). */
export function toggleTheme(rows: readonly ThemeRow[], key: string): ThemeRow[] {
  return rows.map(row => {
    if (row.key !== key) return row;
    if (row.visible && isLastVisible(rows, key)) return row;
    return { ...row, visible: !row.visible };
  });
}

/** Ordre d'origine, affichage conservé. */
export function resetOrder(rows: readonly ThemeRow[]): ThemeRow[] {
  return [...rows].sort((a, b) => a.defaultPosition - b.defaultPosition);
}

/** Configuration d'origine : ordre et affichage. */
export function resetAll(rows: readonly ThemeRow[]): ThemeRow[] {
  return resetOrder(rows).map(row => row.visible === row.defaultVisible ? row : { ...row, visible: row.defaultVisible });
}

export const isDefaultOrder = (rows: readonly ThemeRow[]): boolean => resetOrder(rows).every((row, index) => row.key === rows[index]?.key);

export const isDefaultConfiguration = (rows: readonly ThemeRow[]): boolean =>
  isDefaultOrder(rows) && rows.every(row => row.visible === row.defaultVisible);

export const settingsOf = (rows: readonly ThemeRow[]): ThemeSetting[] => rows.map(row => ({ key: row.key, visible: row.visible }));

/** Brouillon différent de ce que l'école a enregistré (ordre ou affichage). */
export function isDirty(draft: readonly ThemeSetting[], saved: readonly ThemeSetting[]): boolean {
  return draft.length !== saved.length || draft.some((row, index) => row.key !== saved[index]?.key || row.visible !== saved[index]?.visible);
}

/** Problème qui empêche d'enregistrer ce brouillon, ou null. */
export function draftProblem(rows: readonly ThemeRow[]): string | null {
  if (rows.length === 0) return 'Aucun signalement à enregistrer.';
  if (new Set(rows.map(row => row.key)).size !== rows.length) return 'Un signalement figure deux fois.';
  return visibleCount(rows) === 0 ? 'Gardez au moins un signalement affiché.' : null;
}

/** Corps de la commande `SAVE_OBSERVATION_THEMES` (sans `operationId`, ajouté par la commande) : toutes les clés, dans le nouvel ordre. */
export function saveBody(rows: readonly ThemeRow[]): { themes: ThemeSetting[] } {
  return { themes: settingsOf(rows) };
}

/** Tuiles de la grille « Signaler » vue par le moniteur : les thèmes affichés, dans l'ordre. */
export const previewTiles = (rows: readonly ThemeRow[]): ThemeRow[] => rows.filter(row => row.visible);

/** Phrase annoncée par la région vocale après un déplacement. */
export function moveAnnouncement(rows: readonly ThemeRow[], key: string): string {
  const index = rows.findIndex(row => row.key === key);
  return index < 0 ? '' : `${rows[index]!.title} : position ${index + 1} sur ${rows.length}.`;
}

export function toggleAnnouncement(rows: readonly ThemeRow[], key: string): string {
  const row = rows.find(item => item.key === key);
  return row ? `${row.title} ${row.visible ? 'affiché' : 'masqué'}. ${counterLabel(rows)}.` : '';
}

/**
 * Position cible d'un glissement : nombre des autres lignes dont le milieu est au-dessus du centre de la ligne tenue.
 * `middles` : milieux (en pixels, même repère) des lignes dans l'ordre courant, la ligne tenue comprise.
 */
export function dropIndex(middles: readonly number[], held: number, center: number): number {
  let index = 0;
  middles.forEach((middle, position) => { if (position !== held && middle < center) index++; });
  return index;
}
