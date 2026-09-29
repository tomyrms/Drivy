import {readFile,readdir} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {beforeAll,afterAll,it,expect} from 'vitest';
import {Pool} from 'pg';
import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'jose';
import {buildApp} from '../src/app.js';
import {createTokenVerifier} from '../src/auth.js';
import {fixtureIds as id,seedFixtures} from '../scripts/fixtures.js';
const url=process.env.TEST_DATABASE_URL;if(!url || new URL(url).pathname!=='/drivy_test')throw new Error('Base de recette drivy_test requise.');
const pool=new Pool({connectionString:url});const issuer='https://identity.test.invalid';const path=`/v1/schools/${id.schoolA}`;
let app:ReturnType<typeof buildApp>;let keys:Awaited<ReturnType<typeof generateKeyPair>>;
beforeAll(async()=>{
 // Cette recette bornée ne prend pas les migrations suivantes encore écrites par une autre tranche.
 await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');
 for(const role of ['drivy_test_migrator','drivy_app','drivy_invitation_mailer'])await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
 await pool.query('GRANT CREATE ON DATABASE drivy_test TO drivy_test_migrator');await pool.query('GRANT USAGE,CREATE ON SCHEMA public TO drivy_test_migrator');
 await pool.query('GRANT drivy_app,drivy_invitation_mailer TO drivy_test_migrator WITH ADMIN OPTION');
 const migration=new Pool({connectionString:url,options:'-c role=drivy_test_migrator'});
 try {await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
  for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(n=>/^00[1-5]_.*\.sql$/.test(n)).sort()){
   const sql=await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');const db=await migration.connect();
   try{await db.query('BEGIN');await db.query(sql);await db.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',[name,createHash('sha256').update(sql).digest('hex')]);await db.query('COMMIT');}catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
   if(name.startsWith('001_'))await seedFixtures(pool,issuer);
  }
 }finally{await migration.end();}
 keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
 app=buildApp({pool,cursorSecret:'catalogue-test-secret-32-characters',verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'catalogue',alg:'RS256'}]}))});
});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'POST'|'PATCH',route:string,body?:Record<string,unknown>,version?:number,subject='demo-admin',authTime:number|null=Math.floor(Date.now()/1000)){
 const token=await new SignJWT(authTime===null?{}:{auth_time:authTime}).setProtectedHeader({alg:'RS256',kid:'catalogue'}).setIssuer(issuer).setSubject(subject).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
 return app.inject({method,url:route,headers:{authorization:`Bearer ${token}`,...(body?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
}
it('catalogue réel approuvé → formation → affectation, avec héritage et reprise',async()=>{
 expect((await call('GET',`${path}/trainings/${id.aliceTraining}`)).statusCode).toBe(200);
 expect((await call('GET',`${path}/offerings`)).json().data.items).toEqual([]);
 const c=await call('POST',`${path}/curricula`,{operationId:randomUUID(),categoryCode:'B',approved:true,approvalReason:'Référentiel synthétique relu.',competencies:[{key:'look',label:'Observation',description:'Observer avant de déplacer le véhicule.',sortOrder:0}]});expect(c.statusCode,c.body).toBe(201);
 const p=await call('POST',`${path}/policy-versions`,{operationId:randomUUID(),categoryCode:'B',approved:true,approvalReason:'Procédure synthétique relue.',procedureText:'Examiner le permis.',cancellationPolicyText:'Conditions synthétiques de recette.',sourceUrls:[]});expect(p.statusCode,p.body).toBe(201);
 const offerBody={operationId:randomUUID(),offeringKey:'test-b',categoryCode:'B',curriculumVersionId:c.json().data.id,policyVersionId:p.json().data.id,enabled:true,defaultDurationMinutes:50,defaultPriceCents:9000};
 const o=await call('POST',`${path}/offerings`,offerBody);expect(o.statusCode,o.body).toBe(201);
 expect((await call('GET',`${path}/offerings`,undefined,undefined,'demo-alice')).json().data.items[0].id).toBe(o.json().data.id);
 const command={operationId:randomUUID(),learnerId:id.aliceLearner,offeringId:o.json().data.id};
 const created=await call('POST',`${path}/trainings`,command);expect(created.statusCode,created.body).toBe(201);const trainingId=created.json().data.id;
 expect((await call('POST',`${path}/trainings`,command)).json().data).toEqual(created.json().data);
 expect((await call('POST',`${path}/trainings`,{...command,operationId:randomUUID()})).json().code).toBe('ACTIVE_TRAINING_EXISTS');
 expect((await call('GET',`${path}/trainings/${trainingId}`,undefined,undefined,'demo-other-instructor')).statusCode).toBe(404);
 const a=await call('POST',`${path}/trainings/${trainingId}/assignments`,{operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,validFrom:'2026-01-01T00:00:00Z'});expect(a.statusCode,a.body).toBe(201);
 expect((await call('GET',`${path}/trainings/${trainingId}`,undefined,undefined,'demo-other-instructor')).statusCode).toBe(200);
 const member=(await call('GET',`${path}/members`)).json().data.items.find((m:{id:string})=>m.id===id.otherInstructorMember);expect(member.accessEpoch).toBe(2);
 expect((await call('POST',`${path}/offerings`,{...offerBody,operationId:randomUUID(),enabled:false})).statusCode).toBe(201);
 expect((await call('POST',`${path}/trainings`,{operationId:randomUUID(),learnerId:id.bobLearner,offeringId:o.json().data.id})).json().code).toBe('OFFERING_NOT_READY');
 expect((await call('GET',`${path}/trainings/${trainingId}`)).statusCode).toBe(200);
 const otherOffer=await call('POST',`${path}/offerings`,{...offerBody,operationId:randomUUID(),offeringKey:'instructor-test'});expect(otherOffer.statusCode,otherOffer.body).toBe(201);
 const instructorCreated=await call('POST',`${path}/trainings`,{operationId:randomUUID(),learnerId:id.aliceLearner,offeringId:otherOffer.json().data.id},undefined,'demo-instructor');expect(instructorCreated.statusCode,instructorCreated.body).toBe(201);
 expect((await call('GET',`${path}/trainings/${instructorCreated.json().data.id}`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
});
it('rôles : auth_time signé requis, dernier ADMIN et relations protégés',async()=>{
 const body={operationId:randomUUID(),roles:['ADMIN','INSTRUCTOR'],grants:[],reason:'Activer explicitement le rôle enseignant.'};
 const route=`${path}/members/${id.adminMember}`;
 expect((await call('PATCH',route,body,1,'demo-admin',null)).json().code).toBe('REAUTH_REQUIRED');
 expect((await call('PATCH',route,body,1,'demo-admin',Math.floor(Date.now()/1000)-301)).json().code).toBe('REAUTH_REQUIRED');
 const changed=await call('PATCH',route,body,1);expect(changed.statusCode,changed.body).toBe(200);expect(changed.json().data.roles).toEqual(['ADMIN','INSTRUCTOR']);
 expect((await call('PATCH',route,{...body,operationId:randomUUID(),roles:['INSTRUCTOR']},2)).json().code).toBe('LAST_ADMIN');
 expect((await call('GET',`${path}/members`,undefined,undefined,'demo-alice')).statusCode).toBe(403);
 const target=(await call('GET',`${path}/members`)).json().data.items.find((m:{id:string})=>m.id===id.instructorMember);
 expect((await call('PATCH',`${path}/members/${id.instructorMember}`,{operationId:randomUUID(),roles:['ADMIN'],grants:[],reason:'Retrait synthétique.'},target.version)).json().code).toBe('MEMBER_RELATIONS_REQUIRE_REVIEW');
 expect((await pool.query('SELECT reason FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows[0].reason).toBe(body.reason);
});
