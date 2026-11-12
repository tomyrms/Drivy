/**
 * Règles pures des préférences de signalements du COMPTE (R08, #465) : ce qui se compare, ce qui s'envoie, ce que chaque rôle peut faire.
 * Pas de DOM, pas de réseau : le serveur tranche toujours, ce fichier ne fait que refléter ce qu'il a rendu.
 *
 * L'ordre manuel est toujours modifiable. La visibilité ne l'est que si l'école autorise la personnalisation (`visibilityEditable`).
 */
import type { ThemeRow } from './observation-themes-model.js';

export type PreferenceMode = 'MANUAL' | 'SMART';

/** Ce que l'écran lit du serveur (sous-ensemble de `ObservationPreferences`, sans dépendance au schéma). */
export interface PreferenceFacts {
  readonly version: number;
  readonly personalizationAllowed: boolean;
  readonly mode: PreferenceMode;
  readonly themes: readonly { key: string; title: string; visible: boolean; defaultVisible: boolean; defaultPosition: number }[];
  readonly palette: readonly string[];
}

/** Brouillon : lié à la version du compte ET à la politique vue à l'ouverture, jamais rejoué sur un autre état. */
export interface PreferenceDraft {
  readonly version: number;
  readonly visibilityEditable: boolean;
  readonly mode: PreferenceMode;
  readonly rows: ThemeRow[];
}

/** Les signalements se règlent en tant que moniteur ou administrateur ; un compte d'élève seul n'en a pas. */
export const canPersonalizeSignals = (roles: readonly string[]): boolean => roles.includes('ADMIN') || roles.includes('INSTRUCTOR');

/** Adresse de la page des préférences de signalements ; `returnTo` ne sort pas de la gestion d'une école (déjà filtré par l'appelant). */
export function signalsPreferencesHref(options: { returnTo?: string; schoolId?: string }): string {
  const params = new URLSearchParams();
  if (options.schoolId) params.set('school', options.schoolId);
  if (options.returnTo && options.returnTo !== '/app/') params.set('returnTo', options.returnTo);
  const query = params.toString();
  return `/app/preferences/signalements${query ? `?${query}` : ''}`;
}

/** L'école déjà ouverte dans la gestion, lue dans l'adresse de retour (`/app/gestion/<id>/…`). */
export const schoolOfReturn = (returnTo: string): string | undefined => /^\/app\/gestion\/([\da-f-]{36})\//i.exec(returnTo)?.[1];

export const rowsOf =(facts: Pick<PreferenceFacts, 'themes'>): ThemeRow[] =>
  facts.themes.map(theme => ({ key: theme.key, title: theme.title, visible: theme.visible, defaultVisible: theme.defaultVisible, defaultPosition: theme.defaultPosition }));

export const baselineOf = (facts: PreferenceFacts): PreferenceDraft =>
  ({ version: facts.version, visibilityEditable: facts.personalizationAllowed, mode: facts.mode, rows: rowsOf(facts) });

/** Un brouillon d'une autre version du compte, ou d'une autre politique de l'école, n'est jamais rejoué sur l'état courant. */
export function usableDraft(draft: PreferenceDraft | null, facts: PreferenceFacts): PreferenceDraft | null {
  return draft !== null && draft.version === facts.version && draft.visibilityEditable === facts.personalizationAllowed ? draft : null;
}

const sameOrder = (left: readonly ThemeRow[], right: readonly ThemeRow[]) => left.length === right.length && left.every((row, index) => row.key === right[index]?.key);
const sameVisibility = (left: readonly ThemeRow[], right: readonly ThemeRow[]) => {
  const shown = new Map(right.map(row => [row.key, row.visible]));
  return left.length === right.length && left.every(row => shown.get(row.key) === row.visible);
};

/** Ce qui diffère du dernier état confirmé. Une visibilité que l'école impose ne compte jamais : elle ne peut pas être enregistrée. */
export function changesOf(draft: PreferenceDraft, baseline: PreferenceDraft) {
  return {
    order: !sameOrder(draft.rows, baseline.rows),
    visibility: baseline.visibilityEditable && !sameVisibility(draft.rows, baseline.rows),
    mode: draft.mode !== baseline.mode,
  };
}

export function isPreferenceDirty(draft: PreferenceDraft, baseline: PreferenceDraft): boolean {
  const changes = changesOf(draft, baseline);
  return changes.order || changes.visibility || changes.mode;
}

/** Au moins un signalement reste affiché (règle du serveur) : sinon rien ne s'envoie. */
export function preferenceProblem(draft: PreferenceDraft, baseline: PreferenceDraft): string | null {
  if (draft.rows.length === 0) return 'Aucun signalement à enregistrer.';
  if (new Set(draft.rows.map(row => row.key)).size !== draft.rows.length) return 'Un signalement figure deux fois.';
  return baseline.visibilityEditable && !draft.rows.some(row => row.visible) ? 'Gardez au moins un signalement affiché.' : null;
}

/**
 * Corps de `PUT observation-preferences` (sans `operationId`) : seulement ce qui a changé. Ordre, visibilité et mode se séparent,
 * si bien qu'en visibilité imposée l'ordre part seul et n'est pas refusé avec elle.
 */
export function preferenceBody(draft: PreferenceDraft, baseline: PreferenceDraft): Record<string, unknown> {
  const changes = changesOf(draft, baseline);
  return {
    ...(changes.mode ? { mode: draft.mode } : {}),
    ...(changes.order ? { order: draft.rows.map(row => row.key) } : {}),
    ...(changes.visibility ? { visibility: draft.rows.map(row => ({ key: row.key, visible: row.visible })) } : {}),
  };
}

/** Rétablir l'ordre et l'affichage : toujours à l'ADMIN (portée « mon compte »), au moniteur seulement dans une école libre. */
export const canResetPresentation = (rights: { administrator: boolean; personalizationAllowed: boolean }): boolean =>
  rights.administrator || rights.personalizationAllowed;

/** Reprise d'une configuration existante : son ordre, puis (si l'école le permet) son affichage et son mode. Les clés inconnues sont ignorées. */
export function applyCandidate(
  draft: PreferenceDraft,
  candidate: { mode: PreferenceMode; themes: readonly { key: string; visible: boolean }[] },
): PreferenceDraft {
  const byKey = new Map(draft.rows.map(row => [row.key, row]));
  const picked = candidate.themes.flatMap(theme => byKey.has(theme.key) ? [{ ...byKey.get(theme.key)!, visible: draft.visibilityEditable ? theme.visible : byKey.get(theme.key)!.visible }] : []);
  const kept = new Set(picked.map(row => row.key));
  const rows = [...picked, ...draft.rows.filter(row => !kept.has(row.key))];
  return { ...draft, rows: rows.some(row => row.visible) ? rows : draft.rows, mode: candidate.mode };
}

/**
 * Tuiles de « Signaler » telles que le moniteur les verra. En ordre manuel, c'est le brouillon. En classement intelligent, l'ordre vient du
 * serveur (palette enregistrée) ; un thème rendu visible depuis est ajouté à la fin, un thème masqué est retiré, jusqu'à l'enregistrement.
 */
export function previewKeys(draft: PreferenceDraft, baseline: PreferenceDraft, palette: readonly string[]): string[] {
  const visible = draft.rows.filter(row => row.visible).map(row => row.key);
  if (draft.mode === 'MANUAL' || baseline.mode !== 'SMART') return visible;
  const shown = new Set(visible), ordered = palette.filter(key => shown.has(key));
  return [...ordered, ...visible.filter(key => !ordered.includes(key))];
}

/** Ce que l'écran fait de la réponse d'un enregistrement refusé. */
export type PreferenceRefusal = 'conflict' | 'policy' | 'access' | null;
export function preferenceRefusal(code: string): PreferenceRefusal {
  if (code === 'VERSION_CONFLICT' || code === 'PRECONDITION_REQUIRED') return 'conflict';
  if (code === 'OBSERVATION_PERSONALIZATION_DISABLED') return 'policy';
  if (['OBSERVATION_THEMES_ACCESS_REQUIRED', 'FORBIDDEN', 'ACCESS_DENIED'].includes(code)) return 'access';
  return null;
}

export const refusalNotice: Record<Exclude<PreferenceRefusal, null>, { title: string; message: string }> = {
  conflict: { title: 'Préférences rechargées', message: 'Elles ont changé entre-temps ; vos modifications n’ont pas été enregistrées.' },
  policy: { title: 'Affichage imposé par l’école', message: 'L’école vient d’imposer les signalements affichés ; vos modifications n’ont pas été enregistrées.' },
  access: { title: 'Accès modifié', message: 'Vos accès ne permettent plus de modifier ces préférences.' },
};

/** Confirmation d'un retour à la référence de l'école ouverte : l'école nommée, la portée « votre compte », jamais un collègue. */
export function presentationResetCopy(schoolName: string, options: { personalizationAllowed: boolean; dirty: boolean }): { title: string; message: string } {
  return {
    title: 'Rétablir l’ordre et la visibilité ?',
    message: `Votre ordre et votre affichage reprennent la référence de ${schoolName}, sur votre compte seulement.`
      + `${options.personalizationAllowed ? ' Les écoles qui laissent personnaliser appliquent aussi ce choix.' : ''}`
      + `${options.dirty ? ' Les modifications non enregistrées sont abandonnées.' : ''}`,
  };
}

export const learningResetCopy = (dirty: boolean) => ({
  title: 'Recommencer l’apprentissage ?',
  message: `Le classement intelligent repart de votre ordre manuel et n’apprend que des nouveaux signalements. Aucune observation n’est supprimée.${dirty ? ' Les modifications non enregistrées sont abandonnées.' : ''}`,
});
