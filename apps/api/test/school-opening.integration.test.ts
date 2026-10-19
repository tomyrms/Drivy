import { randomBytes, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, expect, test } from 'vitest';
import type { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import { registerSchoolOpening } from '../src/school-opening.js';
import { freshDatabase, issuer, id } from './support/harness.js';
import { seedFixtures } from '../scripts/fixtures.js';
import { ApiError } from '../src/errors.js';

let pool:Pool,app:ReturnType<typeof buildApp>;
const operator='opening-operator',base='/v1/operator/school-opening-links';
const verifyToken=async(header:string|undefined)=>{if(!header?.startsWith('Bearer '))throw new ApiError(401,'AUTHENTICATION_REQUIRED','Connexion requise.');return {issuer,subject:header.slice(7)};};
const schoolOpening={operators:[{issuer,subject:operator}],validityDays:7};
beforeAll(async()=>{
  pool=await freshDatabase();
  app=buildApp({pool,verifyToken,cursorSecret:'opening-synthetic-test-secret-32-characters',schoolOpening});
  if(!app.hasRoute({method:'GET',url:base}))registerSchoolOpening(app,{pool,verifyToken,cursorSecret:'opening-synthetic-test-secret-32-characters',schoolOpening});
});
beforeEach(async()=>{await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);});
afterAll(async()=>{await app?.close();await pool?.end();});
const call=(method:'GET'|'POST',url:string,body?:Record<string,unknown>,subject=operator)=>app.inject({method,url,headers:{authorization:`Bearer ${subject}`,...(body?{'idempotency-key':String(body.operationId)}:{})},...(body?{payload:body}:{})});
const command=(token:string,extra:Record<string,unknown>={})=>({operationId:randomUUID(),token,schoolName:'École de recette',displayName:'Responsable de recette',contactEmail:'school@example.invalid',contactPhone:null,timeZone:'Europe/Zurich',instructs:false,...extra});
async function issue() {
  const token=randomBytes(32).toString('base64url'),body={operationId:randomUUID(),token};
  const response=await call('POST',base,body);expect(response.statusCode,response.body).toBe(201);
  return {token,body,link:response.json().data};
}

test('opérateur explicite, fermé sans liste ; ADMIN scolaire insuffisant et identité inconnue autorisée comme opérateur',async()=>{
  expect((await call('POST',base,{operationId:randomUUID(),token:randomBytes(32).toString('base64url')},'demo-admin')).statusCode).toBe(403);
  expect((await app.inject({url:base})).statusCode).toBe(401);
  const closed=buildApp({pool,verifyToken,cursorSecret:'opening-test-default-closed-secret-32'});
  if(!closed.hasRoute({method:'GET',url:base}))registerSchoolOpening(closed,{pool,verifyToken,cursorSecret:'opening-test-default-closed-secret-32'});
  expect((await closed.inject({url:base,headers:{authorization:`Bearer ${operator}`}})).statusCode).toBe(403);await closed.close();
  const created=await issue();expect(created.link.status).toBe('AVAILABLE');
  expect((await pool.query('SELECT 1 FROM drivy.identity_link WHERE subject=$1',[operator])).rowCount).toBe(0);
});
test('création du lien idempotente, sept jours, secret haché uniquement et GET sans consommation',async()=>{
  const created=await issue(),again=await call('POST',base,created.body);
  expect(again.statusCode).toBe(201);expect(again.json().data.id).toBe(created.link.id);
  expect(Math.round((Date.parse(created.link.expiresAt)-Date.parse(created.link.createdAt))/86400000)).toBe(7);
  expect((await call('GET',base)).json().data.items).toHaveLength(1);
  const row=(await pool.query('SELECT * FROM drivy.school_opening_link WHERE id=$1',[created.link.id])).rows[0];
  expect(JSON.stringify(row).includes(created.token)).toBe(false);expect(row.status).toBe('AVAILABLE');
  expect((await call('POST',base,{...created.body,token:randomBytes(32).toString('base64url')})).json().code).toBe('IDEMPOTENCY_MISMATCH');
  const preview=await call('POST','/v1/school-openings/preview',{token:created.token},'new-person');expect(preview.statusCode,preview.body).toBe(200);
  expect(preview.json().data.status).toBe('AVAILABLE');expect((await pool.query('SELECT status FROM drivy.school_opening_link WHERE id=$1',[created.link.id])).rows[0].status).toBe('AVAILABLE');
  expect((await pool.query('SELECT 1 FROM drivy.identity_link WHERE subject=$1',['new-person'])).rowCount).toBe(0);
});
test('une identité OIDC inconnue crée atomiquement Person, école DRAFT, ADMIN et préparation non approuvée',async()=>{
  const {token}=await issue(),response=await call('POST','/v1/school-openings',command(token),'new-person');expect(response.statusCode,response.body).toBe(201);
  const result=response.json().data;expect(result.status).toBe('DRAFT');expect(result.roles).toEqual(['ADMIN']);expect(result.grants).toEqual(['CONFIGURE_CATALOG']);
  const setup=await pool.query('SELECT * FROM drivy.school_setup WHERE school_id=$1',[result.schoolId]);expect(setup.rowCount).toBe(1);
  expect((await pool.query('SELECT approved_at,notice_text FROM drivy.school_data_policy WHERE school_id=$1',[result.schoolId])).rows[0]).toMatchObject({approved_at:null,notice_text:''});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE school_id=$1 AND action=$2',[result.schoolId,'SchoolOpened'])).rows[0].n).toBe(1);
  const me=await call('GET','/v1/me',undefined,'new-person');expect(me.statusCode).toBe(200);expect(me.json().data.memberships.map((member:{schoolId:string})=>member.schoolId)).toContain(result.schoolId);
});
test('moniteur explicite et identité existante : aucun autre rôle ni doublon Person',async()=>{
  const {token}=await issue(),before=(await pool.query('SELECT count(*)::int AS n FROM drivy.person')).rows[0].n;
  const response=await call('POST','/v1/school-openings',command(token,{instructs:true}),'demo-admin');expect(response.statusCode,response.body).toBe(201);
  expect(response.json().data.roles).toEqual(['ADMIN','INSTRUCTOR']);expect((await pool.query('SELECT count(*)::int AS n FROM drivy.person')).rows[0].n).toBe(before);
  expect((await pool.query('SELECT person_id FROM drivy.membership WHERE id=$1',[response.json().data.membershipId])).rows[0].person_id).toBe(id.admin);
});
test('rejeu et récupération sans secret : reçu durable, accès courant relu et aucun doublon',async()=>{
  const {token}=await issue(),body=command(token),first=await call('POST','/v1/school-openings',body,'recovering');expect(first.statusCode,first.body).toBe(201);
  const replay=await call('POST','/v1/school-openings',body,'recovering');expect(replay.statusCode,replay.body).toBe(201);expect(replay.json().data).toEqual(first.json().data);
  const recovery=await call('GET',`/v1/school-openings/operations/${body.operationId}`,undefined,'recovering');expect(recovery.json().data).toEqual(first.json().data);
  const reopen=await call('POST','/v1/school-openings/preview',{token},'recovering');expect(reopen.json().data.school.schoolId).toBe(first.json().data.schoolId);
  expect((await call('POST','/v1/school-openings',{...body,schoolName:'Autre contenu'},'recovering')).json().code).toBe('IDEMPOTENCY_MISMATCH');
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[first.json().data.membershipId]);
  expect((await call('GET',`/v1/school-openings/operations/${body.operationId}`,undefined,'recovering')).statusCode).toBe(403);
});
test('lien utilisé par une autre identité : aucune fuite de l’école et aucun second usage',async()=>{
  const {token}=await issue(),first=await call('POST','/v1/school-openings',command(token),'first');expect(first.statusCode,first.body).toBe(201);
  const preview=await call('POST','/v1/school-openings/preview',{token},'other');expect(preview.statusCode).toBe(409);expect(preview.json().code).toBe('OPENING_LINK_USED');
  expect(preview.body.includes(first.json().data.schoolId)).toBe(false);
  expect((await call('POST','/v1/school-openings',command(token),'other')).json().code).toBe('OPENING_LINK_USED');
  expect((await call('GET',`/v1/school-openings/operations/${first.json().data.operationId}`,undefined,'other')).statusCode).toBe(404);
});

test('revisiter un lien USED avec une nouvelle opération rend le reçu original sans réécrire les choix',async()=>{
  const {token}=await issue(),body=command(token),first=await call('POST','/v1/school-openings',body,'revisiting');expect(first.statusCode,first.body).toBe(201);
  const changed=command(token,{schoolName:'Nom ignoré lors de la reprise',instructs:true});
  const recovery=await call('POST','/v1/school-openings',changed,'revisiting');expect(recovery.statusCode,recovery.body).toBe(201);
  expect(recovery.json().data).toEqual(first.json().data);expect(recovery.json().data.operationId).toBe(body.operationId);
  expect((await pool.query('SELECT name FROM drivy.school WHERE id=$1',[first.json().data.schoolId])).rows[0].name).toBe(body.schoolName);
  expect((await pool.query('SELECT roles FROM drivy.membership WHERE id=$1',[first.json().data.membershipId])).rows[0].roles).toEqual(['ADMIN']);
  expect((await call('GET',`/v1/school-openings/operations/${changed.operationId}`,undefined,'revisiting')).statusCode).toBe(404);
});

test('une opération de révocation est liée à un seul lien, y compris en concurrence',async()=>{
  const first=await issue(),second=await issue(),operation={operationId:randomUUID()};
  const revoked=await call('POST',`${base}/${first.link.id}/revoke`,operation);expect(revoked.statusCode,revoked.body).toBe(200);
  const replay=await call('POST',`${base}/${first.link.id}/revoke`,operation);expect(replay.json().data).toEqual(revoked.json().data);
  const mismatch=await call('POST',`${base}/${second.link.id}/revoke`,operation);expect(mismatch.statusCode).toBe(409);expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await pool.query('SELECT status FROM drivy.school_opening_link WHERE id=$1',[second.link.id])).rows[0].status).toBe('AVAILABLE');
  expect((await call('POST',`${base}/${first.link.id}/revoke`,{operationId:randomUUID()})).json().code).toBe('OPENING_LINK_REVOKED');
  const third=await issue(),fourth=await issue(),concurrentOperation={operationId:randomUUID()};
  const results=await Promise.all([third,fourth].map(link=>call('POST',`${base}/${link.link.id}/revoke`,concurrentOperation)));
  expect(results.map(result=>result.statusCode).sort()).toEqual([200,409]);
  expect(results.find(result=>result.statusCode===409)!.json().code).toBe('IDEMPOTENCY_MISMATCH');
});
test('expiration et révocation refusent toute création ; révoquer un lien utilisé ne détruit rien',async()=>{
  const expired=await issue();await pool.query("UPDATE drivy.school_opening_link SET created_at=now()-interval '9 days',expires_at=now()-interval '2 days' WHERE id=$1",[expired.link.id]);
  expect((await call('POST','/v1/school-openings',command(expired.token),'expired')).json().code).toBe('OPENING_LINK_EXPIRED');
  const revoked=await issue();const revokeBody={operationId:randomUUID()};expect((await call('POST',`${base}/${revoked.link.id}/revoke`,revokeBody)).statusCode).toBe(200);
  expect((await call('POST',`${base}/${revoked.link.id}/revoke`,revokeBody)).statusCode).toBe(200);
  expect((await call('POST','/v1/school-openings',command(revoked.token),'revoked')).json().code).toBe('OPENING_LINK_REVOKED');
  const used=await issue();await call('POST','/v1/school-openings',command(used.token),'used');expect((await call('POST',`${base}/${used.link.id}/revoke`,{operationId:randomUUID()})).json().code).toBe('OPENING_LINK_USED');
});
test('deux navigateurs et deux identités sur un lien : une seule école créée',async()=>{
  const {token}=await issue();const responses=await Promise.all(['one','two'].map(subject=>call('POST','/v1/school-openings',command(token),subject)));
  expect(responses.map(response=>response.statusCode).sort()).toEqual([201,409]);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.school_opening_link WHERE status='USED'")).rows[0].n).toBe(1);
});
test('deux clics du même compte : un reçu identique et un seul commit',async()=>{
  const {token}=await issue(),body=command(token);const responses=await Promise.all([call('POST','/v1/school-openings',body,'same'),call('POST','/v1/school-openings',body,'same')]);
  expect(responses.map(response=>response.statusCode)).toEqual([201,201]);expect(responses[0]!.json().data).toEqual(responses[1]!.json().data);
});
test('deux liens simultanés pour un compte neuf : une seule Person et deux adhésions isolées',async()=>{
  const links=await Promise.all([issue(),issue()]);const responses=await Promise.all(links.map(link=>call('POST','/v1/school-openings',command(link.token),'same-oidc')));
  expect(responses.map(response=>response.statusCode)).toEqual([201,201]);expect(responses[0]!.json().data.schoolId).not.toBe(responses[1]!.json().data.schoolId);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[issuer,'same-oidc'])).rows[0].n).toBe(1);
});
test('une erreur dans la transaction conserve le lien et ne crée aucune Person ou école',async()=>{
  const {token,link}=await issue();await pool.query("CREATE FUNCTION public.opening_test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.display_name='Rollback de recette' THEN RAISE EXCEPTION 'synthetic_failure'; END IF; RETURN NEW; END $$");
  await pool.query('CREATE TRIGGER opening_test_failure BEFORE INSERT ON drivy.person FOR EACH ROW EXECUTE FUNCTION public.opening_test_failure()');
  try{const response=await call('POST','/v1/school-openings',command(token,{displayName:'Rollback de recette'}),'rollback');expect(response.statusCode).toBe(503);
    expect((await pool.query('SELECT status FROM drivy.school_opening_link WHERE id=$1',[link.id])).rows[0].status).toBe('AVAILABLE');
    expect((await pool.query('SELECT 1 FROM drivy.identity_link WHERE subject=$1',['rollback'])).rowCount).toBe(0);
  }finally{await pool.query('DROP TRIGGER opening_test_failure ON drivy.person');await pool.query('DROP FUNCTION public.opening_test_failure()');}
});
test('le runtime ne crée pas d’école sans contexte de lien et ne contourne pas FORCE RLS',async()=>{
  const db=await pool.connect();try{await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
    const role=(await db.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0];expect(role).toEqual({rolsuper:false,rolbypassrls:false});
    await expect(db.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES($1,'Recette','DRAFT','test@example.invalid')",[randomUUID()])).rejects.toMatchObject({code:'42501'});
  }finally{await db.query('ROLLBACK');db.release();}
  expect((await pool.query("SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='drivy.school_opening_link'::regclass")).rows[0]).toEqual({relrowsecurity:true,relforcerowsecurity:true});
});
