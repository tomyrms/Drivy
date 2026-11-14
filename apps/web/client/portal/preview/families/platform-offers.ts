import type { z } from 'zod';
import type { platformAssignmentPreviewSchema, platformCommercialSchema, platformEntitlementsSchema, platformOfferSchema } from '../../../platform-model';
import { previewId } from '../fixtures';
import type { PreviewBffRequest, PreviewTools } from '../family';

type Offer = z.infer<typeof platformOfferSchema>;
type Entitlements = z.infer<typeof platformEntitlementsSchema>;
type Assignment = { id: string; offerId: string; offerName: string; modules: string[]; effectiveAt: string; createdAt: string; createdByName: string; cancelledAt: string | null };
type Adjustment = { id: string; assignmentId: string; moduleCode: string; effect: 'GRANT' | 'REVOKE'; reason: string; createdAt: string; createdByName: string;
  lifted: { at: string; by: string; reason: string } | null };
type Ledger = { assignments: Assignment[]; adjustments: Adjustment[]; events: number };
type Tools = Pick<PreviewTools, 'reply' | 'nextId'>;
export type OffersJournal = (action: string, extra?: { changes?: Record<string, unknown>; schoolId?: string | null }) => void;

const day = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * day).toISOString();
const catalogue = [{ code: 'MESSAGING', sortOrder: 1 }, { code: 'COLLECTIVE_COURSES', sortOrder: 2 }];
const author = 'Camille Aubry';

const offers: Offer[] = [
  { id: previewId(2000), name: 'Essentiel', modules: ['MESSAGING'], status: 'ACTIVE', version: 1, createdAt: ago(40), updatedAt: ago(40), archivedAt: null, schoolsInForce: 0 },
  { id: previewId(2001), name: 'Complète', modules: ['MESSAGING', 'COLLECTIVE_COURSES'], status: 'ACTIVE', version: 1, createdAt: ago(40), updatedAt: ago(40), archivedAt: null, schoolsInForce: 0 },
  { id: previewId(2002), name: 'Ancienne formule', modules: ['MESSAGING'], status: 'ARCHIVED', version: 2, createdAt: ago(90), updatedAt: ago(20), archivedAt: ago(20), schoolsInForce: 0 },
];
const ledgers = new Map<string, Ledger>();
const ledger = (clientId: string): Ledger => {
  let value = ledgers.get(clientId);
  if (!value) { value = { assignments: [], adjustments: [], events: 0 }; ledgers.set(clientId, value); }
  return value;
};
const receipts = new Map<string, { status: number; body: unknown }>();
const lost = new Set<string>();
let counter = 0;
const newId = () => previewId(2100 + counter++);

const order = (modules: string[]) => catalogue.map(item => item.code).filter(code => modules.includes(code));
const effective = (item: Assignment) => Date.parse(item.effectiveAt) <= Date.now();
const live = (value: Ledger) => value.assignments.filter(item => !item.cancelledAt);
function inForce(value: Ledger): Assignment | null {
  return live(value).filter(effective).sort((a, b) => Date.parse(b.effectiveAt) - Date.parse(a.effectiveAt))[0] ?? null;
}
const scheduled = (value: Ledger) => live(value).filter(item => !effective(item)).sort((a, b) => Date.parse(a.effectiveAt) - Date.parse(b.effectiveAt))[0] ?? null;
const brief = (item: Assignment | null) => (item ? { offerId: item.offerId, name: item.offerName, effectiveAt: item.effectiveAt, modules: item.modules } : null);
const activeAdjustments = (value: Ledger) => { const current = inForce(value); return value.adjustments.filter(item => !item.lifted && current && item.assignmentId === current.id); };

function entitled(value: Ledger): Set<string> {
  const current = inForce(value);
  if (!current) return new Set(catalogue.map(item => item.code));
  const codes = new Set(current.modules);
  for (const item of activeAdjustments(value)) { if (item.effect === 'GRANT') codes.add(item.moduleCode); else codes.delete(item.moduleCode); }
  return codes;
}

/** Le résumé commercial d'une fiche : état dérivé, offre en vigueur, offre programmée. Rien d'autre (#456 y ajoutera les échéances). */
export function commercialOf(clientId: string): z.infer<typeof platformCommercialSchema> {
  const value = ledger(clientId), current = inForce(value);
  return { state: current ? 'OFFER_ACTIVE' : 'NOT_CONFIGURED', offer: brief(current), scheduledOffer: brief(scheduled(value)), entitlementVersion: 1 + value.events, dueDates: [] };
}

function entitlements(clientId: string): Entitlements {
  const value = ledger(clientId), current = inForce(value), codes = entitled(value), active = activeAdjustments(value);
  const phase = (item: Assignment): Entitlements['assignments'][number]['phase'] => item.cancelledAt ? 'CANCELLED' : item === current ? 'IN_FORCE' : effective(item) ? 'SUPERSEDED' : 'SCHEDULED';
  return {
    state: current ? 'OFFER_ACTIVE' : 'NOT_CONFIGURED', offer: brief(current), scheduledOffer: brief(scheduled(value)),
    modules: catalogue.map(item => {
      const adjustment = active.find(entry => entry.moduleCode === item.code) ?? null;
      return { code: item.code, inOffer: current?.modules.includes(item.code) ?? false, entitled: codes.has(item.code),
        adjustment: adjustment ? { id: adjustment.id, effect: adjustment.effect, reason: adjustment.reason, createdAt: adjustment.createdAt, createdByName: adjustment.createdByName } : null };
    }),
    assignments: [...value.assignments].reverse().map(item => ({ id: item.id, offerId: item.offerId, offerName: item.offerName, modules: item.modules, effectiveAt: item.effectiveAt,
      phase: phase(item), createdAt: item.createdAt, createdByName: item.createdByName, cancelledAt: item.cancelledAt })),
    adjustments: [...value.adjustments].reverse().map(item => ({ id: item.id, moduleCode: item.moduleCode, effect: item.effect, reason: item.reason, createdAt: item.createdAt,
      createdByName: item.createdByName, phase: item.lifted ? 'LIFTED' : active.includes(item) ? 'ACTIVE' : 'ENDED', liftedAt: item.lifted?.at ?? null, liftedByName: item.lifted?.by ?? null,
      liftReason: item.lifted?.reason ?? null })),
    version: 1 + value.events, nextChangeAt: scheduled(value)?.effectiveAt ?? null,
  };
}
const refreshCounts = () => {
  const held = new Map<string, number>();
  for (const value of ledgers.values()) { const current = inForce(value); if (current) held.set(current.offerId, (held.get(current.offerId) ?? 0) + 1); }
  for (const offer of offers) offer.schoolsInForce = held.get(offer.id) ?? 0;
};

/** Volumes fictifs d'une école ouverte : seuls des totaux, jamais un contenu. */
const usage: Record<string, Record<string, number>> = {
  MESSAGING: { conversations: 3 }, COLLECTIVE_COURSES: { publishedSeries: 2, activeEnrollments: 5, upcomingSessions: 4 },
};

function previewOf(clientId: string, offer: Offer, effectiveAt: string | null): z.infer<typeof platformAssignmentPreviewSchema> {
  const value = ledger(clientId), before = entitled(value), after = new Set(offer.modules), current = inForce(value), pending = scheduled(value);
  const immediate = !effectiveAt || Date.parse(effectiveAt) <= Date.now();
  return {
    offer: { id: offer.id, name: offer.name, modules: offer.modules }, effectiveAt, immediate, replacesScheduled: brief(pending),
    endingAdjustments: immediate && current ? activeAdjustments(value).map(item => ({ id: item.id, moduleCode: item.moduleCode, effect: item.effect })) : [],
    modules: catalogue.map(item => {
      const was = before.has(item.code), will = after.has(item.code);
      const kind = was && will ? 'KEEPS' : was ? 'LOSES' : will ? 'GAINS' : 'STAYS_OFF';
      return { code: item.code, before: was, after: will, kind, existing: kind === 'LOSES' ? (usage[item.code] ?? null) : null };
    }),
    version: 1 + value.events,
  };
}

/** Offres et droits (R01-T03), lectures : données fictives, jamais d'appel à l'API. */
export function offersRead(request: PreviewBffRequest, path: string, tools: Tools): Response | undefined {
  if (path === 'modules') return tools.reply(200, { data: { items: structuredClone(catalogue) } });
  if (path === 'offers') { refreshCounts(); return tools.reply(200, { data: { items: structuredClone(offers) } }); }
  const rights = /^clients\/([^/]+)\/entitlements$/.exec(path);
  if (rights) return tools.reply(200, { data: entitlements(rights[1]!) });
  const preview = /^clients\/([^/]+)\/assignment-preview$/.exec(path);
  if (preview) {
    const offer = offers.find(item => item.id === request.query.get('offerId'));
    if (!offer) return tools.reply(404, { code: 'NOT_FOUND' });
    if (offer.status === 'ARCHIVED') return tools.reply(409, { code: 'OFFER_ARCHIVED' });
    return tools.reply(200, { data: previewOf(preview[1]!, offer, request.query.get('effectiveAt')) });
  }
  return undefined;
}

/** Offres et droits (R01-T03), écritures : un reçu par opération, la version attendue, mêmes refus que l'API. */
export function offersWrite(request: PreviewBffRequest, path: string, tools: Tools, record: OffersJournal): Response | undefined {
  const body = request.body as Record<string, unknown> & { operationId?: string; version?: number };
  const known = body.operationId ? receipts.get(body.operationId) : undefined;
  if (known && /^(offers|clients\/[^/]+\/(assignments|adjustments))/.test(path)) return tools.reply(known.status, known.body);
  const done = (status: number, payload: unknown) => {
    if (body.operationId) receipts.set(body.operationId, { status, body: payload });
    // La réponse se perd une fois : l'écran doit retrouver l'effet en rejouant la même demande.
    if (request.scenario === 'lost-reply' && body.operationId && !lost.has(body.operationId)) { lost.add(body.operationId); throw new TypeError('Synthetic offers response lost'); }
    return tools.reply(status, payload);
  };
  const moduleCodes = (value: unknown) => (Array.isArray(value) ? order(value.filter((item): item is string => typeof item === 'string')) : []);

  if (path === 'offers') {
    const input = body as { name?: string; modules?: unknown };
    const created: Offer = { id: newId(), name: (input.name ?? '').trim(), modules: moduleCodes(input.modules), status: 'ACTIVE', version: 1,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), archivedAt: null, schoolsInForce: 0 };
    offers.unshift(created);
    record('CREATE_OFFER', { changes: { offerId: created.id, modules: created.modules } });
    return done(201, { data: created });
  }
  const change = /^offers\/([^/]+)\/(update|archive|restore)$/.exec(path);
  if (change) {
    const offer = offers.find(item => item.id === change[1]);
    if (!offer) return tools.reply(404, { code: 'NOT_FOUND' });
    if (body.version !== offer.version) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    const stamp = new Date().toISOString();
    if (change[2] === 'update') {
      if (offer.status === 'ARCHIVED') return tools.reply(409, { code: 'OFFER_ARCHIVED' });
      if (typeof body.name === 'string') offer.name = body.name.trim();
      if (body.modules !== undefined) offer.modules = moduleCodes(body.modules);
      record('UPDATE_OFFER', { changes: { offerId: offer.id, modules: offer.modules } });
    } else if (change[2] === 'archive') {
      if (offer.status === 'ARCHIVED') return tools.reply(409, { code: 'OFFER_ARCHIVED' });
      offer.status = 'ARCHIVED'; offer.archivedAt = stamp;
      record('ARCHIVE_OFFER', { changes: { offerId: offer.id } });
    } else {
      if (offer.status !== 'ARCHIVED') return tools.reply(409, { code: 'OFFER_NOT_ARCHIVED' });
      offer.status = 'ACTIVE'; offer.archivedAt = null;
      record('RESTORE_OFFER', { changes: { offerId: offer.id } });
    }
    offer.version += 1; offer.updatedAt = stamp;
    return done(200, { data: offer });
  }

  const target = /^clients\/([^/]+)\/(assignments|adjustments)(?:\/([^/]+)\/(cancel|lift))?$/.exec(path);
  if (!target) return undefined;
  const clientId = target[1]!, value = ledger(clientId);
  if (body.version !== 1 + value.events) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  const stamp = new Date().toISOString();
  if (target[2] === 'assignments' && !target[3]) {
    const input = body as { offerId?: string; effectiveAt?: string };
    const offer = offers.find(item => item.id === input.offerId);
    if (!offer) return tools.reply(404, { code: 'NOT_FOUND' });
    if (offer.status === 'ARCHIVED') return tools.reply(409, { code: 'OFFER_ARCHIVED' });
    if (input.effectiveAt && Date.parse(input.effectiveAt) <= Date.now()) return tools.reply(422, { code: 'EFFECTIVE_DATE_PAST' });
    // Une nouvelle attribution remplace celle qui était programmée ; l'ancienne reste dans l'historique.
    for (const item of live(value).filter(entry => !effective(entry))) item.cancelledAt = stamp;
    value.assignments.push({ id: newId(), offerId: offer.id, offerName: offer.name, modules: [...offer.modules], effectiveAt: input.effectiveAt ?? stamp, createdAt: stamp, createdByName: author, cancelledAt: null });
    value.events += 1;
    record('ASSIGN_OFFER', { changes: { clientId, offerId: offer.id, immediate: !input.effectiveAt } });
  } else if (target[2] === 'assignments') {
    const item = value.assignments.find(entry => entry.id === target[3]);
    if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
    if (item.cancelledAt || effective(item)) return tools.reply(409, { code: 'ASSIGNMENT_NOT_PENDING' });
    item.cancelledAt = stamp; value.events += 1;
    record('CANCEL_OFFER_ASSIGNMENT', { changes: { clientId, offerId: item.offerId } });
  } else if (!target[3]) {
    const input = body as { moduleCode?: string; effect?: 'GRANT' | 'REVOKE'; reason?: string };
    const current = inForce(value);
    if (!current) return tools.reply(409, { code: 'ADJUSTMENT_REQUIRES_OFFER' });
    if (!catalogue.some(item => item.code === input.moduleCode)) return tools.reply(404, { code: 'MODULE_UNKNOWN' });
    if (activeAdjustments(value).some(item => item.moduleCode === input.moduleCode)) return tools.reply(409, { code: 'ADJUSTMENT_ACTIVE' });
    const has = entitled(value).has(input.moduleCode!);
    if ((input.effect === 'GRANT') === has) return tools.reply(409, { code: 'ADJUSTMENT_NO_EFFECT' });
    value.adjustments.push({ id: newId(), assignmentId: current.id, moduleCode: input.moduleCode!, effect: input.effect!, reason: (input.reason ?? '').trim(), createdAt: stamp, createdByName: author, lifted: null });
    value.events += 1;
    record('ADJUST_SCHOOL_MODULE', { changes: { clientId, moduleCode: input.moduleCode, effect: input.effect } });
  } else {
    const item = value.adjustments.find(entry => entry.id === target[3]);
    if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
    if (!activeAdjustments(value).includes(item)) return tools.reply(409, { code: 'ADJUSTMENT_NOT_ACTIVE' });
    item.lifted = { at: stamp, by: author, reason: String(body.reason ?? '').trim() }; value.events += 1;
    record('LIFT_MODULE_ADJUSTMENT', { changes: { clientId, moduleCode: item.moduleCode } });
  }
  return done(200, { data: entitlements(clientId) });
}
