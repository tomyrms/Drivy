import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import { AttemptLimiter } from './attempt-limiter.js';
import type { Identity, TokenVerifier } from './auth.js';
import { checkIdempotency, commandHash, requireVersion } from './commands.js';
import { Cursors } from './cursor.js';
import { ApiError, notFound } from './errors.js';
import {
  currentOperator, databaseRefusal, lockOperation, operationMismatch, operatorRequired, platformCommand, platformRead, platformTransaction,
  readReceipt, recordPlatformAction, writeReceipt,
} from './platform-command.js';
import {
  acceptInvitationBody, createInvitationBody, invitationProjection, invitationStatus, journalProjection, journalQuery, operationBody, operatorProjection,
  platformCodeHasher, platformRightsView, previewInvitationBody,
  type InvitationRow, type JournalRow, type OperatorRow,
} from './platform-model.js';

const empty = z.object({}).strict();
const idParams = z.object({ id: z.uuid() }).strict();
const operationParams = z.object({ operationId: z.uuid() }).strict();
const invitationSelect = `SELECT i.*,o.display_name AS created_by_name FROM drivy.platform_operator_invitation i JOIN drivy.platform_operator o ON o.id=i.created_by`;
const versionConflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Cette fiche a changé. Rechargez-la avant de confirmer.');
const inviteInvalid = () => new ApiError(404, 'PLATFORM_INVITATION_INVALID', 'Ce code n’est pas valide ou n’est plus utilisable.');

function assertOpen(row: InvitationRow) {
  if (row.status === 'USED') throw new ApiError(409, 'PLATFORM_INVITATION_USED', 'Cette invitation a déjà été utilisée.');
  if (row.status === 'REVOKED') throw new ApiError(410, 'PLATFORM_INVITATION_REVOKED', 'Cette invitation a été révoquée. Demandez-en une nouvelle.');
  if (invitationStatus(row) === 'EXPIRED') throw new ApiError(410, 'PLATFORM_INVITATION_EXPIRED', 'Cette invitation a expiré. Demandez-en une nouvelle.');
  // Un code émis par un opérateur retiré ne vaut plus rien. Son retrait révoque déjà ses invitations ; ceci couvre celle qui aurait échappé
  // à cette révocation (retrait hors service, invitation émise pendant le retrait de son auteur). La base refuse aussi l'entrée dans l'équipe.
  if (row.creator_active === false) throw new ApiError(410, 'PLATFORM_INVITATION_REVOKED', 'Cette invitation a été révoquée. Demandez-en une nouvelle.');
}
/** Lecture d'un code par son porteur : pas de jointure sur l'équipe (il ne la lit pas), l'état de l'auteur vient d'une fonction qui ne rend qu'un booléen. */
const codeSelect = `SELECT i.*,drivy.platform_invitation_creator_active(i.id) AS creator_active FROM drivy.platform_operator_invitation i WHERE i.code_hash=$1`;

/**
 * Console des opérateurs de la plateforme. Aucun rôle scolaire n'est accordé et aucune table scolaire n'est lue ici.
 * L'appartenance à l'équipe est relue dans la base à chaque requête, par le service puis par les politiques RLS.
 */
export function registerPlatform(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier; cursorSecret: string; invitationCodeSecret?: string; platformAttempts?: AttemptLimiter }) {
  const hashOf = platformCodeHasher(options.cursorSecret, options.invitationCodeSecret);
  const cursors = new Cursors(options.cursorSecret);
  const attempts = options.platformAttempts ?? new AttemptLimiter(10, 15 * 60_000);
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const identityOf = (request: FastifyRequest) => options.verifyToken(request.headers.authorization);

  /** Un code d'invitation est court : chaque code refusé compte pour l'identité qui l'essaie. */
  async function guarded<T>(identity: Identity, work: () => Promise<T>): Promise<T> {
    const key = AttemptLimiter.key(identity.issuer, identity.subject); const finish = attempts.begin(key); let failed = false;
    try { return await work(); }
    catch (error) { failed = error instanceof ApiError && (error.code === 'PLATFORM_INVITATION_INVALID' || error.code === 'PLATFORM_INVITATION_EMAIL_MISMATCH'); throw error; }
    finally { finish(failed); if (attempts.size > 1000) attempts.sweep(); }
  }
  const lockInvitationCode = (db: PoolClient, codeHash: string) => db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-code:${codeHash}`]);
  const readInvitation = async (db: PoolClient, id: string) => (await db.query<InvitationRow>(`${invitationSelect} WHERE i.id=$1`, [id])).rows[0];

  app.get('/v1/platform/me', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const data = await platformRead(options.pool, identity, async (db, actor) => {
      const row = (await db.query<OperatorRow>('SELECT * FROM drivy.platform_operator WHERE id=$1', [actor.operatorId])).rows[0]!;
      return { operator: operatorProjection(row, actor.operatorId), ...platformRightsView() };
    });
    return envelope(data, request);
  });

  app.get('/v1/platform/operators', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const data = await platformRead(options.pool, identity, async (db, actor) => {
      const rows = (await db.query<OperatorRow>("SELECT * FROM drivy.platform_operator ORDER BY (status='ACTIVE') DESC,created_at,id LIMIT 200")).rows;
      return { items: rows.map(row => operatorProjection(row, actor.operatorId)) };
    });
    return envelope(data, request);
  });

  app.get('/v1/platform/invitations', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const data = await platformRead(options.pool, identity, async db => ({
      items: (await db.query<InvitationRow>(`${invitationSelect} ORDER BY i.created_at DESC,i.id LIMIT 100`)).rows.map(invitationProjection),
    }));
    return envelope(data, request);
  });

  app.post('/v1/platform/invitations', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = createInvitationBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const validityDays = body.validityDays ?? 7; const codeHash = hashOf(body.code);
    const result = await platformCommand(options.pool, identity, {
      kind: 'CREATE_PLATFORM_INVITATION', operationId: body.operationId, expectedVersion: null,
      // Le code n'entre jamais dans l'empreinte du contenu ni dans le reçu : seule son empreinte à clé serveur y figure.
      body: { email: body.email, validityDays, codeHash }, refusal: { action: 'CREATE_PLATFORM_INVITATION' },
    }, async (db, actor) => {
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-invite:${body.email}`]);
      if ((await db.query("SELECT 1 FROM drivy.platform_operator WHERE contact_email=$1 AND status='ACTIVE'", [body.email])).rowCount)
        throw new ApiError(409, 'PLATFORM_OPERATOR_EXISTS', 'Cette adresse appartient déjà à un opérateur actif.');
      if ((await db.query("SELECT 1 FROM drivy.platform_operator_invitation WHERE invitee_email=$1 AND status='AVAILABLE' AND expires_at>now()", [body.email])).rowCount)
        throw new ApiError(409, 'PLATFORM_INVITATION_PENDING', 'Une invitation est déjà en attente pour cette adresse. Révoquez-la d’abord.');
      const id = randomUUID();
      await db.query(`INSERT INTO drivy.platform_operator_invitation(id,code_hash,invitee_email,created_by,expires_at) VALUES($1,$2,$3,$4,now()+make_interval(days=>$5))`,
        [id, codeHash, body.email, actor.operatorId, validityDays]);
      const row = (await readInvitation(db, id))!;
      const data = invitationProjection(row);
      return { data, status: 201 as const, journal: { action: 'CREATE_PLATFORM_INVITATION', subject: { type: 'PlatformInvitation', id },
        changes: { level: row.level, maskedEmail: data.maskedEmail, expiresAt: data.expiresAt } } };
    });
    reply.status(result.status); return envelope(result.data, request);
  });

  app.post('/v1/platform/invitations/:id/revoke', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = operationBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'REVOKE_PLATFORM_INVITATION', operationId: body.operationId, expectedVersion: expected, body: { id },
      refusal: { action: 'REVOKE_PLATFORM_INVITATION', subject: { type: 'PlatformInvitation', id } },
    }, async (db, actor) => {
      const peek = await readInvitation(db, id);
      if (!peek) throw notFound();
      // Même verrou que l'acceptation : une révocation et une acceptation du même code se suivent, elles ne se croisent pas.
      await lockInvitationCode(db, peek.code_hash);
      const row = (await readInvitation(db, id))!;
      if (row.version !== expected) throw versionConflict();
      if (row.status === 'USED') throw new ApiError(409, 'PLATFORM_INVITATION_USED', 'Cette invitation a déjà été utilisée.');
      if (row.status === 'REVOKED') throw new ApiError(409, 'PLATFORM_INVITATION_REVOKED', 'Cette invitation est déjà révoquée.');
      const locked = (await db.query<InvitationRow>("SELECT * FROM drivy.platform_operator_invitation WHERE id=$1 AND status='AVAILABLE' FOR UPDATE", [id])).rows[0];
      if (!locked || locked.version !== expected) throw versionConflict();
      await db.query("UPDATE drivy.platform_operator_invitation SET status='REVOKED',revoked_at=clock_timestamp(),revoked_by=$2 WHERE id=$1", [id, actor.operatorId]);
      const data = invitationProjection((await readInvitation(db, id))!);
      return { data, journal: { action: 'REVOKE_PLATFORM_INVITATION', subject: { type: 'PlatformInvitation', id },
        changes: { status: { from: 'AVAILABLE', to: 'REVOKED' }, maskedEmail: data.maskedEmail } } };
    });
    return envelope(result.data, request);
  });

  app.post('/v1/platform/operators/:id/revoke', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { id } = idParams.parse(request.params); const body = operationBody.parse(request.body);
    const expected = requireVersion(request.headers['if-match']); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const result = await platformCommand(options.pool, identity, {
      kind: 'REVOKE_PLATFORM_OPERATOR', operationId: body.operationId, expectedVersion: expected, body: { id }, teamWide: true,
      refusal: { action: 'REVOKE_PLATFORM_OPERATOR', subject: { type: 'PlatformOperator', id } },
    }, async (db, actor) => {
      const target = (await db.query<OperatorRow>('SELECT * FROM drivy.platform_operator WHERE id=$1', [id])).rows[0];
      if (!target) throw notFound();
      if (target.version !== expected) throw versionConflict();
      if (target.status !== 'ACTIVE') throw new ApiError(409, 'PLATFORM_OPERATOR_REVOKED', 'Cet opérateur n’a plus d’accès.');
      const locked = (await db.query<OperatorRow>("SELECT * FROM drivy.platform_operator WHERE id=$1 AND status='ACTIVE' FOR UPDATE", [id])).rows[0];
      if (!locked || locked.version !== expected) throw versionConflict();
      // Le verrou d'équipe est tenu : personne ne peut retirer un autre opérateur entre ce contrôle et le commit.
      if (!(await db.query("SELECT 1 FROM drivy.platform_operator WHERE status='ACTIVE' AND id<>$1 LIMIT 1", [id])).rowCount)
        throw new ApiError(409, 'LAST_PLATFORM_OPERATOR', 'Le dernier opérateur actif ne peut pas être retiré.');
      const revokedAt = (await db.query<{ at: Date }>("SELECT date_trunc('milliseconds',clock_timestamp()) AS at")).rows[0]!.at;
      const data = operatorProjection({ ...locked, status: 'REVOKED', version: locked.version + 1, revoked_at: revokedAt, revoked_by: actor.operatorId }, actor.operatorId);
      // Les codes que l'opérateur retiré avait émis ne doivent plus ouvrir l'équipe : ils sont révoqués dans la même transaction, tant que l'acteur
      // est encore actif (c'est aussi le cas d'un retrait de soi-même, appliqué plus bas). La base refuse de toute façon un code dont l'auteur est retiré.
      const revokedInvitations = (await db.query(`UPDATE drivy.platform_operator_invitation SET status='REVOKED',revoked_at=clock_timestamp(),revoked_by=$2
        WHERE created_by=$1 AND status='AVAILABLE' AND expires_at>now()`, [id, actor.operatorId])).rowCount ?? 0;
      return {
        data, journal: { action: 'REVOKE_PLATFORM_OPERATOR', subject: { type: 'PlatformOperator', id },
          changes: { status: { from: 'ACTIVE', to: 'REVOKED' }, self: id === actor.operatorId, revokedInvitations } },
        // Appliquée après le reçu et le journal : un opérateur qui se retire écrit sa trace tant qu'il en a le droit.
        apply: async client => {
          const updated = await client.query('UPDATE drivy.platform_operator SET status=\'REVOKED\',revoked_at=$2,revoked_by=$3 WHERE id=$1 AND version=$4',
            [id, revokedAt, actor.operatorId, expected]);
          if (updated.rowCount !== 1) throw versionConflict();
        },
      };
    });
    return envelope(result.data, request);
  });

  app.get('/v1/platform/operations/:operationId', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { operationId } = operationParams.parse(request.params);
    const data = await platformRead(options.pool, identity, async db => {
      const receipt = await readReceipt(db, identity, operationId);
      if (!receipt) throw notFound();
      return { operationId, kind: receipt.kind, statusCode: receipt.status_code, result: receipt.response };
    });
    return envelope(data, request);
  });

  app.get('/v1/platform/journal', async request => {
    const identity = await identityOf(request);
    const query = journalQuery.parse(request.query);
    const data = await platformRead(options.pool, identity, async (db, actor) => {
      const scope = JSON.stringify(['platform-journal', actor.operatorId, query.schoolId ?? null, query.result ?? null, query.limit]);
      const position = cursors.decode(query.cursor, scope);
      const rows = (await db.query<JournalRow>(`SELECT * FROM drivy.platform_audit_event
        WHERE ($1::uuid IS NULL OR school_id=$1) AND ($2::text IS NULL OR result=$2) AND ($3::timestamptz IS NULL OR (occurred_at,id)<($3::timestamptz,$4::uuid))
        ORDER BY occurred_at DESC,id DESC LIMIT $5`,
      [query.schoolId ?? null, query.result ?? null, position?.createdAt ?? null, position?.id ?? null, query.limit + 1])).rows;
      const last = rows.length > query.limit ? rows[query.limit - 1] : undefined;
      return { items: rows.slice(0, query.limit).map(journalProjection),
        nextCursor: last ? cursors.encode(scope, { createdAt: last.occurred_at.toISOString(), id: last.id }) : null };
    });
    return envelope(data, request);
  });

  // Lecture d'un code par son porteur : droits accordés et refusés, adresse masquée, état. Rien ne change avant l'acceptation.
  app.post('/v1/platform/invitations/preview', async request => {
    const identity = await identityOf(request); empty.parse(request.query);
    const { code } = previewInvitationBody.parse(request.body); const codeHash = hashOf(code);
    const data = await guarded(identity, () => platformTransaction(options.pool, identity, async db => {
      // Pas de jointure sur l'équipe : le porteur du code n'est pas encore opérateur et ne la lit pas.
      const row = (await db.query<InvitationRow>(codeSelect, [codeHash])).rows[0];
      if (!row) throw inviteInvalid();
      assertOpen(row);
      const member = (await db.query<{ id: string | null }>('SELECT drivy.current_platform_operator() AS id')).rows[0]?.id ?? null;
      return { status: 'AVAILABLE' as const, ...platformRightsView(), maskedEmail: invitationProjection(row).maskedEmail, expiresAt: row.expires_at.toISOString(),
        matchesAccount: !!identity.verifiedEmail && identity.verifiedEmail === row.invitee_email, alreadyMember: member !== null };
    }, { readOnly: true, invitationHash: codeHash, ...(identity.verifiedEmail ? { verifiedEmail: identity.verifiedEmail } : {}) }));
    return envelope(data, request);
  });

  // Aucun privilège avant cette route : l'appartenance naît ici, d'un code valide, pour l'adresse vérifiée qu'il vise.
  app.post('/v1/platform/invitations/accept', async (request, reply) => {
    const identity = await identityOf(request); empty.parse(request.query);
    const body = acceptInvitationBody.parse(request.body); checkIdempotency(request.headers['idempotency-key'], body.operationId);
    const codeHash = hashOf(body.code); const hash = commandHash({ codeHash }, null);
    const kind = 'ACCEPT_PLATFORM_INVITATION';
    const result = await guarded(identity, async () => {
      try {
        return await platformTransaction(options.pool, identity, async db => {
          await lockOperation(db, identity, body.operationId);
          const known = await readReceipt(db, identity, body.operationId);
          if (known) {
            if (known.kind !== kind || known.request_hash !== hash) throw operationMismatch();
            return { data: known.response, status: known.status_code };
          }
          if ((await db.query('SELECT drivy.current_platform_operator() AS id')).rows[0]?.id)
            throw new ApiError(409, 'PLATFORM_ALREADY_MEMBER', 'Ce compte fait déjà partie de l’équipe.');
          // Un code ne sert qu'une fois : deux acceptations simultanées passent l'une après l'autre, la seconde voit « utilisée ».
          await lockInvitationCode(db, codeHash);
          const row = (await db.query<InvitationRow>(codeSelect, [codeHash])).rows[0];
          if (!row) throw inviteInvalid();
          assertOpen(row);
          if (!identity.verifiedEmail) throw new ApiError(403, 'EMAIL_VERIFICATION_REQUIRED', 'Vérifiez l’adresse e-mail de votre compte avant d’accepter.');
          if (identity.verifiedEmail !== row.invitee_email) throw new ApiError(403, 'PLATFORM_INVITATION_EMAIL_MISMATCH', 'Cette invitation est destinée à une autre adresse.');
          const operatorId = randomUUID();
          const displayName = (identity.displayName ?? ([identity.firstName, identity.lastName].filter(Boolean).join(' ') || identity.verifiedEmail.split('@')[0]!)).slice(0, 200);
          // Pas de RETURNING : l'appartenance n'est lisible qu'une fois l'instruction terminée.
          await db.query(`INSERT INTO drivy.platform_operator(id,issuer,subject,display_name,contact_email,added_via,invitation_id) VALUES($1,$2,$3,$4,$5,'INVITATION',$6)`,
            [operatorId, identity.issuer, identity.subject, displayName, identity.verifiedEmail, row.id]);
          const used = await db.query("UPDATE drivy.platform_operator_invitation SET status='USED',used_at=clock_timestamp(),used_by=$2 WHERE id=$1 AND status='AVAILABLE' RETURNING id", [row.id, operatorId]);
          if (!used.rowCount) throw new ApiError(409, 'PLATFORM_INVITATION_USED', 'Cette invitation a déjà été utilisée.');
          const created = (await db.query<OperatorRow>('SELECT * FROM drivy.platform_operator WHERE id=$1', [operatorId])).rows[0]!;
          const data = { operator: operatorProjection(created, operatorId), ...platformRightsView() };
          await writeReceipt(db, identity, kind, body.operationId, hash, 201, data);
          await recordPlatformAction(db, { operatorId, displayName }, { action: kind, subject: { type: 'PlatformOperator', id: operatorId },
            changes: { level: row.level, addedVia: 'INVITATION' } }, { operationId: body.operationId });
          return { data, status: 201 };
        }, { invitationHash: codeHash, ...(identity.verifiedEmail ? { verifiedEmail: identity.verifiedEmail } : {}) });
      } catch (error) {
        // Filet : si l'invitation se ferme entre la lecture et l'insertion, la politique de la base refuse l'entrée dans l'équipe.
        if (typeof error === 'object' && error !== null && 'code' in error && error.code === '42501')
          throw new ApiError(409, 'PLATFORM_INVITATION_CLOSED', 'Cette invitation n’est plus ouverte.');
        throw databaseRefusal(error) ?? error;
      }
    });
    reply.status(result.status); return envelope(result.data, request);
  });
}

export { currentOperator, operatorRequired };
