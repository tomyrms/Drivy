import { describe, expect, test } from 'vitest';
import { parseTheme, resolveTheme } from '../client/theme.js';

describe('Préférence d’apparence personnelle', () => {
  test('une valeur absente ou inconnue suit le système', () => {
    for (const value of [null, undefined, '', 'school-brand', '{}']) expect(parseTheme(value)).toBe('system');
    expect(parseTheme('dark')).toBe('dark');
    expect(parseTheme('light')).toBe('light');
  });
  test('les changements système ne remplacent pas un choix manuel', () => {
    expect(resolveTheme('system', true)).toBe('dark');
    expect(resolveTheme('system', false)).toBe('light');
    for (const dark of [false, true]) {
      expect(resolveTheme('light', dark)).toBe('light');
      expect(resolveTheme('dark', dark)).toBe('dark');
    }
  });
});
