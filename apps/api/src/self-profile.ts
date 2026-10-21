import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { Identity, TokenVerifier } from './auth.js';
import { ApiError, forbidden, notFound } from './errors.js';
import { rollbackQuietly, withActor } from './database.js';
import { requireVersion } from './commands.js';
import { canonicalCaptureJSON, type CaptureConfig } from './capture-crypto.js';
import { cleanJpeg, PHOTO_MAX_BYTES } from './profile-photo.js';

/** Même contrôle que le nom saisi à l'ouverture d'une école : espaces de bord retirés, NFC, sans caractère de contrôle. */
const name = (max: number) => z.string().transform(value => value.trim().normalize('NFC'))
  .refine(value => [...value].length >= 1 && [...value].length <= max, `Entre 1 et ${max} caractères.`)
  .refine(value => !/[\u0000-\u001f\u007f]/u.test(value), 'Caractère non autorisé.');
const optionalName = (max: number) => z.union([z.null(), z.string()]).transform(value => {
  const trimmed = value?.trim().normalize('NFC') ?? '';
  return trimmed === '' ? null : trimmed;
}).refine(value => value === null || ([...value].length <= max && !/[\u0000-\u001f\u007f]/u.test(value)), 'Valeur invalide.');
const phone = z.union([z.null(), z.string()]).transform(value => {
  const trimmed = value?.trim() ?? '';
  return trimmed === '' ? null : trimmed;
}).refine(value => value === null || /^[+0-9 ().\-/]{3,32}$/.test(value), 'Numéro invalide.');
const update = z.object({
  displayName: name(200),
  firstName: optionalName(150).optional(),
  lastName: optionalName(150).optional(),
  contactPhone: phone.optional(),
}).strict();
const empty = z.object({}).strict();

interface PersonRow { id: string; display_name: string; first_name: string | null; last_name: string | null; contact_phone: string | null; version: number; photo_version: number }
const projection = (row: PersonRow) => ({ personId: row.id, displayName: row.display_name, firstName: row.first_name, lastName: row.last_name,
  contactPhone: row.contact_phone, photoVersion: row.photo_version > 0 ? row.photo_version : null, version: row.version });
const columns = 'id,display_name,first_name,last_name,contact_phone,version,photo_version';

const photoAAD = (personId: string, photoVersion: number) => Buffer.from(canonicalCaptureJSON({ personId, kind: 'profile-photo', photoVersion }));

/**
 * Profil personnel (extension hors contrat canonique, apps/api/contracts/self-profile.json).
 * La personne connectée lit et modifie son propre compte Drivy, quel que soit son rôle : nom affiché, prénom, nom, téléphone
 * et photo. If-Match porte la version de la personne. Un nouvel envoi identique après une réponse perdue répond 200 sans
 * conflit. Aucun rôle, droit ni dossier d'élève n'est modifié ici.
 */
export function registerSelfProfile(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier; capture?: CaptureConfig }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  const configured = () => {
    if (!options.capture) throw new ApiError(503, 'PHOTO_STORAGE_UNAVAILABLE', 'L’enregistrement des photos n’est pas encore configuré.');
    return options.capture;
  };

  /** Transaction d'écriture sur la seule personne connectée, verrouillée. */
  async function own<T>(identity: Identity, work: (db: PoolClient, person: PersonRow) => Promise<T>): Promise<T> {
    const db = await options.pool.connect();
    let broken = false;
    try {
      await db.query('BEGIN');
      await db.query("SET LOCAL lock_timeout='5s'");
      await db.query("SET LOCAL statement_timeout='10s'");
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.self_profile','true',true)",
        [identity.issuer, identity.subject]);
      const link = await db.query<{ person_id: string }>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject]);
      const personId = link.rows[0]?.person_id;
      if (!personId) throw new ApiError(403, 'IDENTITY_NOT_LINKED', 'Ce compte ne dispose pas encore d’un accès Drivy.');
      await db.query("SELECT set_config('app.person_id',$1,true)", [personId]);
      const person = (await db.query<PersonRow>(`SELECT ${columns} FROM drivy.person WHERE id=$1 AND status='ACTIVE' FOR UPDATE`, [personId])).rows[0];
      if (!person) throw forbidden();
      const value = await work(db, person);
      await db.query('COMMIT');
      return value;
    } catch (error) {
      broken = !(await rollbackQuietly(db));
      throw error;
    } finally { db.release(broken); }
  }
  const conflict = () => new ApiError(412, 'VERSION_CONFLICT', 'Votre profil a changé entre-temps. Rechargez-le avant d’enregistrer.');

  app.get('/v1/me/profile', async (request, reply) => {
    empty.parse(request.query);
    const identity = await options.verifyToken(request.headers.authorization);
    const data = await withActor(options.pool, identity, undefined, async (db, actor) => {
      const row = (await db.query<PersonRow>(`SELECT ${columns} FROM drivy.person WHERE id=$1`, [actor.personId])).rows[0];
      if (!row) throw forbidden();
      return projection(row);
    });
    reply.header('ETag', `"${data.version}"`);
    return envelope(data, request);
  });

  app.patch('/v1/me/profile', async (request, reply) => {
    empty.parse(request.query);
    const value = update.parse(request.body);
    const expected = requireVersion(request.headers['if-match']);
    const identity = await options.verifyToken(request.headers.authorization);
    const data = await own(identity, async (db, person) => {
      const next = {
        display_name: value.displayName,
        first_name: value.firstName === undefined ? person.first_name : value.firstName,
        last_name: value.lastName === undefined ? person.last_name : value.lastName,
        contact_phone: value.contactPhone === undefined ? person.contact_phone : value.contactPhone,
      };
      const same = next.display_name === person.display_name && next.first_name === person.first_name
        && next.last_name === person.last_name && next.contact_phone === person.contact_phone;
      if (same) return projection(person);
      if (person.version !== expected) throw conflict();
      const row = (await db.query<PersonRow>(`UPDATE drivy.person SET display_name=$2,first_name=$3,last_name=$4,contact_phone=$5,version=version+1
        WHERE id=$1 RETURNING ${columns}`, [person.id, next.display_name, next.first_name, next.last_name, next.contact_phone])).rows[0]!;
      return projection(row);
    });
    reply.header('ETag', `"${data.version}"`);
    return envelope(data, request);
  });

  // Photo : corps binaire image/jpeg, borné. Le serveur retire les métadonnées (EXIF, position…) avant de chiffrer.
  app.addContentTypeParser('image/jpeg', { parseAs: 'buffer', bodyLimit: PHOTO_MAX_BYTES * 2 }, (_request, body, done) => done(null, body));
  app.put('/v1/me/profile/photo', { bodyLimit: PHOTO_MAX_BYTES * 2 }, async (request, reply) => {
    empty.parse(request.query);
    const expected = requireVersion(request.headers['if-match']);
    const config = configured();
    if (!Buffer.isBuffer(request.body)) throw new ApiError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Envoyez une image JPEG.');
    const image = cleanJpeg(request.body);
    if (!image) throw new ApiError(422, 'PHOTO_INVALID', 'Cette image ne peut pas être utilisée. Choisissez une photo JPEG carrée de 64 à 1024 pixels.');
    const identity = await options.verifyToken(request.headers.authorization);
    const data = await own(identity, async (db, person) => {
      if (person.version !== expected) throw conflict();
      const photoVersion = person.photo_version + 1;
      const encrypted = sealPhoto(config, image.data, photoAAD(person.id, photoVersion));
      await db.query(`INSERT INTO drivy.person_photo(person_id,photo_version,key_id,encrypted_image,byte_size,width,height) VALUES($1,$2,$3,$4,$5,$6,$7)
        ON CONFLICT(person_id) DO UPDATE SET photo_version=EXCLUDED.photo_version,key_id=EXCLUDED.key_id,encrypted_image=EXCLUDED.encrypted_image,
        byte_size=EXCLUDED.byte_size,width=EXCLUDED.width,height=EXCLUDED.height,updated_at=now()`,
        [person.id, photoVersion, config.encryptionKeyId, encrypted, image.data.length, image.width, image.height]);
      const row = (await db.query<PersonRow>(`UPDATE drivy.person SET photo_version=$2,version=version+1 WHERE id=$1 RETURNING ${columns}`,
        [person.id, photoVersion])).rows[0]!;
      return projection(row);
    });
    reply.header('ETag', `"${data.version}"`);
    return envelope(data, request);
  });

  app.delete('/v1/me/profile/photo', async (request, reply) => {
    empty.parse(request.query);
    const expected = requireVersion(request.headers['if-match']);
    const identity = await options.verifyToken(request.headers.authorization);
    const data = await own(identity, async (db, person) => {
      if (person.photo_version === 0) return projection(person);
      if (person.version !== expected) throw conflict();
      await db.query('DELETE FROM drivy.person_photo WHERE person_id=$1', [person.id]);
      const row = (await db.query<PersonRow>(`UPDATE drivy.person SET photo_version=0,version=version+1 WHERE id=$1 RETURNING ${columns}`,
        [person.id])).rows[0]!;
      return projection(row);
    });
    reply.header('ETag', `"${data.version}"`);
    return envelope(data, request);
  });

  /** Photo d'une personne : soi-même, ou un membre actif d'une même école (politique person_photo_read). 404 sinon. */
  app.get('/v1/people/:personId/photo', async (request, reply) => {
    empty.parse(request.query);
    const { personId } = z.object({ personId: z.uuid() }).parse(request.params);
    const config = configured();
    const identity = await options.verifyToken(request.headers.authorization);
    const row = await withActor(options.pool, identity, undefined, async db =>
      (await db.query<{ photo_version: number; key_id: string; encrypted_image: Buffer }>(
        'SELECT photo_version,key_id,encrypted_image FROM drivy.person_photo WHERE person_id=$1', [personId])).rows[0]);
    if (!row || row.key_id !== config.encryptionKeyId) throw notFound();
    const image = openPhoto(config, row.encrypted_image, photoAAD(personId, row.photo_version));
    if (!image) throw notFound();
    reply.header('Cache-Control', 'private, no-store').header('ETag', `"photo-${row.photo_version}"`);
    return reply.type('image/jpeg').send(image);
  });
}

function sealPhoto(config: CaptureConfig, image: Buffer, aad: Buffer): Buffer {
  const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', config.encryptionKey, nonce);
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(image), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), ciphertext]);
}
function openPhoto(config: CaptureConfig, encrypted: Buffer, aad: Buffer): Buffer | undefined {
  try {
    const decipher = createDecipheriv('aes-256-gcm', config.encryptionKey, encrypted.subarray(0, 12));
    decipher.setAuthTag(encrypted.subarray(12, 28)); decipher.setAAD(aad);
    return Buffer.concat([decipher.update(encrypted.subarray(28)), decipher.final()]);
  } catch { return undefined; }
}
