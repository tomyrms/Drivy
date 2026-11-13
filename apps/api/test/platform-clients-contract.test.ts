import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { platformErrorCodes, platformErrorSchema } from '../src/platform-contract.js';
import {
  issuedCodeEnvelope, issuedCodeSchema, platformClientEnvelope, platformClientSchema, platformClientSummarySchema, platformClientsPageEnvelope, platformCodeEnvelope,
  platformCodeSchema, platformCodesPageEnvelope, unattachedSchoolSchema, unattachedSchoolsEnvelope
} from '../src/platform-clients-contract.js';
import {
  attachSchoolBody, clientDetail, clientListQuery, clientSummary, codeListQuery, codeProjection, createClientBody, issueCodeBody, revokeCodeBody, unattachedProjection,
  unattachedQuery, updateClientBody, type ClientItem, type CodeItem, type UnattachedItem
} from '../src/platform-clients-model.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema, { io: 'input' }); return definition; };
const readContract = async () => JSON.parse(await readFile(new URL('../contracts/platform-clients.json', import.meta.url), 'utf8')) as {
  $id: string; $defs: Record<string, Record<string, unknown>>; description: string };
const at = '2026-11-14T10:00:00.123+00:00';
const later = '2026-11-21T10:00:00.123+00:00';
const requestId = randomUUID();
const meta = { requestId, serverTime: '2026-11-14T10:00:01.000Z' };
const school = { name: 'Auto-école des Lilas', status: 'DRAFT' as const, contact_email: 'contact@example.invalid', contact_phone: '+41 21 000 00 00',
  setup_step: 'ORGANISATION', setup_done: 1, setup_completed_at: null, setup_saved_at: at };
const waiting: ClientItem = { id: randomUUID(), display_name: 'Les Lilas', school_id: null, link_source: null, opened_via_link_id: null, school_linked_at: null, issued_by_name: 'Camille Exemple',
  contact_name: null, contact_email: null, contact_phone: null, billing_street: null, billing_postal_code: null, billing_city: null, billing_country: null, internal_notes: null,
  commercial_state: 'NOT_CONFIGURED', version: 1, created_at: at, updated_at: at, preparation: 'AWAITING_SCHOOL',
  latest_code: { id: randomUUID(), status: 'AVAILABLE', expires_at: later, created_at: at }, school: null };
const opened: ClientItem = { ...waiting, id: randomUUID(), school_id: randomUUID(), link_source: 'OPENING_CODE', opened_via_link_id: randomUUID(), school_linked_at: at,
  contact_name: 'Jeanne Exemple', contact_email: 'jeanne@example.invalid', contact_phone: '+41 79 000 00 00', billing_street: 'Rue du Lac 1', billing_postal_code: '1000',
  billing_city: 'Lausanne', billing_country: 'Suisse', internal_notes: 'Rappeler après la formation', version: 3, preparation: 'IN_PREPARATION',
  latest_code: { id: randomUUID(), status: 'USED', expires_at: later, created_at: at }, school };
const code = (state: CodeItem['state']): CodeItem => ({ id: randomUUID(), client_id: opened.id, client_name: 'Les Lilas', state, created_at: at, expires_at: later,
  used_at: state === 'USED' ? at : null, revoked_at: state === 'REVOKED' ? at : null, issued_by_name: 'Camille Exemple',
  school: state === 'USED' ? { ...school, id: opened.school_id! } : null });
const unattached: UnattachedItem = { id: randomUUID(), name: 'École pilote', status: 'ACTIVE', contact_email: 'pilote@example.invalid', contact_phone: null,
  setup_step: 'REVIEW', setup_done: 6, setup_completed_at: at };

it('le contrat des écoles clientes suit exactement les schémas servis', async () => {
  const contract = await readContract();
  expect(contract.$id).toBe('urn:drivy:contract:platform-clients:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  expect(Object.keys(contract.$defs)).toEqual([
    'PlatformClientSummary', 'PlatformClient', 'PlatformCode', 'UnattachedSchool', 'IssuedCode', 'CreateClientBody', 'UpdateClientBody', 'AttachSchoolBody', 'IssueCodeBody',
    'RevokeCodeBody', 'ClientListQuery', 'CodeListQuery', 'UnattachedQuery', 'ClientsPageEnvelope', 'ClientEnvelope', 'CodesPageEnvelope', 'CodeEnvelope',
    'UnattachedSchoolsEnvelope', 'IssuedCodeEnvelope', 'PlatformError']);
  expect(contract.$defs).toEqual({
    PlatformClientSummary: project(platformClientSummarySchema), PlatformClient: project(platformClientSchema), PlatformCode: project(platformCodeSchema),
    UnattachedSchool: project(unattachedSchoolSchema), IssuedCode: project(issuedCodeSchema), CreateClientBody: project(createClientBody),
    UpdateClientBody: project(updateClientBody), AttachSchoolBody: project(attachSchoolBody), IssueCodeBody: project(issueCodeBody), RevokeCodeBody: project(revokeCodeBody),
    ClientListQuery: project(clientListQuery), CodeListQuery: project(codeListQuery), UnattachedQuery: project(unattachedQuery),
    ClientsPageEnvelope: project(platformClientsPageEnvelope), ClientEnvelope: project(platformClientEnvelope), CodesPageEnvelope: project(platformCodesPageEnvelope),
    CodeEnvelope: project(platformCodeEnvelope), UnattachedSchoolsEnvelope: project(unattachedSchoolsEnvelope), IssuedCodeEnvelope: project(issuedCodeEnvelope),
    PlatformError: project(platformErrorSchema)
  });
});

it('les projections réellement servies respectent le contrat publié, vérifié par un validateur indépendant', async () => {
  const contract = await readContract();
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  const validator = (name: string) => { const validate = ajv.getSchema(`${contract.$id}#/$defs/${name}`); expect(validate, name).toBeTypeOf('function'); return validate!; };
  const codes = [code('AVAILABLE'), code('USED'), code('EXPIRED'), code('REVOKED')].map(codeProjection);
  const samples: Array<[string, unknown]> = [
    ['ClientsPageEnvelope', { data: { items: [clientSummary(waiting), clientSummary(opened)], nextCursor: 'abc', total: 130 }, ...meta }],
    ['ClientsPageEnvelope', { data: { items: [], nextCursor: null, total: null }, ...meta }],
    ['ClientEnvelope', { data: clientDetail(opened, codes), ...meta }],
    ['ClientEnvelope', { data: clientDetail(waiting, []), ...meta }],
    ['CodesPageEnvelope', { data: { items: codes, nextCursor: null, total: 4 }, ...meta }],
    ['CodeEnvelope', { data: codes[3], ...meta }],
    ['UnattachedSchoolsEnvelope', { data: { items: [unattachedProjection(unattached)] }, ...meta }],
    ['IssuedCodeEnvelope', { data: { codeId: randomUUID(), client: clientDetail(waiting, codes.slice(0, 1)) }, ...meta }],
    ['PlatformError', { type: 'urn:drivy:problem:client_code_pending', title: 'Un code est déjà utilisable pour cette fiche.', status: 409, code: 'CLIENT_CODE_PENDING', requestId }]
  ];
  for (const [name, value] of samples) expect(validator(name)(value), `${name} : ${JSON.stringify(validator(name).errors)}`).toBe(true);
  // Les mêmes valeurs passent par les schémas Zod : une dérive de projection casse l'un ou l'autre.
  expect(platformClientsPageEnvelope.safeParse(samples[0]![1]).success).toBe(true);
  expect(platformClientEnvelope.safeParse(samples[2]![1]).success).toBe(true);
  expect(platformCodesPageEnvelope.safeParse(samples[4]![1]).success).toBe(true);
  expect(unattachedSchoolsEnvelope.safeParse(samples[6]![1]).success).toBe(true);
  expect(issuedCodeEnvelope.safeParse(samples[7]![1]).success).toBe(true);
  // Les horodatages de la base (offset, microsecondes) sortent au format ISO du contrat.
  expect(clientSummary(opened).createdAt).toBe('2026-11-14T10:00:00.123Z');
  // Le contrat refuse une réponse qui exposerait plus que prévu : un code, une empreinte, un contenu pédagogique.
  const leaking = clientDetail(opened, codes) as Record<string, unknown>;
  for (const extra of ['code', 'codeHash', 'learners', 'lessons', 'messages', 'members'])
    expect(validator('ClientEnvelope')({ data: { ...leaking, [extra]: 'x' }, ...meta }), extra).toBe(false);
  expect(validator('UnattachedSchoolsEnvelope')({ data: { items: [{ ...unattachedProjection(unattached), members: [] }] }, ...meta })).toBe(false);
  // L'emplacement commercial ne porte ni offre ni échéance inventées.
  expect(validator('ClientEnvelope')({ data: { ...leaking, commercial: { state: 'NOT_CONFIGURED', offer: { price: 1 }, dueDates: [] } }, ...meta })).toBe(false);
  expect(validator('ClientEnvelope')({ data: { ...leaking, commercial: { state: 'TRIAL', offer: null, dueDates: [] } }, ...meta })).toBe(false);
});

it('les corps de requête refusent les mêmes cas que le service', async () => {
  const contract = await readContract();
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  const body = (name: string) => ajv.getSchema(`${contract.$id}#/$defs/${name}`)!;
  const operationId = randomUUID();
  const issue = body('IssueCodeBody');
  const valid = { operationId, code: 'ABCD-FGHJ', displayName: 'Les Lilas', validityDays: 7 };
  expect(issue(valid)).toBe(true);
  expect(issueCodeBody.safeParse(valid).success).toBe(true);
  for (const [label, value] of [
    ['validité nulle', { ...valid, validityDays: 0 }], ['validité trop longue', { ...valid, validityDays: 31 }], ['identifiant non UUID', { ...valid, operationId: 'x' }],
    ['champ inconnu', { ...valid, schoolId: randomUUID() }], ['sans code', { operationId }], ['libellé vide', { ...valid, displayName: '' }]] as const) {
    expect(issue(value), label).toBe(false);
    expect(issueCodeBody.safeParse(value).success, label).toBe(false);
  }
  // Le libellé se saisit sur la fiche existante : service seulement (une règle croisée n'est pas exprimée en JSON Schema).
  expect(issueCodeBody.safeParse({ operationId, code: 'ABCD-FGHJ', clientId: randomUUID(), displayName: 'Autre' }).success).toBe(false);
  expect(issueCodeBody.safeParse({ operationId, code: 'ABCD-FGHJ', clientId: randomUUID() }).success).toBe(true);
  // Aucune zone n'est obligatoire à la création d'une fiche ; une modification doit changer quelque chose ; null efface.
  expect(body('CreateClientBody')({ operationId })).toBe(true);
  expect(createClientBody.safeParse({ operationId }).success).toBe(true);
  expect(updateClientBody.safeParse({ operationId }).success).toBe(false);
  expect(updateClientBody.safeParse({ operationId, internalNotes: null }).success).toBe(true);
  expect(updateClientBody.safeParse({ operationId, contactEmail: 'pas une adresse' }).success).toBe(false);
  expect(updateClientBody.safeParse({ operationId, version: 3 }).success).toBe(false);
  // Les corps refusent un statut ou une offre choisis par l'appelant.
  for (const forbidden of [{ commercialState: 'ACTIVE' }, { offer: 'PRO' }, { schoolStatus: 'ACTIVE' }, { preparation: 'ACTIVE' }]) {
    expect(createClientBody.safeParse({ operationId, ...forbidden }).success, JSON.stringify(forbidden)).toBe(false);
    expect(body('CreateClientBody')({ operationId, ...forbidden }), JSON.stringify(forbidden)).toBe(false);
  }
  expect(attachSchoolBody.safeParse({ operationId, schoolId: randomUUID() }).success).toBe(true);
  expect(attachSchoolBody.safeParse({ operationId }).success).toBe(false);
  expect(revokeCodeBody.safeParse({ operationId }).success).toBe(true);
  expect(clientListQuery.safeParse({ limit: '101' }).success).toBe(false);
  expect(clientListQuery.parse({ q: '  lilas  ' }).q).toBe('lilas');
  expect(clientListQuery.parse({ q: '   ' }).q).toBeUndefined();
  expect(codeListQuery.safeParse({ state: 'LOST' }).success).toBe(false);
});

it('le contrat ne mentionne ni code, ni empreinte, ni contenu pédagogique, et les codes d’erreur émis sont déclarés', async () => {
  const contract = await readContract();
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
  const responses = propertyNames(Object.fromEntries(Object.entries(contract.$defs).filter(([name]) => /Envelope|Summary|^PlatformClient$|^PlatformCode$|^UnattachedSchool$|^IssuedCode$/.test(name))));
  expect(responses.size).toBeGreaterThan(30);
  for (const forbidden of ['code', 'codeHash', 'code_hash', 'token', 'secret', 'password', 'issuer', 'subject', 'learners', 'students', 'lessons', 'messages', 'members',
    'tracks', 'trips', 'documents', 'profiles'])
    expect(responses.has(forbidden), `propriété interdite : ${forbidden}`).toBe(false);
  expect([...responses].every(name => !/hash|secret|token|issuer|password/i.test(name))).toBe(true);
  // Chaque code d'erreur écrit dans les routes de la plateforme figure dans le contrat partagé.
  const emitted = new Set<string>();
  for (const file of ['../src/platform-clients.ts', '../src/platform-clients-model.ts']) {
    const source = await readFile(new URL(file, import.meta.url), 'utf8');
    for (const match of source.matchAll(/new ApiError\(\s*\d{3},\s*'([A-Z_]+)'/g)) emitted.add(match[1]!);
  }
  expect(emitted.size).toBeGreaterThanOrEqual(5);
  for (const found of emitted) expect(platformErrorCodes, found).toContain(found as never);
});
