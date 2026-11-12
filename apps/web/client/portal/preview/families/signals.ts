import { ids, previewId, previewMembership } from '../fixtures';
import type { PreviewFamily, PreviewRequest, PreviewTools } from '../family';

/**
 * Synthetic observation themes (#331): the 18 stable keys of the school catalogue, twelve shown by default.
 * Mirrors `GET/PUT observation-themes` with If-Match; reachable only from the separate preview entry.
 * Also mirrors the ACCOUNT preferences of R08 (`observation-preferences`), read and written in the frame of the open school.
 */
const catalogue: readonly [string, string][] = [
  ['observation', 'Observation'], ['speed', 'Vitesse'], ['right-priority', 'Priorité de droite'], ['give-way', 'Cédez-le-passage'],
  ['intersections', 'Intersections'], ['placement', 'Placement'], ['lane-change', 'Changement de voie'], ['indicators', 'Clignotants'],
  ['following-distance', 'Distance de sécurité'], ['anticipation', 'Anticipation'], ['bends', 'Virages'], ['braking', 'Freinage'],
  ['moving-off', 'Démarrage'], ['manoeuvres', 'Manœuvres'], ['motorway', 'Autoroute'], ['signage', 'Signalisation'],
  ['vehicle', 'Maîtrise du véhicule'], ['eco-driving', 'Éco-conduite'],
];
// `?politique=imposee` : l'aperçu s'ouvre sur une école qui impose l'affichage ; sinon elle laisse personnaliser.
const search = typeof location === 'undefined' ? new URLSearchParams() : new URLSearchParams(location.search);
const settings = { id: previewId(800), schoolId: ids.school, version: 1, canManage: true, personalizationAllowed: search.get('politique') !== 'imposee',
  themes: catalogue.map(([key, title], index) => ({ key, title, visible: index < 12, defaultVisible: index < 12, defaultPosition: index })) };

/** Un seul état par personne ; la politique est celle de `settings` : l'éditeur de l'école et la page personnelle se répondent. */
const account = { version: 1, order: null as string[] | null, visibility: null as Record<string, boolean> | null,
  mode: 'MANUAL' as 'MANUAL' | 'SMART', generation: 0, since: null as string | null };
const adoptionOffered = () => search.get('adoption') === '1' && account.version === 1;

function preferences() {
  const allowed = settings.personalizationAllowed;
  const reference = new Map(settings.themes.map(theme => [theme.key, theme]));
  const personal = allowed ? account.visibility : null;
  const effective = (key: string) => personal && Object.values(personal).some(Boolean) ? personal[key] ?? false : reference.get(key)!.visible;
  const order = account.order ?? settings.themes.map(theme => theme.key);
  // Classement synthétique : l'inverse de l'ordre manuel tant que l'apprentissage n'a pas été recommencé.
  const ranked = account.mode === 'SMART' && account.since === null ? [...order].reverse() : order;
  return { id: ids.person, schoolId: ids.school, version: account.version, personalizationAllowed: allowed,
    orderCustomized: account.order !== null, visibilityCustomized: allowed && account.visibility !== null, mode: account.mode,
    themes: order.map(key => ({ ...reference.get(key)!, competencyKeys: [] as string[], visible: effective(key), schoolVisible: reference.get(key)!.visible, visibilityEditable: allowed })),
    palette: ranked.filter(effective), rankedOn: account.mode === 'SMART' ? new Date().toISOString().slice(0, 10) : null,
    learning: { generation: account.generation, since: account.since },
    adoption: adoptionOffered() ? { candidates: [
      { schoolId: previewId(901), schoolName: 'Auto-école du Lac', mode: 'SMART', themes: catalogue.map(([key], index) => ({ key, visible: index % 2 === 0 })) },
      { schoolId: previewId(902), schoolName: 'Auto-école des Alpes', mode: 'MANUAL', themes: [...catalogue].reverse().map(([key]) => ({ key, visible: true })) },
    ] } : null };
}

const keysOf = (value: unknown): string[] | null => Array.isArray(value) && value.every(item => typeof item === 'string') ? value : null;

/** PUT, presentation-reset et learning-reset : If-Match d'abord, puis les droits de la matrice R08, comme le serveur. */
function writePreferences(request: PreviewRequest, tools: PreviewTools): Response | undefined {
  const known = new Set(settings.themes.map(theme => theme.key));
  const administrator = previewMembership.roles.includes('ADMIN');
  const refuse = () => tools.reply(403, { code: 'OBSERVATION_PERSONALIZATION_DISABLED' });
  if (!tools.versionMatches({ version: account.version })) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  if (request.path === 'observation-preferences/learning-reset' && request.method === 'POST') {
    account.generation++; account.since = new Date().toISOString(); account.version++;
    return tools.commit('resetObservationLearning', preferences());
  }
  if (request.path === 'observation-preferences/presentation-reset' && request.method === 'POST') {
    if (!administrator && !settings.personalizationAllowed) return refuse();
    account.order = settings.themes.map(theme => theme.key);
    account.visibility = Object.fromEntries(settings.themes.map(theme => [theme.key, theme.visible]));
    account.version++;
    return tools.commit('resetObservationPresentation', preferences());
  }
  if (request.path !== 'observation-preferences' || request.method !== 'PUT') return undefined;
  const { mode, order, visibility, themes } = request.body;
  if (themes !== undefined || (mode === undefined && order === undefined && visibility === undefined)) return tools.reply(400, { code: 'INVALID_REQUEST' });
  if (mode !== undefined && mode !== 'MANUAL' && mode !== 'SMART') return tools.reply(400, { code: 'INVALID_REQUEST' });
  const wantedOrder = order === undefined ? null : keysOf(order);
  if (order !== undefined && (!wantedOrder || wantedOrder.length !== known.size || new Set(wantedOrder).size !== known.size || wantedOrder.some(key => !known.has(key)))) return tools.reply(400, { code: 'INVALID_REQUEST' });
  let wantedVisibility: Record<string, boolean> | null = null;
  if (visibility !== undefined) {
    if (!settings.personalizationAllowed) return refuse();
    const rows: { key: string; visible: boolean }[] = Array.isArray(visibility) ? visibility : [];
    if (rows.length !== known.size || new Set(rows.map(row => row.key)).size !== known.size || rows.some(row => !known.has(row.key)) || !rows.some(row => row.visible)) return tools.reply(400, { code: 'INVALID_REQUEST' });
    wantedVisibility = Object.fromEntries(rows.map(row => [row.key, row.visible]));
  }
  if (wantedOrder) account.order = wantedOrder;
  if (wantedVisibility) account.visibility = wantedVisibility;
  if (mode) { account.mode = mode; if (mode === 'SMART') account.since = null; }
  account.version++;
  return tools.commit('saveObservationPreferences', preferences());
}

export const signalsFamily: PreviewFamily = {
  name: 'signals',
  read(request, tools) {
    if (request.path === 'observation-preferences') return tools.reply(200, tools.envelope(preferences()));
    if (request.path !== 'observation-themes') return undefined;
    return tools.reply(200, tools.envelope(settings));
  },
  write(request, tools) {
    if (request.path.startsWith('observation-preferences')) return writePreferences(request, tools);
    if (request.path !== 'observation-themes' || request.method !== 'PUT') return undefined;
    if (!tools.versionMatches(settings)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    const wanted: { key: string; visible: boolean }[] = Array.isArray(request.body.themes) ? request.body.themes : [];
    const known = new Map(settings.themes.map(theme => [theme.key, theme]));
    if (wanted.length !== known.size || wanted.some(item => !known.has(item.key)) || !wanted.some(item => item.visible)) return tools.reply(400, { code: 'INVALID_REQUEST' });
    settings.themes = wanted.map(item => ({ ...known.get(item.key)!, visible: item.visible }));
    if (typeof request.body.personalizationAllowed === 'boolean') settings.personalizationAllowed = request.body.personalizationAllowed;
    settings.version++;
    return tools.commit('saveObservationThemes', settings);
  },
  refusalCode: request => request.path === 'observation-themes' ? 'OBSERVATION_THEMES_INVALID'
    : request.path.startsWith('observation-preferences') ? 'OBSERVATION_PERSONALIZATION_DISABLED' : undefined,
};
