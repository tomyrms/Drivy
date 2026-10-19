import { describe, expect, test } from 'vitest';
import { searchSettings, settingsIndex } from '../client/console/settings-search-model.js';
import { consolePath, parseConsoleRoute } from '../client/console/route.js';

describe('Recherche des paramètres par intention', () => {
  test('un synonyme ouvre le champ exact même absent du titre de la page', () => {
    expect(searchSettings('retention')).toContainEqual(expect.objectContaining({ section: 'confidentialite', target: 'privacy-retention' }));
    expect(searchSettings('numéro mobile')).toEqual([expect.objectContaining({ section: 'configuration', target: 'school-phone' })]);
    expect(searchSettings('PRIX CHF')).toEqual([expect.objectContaining({ section: 'prestations' })]);
    expect(searchSettings('thème sombre')).toEqual([expect.objectContaining({ id: 'appearance' })]);
    expect(searchSettings('thème sombre')[0]?.section).toBeUndefined();
    expect(searchSettings('activer GPS')).toEqual([expect.objectContaining({ section: 'confidentialite', target: 'school-gps' })]);
    expect(searchSettings('enregistrement trajet')).toEqual([expect.objectContaining({ id: 'gps' })]);
  });
  test('les mots combinés et accents ne dépendent pas de la casse', () => {
    expect(searchSettings('téléphone école').map(item => item.id)).toEqual(['phone', 'fields']);
    expect(searchSettings('conservation').map(item => item.id)).toEqual(['retention']);
    expect(searchSettings('inexistant')).toEqual([]);
    expect(searchSettings('')).not.toHaveLength(0);
  });
  test('les liens profonds ont uniquement une cible connue et laissent le contenu hors URL', () => {
    const school = '11111111-1111-4111-8111-111111111111';
    for (const result of settingsIndex.filter(item => item.section)) {
      const href = consolePath(school, result.section!, result.target ? { focus: result.target } : {});
      const url = new URL(href, 'https://example.test');
      const route = parseConsoleRoute(url.pathname, url.search);
      expect(route.section).toBe(result.section);
      expect(route.query.focus).toBe(result.target);
    }
    expect(parseConsoleRoute(`/app/gestion/${school}/configuration`, '?focus=school-email&focus=school-name').query).toEqual({});
    expect(parseConsoleRoute(`/app/gestion/${school}/configuration`, '?focus=unknown&search=private').query).toEqual({});
  });
});
