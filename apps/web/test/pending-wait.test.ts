import { describe, expect, test } from 'vitest';
import { nextTierDelayMs, pendingThresholdMs, slowThresholdMs, waitText, waitTier } from '../client/pending-wait.js';

describe('paliers d\'attente d\'une demande suivie', () => {
  test('les seuils de #105 sont 5 s et 10 s', () => {
    expect(pendingThresholdMs).toBe(5_000);
    expect(slowThresholdMs).toBe(10_000);
  });
  test('4,999 s, 5 s, 9,999 s et 10 s tombent sur le bon palier', () => {
    expect(waitTier(0)).toBe('action');
    expect(waitTier(4_999)).toBe('action');
    expect(waitTier(5_000)).toBe('pending');
    expect(waitTier(9_999)).toBe('pending');
    expect(waitTier(10_000)).toBe('slow');
    expect(waitTier(15_000)).toBe('slow');
  });
  test('le délai vers le palier suivant tombe exactement sur les seuils puis s\'arrête', () => {
    expect(nextTierDelayMs(0)).toBe(5_000);
    expect(nextTierDelayMs(4_000)).toBe(1_000);
    expect(nextTierDelayMs(5_000)).toBe(5_000);
    expect(nextTierDelayMs(9_000)).toBe(1_000);
    expect(nextTierDelayMs(10_000)).toBeNull();
  });
  test('rien n\'est dit avant 5 s et aucun palier ne parle de refus ni d\'échec', () => {
    expect(waitText('action')).toBeNull();
    for (const tier of ['pending', 'slow'] as const) expect(waitText(tier)).not.toMatch(/refus|échec|échou|annul/i);
    expect(waitText('slow')).toContain('suivi');
  });
});
