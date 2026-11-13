import { randomUUID } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import type { PoolClient } from 'pg';
import { ApiError } from '../src/errors.js';
import { generateInvitationCode, invitationCodeHasher } from '../src/invitation-code.js';
import { databaseRefusal, operatorRequired, platformCommand, recordPlatformAction } from '../src/platform-command.js';
import { bootstrapPlatformOperators, readBootstrapEntries } from '../src/platform-bootstrap.js';
import {
  createInvitationBody, generatePlatformCode, invitationProjection, invitationStatus, journalProjection, maskEmail, normalizePlatformCode, operatorProjection,
  platformCodeHasher, platformCodePattern, platformExcludedAccess, platformRights, platformRightsView, readPlatformBootstrap,
  type InvitationRow, type JournalRow, type OperatorRow
} from '../src/platform-model.js';

const secret = 'platform-model-synthetic-secret-32-characters';
const identity = { issuer: 'https://identity.example.invalid', subject: 'synthetic-subject' };
const now = new Date('2026-11-13T10:00:00.000Z');
const operator = (extra: Partial<OperatorRow> = {}): OperatorRow => ({ id: randomUUID(), issuer: identity.issuer, subject: identity.subject, display_name: 'Camille Exemple',
  contact_email: 'camille.exemple@example.invalid', level: 'COMMERCIAL', status: 'ACTIVE', added_via: 'INVITATION', invitation_id: randomUUID(), version: 1,
  created_at: now, revoked_at: null, revoked_by: null, ...extra });
const invitation = (extra: Partial<InvitationRow> = {}): InvitationRow => ({ id: randomUUID(), code_hash: 'a'.repeat(64), invitee_email: 'invite@example.invalid', level: 'COMMERCIAL',
  status: 'AVAILABLE', version: 1, created_by: randomUUID(), created_at: now, expires_at: new Date(now.getTime() + 7 * 86_400_000), revoked_at: null, revoked_by: null,
  used_at: null, used_by: null, created_by_name: 'Camille Exemple', ...extra });

describe('code d’accès à la plateforme', () => {
  it('est formé de 5+5 symboles sans caractères ambigus et ne se répète pas', () => {
    const codes = Array.from({ length: 300 }, generatePlatformCode);
    for (const code of codes) expect(code).toMatch(platformCodePattern);
    expect(new Set(codes).size).toBe(codes.length);
  });
  it('se normalise sans accepter autre chose qu’un code complet', () => {
    expect(normalizePlatformCode(' abcde fghjk ')).toBe('ABCDE-FGHJK');
    expect(normalizePlatformCode('abcdefghjk')).toBe('ABCDE-FGHJK');
    const parsed = createInvitationBody.safeParse({ operationId: randomUUID(), code: 'abcde-fghjk', email: ' Invite@Example.INVALID ' });
    expect(parsed.success && parsed.data.code).toBe('ABCDE-FGHJK');
    expect(parsed.success && parsed.data.email).toBe('invite@example.invalid');
    for (const code of ['ABCDE', 'ABCDE-FGHJ', 'ABCDE-FGHJKL', 'ABCDO-FGHJK', 'ABCDE-FGH1K', ''])
      expect(createInvitationBody.safeParse({ operationId: randomUUID(), code, email: 'invite@example.invalid' }).success, code).toBe(false);
  });
  it('est distinct d’un code d’ouverture ou d’invitation d’école, par le format comme par l’empreinte', () => {
    expect(generateInvitationCode()).not.toMatch(platformCodePattern);
    const code = generatePlatformCode();
    const platform = platformCodeHasher(secret)(code);
    expect(platform).toMatch(/^[a-f0-9]{64}$/);
    // La même chaîne n'a jamais la même empreinte que dans l'autre famille : un code ne se résout pas à la place d'un autre.
    expect(platform).not.toBe(invitationCodeHasher(secret)(code));
    expect(platformCodeHasher(secret)(code.toLowerCase())).toBe(platform);
    expect(platformCodeHasher(secret, 'platform-model-dedicated-secret-32-characters')(code)).not.toBe(platform);
    expect(platformCodeHasher(secret)(generatePlatformCode())).not.toBe(platform);
  });
});

describe('droits du niveau commercial', () => {
  it('donne l’équipe, les ouvertures d’école et le journal ; jamais dossiers, trajets, messages ni rôle scolaire', () => {
    expect(platformRights).toEqual(['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'READ_COMMERCIAL_JOURNAL']);
    expect(platformExcludedAccess).toEqual(['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES']);
    expect(platformRightsView()).toEqual({ level: 'COMMERCIAL', rights: [...platformRights], notGranted: [...platformExcludedAccess] });
    for (const right of platformRights) expect(platformExcludedAccess).not.toContain(right as never);
  });
});

describe('projections sans donnée superflue', () => {
  it('masque l’adresse et n’expose ni identité OIDC, ni empreinte, ni code', () => {
    expect(maskEmail('camille.exemple@example.invalid')).toBe('c***@example.invalid');
    expect(maskEmail('sans-arobase')).toBe('***');
    const row = operator();
    const view = operatorProjection(row, row.id);
    const text = JSON.stringify(view);
    expect(view).toMatchObject({ displayName: 'Camille Exemple', maskedEmail: 'c***@example.invalid', status: 'ACTIVE', self: true, version: 1 });
    expect(text).not.toMatch(/camille\.exemple|issuer|subject|identity\.example|synthetic-subject/);
    expect(operatorProjection(row, randomUUID()).self).toBe(false);
    const invited = invitation(); const projected = invitationProjection(invited);
    expect(projected.maskedEmail).toBe('i***@example.invalid');
    expect(JSON.stringify(projected)).not.toMatch(/code|hash|invite@example/i);
  });
  it('dit « expirée » une invitation disponible dont l’échéance est passée, sans toucher aux états terminaux', () => {
    const open = invitation();
    expect(invitationStatus(open, now.getTime())).toBe('AVAILABLE');
    expect(invitationStatus(open, open.expires_at.getTime())).toBe('EXPIRED');
    expect(invitationStatus(invitation({ status: 'USED' }), open.expires_at.getTime() + 1)).toBe('USED');
    expect(invitationStatus(invitation({ status: 'REVOKED' }), open.expires_at.getTime() + 1)).toBe('REVOKED');
  });
  it('projette une ligne du journal avec acteur, école, action, résultat et modification', () => {
    const row: JournalRow = { id: randomUUID(), occurred_at: now, actor_kind: 'OPERATOR', actor_operator_id: randomUUID(), actor_name: 'Camille Exemple', action: 'REVOKE_PLATFORM_OPERATOR',
      result: 'REFUSED', reason_code: 'LAST_PLATFORM_OPERATOR', school_id: null, subject_type: 'PlatformOperator', subject_id: randomUUID(), operation_id: randomUUID(), changes: { self: true } };
    expect(journalProjection(row)).toMatchObject({ actorKind: 'OPERATOR', actorName: 'Camille Exemple', result: 'REFUSED', reasonCode: 'LAST_PLATFORM_OPERATOR', schoolId: null, changes: { self: true },
      subject: { type: 'PlatformOperator', id: row.subject_id } });
    expect(JSON.stringify(journalProjection(row))).not.toMatch(/actor_operator_id|actorOperatorId/);
  });
});

describe('journal commercial : point d’entrée des lots suivants', () => {
  const actor = { operatorId: randomUUID(), displayName: 'Camille Exemple' };
  const fake = () => { const query = vi.fn(async () => ({ rows: [], rowCount: 1 })); return { db: { query } as unknown as PoolClient, query }; };
  it('écrit l’acteur confirmé, l’école, l’action et la modification utile', async () => {
    const { db, query } = fake(); const schoolId = randomUUID(); const operationId = randomUUID();
    await recordPlatformAction(db, actor, { action: 'SUSPEND_SCHOOL', schoolId, subject: { type: 'School', id: schoolId }, changes: { status: { from: 'ACTIVE', to: 'SUSPENDED' } } }, { operationId });
    const [sql, values] = query.mock.calls[0] as unknown as [string, unknown[]];
    expect(sql).toContain('drivy.platform_audit_event');
    expect(values).toEqual(expect.arrayContaining([actor.operatorId, 'Camille Exemple', 'SUSPEND_SCHOOL', 'SUCCESS', schoolId, 'School', operationId]));
    expect(JSON.parse(values[10] as string)).toEqual({ status: { from: 'ACTIVE', to: 'SUSPENDED' } });
  });
  it('refuse d’écrire un secret, un jeton, un code ou une empreinte, à n’importe quelle profondeur', async () => {
    for (const changes of [{ code: 'ABCDE-FGHJK' }, { token: 'x' }, { nested: { secret: 'x' } }, { codeHash: 'x' }, { code_hash: 'x' }, { authorization: 'Bearer x' }, { [['pass', 'word'].join('')]: 'x' }]) {
      const { db, query } = fake();
      await expect(recordPlatformAction(db, actor, { action: 'CREATE_OFFER', changes }), JSON.stringify(changes)).rejects.toThrow();
      expect(query).not.toHaveBeenCalled();
    }
    const { db } = fake();
    await expect(recordPlatformAction(db, actor, { action: 'CREATE_OFFER', changes: { text: 'x'.repeat(5000) } })).rejects.toThrow();
  });
  it('refuse un genre de commande qui n’est pas en MAJUSCULES_ET_TIRETS_BAS avant toute connexion', async () => {
    const pool = { connect: vi.fn() } as never;
    await expect(platformCommand(pool, identity, { kind: 'bad kind', operationId: randomUUID(), body: {}, expectedVersion: null }, async () => { throw new Error('jamais'); })).rejects.toThrow();
    expect((pool as { connect: ReturnType<typeof vi.fn> }).connect).not.toHaveBeenCalled();
  });
});

describe('refus de la base rendus lisibles', () => {
  const pgError = (code: string, message: string, constraint?: string) => Object.assign(new Error(message), { code, ...(constraint ? { constraint } : {}) });
  it('traduit les garde-fous en 409 explicites, sans masquer une erreur inconnue', () => {
    expect(databaseRefusal(pgError('23514', 'last_platform_operator'))).toMatchObject({ status: 409, code: 'LAST_PLATFORM_OPERATOR' });
    expect(databaseRefusal(pgError('23514', 'platform_operator_terminal'))).toMatchObject({ status: 409, code: 'PLATFORM_OPERATOR_REVOKED' });
    expect(databaseRefusal(pgError('23514', 'platform_invitation_terminal'))).toMatchObject({ status: 409, code: 'PLATFORM_INVITATION_CLOSED' });
    expect(databaseRefusal(pgError('23505', 'dup', 'platform_operator_active_identity'))).toMatchObject({ code: 'PLATFORM_ALREADY_MEMBER' });
    expect(databaseRefusal(pgError('23505', 'dup', 'platform_operator_active_email'))).toMatchObject({ code: 'PLATFORM_OPERATOR_EXISTS' });
    expect(databaseRefusal(pgError('23505', 'dup', 'platform_operator_one_per_invitation'))).toMatchObject({ code: 'PLATFORM_INVITATION_USED' });
    expect(databaseRefusal(pgError('23505', 'dup', 'platform_operator_invitation_code_hash_key'))).toMatchObject({ code: 'PLATFORM_CODE_TAKEN' });
    expect(databaseRefusal(pgError('23505', 'dup', 'autre_contrainte'))).toBeUndefined();
    expect(databaseRefusal(new Error('boom'))).toBeUndefined();
    expect(databaseRefusal(new ApiError(409, 'X', 'x'))).toBeUndefined();
  });
  it('répond 403 PLATFORM_OPERATOR_REQUIRED à tout compte hors équipe', () => {
    expect(operatorRequired()).toMatchObject({ status: 403, code: 'PLATFORM_OPERATOR_REQUIRED' });
  });
});

describe('mise en service des premiers opérateurs', () => {
  const first = { issuer: 'https://identity.example.invalid', subject: 'first' };
  const second = { issuer: 'https://identity.example.invalid', subject: 'second' };
  it('lit une configuration privée stricte, au plus dix identités', () => {
    expect(readPlatformBootstrap({})).toEqual([]);
    expect(readPlatformBootstrap({ PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify([{ ...first, displayName: 'Camille' }, second]) })).toHaveLength(2);
    expect(() => readPlatformBootstrap({ PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify([{ ...first, email: 'x@example.invalid' }]) })).toThrow();
    expect(() => readPlatformBootstrap({ PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify([{ subject: 'sans-emetteur' }]) })).toThrow();
    expect(() => readPlatformBootstrap({ PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify(Array.from({ length: 11 }, (_, index) => ({ ...first, subject: `s${index}` }))) })).toThrow();
  });
  it('ne reprend l’ancienne liste d’ouverture que sur demande explicite, sans doublon', () => {
    const env = { PLATFORM_OPERATORS_BOOTSTRAP_JSON: JSON.stringify([first]), SCHOOL_OPENING_OPERATORS_JSON: JSON.stringify([first, second]) };
    expect(readBootstrapEntries(env).map(entry => entry.subject)).toEqual(['first']);
    expect(readBootstrapEntries(env, { legacyOpeningOperators: true }).map(entry => [entry.subject, entry.source])).toEqual([['first', 'PRIVATE_CONFIG'], ['second', 'LEGACY_OPENING_LIST']]);
    expect(readBootstrapEntries({ SCHOOL_OPENING_OPERATORS_JSON: JSON.stringify([second]) }, { legacyOpeningOperators: true })).toHaveLength(1);
    expect(readBootstrapEntries({ SCHOOL_OPENING_OPERATORS_JSON: JSON.stringify([second]) })).toHaveLength(0);
  });
  it('refuse de s’exécuter sans aucune identité, avant toute connexion', async () => {
    const pool = { connect: vi.fn() } as never;
    await expect(bootstrapPlatformOperators(pool, [])).rejects.toThrow(/Aucune identité/);
    expect((pool as { connect: ReturnType<typeof vi.fn> }).connect).not.toHaveBeenCalled();
  });
});
