import { describe, expect, test } from 'vitest';
import { readStateFor, type ScopedReadState } from '../client/console/load-model.js';

describe('Données de gestion et contexte affiché', () => {
  const previous: ScopedReadState<string[]> = { scope: 'school/week-1/instructor-a', status: 'ready', data: ['lesson-a'], error: null };
  test.each(['school/week-2/instructor-a', 'school/week-1/instructor-b', 'other/week-1/instructor-a'])('ne montre pas les leçons précédentes pendant le chargement de %s', scope => {
    expect(readStateFor(previous, scope)).toEqual({ status: 'loading', data: undefined, error: null });
  });
  test('une relecture du même agenda garde les données et expose un échec comme périmées', () => {
    expect(readStateFor(previous, previous.scope).data).toEqual(['lesson-a']);
    const failed = { ...previous, status: 'error' as const, error: 'Connexion interrompue' };
    expect(readStateFor(failed, previous.scope)).toMatchObject({ status: 'error', data: ['lesson-a'], error: 'Connexion interrompue' });
    expect(readStateFor(failed, 'school/week-2/instructor-a').data).toBeUndefined();
  });
});
