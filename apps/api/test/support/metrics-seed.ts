import {randomUUID} from 'node:crypto';
import type {Pool} from 'pg';
import {issuer} from './harness.js';

/**
 * Données entièrement synthétiques du jeu de référence de docs/implementation/pilotage-373-indicateurs.md (section 6).
 * Aucune personne réelle : les noms sont des codes. Tout passe par des INSERT directs sous le propriétaire du schéma ;
 * la formation du snapshot de prix par la route de réservation est testée ailleurs (lessons.integration.test.ts).
 */
export interface Actor {subject:string;personId:string;membershipId:string}
export interface Learner {key:string;personId:string;learnerId:string;trainingId:string;subject:string}
export interface SeedSchool {id:string;policy:string;terms:string;admin:Actor;products:Record<string,string>;offerings:Record<string,string>}

export async function addPerson(pool:Pool,subject:string,name:string):Promise<string>{
 const person=randomUUID();
 await pool.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)',[person,name]);
 await pool.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)',[issuer,subject,person]);
 return person;
}
export async function addActor(pool:Pool,school:Pick<SeedSchool,'id'>,subject:string,roles:string[],grants:string[]=[],name=`Acteur ${subject}`):Promise<Actor>{
 const personId=await addPerson(pool,subject,name),membershipId=randomUUID();
 await pool.query('INSERT INTO drivy.membership(id,school_id,person_id,roles,grants) VALUES($1,$2,$3,$4,$5)',[membershipId,school.id,personId,roles,grants]);
 return {subject,personId,membershipId};
}
export async function createSchool(pool:Pool,key:string,options:{status?:string;timeZone?:string}={}):Promise<SeedSchool>{
 const id=randomUUID();
 await pool.query("INSERT INTO drivy.school(id,name,status,contact_email,time_zone) VALUES($1,$2,$3,'contact@example.invalid',$4)",[id,`École synthétique ${key}`,options.status??'ACTIVE',options.timeZone??'Europe/Zurich']);
 const admin=await addActor(pool,{id},`adm-${key}`,['ADMIN']);
 const policy=randomUUID(),terms=randomUUID();
 await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at)
  VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policy,id,admin.membershipId]);
 await pool.query(`INSERT INTO drivy.commercial_terms_version(id,school_id,version,label,terms_text,valid_from,approved,approval_reason,created_by,approved_by,approved_at)
  VALUES($1,$2,1,'Conditions synthétiques','Texte synthétique','2026-01-01',true,'Synthétique',$3,$3,now())`,[terms,id,admin.membershipId]);
 const offerings:Record<string,string>={};
 for(const category of ['B','A']){
  offerings[category]=randomUUID();
  await pool.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES($1,$2,$3,$4,1)",[offerings[category],id,`category-${category.toLowerCase()}`,category]);
 }
 const products:Record<string,string>={};
 const product=async(name:string,productKey:string,version:number,category:string,minutes:number,cents:number)=>{
  products[name]=randomUUID();
  await pool.query(`INSERT INTO drivy.service_product_version(id,school_id,version,product_key,label,type,category_code,duration_minutes,unit_label,unit_price_cents,valid_from,terms_version_id,enabled)
   VALUES($1,$2,$3,$4,$5,'INDIVIDUAL_LESSON',$6,$7,'leçon',$8,'2026-01-01',$9,true)`,[products[name],id,version,productKey,`Prestation ${productKey}`,category,minutes,cents,terms]);
 };
 await product('b45v1','b-45',1,'B',45,9000);
 await product('b45v2','b-45',2,'B',45,10000);
 await product('a60','a-60',1,'A',60,11000);
 return {id,policy,terms,admin,products,offerings};
}
export async function addLearner(pool:Pool,school:SeedSchool,key:string,category:'B'|'A'):Promise<Learner>{
 const subject=`el-${key}-${school.id.slice(0,8)}`,actor=await addActor(pool,school,subject,['LEARNER'],[],`Élève ${key}`);
 const learnerId=randomUUID(),trainingId=randomUUID();
 await pool.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,created_at) VALUES($1,$2,$3,'2026-01-01T00:00:00Z')",[learnerId,school.id,actor.personId]);
 await pool.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on,created_at) VALUES($1,$2,$3,$4,$5,'ACTIVE','2026-01-01','2026-01-01T00:00:00Z')",
  [trainingId,school.id,learnerId,school.offerings[category],`category-${category.toLowerCase()}`]);
 return {key,personId:actor.personId,learnerId,trainingId,subject};
}

export interface LessonSpec {
 instructor:Actor;learner:Learner;product:'b45v1'|'b45v2'|'a60';quantity?:number;status:'PLANNED'|'COMPLETED'|'CANCELLED'|'NO_SHOW';
 plannedStart:string;plannedEnd:string;actualStart?:string;actualEnd?:string;price:number;createdAt?:string;
 mode?:'UNIT_PRICE'|'ENTITLEMENT';charge?:'initial'|'none'|'reversed'|number;timeZone?:string;
}
export async function addLesson(pool:Pool,school:SeedSchool,spec:LessonSpec):Promise<string>{
 const id=randomUUID(),selection={mode:spec.mode??'UNIT_PRICE',serviceProductVersionId:school.products[spec.product],quantity:spec.quantity??1,entitlementLotId:null,acceptedTermsVersionId:school.terms};
 const created=spec.createdAt??new Date(Date.parse(spec.plannedStart)-7*86_400_000).toISOString();
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,status,
   price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection,actual_start,actual_end,created_at)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'Gare (synthétique)',$10,$11,0,$12,$13,$14,$15,$16)`,
  [id,school.id,spec.learner.trainingId,spec.learner.learnerId,spec.learner.personId,spec.instructor.membershipId,spec.plannedStart,spec.plannedEnd,spec.timeZone??'Europe/Zurich',spec.status,
   spec.price,school.policy,JSON.stringify(selection),spec.actualStart??null,spec.actualEnd??null,created]);
 if(spec.status==='COMPLETED'||spec.status==='CANCELLED'||spec.status==='NO_SHOW'){
  const account=randomUUID();
  await pool.query('INSERT INTO drivy.lesson_account(id,school_id,lesson_id,planned_price_cents) VALUES($1,$2,$3,$4)',[account,school.id,id,spec.price]);
  const charge=spec.charge??(spec.status==='COMPLETED'?'initial':'none');
  const entry=async(kind:string,cents:number)=>pool.query("INSERT INTO drivy.charge_entry(school_id,account_id,kind,amount_signed_cents,reason,operation_id) VALUES($1,$2,$3,$4,'Synthétique',$5)",[school.id,account,kind,cents,randomUUID()]);
  if(typeof charge==='number')await entry('INITIAL',charge);
  else if(charge==='initial'||charge==='reversed')await entry('INITIAL',spec.price);
  if(charge==='reversed')await entry('REVERSAL',-spec.price);
 }
 return id;
}

export interface SeriesSpec {typeKey:'FIRST_AID'|'AWARENESS';status:'PUBLISHED'|'CANCELLED';capacity:number;responsible:Actor;createdBy:Actor;createdAt:string;
 publishedAt:string;cancelledAt?:string;occurrences:{start:string;end:string;instructor:Actor}[]}
export async function addSeries(pool:Pool,school:SeedSchool,spec:SeriesSpec):Promise<{id:string;occurrences:string[]}>{
 const id=randomUUID(),type=(await pool.query<{id:string}>('SELECT id FROM drivy.course_type WHERE stable_key=$1',[spec.typeKey])).rows[0]!.id;
 await pool.query(`INSERT INTO drivy.course_series(id,school_id,type_id,status,title,responsible_membership_id,capacity,created_by,created_at,published_at,cancelled_at,cancel_reason)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,[id,school.id,type,spec.status,`Cours synthétique ${spec.typeKey}`,spec.responsible.membershipId,spec.capacity,spec.createdBy.membershipId,
  spec.createdAt,spec.publishedAt,spec.cancelledAt??null,spec.cancelledAt?'Annulé (synthétique)':null]);
 const occurrences:string[]=[];
 for(const [index,o] of spec.occurrences.entries()){
  const occurrence=randomUUID();occurrences.push(occurrence);
  await pool.query(`INSERT INTO drivy.course_occurrence(id,school_id,series_id,position,starts_at,ends_at,time_zone,instructor_membership_id) VALUES($1,$2,$3,$4,$5,$6,'Europe/Zurich',$7)`,
   [occurrence,school.id,id,index+1,o.start,o.end,o.instructor.membershipId]);
 }
 return {id,occurrences};
}
export async function addEnrollment(pool:Pool,school:SeedSchool,series:{id:string},learner:Learner,by:Actor,options:{createdAt:string;cancelledAt?:string;cancelKind?:'SELF'|'STAFF'|'SERIES_CANCELLED'}):Promise<string>{
 const id=randomUUID();
 await pool.query(`INSERT INTO drivy.course_enrollment(id,school_id,series_id,learner_id,status,source,policy_version,self_cancel_hours,self_cancel_deadline,created_by,created_at,cancelled_at,cancelled_by,cancel_kind)
  VALUES($1,$2,$3,$4,$5,'STAFF',1,24,$6,$7,$8,$9,$10,$11)`,[id,school.id,series.id,learner.learnerId,options.cancelledAt?'CANCELLED':'ACTIVE',options.createdAt,by.membershipId,options.createdAt,
  options.cancelledAt??null,options.cancelledAt?by.membershipId:null,options.cancelledAt?options.cancelKind??'STAFF':null]);
 return id;
}
export async function addAttendance(pool:Pool,school:SeedSchool,enrollment:string,occurrence:string,status:'PRESENT'|'ABSENT'|'EXCUSED',by:Actor){
 await pool.query('INSERT INTO drivy.course_attendance(school_id,enrollment_id,occurrence_id,status,recorded_by) VALUES($1,$2,$3,$4,$5)',[school.id,enrollment,occurrence,status,by.membershipId]);
}
export async function addSeatOffer(pool:Pool,school:SeedSchool,series:{id:string},learner:Learner,expiresAt:string){
 const entry=randomUUID();
 await pool.query("INSERT INTO drivy.course_waitlist_entry(id,school_id,series_id,learner_id,status) VALUES($1,$2,$3,$4,'OFFERED')",[entry,school.id,series.id,learner.learnerId]);
 await pool.query("INSERT INTO drivy.course_seat_offer(id,school_id,series_id,entry_id,offered_at,expires_at,status) VALUES($1,$2,$3,$4,$5,$6,'ACTIVE')",[randomUUID(),school.id,series.id,entry,new Date(Date.parse(expiresAt)-3_600_000).toISOString(),expiresAt]);
}
export async function addPayment(pool:Pool,school:SeedSchool,enrollment:string,by:Actor,cents:number,recordedAt:string,voidedAt?:string):Promise<string>{
 const id=randomUUID();
 await pool.query(`INSERT INTO drivy.course_payment_record(id,school_id,enrollment_id,amount_cents,recorded_by,recorded_at,voided_at,voided_by,void_reason)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[id,school.id,enrollment,cents,by.membershipId,recordedAt,voidedAt??null,voidedAt?by.membershipId:null,voidedAt?'Saisie erronée (synthétique)':null]);
 return id;
}

// ---------------------------------------------------------------- jeu A (docs/implementation/pilotage-373-indicateurs.md, sections 6.1 à 6.3)
export interface Reference {school:SeedSchool;adm1:Actor;adm2:Actor;m1:Actor;m2:Actor;m3:Actor;m4:Actor;learners:Record<string,Learner>;lessons:Record<string,string>}
export const NOW='2026-10-28T17:00:00Z';
export async function seedReference(pool:Pool):Promise<Reference>{
 const school=await createSchool(pool,'ref');
 const adm1=school.admin,adm2=await addActor(pool,school,'adm2-ref',['ADMIN'],['EXPORT_MANAGEMENT']);
 const m1=await addActor(pool,school,'m1-ref',['INSTRUCTOR']),m2=await addActor(pool,school,'m2-ref',['INSTRUCTOR'],['VIEW_SCHOOL_METRICS']);
 const m3=await addActor(pool,school,'m3-ref',['INSTRUCTOR'],['VIEW_FINANCIAL_METRICS']),m4=await addActor(pool,school,'m4-ref',['INSTRUCTOR'],['EXPORT_MANAGEMENT']);
 const learners:Record<string,Learner>={};
 for(const [key,category] of [['E1','B'],['E2','B'],['E3','A'],['E4','A'],['E5','B'],['E6','B']] as const)learners[key]=await addLearner(pool,school,key,category);
 // [id, moniteur, élève, prestation, quantité, statut, début prévu, fin prévue, début réel, fin réelle, prix, création]
 type Row=[string,Actor,string,LessonSpec["product"],number,LessonSpec["status"],string,string,(string|undefined)?,(string|undefined)?,number?,(string|undefined)?,LessonSpec["charge"]?];
 const rows:Row[]=[
  ['S1',m1,'E1','b45v1',1,'COMPLETED','2026-09-08T08:00:00Z','2026-09-08T08:45:00Z','2026-09-08T08:02:00Z','2026-09-08T08:49:00Z',9000],
  ['S2',m1,'E2','b45v1',2,'COMPLETED','2026-09-15T12:00:00Z','2026-09-15T13:30:00Z','2026-09-15T12:00:00Z','2026-09-15T13:30:00Z',18000],
  ['S3',m2,'E3','a60',1,'COMPLETED','2026-09-22T07:00:00Z','2026-09-22T08:00:00Z','2026-09-22T07:05:00Z','2026-09-22T08:03:00Z',11000],
  ['S4',m1,'E1','b45v1',1,'CANCELLED','2026-09-24T08:00:00Z','2026-09-24T08:45:00Z',undefined,undefined,9000],
  ['S5',m2,'E4','a60',1,'NO_SHOW','2026-09-25T13:00:00Z','2026-09-25T14:00:00Z',undefined,undefined,11000],
  ['S6',m1,'E2','b45v1',1,'COMPLETED','2026-09-29T09:00:00Z','2026-09-29T09:45:00Z','2026-09-29T09:00:00Z','2026-09-29T09:45:00Z',9000],
  ['S7',m2,'E3','a60',1,'COMPLETED','2026-09-30T21:30:00Z','2026-09-30T22:30:00Z','2026-09-30T21:30:00Z','2026-09-30T22:30:00Z',11000],
  ['O1',m1,'E5','b45v2',1,'COMPLETED','2026-09-30T22:30:00Z','2026-09-30T23:15:00Z','2026-09-30T22:30:00Z','2026-09-30T23:15:00Z',10000,'2026-09-30T12:30:00Z'],
  ['O2',m1,'E1','b45v1',1,'COMPLETED','2026-10-06T08:00:00Z','2026-10-06T08:45:00Z','2026-10-06T08:00:00Z','2026-10-06T08:40:00Z',9000,'2026-09-25T10:00:00Z'],
  ['O3',m1,'E2','b45v1',2,'COMPLETED','2026-10-13T12:00:00Z','2026-10-13T13:30:00Z','2026-10-13T12:03:00Z','2026-10-13T13:31:00Z',17000,'2026-09-28T10:00:00Z'],
  ['O5',m2,'E4','a60',1,'COMPLETED','2026-10-15T07:00:00Z','2026-10-15T08:00:00Z',undefined,undefined,11000],
  ['O6',m2,'E3','a60',1,'CANCELLED','2026-10-07T08:00:00Z','2026-10-07T09:00:00Z',undefined,undefined,11000,undefined,'reversed'],
  ['X1',m1,'E2','b45v2',1,'CANCELLED','2026-10-16T08:00:00Z','2026-10-16T08:45:00Z',undefined,undefined,10000],
  ['X2',m2,'E4','a60',1,'NO_SHOW','2026-10-21T13:00:00Z','2026-10-21T14:00:00Z',undefined,undefined,11000],
  ['X3',m1,'E5','b45v2',1,'CANCELLED','2026-10-23T08:00:00Z','2026-10-23T08:45:00Z',undefined,undefined,10000],
  ['V1',m2,'E4','a60',1,'PLANNED','2026-10-20T07:00:00Z','2026-10-20T08:00:00Z',undefined,undefined,11000],
  ['V2',m1,'E5','b45v2',1,'PLANNED','2026-10-22T08:00:00Z','2026-10-22T08:45:00Z','2026-10-22T08:00:00Z',undefined,10000],
  ['V3',m1,'E1','b45v2',1,'PLANNED','2026-10-28T16:30:00Z','2026-10-28T17:15:00Z','2026-10-28T16:30:00Z',undefined,10000],
  ['D1',m1,'E1','b45v2',1,'COMPLETED','2026-10-25T22:30:00Z','2026-10-25T23:15:00Z','2026-10-25T22:30:00Z','2026-10-25T23:15:00Z',10000],
  ['U1',m1,'E1','b45v2',1,'PLANNED','2026-10-29T09:00:00Z','2026-10-29T09:45:00Z',undefined,undefined,10000],
  ['U2',m2,'E3','a60',1,'PLANNED','2026-10-30T13:00:00Z','2026-10-30T14:00:00Z',undefined,undefined,11000],
  ['U3',m1,'E2','b45v2',1,'PLANNED','2026-10-31T22:30:00Z','2026-10-31T23:15:00Z',undefined,undefined,10000],
  ['N1',m1,'E5','b45v2',1,'PLANNED','2026-10-31T23:30:00Z','2026-11-01T00:15:00Z',undefined,undefined,10000],
 ];
 const lessons:Record<string,string>={};
 for(const [key,instructor,learner,product,quantity,status,plannedStart,plannedEnd,actualStart,actualEnd,price,createdAt,charge] of rows)
  lessons[key]=await addLesson(pool,school,{instructor,learner:learners[learner]!,product,quantity,status,plannedStart,plannedEnd,price:price!,
   ...(actualStart?{actualStart}:{}),...(actualEnd?{actualEnd}:{}),...(createdAt?{createdAt}:{}),...(charge?{charge}:{})});

 // Cours : CS1 passée avec appel incomplet, CS2 et CS3 à venir, CS4 annulée.
 const cs1=await addSeries(pool,school,{typeKey:'FIRST_AID',status:'PUBLISHED',capacity:8,responsible:m1,createdBy:adm1,createdAt:'2026-09-28T08:00:00Z',publishedAt:'2026-09-28T09:00:00Z',
  occurrences:[{start:'2026-10-12T17:00:00Z',end:'2026-10-12T19:00:00Z',instructor:m1},{start:'2026-10-13T17:00:00Z',end:'2026-10-13T19:00:00Z',instructor:m1}]});
 const cs2=await addSeries(pool,school,{typeKey:'AWARENESS',status:'PUBLISHED',capacity:12,responsible:m1,createdBy:adm1,createdAt:'2026-09-10T08:00:00Z',publishedAt:'2026-09-10T09:00:00Z',
  occurrences:[{start:'2026-11-10T18:00:00Z',end:'2026-11-10T20:00:00Z',instructor:m1}]});
 const cs3=await addSeries(pool,school,{typeKey:'FIRST_AID',status:'PUBLISHED',capacity:8,responsible:m2,createdBy:adm1,createdAt:'2026-10-20T08:00:00Z',publishedAt:'2026-10-20T09:00:00Z',
  occurrences:[{start:'2026-11-20T18:00:00Z',end:'2026-11-20T20:00:00Z',instructor:m2}]});
 const cs4=await addSeries(pool,school,{typeKey:'FIRST_AID',status:'CANCELLED',capacity:8,responsible:m1,createdBy:adm1,createdAt:'2026-09-29T08:00:00Z',publishedAt:'2026-09-29T09:00:00Z',cancelledAt:'2026-10-02T09:00:00Z',
  occurrences:[{start:'2026-10-20T18:00:00Z',end:'2026-10-20T20:00:00Z',instructor:m1}]});
 const L=learners;
 const i1=await addEnrollment(pool,school,cs1,L.E1!,adm1,{createdAt:'2026-10-02T08:00:00Z'}),i2=await addEnrollment(pool,school,cs1,L.E2!,adm1,{createdAt:'2026-10-02T08:05:00Z'});
 const i3=await addEnrollment(pool,school,cs1,L.E3!,adm1,{createdAt:'2026-10-03T08:00:00Z',cancelledAt:'2026-10-10T08:00:00Z',cancelKind:'SELF'});
 const i4=await addEnrollment(pool,school,cs1,L.E4!,adm1,{createdAt:'2026-10-04T08:00:00Z'});
 const i5=await addEnrollment(pool,school,cs2,L.E1!,adm1,{createdAt:'2026-09-15T08:00:00Z'}),i6=await addEnrollment(pool,school,cs2,L.E2!,adm1,{createdAt:'2026-10-20T08:00:00Z'});
 for(const key of ['E1','E2','E3','E4','E5','E6'])await addEnrollment(pool,school,cs3,L[key]!,adm1,{createdAt:'2026-10-21T08:00:00Z'});
 await addEnrollment(pool,school,cs4,L.E6!,adm1,{createdAt:'2026-10-01T08:00:00Z',cancelledAt:'2026-10-02T09:00:00Z',cancelKind:'SERIES_CANCELLED'});
 await addSeatOffer(pool,school,cs2,L.E5!,'2026-10-29T12:00:00Z');
 const [o1,o2]=cs1.occurrences as [string,string];
 await addAttendance(pool,school,i1,o1,'PRESENT',m1);await addAttendance(pool,school,i2,o1,'PRESENT',m1);await addAttendance(pool,school,i4,o1,'ABSENT',m1);
 await addAttendance(pool,school,i1,o2,'PRESENT',m1);
 // Règlements de cours (centimes).
 await addPayment(pool,school,i1,adm1,12000,'2026-10-12T09:00:00Z');
 await addPayment(pool,school,i2,adm1,6000,'2026-10-12T09:05:00Z');
 await addPayment(pool,school,i2,adm1,6000,'2026-10-20T09:00:00Z');
 await addPayment(pool,school,i4,adm1,12000,'2026-10-12T09:10:00Z','2026-10-13T08:00:00Z');
 await addPayment(pool,school,i4,adm1,12000,'2026-10-13T08:05:00Z');
 await addPayment(pool,school,i3,adm1,12000,'2026-10-05T09:00:00Z');
 await addPayment(pool,school,i5,adm1,3000,'2026-09-30T21:30:00Z');
 await addPayment(pool,school,i5,adm1,3000,'2026-09-30T22:30:00Z');
 await addPayment(pool,school,i1,adm1,0,'2026-10-14T09:00:00Z');
 await addPayment(pool,school,i5,adm1,12000,'2026-09-20T09:00:00Z','2026-10-09T09:00:00Z');
 void i6;
 return {school,adm1,adm2,m1,m2,m3,m4,learners,lessons};
}

// ---------------------------------------------------------------- jeu B : 8 000 + 2 000 = 10 000 CHF, un règlement de 500 CHF n'y change rien
export async function seedBulk(pool:Pool):Promise<{school:SeedSchool;admin:Actor}>{
 const school=await createSchool(pool,'bulk'),instructors:Actor[]=[];
 for(let n=1;n<=4;n++)instructors.push(await addActor(pool,school,`m${n}-bulk`,['INSTRUCTOR']));
 const learner=await addLearner(pool,school,'B1','B');
 const day=(n:number)=>`2026-10-${String(n).padStart(2,'0')}`;
 const slot=(dayNumber:number,hour:number)=>{
  const hh=String(hour).padStart(2,'0'),start=`${day(dayNumber)}T${hh}:00:00Z`,end=`${day(dayNumber)}T${hh}:45:00Z`;
  return {start,end};
 };
 // 80 leçons réalisées du 1er au 27 octobre (le chevauchement de leçons n'est contraint que par les réservations, non créées ici).
 for(let index=0;index<80;index++){
  const {start,end}=slot(1+index%27,8+Math.floor(index/27));
  await addLesson(pool,school,{instructor:instructors[index%4]!,learner,product:'b45v2',status:'COMPLETED',plannedStart:start,plannedEnd:end,actualStart:start,actualEnd:end,price:10000});
 }
 // 20 leçons futures les 29, 30 et 31 octobre.
 for(let index=0;index<20;index++){
  const {start,end}=slot(29+index%3,8+Math.floor(index/3));
  await addLesson(pool,school,{instructor:instructors[index%4]!,learner,product:'b45v2',status:'PLANNED',plannedStart:start,plannedEnd:end,price:10000});
 }
 const series=await addSeries(pool,school,{typeKey:'FIRST_AID',status:'PUBLISHED',capacity:8,responsible:instructors[0]!,createdBy:school.admin,createdAt:'2026-10-01T08:00:00Z',publishedAt:'2026-10-01T09:00:00Z',
  occurrences:[{start:'2026-11-10T18:00:00Z',end:'2026-11-10T20:00:00Z',instructor:instructors[0]!}]});
 const enrollment=await addEnrollment(pool,school,series,learner,school.admin,{createdAt:'2026-10-02T08:00:00Z'});
 await addPayment(pool,school,enrollment,school.admin,50000,'2026-10-15T09:00:00Z');
 return {school,admin:school.admin};
}
