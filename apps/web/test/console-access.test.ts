import { describe, expect, test, vi } from 'vitest';
import { ConsoleAccessReader } from '../client/console/access-reader.js';
import { RequestFailure, type Me } from '../client/protocol.js';
import type { School } from '../client/school-api.js';

const schoolId = '11111111-1111-4111-8111-111111111111';
const admin: Me = { personId: '22222222-2222-4222-8222-222222222222', displayName: 'Compte synthétique', version: 1,
  memberships: [{ membershipId: '33333333-3333-4333-8333-333333333333', schoolId, schoolName: 'École synthétique', roles: ['ADMIN'], grants: [], accessEpoch: 1 }] };
const school: School = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE',
  contactEmail: 'ecole@example.test', contactPhone: null, configurationVersion: 1,
  modules: { gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false } };
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}

describe('Relecture concurrente des droits de gestion', () => {
  test('une ancienne réponse ADMIN ne rétablit pas les écrans après un retrait plus récent', async () => {
    const oldMe = deferred<Me>();
    const readMe = vi.fn().mockReturnValueOnce(oldMe.promise).mockResolvedValueOnce({ ...admin, memberships: [] });
    const readSchool = vi.fn().mockResolvedValue(school);
    const reader = new ConsoleAccessReader(readMe, readSchool);
    const oldRead = reader.read(schoolId);
    const current = await reader.read(schoolId);
    expect(current).toMatchObject({ status: 'denied', membership: null });
    oldMe.resolve(admin);
    expect(await oldRead).toBeNull();
    expect(readSchool).not.toHaveBeenCalled();
  });

  test('une réponse scolaire tardive ne remplace pas un refus scolaire plus récent', async () => {
    const oldSchool = deferred<School>();
    const readSchool = vi.fn().mockReturnValueOnce(oldSchool.promise).mockRejectedValueOnce(new RequestFailure('ACCESS_DENIED', 403));
    const reader = new ConsoleAccessReader(async () => admin, readSchool);
    const oldRead = reader.read(schoolId);
    await vi.waitFor(() => expect(readSchool).toHaveBeenCalledTimes(1));
    expect(await reader.read(schoolId)).toMatchObject({ status: 'unavailable', error: { status: 403 } });
    oldSchool.resolve(school);
    expect(await oldRead).toBeNull();
  });

  test('changer d’école ou fermer la console invalide une lecture déjà partie', async () => {
    const pending = deferred<Me>();
    const readSchool = vi.fn().mockResolvedValue(school);
    const reader = new ConsoleAccessReader(() => pending.promise, readSchool);
    const read = reader.read(schoolId);
    reader.invalidate();
    pending.resolve(admin);
    expect(await read).toBeNull();
    expect(readSchool).not.toHaveBeenCalled();
  });

  test.each([401, 403, 404])('un refus explicite %s remplace les anciennes données de gestion', async status => {
    const reader = new ConsoleAccessReader(async () => admin, async () => { throw new RequestFailure('ACCESS_DENIED', status); });
    const result = await reader.read(schoolId);
    expect(result).toMatchObject({ status: status === 401 ? 'signin' : 'unavailable' });
    expect(result).not.toHaveProperty('school');
    expect(result).not.toHaveProperty('membership');
  });

  test('une réponse courante autorisée remplace bien le rôle et son époque', async () => {
    const current = { ...admin, memberships: [{ ...admin.memberships[0]!, accessEpoch: 2, grants: ['CONFIGURE_CATALOG'] }] };
    const reader = new ConsoleAccessReader(async () => current, async () => school);
    expect(await reader.read(schoolId)).toMatchObject({ status: 'ready', membership: { accessEpoch: 2, grants: ['CONFIGURE_CATALOG'] } });
  });
});
