import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { checkIdempotency, commandHash, requireVersion } from './commands.js';
import { Cursors } from './cursor.js';
import { ApiError, notFound } from './errors.js';
import { invitationCodeHasher } from './invitation-code.js';
import { platformCommand, platformRead, type PlatformActor } from './platform-command.js';
import {
  attachSchoolBody, clientColumn, clientDetail, clientFieldNames, clientListQuery, clientSummary, codeListQuery, codeProjection,
  createClientBody, issueCodeBody, revokeCodeBody, searchPattern, unattachedProjection, unattachedQuery, updateClientBody,
  type ClientItem, type CodeItem, type UnattachedItem,
} from './platform-clients-model.js';
import { openingDigest, type SchoolOpeningConfig } from './school-opening-model.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const versionConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Cette fiche a changé. Rechargez-la avant de confirmer.');
const opening = { openingOperator: true } as const;
const lockClient = (db: PoolClient, clientId: string) => db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-client:${clientId}`]);

type OverviewRow<T> = { result_total: string; item: T };
const clientRows = async (db: PoolClient, args: { id?: string; pattern?: string | null; preparation?: string | null; after?: { createdAt: string; id: string } | undefined; limit: number }) =>
  (await db.query<OverviewRow<ClientItem>>('SELECT * FROM drivy.platform_client_overview($1::uuid,$2::text,$3::text,$4::timestamptz,$5::uuid,$6::integer)',
    [args.id ?? null, args.pattern ?? null, args.preparation ?? null, args.after?.createdAt ?? null, args.after?.id ?? null, args.limit])).rows;
const codeRows = async (db: PoolClient, args: { clientId?: string; codeId?: string; state?: string | null; after?: { createdAt: string; id: string } | undefined; limit: number }) =>
  (await db.query<OverviewRow<CodeItem>>('SELECT * FROM drivy.platform_code_overview($1::uuid,$2::uuid,$3::text,$4::timestamptz,$5::uuid,$6::integer)',
    [args.clientId ?? null, args.codeId ?? null, args.state ?? null, args.after?.createdAt ?? null, args.after?.id ?? null, args.limit])).rows;

/** Fiche complète : faits de l'école (projection fixe), codes de la fiche, rien d'autre. */
async function readClient(db: PoolClient, id: string) {
  const row = (await clientRows(db, { id, limit: 1 }))[0];
  if (!row) throw notFound();
  const codes = (await codeRows(db, { clientId: id, limit: 50 })).map(code => codeProjection(code.item));
  return clientDetail(row.item, codes);
}

/**
 * Écoles clientes et codes d'ouverture (R01-T02). Chaque lecture et chaque écriture passent par le rôle applicatif sous RLS
 * et par l'équipe relue en base ; les faits d'école ne se lisent que par des fonctions à projection fixe (jamais un dossier,
 * un trajet ni un message). Chaque commande entre par `platformCommand` : reçu durable, journal commercial et effet dans un seul commit.
 */
export function registerPlatformClients(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier; cursorSecret: string; invitationCodeSecret?: string; schoolOpening?: SchoolOpeningConfig }) {
  const cursors = new Cursors(options.cursorSecret);
  const hashOf = openingDigest(invitationCodeHasher(options.cursorSecret, options.invitationCodeSecret));
  const validityDays = options.schoolOpening?.validityDays ?? 7;
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);

  function paged<T extends { id: string; created_at: string }>(rows: OverviewRow<T>[], limit: number, scope: string, after: unknown) {
    const last = rows.length > limit ? rows[limit - 1]!.item : undefined;
    return {
      items: rows.slice(0, limit).map(row => row.item),
      total: rows[0] ? Number(rows[0].result_total) : after ? null : 0,
      nextCursor: last ? cursors.encode(scope, { createdAt: new Date(last.created_at).toISOString(), id: last.id }) : null,
    };
  }

  app.get('/v1/platform/clients', async request => {
    const identity = await identityOf(request); const query = clientListQuery.parse(request.query);
    const data = await platformRead(options.pool, identity, async (db, actor) => {
      const scope = JSON.stringify(['platform-clients', actor.operatorId, query.q ?? null, query.preparation ?? null, query.limit]);
      const after = cursors.decode(query.cursor, scope);
      const rows = await clientRows(db, { pattern: searchPattern(query.q), preparation: query.preparation ?? null, after, limit: query.limit + 1 });
      const page = paged(rows, query.limit, scope, after);
      return { items: page.items.map(clientSummary), total: page.total, nextCursor: page.nextCursor };
    }, opening);
    return envelope(data, request);
  });

  app.get('/v1/platform/clients/:id', async request => {
    const identity = await identityOf(request); empty.parse(request.query); const { id } = idParams.parse(request.params);
    return envelope(await platformRead(options.pool, identity, db => readClient(db, id), opening), request);
  });

  // Écoles déjà ouvertes que personne n'a reliées à une fiche : proposées au rattachement explicite.
  app.get('/v1/platform/unattached-schools', async request => {
    const identity = await identityOf(request); const query = unattachedQuery.parse(request.query);
    const data = await platformRead(options.pool, identity, async db => ({
      items: (await db.query<{ item: UnattachedItem }>('SELECT * FROM drivy.platform_unattached_schools($1::text,$2::integer)', [searchPattern(query.q), query.limit])).rows
        .map(row => unattachedProjection(row.item)),
    }), opening);
    return envelope(data, request);
  });

  async function insertClient(db: PoolClient, actor: PlatformActor, body: z.infer<typeof createClientBody>): Promise<string> {
    const id = randomUUID();
    await db.query(`INSERT INTO drivy.platform_client(id,display_name,contact_name,contact_email,contact_phone,billing_street,billing_postal_code,billing_city,billing_country,internal_notes,created_by)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [id, body.displayName ?? null, body.contactName ?? null, body.contactEmail ?? null, body.contactPhone ?? null, body.billingStreet ?? null,
      body.billingPostalCode ?? null, body.billingCity ?? null, body.billingCountry ?? null, body.internalNotes ?? null, actor.operatorId]);
    return id;
  }
  /** Rattachement explicite : ne touche que la fiche. L'école, ses membres et sa configuration ne changent pas. */
  async function attachSchool(db: PoolClient, actor: PlatformActor, clientId: string, schoolId: string, expected: number) {
    const updated = await db.query(`UPDATE drivy.platform_client SET school_id=$2,link_source='EXISTING_SCHOOL',school_linked_at=date_trunc('milliseconds',clock_timestamp()),
      school_linked_by=$3,updated_by=$3 WHERE id=$1 AND school_id IS NULL AND version=$4`, [clientId, schoolId, actor.operatorId, expected]);
    if (updated.rowCount === 1) return;
    const current = (await db.query<{ school_id: string | null; version: number }>('SELECT school_id,version FROM drivy.platform_client WHERE id=$1', [clientId])).rows[0];
    if (!current) throw notFound();
    if (current.school_id) throw new ApiError(409, 'CLIENT_SCHOOL_LINKED', 'Une école est déjà reliée à cette fiche.');
    throw versionConflict();
  }

  app.post('/v1/platform/clients', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = createClientBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body;
    const result = await platformCommand(options.pool, identity, {
      kind: 'CREATE_PLATFORM_CLIENT', operationId, expectedVersion: null, body: content, refusal: { action: 'CREATE_PLATFORM_CLIENT', schoolId: body.schoolId ?? null }, context: opening,
    }, async (db, actor) => {
      const id = await insertClient(db, actor, body);
      if (body.schoolId) await attachSchool(db, actor, id, body.schoolId, 1);
      const data = await readClient(db, id);
      return { data, status: 201 as const, journal: { action: 'CREATE_PLATFORM_CLIENT', schoolId: body.schoolId ?? null, subject: { type: 'PlatformClient', id },
        changes: { fields: clientFieldNames.filter(name => body[name] != null), attachedSchool: !!body.schoolId } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  app.patch('/v1/platform/clients/:id', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = updateClientBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const { operationId, ...content } = body; const fields = clientFieldNames.filter(name => content[name] !== undefined);
    const result = await platformCommand(options.pool, identity, {
      kind: 'UPDATE_PLATFORM_CLIENT', operationId, expectedVersion: expected, body: { id, ...content },
      refusal: { action: 'UPDATE_PLATFORM_CLIENT', subject: { type: 'PlatformClient', id } }, context: opening,
    }, async (db, actor) => {
      const row = (await db.query<{ school_id: string | null; version: number }>('SELECT school_id,version FROM drivy.platform_client WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!row) throw notFound();
      if (row.version !== expected) throw versionConflict();
      const assignments = fields.map((name, index) => `${clientColumn(name)}=$${index + 3}`);
      const updated = await db.query(`UPDATE drivy.platform_client SET ${assignments.join(',')},updated_by=$2 WHERE id=$1 AND version=${expected}`,
        [id, actor.operatorId, ...fields.map(name => content[name] ?? null)]);
      if (updated.rowCount !== 1) throw versionConflict();
      const data = await readClient(db, id);
      // Le journal retient les zones modifiées, jamais leur valeur : coordonnées et notes restent dans la fiche.
      return { data, journal: { action: 'UPDATE_PLATFORM_CLIENT', schoolId: row.school_id, subject: { type: 'PlatformClient', id }, changes: { fields } } };
    });
    return envelope(result.data, request);
  });

  app.post('/v1/platform/clients/:id/attach-school', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = attachSchoolBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'ATTACH_EXISTING_SCHOOL', operationId: body.operationId, expectedVersion: expected, body: { id, schoolId: body.schoolId },
      refusal: { action: 'ATTACH_EXISTING_SCHOOL', schoolId: body.schoolId, subject: { type: 'PlatformClient', id } }, context: opening,
    }, async (db, actor) => {
      await lockClient(db, id);
      await attachSchool(db, actor, id, body.schoolId, expected);
      const data = await readClient(db, id);
      return { data, journal: { action: 'ATTACH_EXISTING_SCHOOL', schoolId: body.schoolId, subject: { type: 'PlatformClient', id }, changes: { source: 'EXISTING_SCHOOL' } } };
    });
    return envelope(result.data, request);
  });

  app.get('/v1/platform/school-codes', async request => {
    const identity = await identityOf(request); const query = codeListQuery.parse(request.query);
    const data = await platformRead(options.pool, identity, async (db, actor) => {
      const scope = JSON.stringify(['platform-codes', actor.operatorId, query.clientId ?? null, query.state ?? null, query.limit]);
      const after = cursors.decode(query.cursor, scope);
      const rows = await codeRows(db, { ...(query.clientId ? { clientId: query.clientId } : {}), state: query.state ?? null, after, limit: query.limit + 1 });
      const page = paged(rows, query.limit, scope, after);
      return { items: page.items.map(codeProjection), total: page.total, nextCursor: page.nextCursor };
    }, opening);
    return envelope(data, request);
  });

  // « Créer un code » : la fiche de suivi naît avec le code (libellé facultatif) ou se rattache à une fiche existante sans école.
  app.post('/v1/platform/school-codes', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = issueCodeBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const days = body.validityDays ?? validityDays; const tokenHash = hashOf(body.code);
    // Le code n'entre ni dans le contenu comparé ni dans le reçu : seule son empreinte à clé serveur y figure.
    const content = { codeHash: tokenHash, clientId: body.clientId ?? null, displayName: body.displayName ?? null, validityDays: days };
    const result = await platformCommand(options.pool, identity, {
      kind: 'CREATE_SCHOOL_OPENING_CODE', operationId: body.operationId, expectedVersion: null, body: content,
      refusal: { action: 'CREATE_SCHOOL_OPENING_CODE', ...(body.clientId ? { subject: { type: 'PlatformClient', id: body.clientId } } : {}) }, context: opening,
    }, async (db, actor) => {
      let clientId = body.clientId;
      if (clientId) {
        await lockClient(db, clientId);
        const client = (await db.query<{ school_id: string | null }>('SELECT school_id FROM drivy.platform_client WHERE id=$1 FOR UPDATE', [clientId])).rows[0];
        if (!client) throw notFound();
        if (client.school_id) throw new ApiError(409, 'CLIENT_SCHOOL_LINKED', 'Cette fiche a déjà son école : un code d’ouverture n’a plus d’objet.');
        if ((await db.query("SELECT 1 FROM drivy.school_opening_link WHERE client_id=$1 AND status='AVAILABLE' AND expires_at>now()", [clientId])).rowCount)
          throw new ApiError(409, 'CLIENT_CODE_PENDING', 'Un code est déjà utilisable pour cette fiche. Révoquez-le avant d’en créer un autre.');
      } else clientId = await insertClient(db, actor, { operationId: body.operationId, ...(body.displayName ? { displayName: body.displayName } : {}) });
      const linkId = randomUUID();
      const link = (await db.query<{ expires_at: Date }>(`INSERT INTO drivy.school_opening_link(id,token_hash,reserved_school_id,reserved_membership_id,created_by_issuer,created_by_subject,
        create_operation_id,create_hash,expires_at,client_id,issued_by_operator_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,now()+make_interval(days=>$9),$10,$11) RETURNING expires_at`,
      [linkId, tokenHash, randomUUID(), randomUUID(), identity.issuer, identity.subject, body.operationId, commandHash(content, null), days, clientId, actor.operatorId])).rows[0]!;
      const data = { codeId: linkId, client: await readClient(db, clientId) };
      return { data, status: 201 as const, journal: { action: 'CREATE_SCHOOL_OPENING_CODE', subject: { type: 'SchoolOpeningLink', id: linkId },
        changes: { clientId, newClient: !body.clientId, validityDays: days, expiresAt: link.expires_at.toISOString() } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  app.post('/v1/platform/school-codes/:id/revoke', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = revokeCodeBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'REVOKE_SCHOOL_OPENING_CODE', operationId: body.operationId, expectedVersion: null, body: { id },
      refusal: { action: 'REVOKE_SCHOOL_OPENING_CODE', subject: { type: 'SchoolOpeningLink', id } }, context: opening,
    }, async db => {
      const peek = (await db.query<{ status: string; client_id: string | null }>('SELECT status,client_id FROM drivy.school_opening_link WHERE id=$1', [id])).rows[0];
      if (!peek) throw notFound();
      if (peek.status === 'USED') throw new ApiError(409, 'OPENING_LINK_USED', 'Ce code a déjà été utilisé.');
      // Même verrou de ligne que l'utilisation : si l'utilisation gagne, la révocation voit « utilisé » et refuse.
      const row = (await db.query<{ status: string }>('SELECT status FROM drivy.school_opening_link WHERE id=$1 FOR UPDATE', [id])).rows[0];
      // La politique de mise à jour écarte une ligne devenue « utilisée » entre la lecture et le verrou : ce n'est pas un code inconnu.
      if (!row || row.status === 'USED') throw new ApiError(409, 'OPENING_LINK_USED', 'Ce code a déjà été utilisé.');
      if (row.status === 'REVOKED') throw new ApiError(409, 'OPENING_LINK_REVOKED', 'Ce code est déjà révoqué.');
      await db.query(`UPDATE drivy.school_opening_link SET status='REVOKED',revoked_at=clock_timestamp(),revoke_operation_id=$2,revoked_by_issuer=$3,revoked_by_subject=$4 WHERE id=$1`,
        [id, body.operationId, identity.issuer, identity.subject]);
      const code = (await codeRows(db, { codeId: id, limit: 1 }))[0]?.item;
      if (!code) throw notFound();
      const data = codeProjection(code);
      return { data, journal: { action: 'REVOKE_SCHOOL_OPENING_CODE', subject: { type: 'SchoolOpeningLink', id }, changes: { status: { from: 'AVAILABLE', to: 'REVOKED' }, clientId: peek.client_id } } };
    });
    return envelope(result.data, request);
  });
}
