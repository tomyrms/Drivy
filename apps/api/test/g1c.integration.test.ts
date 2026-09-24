import { readFile } from 'node:fs/promises';
import { createDecipheriv,randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { afterAll,beforeAll,beforeEach,describe,expect,it } from 'vitest';
import { Pool } from 'pg';
import { createLocalJWKSet,exportJWK,generateKeyPair,SignJWT } from 'jose';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
import { parse } from 'yaml';
import { buildApp } from '../src/app.js';
import { createTokenVerifier } from '../src/auth.js';
import { deliverOneInvitation,invitationMailConfig,type InvitationMailConfig } from '../src/invitation-mail.js';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id,seedFixtures } from '../scripts/fixtures.js';
const url=process.env.TEST_DATABASE_URL;
if(!url || new URL(url).pathname!=='/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool=new Pool({connectionString:url,max:10,connectionTimeoutMillis:5000,application_name:'drivy-g1c-tests'});
const issuer='https://identity.test.invalid';const path=`/v1/schools/${id.schoolA}/invitations`;
const mail:InvitationMailConfig={webURL:'http://127.0.0.1:3002/app/invitation',encryptionKey:'a1'.repeat(32),host:'127.0.0.1',
  port:Number(process.env.TEST_SMTP_PORT ?? 1025),secure:false,requireTLS:false,from:'drivy@example.invalid'};
const mailpit=process.env.TEST_MAILPIT_URL ?? 'http://127.0.0.1:8025';
let app:ReturnType<typeof buildApp>;let keys:Awaited<ReturnType<typeof generateKeyPair>>;
const validators=new Map<string,ReturnType<Ajv2020['compile']>>();
beforeAll(async()=>{
  await migrate(pool);keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
  app=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',invitationMail:mail,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'g1c',alg:'RS256'}]}))});
  const document=parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'g1c-contract',components:document.components});
  for(const name of ['InvitationEnvelope','InvitationPageEnvelope','MemberContextEnvelope','OperationResultEnvelope']) validators.set(name,ajv.compile({$ref:`g1c-contract#/components/schemas/${name}`}));
  validators.set('Preview',ajv.compile(JSON.parse(await readFile(new URL('../contracts/g1c-invitation-preview.json',import.meta.url),'utf8')) as object));
});
beforeEach(async()=>{
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);
  const policy=await call('PUT',`/v1/schools/${id.schoolA}/data-policy`,{operationId:randomUUID(),noticeText:'Notice synthétique F02.',retentionText:'Conservation limitée à la recette.',contactEmail:'privacy@example.invalid',reviewAcknowledged:true},1);
  expect(policy.statusCode,policy.body).toBe(200);
});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'POST'|'PUT',route:string,body?:Record<string,unknown>,version?:number,subject='demo-admin',claims:Record<string,unknown>={}) {
  const jwt=await new SignJWT(claims).setProtectedHeader({alg:'RS256',kid:'g1c'}).setSubject(subject).setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  return app.inject({method,url:route,headers:{authorization:`Bearer ${jwt}`,...(body?.operationId?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
}
function conforms(name:string,value:unknown) {const v=validators.get(name)!;expect(v(value),JSON.stringify(v.errors)).toBe(true);}
const verified=(email='new@example.invalid')=>({email,email_verified:true});
async function secret(invitationId:string) {
  const row=(await pool.query('SELECT id,payload FROM drivy.invitation_mail WHERE invitation_id=$1 ORDER BY invitation_version DESC LIMIT 1',[invitationId])).rows[0] as {id:string;payload:Buffer};
  const cipher=createDecipheriv('aes-256-gcm',Buffer.from(mail.encryptionKey,'hex'),row.payload.subarray(0,12));
  cipher.setAAD(Buffer.from(row.id));cipher.setAuthTag(row.payload.subarray(12,28));
  return (JSON.parse(Buffer.concat([cipher.update(row.payload.subarray(28)),cipher.final()]).toString('utf8')) as {token:string}).token;
}
async function invite(email='new@example.invalid',roles=['LEARNER'],subject='demo-admin') {
  const body={operationId:randomUUID(),email,roles};const response=await call('POST',path,body,undefined,subject);
  expect(response.statusCode,response.body).toBe(201);conforms('InvitationEnvelope',response.json());
  const dto=response.json().data as {id:string;version:number;status:string};return {...dto,token:await secret(dto.id),operationId:body.operationId};
}
async function accept(token:string,subject='new-person',email='new@example.invalid',operationId=randomUUID()) {
  return call('POST','/v1/invitations/accept',{operationId,token},undefined,subject,verified(email));
}
async function counts() {return (await pool.query(`SELECT (SELECT count(*)::int FROM drivy.person) persons,(SELECT count(*)::int FROM drivy.membership) members,
  (SELECT count(*)::int FROM drivy.learner_profile) learners,(SELECT count(*)::int FROM drivy.training) trainings,
  (SELECT count(*)::int FROM drivy.operation) operations,(SELECT count(*)::int FROM drivy.audit_event) audits`)).rows[0];}

describe('F02 · contrat et entrée explicite',()=>{
  it('T005 : preview sans effet puis identité, adhésion et élève atomiques sans formation',async()=>{
    const invitation=await invite();const before=await counts();
    const shown=await call('POST','/v1/invitations/preview',{token:invitation.token},undefined,'new-person',verified());
    expect(shown.statusCode,shown.body).toBe(200);expect(shown.json().data).toMatchObject({schoolId:id.schoolA,roles:['LEARNER'],notice:{version:2,noticeText:'Notice synthétique F02.'}});
    conforms('Preview',shown.json());
    expect(await counts()).toEqual(before);
    const response=await accept(invitation.token);expect(response.statusCode,response.body).toBe(201);conforms('MemberContextEnvelope',response.json());
    const after=await counts();expect(after).toEqual({...before,persons:before.persons+1,members:before.members+1,learners:before.learners+1,operations:before.operations+1,audits:before.audits+1});
    expect(response.json().data).toMatchObject({schoolId:id.schoolA,roles:['LEARNER'],grants:[],accessEpoch:1});
    expect((await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'CANCELLED',payload:null});
    const current=await call('GET','/v1/me',undefined,undefined,'new-person');expect(current.statusCode).toBe(200);
  });
  it.each([{email:'other@example.invalid',email_verified:true},{email:'new@example.invalid',email_verified:false},{email:'new@example.invalid',email_verified:'true'},{}])('T007 : adresse non correspondante ou non vérifiée ne consomme rien %j',async claims=>{
    const invitation=await invite();const before=await counts();
    for(const route of ['preview','accept']) {
      const body=route==='accept'?{token:invitation.token,operationId:randomUUID()}:{token:invitation.token};
      const result=await call('POST',`/v1/invitations/${route}`,body,undefined,'new-person',claims);
      expect(result.statusCode).toBe(403);expect(result.json().code).toBe('INVITATION_IDENTITY_MISMATCH');expect(result.body).not.toContain(id.schoolA);
    }
    expect(await counts()).toEqual(before);
  });
  it('ne fait confiance ni à un email de corps ni à un rôle JWT',async()=>{
    const invitation=await invite();const response=await call('POST','/v1/invitations/accept',{operationId:randomUUID(),token:invitation.token,email:'new@example.invalid'},undefined,'new-person');
    expect(response.statusCode).toBe(400);
    const created=await call('POST',path,{operationId:randomUUID(),email:'x@example.invalid',roles:['ADMIN']},undefined,'demo-alice',{roles:['ADMIN']});expect(created.statusCode).toBe(403);
  });
  it('T006 : acceptations concurrentes même opération restituent une seule preuve',async()=>{
    const invitation=await invite();const before=await counts();const operationId=randomUUID();
    const results=await Promise.all([accept(invitation.token,'new-person','new@example.invalid',operationId),accept(invitation.token,'new-person','new@example.invalid',operationId)]);
    expect(results.map(r=>r.statusCode)).toEqual([201,201]);expect(results[0]!.json().data).toEqual(results[1]!.json().data);
    expect((await counts()).operations).toBe(before.operations+1);
    expect((await pool.query("SELECT count(*)::int n FROM drivy.audit_event WHERE action='InvitationAccepted'")).rows[0].n).toBe(1);
    const shown=await call('POST','/v1/invitations/preview',{token:invitation.token},undefined,'new-person',verified());expect(shown.statusCode).toBe(200);
    const proof=await call('GET',`/v1/schools/${id.schoolA}/operations/${operationId}`,undefined,undefined,'new-person');expect(proof.statusCode).toBe(200);conforms('OperationResultEnvelope',proof.json());
    expect(proof.json().data).toMatchObject({commandType:'ACCEPT_INVITATION',resourceType:'Membership',resourceVersion:1});
  });
  it('après perte session, nouvelle opération même personne confirme sans recréer ; autre sub refusé',async()=>{
    const invitation=await invite();expect((await accept(invitation.token)).statusCode).toBe(201);const before=await counts();
    const again=await accept(invitation.token);expect(again.statusCode).toBe(201);expect((await counts()).members).toBe(before.members);
    expect((await pool.query("SELECT count(*)::int n FROM drivy.audit_event WHERE action='InvitationAccepted'")).rows[0].n).toBe(1);
    expect((await accept(invitation.token,'other-person')).json().code).toBe('INVITATION_USED');
    await pool.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1",[again.json().data.membershipId]);
    expect((await accept(invitation.token)).statusCode).toBe(403);
  });
  it('réutilise une personne déjà liée dans une autre école et son profil local existant',async()=>{
    const foreign=await invite('foreign@example.invalid');const before=await counts();
    const accepted=await accept(foreign.token,'demo-foreign','foreign@example.invalid');expect(accepted.statusCode,accepted.body).toBe(201);
    expect((await counts()).persons).toBe(before.persons);expect((await counts()).members).toBe(before.members+1);
    const existing=await invite('alice@example.invalid');const beforeExisting=await counts();
    expect((await accept(existing.token,'demo-alice','alice@example.invalid')).statusCode).toBe(201);
    expect((await counts()).members).toBe(beforeExisting.members);expect((await counts()).learners).toBe(beforeExisting.learners);
    const duplicate=await call('POST',path,{operationId:randomUUID(),email:'ALICE@example.invalid',roles:['LEARNER']});expect(duplicate.json().code).toBe('ALREADY_MEMBER');
  });
  it('une nouvelle invitation réactive seulement ses rôles et ne restaure pas les anciens grants',async()=>{
    await pool.query("UPDATE drivy.membership SET status='REVOKED',roles=ARRAY['ADMIN'],grants=ARRAY['CONFIGURE_CATALOG'] WHERE id=$1",[id.bobMember]);
    const invitation=await invite('bob@example.invalid');const response=await accept(invitation.token,'demo-bob','bob@example.invalid');
    expect(response.statusCode,response.body).toBe(201);expect(response.json().data).toMatchObject({membershipId:id.bobMember,roles:['LEARNER'],grants:[],accessEpoch:2});
  });
  it('deux subjects concurrents partageant un email ne fusionnent pas et un seul accepte',async()=>{
    const invitation=await invite();const before=await counts();const responses=await Promise.all([accept(invitation.token,'new-one'),accept(invitation.token,'new-two')]);
    expect(responses.map(r=>r.statusCode).sort()).toEqual([201,409]);expect(responses.find(r=>r.statusCode===409)!.json().code).toBe('INVITATION_USED');
    expect((await counts()).persons).toBe(before.persons+1);expect((await counts()).members).toBe(before.members+1);
  });
  it('une personne suspendue ne récupère pas des droits via invitation',async()=>{
    const invitation=await invite('bob@example.invalid');await pool.query("UPDATE drivy.person SET status='SUSPENDED' WHERE id=$1",[id.bob]);
    const before=await counts();expect((await accept(invitation.token,'demo-bob','bob@example.invalid')).statusCode).toBe(403);expect(await counts()).toEqual(before);
  });
  it('une invitation complémentaire conserve le dernier ADMIN actif, ses grants et son lien OIDC',async()=>{
    await pool.query("UPDATE drivy.membership SET grants=ARRAY['CONFIGURE_CATALOG'] WHERE id=$1",[id.adminMember]);
    const invitation=await invite('admin@example.invalid',['LEARNER']);const response=await accept(invitation.token,'demo-admin','admin@example.invalid');
    expect(response.statusCode,response.body).toBe(201);expect(response.json().data.roles).toEqual(['ADMIN','LEARNER']);expect(response.json().data.grants).toEqual(['CONFIGURE_CATALOG']);
    expect((await pool.query("SELECT count(*)::int n FROM drivy.membership WHERE school_id=$1 AND status='ACTIVE' AND 'ADMIN'=ANY(roles)",[id.schoolA])).rows[0].n).toBe(1);
    expect((await pool.query('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[issuer,'demo-admin'])).rows[0].person_id).toBe(id.admin);
  });
});

describe('F02 · droits, versions, concurrence et rollback',()=>{
  it('INSTRUCTOR : rôles LEARNER seulement, liste personnelle, aucun dossier implicite',async()=>{
    const own=await invite('new@example.invalid',['LEARNER'],'demo-instructor');await invite('second@example.invalid');
    const list=await call('GET',path,undefined,undefined,'demo-instructor');conforms('InvitationPageEnvelope',list.json());expect(list.json().data.items.map((i:{id:string})=>i.id)).toEqual([own.id]);
    const other=await call('GET',path,undefined,undefined,'demo-other-instructor');expect(other.json().data.items).toEqual([]);
    const forbiddenRole=await call('POST',path,{operationId:randomUUID(),email:'role@example.invalid',roles:['LEARNER','ADMIN']},undefined,'demo-instructor');expect(forbiddenRole.json().code).toBe('INVITATION_ROLE_FORBIDDEN');
    expect((await call('POST',`${path}/${own.id}/revoke`,{operationId:randomUUID(),reason:'Correction'},1,'demo-other-instructor')).statusCode).toBe(404);
    const before=await call('GET',`/v1/schools/${id.schoolA}/learners`,undefined,undefined,'demo-instructor');expect((await accept(own.token)).statusCode).toBe(201);
    const after=await call('GET',`/v1/schools/${id.schoolA}/learners`,undefined,undefined,'demo-instructor');expect(after.json().data.items).toEqual(before.json().data.items);
    const proof=await call('GET',`/v1/schools/${id.schoolA}/operations/${own.operationId}`,undefined,undefined,'demo-instructor');expect(proof.statusCode).toBe(200);
  });
  it('concurrence : deux émetteurs ne créent pas deux invitations pour la même adresse',async()=>{
    const responses=await Promise.all(['demo-instructor','demo-other-instructor'].map(subject=>call('POST',path,{operationId:randomUUID(),email:'duplicate@example.invalid',roles:['LEARNER']},undefined,subject)));
    expect(responses.map(r=>r.statusCode).sort()).toEqual([201,409]);expect(responses.find(r=>r.statusCode===409)!.json().code).toBe('INVITATION_ALREADY_PENDING');
    expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation_mail')).rows[0].n).toBe(1);
  });
  it('T008 : renvoi invalide immédiatement le jeton et l’outbox précédents',async()=>{
    const invitation=await invite();const resent=await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()},1);expect(resent.statusCode,resent.body).toBe(200);expect(resent.json().data.version).toBe(2);
    expect((await accept(invitation.token)).json().code).toBe('INVITATION_IDENTITY_MISMATCH');
    const rows=(await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1 ORDER BY invitation_version',[invitation.id])).rows;
    expect(rows[0]).toEqual({status:'CANCELLED',payload:null});expect(rows[1].status).toBe('QUEUED');
    expect((await accept(await secret(invitation.id))).statusCode).toBe(201);
  });
  it('révocation, expiration et If-Match ont des résultats distincts sans effet secondaire',async()=>{
    const invitation=await invite();const before=await counts();
    expect((await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()})).statusCode).toBe(428);
    expect((await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()},9)).statusCode).toBe(412);
    await pool.query("UPDATE drivy.invitation SET expires_at=now()-interval '1 second' WHERE id=$1",[invitation.id]);
    expect((await accept(invitation.token)).statusCode).toBe(410);expect(await counts()).toEqual(before);
    const revoked=await call('POST',`${path}/${invitation.id}/revoke`,{operationId:randomUUID(),reason:'Lien inutilisé'},1);expect(revoked.statusCode).toBe(200);expect(revoked.json().data.status).toBe('REVOKED');
    expect((await accept(invitation.token)).json().code).toBe('INVITATION_REVOKED');
    expect((await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()},2)).json().code).toBe('INVITATION_REVOKED');
  });
  it('replay de création, pagination opaque, filtrage refusé et preuve isolée',async()=>{
    const body={operationId:randomUUID(),email:'replay@example.invalid',roles:['LEARNER']};
    const first=await call('POST',path,body);const second=await call('POST',path,body);expect(first.statusCode).toBe(201);expect(second.json().data).toEqual(first.json().data);
    const mismatch=await call('POST',path,{...body,email:'different@example.invalid'});expect(mismatch.json().code).toBe('IDEMPOTENCY_MISMATCH');
    await invite();const page=await call('GET',`${path}?limit=1`);expect(page.json().data.nextCursor).toBeTypeOf('string');
    const next=await call('GET',`${path}?limit=1&cursor=${encodeURIComponent(page.json().data.nextCursor)}`);expect(next.json().data.items[0].id).not.toBe(page.json().data.items[0].id);
    expect((await call('GET',`${path}?status=PENDING`)).statusCode).toBe(400);
    expect((await call('GET',`/v1/schools/${id.schoolA}/operations/${body.operationId}`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
    const proof=await call('GET',`/v1/schools/${id.schoolA}/operations/${body.operationId}`);conforms('OperationResultEnvelope',proof.json());expect(proof.json().data).toMatchObject({commandType:'CREATE_INVITATION',resourceType:'Invitation',resourceVersion:1});
  });
  it('revérifie les droits de l’émetteur après attente sur le verrou école',async()=>{
    const invitation=await invite('new@example.invalid',['LEARNER'],'demo-instructor');const before=await counts();const blocker=await pool.connect();
    await blocker.query('BEGIN');await blocker.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);
    const pending=accept(invitation.token);try {
      const deadline=Date.now()+4000;let waiting=false;while(Date.now()<deadline) {
        waiting=Boolean((await pool.query("SELECT 1 FROM pg_stat_activity WHERE application_name='drivy-g1c-tests' AND wait_event_type='Lock' AND query LIKE '%FROM drivy.school WHERE id=$1 FOR UPDATE%'")).rowCount);
        if(waiting) break;await delay(10);
      }
      expect(waiting).toBe(true);await blocker.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1",[id.instructorMember]);await blocker.query('COMMIT');
    } finally {await blocker.query('ROLLBACK');blocker.release();}
    const response=await pending;expect(response.json().code).toBe('INVITATION_REVOKED');expect(await counts()).toEqual(before);
  });
  it.each(['new-person','demo-admin'])('revérifie le secret après rotation pendant le verrou, même pour un destinataire ADMIN : %s',async subject=>{
    const invitation=await invite();const before=await counts();const blocker=await pool.connect();
    await blocker.query('BEGIN');await blocker.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);const pending=accept(invitation.token,subject);
    try {
      const deadline=Date.now()+4000;let waiting=false;while(Date.now()<deadline) {
        waiting=Boolean((await pool.query("SELECT 1 FROM pg_stat_activity WHERE application_name='drivy-g1c-tests' AND wait_event_type='Lock' AND query LIKE '%FROM drivy.school WHERE id=$1 FOR UPDATE%'")).rowCount);
        if(waiting) break;await delay(10);
      }
      expect(waiting).toBe(true);await blocker.query('UPDATE drivy.invitation SET token_hash=$2,version=version+1 WHERE id=$1',[invitation.id,'b1'.repeat(32)]);await blocker.query('COMMIT');
    } finally {await blocker.query('ROLLBACK');blocker.release();}
    const response=await pending;expect(response.statusCode).toBe(403);expect(response.json().code).toBe('INVITATION_IDENTITY_MISMATCH');expect(await counts()).toEqual(before);
  });
  it('une panne d’audit annule identité, profil, consommation et preuve',async()=>{
    const invitation=await invite();const before=await counts();
    await pool.query("CREATE FUNCTION drivy.fail_accept_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='InvitationAccepted' THEN RAISE EXCEPTION 'failure_test'; END IF;RETURN NEW;END $$");
    await pool.query('CREATE TRIGGER fail_accept_audit BEFORE INSERT ON drivy.audit_event FOR EACH ROW EXECUTE FUNCTION drivy.fail_accept_audit()');
    try {expect((await accept(invitation.token)).statusCode).toBe(503);expect(await counts()).toEqual(before);
      expect((await pool.query('SELECT status FROM drivy.invitation WHERE id=$1',[invitation.id])).rows[0].status).toBe('PENDING');
    } finally {await pool.query('DROP TRIGGER fail_accept_audit ON drivy.audit_event');await pool.query('DROP FUNCTION drivy.fail_accept_audit()');}
    expect((await accept(invitation.token)).statusCode).toBe(201);
  });
  it('une école DRAFT ou archivée ne permet ni création ni acceptation',async()=>{
    const invitation=await invite();for(const status of ['DRAFT','ARCHIVED']) {
      await pool.query('UPDATE drivy.school SET status=$2 WHERE id=$1',[id.schoolA,status]);
      expect((await accept(invitation.token)).json().code).toBe('SCHOOL_NOT_ACTIVE');
      expect([409]).toContain((await call('POST',path,{operationId:randomUUID(),email:'x@example.invalid',roles:['LEARNER']})).statusCode);
    }
  });
  it('la perte du rôle ADMIN invalide une invitation de personnel',async()=>{
    const invitation=await invite('new@example.invalid',['ADMIN']);await pool.query("UPDATE drivy.membership SET roles=ARRAY['INSTRUCTOR'],access_epoch=access_epoch+1 WHERE id=$1",[id.adminMember]);
    expect((await accept(invitation.token)).json().code).toBe('INVITATION_ROLE_FORBIDDEN');
    expect((await call('GET',path)).json().data.items).toEqual([]);
    await deliverOneInvitation(pool,mail);expect((await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'CANCELLED',payload:null});
  });
  it('les politiques SQL isolent auteur, destinataire et worker sans droit de mutation métier',async()=>{
    await invite('first@example.invalid',['LEARNER'],'demo-instructor');await invite('second@example.invalid');
    const db=await pool.connect();try {
      await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.person_id',$1,true),set_config('app.school_id',$2,true)",[id.instructor,id.schoolA]);
      expect((await db.query('SELECT id FROM drivy.invitation')).rowCount).toBe(1);expect((await db.query('SELECT id FROM drivy.invitation_mail')).rowCount).toBe(1);
      await db.query('ROLLBACK');await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_invitation_mailer');
      expect((await db.query('SELECT id FROM drivy.invitation_mail')).rowCount).toBe(2);
      await expect(db.query("UPDATE drivy.membership SET roles=ARRAY['ADMIN'] WHERE id=$1",[id.instructorMember])).rejects.toMatchObject({code:'42501'});
      await db.query('ROLLBACK');await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.person_id',$1,true)",[randomUUID()]);
      await expect(db.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)',[randomUUID(),'Sans invitation'])).rejects.toMatchObject({code:'42501'});
    } finally {await db.query('ROLLBACK');db.release();}
  });
});

describe('F02 · SMTP réel et secrets transitoires',()=>{
  it('Mailpit accepte le message et le payload chiffré est effacé après acceptation SMTP',async()=>{
    const invitation=await invite();const row=(await pool.query('SELECT payload,token_hash FROM drivy.invitation_mail o JOIN drivy.invitation i ON i.id=o.invitation_id WHERE i.id=$1',[invitation.id])).rows[0];
    expect(row.payload.toString('utf8')).not.toContain(invitation.token);expect(row.payload.toString('utf8')).not.toContain('new@example.invalid');expect(row.token_hash).not.toBe(invitation.token);
    expect(await deliverOneInvitation(pool,mail)).toBe(true);
    const state=(await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0];expect(state).toEqual({status:'SENT',payload:null});
    const listed=await fetch(`${mailpit}/api/v1/messages`);expect(listed.ok).toBe(true);const messages=await listed.json() as {messages:{ID:string;MessageID:string}[]};
    const outbox=(await pool.query('SELECT id FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0];
    const sent=messages.messages.find(m=>m.MessageID.includes(outbox.id));expect(sent).toBeDefined();
    const content=await (await fetch(`${mailpit}/api/v1/message/${sent!.ID}`)).json() as {Text:string};
    expect(content.Text).toContain(`/app/invitation#token=${invitation.token}`);expect(content.Text).toContain('choisir explicitement');
    expect(await deliverOneInvitation(pool,mail)).toBe(false);
  });
  it('un émetteur révoqué annule le mail avant SMTP et purge le secret',async()=>{
    const invitation=await invite('new@example.invalid',['LEARNER'],'demo-instructor');await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
    expect(await deliverOneInvitation(pool,mail)).toBe(true);expect((await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'CANCELLED',payload:null});
  });
  it('la corruption du payload échoue sans contenu en clair ni faux état SENT',async()=>{
    const invitation=await invite();await pool.query("UPDATE drivy.invitation_mail SET payload=decode('abcd','hex') WHERE invitation_id=$1",[invitation.id]);
    await deliverOneInvitation(pool,mail);expect((await pool.query('SELECT status,failure_code FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'FAILED',failure_code:'PAYLOAD_INVALID'});
  });
  it('échec SMTP reste rejouable ; expiration purge aussi ce payload sans envoi',async()=>{
    const invitation=await invite();await deliverOneInvitation(pool,{...mail,port:1});
    expect((await pool.query('SELECT status,failure_code,payload IS NOT NULL AS retained FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'QUEUED',failure_code:'SMTP_FAILED',retained:true});
    await pool.query("UPDATE drivy.invitation SET expires_at=now()-interval '1 second' WHERE id=$1",[invitation.id]);await deliverOneInvitation(pool,mail);
    expect((await pool.query('SELECT status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'CANCELLED',payload:null});
  });
  it('deux workers concurrents ne réclament pas le même message',async()=>{
    const invitation=await invite();const delivered=await Promise.all([deliverOneInvitation(pool,mail),deliverOneInvitation(pool,mail)]);
    expect(delivered.filter(Boolean)).toHaveLength(1);expect((await pool.query('SELECT status,attempts FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0]).toEqual({status:'SENT',attempts:1});
  });
  it('l’absence de transport refuse la création sans écrire une invitation',async()=>{
    const plain=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',verifyToken:async()=>({issuer,subject:'demo-admin'})});
    try {const operationId=randomUUID();const response=await plain.inject({method:'POST',url:path,headers:{'idempotency-key':operationId},payload:{operationId,email:'x@example.invalid',roles:['LEARNER']}});
      expect(response.statusCode).toBe(503);expect(response.json().code).toBe('INVITATION_DELIVERY_UNAVAILABLE');expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation')).rows[0].n).toBe(0);
    } finally {await plain.close();}
  });
  it('refuse un lien HTTP distant et exige TLS en production',()=>{
    const env={NODE_ENV:'production',INVITATION_WEB_URL:'http://example.invalid/app/invitation',INVITATION_OUTBOX_KEY:mail.encryptionKey,SMTP_HOST:'127.0.0.1',SMTP_FROM:mail.from};
    expect(()=>invitationMailConfig(env)).toThrow();expect(invitationMailConfig({...env,INVITATION_WEB_URL:'https://example.invalid/app/invitation'})?.requireTLS).toBe(true);
  });
});
