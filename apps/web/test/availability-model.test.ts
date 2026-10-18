import { describe, expect, it } from 'vitest';
import { overlappingHours, type WeeklyHours } from '../client/availability-model.js';

const rule = (overrides: Partial<WeeklyHours> = {}): WeeklyHours => ({
  weekdays: [1, 2, 3], localStart: '08:00', localEnd: '12:00', validFrom: '2026-09-01', validUntil: null, ...overrides,
});

describe('overlappingHours', () => {
  it('finds hours that share a day, an hour and a period', () => {
    const existing = rule();
    expect(overlappingHours([existing], rule({ weekdays: [3, 4], localStart: '11:00', localEnd: '14:00' }))).toBe(existing);
  });
  it('lets adjacent hours follow one another', () => {
    expect(overlappingHours([rule()], rule({ localStart: '12:00', localEnd: '18:00' }))).toBeNull();
  });
  it('ignores other days', () => {
    expect(overlappingHours([rule()], rule({ weekdays: [5, 6] }))).toBeNull();
  });
  it('ignores periods that do not meet, and counts an open period as endless', () => {
    const closed = rule({ validFrom: '2026-09-01', validUntil: '2026-09-30' });
    expect(overlappingHours([closed], rule({ validFrom: '2026-10-01' }))).toBeNull();
    expect(overlappingHours([closed], rule({ validFrom: '2026-09-30' }))).toBe(closed);
    expect(overlappingHours([rule()], rule({ validFrom: '2030-01-01' }))).not.toBeNull();
  });
});
