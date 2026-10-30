import { ids, previewId } from '../fixtures';
import type { PreviewFamily } from '../family';

/**
 * Synthetic observation themes (#331): the 18 stable keys of the school catalogue, twelve shown by default.
 * Mirrors `GET/PUT observation-themes` with If-Match; reachable only from the separate preview entry.
 */
const catalogue: readonly [string, string][] = [
  ['observation', 'Observation'], ['speed', 'Vitesse'], ['right-priority', 'Priorité de droite'], ['give-way', 'Cédez-le-passage'],
  ['intersections', 'Intersections'], ['placement', 'Placement'], ['lane-change', 'Changement de voie'], ['indicators', 'Clignotants'],
  ['following-distance', 'Distance de sécurité'], ['anticipation', 'Anticipation'], ['bends', 'Virages'], ['braking', 'Freinage'],
  ['moving-off', 'Démarrage'], ['manoeuvres', 'Manœuvres'], ['motorway', 'Autoroute'], ['signage', 'Signalisation'],
  ['vehicle', 'Maîtrise du véhicule'], ['eco-driving', 'Éco-conduite'],
];
const settings = { id: previewId(800), schoolId: ids.school, version: 1, canManage: true,
  themes: catalogue.map(([key, title], index) => ({ key, title, visible: index < 12, defaultVisible: index < 12, defaultPosition: index })) };

export const signalsFamily: PreviewFamily = {
  name: 'signals',
  read(request, tools) {
    if (request.path !== 'observation-themes') return undefined;
    return tools.reply(200, tools.envelope(settings));
  },
  write(request, tools) {
    if (request.path !== 'observation-themes' || request.method !== 'PUT') return undefined;
    if (!tools.versionMatches(settings)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    const wanted: { key: string; visible: boolean }[] = Array.isArray(request.body.themes) ? request.body.themes : [];
    const known = new Map(settings.themes.map(theme => [theme.key, theme]));
    if (wanted.length !== known.size || wanted.some(item => !known.has(item.key)) || !wanted.some(item => item.visible)) return tools.reply(400, { code: 'INVALID_REQUEST' });
    settings.themes = wanted.map(item => ({ ...known.get(item.key)!, visible: item.visible }));
    settings.version++;
    return tools.commit('saveObservationThemes', settings);
  },
  refusalCode: request => request.path === 'observation-themes' ? 'OBSERVATION_THEMES_INVALID' : undefined,
};
