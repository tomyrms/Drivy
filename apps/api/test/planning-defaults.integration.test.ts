import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,prepareCommercial,lessonBody,slot,id,issuer,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
const preference=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),trainingCategoryCode:'B',serviceProductKey:'lesson-50',...extra});

describe('préférences personnelles de planification',()=>{
 it('reprend une représentation initiale, persiste avec version et ne partage pas les réglages entre membres',async()=>{
  const initial=await call('GET','/planning-defaults');expect(initial.statusCode,initial.body).toBe(200);
  expect(initial.json().data).toEqual({id:id.instructorMember,schoolId:id.schoolA,version:1,trainingCategoryCode:null,serviceProductKey:null});
  const body=preference(),saved=await call('PUT','/planning-defaults',body,1);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({version:2,trainingCategoryCode:'B',serviceProductKey:'lesson-50'});
  expect((await call('PUT','/planning-defaults',body,1)).json().data).toEqual(saved.json().data);
  expect((await call('PUT','/planning-defaults',{...body,serviceProductKey:null},1)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('PUT','/planning-defaults',preference(),1)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT','/planning-defaults',preference())).statusCode).toBe(428);
  expect((await call('GET','/planning-defaults',undefined,null,'demo-admin')).json().data).toMatchObject({id:id.adminMember,version:1,trainingCategoryCode:null,serviceProductKey:null});
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'SAVE_PLANNING_DEFAULTS',resourceType:'PlanningDefaults',resourceId:id.instructorMember,resourceVersion:2});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows[0].n).toBe(1);
 });
 it('refuse élève, autre école, valeur inconnue, ancienne version de tarif et accès retiré',async()=>{
  expect((await call('GET','/planning-defaults',undefined,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('PUT','/planning-defaults',preference(),1,'demo-alice')).statusCode).toBe(403);
  expect((await call('GET',`/v1/schools/${id.schoolB}/planning-defaults`,undefined,null,'demo-admin')).statusCode).toBe(403);
  for(const body of [preference({trainingCategoryCode:'UNKNOWN'}),preference({serviceProductKey:'unknown'}),preference({membershipId:id.adminMember})]) {
   expect((await call('PUT','/planning-defaults',body,2)).statusCode).toBeGreaterThanOrEqual(400);
  }
  await pool.query('UPDATE drivy.service_product_version SET enabled=false WHERE id=$1',[commercial.product.id]);
  try{expect((await call('PUT','/planning-defaults',preference(),2)).json().code).toBe('PLANNING_DEFAULT_INVALID');}
  finally{await pool.query('UPDATE drivy.service_product_version SET enabled=true WHERE id=$1',[commercial.product.id]);}
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
  try{expect((await call('GET','/planning-defaults')).statusCode).toBe(403);}
  finally{await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.instructorMember]);}
 });
 it('la RLS limite la préférence au membre courant même pour un administrateur',async()=>{
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject','demo-admin',true),set_config('app.school_id',$2,true),set_config('app.person_id',$3,true)",[issuer,id.schoolA,id.admin]);
   expect((await db.query('SELECT * FROM drivy.planning_defaults')).rows).toEqual([]);
   await db.query('ROLLBACK');
  }finally{db.release();}
 });
 it('refuse une écriture concurrente et permet de remettre les préférences à aucune',async()=>{
  const writes=await Promise.all([call('PUT','/planning-defaults',preference({serviceProductKey:null}),2),call('PUT','/planning-defaults',preference({trainingCategoryCode:null,serviceProductKey:null}),2)]);
  expect(writes.map(r=>r.statusCode).sort()).toEqual([200,412]);
  const cleared=await call('PUT','/planning-defaults',preference({trainingCategoryCode:null,serviceProductKey:null}),3);
  expect(cleared.statusCode,cleared.body).toBe(200);expect(cleared.json().data).toMatchObject({version:4,trainingCategoryCode:null,serviceProductKey:null});
 });
});

describe('lieu de rendez-vous facultatif et tarif préféré',()=>{
 it('planifie et déplace sans lieu, sans modifier les prérequis commerciaux et les affectations',async()=>{
  const body=lessonBody(commercial,school.policy,20);const {meetingPoint:_omitted,...withoutPlace}=body;
  const created=await call('POST','/lessons',withoutPlace);expect(created.statusCode,created.body).toBe(201);
  expect(created.json().data).toMatchObject({meetingPoint:'',priceCentsSnapshot:9000,instructorMembershipId:id.instructorMember});
  const move={operationId:randomUUID(),...slot(21),timeZone:'Europe/Zurich',meetingPoint:null,instructorMembershipId:id.instructorMember,agreementConfirmed:true};
  const moved=await call('POST',`/lessons/${created.json().data.id}/move`,move,1);expect(moved.statusCode,moved.body).toBe(200);expect(moved.json().data.meetingPoint).toBe('');
  const invalid=await call('POST','/lessons',{...withoutPlace,operationId:randomUUID(),...slot(22),commercialSelection:{...body.commercialSelection,acceptedTermsVersionId:randomUUID()}});
  expect(invalid.statusCode).toBe(422);
  expect((await call('POST','/lessons',{...withoutPlace,operationId:randomUUID(),...slot(22),instructorMembershipId:id.otherInstructorMember})).statusCode).toBeGreaterThanOrEqual(400);
 });
 it('démarre sans lieu et photographie le tarif préféré courant et compatible',async()=>{
  const product=await call('POST','/service-products',{operationId:randomUUID(),productKey:'preferred-50',label:'Tarif préféré de recette',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9500,validFrom:new Date().toISOString().slice(0,10),validUntil:null,termsVersionId:commercial.terms.id,enabled:true},null,'demo-admin');
  expect(product.statusCode,product.body).toBe(201);
  expect((await call('PUT','/planning-defaults',preference({serviceProductKey:'preferred-50'}),4)).statusCode).toBe(200);
  const started=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining,meetingPoint:''});
  expect(started.statusCode,started.body).toBe(201);expect(started.json().data).toMatchObject({meetingPoint:'',priceCentsSnapshot:9500,commercialSelection:{serviceProductVersionId:product.json().data.id}});
  expect((await call('POST',`/lessons/${started.json().data.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},1)).statusCode).toBe(200);
  await pool.query('UPDATE drivy.service_product_version SET enabled=false WHERE id=$1',[product.json().data.id]);
  const fallback=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining});
  expect(fallback.statusCode,fallback.body).toBe(201);expect(fallback.json().data.priceCentsSnapshot).toBe(9000);
 });
});
