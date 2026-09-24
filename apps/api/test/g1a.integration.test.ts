import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { parse } from 'yaml';
import { buildApp } from '../src/app.js';
import { createTokenVerifier } from '../src/auth.js';
import { withActor } from '../src/database.js';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') {
  throw new Error('Tests d’intégration : TEST_DATABASE_URL vers la base isolée drivy_test est obligatoire. Aucun test ignoré ni base implicite.');
}
const issuer = 'https://identity.test.invalid';
const pool = new Pool({ connectionString: url, max: 5, connectionTimeoutMillis: 5000 });
let app: ReturnType<typeof buildApp>;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
const validators = new Map<string, ReturnType<Ajv2020['compile']>>();
beforeAll(async () => {
  await migrate(pool);
  keys = await generateKeyPair('RS256');
  const key = await exportJWK(keys.publicKey);
  const verifyToken = createTokenVerifier({ OIDC_ISSUER:issuer, OIDC_AUDIENCE:'drivy-api', OIDC_JWKS_URL:`${issuer}/jwks` }, createLocalJWKSet({ keys:[{ ...key,kid:'integration',alg:'RS256' }] }));
  app = buildApp({ pool, verifyToken, cursorSecret:'secret-test-32-caracteres-minimum' });
  const document = parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml', import.meta.url), 'utf8')) as { components: { schemas: Record<string, object> } };
  const ajv = new Ajv2020({ strict:false, allErrors:true, formats:fullFormats });
  ajv.addSchema({ $id:'drivy-contract', components:document.components });
  for (const name of ['MeEnvelope','SchoolEnvelope','LearnerEnvelope','LearnerPageEnvelope','TrainingEnvelope','TrainingPageEnvelope','Problem']) {
    validators.set(name,ajv.compile({ $ref:`drivy-contract#/components/schemas/${name}` }));
  }
});
beforeEach(async () => {
  // La garde ci-dessus interdit explicitement toute base autre que drivy_test.
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');
  await seedFixtures(pool,issuer);
});
afterAll(async () => { await app?.close(); await pool.end(); });
async function get(path: string, subject = 'demo-instructor') {
  const token = await new SignJWT({}).setProtectedHeader({ alg:'RS256',kid:'integration' }).setSubject(subject)
    .setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  return app.inject({ method:'GET',url:path,headers:{ authorization:`Bearer ${token}` } });
}
function conforms(name: string, data: unknown) {
  const validate = validators.get(name);
  if (!validate) throw new Error(`Validateur absent ${name}`);
  expect(validate(data),JSON.stringify(validate.errors)).toBe(true);
}
const school = `/v1/schools/${id.schoolA}`;
describe('G1A · contrats exacts OpenAPI 3.11', () => {
  it('identifie issuer/subject et liste uniquement les appartenances de la personne', async () => {
    const response = await get('/v1/me');
    expect(response.statusCode).toBe(200); conforms('MeEnvelope',response.json());
    expect(response.json().data.memberships.map((member: { schoolId:string }) => member.schoolId).sort()).toEqual([id.schoolA,id.schoolB]);
    expect(response.json().data.personId).toBe(id.instructor);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.headers.etag).toBe('"1"');
  });
  it('ouvre école, dossier et formation avec les enveloppes canoniques', async () => {
    for (const [path,schema] of [[school,'SchoolEnvelope'],[`${school}/learners/${id.aliceLearner}`,'LearnerEnvelope'],[`${school}/trainings/${id.aliceTraining}`,'TrainingEnvelope']]) {
      const response = await get(path!);
      expect(response.statusCode,response.body).toBe(200); conforms(schema!,response.json());
    }
  });
  it('filtre les pages selon affectation et ne divulgue aucun autre dossier', async () => {
    for (const [path,schema,expected] of [[`${school}/learners`,'LearnerPageEnvelope',id.aliceLearner],[`${school}/trainings`,'TrainingPageEnvelope',id.aliceTraining]]) {
      const response = await get(path!);
      expect(response.statusCode,response.body).toBe(200); conforms(schema!,response.json());
      expect(response.json().data.items.map((item:{id:string})=>item.id)).toEqual([expected]);
    }
  });
  it('retourne une Problem canonique sans données sur un objet inaccessible', async () => {
    const response = await get(`${school}/learners/${id.bobLearner}`);
    expect(response.statusCode).toBe(404); conforms('Problem',response.json());
    expect(response.headers['content-type']).toContain('application/problem+json');
  });
});
describe('G1A · droits réels et isolation', () => {
  it('ADMIN lit les dossiers administratifs de son école uniquement', async () => {
    const response = await get(`${school}/learners`,'demo-admin');
    expect(response.json().data.items.map((row:{id:string})=>row.id)).toEqual([id.aliceLearner,id.bobLearner]);
    expect((await get(`/v1/schools/${id.schoolB}`,'demo-admin')).statusCode).toBe(403);
    expect((await get(`${school}/learners/${id.foreignLearner}`,'demo-admin')).statusCode).toBe(404);
  });
  it('LEARNER lit seulement son dossier et ses formations', async () => {
    expect((await get(`${school}/learners`,'demo-alice')).json().data.items.map((row:{id:string})=>row.id)).toEqual([id.aliceLearner]);
    expect((await get(`${school}/trainings/${id.aliceTraining}`,'demo-alice')).statusCode).toBe(200);
    expect((await get(`${school}/trainings/${id.bobTraining}`,'demo-alice')).statusCode).toBe(404);
    expect((await get(`${school}/trainings?learnerId=${id.bobLearner}`,'demo-alice')).json().data.items).toEqual([]);
  });
  it('INSTRUCTOR non affecté ne découvre aucun dossier', async () => {
    expect((await get(`${school}/learners`,'demo-other-instructor')).json().data.items).toEqual([]);
    expect((await get(`${school}/trainings/${id.aliceTraining}`,'demo-other-instructor')).statusCode).toBe(404);
  });
  it('révocation relue en base malgré JWT encore valide', async () => {
    expect((await get(`${school}/learners`)).statusCode).toBe(200);
    await pool.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1",[id.instructorMember]);
    expect((await get(`${school}/learners`)).statusCode).toBe(403);
    expect((await get('/v1/me')).json().data.memberships.map((row:{schoolId:string})=>row.schoolId)).toEqual([id.schoolB]);
  });
  it('fin d’affectation et retrait de rôle coupent immédiatement les lectures', async () => {
    await pool.query("UPDATE drivy.instructor_assignment SET valid_until='2026-02-01T00:00:00Z' WHERE id=$1",[id.assignment]);
    expect((await get(`${school}/trainings/${id.aliceTraining}`)).statusCode).toBe(404);
    await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);
    await pool.query("UPDATE drivy.membership SET roles=ARRAY['LEARNER'] WHERE id=$1",[id.instructorMember]);
    expect((await get(`${school}/trainings/${id.aliceTraining}`)).statusCode).toBe(404);
  });
  it('cumule les rôles sans importer ceux d’une autre école', async () => {
    expect((await get(`${school}/learners/${id.bobLearner}`)).statusCode).toBe(404);
    expect((await get(`/v1/schools/${id.schoolB}/learners/${id.foreignLearner}`)).statusCode).toBe(200);
    await pool.query("UPDATE drivy.membership SET roles=ARRAY['ADMIN','INSTRUCTOR'] WHERE id=$1",[id.instructorMember]);
    expect((await get(`${school}/learners/${id.bobLearner}`)).statusCode).toBe(200);
  });
  it('ne crée aucun compte sur un subject inconnu et refuse les sessions absentes', async () => {
    expect((await get('/v1/me','unlinked')).statusCode).toBe(403);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.person')).rows[0].count).toBe(6);
    expect((await app.inject({ method:'GET',url:'/v1/me' })).statusCode).toBe(401);
  });
  it('le rôle PostgreSQL réel applique RLS même sans filtre school_id dans SELECT', async () => {
    await withActor(pool,{ issuer,subject:'demo-instructor' },id.schoolA,async db => {
      const role = await db.query('SELECT current_user,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user');
      expect(role.rows[0]).toEqual({ current_user:'drivy_app',rolsuper:false,rolbypassrls:false });
      const rows = await db.query('SELECT school_id FROM drivy.learner_profile');
      expect(rows.rows.length).toBe(2); expect(rows.rows.every(row=>row.school_id===id.schoolA)).toBe(true);
    });
  });
  it('le contexte scolaire ne fuit pas entre connexions réutilisées', async () => {
    await get(`${school}/learners`);
    await withActor(pool,{ issuer,subject:'demo-foreign' },id.schoolB,async db => {
      expect((await db.query('SELECT id FROM drivy.learner_profile')).rows.map(row=>row.id)).toEqual([id.foreignLearner]);
    });
  });
});
describe('G1A · pagination et contraintes persistantes', () => {
  it('conserve les microsecondes PostgreSQL sans répéter la dernière ligne de page', async () => {
    await pool.query("UPDATE drivy.learner_profile SET created_at='2026-01-01T00:00:00.123456Z' WHERE school_id=$1",[id.schoolA]);
    await pool.query("UPDATE drivy.training SET created_at='2026-01-01T00:00:00.123456Z' WHERE school_id=$1",[id.schoolA]);
    for (const [resource,secondId] of [['learners',id.bobLearner],['trainings',id.bobTraining]]) {
      const first = await get(`${school}/${resource}?limit=1`,'demo-admin');
      const cursor = first.json().data.nextCursor as string;
      const second = await get(`${school}/${resource}?limit=1&cursor=${cursor}`,'demo-admin');
      expect(second.statusCode,second.body).toBe(200);
      expect(second.json().data.items.map((row:{id:string})=>row.id)).toEqual([secondId]);
      expect(second.json().data.nextCursor).toBeNull();
    }
  });
  it('pagine de manière stable puis refuse curseur altéré, nouveau filtre ou autre acteur', async () => {
    const first = await get(`${school}/learners?limit=1`,'demo-admin');
    const cursor = first.json().data.nextCursor as string;
    expect(cursor).toBeTypeOf('string');
    const second = await get(`${school}/learners?limit=1&cursor=${cursor}`,'demo-admin');
    expect(second.json().data.items[0].id).toBe(id.bobLearner); expect(second.json().data.nextCursor).toBeNull();
    expect((await get(`${school}/learners?limit=1&q=Alice&cursor=${cursor}`,'demo-admin')).statusCode).toBe(400);
    expect((await get(`${school}/learners?limit=1&cursor=${cursor}`,'demo-instructor')).statusCode).toBe(400);
    expect((await get(`${school}/learners?limit=1&cursor=invalid`,'demo-admin')).statusCode).toBe(400);
  });
  it('refuse filtres inconnus et identifiants mal formés', async () => {
    expect((await get(`${school}/learners?secret=true`)).statusCode).toBe(400);
    expect((await get(`${school}/learners?limit=101`)).statusCode).toBe(400);
    expect((await get('/v1/schools/not-a-uuid')).statusCode).toBe(400);
  });
  it('refuse une formation liée à une offre d’une autre école', async () => {
    await expect(pool.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status) VALUES ($1,$2,$3,$4,'category-b','COMPLETED')",[randomUUID(),id.schoolA,id.aliceLearner,id.offeringB])).rejects.toMatchObject({ code:'23503' });
  });
  it('une version d’offre nouvelle ne contourne pas la formation active unique', async () => {
    const offeringId = randomUUID();
    await pool.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES ($1,$2,'category-b','B',2)",[offeringId,id.schoolA]);
    await expect(pool.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status) VALUES ($1,$2,$3,$4,'category-b','ACTIVE')",[randomUUID(),id.schoolA,id.aliceLearner,offeringId])).rejects.toMatchObject({ code:'23505' });
  });
  it('refuse une affectation sans rôle INSTRUCTOR', async () => {
    await expect(pool.query('INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES ($1,$2,$3,$4,now())',[randomUUID(),id.schoolA,id.aliceTraining,id.adminMember])).rejects.toMatchObject({ code:'23514' });
  });
  it('réapplique les migrations sans modifier le schéma déjà validé', async () => { await expect(migrate(pool)).resolves.toBeUndefined(); });
});
