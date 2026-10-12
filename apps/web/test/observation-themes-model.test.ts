import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  counterLabel, draftProblem, dropIndex, isDefaultConfiguration, isDefaultOrder, isDirty, isLastVisible, moveAnnouncement, moveTheme, moveThemeBy, moveThemeTo,
  previewTiles, resetAll, resetOrder, saveBody, settingsOf, toggleAnnouncement, toggleTheme, visibleCount, type ThemeRow,
} from '../client/console/observation-themes-model.js';
import { createCommand, commandHeaders, commandSpecs, receiptMatches } from '../client/command-core.js';
import { observationThemesSchema } from '../client/school-api.js';

/** Catalogue du contrat (docs/implementation/signalements-configurables-20261012.md) : dix-huit clés, douze affichées à l'origine. */
const catalogue: readonly { key: string; title: string; competencyKeys: string[]; visible: boolean }[] = [
  { key: 'vehicle', title: 'Maîtrise du véhicule', competencyKeys: ['vehicule'], visible: true },
  { key: 'observation', title: 'Observation et contrôles', competencyKeys: ['observation'], visible: true },
  { key: 'right-priority', title: 'Priorité à droite', competencyKeys: ['priorites'], visible: true },
  { key: 'signage', title: 'Signalisation', competencyKeys: ['priorites'], visible: true },
  { key: 'give-way', title: 'Céder le passage', competencyKeys: ['priorites'], visible: true },
  { key: 'intersections', title: 'Intersections et giratoires', competencyKeys: ['intersections'], visible: true },
  { key: 'speed', title: 'Vitesse', competencyKeys: ['vitesse'], visible: true },
  { key: 'placement', title: 'Placement sur la chaussée', competencyKeys: ['placement'], visible: true },
  { key: 'manoeuvres', title: 'Manœuvres', competencyKeys: ['manoeuvres', 'parking'], visible: true },
  { key: 'motorway', title: 'Autoroute', competencyKeys: ['autoroute', 'motorway'], visible: true },
  { key: 'anticipation', title: 'Anticipation', competencyKeys: ['anticipation'], visible: true },
  { key: 'indicators', title: 'Clignotants', competencyKeys: ['observation'], visible: true },
  { key: 'following-distance', title: 'Distance de sécurité', competencyKeys: ['vitesse'], visible: false },
  { key: 'braking', title: 'Freinage', competencyKeys: ['vehicule'], visible: false },
  { key: 'lane-change', title: 'Changement de voie', competencyKeys: ['placement'], visible: false },
  { key: 'moving-off', title: 'Démarrage', competencyKeys: ['vehicule'], visible: false },
  { key: 'bends', title: 'Virages', competencyKeys: ['placement'], visible: false },
  { key: 'eco-driving', title: 'Éco-conduite', competencyKeys: ['vehicule'], visible: false },
];
const themes = catalogue.map((theme, index) => ({ ...theme, defaultVisible: theme.visible, defaultPosition: index }));
const row = (theme: typeof themes[number]): ThemeRow => ({ key: theme.key, title: theme.title, visible: theme.visible, defaultVisible: theme.defaultVisible, defaultPosition: theme.defaultPosition });
const origin: ThemeRow[] = themes.map(row);
const keys = (rows: readonly { key: string }[]) => rows.map(item => item.key);
const only = (rows: readonly ThemeRow[], shown: string[]): ThemeRow[] => rows.map(item => ({ ...item, visible: shown.includes(item.key) }));

describe('Compteur et garde « au moins un affiché »', () => {
  test('douze affichés sur dix-huit à l’origine, le total vient du compte réel', () => {
    expect(visibleCount(origin)).toBe(12);
    expect(counterLabel(origin.slice(0, 5))).toBe('5 affichés sur 5');
    expect(counterLabel(origin)).toBe('12 affichés sur 18');
  });

  test('le singulier suit le nombre', () => {
    expect(counterLabel(only(origin, ['speed']))).toBe('1 affiché sur 18');
    expect(counterLabel(only(origin, ['speed', 'vehicle']))).toBe('2 affichés sur 18');
  });

  test('masquer puis afficher met le compteur à jour sans toucher l’ordre', () => {
    const hidden = toggleTheme(origin, 'vehicle');
    expect(hidden.find(item => item.key === 'vehicle')?.visible).toBe(false);
    expect(counterLabel(hidden)).toBe('11 affichés sur 18');
    expect(keys(hidden)).toEqual(keys(origin));
    expect(counterLabel(toggleTheme(hidden, 'braking'))).toBe('12 affichés sur 18');
  });

  test('le dernier thème affiché ne se masque pas', () => {
    const single = only(origin, ['signage']);
    expect(isLastVisible(single, 'signage')).toBe(true);
    expect(isLastVisible(single, 'speed')).toBe(false);
    expect(isLastVisible(origin, 'signage')).toBe(false);
    expect(toggleTheme(single, 'signage')).toEqual(single);
    expect(visibleCount(toggleTheme(single, 'signage'))).toBe(1);
    expect(visibleCount(toggleTheme(single, 'speed'))).toBe(2);
  });

  test('un brouillon sans aucun thème affiché n’est pas enregistrable', () => {
    expect(draftProblem(origin)).toBeNull();
    expect(draftProblem(only(origin, []))).toBe('Gardez au moins un signalement affiché.');
    expect(draftProblem([])).not.toBeNull();
    expect(draftProblem([origin[0]!, origin[0]!])).toBe('Un signalement figure deux fois.');
  });

  test('une clé inconnue est ignorée', () => {
    expect(toggleTheme(origin, 'inconnu')).toEqual(origin);
  });
});

describe('Déplacement', () => {
  test('moveTheme place l’élément à la position demandée et décale les autres', () => {
    expect(moveTheme(['a', 'b', 'c', 'd'], 0, 2)).toEqual(['b', 'c', 'a', 'd']);
    expect(moveTheme(['a', 'b', 'c', 'd'], 3, 1)).toEqual(['a', 'd', 'b', 'c']);
    expect(moveTheme(['a', 'b', 'c'], 1, 1)).toEqual(['a', 'b', 'c']);
  });

  test('les positions hors bornes sont ramenées aux extrémités, les sources hors bornes ignorées', () => {
    expect(moveTheme(['a', 'b', 'c'], 1, -5)).toEqual(['b', 'a', 'c']);
    expect(moveTheme(['a', 'b', 'c'], 1, 99)).toEqual(['a', 'c', 'b']);
    expect(moveTheme(['a', 'b', 'c'], -1, 0)).toEqual(['a', 'b', 'c']);
    expect(moveTheme(['a', 'b', 'c'], 3, 0)).toEqual(['a', 'b', 'c']);
    expect(moveTheme(['a', 'b', 'c'], 0.5, 1)).toEqual(['a', 'b', 'c']);
  });

  test('moveTheme ne modifie pas la liste d’origine', () => {
    const list = ['a', 'b', 'c'];
    moveTheme(list, 0, 2);
    expect(list).toEqual(['a', 'b', 'c']);
    expect(moveTheme(list, 1, 1)).not.toBe(list);
  });

  test('Monter / Descendre déplacent d’un cran et s’arrêtent aux bords', () => {
    expect(keys(moveThemeBy(origin, 'speed', -1)).slice(4, 8)).toEqual(['give-way', 'speed', 'intersections', 'placement']);
    expect(keys(moveThemeBy(origin, 'speed', 1)).slice(5, 8)).toEqual(['intersections', 'placement', 'speed']);
    expect(keys(moveThemeBy(origin, 'vehicle', -1))).toEqual(keys(origin));
    expect(keys(moveThemeBy(origin, 'eco-driving', 1))).toEqual(keys(origin));
    expect(keys(moveThemeBy(origin, 'inconnu', 1))).toEqual(keys(origin));
  });

  test('Début et Fin déplacent aux extrémités', () => {
    expect(moveThemeBy(origin, 'speed', -origin.length)[0]?.key).toBe('speed');
    expect(moveThemeBy(origin, 'speed', origin.length).at(-1)?.key).toBe('speed');
  });

  test('un déplacement garde les dix-huit thèmes une fois chacun et leur affichage', () => {
    const next = moveThemeTo(toggleTheme(origin, 'vehicle'), 'braking', 0);
    expect(next).toHaveLength(18);
    expect(new Set(keys(next)).size).toBe(18);
    expect(next[0]?.key).toBe('braking');
    expect(next.find(item => item.key === 'vehicle')?.visible).toBe(false);
  });

  test('moveThemeTo : cible par clé', () => {
    expect(keys(moveThemeTo(origin, 'vehicle', 2)).slice(0, 3)).toEqual(['observation', 'right-priority', 'vehicle']);
    expect(keys(moveThemeTo(origin, 'inconnu', 2))).toEqual(keys(origin));
  });

  test('annonces vocales : position et état', () => {
    const next = moveThemeBy(origin, 'vehicle', 1);
    expect(moveAnnouncement(next, 'vehicle')).toBe('Maîtrise du véhicule : position 2 sur 18.');
    expect(moveAnnouncement(next, 'inconnu')).toBe('');
    const hidden = toggleTheme(origin, 'speed');
    expect(toggleAnnouncement(hidden, 'speed')).toBe('Vitesse masqué. 11 affichés sur 18.');
    expect(toggleAnnouncement(toggleTheme(hidden, 'speed'), 'speed')).toBe('Vitesse affiché. 12 affichés sur 18.');
  });
});

describe('Positions de glissement', () => {
  const middles = [20, 60, 100, 140];
  test('la ligne tenue ne change de place qu’en dépassant le milieu de sa voisine', () => {
    expect(dropIndex(middles, 0, 20)).toBe(0);
    expect(dropIndex(middles, 0, 59)).toBe(0);
    expect(dropIndex(middles, 0, 61)).toBe(1);
    expect(dropIndex(middles, 0, 500)).toBe(3);
    expect(dropIndex(middles, 3, 61)).toBe(2);
    expect(dropIndex(middles, 3, 59)).toBe(1);
    expect(dropIndex(middles, 3, -50)).toBe(0);
    expect(dropIndex(middles, 2, 100)).toBe(2);
  });
});

describe('Réinitialisations', () => {
  const scrambled = toggleTheme(toggleTheme(moveThemeTo(moveThemeTo(origin, 'braking', 0), 'vehicle', 14), 'signage'), 'lane-change');

  test('l’ordre d’origine rétablit les positions et garde l’affichage choisi', () => {
    const next = resetOrder(scrambled);
    expect(keys(next)).toEqual(keys(origin));
    expect(next.map(item => item.visible)).toEqual(keys(next).map(key => scrambled.find(other => other.key === key)!.visible));
    expect(next.find(item => item.key === 'signage')?.visible).toBe(false);
    expect(next.find(item => item.key === 'lane-change')?.visible).toBe(true);
  });

  test('la configuration d’origine rétablit l’ordre et l’affichage', () => {
    expect(resetAll(scrambled)).toEqual(origin);
  });

  test('l’ordre d’origine se calcule depuis defaultPosition, pas depuis l’ordre reçu', () => {
    const reversed = [...origin].reverse();
    expect(keys(resetOrder(reversed))).toEqual(keys(origin));
  });

  test('un catalogue dont le défaut n’est pas l’ordre de lecture est respecté', () => {
    const custom: ThemeRow[] = [
      { key: 'b', title: 'B', visible: true, defaultVisible: false, defaultPosition: 1 },
      { key: 'a', title: 'A', visible: false, defaultVisible: true, defaultPosition: 0 },
    ];
    expect(isDefaultOrder(custom)).toBe(false);
    expect(resetAll(custom).map(item => [item.key, item.visible])).toEqual([['a', true], ['b', false]]);
  });

  test('détection de l’état d’origine', () => {
    expect(isDefaultOrder(origin)).toBe(true);
    expect(isDefaultConfiguration(origin)).toBe(true);
    expect(isDefaultOrder(toggleTheme(origin, 'vehicle'))).toBe(true);
    expect(isDefaultConfiguration(toggleTheme(origin, 'vehicle'))).toBe(false);
    expect(isDefaultOrder(moveThemeBy(origin, 'vehicle', 1))).toBe(false);
    expect(isDefaultConfiguration(resetAll(scrambled))).toBe(true);
  });

  test('les réinitialisations ne modifient pas leur entrée', () => {
    const copy = JSON.parse(JSON.stringify(scrambled)) as ThemeRow[];
    resetOrder(scrambled); resetAll(scrambled);
    expect(scrambled).toEqual(copy);
  });
});

describe('Brouillon, aperçu et commande', () => {
  test('un brouillon est modifié dès qu’un ordre ou un affichage diffère, et plus quand on revient en arrière', () => {
    const saved = settingsOf(origin);
    expect(isDirty(settingsOf(origin), saved)).toBe(false);
    expect(isDirty(settingsOf(toggleTheme(origin, 'vehicle')), saved)).toBe(true);
    expect(isDirty(settingsOf(moveThemeBy(origin, 'vehicle', 1)), saved)).toBe(true);
    expect(isDirty(settingsOf(moveThemeBy(moveThemeBy(origin, 'vehicle', 1), 'vehicle', -1)), saved)).toBe(false);
    expect(isDirty(settingsOf(toggleTheme(toggleTheme(origin, 'vehicle'), 'vehicle')), saved)).toBe(false);
    expect(isDirty(settingsOf(origin).slice(1), saved)).toBe(true);
  });

  test('l’aperçu montre les thèmes affichés dans l’ordre du brouillon, en direct', () => {
    expect(previewTiles(origin)).toHaveLength(12);
    expect(keys(previewTiles(origin)).slice(-2)).toEqual(['anticipation', 'indicators']);
    const edited = toggleTheme(moveThemeTo(toggleTheme(origin, 'lane-change'), 'lane-change', 0), 'signage');
    expect(keys(previewTiles(edited)).slice(0, 3)).toEqual(['lane-change', 'vehicle', 'observation']);
    expect(keys(previewTiles(edited))).not.toContain('signage');
    expect(keys(previewTiles(edited))).not.toContain('braking');
  });

  test('le corps de la commande porte les dix-huit clés une fois, dans le nouvel ordre, avec leur affichage', () => {
    const edited = toggleTheme(moveThemeTo(origin, 'braking', 1), 'vehicle');
    const body = saveBody(edited);
    expect(Object.keys(body)).toEqual(['themes']);
    expect(body.themes).toHaveLength(18);
    expect(body.themes.slice(0, 3)).toEqual([{ key: 'vehicle', visible: false }, { key: 'braking', visible: false }, { key: 'observation', visible: true }]);
    expect(new Set(body.themes.map(theme => theme.key)).size).toBe(18);
    expect(body.themes.every(theme => Object.keys(theme).sort().join() === 'key,visible')).toBe(true);
    expect(JSON.stringify(body).length).toBeLessThan(2_000);
  });

  test('la commande suit le contrat HTTP : PUT, If-Match, Idempotency-Key, corps avec operationId', () => {
    const schoolId = randomUUID();
    const command = createCommand({ schoolId, kind: 'saveObservationThemes', path: 'observation-themes', ifMatch: 3, resourceVersion: 3, body: saveBody(origin) });
    expect(commandSpecs.saveObservationThemes).toMatchObject({ method: 'PUT', expectedStatus: 200, target: 'school', operationType: 'SAVE_OBSERVATION_THEMES' });
    expect(commandHeaders(command, 'csrf')).toMatchObject({ 'If-Match': '"3"', 'Idempotency-Key': command.operationId });
    expect(command.body.operationId).toBe(command.operationId);
    expect(Object.keys(command.body).sort()).toEqual(['operationId', 'themes']);
    const receipt = { operationId: command.operationId, commandType: 'SAVE_OBSERVATION_THEMES', resourceType: 'ObservationThemeSettings', resourceId: schoolId,
      committedAt: '2026-10-12T08:00:00Z', resourceVersion: 4 };
    expect(receiptMatches(command, receipt)).toBe(true);
    expect(receiptMatches(command, { ...receipt, resourceVersion: 3 })).toBe(false);
    expect(receiptMatches(command, { ...receipt, resourceId: randomUUID() })).toBe(false);
  });
});

describe('Projection du serveur', () => {
  const schoolId = randomUUID();
  const projection = { id: schoolId, schoolId, version: 1, canManage: true, themes };

  test('les dix-huit thèmes du contrat sont lus tels quels', () => {
    const parsed = observationThemesSchema.safeParse(projection);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.themes).toHaveLength(18);
      expect(parsed.data.themes.filter(theme => theme.visible)).toHaveLength(12);
    }
  });

  test.each([
    ['sans version', { ...projection, version: undefined }],
    ['version nulle', { ...projection, version: 0 }],
    ['sans canManage', { ...projection, canManage: undefined }],
    ['aucun thème', { ...projection, themes: [] }],
    ['clé en double', { ...projection, themes: [themes[0], themes[0]] }],
    ['position d’origine en double', { ...projection, themes: [themes[0], { ...themes[1], defaultPosition: 0 }] }],
    ['clé invalide', { ...projection, themes: [{ ...themes[0], key: 'Vehicle Maîtrise' }] }],
    ['titre vide', { ...projection, themes: [{ ...themes[0], title: '' }] }],
    ['visible non booléen', { ...projection, themes: [{ ...themes[0], visible: 'oui' }] }],
    ['école invalide', { ...projection, schoolId: 'x' }],
  ])('refuse une projection %s', (_label, value) => {
    expect(observationThemesSchema.safeParse(value).success).toBe(false);
  });
});
