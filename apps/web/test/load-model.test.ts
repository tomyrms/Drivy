import { describe, expect, test } from 'vitest';
import { failedReadState, readStateFor, ScopedReadCache, type ScopedReadState } from '../client/console/load-model.js';

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

describe('Cache mémoire dans une portée autorisée', () => {
  test('deux consommateurs dédupliquent une lecture ; une autre ressource reste indépendante', async () => {
    const cache = new ScopedReadCache(); let calls = 0;
    let release!: (value: string) => void;
    const waiting = new Promise<string>(resolve => { release = resolve; });
    const loader = () => { calls++; return waiting; };
    const a = cache.read('resource-a', loader), b = cache.read('resource-a', loader);
    expect(await cache.read('resource-b', async () => 'B')).toBe('B');
    expect(calls).toBe(1);
    release('A'); expect(await Promise.all([a,b])).toEqual(['A','A']);
    expect(cache.peek('resource-a')?.value).toBe('A');
  });

  test('invalidation et réponse tardive ne ressuscitent pas un ancien contexte', async () => {
    const cache = new ScopedReadCache();
    let release!: (value: string) => void;
    const a = cache.read('same-resource', () => new Promise<string>(resolve => { release = resolve; }));
    await Promise.resolve(); cache.invalidate();
    await cache.read('same-resource', async () => 'new');
    release('old'); await a;
    expect(cache.peek('same-resource')?.value).toBe('new');
  });

  test('panne garde la projection ; refus et absence la purgent', async () => {
    const cache = new ScopedReadCache(); await cache.read('a', async () => ['authorized']);
    await expect(cache.read('a', async () => { throw { status: 503 }; })).rejects.toEqual({ status: 503 });
    expect(cache.peek('a')?.value).toEqual(['authorized']);
    await expect(cache.read('a', async () => { throw { status: 403 }; })).rejects.toEqual({ status: 403 });
    expect(cache.peek('a')).toBeUndefined();
  });

  test('nombre de projections et durée en mémoire sont bornés', async () => {
    let now = 100; const cache = new ScopedReadCache(2, 1_000, () => now);
    await cache.read('a', async () => 1); now++;
    await cache.read('b', async () => 2); now++;
    await cache.read('c', async () => 3);
    expect(cache.peek('a')).toBeUndefined(); expect(cache.peek('c')?.value).toBe(3);
    now += 1_001; expect(cache.peek('c')).toBeUndefined();
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
