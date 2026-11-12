import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import { commandHeaders, commandMessage, commandSpecs, createCommand, receiptMatches } from '../client/command-core.js';
import { commandConflictKeys } from '../client/command-conflicts.js';
import {
  applyCandidate, baselineOf, canPersonalizeSignals, canResetPresentation, changesOf, isPreferenceDirty, learningResetCopy, preferenceBody, preferenceProblem,
  preferenceRefusal, presentationResetCopy, previewKeys, refusalNotice, schoolOfReturn, signalsPreferencesHref, usableDraft, type PreferenceDraft, type PreferenceFacts,
} from '../client/console/observation-preferences-model.js';
import { moveThemeBy, toggleTheme } from '../client/console/observation-themes-model.js';
import { observationPreferencesSchema, observationThemesSchema } from '../client/school-api.js';

const keys = ['observation', 'speed', 'give-way', 'placement'] as const;
const theme = (key: string, index: number, visible = true) => ({ key, title: key.toUpperCase(), visible, defaultVisible: true, defaultPosition: index });
const facts = (overrides: Partial<PreferenceFacts> = {}): PreferenceFacts => ({
  version: 1, personalizationAllowed: true, mode: 'MANUAL', themes: keys.map((key, index) => theme(key, index)), palette: [...keys], ...overrides,
});
const schoolId = randomUUID();
const personId = randomUUID();

describe('Droits sur les signalements du compte (R08)', () => {
  test('moniteur et administrateur règlent leurs signalements ; l’élève seul n’a rien', () => {
    expect(canPersonalizeSignals(['INSTRUCTOR'])).toBe(true);
    expect(canPersonalizeSignals(['ADMIN'])).toBe(true);
    expect(canPersonalizeSignals(['ADMIN', 'INSTRUCTOR'])).toBe(true);
    expect(canPersonalizeSignals(['LEARNER'])).toBe(false);
  });

  test.each([
    ['administrateur, école libre', true, true, true],
    ['administrateur, affichage imposé', true, false, true],
    ['moniteur, école libre', false, true, true],
    ['moniteur, affichage imposé', false, false, false],
  ])('« Rétablir l’ordre et la visibilité » : %s', (_name, administrator, personalizationAllowed, expected) => {
    expect(canResetPresentation({ administrator, personalizationAllowed })).toBe(expected);
  });
});

describe('Ce qui s’envoie à l’enregistrement', () => {
  test('école libre : ordre, affichage et mode partent, et seulement ce qui a changé', () => {
    const baseline = baselineOf(facts());
    const reordered: PreferenceDraft = { ...baseline, rows: moveThemeBy(baseline.rows, 'placement', -3), mode: 'SMART' };
    expect(preferenceBody(reordered, baseline)).toEqual({ mode: 'SMART', order: ['placement', 'observation', 'speed', 'give-way'] });
    const hidden: PreferenceDraft = { ...baseline, rows: toggleTheme(baseline.rows, 'speed') };
    expect(preferenceBody(hidden, baseline)).toEqual({ visibility: keys.map(key => ({ key, visible: key !== 'speed' })) });
    expect(preferenceBody(baseline, baseline)).toEqual({});
  });

  test('affichage imposé : l’ordre part SEUL, jamais avec une visibilité que le serveur refuserait', () => {
    const baseline = baselineOf(facts({ personalizationAllowed: false }));
    // Même si un brouillon masque un thème, la visibilité imposée ne s'envoie jamais : l'ordre ne risque pas d'être refusé avec elle.
    const draft: PreferenceDraft = { ...baseline, rows: toggleTheme(moveThemeBy(baseline.rows, 'give-way', -2), 'speed') };
    const body = preferenceBody(draft, baseline);
    expect(body).toEqual({ order: ['give-way', 'observation', 'speed', 'placement'] });
    expect(body).not.toHaveProperty('visibility');
    expect(changesOf(draft, baseline)).toEqual({ order: true, visibility: false, mode: false });
  });

  test('affichage imposé : un changement d’affichage seul n’est pas une modification à enregistrer', () => {
    const baseline = baselineOf(facts({ personalizationAllowed: false }));
    expect(isPreferenceDirty({ ...baseline, rows: toggleTheme(baseline.rows, 'speed') }, baseline)).toBe(false);
    expect(isPreferenceDirty({ ...baseline, mode: 'SMART' }, baseline)).toBe(true);
  });

  test('on ne peut pas tout masquer en école libre', () => {
    const baseline = baselineOf(facts({ themes: [theme('observation', 0)], palette: ['observation'] }));
    const hiddenAll: PreferenceDraft = { ...baseline, rows: baseline.rows.map(row => ({ ...row, visible: false })) };
    expect(preferenceProblem(hiddenAll, baseline)).toBe('Gardez au moins un signalement affiché.');
    expect(preferenceProblem(baseline, baseline)).toBeNull();
  });
});

describe('Brouillon lié à un état précis du compte', () => {
  test('un brouillon d’une autre version, ou d’une autre politique d’école, n’est jamais rejoué', () => {
    const baseline = baselineOf(facts({ version: 3 }));
    const draft: PreferenceDraft = { ...baseline, rows: moveThemeBy(baseline.rows, 'speed', 1) };
    expect(usableDraft(draft, facts({ version: 3 }))).toBe(draft);
    expect(usableDraft(draft, facts({ version: 4 }))).toBeNull();
    expect(usableDraft(draft, facts({ version: 3, personalizationAllowed: false }))).toBeNull();
    expect(usableDraft(null, facts())).toBeNull();
  });
});

describe('Aperçu de la grille Signaler', () => {
  test('ordre manuel : le brouillon, thèmes affichés seulement', () => {
    const baseline = baselineOf(facts());
    const draft: PreferenceDraft = { ...baseline, rows: toggleTheme(moveThemeBy(baseline.rows, 'placement', -3), 'speed') };
    expect(previewKeys(draft, baseline, [...keys])).toEqual(['placement', 'observation', 'give-way']);
  });

  test('classement intelligent : l’ordre du serveur, un thème masqué retiré, un thème rendu visible ajouté à la fin', () => {
    const baseline = baselineOf(facts({ mode: 'SMART', themes: [theme('observation', 0), theme('speed', 1), theme('give-way', 2, false), theme('placement', 3)], palette: ['placement', 'observation', 'speed'] }));
    expect(previewKeys(baseline, baseline, ['placement', 'observation', 'speed'])).toEqual(['placement', 'observation', 'speed']);
    const edited: PreferenceDraft = { ...baseline, rows: toggleTheme(toggleTheme(baseline.rows, 'observation'), 'give-way') };
    expect(previewKeys(edited, baseline, ['placement', 'observation', 'speed'])).toEqual(['placement', 'speed', 'give-way']);
  });
});

describe('Adoption d’une configuration existante (plusieurs écoles)', () => {
  const candidate = { mode: 'SMART' as const, themes: [{ key: 'placement', visible: true }, { key: 'speed', visible: false }, { key: 'inconnu', visible: true }] };

  test('école libre : l’ordre, l’affichage et le mode sont repris ; une clé inconnue est ignorée ; le reste suit', () => {
    const adopted = applyCandidate(baselineOf(facts()), candidate);
    expect(adopted.rows.map(row => row.key)).toEqual(['placement', 'speed', 'observation', 'give-way']);
    expect(adopted.rows.find(row => row.key === 'speed')?.visible).toBe(false);
    expect(adopted.mode).toBe('SMART');
  });

  test('affichage imposé : seul l’ordre est repris', () => {
    const adopted = applyCandidate(baselineOf(facts({ personalizationAllowed: false })), candidate);
    expect(adopted.rows.map(row => row.key)).toEqual(['placement', 'speed', 'observation', 'give-way']);
    expect(adopted.rows.every(row => row.visible)).toBe(true);
  });
});

describe('Refus du serveur pendant une modification', () => {
  test.each([
    ['VERSION_CONFLICT', 'conflict'], ['PRECONDITION_REQUIRED', 'conflict'],
    ['OBSERVATION_PERSONALIZATION_DISABLED', 'policy'],
    ['FORBIDDEN', 'access'], ['ACCESS_DENIED', 'access'], ['OBSERVATION_THEMES_ACCESS_REQUIRED', 'access'],
    ['AUTRE_CODE', null],
  ])('%s', (code, expected) => {
    expect(preferenceRefusal(code)).toBe(expected);
  });

  test('chaque refus dit que rien n’a été enregistré', () => {
    expect(refusalNotice.policy.message).toContain('n’ont pas été enregistrées');
    expect(refusalNotice.conflict.message).toContain('n’ont pas été enregistrées');
    expect(commandMessage('OBSERVATION_PERSONALIZATION_DISABLED')).toBe('Cette école impose les signalements affichés. Rien n’a été modifié.');
  });
});

describe('Confirmations courtes', () => {
  test('le retour à la référence nomme l’école ouverte et la portée « votre compte »', () => {
    const copy = presentationResetCopy('École du Léman', { personalizationAllowed: true, dirty: false });
    expect(copy.message).toContain('École du Léman');
    expect(copy.message).toContain('sur votre compte seulement');
    expect(copy.message).not.toContain('abandonnées');
    expect(presentationResetCopy('École du Léman', { personalizationAllowed: false, dirty: true }).message).toContain('abandonnées');
  });

  test('recommencer l’apprentissage ne supprime aucune observation', () => {
    expect(learningResetCopy(false).message).toContain('Aucune observation n’est supprimée');
    expect(learningResetCopy(true).message).toContain('abandonnées');
  });
});

describe('Commandes du compte : la ressource est la personne', () => {
  const kinds = ['saveObservationPreferences', 'resetObservationPresentation', 'resetObservationLearning'] as const;
  const paths = { saveObservationPreferences: 'observation-preferences', resetObservationPresentation: 'observation-preferences/presentation-reset', resetObservationLearning: 'observation-preferences/learning-reset' };

  test.each(kinds)('%s : If-Match, clé d’idempotence et reçu rattaché à la personne', kind => {
    const command = createCommand({ schoolId, kind, path: paths[kind], body: {}, ifMatch: 1, resourceVersion: 1, resourceId: personId });
    expect(commandHeaders(command, 'csrf')['If-Match']).toBe('"1"');
    expect(commandHeaders(command, 'csrf')['Idempotency-Key']).toBe(command.operationId);
    const receipt = { operationId: command.operationId, commandType: commandSpecs[kind].operationType, resourceType: 'ObservationPreferences', resourceId: personId,
      committedAt: '2026-11-12T08:00:00Z', resourceVersion: 2 };
    expect(receiptMatches(command, receipt)).toBe(true);
    // Le reçu d'une autre personne, d'une autre version ou d'une autre opération ne confirme rien.
    expect(receiptMatches(command, { ...receipt, resourceId: randomUUID() })).toBe(false);
    expect(receiptMatches(command, { ...receipt, resourceVersion: 1 })).toBe(false);
    expect(receiptMatches(command, { ...receipt, commandType: 'SAVE_OBSERVATION_THEMES' })).toBe(false);
    expect(receiptMatches(command, { ...receipt, resourceId: schoolId })).toBe(false);
  });

  test('sans identifiant de personne la commande ne se crée pas', () => {
    expect(() => createCommand({ schoolId, kind: 'saveObservationPreferences', path: 'observation-preferences', body: {}, ifMatch: 1, resourceVersion: 1 })).toThrow();
  });

  test('les trois commandes se bloquent entre elles : elles écrivent la même ligne du compte', () => {
    for (const kind of kinds) {
      const command = createCommand({ schoolId, kind, path: paths[kind], body: {}, ifMatch: 1, resourceVersion: 1, resourceId: personId });
      expect(commandConflictKeys(command)).toEqual(['observation-preferences']);
    }
  });
});

describe('Projection des préférences lues du serveur', () => {
  const themes = keys.map((key, index) => ({ ...theme(key, index), schoolVisible: true, visibilityEditable: true }));
  const projection = { id: personId, schoolId, version: 1, personalizationAllowed: true, orderCustomized: false, visibilityCustomized: false, mode: 'MANUAL',
    themes, palette: [...keys], rankedOn: null, learning: { generation: 0, since: null }, adoption: null };

  test('la réponse du contrat est lue telle quelle', () => {
    expect(observationPreferencesSchema.safeParse(projection).success).toBe(true);
  });

  test('l’adoption exige au moins deux configurations', () => {
    const candidate = (name: string) => ({ schoolId: randomUUID(), schoolName: name, mode: 'MANUAL', themes: [{ key: 'speed', visible: true }] });
    expect(observationPreferencesSchema.safeParse({ ...projection, adoption: { candidates: [candidate('A'), candidate('B')] } }).success).toBe(true);
    expect(observationPreferencesSchema.safeParse({ ...projection, adoption: { candidates: [candidate('A')] } }).success).toBe(false);
  });

  test.each([
    ['sans politique', { ...projection, personalizationAllowed: undefined }],
    ['mode inconnu', { ...projection, mode: 'AUTO' }],
    ['palette hors catalogue', { ...projection, palette: ['inconnu'] }],
    ['palette vide', { ...projection, palette: [] }],
    ['thème en double', { ...projection, themes: [themes[0], themes[0]] }],
    ['sans visibilityEditable', { ...projection, themes: [{ ...themes[0], visibilityEditable: undefined }] }],
  ])('refusée : %s', (_name, body) => {
    expect(observationPreferencesSchema.safeParse(body).success).toBe(false);
  });

  test('la lecture de l’école porte désormais sa politique', () => {
    const settings = { id: schoolId, schoolId, version: 1, canManage: true, themes: keys.map((key, index) => theme(key, index)) };
    expect(observationThemesSchema.safeParse(settings).success).toBe(false);
    expect(observationThemesSchema.safeParse({ ...settings, personalizationAllowed: false }).success).toBe(true);
  });
});

describe('Adresses', () => {
  test('la page des signalements du compte garde l’école et le retour', () => {
    const back = `/app/gestion/${schoolId}/agenda`;
    expect(signalsPreferencesHref({})).toBe('/app/preferences/signalements');
    expect(signalsPreferencesHref({ returnTo: '/app/' })).toBe('/app/preferences/signalements');
    expect(signalsPreferencesHref({ returnTo: back, schoolId })).toBe(`/app/preferences/signalements?school=${schoolId}&returnTo=${encodeURIComponent(back)}`);
    expect(schoolOfReturn(back)).toBe(schoolId);
    expect(schoolOfReturn('/app/')).toBeUndefined();
  });
});
