import { expect, it } from 'vitest';
import { clientColumn, clientFieldNames, commercialPlaceholder, searchPattern, setupStepCount, unattachedQuery } from '../src/platform-clients-model.js';

it('la recherche traite les caractères spéciaux de la saisie comme des caractères ordinaires', () => {
  expect(searchPattern(undefined)).toBeNull();
  expect(searchPattern('lilas')).toBe('%lilas%');
  expect(searchPattern('100%')).toBe('%100\\%%');
  expect(searchPattern('a_b')).toBe('%a\\_b%');
  expect(searchPattern('c:\\dir')).toBe('%c:\\\\dir%');
  expect(unattachedQuery.parse({ q: '   ' }).q).toBeUndefined();
});

it('chaque zone de la fiche correspond à une colonne distincte, sans zone de statut ni d’offre', () => {
  const columns = clientFieldNames.map(clientColumn);
  expect(new Set(columns).size).toBe(clientFieldNames.length);
  expect(columns).toEqual(['display_name', 'contact_name', 'contact_email', 'contact_phone', 'billing_street', 'billing_postal_code', 'billing_city', 'billing_country', 'internal_notes']);
  for (const column of columns) expect(column).not.toMatch(/status|state|offer|school|version|created|updated/);
});

it('l’emplacement commercial ne contient ni offre ni échéance tant que les lots suivants ne les définissent pas', () => {
  expect(commercialPlaceholder()).toEqual({ state: 'NOT_CONFIGURED', offer: null, dueDates: [] });
  expect(setupStepCount).toBe(6);
});
