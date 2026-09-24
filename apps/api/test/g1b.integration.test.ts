import { readFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { parse } from 'yaml';
import { buildApp } from '../src/app.js';
import { createTokenVerifier } from '../src/auth.js';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';

const url=process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname!=='/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool=new Pool({connectionString:url,max:8,connectionTimeoutMillis:5000,application_name:'drivy-g1b-tests'});
const issuer='https://identity.test.invalid';
let app:ReturnType<typeof buildApp>;
let keys:Awaited<ReturnType<typeof generateKeyPair>>;
const validators=new Map<string,ReturnType<Ajv2020['compile']>>();
const school=`/v1/schools/${id.schoolA}`;
beforeAll(async()=>{
  // Remise à zéro de CETTE base de test seulement, puis migration avec le rôle réel de production reproduit.
  if ((await pool.query('SELECT current_database() AS name')).rows[0].name!=='drivy_test') throw new Error('Base de test inattendue.');
  await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');
  await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');
  await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_test_migrator') THEN
    CREATE ROLE drivy_test_migrator NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$`);
  await pool.query('GRANT CREATE ON DATABASE drivy_test TO drivy_test_migrator');
  await pool.query('GRANT USAGE,CREATE ON SCHEMA public TO drivy_test_migrator');
  // La migration 001 gère un rôle applicatif existant ; le propriétaire reçoit seulement ADMIN OPTION sur celui-ci.
  await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_app') THEN
    CREATE ROLE drivy_app NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$`);
  await pool.query('GRANT drivy_app TO drivy_test_migrator WITH ADMIN OPTION');
  await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_invitation_mailer') THEN
    CREATE ROLE drivy_invitation_mailer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$`);
  await pool.query('GRANT drivy_invitation_mailer TO drivy_test_migrator WITH ADMIN OPTION');
  const migrationPool=new Pool({connectionString:url,options:'-c role=drivy_test_migrator'});
  try {
    const privileges=await migrationPool.query('SELECT current_user,rolsuper,rolbypassrls,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user');
    expect(privileges.rows[0]).toEqual({current_user:'drivy_test_migrator',rolsuper:false,rolbypassrls:false,rolcreatedb:false,rolcreaterole:false});
    // Une vraie école G1A précède 002, comme sur l'hébergement : le backfill doit traverser FORCE RLS sous ce propriétaire.
    const initial=await readFile(new URL('../migrations/001_g1a.sql',import.meta.url),'utf8');
    const migration=await migrationPool.connect();
    try {
      await migration.query('BEGIN');await migration.query(initial);
      await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
      await migration.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',['001_g1a.sql',createHash('sha256').update(initial).digest('hex')]);
      await migration.query('COMMIT');
    } catch(error) {await migration.query('ROLLBACK');throw error;} finally {migration.release();}
    await seedFixtures(pool,issuer);
    await migrate(migrationPool);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.school_setup')).rows[0].n).toBe(2);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.school_data_policy WHERE approved_at IS NOT NULL')).rows[0].n).toBe(0);
    const tables=await pool.query("SELECT relname,relrowsecurity,relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r'");
    expect(tables.rows.length).toBe(17);expect(tables.rows.every(row=>row.relrowsecurity && row.relforcerowsecurity)).toBe(true);
  } finally {await migrationPool.end();}
  keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
  app=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},
    createLocalJWKSet({keys:[{...key,kid:'g1b',alg:'RS256'}]}))});
  const document=parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'g1b-contract',components:document.components});
  for(const name of ['SchoolEnvelope','SchoolSetupEnvelopeV3','SchoolReadinessEnvelopeV3','OperationResultEnvelope','Problem']) validators.set(name,ajv.compile({$ref:`g1b-contract#/components/schemas/${name}`}));
  const policySchema=JSON.parse(await readFile(new URL('../contracts/g1b-data-policy.json',import.meta.url),'utf8')) as object;
  ajv.addSchema(policySchema);validators.set('SchoolDataPolicyEnvelope',ajv.compile({$ref:'urn:drivy:contract:g1b-data-policy:1#/$defs/SchoolDataPolicyEnvelope'}));
});
beforeEach(async()=>{
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);
  await pool.query("UPDATE drivy.school SET status='DRAFT' WHERE id=$1",[id.schoolA]);
});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'PATCH'|'PUT'|'POST',path:string,body?:Record<string,unknown>,version?:number,subject='demo-admin',headers:Record<string,string>={}) {
  const token=await new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'g1b'}).setSubject(subject).setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  return app.inject({method,url:path,headers:{authorization:`Bearer ${token}`,...(body?{'idempotency-key':String(body.operationId)}:{}),
    ...(version?{'if-match':`"${version}"`}:{}),...headers},...(body?{payload:body}:{})});
}
const policyBody=()=>({operationId:randomUUID(),noticeText:'Notice de recette synthétique : finalités, destinataires et droits expliqués.',
  retentionText:'Politique de recette synthétique : aucune donnée réelle. Conservation limitée au test.',contactEmail:'privacy@example.invalid',reviewAcknowledged:true});
const setupBody=()=>({operationId:randomUUID(),currentStep:'REVIEW',completedSteps:['IDENTITY','DATA']});
const updateBody=()=>({operationId:randomUUID(),name:'École de recette · été',timeZone:'Europe/Zurich',contactEmail:'contact@example.invalid',impactConfirmed:true});
function conforms(name:string,value:unknown) { const validate=validators.get(name)!;expect(validate(value),JSON.stringify(validate.errors)).toBe(true); }
async function counts() {
  return (await pool.query(`SELECT (SELECT count(*)::int FROM drivy.operation) AS operations,
    (SELECT count(*)::int FROM drivy.audit_event) AS audits,(SELECT count(*)::int FROM drivy.school_data_policy WHERE school_id=$1) AS policies`,[id.schoolA])).rows[0];
}
async function prepare() {
  const response=await call('PUT',`${school}/data-policy`,policyBody(),1);expect(response.statusCode,response.body).toBe(200);
  return (await call('GET',school)).json().data as {version:number;configurationVersion:number};
}
async function waitForSchoolLock() {
  const deadline=Date.now()+4000;
  while(Date.now()<deadline) {
    const waiting=await pool.query("SELECT 1 FROM pg_stat_activity WHERE application_name='drivy-g1b-tests' AND wait_event_type='Lock' AND query LIKE '%FROM drivy.school WHERE id=$1 FOR UPDATE%'");
    if(waiting.rowCount) return;
    await delay(10);
  }
  throw new Error('La commande ne s’est pas présentée au verrou scolaire attendu.');
}

describe('G1B · contrats, prérequis et adoption explicite',()=>{
  it('T233 : GET ne crée rien ; DRAFT peut être évalué sans activation circulaire',async()=>{
    const before=await counts();
    const response=await call('GET',`${school}/setup`);expect(response.statusCode).toBe(200);conforms('SchoolSetupEnvelopeV3',response.json());
    expect(response.json().data.status).toBe('IN_PROGRESS');expect(response.headers.etag).toBe('"1"');
    const ready=await call('GET',`${school}/readiness`);conforms('SchoolReadinessEnvelopeV3',ready.json());
    expect(ready.json().data.activationReady).toBe(false);expect(ready.json().data.activationBlockers.map((b:{code:string})=>b.code)).toEqual(['POLICY_REVIEW_REQUIRED']);
    const policy=await call('GET',`${school}/data-policy`);
    conforms('SchoolDataPolicyEnvelope',policy.json());
    expect(policy.json().data).toMatchObject({version:1,status:'DRAFT',noticeText:'',retentionText:'',approvedAt:null,approvedByMembershipId:null});
    expect(await counts()).toEqual(before);
  });
  it('AP167 valide deviceId sans inventer une capacité de capture scolaire',async()=>{
    const response=await call('GET',`${school}/readiness?deviceId=${randomUUID()}`);expect(response.statusCode).toBe(200);conforms('SchoolReadinessEnvelopeV3',response.json());
    expect(response.json().data.capabilities.find((c:{capability:string})=>c.capability==='CAN_CAPTURE').ready).toBe(false);
    expect((await call('GET',`${school}/readiness?deviceId=invalid`)).statusCode).toBe(400);
  });
  it('AP166 sauvegarde la progression sans approuver de politique',async()=>{
    const response=await call('PATCH',`${school}/setup`,setupBody(),1);
    expect(response.statusCode,response.body).toBe(200);conforms('SchoolSetupEnvelopeV3',response.json());
    expect(response.json().data).toMatchObject({version:2,currentStep:'REVIEW',completedSteps:['IDENTITY','DATA'],status:'IN_PROGRESS'});
    expect(response.json().data.readiness.activationReady).toBe(false);expect(await counts()).toEqual({operations:1,audits:1,policies:1});
  });
  it('AP06 publie une version des seuls paramètres demandés, sans changer modules ni état',async()=>{
    const response=await call('PATCH',school,updateBody(),1);expect(response.statusCode,response.body).toBe(200);conforms('SchoolEnvelope',response.json());
    expect(response.json().data).toMatchObject({name:'École de recette · été',status:'DRAFT',version:2,configurationVersion:2});
    expect((await pool.query('SELECT count(*)::int n FROM drivy.school_settings_version WHERE school_id=$1',[id.schoolA])).rows[0].n).toBe(2);
    expect(await counts()).toEqual({operations:1,audits:1,policies:1});
  });
  it('refuse fuseau invalide, modules indisponibles et absence de confirmation',async()=>{
    for(const [change,code] of [[{timeZone:'Mars/Olympus'},'INVALID_TIME_ZONE'],[{impactConfirmed:false},'CONFIG_IMPACT_REVIEW_REQUIRED'],
      [{modules:{gpsEnabled:true,packsEnabled:false,collectiveCoursesEnabled:false,courseOffersVisibleByDefault:false}},'MODULE_NOT_READY']] as const) {
      const response=await call('PATCH',school,{...updateBody(),...change},1);expect(response.json().code).toBe(code);
    }
    expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('l’adoption conserve exactement les textes/version/acteur sans modifier une ancienne révision',async()=>{
    const body=policyBody();const response=await call('PUT',`${school}/data-policy`,body,1);
    conforms('SchoolDataPolicyEnvelope',response.json());
    expect(response.statusCode,response.body).toBe(200);expect(response.json().data).toMatchObject({version:2,status:'APPROVED',noticeText:body.noticeText,
      retentionText:body.retentionText,approvedByMembershipId:id.adminMember});expect(response.json().data.approvedAt).toBeTruthy();
    const rows=await pool.query('SELECT version,approved_by,notice_text FROM drivy.school_data_policy WHERE school_id=$1 ORDER BY version',[id.schoolA]);
    expect(rows.rows[0]).toEqual({version:1,approved_by:null,notice_text:''});expect(rows.rows.length).toBe(2);
    const readiness=await call('GET',`${school}/readiness`);expect(readiness.json().data.activationReady).toBe(true);
    expect(readiness.json().data.capabilities.every((c:{ready:boolean})=>!c.ready)).toBe(true);
  });
  it('aucune adoption si textes blancs, trop longs, champ inconnu ou accord absent/faux',async()=>{
    for(const change of [{noticeText:'  \n '},{retentionText:'x'.repeat(20001)},{reviewAcknowledged:false},{approvedByMembershipId:id.adminMember}]) {
      const response=await call('PUT',`${school}/data-policy`,{...policyBody(),...change},1);expect(response.statusCode).toBe(400);
    }
    const body:Record<string,unknown>=policyBody();delete body.reviewAcknowledged;
    expect((await call('PUT',`${school}/data-policy`,body,1)).statusCode).toBe(400);
    expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('T174 : confirmation seule ne rend jamais une école prête',async()=>{
    const response=await call('POST',`${school}/activate`,{operationId:randomUUID(),expectedConfigurationVersion:1,reviewAcknowledged:true},1);
    expect(response.statusCode).toBe(409);expect(response.json().code).toBe('POLICY_REVIEW_REQUIRED');conforms('Problem',response.json());
    expect((await call('GET',school)).json().data.status).toBe('DRAFT');expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('T172/T233 : activation explicite réussie, sans offre/GPS/formation inventés',async()=>{
    const schoolData=await prepare();const body={operationId:randomUUID(),expectedConfigurationVersion:schoolData.configurationVersion,reviewAcknowledged:true};
    const response=await call('POST',`${school}/activate`,body,schoolData.version);expect(response.statusCode,response.body).toBe(200);conforms('SchoolEnvelope',response.json());
    expect(response.json().data.status).toBe('ACTIVE');expect((await call('GET',`${school}/setup`)).json().data.status).toBe('COMPLETED');
    const ready=(await call('GET',`${school}/readiness`)).json().data;conforms('SchoolReadinessEnvelopeV3',(await call('GET',`${school}/readiness`)).json());
    expect(ready.capabilities.map((c:{ready:boolean})=>c.ready)).toEqual([true,false,false,false]);
    const replay=await call('POST',`${school}/activate`,body,schoolData.version);expect(replay.statusCode).toBe(200);expect(replay.json().data).toEqual(response.json().data);
    expect(await counts()).toEqual({operations:2,audits:2,policies:2});
    expect((await pool.query('SELECT count(*)::int n FROM drivy.training')).rows[0].n).toBe(3);
  });
  it('une seconde intention d’activer retourne SCHOOL_ALREADY_ACTIVE',async()=>{
    const data=await prepare();const body={operationId:randomUUID(),expectedConfigurationVersion:data.configurationVersion,reviewAcknowledged:true};
    const first=await call('POST',`${school}/activate`,body,data.version);
    const response=await call('POST',`${school}/activate`,{...body,operationId:randomUUID()},first.json().data.version);
    expect(response.json().code).toBe('SCHOOL_ALREADY_ACTIVE');expect(await counts()).toEqual({operations:2,audits:2,policies:2});
  });
});

describe('G1B · écritures idempotentes, droits au commit et rollback PostgreSQL',()=>{
  it('en-têtes manquants, version faible et clé incohérente sont refusés sans effet',async()=>{
    const body=setupBody();expect((await call('PATCH',`${school}/setup`,body)).statusCode).toBe(428);
    expect((await call('PATCH',`${school}/setup`,body,1,'demo-admin',{'if-match':'W/"1"'})).statusCode).toBe(400);
    expect((await call('PATCH',`${school}/setup`,body,1,'demo-admin',{'idempotency-key':randomUUID()})).statusCode).toBe(400);
    expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('réponse perdue et rejeu concurrent : un seul effet et résultat identique',async()=>{
    const body=setupBody();const responses=await Promise.all([call('PATCH',`${school}/setup`,body,1),call('PATCH',`${school}/setup`,body,1)]);
    expect(responses.map(r=>r.statusCode)).toEqual([200,200]);expect(responses[0]!.json().data).toEqual(responses[1]!.json().data);
    expect(await counts()).toEqual({operations:1,audits:1,policies:1});
  });
  it('refuse une même clé avec corps/version/type/école différent sans exposer l’ancien résultat',async()=>{
    const body=setupBody();expect((await call('PATCH',`${school}/setup`,body,1)).statusCode).toBe(200);
    for(const response of [await call('PATCH',`${school}/setup`,{...body,currentStep:'DATA'},1),await call('PATCH',`${school}/setup`,body,2),
      await call('PATCH',school,{...updateBody(),operationId:body.operationId},1)]) expect(response.json().code).toBe('IDEMPOTENCY_MISMATCH');
    // Même auteur autorisé dans deux écoles : la clé ne peut pas changer de portée.
    await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,ARRAY['ADMIN'])",[randomUUID(),id.schoolB,id.admin]);
    const response=await call('PATCH',`/v1/schools/${id.schoolB}/setup`,body,1);expect(response.json().code).toBe('IDEMPOTENCY_MISMATCH');
    expect(response.body).not.toContain('completedSteps');expect(await counts()).toEqual({operations:1,audits:1,policies:1});
  });
  it('deux intentions avec même version : une gagne, l’autre conserve ses préconditions',async()=>{
    const responses=await Promise.all([call('PATCH',`${school}/setup`,setupBody(),1),call('PATCH',`${school}/setup`,setupBody(),1)]);
    expect(responses.map(r=>r.statusCode).sort()).toEqual([200,412]);expect(await counts()).toEqual({operations:1,audits:1,policies:1});
  });
  it('T235 : la configuration changée depuis la revue empêche activation',async()=>{
    const previous=await prepare();const update=await call('PATCH',school,updateBody(),previous.version);expect(update.statusCode).toBe(200);
    const response=await call('POST',`${school}/activate`,{operationId:randomUUID(),expectedConfigurationVersion:previous.configurationVersion,reviewAcknowledged:true},update.json().data.version);
    expect(response.statusCode).toBe(412);expect((await call('GET',school)).json().data.status).toBe('DRAFT');expect(await counts()).toEqual({operations:2,audits:2,policies:2});
  });
  it('ADMIN requis pour lectures de configuration et toutes les mutations',async()=>{
    for(const subject of ['demo-instructor','demo-alice']) {
      for(const path of ['setup','readiness']) expect((await call('GET',`${school}/${path}`,undefined,undefined,subject)).statusCode).toBe(403);
      // G1D ouvre la lecture des notices approuvées aux membres ; le brouillon reste invisible.
      expect((await call('GET',`${school}/data-policy`,undefined,undefined,subject)).statusCode).toBe(404);
      expect((await call('PATCH',`${school}/setup`,setupBody(),1,subject)).statusCode).toBe(403);
      expect((await call('PUT',`${school}/data-policy`,policyBody(),1,subject)).statusCode).toBe(403);
    }
    expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('une école hors périmètre ne peut être modifiée, même avec ses IDs connus',async()=>{
    const response=await call('PATCH',`/v1/schools/${id.schoolB}/setup`,setupBody(),1);expect(response.statusCode).toBe(404);
    expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('révocation pendant attente du verrou : aucun effet après le retrait de droits',async()=>{
    const controller=await pool.connect();await controller.query('BEGIN');await controller.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);
    const pending=call('PATCH',`${school}/setup`,setupBody(),1);
    try {
      await waitForSchoolLock();await pool.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1",[id.adminMember]);
    } finally {await controller.query('ROLLBACK');controller.release();}
    const response=await pending;expect([403,404]).toContain(response.statusCode);expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
  it('un résultat connu ne fuit pas après révocation',async()=>{
    const body=setupBody();expect((await call('PATCH',`${school}/setup`,body,1)).statusCode).toBe(200);
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.adminMember]);
    const response=await call('PATCH',`${school}/setup`,body,1);expect(response.statusCode).toBe(404);expect(response.body).not.toContain('completedSteps');
  });
  it('AP72 prouve un commit à son seul auteur et à son école, sans charge personnelle',async()=>{
    const body=policyBody();expect((await call('PUT',`${school}/data-policy`,body,1)).statusCode).toBe(200);
    const response=await call('GET',`${school}/operations/${body.operationId}`);expect(response.statusCode).toBe(200);conforms('OperationResultEnvelope',response.json());
    expect(response.json().data).toMatchObject({operationId:body.operationId,commandType:'ADOPT_SCHOOL_DATA_POLICY',resourceType:'SchoolDataPolicy',resourceId:id.schoolA,resourceVersion:2});
    expect(response.body).not.toContain(body.noticeText);expect(response.body).not.toContain(body.contactEmail);
    await pool.query("UPDATE drivy.membership SET roles=ARRAY['ADMIN'] WHERE id=$1",[id.instructorMember]);
    expect((await call('GET',`${school}/operations/${body.operationId}`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
    expect((await call('GET',`${school}/operations/${randomUUID()}`)).statusCode).toBe(404);
    expect((await call('GET',`/v1/schools/${id.schoolB}/operations/${body.operationId}`)).statusCode).toBe(403);
  });
  it('échec réel de l’audit annule politique, version scolaire et preuve d’opération',async()=>{
    await pool.query("CREATE FUNCTION drivy.test_reject_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test_audit_failure'; END $$");
    await pool.query('CREATE TRIGGER test_reject_audit BEFORE INSERT ON drivy.audit_event FOR EACH ROW EXECUTE FUNCTION drivy.test_reject_audit()');
    const body=policyBody();
    try {
      const response=await call('PUT',`${school}/data-policy`,body,1);expect(response.statusCode).toBe(503);
      expect(await counts()).toEqual({operations:0,audits:0,policies:1});expect((await call('GET',school)).json().data.version).toBe(1);
    } finally {await pool.query('DROP TRIGGER test_reject_audit ON drivy.audit_event');await pool.query('DROP FUNCTION drivy.test_reject_audit()');}
    expect((await call('PUT',`${school}/data-policy`,body,1)).statusCode).toBe(200);
  });
  it('RLS interdit mutation identité/rôles, autres écoles et réécriture des preuves',async()=>{
    await prepare();
    for(const [sql,parameters] of [
      ['UPDATE drivy.person SET version=version+1 WHERE id=$1',[id.admin]],
      ['UPDATE drivy.membership SET version=version+1 WHERE id=$1',[id.adminMember]],
      ["UPDATE drivy.school_data_policy SET notice_text='altéré' WHERE school_id=$1",[id.schoolA]],
      ['DELETE FROM drivy.audit_event WHERE school_id=$1',[id.schoolA]],
      ['DELETE FROM drivy.operation WHERE school_id=$1',[id.schoolA]],
      ['INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text) VALUES($1,1,\'\',\'\')',[id.schoolB]]
    ] as const) {
      const db=await pool.connect();try{
        await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');await db.query("SELECT set_config('app.person_id',$1,true),set_config('app.school_id',$2,true)",[id.admin,id.schoolA]);
        await expect(db.query(sql,[...parameters])).rejects.toThrow();
      }finally{await db.query('ROLLBACK');db.release();}
    }
    const events=await pool.query('SELECT action,changed_fields FROM drivy.audit_event');expect(events.rows).toEqual([{action:'SchoolDataPolicyAdopted',changed_fields:['noticeText','retentionText','contactEmail']}]);
  });
  it('école archivée : lecture permise, écriture refusée sans effet',async()=>{
    await pool.query("UPDATE drivy.school SET status='ARCHIVED' WHERE id=$1",[id.schoolA]);
    expect((await call('GET',`${school}/setup`)).statusCode).toBe(200);
    const response=await call('PATCH',`${school}/setup`,setupBody(),1);expect(response.json().code).toBe('SCHOOL_ARCHIVED');expect(await counts()).toEqual({operations:0,audits:0,policies:1});
  });
});
