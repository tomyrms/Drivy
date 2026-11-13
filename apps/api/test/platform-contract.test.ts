import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import {
  acceptInvitationBody, createInvitationBody, operationBody, platformErrorCodes, platformErrorSchema, platformInvitationEnvelope, platformInvitationSchema,
  platformInvitationsEnvelope, platformJournalEntrySchema, platformJournalEnvelope, platformMeEnvelope, platformOperationEnvelope, platformOperatorEnvelope,
  platformOperatorSchema, platformOperatorsEnvelope, platformPreviewEnvelope, platformRightsSchema, previewInvitationBody
} from '../src/platform-contract.js';
import { invitationProjection, journalProjection, journalQuery, operatorProjection, platformRightsView, type InvitationRow, type JournalRow, type OperatorRow } from '../src/platform-model.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema, { io: 'input' }); return definition; };
const readContract = async () => JSON.parse(await readFile(new URL('../contracts/platform-operators.json', import.meta.url), 'utf8')) as {
  $id: string; $defs: Record<string, Record<string, unknown>>; description: string };
const now = new Date('2026-11-13T10:00:00.000Z');
const requestId = randomUUID();
const meta = { requestId, serverTime: now.toISOString() };
const operatorRow: OperatorRow = { id: randomUUID(), issuer: 'https://identity.example.invalid', subject: 'synthetic', display_name: 'Camille Exemple', contact_email: 'camille@example.invalid',
  level: 'COMMERCIAL', status: 'ACTIVE', added_via: 'INVITATION', invitation_id: randomUUID(), version: 3, created_at: now, revoked_at: null, revoked_by: null };
const invitationRow: InvitationRow = { id: randomUUID(), code_hash: 'b'.repeat(64), invitee_email: 'invite@example.invalid', level: 'COMMERCIAL', status: 'AVAILABLE', version: 1,
  created_by: operatorRow.id, created_at: now, expires_at: new Date(now.getTime() + 7 * 86_400_000), revoked_at: null, revoked_by: null, used_at: null, used_by: null, created_by_name: 'Camille Exemple' };
const journalRow: JournalRow = { id: randomUUID(), occurred_at: now, actor_kind: 'OPERATOR', actor_operator_id: operatorRow.id, actor_name: 'Camille Exemple', action: 'CREATE_PLATFORM_INVITATION',
  result: 'SUCCESS', reason_code: null, school_id: null, subject_type: 'PlatformInvitation', subject_id: invitationRow.id, operation_id: randomUUID(), changes: { level: 'COMMERCIAL' } };

it('le contrat des opérateurs suit exactement les schémas servis', async () => {
  const contract = await readContract();
  expect(contract.$id).toBe('urn:drivy:contract:platform-operators:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  expect(contract.$defs).toEqual({
    PlatformRights: project(platformRightsSchema), PlatformOperator: project(platformOperatorSchema), PlatformInvitation: project(platformInvitationSchema),
    PlatformJournalEntry: project(platformJournalEntrySchema), CreateInvitationBody: project(createInvitationBody), OperationBody: project(operationBody),
    PreviewInvitationBody: project(previewInvitationBody), AcceptInvitationBody: project(acceptInvitationBody), JournalQuery: project(journalQuery),
    MeEnvelope: project(platformMeEnvelope), OperatorsEnvelope: project(platformOperatorsEnvelope), OperatorEnvelope: project(platformOperatorEnvelope),
    InvitationsEnvelope: project(platformInvitationsEnvelope), InvitationEnvelope: project(platformInvitationEnvelope), JournalEnvelope: project(platformJournalEnvelope),
    PreviewEnvelope: project(platformPreviewEnvelope), OperationEnvelope: project(platformOperationEnvelope), PlatformError: project(platformErrorSchema)
  });
});

it('les projections réellement servies respectent le contrat publié, vérifié par un validateur indépendant', async () => {
  const contract = await readContract();
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  const validator = (name: string) => { const validate = ajv.getSchema(`${contract.$id}#/$defs/${name}`); expect(validate, name).toBeTypeOf('function'); return validate!; };
  const revoked = operatorProjection({ ...operatorRow, status: 'REVOKED', revoked_at: now }, randomUUID());
  const samples: Array<[string, unknown]> = [
    ['MeEnvelope', { data: { operator: operatorProjection(operatorRow, operatorRow.id), ...platformRightsView() }, ...meta }],
    ['OperatorsEnvelope', { data: { items: [operatorProjection(operatorRow, operatorRow.id), revoked] }, ...meta }],
    ['InvitationsEnvelope', { data: { items: [invitationProjection(invitationRow), invitationProjection({ ...invitationRow, status: 'USED', used_at: now, used_by: operatorRow.id })] }, ...meta }],
    ['InvitationEnvelope', { data: invitationProjection(invitationRow), ...meta }],
    ['JournalEnvelope', { data: { items: [journalProjection(journalRow), journalProjection({ ...journalRow, result: 'REFUSED', reason_code: 'VERSION_CONFLICT' })], nextCursor: null }, ...meta }],
    ['PreviewEnvelope', { data: { status: 'AVAILABLE', ...platformRightsView(), maskedEmail: 'i***@example.invalid', expiresAt: now.toISOString(), matchesAccount: true, alreadyMember: false }, ...meta }],
    ['OperationEnvelope', { data: { operationId: randomUUID(), kind: 'REVOKE_PLATFORM_OPERATOR', statusCode: 200, result: { ok: true } }, ...meta }],
    ['PlatformError', { type: 'urn:drivy:problem:last_platform_operator', title: 'Le dernier opérateur actif ne peut pas être retiré.', status: 409, code: 'LAST_PLATFORM_OPERATOR', requestId }]
  ];
  for (const [name, value] of samples) expect(validator(name)(value), `${name} : ${JSON.stringify(validator(name).errors)}`).toBe(true);
  // Les mêmes valeurs passent par les schémas Zod : une dérive de projection casse l'un ou l'autre.
  expect(platformMeEnvelope.safeParse(samples[0]![1]).success).toBe(true);
  expect(platformJournalEnvelope.safeParse(samples[4]![1]).success).toBe(true);
  // Le contrat refuse une réponse qui exposerait plus que prévu.
  const leaking = { data: { items: [{ ...operatorProjection(operatorRow, operatorRow.id), issuer: operatorRow.issuer }] }, ...meta };
  expect(validator('OperatorsEnvelope')(leaking)).toBe(false);
  const withHash = { data: invitationProjection(invitationRow) as Record<string, unknown>, ...meta }; withHash.data.codeHash = 'x';
  expect(validator('InvitationEnvelope')(withHash)).toBe(false);
});

it('les corps de requête refusent les mêmes cas que le service', async () => {
  const contract = await readContract();
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  const create = ajv.getSchema(`${contract.$id}#/$defs/CreateInvitationBody`)!;
  const valid = { operationId: randomUUID(), code: 'ABCDE-FGHJK', email: 'invite@example.invalid', validityDays: 7 };
  expect(create(valid)).toBe(true);
  expect(createInvitationBody.safeParse(valid).success).toBe(true);
  for (const [label, value] of [
    ['validité nulle', { ...valid, validityDays: 0 }], ['validité trop longue', { ...valid, validityDays: 15 }], ['identifiant non UUID', { ...valid, operationId: 'x' }],
    ['champ inconnu', { ...valid, role: 'ADMIN' }], ['sans adresse', { operationId: valid.operationId, code: valid.code }]] as const) {
    expect(create(value), label).toBe(false);
    expect(createInvitationBody.safeParse(value).success, label).toBe(false);
  }
});

it('le contrat ne mentionne ni code, ni empreinte, ni identité OIDC dans une réponse, et les codes d’erreur émis sont déclarés', async () => {
  const contract = await readContract();
  // Noms de propriétés des réponses (le « subject » du journal est l'objet concerné, pas l'identité OIDC : il n'a que type et id).
  const propertyNames = (node: unknown, found = new Set<string>()): Set<string> => {
    if (Array.isArray(node)) node.forEach(item => propertyNames(item, found));
    else if (node && typeof node === 'object') {
      for (const [key, value] of Object.entries(node)) {
        if (key === 'properties' && value && typeof value === 'object') Object.keys(value).forEach(name => found.add(name));
        propertyNames(value, found);
      }
    }
    return found;
  };
  const exposed = propertyNames(Object.fromEntries(Object.entries(contract.$defs).filter(([name]) => /Envelope|Operator$|Invitation$|JournalEntry|Rights/.test(name))));
  expect(exposed.size).toBeGreaterThan(20);
  for (const forbidden of ['code', 'codeHash', 'code_hash', 'issuer', 'email', 'contactEmail', 'inviteeEmail', 'token', 'secret', 'authorization', 'password'])
    expect(exposed.has(forbidden), `propriété interdite : ${forbidden}`).toBe(false);
  expect([...exposed].every(name => !/hash|secret|token|issuer/i.test(name))).toBe(true);
  // Chaque code d'erreur écrit dans les routes de la plateforme figure dans le contrat (et réciproquement pour ceux propres à la plateforme).
  const emitted = new Set<string>();
  for (const file of ['../src/platform.ts', '../src/platform-command.ts']) {
    const source = await readFile(new URL(file, import.meta.url), 'utf8');
    for (const match of source.matchAll(/new ApiError\(\s*\d{3},\s*'([A-Z_]+)'/g)) emitted.add(match[1]!);
  }
  expect(emitted.size).toBeGreaterThan(10);
  for (const code of emitted) expect(platformErrorCodes, code).toContain(code as never);
  for (const code of platformErrorCodes.filter(code => code.startsWith('PLATFORM_') || code === 'LAST_PLATFORM_OPERATOR'))
    expect(emitted.has(code), `${code} déclaré mais jamais émis`).toBe(true);
});
