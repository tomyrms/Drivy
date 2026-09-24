import { expect, it } from 'vitest';
import { Cursors } from '../src/cursor.js';
const cursors = new Cursors('cle-de-test-uniquement-32-caracteres');
const position = { id: '10000000-0000-4000-8000-000000000001', createdAt:'2026-01-01T00:00:00.000Z' };
it('conserve une position et lie le curseur à son périmètre', () => {
  const cursor = cursors.encode('personne-école-filtres', position);
  expect(cursors.decode(cursor, 'personne-école-filtres')).toEqual(position);
  expect(() => cursors.decode(cursor, 'autre-école')).toThrow();
  expect(() => cursors.decode(cursor, 'autres-filtres')).toThrow();
});
it('refuse une modification du curseur', () => {
  const cursor = cursors.encode('scope', position);
  const altered = `${cursor[0] === 'A' ? 'B' : 'A'}${cursor.slice(1)}`;
  expect(() => cursors.decode(altered,'scope')).toThrow();
});
