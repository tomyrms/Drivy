import { describe, expect, test } from 'vitest';
import { failedReadState, readStateFor, type ScopedReadState } from '../client/console/load-model.js';

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

describe('Échec d’une lecture', () => {
  const previous: ScopedReadState<string[]> = { scope: 'school/a', status: 'ready', data: ['dossier'], error: null };
  test('une session terminée retire les données et propose de se reconnecter, pas de réessayer', () => {
    expect(failedReadState(previous, 'school/a', { status: 401 }, 'Connexion expirée')).toEqual({
      scope: 'school/a', status: 'error', data: undefined, error: 'Connexion expirée', needsLogin: true });
  });
  test.each([403, 404])('un refus %i retire aussi les données, sans demander de reconnexion', status => {
    const state = failedReadState(previous, 'school/a', { status }, 'Refusé');
    expect(state.data).toBeUndefined();
    expect(state.needsLogin).toBeUndefined();
  });
  test.each([0, 500, 503])('une panne %i garde les données affichées, comme périmées', status => {
    expect(failedReadState(previous, 'school/a', { status }, 'Panne')).toEqual({ scope: 'school/a', status: 'error', data: ['dossier'], error: 'Panne' });
  });
  test('une panne sur un autre périmètre ne ressuscite pas les données de l’ancien', () => {
    expect(failedReadState(previous, 'school/b', { status: 503 }, 'Panne').data).toBeUndefined();
    expect(failedReadState(previous, 'school/b', {}, 'Panne').status).toBe('error');
  });
});
