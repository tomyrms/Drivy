import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { moduleCodes } from '../src/entitlements-model.js';
import { ApiError } from '../src/errors.js';
import { platformErrorCodes } from '../src/platform-contract.js';
import { platformRights } from '../src/platform-model.js';
import { newUseCommands } from '../src/course-enrollments.js';
import { effectiveInstant } from '../src/platform-offers.js';
import {
  adjustModuleBody, assignOfferBody, assignmentPreviewQuery, createOfferBody, entitlementQuery, liftAdjustmentBody, maxEffectiveDays, offerCommandBody, offerListQuery,
  offerStatuses, offerView, updateOfferBody, type OfferItem
} from '../src/platform-offers-model.js';

const operationId = randomUUID();
const source = (path: string) => readFile(new URL(path, import.meta.url), 'utf8');
const refusal = (run: () => unknown) => { try { run(); } catch (error) { return error as ApiError; } throw new Error('Un refus était attendu.'); };

describe('corps et requêtes des offres', () => {
  it('une offre porte un nom et des modules du catalogue, sans doublon ni montant', () => {
    expect(createOfferBody.parse({ operationId, name: '  Essentiel  ', modules: ['MESSAGING'] })).toEqual({ operationId, name: 'Essentiel', modules: ['MESSAGING'] });
    expect(createOfferBody.safeParse({ operationId, name: 'Sans module', modules: [] }).success).toBe(true);
    expect(createOfferBody.safeParse({ operationId, name: 'Complet', modules: ['COLLECTIVE_COURSES', 'MESSAGING'] }).success).toBe(true);
    const refused: Array<[string, unknown]> = [
      ['nom vide', { operationId, name: '   ', modules: [] }], ['nom trop long', { operationId, name: 'x'.repeat(101), modules: [] }],
      ['module inconnu', { operationId, name: 'Offre', modules: ['PAYMENTS'] }], ['doublon', { operationId, name: 'Offre', modules: ['MESSAGING', 'MESSAGING'] }],
      ['module hors liste', { operationId, name: 'Offre', modules: 'MESSAGING' }], ['sans modules', { operationId, name: 'Offre' }], ['sans identifiant', { name: 'Offre', modules: [] }],
      ['identifiant non UUID', { operationId: 'x', name: 'Offre', modules: [] }],
      // Les montants, essais et états relèvent de #456 : le corps les refuse tous.
      ['montant', { operationId, name: 'Offre', modules: [], amount: 100 }], ['prix', { operationId, name: 'Offre', modules: [], price: 1 }],
      ['essai', { operationId, name: 'Offre', modules: [], trialDays: 30 }], ['statut', { operationId, name: 'Offre', modules: [], status: 'ARCHIVED' }]
    ];
    for (const [label, value] of refused) expect(createOfferBody.safeParse(value).success, label).toBe(false);
  });

  it('une modification change quelque chose, sans pouvoir toucher au statut ni à la version', () => {
    expect(updateOfferBody.safeParse({ operationId }).success).toBe(false);
    expect(updateOfferBody.safeParse({ operationId, name: 'Nouveau nom' }).success).toBe(true);
    expect(updateOfferBody.safeParse({ operationId, modules: [] }).success).toBe(true);
    for (const forbidden of [{ status: 'ARCHIVED' }, { version: 2 }, { archivedAt: null }, { id: randomUUID() }])
      expect(updateOfferBody.safeParse({ operationId, name: 'Offre', ...forbidden }).success, JSON.stringify(forbidden)).toBe(false);
    expect(offerCommandBody.safeParse({ operationId }).success).toBe(true);
    expect(offerCommandBody.safeParse({ operationId, reason: 'x' }).success).toBe(false);
    expect(offerListQuery.safeParse({}).success).toBe(true);
    expect(offerListQuery.parse({ status: 'ARCHIVED' }).status).toBe('ARCHIVED');
    expect(offerListQuery.safeParse({ status: 'DRAFT' }).success).toBe(false);
    expect(offerListQuery.safeParse({ limit: 5 }).success).toBe(false);
    expect([...offerStatuses]).toEqual(['ACTIVE', 'ARCHIVED']);
    expect(entitlementQuery.safeParse({}).success).toBe(true);
    expect(entitlementQuery.safeParse({ at: '2026-01-01T00:00:00Z' }).success).toBe(false);
  });

  it('une attribution est immédiate (date absente ou nulle) ou datée ; le serveur choisit l’offre, jamais l’école', () => {
    const offerId = randomUUID();
    expect(assignOfferBody.safeParse({ operationId, offerId }).success).toBe(true);
    expect(assignOfferBody.safeParse({ operationId, offerId, effectiveAt: null }).success).toBe(true);
    expect(assignOfferBody.safeParse({ operationId, offerId, effectiveAt: '2026-12-01T08:00:00Z' }).success).toBe(true);
    for (const bad of [{ effectiveAt: 'demain' }, { effectiveAt: '2026-12-01' }, { offerId: 'x' }, { schoolId: randomUUID() }, { modules: ['MESSAGING'] }, { amount: 1 }])
      expect(assignOfferBody.safeParse({ operationId, offerId, ...bad }).success, JSON.stringify(bad)).toBe(false);
    expect(assignOfferBody.safeParse({ operationId }).success).toBe(false);
    expect(assignmentPreviewQuery.safeParse({ offerId }).success).toBe(true);
    expect(assignmentPreviewQuery.safeParse({ offerId, effectiveAt: '2026-12-01T08:00:00Z' }).success).toBe(true);
    expect(assignmentPreviewQuery.safeParse({ effectiveAt: '2026-12-01T08:00:00Z' }).success).toBe(false);
    expect(assignmentPreviewQuery.safeParse({ offerId, effectiveAt: 'bientôt' }).success).toBe(false);
  });

  it('un ajustement nomme un module du catalogue, un effet et un motif de 3 à 500 caractères ; la levée garde aussi son motif', () => {
    const valid = { operationId, moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT', reason: '  Essai convenu avec la direction  ' };
    expect(adjustModuleBody.parse(valid).reason).toBe('Essai convenu avec la direction');
    expect(adjustModuleBody.safeParse({ ...valid, effect: 'REVOKE' }).success).toBe(true);
    for (const bad of [{ moduleCode: 'GPS' }, { effect: 'TOGGLE' }, { reason: 'ab' }, { reason: '  a  ' }, { reason: 'x'.repeat(501) }, { reason: undefined }, { amount: 1 }, { schoolId: randomUUID() }])
      expect(adjustModuleBody.safeParse({ ...valid, ...bad }).success, JSON.stringify(bad)).toBe(false);
    expect(adjustModuleBody.safeParse({ ...valid, reason: 'x'.repeat(500) }).success).toBe(true);
    expect(liftAdjustmentBody.safeParse({ operationId, reason: 'Erreur de saisie' }).success).toBe(true);
    for (const bad of [{ reason: 'ab' }, { reason: '' }, { reason: 'x'.repeat(501) }, { effect: 'GRANT' }])
      expect(liftAdjustmentBody.safeParse({ operationId, reason: 'Erreur de saisie', ...bad }).success, JSON.stringify(bad)).toBe(false);
    expect(liftAdjustmentBody.safeParse({ operationId }).success).toBe(false);
  });
});

describe('date d’effet', () => {
  const now = Date.parse('2026-11-14T10:00:00.000Z');
  it('absente ou nulle : immédiate ; sinon strictement à venir et pas au-delà d’une saison', () => {
    expect(effectiveInstant(undefined, now)).toBeNull();
    expect(effectiveInstant(null, now)).toBeNull();
    expect(effectiveInstant('2026-11-14T10:00:01.000Z', now)).toBe('2026-11-14T10:00:01.000Z');
    expect(effectiveInstant('2026-12-01T08:00:00Z', now)).toBe('2026-12-01T08:00:00.000Z');
    expect(maxEffectiveDays).toBe(366);
    const limit = new Date(now + maxEffectiveDays * 86_400_000).toISOString();
    expect(effectiveInstant(limit, now)).toBe(limit);
  });

  it('une date passée ou égale à maintenant répond 409 EFFECTIVE_DATE_PAST ; une date trop lointaine, 400', () => {
    for (const past of ['2026-11-14T10:00:00.000Z', '2026-11-14T09:59:59.000Z', '2020-01-01T00:00:00Z']) {
      const error = refusal(() => effectiveInstant(past, now));
      expect([error.status, error.code], past).toEqual([409, 'EFFECTIVE_DATE_PAST']);
    }
    const far = refusal(() => effectiveInstant(new Date(now + (maxEffectiveDays + 1) * 86_400_000).toISOString(), now));
    expect([far.status, far.code]).toEqual([400, 'INVALID_REQUEST']);
  });
});

describe('projection d’une offre', () => {
  const base: OfferItem = {
    id: randomUUID(), name: 'Essentiel', modules: ['MESSAGING'], status: 'ACTIVE', version: 3, created_at: '2026-11-14T10:00:00.123+00:00',
    updated_at: '2026-11-15T10:00:00.456+00:00', archived_at: null, schools_in_force: '4'
  };
  it('met les horodatages au format du contrat, le compte d’écoles en nombre, et ne laisse rien d’autre', () => {
    expect(offerView(base)).toEqual({
      id: base.id, name: 'Essentiel', modules: ['MESSAGING'], status: 'ACTIVE', version: 3, createdAt: '2026-11-14T10:00:00.123Z',
      updatedAt: '2026-11-15T10:00:00.456Z', archivedAt: null, schoolsInForce: 4
    });
    expect(offerView({ ...base, status: 'ARCHIVED', archived_at: '2026-11-16T10:00:00.000+00:00', schools_in_force: 0 })).toMatchObject({ archivedAt: '2026-11-16T10:00:00.000Z', schoolsInForce: 0 });
    const copy = offerView(base); copy.modules.push('COLLECTIVE_COURSES');
    expect(base.modules).toEqual(['MESSAGING']);
    expect(Object.keys(offerView(base)).join(',')).not.toMatch(/amount|price|trial|due|billing|school(?!sInForce)/i);
  });
});

describe('cohérence du code avec la migration et les droits', () => {
  it('le catalogue du code est celui que la migration amorce, dans le même ordre, et rien d’autre', async () => {
    const sql = await source('../migrations/20261115_platform_offers_modules.sql');
    const seed = /INSERT INTO drivy\.platform_module\(code, sort_order\) VALUES ([^;]+);/.exec(sql)?.[1] ?? '';
    const rows = [...seed.matchAll(/\('([A-Z_]+)',\s*(\d+)\)/g)].map(match => [match[1]!, Number(match[2])] as const);
    expect(rows.map(([code]) => code)).toEqual([...moduleCodes]);
    expect(rows.map(([, order]) => order)).toEqual(rows.map((_row, index) => index + 1));
    // Les modules du catalogue de la migration ne sont ajoutés que par une migration datée, jamais par l'application.
    expect(sql).not.toMatch(/INSERT INTO drivy\.platform_module\(code, sort_order\) VALUES[^;]*;[\s\S]*INSERT INTO drivy\.platform_module\(code/);
  });

  it('la migration ne touche aucune table existante par un déclencheur ni par une valeur imposée, et force la sécurité par ligne partout', async () => {
    const sql = await source('../migrations/20261115_platform_offers_modules.sql');
    const created = [...sql.matchAll(/CREATE TABLE drivy\.(\w+)/g)].map(match => match[1]!);
    expect(created).toEqual(['platform_module', 'platform_offer', 'platform_offer_assignment', 'platform_module_adjustment']);
    for (const table of created) {
      expect(sql, table).toContain(`ALTER TABLE drivy.${table} ENABLE ROW LEVEL SECURITY;`);
      expect(sql, table).toContain(`ALTER TABLE drivy.${table} FORCE ROW LEVEL SECURITY;`);
    }
    const triggers = [...sql.matchAll(/CREATE TRIGGER \w+ BEFORE [A-Z ]+ ON drivy\.(\w+)/g)].map(match => match[1]!);
    expect(triggers.sort()).toEqual([...created].sort());
    // Aucune table existante n'est modifiée : pas d'ALTER TABLE autre que la sécurité par ligne des tables créées ici.
    for (const alter of sql.matchAll(/ALTER TABLE drivy\.(\w+)\s+(?!ENABLE ROW|FORCE ROW)/g)) throw new Error(`ALTER TABLE inattendu sur ${alter[1]}`);
    expect(sql).not.toMatch(/UPDATE drivy\.(school|platform_client|membership)\b/i);
    expect(sql).not.toMatch(/DELETE FROM|DROP TABLE|TRUNCATE/i);
  });

  it('la gestion des offres est un droit d’équipe distinct, lu en base', () => {
    expect(platformRights).toContain('MANAGE_OFFERS');
    expect(new Set(platformRights).size).toBe(platformRights.length);
  });

  it('chaque code d’erreur écrit par les routes d’offres est déclaré au contrat partagé', async () => {
    const emitted = new Set<string>();
    for (const file of ['../src/platform-offers.ts', '../src/platform-command.ts']) {
      for (const match of (await source(file)).matchAll(/new ApiError\(\s*\d{3},\s*'([A-Z_]+)'/g)) emitted.add(match[1]!);
    }
    for (const expected of ['OFFER_ARCHIVED', 'OFFER_NOT_ARCHIVED', 'EFFECTIVE_DATE_PAST', 'ASSIGNMENT_NOT_PENDING', 'ADJUSTMENT_REQUIRES_OFFER', 'ADJUSTMENT_NO_EFFECT',
      'ADJUSTMENT_ACTIVE', 'ADJUSTMENT_NOT_ACTIVE', 'MODULE_UNKNOWN', 'OFFER_NAME_TAKEN', 'VERSION_CONFLICT'])
      expect(emitted.has(expected), expected).toBe(true);
    for (const found of emitted) expect(platformErrorCodes, found).toContain(found as never);
  });
});

describe('gardes serveur des modules : aucune autorisation ne vient de l’interface', () => {
  it('les commandes d’inscription qui créent un nouvel usage sont exactement celles qui exigent le droit ; annuler, quitter et refuser restent permis', async () => {
    expect([...newUseCommands].sort()).toEqual(['ACCEPT_COURSE_OFFER', 'ENROLL_COURSE', 'JOIN_COURSE_WAITLIST', 'STAFF_ENROLL_COURSE']);
    // Toute nouvelle commande ajoutée au fichier doit être rangée d'un côté ou de l'autre : ce test échoue tant qu'elle ne l'est pas.
    const declared = [...(await source('../src/course-enrollments.ts')).matchAll(/run\(r,'([A-Z_]+)'/g)].map(match => match[1]!);
    expect(new Set(declared).size).toBe(declared.length);
    expect(declared.filter(type => !newUseCommands.has(type)).sort()).toEqual([
      'CANCEL_COURSE_ENROLLMENT', 'CANCEL_COURSE_SERIES', 'DECLINE_COURSE_OFFER', 'LEAVE_COURSE_WAITLIST', 'RESCHEDULE_COURSE_SERIES', 'STAFF_CANCEL_COURSE_ENROLLMENT']);
    for (const type of newUseCommands) expect(declared, type).toContain(type);
  });

  it('chaque point d’entrée d’un nouvel usage relit le droit au serveur', async () => {
    const courses = await source('../src/courses.ts');
    const enrollments = await source('../src/course-enrollments.ts');
    const messaging = await source('../src/messaging.ts');
    const media = await source('../src/messaging-media.ts');
    expect(courses).toMatch(/requireModule\(db,schoolId,'COLLECTIVE_COURSES'\)/);
    expect(enrollments).toMatch(/newUseCommands\.has\(type\)\)await requireModule\(db,schoolId,'COLLECTIVE_COURSES'\)/);
    expect(messaging).toMatch(/if \(commercial\) await requireModule\(db, actor\.schoolId, 'MESSAGING'\)/);
    // L'envoi d'un message (nouvel envoi seulement) relit le droit après le contrôle d'idempotence.
    expect((messaging.match(/await requireModule\(db, actor\.schoolId, 'MESSAGING'\)/g) ?? []).length).toBeGreaterThanOrEqual(2);
    expect(messaging).toMatch(/schoolModuleEntitled\(db, actor\.schoolId, 'MESSAGING'\)/);
    expect(media).toMatch(/if \(newUse\) await requireModule\(db, actor\.schoolId, 'MESSAGING'\)/);
    // Consulter ne passe jamais par le contrôle : les lectures de cours n'appellent pas requireModule.
    const readsOnly = courses.split('\n').filter(line => /app\.get\(/.test(line) && /requireModule/.test(line));
    expect(readsOnly).toEqual([]);
  });

  it('un client ne peut ni lire une offre, ni modifier ses propres droits : la lecture école est la seule route d’école ajoutée', async () => {
    const entitlements = await source('../src/entitlements.ts');
    const routes = [...entitlements.matchAll(/app\.(get|post|put|patch|delete)\(\s*'([^']+)'/g)].map(match => `${match[1]} ${match[2]}`);
    expect(routes).toEqual(['get /v1/schools/:schoolId/entitlements']);
    // Chaque écriture de plateforme passe par platformCommand (équipe relue en base, journal, reçu durable) ; les lectures par platformRead.
    const platform = await source('../src/platform-offers.ts');
    const writes = (platform.match(/app\.(post|patch|put|delete)\(/g) ?? []).length;
    expect(writes).toBe(7);
    expect((platform.match(/await platformCommand\(/g) ?? []).length).toBe(writes);
    expect((platform.match(/app\.get\(/g) ?? []).length).toBe(4);
    expect((platform.match(/await platformRead\(/g) ?? []).length).toBe(4);
  });
});
