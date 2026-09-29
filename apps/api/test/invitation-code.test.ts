import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { AttemptLimiter } from '../src/attempt-limiter.js';
import { generateInvitationCode,normalizeInvitationCode } from '../src/invitations.js';

describe('code d’invitation', () => {
  it('a 8 caractères de l’alphabet sans ambiguïté, au format XXXX-XXXX', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 500; i++) {
      const code = generateInvitationCode();
      expect(code).toMatch(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$/);
      seen.add(code);
    }
    expect(seen.size).toBe(500);
  });
  it('couvre tout l’alphabet à peu près uniformément', () => {
    const counts = new Map<string, number>();
    for (let i = 0; i < 4000; i++) for (const char of normalizeInvitationCode(generateInvitationCode())) counts.set(char, (counts.get(char) ?? 0) + 1);
    expect(counts.size).toBe(32);
    // 32 000 tirages, attendu 1 000 par caractère : une dérive de 30 % trahirait un biais.
    for (const n of counts.values()) expect(n).toBeGreaterThan(700), expect(n).toBeLessThan(1300);
  });
  it('se normalise : majuscules, sans espaces ni tirets', () => {
    expect(normalizeInvitationCode('abcd-efgh')).toBe('ABCDEFGH');
    expect(normalizeInvitationCode(' ab cd - ef gh ')).toBe('ABCDEFGH');
    expect(normalizeInvitationCode('ABCDEFGH')).toBe('ABCDEFGH');
  });
});

describe('limite des codes refusés', () => {
  const key = AttemptLimiter.key('https://identity.test.invalid', 'sujet');
  it('coupe à la dixième tentative refusée puis rouvre après la fenêtre', () => {
    let now = 1_000_000;const limiter = new AttemptLimiter(10, 15 * 60_000, () => now);
    for (let i = 0; i < 10; i++) {limiter.check(key);limiter.fail(key);now += 1000;}
    expect(() => limiter.check(key)).toThrowError(expect.objectContaining({ status: 429, code: 'INVITATION_CODE_ATTEMPTS' }));
    // Fenêtre glissante : le premier échec (t=1 000 000) sort à t=1 900 000, ce qui rouvre l'accès.
    now = 1_899_999;expect(() => limiter.check(key)).toThrow();
    now = 1_900_000;expect(() => limiter.check(key)).not.toThrow();
  });
  it('compte par émetteur et sujet, pas globalement', () => {
    const limiter = new AttemptLimiter(2, 60_000, () => 5);
    limiter.fail(key);limiter.fail(key);
    expect(() => limiter.check(key)).toThrow();
    expect(() => limiter.check(AttemptLimiter.key('https://identity.test.invalid', 'autre'))).not.toThrow();
    expect(() => limiter.check(AttemptLimiter.key('https://autre-emetteur.invalid', 'sujet'))).not.toThrow();
  });
  it('libère la mémoire des identités sorties de la fenêtre', () => {
    let now = 0;const limiter = new AttemptLimiter(3, 1000, () => now);
    for (let i = 0; i < 50; i++) limiter.fail(AttemptLimiter.key('i', `s${i}`));
    expect(limiter.size).toBe(50);now = 2000;limiter.sweep();expect(limiter.size).toBe(0);
  });
});

describe('contrat d’extension des invitations', () => {
  const invitation = { id: '10000000-0000-4000-8000-000000000001', schoolId: '10000000-0000-4000-8000-000000000002', version: 1, roles: ['LEARNER'], status: 'PENDING', expiresAt: '2026-10-06T10:00:00.000Z' };
  const envelope = (data: unknown) => ({ data, requestId: 'r', serverTime: '2026-09-29T10:00:00.000Z' });
  async function validator() {
    const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
    const contract = JSON.parse(await readFile(new URL('../contracts/invitation-delivery.json', import.meta.url), 'utf8')) as { $id: string };
    ajv.addSchema(contract);return { one: ajv.compile({ $ref: `${contract.$id}#/$defs/Envelope` }), page: ajv.compile({ $ref: `${contract.$id}#/$defs/PageEnvelope` }) };
  }
  it('accepte EMAIL avec adresse masquée et CODE sans adresse, avec ou sans code', async () => {
    const { one, page } = await validator();
    expect(one(envelope({ ...invitation, maskedEmail: 'n***@example.invalid', delivery: 'EMAIL' }))).toBe(true);
    expect(one(envelope({ ...invitation, maskedEmail: null, delivery: 'CODE' }))).toBe(true);
    expect(one(envelope({ ...invitation, maskedEmail: null, delivery: 'CODE', code: 'ABCD-EF23' }))).toBe(true);
    expect(page(envelope({ items: [{ ...invitation, maskedEmail: null, delivery: 'CODE' }], nextCursor: null }))).toBe(true);
  });
  it('refuse les combinaisons incohérentes', async () => {
    const { one } = await validator();
    expect(one(envelope({ ...invitation, maskedEmail: null, delivery: 'EMAIL' }))).toBe(false);
    expect(one(envelope({ ...invitation, maskedEmail: 'n***@example.invalid', delivery: 'CODE' }))).toBe(false);
    expect(one(envelope({ ...invitation, maskedEmail: 'n***@example.invalid', delivery: 'EMAIL', code: 'ABCD-EF23' }))).toBe(false);
    expect(one(envelope({ ...invitation, maskedEmail: null, delivery: 'CODE', code: 'abcd-ef23' }))).toBe(false);
    expect(one(envelope({ ...invitation, maskedEmail: 'n***@example.invalid' }))).toBe(false);
  });
});
