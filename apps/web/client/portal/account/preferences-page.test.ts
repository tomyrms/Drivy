import { describe, expect, test } from 'vitest';
import { preferencesReturn } from './preferences-page';

const school = '11111111-1111-4111-8111-111111111111';
const returnTo = (value: string) => preferencesReturn(`?returnTo=${encodeURIComponent(value)}`);

describe('retour depuis les préférences personnelles', () => {
  test('un écran de gestion garde sa rubrique et son public', () => {
    expect(returnTo(`/app/gestion/${school}/invitations?audience=team`)).toBe(`/app/gestion/${school}/invitations?audience=team`);
    expect(returnTo(`/app/gestion/${school}/eleves?selection=${school}`)).toBe(`/app/gestion/${school}/eleves?selection=${school}`);
    expect(returnTo(`/app/gestion/${school}/agenda`)).toBe(`/app/gestion/${school}/agenda`);
  });

  test('toute adresse hors de la gestion revient à l’espace personnel', () => {
    expect(returnTo('https://evil.example/app/gestion')).toBe('/app/');
    expect(returnTo('//evil.example')).toBe('/app/');
    expect(returnTo(`/app/gestion/${school}/../bff`)).toBe('/app/');
    expect(returnTo(`/app/gestion/${school}/eleves#token=secret`)).toBe('/app/');
    expect(preferencesReturn('')).toBe('/app/');
  });
});
