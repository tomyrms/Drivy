import { describe, expect, it } from 'vitest';
import { distinctLabel, homonymReferences } from '../client/person-reference.js';

const a = '0192f3a1-0000-7000-8000-00000000a1b2';
const b = '0192f3a1-0000-7000-8000-00000000c3b2';
const c = '0192f3a1-0000-7000-8000-0000000099d4';

describe('homonymReferences', () => {
  it('leaves unique names without reference', () => {
    expect(homonymReferences([{ id: a, label: 'Marie Rochat' }, { id: c, label: 'Luc Favre' }]).size).toBe(0);
  });

  it('distinguishes homonyms, accents and spacing included, with distinct references', () => {
    const refs = homonymReferences([{ id: a, label: 'Hélène Rochat' }, { id: b, label: ' helene  rochat' }, { id: c, label: 'Luc Favre' }]);
    expect(refs.has(c)).toBe(false);
    expect(refs.get(a)).toBe('A1B2');
    expect(refs.get(b)).toBe('C3B2');
  });

  it('lengthens the reference until homonyms differ', () => {
    const x = '0192f3a1-0000-7000-8000-000000001234';
    const y = '0192f3a1-0000-7000-8000-000000011234';
    const refs = homonymReferences([{ id: x, label: 'Marie' }, { id: y, label: 'Marie' }]);
    expect(refs.get(x)).not.toBe(refs.get(y));
    expect(refs.get(x)).toBe('01234');
  });

  it('formats the label only when a reference exists', () => {
    expect(distinctLabel('Marie Rochat', undefined)).toBe('Marie Rochat');
    expect(distinctLabel('Marie Rochat', 'A1B2')).toBe('Marie Rochat · Réf. A1B2');
  });
});
