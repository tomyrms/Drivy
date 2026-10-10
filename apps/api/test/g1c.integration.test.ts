import { readFile } from 'node:fs/promises';
import { createDecipheriv,createHash,randomUUID } from 'node:crypto';
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
import { invitationCodeHasher } from '../src/invitation-code.js';
import { migrate } from '../scripts/migrations.js';
import { fixtureIds as id,seedFixtures } from '../scripts/fixtures.js';
const url=process.env.TEST_DATABASE_URL;
if(!url || new URL(url).pathname!=='/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool=new Pool({connectionString:url,max:10,connectionTimeoutMillis:5000,application_name:'drivy-g1c-tests'});
const cursorSecret='secret-test-32-caracteres-minimum';const issuer='https://identity.test.invalid';const path=`/v1/schools/${id.schoolA}/invitations`;
const mail:InvitationMailConfig={webURL:'http://127.0.0.1:3002/app/invitation',encryptionKey:'a1'.repeat(32),host:'127.0.0.1',
  port:Number(process.env.TEST_SMTP_PORT ?? 1025),secure:false,requireTLS:false,from:'drivy@example.invalid'};
const mailpit=process.env.TEST_MAILPIT_URL ?? 'http://127.0.0.1:8025';
let app:ReturnType<typeof buildApp>;let keys:Awaited<ReturnType<typeof generateKeyPair>>;
const validators=new Map<string,ReturnType<Ajv2020['compile']>>();
beforeAll(async()=>{
  await migrate(pool);keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
  app=buildApp({pool,cursorSecret,invitationMail:mail,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'g1c',alg:'RS256'}]}))});
  const document=parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'g1c-contract',components:document.components});
  for(const name of ['MemberContextEnvelope','OperationResultEnvelope']) validators.set(name,ajv.compile({$ref:`g1c-contract#/components/schemas/${name}`}));
  // Le schéma canonique Invitation (3.11.0, inchangé) est fermé : delivery, code et maskedEmail nul relèvent de l'extension du 28 septembre 2026.
  const delivery=JSON.parse(await readFile(new URL('../contracts/invitation-delivery.json',import.meta.url),'utf8')) as {$id:string};ajv.addSchema(delivery);
  validators.set('InvitationEnvelope',ajv.compile({$ref:`${delivery.$id}#/$defs/Envelope`}));validators.set('InvitationPageEnvelope',ajv.compile({$ref:`${delivery.$id}#/$defs/PageEnvelope`}));
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
  it('une invitation élève avec formation ouvre la formation et affecte le moniteur à l’acceptation',async()=>{
    const policy=randomUUID(),curriculum=randomUUID();
    await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette','Recette','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
    await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
    await pool.query('UPDATE drivy.offering_version SET curriculum_version_id=$2,policy_version_id=$3,default_duration_minutes=50,default_price_cents=9000,enabled=true WHERE id=$1',[id.offeringA,curriculum,policy]);
    const training={offeringId:id.offeringA,instructorMembershipId:id.instructorMember};
    // Un moniteur ne s'affecte que lui-même ; seul le rôle Élève porte une formation.
    expect((await call('POST',path,{operationId:randomUUID(),email:'other@example.invalid',roles:['LEARNER'],training:{...training,instructorMembershipId:id.otherInstructorMember}},undefined,'demo-instructor')).json().code).toBe('INVITATION_TRAINING_INVALID');
    expect((await call('POST',path,{operationId:randomUUID(),email:'staff@example.invalid',roles:['INSTRUCTOR'],training})).json().code).toBe('INVITATION_TRAINING_INVALID');
    expect((await call('POST',path,{operationId:randomUUID(),email:'closed@example.invalid',roles:['LEARNER'],training:{...training,offeringId:randomUUID()}})).json().code).toBe('INVITATION_TRAINING_INVALID');
    const created=await call('POST',path,{operationId:randomUUID(),email:'new@example.invalid',roles:['LEARNER'],training},undefined,'demo-instructor');
    expect(created.statusCode,created.body).toBe(201);conforms('InvitationEnvelope',created.json());
    const token=await secret(created.json().data.id);
    const accepted=await accept(token);expect(accepted.statusCode,accepted.body).toBe(201);
    const opened=async()=>(await pool.query(`SELECT t.status,t.offering_id,a.instructor_membership_id FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id
      JOIN drivy.instructor_assignment a ON a.training_id=t.id WHERE l.contact_email='new@example.invalid'`)).rows;
    expect(await opened()).toEqual([{status:'ACTIVE',offering_id:id.offeringA,instructor_membership_id:id.instructorMember}]);
    // Le moniteur voit aussitôt son nouvel élève ; rejouer l'acceptation ne crée pas de seconde formation.
    const learners=await call('GET',`/v1/schools/${id.schoolA}/learners`,undefined,undefined,'demo-instructor');
    expect(learners.json().data.items.some((l:{contactEmail:string|null})=>l.contactEmail==='new@example.invalid')).toBe(true);
    await accept(token);expect(await opened()).toHaveLength(1);
    // La politique SQL refuse toute autre formation à la personne invitée.
    const db=await pool.connect();
    try{
      await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
      const person=(await pool.query("SELECT person_id,id FROM drivy.learner_profile WHERE contact_email='new@example.invalid'")).rows[0];
      await db.query("SELECT set_config('app.person_id',$1,true),set_config('app.school_id',$2,true)",[person.person_id,id.schoolA]);
      const key=(await pool.query('SELECT offering_key FROM drivy.offering_version WHERE id=$1',[id.offeringA])).rows[0].offering_key;
      await expect(db.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status) VALUES(gen_random_uuid(),$1,$2,$3,$4,'ACTIVE')",[id.schoolA,id.aliceLearner,id.offeringA,key])).rejects.toThrow();
    }finally{await db.query('ROLLBACK');db.release();}
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
  it('l’absence de transport refuse la création par e-mail par un 409 définitif, sans rien écrire ni retenir',async()=>{
    const plain=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',verifyToken:async()=>({issuer,subject:'demo-admin'})});
    try {const operationId=randomUUID();const send=()=>plain.inject({method:'POST',url:path,headers:{'idempotency-key':operationId},payload:{operationId,email:'x@example.invalid',roles:['LEARNER']}});
      // Un 5xx serait une incertitude pour les clients (verrou des écritures de l'école) : le refus est un 409, sans effet.
      for(const attempt of [1,2]) {const response=await send();expect(response.statusCode,`essai ${attempt}`).toBe(409);expect(response.json().code).toBe('INVITATION_DELIVERY_UNAVAILABLE');}
      expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation')).rows[0].n).toBe(0);
      expect((await pool.query('SELECT count(*)::int n FROM drivy.operation WHERE operation_id=$1',[operationId])).rows[0].n).toBe(0);
    } finally {await plain.close();}
  });
  it('refuse un lien HTTP distant et exige TLS en production',()=>{
    const env={NODE_ENV:'production',INVITATION_WEB_URL:'http://example.invalid/app/invitation',INVITATION_OUTBOX_KEY:mail.encryptionKey,SMTP_HOST:'127.0.0.1',SMTP_FROM:mail.from};
    expect(()=>invitationMailConfig(env)).toThrow();expect(invitationMailConfig({...env,INVITATION_WEB_URL:'https://example.invalid/app/invitation'})?.requireTLS).toBe(true);
  });
  it('sans transport : les options l’annoncent, le renvoi par e-mail est refusé en 409 et le code reste possible',async()=>{
    const invitation=await invite('resend@example.invalid');
    const plain=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',verifyToken:async()=>({issuer,subject:'demo-admin'})});
    try {
      const options=`/v1/schools/${id.schoolA}/invitation-options`;
      expect((await call('GET',options)).json().data).toEqual({emailInvitationsAvailable:true,codeInvitationsAvailable:true});
      expect((await call('GET',options,undefined,undefined,'demo-instructor')).statusCode).toBe(200);
      expect((await call('GET',options,undefined,undefined,'demo-alice')).statusCode).toBe(403);
      const noTransport=await plain.inject({method:'GET',url:options});expect(noTransport.statusCode).toBe(200);
      expect(noTransport.json().data).toEqual({emailInvitationsAvailable:false,codeInvitationsAvailable:true});
      const operationId=randomUUID();
      const resend=await plain.inject({method:'POST',url:`${path}/${invitation.id}/resend`,headers:{'idempotency-key':operationId,'if-match':'"1"'},payload:{operationId}});
      expect(resend.statusCode).toBe(409);expect(resend.json().code).toBe('INVITATION_DELIVERY_UNAVAILABLE');
      // Rien n'a bougé : version inchangée, message en attente non annulé.
      expect((await pool.query('SELECT version FROM drivy.invitation WHERE id=$1',[invitation.id])).rows[0].version).toBe(1);
      expect((await pool.query('SELECT status FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0].status).toBe('QUEUED');
    } finally {await plain.close();}
  });
});

describe('Invitation par code · sans e-mail',()=>{
  let subjects=0;const fresh=()=>`code-user-${subjects++}`;
  const trainingFor=(instructorMembershipId:string=id.instructorMember)=>({offeringId:id.offeringA,instructorMembershipId});
  async function prepareOffering() {
    const policy=randomUUID(),curriculum=randomUUID();
    await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette','Recette','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
    await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
    await pool.query('UPDATE drivy.offering_version SET curriculum_version_id=$2,policy_version_id=$3,default_duration_minutes=50,default_price_cents=9000,enabled=true WHERE id=$1',[id.offeringA,curriculum,policy]);
  }
  beforeEach(prepareOffering);
  const create=(subject='demo-instructor',extra:Record<string,unknown>={})=>{const body={operationId:randomUUID(),delivery:'CODE',roles:['LEARNER'],training:trainingFor(),...extra};return call('POST',path,body,undefined,subject).then(response=>({response,body}));};
  async function issue(subject='demo-instructor') {
    const {response,body}=await create(subject);expect(response.statusCode,response.body).toBe(201);
    return {...(response.json().data as {id:string;version:number;code:string}),operationId:body.operationId};
  }
  const preview=(code:string,subject=fresh(),claims:Record<string,unknown>={})=>call('POST','/v1/invitations/code/preview',{code},undefined,subject,claims);
  const acceptCode=(code:string,subject=fresh(),operationId=randomUUID(),claims:Record<string,unknown>={})=>call('POST','/v1/invitations/code/accept',{operationId,code},undefined,subject,claims);
  const personOf=async(subject:string)=>(await pool.query('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[issuer,subject])).rows[0]?.person_id as string|undefined;
  const trainingsOf=async(subject:string)=>(await pool.query(`SELECT t.status,t.offering_id,a.instructor_membership_id FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id
    JOIN drivy.instructor_assignment a ON a.training_id=t.id WHERE l.person_id=$1 ORDER BY t.created_at`,[await personOf(subject)])).rows;
  const wrong=(n:number)=>Array.from({length:n},(_,i)=>`AAA${i}-BBB${i}`);

  it('création par le moniteur : formation portée, code présent une seule fois, aucun e-mail ni secret conservé',async()=>{
    const before=await counts();
    const {response,body}=await create();expect(response.statusCode,response.body).toBe(201);conforms('InvitationEnvelope',response.json());
    const data=response.json().data;expect(data).toMatchObject({schoolId:id.schoolA,version:1,maskedEmail:null,roles:['LEARNER'],status:'PENDING',delivery:'CODE'});
    expect(data.code).toMatch(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$/);
    expect(response.headers.etag).toBe('"1"');expect(Date.parse(data.expiresAt)-Date.now()).toBeGreaterThan(6.9*86_400_000);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation_mail')).rows[0].n).toBe(0);
    const stored=(await pool.query('SELECT email,delivery,token_hash,roles,training_offering_id,training_instructor_membership_id FROM drivy.invitation WHERE id=$1',[data.id])).rows[0];
    expect(stored).toMatchObject({email:null,delivery:'CODE',roles:['LEARNER'],training_offering_id:id.offeringA,training_instructor_membership_id:id.instructorMember});
    // Empreinte à clé serveur (HMAC dérivé du secret de curseur), jamais le SHA-256 du code : une base copiée ne permet pas de le deviner.
    expect(stored.token_hash).toBe(invitationCodeHasher(cursorSecret)(data.code));
    expect(stored.token_hash).not.toBe(createHash('sha256').update(data.code.replace('-','')).digest('hex'));
    expect(stored.token_hash).not.toBe(createHash('sha256').update(data.code).digest('hex'));
    // Ni le code ni sa forme normalisée ne sont écrits ailleurs (opération, audit).
    const operation=JSON.stringify((await pool.query('SELECT * FROM drivy.operation WHERE operation_id=$1',[body.operationId])).rows);
    expect(operation).not.toContain(data.code);expect(operation).not.toContain(data.code.replace('-',''));expect(operation).not.toContain('"code"');
    expect(await counts()).toEqual({...before,operations:before.operations+1,audits:before.audits+1});
    // Rejeu idempotent : même invitation, sans code (le client propose « Nouveau code »).
    const replay=await call('POST',path,body,undefined,'demo-instructor');expect(replay.statusCode).toBe(201);conforms('InvitationEnvelope',replay.json());
    expect(replay.json().data).toEqual({...data,code:undefined});expect('code' in replay.json().data).toBe(false);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation')).rows[0].n).toBe(1);
    // Les listes ne contiennent jamais le code.
    const list=await call('GET',path,undefined,undefined,'demo-instructor');conforms('InvitationPageEnvelope',list.json());
    expect(list.json().data.items).toHaveLength(1);expect(list.json().data.items[0]).toMatchObject({delivery:'CODE',maskedEmail:null});expect(list.body).not.toContain(data.code);
    expect((await call('GET',path)).body).not.toContain(data.code);
  });
  it('la clé des codes appartient au serveur : un autre secret ne retrouve pas un code, le secret dédié l’emporte sur le secret de curseur',async()=>{
    const invitation=await issue();const dedicatedSecret='secret-dedie-aux-codes-de-test-32-caracteres';
    const instructor=async()=>({issuer,subject:'demo-instructor'});
    const dedicated=buildApp({pool,cursorSecret,invitationCodeSecret:dedicatedSecret,verifyToken:instructor});
    const otherCursor=buildApp({pool,cursorSecret:'un-autre-secret-de-curseur-de-32-caracteres',verifyToken:instructor});
    const previewOn=(server:ReturnType<typeof buildApp>,code:string)=>server.inject({method:'POST',url:'/v1/invitations/code/preview',payload:{code}});
    try {
      for(const server of [dedicated,otherCursor]) {const response=await previewOn(server,invitation.code);expect(response.statusCode).toBe(404);expect(response.json().code).toBe('INVITATION_CODE_INVALID');}
      const operationId=randomUUID();
      const created=await dedicated.inject({method:'POST',url:path,headers:{'idempotency-key':operationId},payload:{operationId,delivery:'CODE',roles:['LEARNER'],training:trainingFor()}});
      expect(created.statusCode,created.body).toBe(201);const {id:createdId,code}=created.json().data as {id:string;code:string};
      expect((await pool.query('SELECT token_hash FROM drivy.invitation WHERE id=$1',[createdId])).rows[0].token_hash).toBe(invitationCodeHasher(cursorSecret,dedicatedSecret)(code));
      expect((await previewOn(dedicated,code)).statusCode).toBe(200);
      // Le serveur principal (secret de curseur seul) ne reconnaît pas ce code, et inversement.
      expect((await preview(code)).statusCode).toBe(404);
      expect((await previewOn(otherCursor,code)).statusCode).toBe(404);
      expect((await preview(invitation.code)).statusCode).toBe(200);
    } finally {await dedicated.close();await otherCursor.close();}
  });
  it('les invitations par e-mail gardent leur forme et annoncent delivery EMAIL',async()=>{
    const invitation=await invite('mail@example.invalid');const listed=await call('GET',path);
    expect(listed.json().data.items.find((i:{id:string})=>i.id===invitation.id)).toMatchObject({delivery:'EMAIL',maskedEmail:'m***@example.invalid'});
    expect('code' in listed.json().data.items[0]).toBe(false);
    const explicit=await call('POST',path,{operationId:randomUUID(),delivery:'EMAIL',email:'explicit@example.invalid',roles:['LEARNER']});expect(explicit.statusCode,explicit.body).toBe(201);conforms('InvitationEnvelope',explicit.json());
  });
  it('création sans transport SMTP : le code n’en a pas besoin',async()=>{
    const plain=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',verifyToken:async()=>({issuer,subject:'demo-instructor'})});
    try {const operationId=randomUUID();
      const response=await plain.inject({method:'POST',url:path,headers:{'idempotency-key':operationId},payload:{operationId,delivery:'CODE',roles:['LEARNER'],training:trainingFor()}});
      expect(response.statusCode,response.body).toBe(201);expect(response.json().data.code).toBeTypeOf('string');
    } finally {await plain.close();}
  });
  it('mêmes règles que la formation portée : moniteur lui-même, administrateur pour tout moniteur actif, offre ouverte, jamais un élève',async()=>{
    expect((await create('demo-instructor',{training:trainingFor(id.otherInstructorMember)})).response.json().code).toBe('INVITATION_TRAINING_INVALID');
    expect((await create('demo-instructor',{training:{...trainingFor(),offeringId:randomUUID()}})).response.json().code).toBe('INVITATION_TRAINING_INVALID');
    expect((await create('demo-admin',{training:trainingFor(id.aliceMember)})).response.json().code).toBe('INVITATION_TRAINING_INVALID');
    const byAdmin=await create('demo-admin',{training:trainingFor(id.otherInstructorMember)});expect(byAdmin.response.statusCode,byAdmin.response.body).toBe(201);
    expect((await create('demo-alice')).response.statusCode).toBe(403);
    // Formes incohérentes : refus de validation avant tout effet.
    for(const extra of [{email:'x@example.invalid'},{roles:['ADMIN']},{roles:['LEARNER','INSTRUCTOR']},{training:undefined}]) {
      const {response}=await create('demo-admin',extra);expect(response.statusCode,JSON.stringify(extra)).toBe(400);expect(response.json().code).toBe('INVALID_REQUEST');
    }
    expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation')).rows[0].n).toBe(1);
    // L'e-mail sans adresse n'existe pas non plus.
    expect((await call('POST',path,{operationId:randomUUID(),roles:['LEARNER']})).statusCode).toBe(400);
  });
  it('aperçu : toute identité connectée, même sans compte ni adresse vérifiée ; rien n’est créé',async()=>{
    const invitation=await issue();const before=await counts();const subject=fresh();
    const shown=await preview(invitation.code,subject);expect(shown.statusCode,shown.body).toBe(200);
    expect(Object.keys(shown.json().data).sort()).toEqual(['expiresAt','roles','schoolName','trainingCategoryCode','trainingCategoryCodes']);
    expect(shown.json().data).toMatchObject({schoolName:'Auto-école Horizon · Démonstration',roles:['LEARNER'],trainingCategoryCode:'B'});
    expect(Date.parse(shown.json().data.expiresAt)).toBeGreaterThan(Date.now());
    // Saisie tolérante : minuscules, sans tiret, espaces.
    for(const typed of [invitation.code.toLowerCase(),invitation.code.replace('-',''),` ${invitation.code.slice(0,4)} ${invitation.code.slice(5)} `]) expect((await preview(typed,subject)).statusCode).toBe(200);
    expect(await counts()).toEqual(before);expect(await personOf(subject)).toBeUndefined();
    const anonymous=await app.inject({method:'POST',url:'/v1/invitations/code/preview',payload:{code:invitation.code}});expect(anonymous.statusCode).toBe(401);
    expect((await call('POST','/v1/invitations/code/preview',{code:invitation.code,extra:1},undefined,subject)).statusCode).toBe(400);
  });
  it('code inconnu, expiré, révoqué, école inactive ou émetteur sans droit : la même réponse 404 partout',async()=>{
    const unknown=await preview('ABCD-EFGH');expect(unknown.statusCode).toBe(404);expect(unknown.json().code).toBe('INVITATION_CODE_INVALID');
    const reference=unknown.body.replace(/"requestId":"[^"]+"/,'');
    const expired=await issue();await pool.query("UPDATE drivy.invitation SET expires_at=now()-interval '1 second' WHERE id=$1",[expired.id]);
    const revoked=await issue();expect((await call('POST',`${path}/${revoked.id}/revoke`,{operationId:randomUUID(),reason:'Erreur de saisie'},1,'demo-instructor')).statusCode).toBe(200);
    const orphan=await issue();await pool.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1",[id.instructorMember]);
    for(const code of [expired.code,revoked.code,orphan.code]) for(const use of [preview,acceptCode]) {
      const response=await use(code);expect(response.statusCode).toBe(404);expect(response.json().code).toBe('INVITATION_CODE_INVALID');
      expect(response.body.replace(/"requestId":"[^"]+"/,'')).toBe(reference);
    }
    await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.instructorMember]);
    const live=await issue();await pool.query("UPDATE drivy.school SET status='DRAFT' WHERE id=$1",[id.schoolA]);
    for(const use of [preview,acceptCode]) expect((await use(live.code)).json().code).toBe('INVITATION_CODE_INVALID');
    expect(await counts()).toMatchObject({persons:6,members:7,learners:3});
  });
  it('acceptation sans adresse vérifiée : personne, adhésion, dossier, formation et affectation, atomiquement',async()=>{
    const invitation=await issue();const before=await counts();const subject=fresh();
    const response=await acceptCode(invitation.code,subject);expect(response.statusCode,response.body).toBe(201);conforms('MemberContextEnvelope',response.json());
    expect(response.json().data).toMatchObject({schoolId:id.schoolA,roles:['LEARNER'],grants:[],accessEpoch:1});expect('trainingOpened' in response.json().data).toBe(false);
    expect(await counts()).toEqual({...before,persons:before.persons+1,members:before.members+1,learners:before.learners+1,trainings:before.trainings+1,operations:before.operations+1,audits:before.audits+1});
    const person=(await personOf(subject))!;
    expect((await pool.query('SELECT invitation_email,roles FROM drivy.membership WHERE school_id=$1 AND person_id=$2',[id.schoolA,person])).rows[0]).toEqual({invitation_email:null,roles:['LEARNER']});
    expect((await pool.query('SELECT contact_email,profile_readiness FROM drivy.learner_profile WHERE person_id=$1',[person])).rows[0]).toEqual({contact_email:null,profile_readiness:'MINIMAL'});
    expect(await trainingsOf(subject)).toEqual([{status:'ACTIVE',offering_id:id.offeringA,instructor_membership_id:id.instructorMember}]);
    expect((await pool.query('SELECT status,accepted_by_person_id FROM drivy.invitation WHERE id=$1',[invitation.id])).rows[0]).toEqual({status:'ACCEPTED',accepted_by_person_id:person});
    expect((await call('GET','/v1/me',undefined,undefined,subject)).statusCode).toBe(200);
    // Le moniteur voit aussitôt son élève ; la preuve d'opération existe pour la personne créée.
    const learners=await call('GET',`/v1/schools/${id.schoolA}/learners`,undefined,undefined,'demo-instructor');expect(learners.json().data.items.some((l:{personId:string})=>l.personId===person)).toBe(true);
    const list=await call('GET',path,undefined,undefined,'demo-instructor');expect(list.json().data.items[0].status).toBe('ACCEPTED');
  });
  it('l’adresse n’est retenue que si le fournisseur d’identité l’a vérifiée',async()=>{
    const verifiedSubject=fresh(),plainSubject=fresh();
    const first=await issue();expect((await acceptCode(first.code,verifiedSubject,randomUUID(),{email:'Verifie@Example.invalid',email_verified:true})).statusCode).toBe(201);
    const second=await issue();expect((await acceptCode(second.code,plainSubject,randomUUID(),{email:'non.verifie@example.invalid',email_verified:false})).statusCode).toBe(201);
    const stored=async(subject:string)=>(await pool.query('SELECT m.invitation_email,l.contact_email FROM drivy.membership m JOIN drivy.learner_profile l ON l.person_id=m.person_id AND l.school_id=m.school_id WHERE m.person_id=$1 AND m.school_id=$2',[await personOf(subject),id.schoolA])).rows[0];
    expect(await stored(verifiedSubject)).toEqual({invitation_email:'verifie@example.invalid',contact_email:'verifie@example.invalid'});
    expect(await stored(plainSubject)).toEqual({invitation_email:null,contact_email:null});
  });
  it('usage unique : un autre compte, puis une concurrence, échouent ; la même personne se reconfirme sans rien recréer',async()=>{
    const invitation=await issue();const subject=fresh();const operationId=randomUUID();
    const [one,two]=await Promise.all([acceptCode(invitation.code,subject,operationId),acceptCode(invitation.code,subject,operationId)]);
    expect([one.statusCode,two.statusCode]).toEqual([201,201]);expect(one.json().data).toEqual(two.json().data);
    const before=await counts();
    const other=await acceptCode(invitation.code);expect(other.statusCode).toBe(404);expect(other.json().code).toBe('INVITATION_CODE_INVALID');
    expect((await preview(invitation.code)).statusCode).toBe(404);
    const again=await acceptCode(invitation.code,subject);expect(again.statusCode).toBe(201);expect(again.json().data).toEqual(one.json().data);
    expect(await counts()).toEqual({...before,operations:before.operations+1,audits:before.audits+1});
    expect((await pool.query("SELECT count(*)::int n FROM drivy.audit_event WHERE action='InvitationAccepted'")).rows[0].n).toBe(1);
    expect((await trainingsOf(subject))).toHaveLength(1);
    const proof=await call('GET',`/v1/schools/${id.schoolA}/operations/${operationId}`,undefined,undefined,subject);expect(proof.statusCode).toBe(200);
    expect(proof.json().data).toMatchObject({commandType:'ACCEPT_INVITATION',resourceType:'Membership'});expect(proof.body).not.toContain(invitation.code);
    // Deux comptes concurrents sur un même code : un seul l'obtient.
    const raced=await issue();const results=await Promise.all([acceptCode(raced.code,fresh()),acceptCode(raced.code,fresh())]);
    expect(results.map(r=>r.statusCode).sort()).toEqual([201,404]);
    // Même opération avec un autre code : conflit d'idempotence, sans effet.
    const third=await issue();expect((await acceptCode(third.code,subject,operationId)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  });
  it('une personne déjà liée à une autre école rejoint celle-ci avec le même compte',async()=>{
    const invitation=await issue();const before=await counts();
    const response=await acceptCode(invitation.code,'demo-foreign');expect(response.statusCode,response.body).toBe(201);
    const after=await counts();expect(after.persons).toBe(before.persons);expect(after.members).toBe(before.members+1);expect(after.learners).toBe(before.learners+1);
    expect((await pool.query('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[issuer,'demo-foreign'])).rows[0].person_id).toBe(id.foreign);
  });
  it('« Nouveau code » : le renvoi remplace le code, l’ancien échoue aussitôt, le nouveau n’apparaît que dans cette réponse',async()=>{
    const invitation=await issue();const operationId=randomUUID();
    const resent=await call('POST',`${path}/${invitation.id}/resend`,{operationId},1,'demo-instructor');expect(resent.statusCode,resent.body).toBe(200);conforms('InvitationEnvelope',resent.json());
    expect(resent.json().data).toMatchObject({id:invitation.id,version:2,delivery:'CODE',maskedEmail:null,status:'PENDING'});expect(resent.json().data.code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(resent.json().data.code).not.toBe(invitation.code);expect(resent.headers.etag).toBe('"2"');
    expect((await preview(invitation.code)).statusCode).toBe(404);expect((await acceptCode(invitation.code)).statusCode).toBe(404);
    const replay=await call('POST',`${path}/${invitation.id}/resend`,{operationId},1,'demo-instructor');expect(replay.statusCode).toBe(200);expect('code' in replay.json().data).toBe(false);expect(replay.json().data.version).toBe(2);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.invitation_mail')).rows[0].n).toBe(0);
    expect((await preview(resent.json().data.code)).statusCode).toBe(200);
    expect((await acceptCode(resent.json().data.code)).statusCode).toBe(201);
    expect((await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()},3,'demo-instructor')).json().code).toBe('INVITATION_USED');
    // Un autre moniteur ne renvoie pas le code d'un collègue ; une invitation expirée se renouvelle.
    const mine=await issue();expect((await call('POST',`${path}/${mine.id}/resend`,{operationId:randomUUID()},1,'demo-other-instructor')).statusCode).toBe(404);
    await pool.query("UPDATE drivy.invitation SET expires_at=now()-interval '1 second' WHERE id=$1",[mine.id]);
    expect((await preview(mine.code)).statusCode).toBe(404);
    const renewed=await call('POST',`${path}/${mine.id}/resend`,{operationId:randomUUID()},1,'demo-instructor');expect(renewed.statusCode).toBe(200);expect((await preview(renewed.json().data.code)).statusCode).toBe(200);
  });
  it('révocation : le code ne sert plus, la projection reste celle d’un code',async()=>{
    const invitation=await issue();
    const revoked=await call('POST',`${path}/${invitation.id}/revoke`,{operationId:randomUUID(),reason:'Mauvais élève'},1,'demo-instructor');expect(revoked.statusCode,revoked.body).toBe(200);
    conforms('InvitationEnvelope',revoked.json());expect(revoked.json().data).toMatchObject({status:'REVOKED',delivery:'CODE',maskedEmail:null});expect('code' in revoked.json().data).toBe(false);
    const before=await counts();expect((await acceptCode(invitation.code)).json().code).toBe('INVITATION_CODE_INVALID');expect((await preview(invitation.code)).statusCode).toBe(404);
    expect(await counts()).toEqual(before);
    expect((await call('POST',`${path}/${invitation.id}/resend`,{operationId:randomUUID()},2,'demo-instructor')).json().code).toBe('INVITATION_REVOKED');
  });
  it('frein : dix codes refusés en quinze minutes coupent l’identité (aperçu et acceptation confondus), pas les autres',async()=>{
    const invitation=await issue();const attacker='brute-force-subject';
    const guesses=wrong(10);
    for(const [index,guess] of guesses.entries()) {
      const response=index%2===0?await preview(guess,attacker):await acceptCode(guess,attacker);
      expect(response.statusCode,`essai ${index+1}`).toBe(404);expect(response.json().code).toBe('INVITATION_CODE_INVALID');
    }
    for(const use of [preview,acceptCode]) {
      const blocked=await use(invitation.code,attacker);expect(blocked.statusCode).toBe(429);expect(blocked.json().code).toBe('INVITATION_CODE_ATTEMPTS');
    }
    expect((await pool.query("SELECT status FROM drivy.invitation WHERE id=$1",[invitation.id])).rows[0].status).toBe('PENDING');
    expect((await preview(invitation.code,fresh())).statusCode).toBe(200);
    // La limite se compte par émetteur ET sujet : le même sujet d'un autre émetteur n'est pas concerné (voir le test unitaire du limiteur).
  });
  it('une rafale parallèle ne dépasse pas dix tentatives refusées pour la même identité',async()=>{
    const subject=fresh();const results=await Promise.all(Array.from({length:30},(_,i)=>i%2?preview('CODE-FAUX',subject):acceptCode('CODE-FAUX',subject)));
    expect(results.filter(r=>r.statusCode===404)).toHaveLength(10);expect(results.filter(r=>r.statusCode===429)).toHaveLength(20);
    const invitation=await issue();expect((await preview(invitation.code,subject)).statusCode).toBe(429);
    expect((await acceptCode(invitation.code,fresh())).statusCode).toBe(201);
  });
  it('plusieurs permis : un code ouvre toutes les formations et affectations, sans doublon au rejeu',async()=>{
    const offeringA=randomUUID(),policyA=randomUUID(),curriculumA=randomUUID();
    await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at)
      SELECT $1,school_id,'A',1,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at FROM drivy.school_policy_version WHERE school_id=$2 LIMIT 1`,[policyA,id.schoolA]);
    await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at)
      SELECT $1,school_id,'A',1,approved,approval_reason,created_by,approved_at FROM drivy.curriculum_version WHERE school_id=$2 LIMIT 1`,[curriculumA,id.schoolA]);
    await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
      VALUES($1,$2,'category-a','A',1,true,$3,$4,50,9000)`,[offeringA,id.schoolA,curriculumA,policyA]);
    const trainings=[trainingFor(),{offeringId:offeringA,instructorMembershipId:id.otherInstructorMember}];
    const {response}=await create('demo-admin',{training:undefined,trainings});expect(response.statusCode,response.body).toBe(201);
    expect(response.json().data.trainings).toEqual(trainings);conforms('InvitationEnvelope',response.json());
    const {code}=response.json().data as {code:string};expect((await preview(code)).json().data.trainingCategoryCodes).toEqual(['B','A']);
    const subject=fresh(),operationId=randomUUID(),before=await counts();
    await pool.query('UPDATE drivy.offering_version SET enabled=false WHERE id=$1',[offeringA]);
    expect((await acceptCode(code,subject,operationId)).json().code).toBe('INVITATION_CODE_INVALID');expect(await counts()).toEqual(before);
    await pool.query('UPDATE drivy.offering_version SET enabled=true WHERE id=$1',[offeringA]);
    const accepted=await acceptCode(code,subject,operationId);expect(accepted.statusCode,accepted.body).toBe(201);
    expect(await trainingsOf(subject)).toEqual(expect.arrayContaining([
      {status:'ACTIVE',offering_id:id.offeringA,instructor_membership_id:id.instructorMember},
      {status:'ACTIVE',offering_id:offeringA,instructor_membership_id:id.otherInstructorMember}]));
    expect(await trainingsOf(subject)).toHaveLength(2);
    expect((await acceptCode(code,subject,operationId)).json().data).toEqual(accepted.json().data);expect(await trainingsOf(subject)).toHaveLength(2);
    for(const extra of [{trainings:[]},{trainings:[trainingFor(),trainingFor()]},{training:trainingFor(),trainings:[trainingFor()]}])
      expect((await create('demo-admin',{training:undefined,...extra})).response.statusCode).toBe(400);
    expect((await create('demo-instructor',{training:undefined,trainings})).response.json().code).toBe('INVITATION_TRAINING_INVALID');
  });
  it('une formation existante reçoit le moniteur prévu, sans seconde formation ni affectation en double',async()=>{
    const {response}=await create('demo-admin',{training:trainingFor(id.otherInstructorMember)});expect(response.statusCode,response.body).toBe(201);
    const code=response.json().data.code as string,operationId=randomUUID();
    const accepted=await acceptCode(code,'demo-alice',operationId);expect(accepted.statusCode,accepted.body).toBe(201);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.training WHERE learner_id=$1',[id.aliceLearner])).rows[0].n).toBe(1);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.instructor_assignment WHERE training_id=$1 AND instructor_membership_id=$2',[id.aliceTraining,id.otherInstructorMember])).rows[0].n).toBe(1);
    expect((await acceptCode(code,'demo-alice',operationId)).statusCode).toBe(201);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.instructor_assignment WHERE training_id=$1 AND instructor_membership_id=$2',[id.aliceTraining,id.otherInstructorMember])).rows[0].n).toBe(1);
  });
  it('un moniteur prévu devenu inactif refuse le code sans consommer ni créer un dossier',async()=>{
    const {response}=await create('demo-admin',{training:trainingFor(id.otherInstructorMember)});expect(response.statusCode,response.body).toBe(201);
    const code=response.json().data.code as string,before=await counts(),subject=fresh();
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.otherInstructorMember]);
    const refused=await acceptCode(code,subject);expect(refused.statusCode,refused.body).toBe(404);expect(await counts()).toEqual(before);
    expect((await pool.query('SELECT status FROM drivy.invitation WHERE id=$1',[response.json().data.id])).rows[0].status).toBe('PENDING');
    await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.otherInstructorMember]);
    const person=(await pool.query('SELECT person_id FROM drivy.membership WHERE id=$1',[id.otherInstructorMember])).rows[0].person_id as string;
    await pool.query("UPDATE drivy.person SET status='SUSPENDED' WHERE id=$1",[person]);
    expect((await create('demo-admin',{training:trainingFor(id.otherInstructorMember)})).response.json().code).toBe('INVITATION_TRAINING_INVALID');
    expect((await acceptCode(code,subject)).statusCode).toBe(404);expect(await counts()).toEqual(before);
    await pool.query("UPDATE drivy.person SET status='ACTIVE' WHERE id=$1",[person]);
    expect((await acceptCode(code,subject)).statusCode).toBe(201);
  });
  it('un jeton d’e-mail n’ouvre pas les routes de code, ni un code la route des jetons',async()=>{
    const email=await invite('cross@example.invalid');const code=await issue();
    expect((await preview(email.token)).json().code).toBe('INVITATION_CODE_INVALID');
    expect((await call('POST','/v1/invitations/accept',{operationId:randomUUID(),token:code.code},undefined,fresh(),verified())).statusCode).toBe(400);
    expect((await call('POST','/v1/invitations/preview',{token:code.code.repeat(4)},undefined,fresh(),verified())).statusCode).toBe(403);
  });
  it('la base refuse une invitation dont la forme ne correspond pas à son mode',async()=>{
    const insert=(email:string|null,delivery:string,roles:string[],withTraining:boolean)=>pool.query(`INSERT INTO drivy.invitation(id,school_id,email,roles,token_hash,expires_at,inviter_membership_id,inviter_person_id,notice_version,delivery,training_offering_id,training_instructor_membership_id)
      VALUES($1,$2,$3,$4,$5,now()+interval '1 day',$6,$7,(SELECT max(version) FROM drivy.school_data_policy WHERE school_id=$2),$8,$9,$10)`,
      [randomUUID(),id.schoolA,email,roles,createHash('sha256').update(randomUUID()).digest('hex'),id.instructorMember,id.instructor,delivery,withTraining?id.offeringA:null,withTraining?id.instructorMember:null]);
    await expect(insert('x@example.invalid','CODE',['LEARNER'],true)).rejects.toMatchObject({constraint:'invitation_delivery_shape'});
    await expect(insert(null,'CODE',['ADMIN'],false)).rejects.toMatchObject({constraint:'invitation_delivery_shape'});
    await expect(insert(null,'CODE',['LEARNER'],false)).rejects.toMatchObject({constraint:'invitation_delivery_shape'});
    await expect(insert(null,'EMAIL',['LEARNER'],false)).rejects.toMatchObject({constraint:'invitation_delivery_shape'});
    await expect(insert(null,'SMS',['LEARNER'],true)).rejects.toThrow();
    await expect(insert(null,'CODE',['LEARNER'],true)).resolves.toBeDefined();
  });
});

describe('Invitation avec formation · offre republiée depuis l’envoi',()=>{
  let subjects=0;const fresh=()=>`republished-${subjects++}`;
  async function prepareOffering() {
    const policy=randomUUID(),curriculum=randomUUID();
    await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette','Recette','{}',true,'Synthétique',$3,now())`,[policy,id.schoolA,id.adminMember]);
    await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,true,'Synthétique',$3,now())`,[curriculum,id.schoolA,id.adminMember]);
    await pool.query('UPDATE drivy.offering_version SET curriculum_version_id=$2,policy_version_id=$3,default_duration_minutes=50,default_price_cents=9000,enabled=true WHERE id=$1',[id.offeringA,curriculum,policy]);
  }
  beforeEach(prepareOffering);
  const training={offeringId:id.offeringA,instructorMembershipId:id.instructorMember};
  /** Crée une invitation avec formation par le mode demandé et rend de quoi l'accepter. */
  async function invitation(mode:'CODE'|'EMAIL') {
    if(mode==='CODE') {
      const created=await call('POST',path,{operationId:randomUUID(),delivery:'CODE',roles:['LEARNER'],training},undefined,'demo-instructor');expect(created.statusCode,created.body).toBe(201);
      const {code}=created.json().data as {code:string};return (subject:string,operationId=randomUUID())=>call('POST','/v1/invitations/code/accept',{operationId,code},undefined,subject);
    }
    const created=await call('POST',path,{operationId:randomUUID(),email:'new@example.invalid',roles:['LEARNER'],training},undefined,'demo-instructor');expect(created.statusCode,created.body).toBe(201);
    const token=await secret(created.json().data.id);return (subject:string,operationId=randomUUID())=>accept(token,subject,'new@example.invalid',operationId);
  }
  const trainingsOf=async(subject:string)=>(await pool.query(`SELECT t.status,t.offering_id,t.offering_key,a.instructor_membership_id FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id
    JOIN drivy.instructor_assignment a ON a.training_id=t.id JOIN drivy.identity_link k ON k.person_id=l.person_id WHERE k.issuer=$1 AND k.subject=$2`,[issuer,subject])).rows;
  const publishNewVersion=async()=>{const next=randomUUID();
    await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
      SELECT $1,school_id,offering_key,category_code,version+1,true,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents FROM drivy.offering_version WHERE id=$2`,[next,id.offeringA]);return next;};

  it.each(['CODE','EMAIL'] as const)('%s : la formation s’ouvre sur la dernière version prête de la même offre',async mode=>{
    const acceptInvitation=await invitation(mode);const next=await publishNewVersion();const subject=fresh();
    const response=await acceptInvitation(subject);expect(response.statusCode,response.body).toBe(201);
    expect('trainingOpened' in response.json().data).toBe(false);
    const opened=await trainingsOf(subject);expect(opened).toEqual([{status:'ACTIVE',offering_id:next,offering_key:'category-b',instructor_membership_id:id.instructorMember}]);
    const listed=await call('GET',`/v1/schools/${id.schoolA}/trainings`,undefined,undefined,'demo-instructor');
    expect(listed.json().data.items.some((t:{offeringId:string})=>t.offeringId===next)).toBe(true);
  });
  it('EMAIL : sans version prête, l’adhésion est acceptée et l’absence de formation est annoncée',async()=>{
    const mode='EMAIL';
    const acceptInvitation=await invitation(mode);await pool.query('UPDATE drivy.offering_version SET enabled=false WHERE id=$1',[id.offeringA]);
    const subject=fresh();const operationId=randomUUID();const before=await counts();
    const response=await acceptInvitation(subject,operationId);expect(response.statusCode,response.body).toBe(201);
    expect(response.json().data).toMatchObject({schoolId:id.schoolA,roles:['LEARNER'],trainingOpened:false});
    expect(await trainingsOf(subject)).toEqual([]);
    const after=await counts();expect(after).toEqual({...before,persons:before.persons+1,members:before.members+1,learners:before.learners+1,operations:before.operations+1,audits:before.audits+1});
    expect((await pool.query("SELECT changed_fields FROM drivy.audit_event WHERE operation_id=$1",[operationId])).rows[0].changed_fields).toContain('trainingNotOpened');
    // Un rejeu de la même opération rend la même annonce.
    const replay=await acceptInvitation(subject,operationId);expect(replay.statusCode).toBe(201);expect(replay.json().data).toEqual(response.json().data);
  });
  it('CODE : sans version prête, aucun rattachement ni consommation ; le même code fonctionne après réouverture',async()=>{
    const acceptInvitation=await invitation('CODE');await pool.query('UPDATE drivy.offering_version SET enabled=false WHERE id=$1',[id.offeringA]);
    const subject=fresh(),operationId=randomUUID(),before=await counts();
    const response=await acceptInvitation(subject,operationId);expect(response.statusCode,response.body).toBe(404);expect(response.json().code).toBe('INVITATION_CODE_INVALID');
    expect(await counts()).toEqual(before);expect(await trainingsOf(subject)).toEqual([]);
    expect((await pool.query('SELECT status FROM drivy.invitation')).rows[0].status).toBe('PENDING');
    await pool.query('UPDATE drivy.offering_version SET enabled=true WHERE id=$1',[id.offeringA]);
    expect((await acceptInvitation(subject,operationId)).statusCode).toBe(201);expect(await trainingsOf(subject)).toHaveLength(1);
  });
  it('une formation déjà suivie sur cette offre n’est pas dupliquée et n’est pas une anomalie',async()=>{
    const acceptInvitation=await invitation('CODE');const next=await publishNewVersion();
    // Alice suit déjà l'offre (version 1) et accepte : rien à ouvrir, aucun signalement.
    void next;
    const response=await acceptInvitation('demo-alice');expect(response.statusCode,response.body).toBe(201);expect('trainingOpened' in response.json().data).toBe(false);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.training WHERE learner_id=$1',[id.aliceLearner])).rows[0].n).toBe(1);
  });
});
