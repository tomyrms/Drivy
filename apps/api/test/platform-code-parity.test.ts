import { describe, expect, it } from 'vitest';
import {
  generatePlatformCode, normalizePlatformCode as apiNormalize, platformCode as apiCodeSchema, platformCodePattern,
} from '../src/platform-model.js';
import { normalizePlatformCode as webNormalize, platformCodeSchema as webCodeSchema, platformInvitationCode } from '../../web/server/platform-routes.js';

/**
 * Le code d'accès à la plateforme est généré et normalisé deux fois : par le relais web (qui le fabrique pour l'opérateur) et par l'API
 * (qui l'empreinte et le compare). Une dérive entre les deux — alphabet, longueur, tiret, majuscules — ferait refuser des codes valides
 * ou en accepterait que l'autre côté ne sait pas lire. Ce test lit les deux sources et échoue dès qu'elles divergent.
 */
describe('code d’accès à la plateforme : le relais web et l’API disent la même chose', () => {
  const corpus = [
    'ABCDE-FGHJK', 'abcde-fghjk', '  abcde-fghjk  ', ' abcde fghjk ', 'abcdefghjk', 'ABCDE_FGHJK', 'abcde_fghjk', 'ABCDE-FGHJ', 'ABCD-EFGHJK',
    'ABCDE-FGHJO', 'ABCDE-FGHJ0', 'ABCDE-FGHJ1', 'ABCDE-FGHJI', 'ABCDEFGHJKL', 'ABCDE--FGHJK', '22222-33333', '22222-99999', 'ÀBCDE-FGHJK',
    '', '-', 'XXXX-XXXX', 'ABCDE-FGHJK\n', 'a'.repeat(41), 'ABCDE FGHJK EXTRA',
  ];

  it('normalise de la même façon, entrée par entrée', () => {
    for (const input of corpus) expect(webNormalize(input), JSON.stringify(input)).toBe(apiNormalize(input));
  });

  it('accepte et refuse les mêmes entrées, et rend la même forme', () => {
    for (const input of corpus) {
      const web = webCodeSchema.safeParse(input), api = apiCodeSchema.safeParse(input);
      expect(web.success, JSON.stringify(input)).toBe(api.success);
      if (web.success && api.success) expect(web.data).toBe(api.data);
    }
  });

  it('génère des codes que l’autre côté reconnaît, avec le même alphabet', () => {
    const seen = { web: new Set<string>(), api: new Set<string>() };
    for (let index = 0; index < 4000; index += 1) {
      const fromWeb = platformInvitationCode(), fromApi = generatePlatformCode();
      expect(fromWeb).toMatch(platformCodePattern);
      expect(fromApi).toMatch(platformCodePattern);
      expect(apiCodeSchema.safeParse(fromWeb).success).toBe(true);
      expect(webCodeSchema.safeParse(fromApi).success).toBe(true);
      for (const char of fromWeb.replace('-', '')) seen.web.add(char);
      for (const char of fromApi.replace('-', '')) seen.api.add(char);
    }
    // 40 000 tirages par côté : un symbole absent d'un des deux alphabets (ou en trop) se voit.
    expect(seen.web.size).toBe(32);
    expect(seen.api.size).toBe(32);
    expect([...seen.web].sort()).toEqual([...seen.api].sort());
    for (const forbidden of ['O', '0', 'I', '1']) { expect(seen.web.has(forbidden)).toBe(false); expect(seen.api.has(forbidden)).toBe(false); }
  });
});
