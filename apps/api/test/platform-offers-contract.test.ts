import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { expect, it } from 'vitest';
import { z } from 'zod';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { assignmentPreview, entitlementDetailView, moduleCodes, schoolEntitlementsView, type EntitlementDetailRow } from '../src/entitlements-model.js';
import { platformErrorSchema } from '../src/platform-contract.js';
import {
  adjustmentHistorySchema, assignmentHistorySchema, assignmentPreviewEnvelope, assignmentPreviewSchema, clientEntitlementsEnvelope, clientEntitlementsSchema,
  entitlementModuleSchema, moduleNotEntitledSchema, offerSchema, platformModuleSchema, platformModulesEnvelope, platformOfferEnvelope, platformOffersEnvelope,
  schoolEntitlementsEnvelope, schoolEntitlementsSchema
} from '../src/platform-offers-contract.js';
import {
  adjustModuleBody, assignOfferBody, assignmentPreviewQuery, createOfferBody, liftAdjustmentBody, offerCommandBody, offerListQuery, offerView, updateOfferBody, type OfferItem
} from '../src/platform-offers-model.js';

const project = (schema: z.ZodType) => { const { $schema: _ignored, ...definition } = z.toJSONSchema(schema, { io: 'input' }); return definition; };
type Contract = { $id: string; $defs: Record<string, Record<string, unknown>>; description: string };
const readContract = async (name: string) => JSON.parse(await readFile(new URL(`../contracts/${name}.json`, import.meta.url), 'utf8')) as Contract;
const validators = (contract: Contract) => {
  const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
  ajv.addSchema(contract);
  return (name: string) => { const validate = ajv.getSchema(`${contract.$id}#/$defs/${name}`); expect(validate, name).toBeTypeOf('function'); return validate!; };
};

const at = '2026-11-14T10:00:00.123+00:00';
const later = '2026-12-01T08:00:00.000+00:00';
const requestId = randomUUID();
const meta = { requestId, serverTime: '2026-11-14T10:00:01.000Z' };
const author = { createdAt: at, createdByName: 'Camille Exemple' };
const inForce = { id: randomUUID(), offerId: randomUUID(), offerName: 'Essentiel', effectiveAt: at, modules: ['MESSAGING'] };
const scheduled = { id: randomUUID(), offerId: randomUUID(), offerName: 'Complet', effectiveAt: later, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] };
const adjustment = { id: randomUUID(), effect: 'GRANT' as const, reason: 'Essai convenu avec la direction', ...author };
const row: EntitlementDetailRow = {
  state: 'OFFER_ACTIVE', assignment: inForce, scheduled, version: 7, nextChangeAt: later,
  modules: [{ code: 'MESSAGING', inOffer: true, entitled: true, adjustment: null }, { code: 'COLLECTIVE_COURSES', inOffer: false, entitled: true, adjustment }],
  assignments: [
    { ...scheduled, status: 'ACTIVE', ...author, cancelledAt: null }, { ...inForce, status: 'ACTIVE', ...author, cancelledAt: null },
    { ...inForce, id: randomUUID(), status: 'CANCELLED', ...author, cancelledAt: at }
  ],
  adjustments: [
    { id: adjustment.id, assignmentId: inForce.id, moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT', reason: adjustment.reason, ...author, liftedAt: null, liftedByName: null, liftReason: null },
    { id: randomUUID(), assignmentId: inForce.id, moduleCode: 'MESSAGING', effect: 'REVOKE', reason: 'Pause demandée', ...author, liftedAt: at, liftedByName: 'Camille Exemple', liftReason: 'Erreur de saisie' }
  ]
};
const noOffer: EntitlementDetailRow = { ...row, state: 'NOT_CONFIGURED', assignment: null, scheduled: null, version: 1, nextChangeAt: null, assignments: [], adjustments: [],
  modules: [{ code: 'MESSAGING', inOffer: false, entitled: true, adjustment: null }, { code: 'COLLECTIVE_COURSES', inOffer: false, entitled: true, adjustment: null }] };
const offer: OfferItem = { id: randomUUID(), name: 'Essentiel', modules: ['MESSAGING'], status: 'ACTIVE', version: 2, created_at: at, updated_at: at, archived_at: null, schools_in_force: 3 };
const now = new Date('2026-11-14T10:00:01.000Z');

it('le contrat des offres suit exactement les schémas servis', async () => {
  const contract = await readContract('platform-offers');
  expect(contract.$id).toBe('urn:drivy:contract:platform-offers:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  expect(Object.keys(contract.$defs)).toEqual([
    'PlatformModule', 'Offer', 'EntitlementModule', 'AssignmentHistory', 'AdjustmentHistory', 'ClientEntitlements', 'AssignmentPreview', 'CreateOfferBody', 'UpdateOfferBody',
    'OfferCommandBody', 'OfferListQuery', 'AssignOfferBody', 'AssignmentPreviewQuery', 'AdjustModuleBody', 'LiftAdjustmentBody', 'ModulesEnvelope', 'OffersEnvelope', 'OfferEnvelope',
    'ClientEntitlementsEnvelope', 'AssignmentPreviewEnvelope', 'PlatformError']);
  expect(contract.$defs).toEqual({
    PlatformModule: project(platformModuleSchema), Offer: project(offerSchema), EntitlementModule: project(entitlementModuleSchema), AssignmentHistory: project(assignmentHistorySchema),
    AdjustmentHistory: project(adjustmentHistorySchema), ClientEntitlements: project(clientEntitlementsSchema), AssignmentPreview: project(assignmentPreviewSchema),
    CreateOfferBody: project(createOfferBody), UpdateOfferBody: project(updateOfferBody), OfferCommandBody: project(offerCommandBody), OfferListQuery: project(offerListQuery),
    AssignOfferBody: project(assignOfferBody), AssignmentPreviewQuery: project(assignmentPreviewQuery), AdjustModuleBody: project(adjustModuleBody),
    LiftAdjustmentBody: project(liftAdjustmentBody), ModulesEnvelope: project(platformModulesEnvelope), OffersEnvelope: project(platformOffersEnvelope),
    OfferEnvelope: project(platformOfferEnvelope), ClientEntitlementsEnvelope: project(clientEntitlementsEnvelope), AssignmentPreviewEnvelope: project(assignmentPreviewEnvelope),
    PlatformError: project(platformErrorSchema)
  });
});

it('le contrat des droits côté école suit exactement les schémas servis', async () => {
  const contract = await readContract('school-entitlements');
  expect(contract.$id).toBe('urn:drivy:contract:school-entitlements:1');
  expect(contract.description).toMatch(/3\.11\.0/);
  expect(contract.description).toMatch(/MODULE_NOT_ENTITLED/);
  expect(Object.keys(contract.$defs)).toEqual(['SchoolEntitlements', 'SchoolEntitlementsEnvelope', 'ModuleNotEntitled']);
  expect(contract.$defs).toEqual({
    SchoolEntitlements: project(schoolEntitlementsSchema), SchoolEntitlementsEnvelope: project(schoolEntitlementsEnvelope), ModuleNotEntitled: project(moduleNotEntitledSchema)
  });
});

it('les projections réellement servies respectent le contrat publié, vérifié par un validateur indépendant', async () => {
  const validator = validators(await readContract('platform-offers'));
  const detail = entitlementDetailView(row, now);
  const none = entitlementDetailView(noOffer, now);
  const preview = assignmentPreview({
    current: detail, offer: { id: randomUUID(), name: 'Cours', modules: ['COLLECTIVE_COURSES'] }, effectiveAt: null,
    usage: { MESSAGING: { conversations: 12 }, COLLECTIVE_COURSES: { publishedSeries: 2, activeEnrollments: 31, upcomingSessions: 6 } }
  });
  const dated = assignmentPreview({ current: none, offer: { id: randomUUID(), name: 'Messagerie', modules: ['MESSAGING'] }, effectiveAt: '2026-12-01T08:00:00.000Z', usage: {} });
  const samples: Array<[string, unknown]> = [
    ['ModulesEnvelope', { data: { items: moduleCodes.map((code, index) => ({ code, sortOrder: index + 1 })) }, ...meta }],
    ['OffersEnvelope', { data: { items: [offerView(offer), offerView({ ...offer, status: 'ARCHIVED', archived_at: at, schools_in_force: '0' })] }, ...meta }],
    ['OffersEnvelope', { data: { items: [] }, ...meta }],
    ['OfferEnvelope', { data: offerView(offer), ...meta }],
    ['ClientEntitlementsEnvelope', { data: detail, ...meta }],
    ['ClientEntitlementsEnvelope', { data: none, ...meta }],
    ['AssignmentPreviewEnvelope', { data: preview, ...meta }],
    ['AssignmentPreviewEnvelope', { data: dated, ...meta }],
    ['PlatformError', { type: 'urn:drivy:problem:offer_archived', title: 'Cette offre est archivée.', status: 409, code: 'OFFER_ARCHIVED', requestId }],
    ['PlatformError', { type: 'urn:drivy:problem:effective_date_past', title: 'La date d’effet doit être à venir.', status: 409, code: 'EFFECTIVE_DATE_PAST', requestId }]
  ];
  for (const [name, value] of samples) expect(validator(name)(value), `${name} : ${JSON.stringify(validator(name).errors)}`).toBe(true);
  // Les mêmes valeurs passent par les schémas Zod : une dérive de projection casse l'un ou l'autre.
  expect(platformModulesEnvelope.safeParse(samples[0]![1]).success).toBe(true);
  expect(platformOffersEnvelope.safeParse(samples[1]![1]).success).toBe(true);
  expect(platformOfferEnvelope.safeParse(samples[3]![1]).success).toBe(true);
  expect(clientEntitlementsEnvelope.safeParse(samples[4]![1]).success).toBe(true);
  expect(clientEntitlementsEnvelope.safeParse(samples[5]![1]).success).toBe(true);
  expect(assignmentPreviewEnvelope.safeParse(samples[6]![1]).success).toBe(true);
  expect(assignmentPreviewEnvelope.safeParse(samples[7]![1]).success).toBe(true);
  // Les horodatages de la base (offset, microsecondes) sortent au format ISO du contrat.
  expect(detail.offer?.effectiveAt).toBe('2026-11-14T10:00:00.123Z');
  expect(detail.assignments.map(item => item.phase)).toEqual(['SCHEDULED', 'IN_FORCE', 'CANCELLED']);
  expect(detail.adjustments.map(item => item.phase)).toEqual(['ACTIVE', 'LIFTED']);
});

it('les réponses de la plateforme ne portent ni montant, ni essai, ni échéance, ni contenu d’école, et refusent tout champ en plus', async () => {
  const validator = validators(await readContract('platform-offers'));
  const detail = entitlementDetailView(row, now) as Record<string, unknown>;
  const envelope = (data: unknown) => ({ data, ...meta });
  for (const extra of ['amount', 'price', 'trial', 'dueDates', 'billing', 'messages', 'learners', 'lessons', 'members', 'token'])
    expect(validator('ClientEntitlementsEnvelope')(envelope({ ...detail, [extra]: 1 })), extra).toBe(false);
  expect(validator('OfferEnvelope')(envelope({ ...offerView(offer), price: 10 }))).toBe(false);
  expect(validator('OfferEnvelope')(envelope({ ...offerView(offer), modules: ['PAYMENTS'] }))).toBe(false);
  expect(validator('OfferEnvelope')(envelope({ ...offerView(offer), status: 'DRAFT' }))).toBe(false);
  expect(validator('OfferEnvelope')(envelope({ ...offerView(offer), version: 0 }))).toBe(false);
  expect(validator('ClientEntitlementsEnvelope')(envelope({ ...detail, state: 'TRIAL' }))).toBe(false);
  expect(validator('ClientEntitlementsEnvelope')(envelope({ ...detail, version: 0 }))).toBe(false);
  expect(validator('ClientEntitlementsEnvelope')(envelope({ ...detail, modules: [{ code: 'GPS', inOffer: true, entitled: true, adjustment: null }] }))).toBe(false);
  expect(validator('ClientEntitlementsEnvelope')(envelope({ ...detail, offer: { ...(detail.offer as object), amount: 1 } }))).toBe(false);
  const preview = assignmentPreview({ current: entitlementDetailView(row, now), offer: { id: randomUUID(), name: 'Cours', modules: [] }, effectiveAt: null, usage: {} });
  expect(validator('AssignmentPreviewEnvelope')(envelope({ ...preview, messages: [] }))).toBe(false);
  expect(validator('AssignmentPreviewEnvelope')(envelope({ ...preview, modules: preview.modules.map(item => ({ ...item, kind: 'DELETES' })) }))).toBe(false);
  // L'aperçu ne dit que des volumes : un texte à la place d'un nombre est refusé.
  expect(validator('AssignmentPreviewEnvelope')(envelope({ ...preview, modules: preview.modules.map(item => ({ ...item, existing: { conversations: 'Bonjour' } })) }))).toBe(false);
});

it('l’école ne voit que l’état et les modules accordés, jamais l’offre, le motif, l’auteur ni l’historique', async () => {
  const validator = validators(await readContract('school-entitlements'));
  const view = schoolEntitlementsView({
    state: 'OFFER_ACTIVE', version: 7, nextChangeAt: later, modules: [{ code: 'MESSAGING', entitled: true }, { code: 'COLLECTIVE_COURSES', entitled: false }]
  }, now);
  expect(validator('SchoolEntitlementsEnvelope')({ data: view, ...meta }), JSON.stringify(validator('SchoolEntitlementsEnvelope').errors)).toBe(true);
  expect(schoolEntitlementsEnvelope.safeParse({ data: view, ...meta }).success).toBe(true);
  const quiet = schoolEntitlementsView({ state: 'NOT_CONFIGURED', version: 1, nextChangeAt: null, modules: moduleCodes.map(code => ({ code, entitled: true })) }, now);
  expect(validator('SchoolEntitlementsEnvelope')({ data: quiet, ...meta })).toBe(true);
  for (const extra of ['offer', 'scheduledOffer', 'reason', 'createdByName', 'assignments', 'adjustments', 'amount', 'dueDates'])
    expect(validator('SchoolEntitlementsEnvelope')({ data: { ...view, [extra]: 'x' }, ...meta }), extra).toBe(false);
  expect(validator('SchoolEntitlementsEnvelope')({ data: { ...view, modules: [{ code: 'MESSAGING', entitled: true, reason: 'Geste' }] }, ...meta })).toBe(false);
  expect(validator('SchoolEntitlementsEnvelope')({ data: { ...view, version: 0 }, ...meta })).toBe(false);
  const refusal = { type: 'urn:drivy:problem:module_not_entitled', title: 'La messagerie n’est pas incluse dans l’offre de cette école.', status: 403, code: 'MODULE_NOT_ENTITLED', requestId };
  expect(validator('ModuleNotEntitled')(refusal)).toBe(true);
  expect(moduleNotEntitledSchema.safeParse(refusal).success).toBe(true);
  expect(validator('ModuleNotEntitled')({ ...refusal, status: 404 })).toBe(false);
  expect(validator('ModuleNotEntitled')({ ...refusal, module: 'MESSAGING', offer: 'Essentiel' })).toBe(false);
});

it('les corps de requête refusent les mêmes cas que le service', async () => {
  const validator = validators(await readContract('platform-offers'));
  const operationId = randomUUID();
  const offerId = randomUUID();
  const cases: Array<[string, z.ZodType, Array<[string, unknown, boolean]>]> = [
    ['CreateOfferBody', createOfferBody, [
      ['valide', { operationId, name: 'Essentiel', modules: ['MESSAGING'] }, true], ['sans module', { operationId, name: 'Vide', modules: [] }, true],
      ['module inconnu', { operationId, name: 'Offre', modules: ['PAYMENTS'] }, false], ['nom vide', { operationId, name: '', modules: [] }, false],
      ['nom trop long', { operationId, name: 'x'.repeat(101), modules: [] }, false], ['montant', { operationId, name: 'Offre', modules: [], amount: 1 }, false],
      ['identifiant non UUID', { operationId: 'x', name: 'Offre', modules: [] }, false]]],
    ['UpdateOfferBody', updateOfferBody, [
      ['nom seul', { operationId, name: 'Autre' }, true], ['modules seuls', { operationId, modules: ['COLLECTIVE_COURSES'] }, true],
      ['statut', { operationId, name: 'Autre', status: 'ARCHIVED' }, false], ['version', { operationId, name: 'Autre', version: 2 }, false]]],
    ['OfferCommandBody', offerCommandBody, [['valide', { operationId }, true], ['champ en plus', { operationId, reason: 'x' }, false], ['sans identifiant', {}, false]]],
    ['AssignOfferBody', assignOfferBody, [
      ['immédiate', { operationId, offerId }, true], ['immédiate explicite', { operationId, offerId, effectiveAt: null }, true],
      ['datée', { operationId, offerId, effectiveAt: '2026-12-01T08:00:00Z' }, true], ['date illisible', { operationId, offerId, effectiveAt: 'demain' }, false],
      ['école choisie', { operationId, offerId, schoolId: randomUUID() }, false], ['sans offre', { operationId }, false]]],
    ['AdjustModuleBody', adjustModuleBody, [
      ['valide', { operationId, moduleCode: 'MESSAGING', effect: 'REVOKE', reason: 'Pause demandée' }, true],
      ['module inconnu', { operationId, moduleCode: 'GPS', effect: 'GRANT', reason: 'Motif' }, false], ['effet inconnu', { operationId, moduleCode: 'MESSAGING', effect: 'TOGGLE', reason: 'Motif' }, false],
      ['motif trop court', { operationId, moduleCode: 'MESSAGING', effect: 'GRANT', reason: 'ab' }, false],
      ['motif trop long', { operationId, moduleCode: 'MESSAGING', effect: 'GRANT', reason: 'x'.repeat(501) }, false], ['sans motif', { operationId, moduleCode: 'MESSAGING', effect: 'GRANT' }, false]]],
    ['LiftAdjustmentBody', liftAdjustmentBody, [['valide', { operationId, reason: 'Erreur de saisie' }, true], ['sans motif', { operationId }, false], ['motif court', { operationId, reason: 'ab' }, false]]],
    ['OfferListQuery', offerListQuery, [['vide', {}, true], ['statut', { status: 'ARCHIVED' }, true], ['statut inconnu', { status: 'DRAFT' }, false], ['champ en plus', { limit: 3 }, false]]],
    ['AssignmentPreviewQuery', assignmentPreviewQuery, [
      ['offre', { offerId }, true], ['offre datée', { offerId, effectiveAt: '2026-12-01T08:00:00Z' }, true], ['sans offre', {}, false], ['offre illisible', { offerId: 'x' }, false]]]
  ];
  for (const [name, schema, samples] of cases) {
    for (const [label, value, valid] of samples) {
      expect(validator(name)(value), `${name} / ${label} (contrat)`).toBe(valid);
      expect(schema.safeParse(value).success, `${name} / ${label} (service)`).toBe(valid);
    }
  }
  // Règles croisées que JSON Schema n'exprime pas : le service seul les refuse.
  expect(updateOfferBody.safeParse({ operationId }).success).toBe(false);
  expect(createOfferBody.safeParse({ operationId, name: 'Offre', modules: ['MESSAGING', 'MESSAGING'] }).success).toBe(false);
  expect(adjustModuleBody.safeParse({ operationId, moduleCode: 'MESSAGING', effect: 'GRANT', reason: '  a  ' }).success).toBe(false);
});

it('le contrat des offres ne mentionne aucune propriété de montant, d’essai, d’échéance ni de contenu, et celui des écoles aucune offre', async () => {
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
  const offers = propertyNames((await readContract('platform-offers')).$defs);
  expect(offers.size).toBeGreaterThan(30);
  for (const forbidden of ['amount', 'price', 'currency', 'billing', 'trial', 'trialEnd', 'dueDate', 'dueDates', 'invoice', 'payment', 'messages', 'learners', 'students', 'lessons', 'members',
    'tracks', 'trips', 'documents', 'profiles', 'token', 'secret', 'password', 'codeHash', 'code_hash', 'issuer', 'subject'])
    expect(offers.has(forbidden), `propriété interdite : ${forbidden}`).toBe(false);
  const school = propertyNames((await readContract('school-entitlements')).$defs);
  for (const forbidden of ['offer', 'offerName', 'scheduledOffer', 'reason', 'createdByName', 'assignments', 'adjustments', 'amount', 'dueDates'])
    expect(school.has(forbidden), `propriété interdite côté école : ${forbidden}`).toBe(false);
  expect([...school].sort()).toEqual(['code', 'computedAt', 'data', 'entitled', 'modules', 'nextChangeAt', 'requestId', 'serverTime', 'state', 'status', 'title', 'type', 'version'].sort());
});
