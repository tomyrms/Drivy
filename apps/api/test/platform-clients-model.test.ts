import { expect, it } from 'vitest';
import { commercialView } from '../src/entitlements-model.js';
import { clientColumn, clientFieldNames, searchPattern, setupStepCount, unattachedQuery } from '../src/platform-clients-model.js';

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

it('la projection commerciale d’une fiche sans offre en vigueur laisse le périmètre inchangé et ne porte ni montant ni échéance', () => {
  expect(commercialView({ commercial_state: 'NOT_CONFIGURED', offer: null, scheduled_offer: null, entitlement_version: 1 }))
    .toEqual({ state: 'NOT_CONFIGURED', offer: null, scheduledOffer: null, entitlementVersion: 1, dueDates: [] });
  const assignment = { id: '3f0f0a50-3b8a-4f43-8c1a-7a1c4d2f9a11', offerId: '9b1e6a8e-9a64-4c47-8f3b-0c4f1d2e7a22', offerName: 'Essentiel', effectiveAt: '2026-11-14T10:00:00.123+00:00', modules: ['MESSAGING'] };
  expect(commercialView({ commercial_state: 'OFFER_ACTIVE', offer: assignment, scheduled_offer: null, entitlement_version: 3 }))
    .toEqual({ state: 'OFFER_ACTIVE', offer: { offerId: assignment.offerId, name: 'Essentiel', effectiveAt: '2026-11-14T10:00:00.123Z', modules: ['MESSAGING'] },
      scheduledOffer: null, entitlementVersion: 3, dueDates: [] });
  expect(setupStepCount).toBe(6);
});
