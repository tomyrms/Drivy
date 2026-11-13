import type { z } from 'zod';
import type { platformClientCodeSchema, platformClientDetailSchema, platformUnattachedSchema } from '../../../platform-model';
import { previewId } from '../fixtures';
import type { PreviewBffRequest, PreviewTools } from '../family';

type Client = z.infer<typeof platformClientDetailSchema>;
type Code = z.infer<typeof platformClientCodeSchema>;
type Facts = NonNullable<Client['school']>;
type Unattached = z.infer<typeof platformUnattachedSchema>;
type Tools = Pick<PreviewTools, 'reply' | 'nextId'>;
/** Une ligne du journal commercial partagé avec le reste de la console. */
export type ClientJournal = (action: string, extra?: { changes?: Record<string, unknown>; schoolId?: string | null }) => void;

const day = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * day).toISOString();
const ahead = (days: number) => new Date(Date.now() + days * day).toISOString();
const plain = (text: string) => text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const slug = (text: string) => plain(text).replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const setup = (done: number, completed = false): Facts['setup'] => ({
  step: completed || done >= 6 ? null : `STEP_${done + 1}`, stepsDone: done, stepsTotal: 6, completedAt: completed ? ago(3) : null, savedAt: done > 0 ? ago(2) : null,
});
const facts = (name: string, status: Facts['status'], done: number, completed = false): Facts => ({
  name, status, contactEmail: `${slug(name)}@example.test`, contactPhone: null, setup: setup(done, completed),
});

let codeCount = 0, schoolCount = 0;
const codeId = () => previewId(1500 + codeCount++);
const schoolId = () => previewId(1800 + schoolCount++);

const blank = (n: number, displayName: string | null, days: number): Client => ({
  id: previewId(1000 + n), displayName, preparation: 'AWAITING_SCHOOL', schoolId: null, school: null, contactName: null, contactEmail: null, contactPhone: null,
  latestCode: null, commercial: { state: 'NOT_CONFIGURED', offer: null, dueDates: [] }, version: 1, createdAt: ago(days), updatedAt: ago(days),
  billing: { street: null, postalCode: null, city: null, country: null }, internalNotes: null, link: null, codes: [],
});
const addCode = (client: Client, state: Code['state'], issued: number, validity: number, school: Facts | null = null): Code => {
  const code: Code = {
    id: codeId(), state, clientId: client.id, clientName: client.displayName, createdAt: ago(issued), expiresAt: ahead(validity - issued),
    usedAt: state === 'USED' ? ago(issued - 1) : null, revokedAt: state === 'REVOKED' ? ago(issued - 1) : null, issuedByName: 'Camille Aubry',
    school: school ? { ...school, id: client.schoolId ?? previewId(1899) } : null,
  };
  client.codes.unshift(code);
  return code;
};
const open = (client: Client, school: Facts, source: 'OPENING_CODE' | 'EXISTING_SCHOOL', days: number) => {
  client.school = school; client.schoolId = schoolId();
  client.link = { source, linkedAt: ago(days), issuedByName: source === 'OPENING_CODE' ? 'Camille Aubry' : null };
};

const clients: Client[] = [];
const places = ['Aigle', 'Bex', 'Cossonay', 'Delémont', 'Estavayer', 'Fribourg', 'Gland', 'Hauterive', 'Lutry', 'Morges', 'Nyon', 'Orbe', 'Payerne', 'Renens', 'Sierre', 'Vevey', 'Yverdon', 'Bulle', 'Carouge'];
function seed() {
  const leman = blank(1, 'Auto-école du Léman', 60);
  Object.assign(leman, { contactName: 'Sophie Rochat', contactEmail: 'sophie.rochat@example.test', contactPhone: '+41 21 555 01 01', internalNotes: 'Reprise de l’ancien site en janvier.' });
  leman.billing = { street: 'Rue du Lac 12', postalCode: '1800', city: 'Vevey', country: 'Suisse' };
  addCode(leman, 'USED', 31, 7); open(leman, facts('Auto-école du Léman', 'ACTIVE', 6, true), 'OPENING_CODE', 30); leman.codes[0]!.school = { ...leman.school!, id: leman.schoolId! };
  const riviera = blank(2, 'Conduite Riviera', 12);
  Object.assign(riviera, { contactName: 'Marc Delacrétaz', contactEmail: 'marc@example.test' });
  addCode(riviera, 'USED', 5, 7); open(riviera, facts('Conduite Riviera', 'DRAFT', 3), 'OPENING_CODE', 4); riviera.codes[0]!.school = { ...riviera.school!, id: riviera.schoolId! };
  const jura = blank(3, 'Auto-école Jura', 3); jura.contactName = 'Aline Gerber'; addCode(jura, 'AVAILABLE', 2, 7);
  const gruyere = blank(4, 'Drive Gruyère', 25); gruyere.contactEmail = 'contact@example.test'; addCode(gruyere, 'EXPIRED', 20, 7);
  const saleve = blank(5, 'École Salève', 18); addCode(saleve, 'REVOKED', 14, 7);
  const pilote = blank(6, null, 90); pilote.contactName = 'Luc Favre'; open(pilote, facts('École de conduite Luc', 'ACTIVE', 6, true), 'EXISTING_SCHOOL', 45);
  const vully = blank(7, 'Auto-école Vully', 120); addCode(vully, 'USED', 100, 7); open(vully, facts('Auto-école Vully', 'ARCHIVED', 6, true), 'OPENING_CODE', 99);
  vully.codes[0]!.school = { ...vully.school!, id: vully.schoolId! };
  clients.push(leman, riviera, jura, gruyere, saleve, pilote, vully);
  // De quoi dépasser une page : l'annuaire se lit par pages, sans plafond.
  for (let i = 0; i < 38; i += 1) {
    const name = `Auto-école ${places[i % places.length]}${i >= places.length ? ' II' : ''}`, client = blank(8 + i, name, 10 + i * 2);
    if (i % 3 === 0) addCode(client, 'AVAILABLE', 1, 7);
    else if (i % 3 === 1) { addCode(client, 'USED', 9, 7); open(client, facts(name, 'DRAFT', 1 + (i % 5)), 'OPENING_CODE', 8); client.codes[0]!.school = { ...client.school!, id: client.schoolId! }; }
    else { addCode(client, 'USED', 20, 7); open(client, facts(name, 'ACTIVE', 6, true), 'OPENING_CODE', 19); client.codes[0]!.school = { ...client.school!, id: client.schoolId! }; }
    clients.push(client);
  }
}
seed();
let nextClient = 100;

const unattached: Unattached[] = [
  { id: previewId(1900), ...facts('Auto-école Pilote Nord', 'ACTIVE', 4) },
  { id: previewId(1901), ...facts('Conduite Pilote Sud', 'DRAFT', 1) },
  { id: previewId(1902), ...facts('École Pilote Est', 'ACTIVE', 6, true) },
];

const receipts = new Map<string, { status: number; body: unknown }>();
const lost = new Set<string>();
// Le code vit ici comme dans la session du relais : il n'est jamais écrit dans une liste ni dans une fiche.
let issuing: { operationId: string; clientId: string; named: boolean; validityDays?: number; code: string; codeId: string } | null = null;
const sample = ['DEMK-X7K4', 'DEMK-H3N8', 'DEMK-P6R2'];
let issued = 0;

const effective = (code: Code): Code['state'] => (code.state === 'AVAILABLE' && Date.parse(code.expiresAt) <= Date.now() ? 'EXPIRED' : code.state);
function prepare(client: Client): Client['preparation'] {
  if (!client.school) return 'AWAITING_SCHOOL';
  if (client.school.status === 'ARCHIVED') return 'ARCHIVED';
  return client.school.status === 'ACTIVE' && client.school.setup.completedAt ? 'ACTIVE' : 'IN_PREPARATION';
}
function view(client: Client): Client {
  const copy = structuredClone(client);
  copy.codes = copy.codes.map(code => ({ ...code, state: effective(code) }));
  const latest = copy.codes[0];
  copy.latestCode = latest ? { id: latest.id, state: latest.state, expiresAt: latest.expiresAt, createdAt: latest.createdAt } : null;
  copy.preparation = prepare(copy);
  return copy;
}
function summary(client: Client) {
  const { contactPhone: _phone, billing: _billing, internalNotes: _notes, link: _link, codes: _codes, ...rest } = view(client);
  return rest;
}
const touch = (client: Client) => { client.version += 1; client.updatedAt = new Date().toISOString(); };
const matches = (client: Client, query: string) => [client.displayName, client.school?.name, client.contactName, client.contactEmail, client.school?.contactEmail]
  .some(value => value && plain(value).includes(plain(query)));

/** Écoles clientes (R01-T02), lectures : données fictives, jamais d'appel à l'API. */
export function clientsRead(request: PreviewBffRequest, path: string, tools: Tools): Response | undefined {
  if (path === 'clients') {
    const search = request.query.get('q')?.trim() ?? '', preparation = request.query.get('preparation');
    const limit = Math.min(Number(request.query.get('limit') ?? 25) || 25, 100), offset = Number(request.query.get('cursor') ?? 0) || 0;
    const found = clients.filter(client => (!preparation || prepare(client) === preparation) && (!search || matches(client, search)))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    const items = found.slice(offset, offset + limit).map(summary);
    return tools.reply(200, { data: { items, total: found.length, nextCursor: offset + limit < found.length ? String(offset + limit) : null } });
  }
  const one = /^clients\/([^/]+)$/.exec(path);
  if (one) {
    const client = clients.find(item => item.id === one[1]);
    return client ? tools.reply(200, { data: view(client) }) : tools.reply(404, { code: 'NOT_FOUND' });
  }
  if (path === 'school-codes/pending') {
    const waiting = issuing ? { operationId: issuing.operationId, ...(issuing.named ? { displayName: clients.find(item => item.id === issuing!.clientId)?.displayName ?? undefined } : { clientId: issuing.clientId }),
      ...(issuing.validityDays ? { validityDays: issuing.validityDays } : {}) } : null;
    return tools.reply(200, { pending: waiting });
  }
  if (path === 'unattached-schools') {
    const search = request.query.get('q')?.trim() ?? '';
    return tools.reply(200, { data: { items: unattached.filter(item => !search || plain(item.name).includes(plain(search))).slice(0, 50) } });
  }
  return undefined;
}

/** Écoles clientes (R01-T02), écritures : même idempotence que l'API (un reçu par opération), mêmes refus. */
export function clientsWrite(request: PreviewBffRequest, path: string, tools: Tools, record: ClientJournal): Response | undefined {
  const body = request.body as Record<string, unknown> & { operationId?: string; version?: number };
  const known = body.operationId && path !== 'school-codes' && path !== 'school-codes/clear' ? receipts.get(body.operationId) : undefined;
  if (known) return tools.reply(known.status, known.body);
  const done = (status: number, payload: unknown) => {
    if (body.operationId) receipts.set(body.operationId, { status, body: payload });
    // La réponse se perd une fois : l'écran doit retrouver l'effet en rejouant la même demande.
    if (request.scenario === 'lost-reply' && body.operationId && !lost.has(body.operationId)) { lost.add(body.operationId); throw new TypeError('Synthetic client response lost'); }
    return tools.reply(status, payload);
  };

  if (path === 'school-codes/clear') { issuing = null; return tools.reply(200, { ok: true }); }
  if (path === 'school-codes') {
    const input = body as { operationId: string; clientId?: string; displayName?: string; validityDays?: number };
    if (issuing && issuing.operationId !== input.operationId) return tools.reply(409, { code: 'PLATFORM_CODE_IN_PROGRESS' });
    if (!issuing) {
      let client = input.clientId ? clients.find(item => item.id === input.clientId) : undefined;
      if (input.clientId && !client) return tools.reply(404, { code: 'NOT_FOUND' });
      if (client) {
        if (client.school) return tools.reply(409, { code: 'CLIENT_SCHOOL_LINKED' });
        if (client.codes.some(code => effective(code) === 'AVAILABLE')) return tools.reply(409, { code: 'CLIENT_CODE_PENDING' });
      } else {
        client = blank(nextClient++, (input.displayName ?? '').trim() || null, 0); clients.unshift(client);
        record('CREATE_PLATFORM_CLIENT', { changes: { source: 'OPENING_CODE', clientId: client.id } });
      }
      const created = addCode(client, 'AVAILABLE', 0, input.validityDays ?? 7);
      touch(client);
      issuing = { operationId: input.operationId, clientId: client.id, named: !input.clientId, ...(input.validityDays ? { validityDays: input.validityDays } : {}),
        code: sample[issued++ % sample.length]!, codeId: created.id };
      record('CREATE_SCHOOL_OPENING_CODE', { changes: { clientId: client.id, newClient: !input.clientId, validityDays: input.validityDays ?? 7, expiresAt: created.expiresAt } });
      if (request.scenario === 'lost-reply') throw new TypeError('Synthetic code response lost');
    }
    const client = clients.find(item => item.id === issuing!.clientId)!;
    return tools.reply(201, { data: { codeId: issuing.codeId, client: view(client) }, code: issuing.code, link: `https://apercu.example.test/app/ouvrir#token=${issuing.code}` });
  }

  const revoke = /^school-codes\/([^/]+)\/revoke$/.exec(path);
  if (revoke) {
    const owner = clients.find(client => client.codes.some(code => code.id === revoke[1]));
    const code = owner?.codes.find(item => item.id === revoke[1]);
    if (!owner || !code) return tools.reply(404, { code: 'NOT_FOUND' });
    const state = effective(code);
    if (state === 'USED') return tools.reply(409, { code: 'OPENING_LINK_USED' });
    if (state === 'REVOKED') return tools.reply(409, { code: 'OPENING_LINK_REVOKED' });
    if (state === 'EXPIRED') return tools.reply(409, { code: 'OPENING_LINK_EXPIRED' });
    code.state = 'REVOKED'; code.revokedAt = new Date().toISOString(); touch(owner);
    if (issuing?.codeId === code.id) issuing = null;
    record('REVOKE_SCHOOL_OPENING_CODE', { changes: { clientId: owner.id, status: { from: 'AVAILABLE', to: 'REVOKED' } } });
    return done(200, { data: { ...code, state: 'REVOKED' } });
  }

  if (path === 'clients') {
    const input = body as { operationId: string; schoolId?: string; displayName?: string };
    if (input.schoolId) {
      const school = unattached.find(item => item.id === input.schoolId);
      if (!school) return tools.reply(409, { code: 'CLIENT_SCHOOL_ALREADY_LINKED' });
      const client = blank(nextClient++, null, 0);
      attach(client, school);
      clients.unshift(client);
      record('ATTACH_EXISTING_SCHOOL', { schoolId: school.id, changes: { clientId: client.id, newClient: true, source: 'EXISTING_SCHOOL' } });
      return done(201, { data: view(client) });
    }
    const client = blank(nextClient++, (input.displayName ?? '').trim() || null, 0); clients.unshift(client);
    record('CREATE_PLATFORM_CLIENT', { changes: { source: 'FICHE', clientId: client.id } });
    return done(201, { data: view(client) });
  }

  const update = /^clients\/([^/]+)\/(update|attach-school)$/.exec(path);
  if (update) {
    const client = clients.find(item => item.id === update[1]);
    if (!client) return tools.reply(404, { code: 'NOT_FOUND' });
    if (body.version !== client.version) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    if (update[2] === 'attach-school') {
      const school = unattached.find(item => item.id === body.schoolId);
      if (client.school) return tools.reply(409, { code: 'CLIENT_SCHOOL_LINKED' });
      if (client.codes.some(code => effective(code) === 'AVAILABLE')) return tools.reply(409, { code: 'CLIENT_CODE_PENDING' });
      if (!school) return tools.reply(409, { code: 'CLIENT_SCHOOL_ALREADY_LINKED' });
      attach(client, school); touch(client);
      record('ATTACH_EXISTING_SCHOOL', { schoolId: school.id, changes: { clientId: client.id, newClient: false, source: 'EXISTING_SCHOOL' } });
      return done(200, { data: view(client) });
    }
    const changed: string[] = [];
    const set = (field: string, apply: (value: string | null) => void) => { if (field in body) { apply(body[field] as string | null); changed.push(field); } };
    set('displayName', value => { client.displayName = value; });
    set('contactName', value => { client.contactName = value; });
    set('contactEmail', value => { client.contactEmail = value; });
    set('contactPhone', value => { client.contactPhone = value; });
    set('billingStreet', value => { client.billing.street = value; });
    set('billingPostalCode', value => { client.billing.postalCode = value; });
    set('billingCity', value => { client.billing.city = value; });
    set('billingCountry', value => { client.billing.country = value; });
    set('internalNotes', value => { client.internalNotes = value; });
    touch(client);
    record('UPDATE_PLATFORM_CLIENT', { changes: { clientId: client.id, fields: changed } });
    return done(200, { data: view(client) });
  }
  return undefined;
}

/** L'école existante garde ses accès et ses données : seule la fiche la reconnaît, aucune facture ni suspension n'en découle. */
function attach(client: Client, school: Unattached) {
  const { id, ...rest } = school;
  client.school = rest; client.schoolId = id;
  client.link = { source: 'EXISTING_SCHOOL', linkedAt: new Date().toISOString(), issuedByName: 'Camille Aubry' };
  unattached.splice(unattached.findIndex(item => item.id === id), 1);
}
