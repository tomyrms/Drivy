import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {observationThemes} from '../src/observation-themes.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
let look:string,speed:string;
const path='/observation-ranking',themes='/observation-themes',schoolB=`/v1/schools/${id.schoolB}/observation-ranking`;
const manual=observationThemes.filter(theme=>theme.defaultVisible).map(theme=>theme.key as string);
const mode=(value:'MANUAL'|'SMART')=>({operationId:randomUUID(),mode:value});
const refreshes=async()=>(await pool.query("SELECT count(*)::int AS n FROM drivy.operation WHERE command_type='REFRESH_OBSERVATION_RANKING'")).rows[0].n as number;
/** Vieillit le dernier classement : la prochaine lecture est la première d'un nouveau jour. Chaque appel recule d'un jour de plus. */
let age=0;
const yesterday=(member:string)=>pool.query("UPDATE drivy.observation_ranking SET ranked_on=(now() AT TIME ZONE 'Europe/Zurich')::date-$2::int WHERE membership_id=$1",[member,++age]);
/** Une leçon passée du moniteur, avec `uses` signalements d'un thème faits dans la palette. */
async function pastLesson(daysAgo:number,slot:number,theme:string,competency:string,uses:number,member=id.instructorMember){
 const lesson=randomUUID();
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  VALUES($1,$2,$3,$4,$5,$6,now()-make_interval(days=>$7,hours=>$8),now()-make_interval(days=>$7,hours=>$8)+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$9,'{"mode":"UNIT_PRICE"}')`,
  [lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,member,daysAgo,slot,school.policy]);
 for(let index=0;index<uses;index++)await pool.query(`INSERT INTO drivy.geo_observation(school_id,lesson_id,training_id,author_membership_id,competency_id,text,origin,observed_at,created_at,event_kind,event_status,theme_key)
  VALUES($1,$2,$3,$4,$5,'Recette','LIVE',now()-make_interval(days=>$6,hours=>$7),now()-make_interval(days=>$6,hours=>$7),'QUALIFIED','TO_REWORK',$8)`,[id.schoolA,lesson,id.aliceTraining,member,competency,daysAgo,slot,theme]);
 return lesson;
}

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);look=randomUUID();speed=randomUUID();
 await pool.query(`INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$3,$4,'observation','Observation et contrôles','Synthétique',2),($2,$3,$4,'vitesse','Vitesse','Synthétique',3)`,[look,speed,id.schoolA,school.curriculum]);
});
afterAll(async()=>{await app?.close();await pool?.end();});

describe('classement intelligent : préférence du moniteur',()=>{
 it('est désactivé par défaut, sans ligne en base, et refusé à un élève ou à un compte étranger',async()=>{
  const read=await call('GET',path);expect(read.statusCode,read.body).toBe(200);
  expect(read.json().data).toEqual({id:id.instructorMember,schoolId:id.schoolA,membershipId:id.instructorMember,version:1,mode:'MANUAL',order:[],rankedOn:null});
  expect(read.headers.etag).toBe('"1"');
  expect((await call('GET',path,undefined,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('GET',path,undefined,null,'demo-foreign')).statusCode).toBe(403);
  expect((await call('PUT',path,mode('SMART'),1,'demo-alice')).statusCode).toBe(403);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.observation_ranking')).rows[0].n).toBe(0);
 });
 it('un moniteur sans droit de gestion l’active : sans historique, le classement est l’ordre de l’école',async()=>{
  const body=mode('SMART'),saved=await call('PUT',path,body,1);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({version:2,mode:'SMART',order:manual});expect(saved.json().data.rankedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);expect(saved.headers.etag).toBe('"2"');
  // Rejeu de la même demande : même état, aucune seconde écriture.
  expect((await call('PUT',path,body,1)).json().data.version).toBe(2);
  expect((await call('PUT',path,{...body,mode:'MANUAL'},1)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('PUT',path,mode('MANUAL'),1)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',path,mode('MANUAL'),null)).statusCode).toBe(428);
  for(const invalid of [{operationId:randomUUID(),mode:'AUTO'},{operationId:randomUUID()},{...mode('SMART'),order:manual}])expect((await call('PUT',path,invalid,2)).statusCode).toBe(400);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_RANKING',resourceType:'ObservationRanking',resourceId:id.instructorMember,resourceVersion:2});
  expect((await pool.query('SELECT action FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationRankingSaved'}]);
  // La preuve appartient à son auteur.
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-other-instructor')).statusCode).toBeGreaterThanOrEqual(403);
 });
 it('le retour au mode manuel ne publie plus d’ordre et n’a jamais touché à l’ordre de l’école',async()=>{
  const before=(await call('GET',themes)).json().data;
  const off=await call('PUT',path,mode('MANUAL'),2);expect(off.statusCode,off.body).toBe(200);
  expect(off.json().data).toMatchObject({version:3,mode:'MANUAL',order:[],rankedOn:null});
  expect((await call('GET',themes)).json().data).toEqual(before);expect(before.version).toBe(1);
 });
});

describe('classement intelligent : habitudes',()=>{
 it('l’activation classe d’après l’historique déjà enregistré, quel que soit son rang',async()=>{
  // « Clignotants » est le douzième thème affiché ; « Vitesse » le septième. Les deux sont utilisés à chaque leçon depuis dix jours.
  for(let day=1;day<=10;day++){await pastLesson(day,1,'indicators',look,3);await pastLesson(day,3,'speed',speed,1);}
  const on=await call('PUT',path,mode('SMART'),3);expect(on.statusCode,on.body).toBe(200);
  const order=on.json().data.order as string[];
  expect(order.slice(0,2)).toEqual(['indicators','speed']);expect(order).toHaveLength(manual.length);expect([...order].sort()).toEqual([...manual].sort());
  // Les thèmes jamais utilisés gardent entre eux l'ordre de l'école.
  expect(order.slice(2)).toEqual(manual.filter(key=>!['indicators','speed'].includes(key)));
 });
 it('un usage isolé, une leçon très répétitive et un signalement annulé ne déplacent rien',async()=>{
  await pastLesson(1,5,'anticipation',look,1);await pastLesson(2,5,'motorway',look,40);
  const removed=await pastLesson(1,7,'give-way',look,2);await pastLesson(2,7,'give-way',look,2);
  await pool.query('UPDATE drivy.geo_observation SET removed_at=now(),text=NULL WHERE lesson_id=$1',[removed]);
  const before=(await call('GET',path)).json().data;await yesterday(id.instructorMember);
  const after=(await call('GET',path)).json().data;
  expect(after.order).toEqual(before.order);expect(after.version).toBe(before.version);
 });
 it('la première lecture du jour reclasse une fois ; un second appareil lit le même ordre',async()=>{
  // « Céder le passage » devient une habitude nette sur trois jours.
  for(let day=1;day<=3;day++)for(const slot of [9,11,13])await pastLesson(day,slot,'give-way',look,3);
  const stored=(await call('GET',path)).json().data,count=await refreshes();
  await yesterday(id.instructorMember);
  const [first,second]=await Promise.all([call('GET',path),call('GET',path)]);
  expect(first.statusCode,first.body).toBe(200);expect(second.statusCode,second.body).toBe(200);
  expect(first.json().data).toEqual(second.json().data);expect(await refreshes()).toBe(count+1);
  const data=first.json().data;
  expect(data.version).toBe(stored.version+1);expect(first.headers.etag).toBe(`"${data.version}"`);
  expect(data.order.indexOf('give-way')).toBeLessThan(stored.order.indexOf('give-way'));
  // Il passe « Vitesse », qu'il domine nettement, mais pas « Clignotants », trop proche : l'hystérésis garde le premier en place.
  expect(data.order.slice(0,3)).toEqual(['indicators','give-way','speed']);
  // Le reste de la journée, plus rien ne bouge et rien n'est recalculé.
  expect((await call('GET',path)).json().data).toEqual(data);expect(await refreshes()).toBe(count+1);
 });
 it('un signalement du jour ne déplace rien aujourd’hui, et garde le rang de sa tuile',async()=>{
  const lesson=randomUUID();
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
   VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,school.policy]);
  const before=(await call('GET',path)).json().data;
  const live=(themeKey:string|null,extra:Record<string,unknown>={})=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:look,text:'Recette',origin:'LIVE',observedAt:new Date().toISOString(),eventKind:'QUALIFIED',eventStatus:'TO_REWORK',...(themeKey?{themeKey}:{}),...extra});
  for(let index=0;index<5;index++)expect((await call('POST',`/lessons/${lesson}/geo-observations`,live('observation'))).statusCode).toBe(201);
  expect((await call('POST',`/lessons/${lesson}/geo-observations`,live(null))).statusCode).toBe(201);
  const rows=(await pool.query('SELECT theme_key,palette_position FROM drivy.geo_observation WHERE lesson_id=$1 ORDER BY created_at,id',[lesson])).rows;
  expect(rows.slice(0,5).map(row=>row.palette_position)).toEqual(Array(5).fill(before.order.indexOf('observation')+1));expect(rows[5]).toEqual({theme_key:null,palette_position:null});
  expect((await call('GET',path)).json().data).toEqual(before);
 });
 it('masquer un thème le retire aussitôt du classement ; réaffiché, il retrouve sa place, ou celle que son historique lui donne',async()=>{
  const settings=(await call('GET',themes,undefined,null,'demo-admin')).json().data,before=(await call('GET',path)).json().data;
  const hidden=settings.themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.visible&&theme.key!=='indicators'}));
  const saved=await call('PUT',themes,{operationId:randomUUID(),themes:hidden},settings.version,'demo-admin');expect(saved.statusCode,saved.body).toBe(200);
  const without=(await call('GET',path)).json().data;
  expect(without.order).toEqual(before.order.filter((key:string)=>key!=='indicators'));
  const original=settings.themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.visible}));
  const shown=await call('PUT',themes,{operationId:randomUUID(),themes:original},saved.json().data.version,'demo-admin');expect(shown.statusCode,shown.body).toBe(200);
  // Réaffiché le jour même : le classement enregistré le connaît encore.
  expect((await call('GET',path)).json().data.order).toEqual(before.order);
  // Masqué pendant un reclassement, il en sort ; réaffiché ensuite, il part en fin jusqu'au lendemain…
  const again=await call('PUT',themes,{operationId:randomUUID(),themes:hidden},shown.json().data.version,'demo-admin');expect(again.statusCode,again.body).toBe(200);
  await yesterday(id.instructorMember);expect((await call('GET',path)).json().data.order).not.toContain('indicators');
  const back=await call('PUT',themes,{operationId:randomUUID(),themes:original},again.json().data.version,'demo-admin');expect(back.statusCode,back.body).toBe(200);
  expect((await call('GET',path)).json().data.order.at(-1)).toBe('indicators');
  // … où son historique le replace d'un coup, sans la limite de montée.
  await yesterday(id.instructorMember);expect((await call('GET',path)).json().data.order.indexOf('indicators')).toBeLessThan(2);
 });
});

describe('classement intelligent : isolation',()=>{
 it('les habitudes d’un moniteur n’influencent ni un collègue, ni l’administration, ni une autre école',async()=>{
  const other=await call('GET',path,undefined,null,'demo-other-instructor');
  expect(other.json().data).toMatchObject({id:id.otherInstructorMember,version:1,mode:'MANUAL',order:[]});
  const on=await call('PUT',path,mode('SMART'),1,'demo-other-instructor');expect(on.statusCode,on.body).toBe(200);
  expect(on.json().data.order).toEqual(manual);
  expect((await call('GET',path,undefined,null,'demo-admin')).json().data).toMatchObject({id:id.adminMember,version:1,mode:'MANUAL'});
  // Le même compte, administrateur d'une autre école, y garde un classement distinct.
  const elsewhere=await call('GET',schoolB);expect(elsewhere.statusCode,elsewhere.body).toBe(200);
  expect(elsewhere.json().data).toMatchObject({id:id.instructorMemberB,schoolId:id.schoolB,version:1,mode:'MANUAL',order:[]});
  expect((await call('GET',schoolB,undefined,null,'demo-admin')).statusCode).toBe(403);
  expect((await call('GET',path)).json().data.mode).toBe('SMART');
 });
 it('la base refuse à un collègue la lecture et l’écriture du classement d’un autre',async()=>{
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject','demo-other-instructor',true),set_config('app.school_id',$2,true),set_config('app.person_id',$3,true),set_config('app.membership_id',$4,true)",[issuer,id.schoolA,id.otherInstructor,id.otherInstructorMember]);
   expect((await db.query('SELECT membership_id FROM drivy.observation_ranking')).rows).toEqual([{membership_id:id.otherInstructorMember}]);
   expect((await db.query("UPDATE drivy.observation_ranking SET mode='MANUAL' WHERE membership_id=$1",[id.instructorMember])).rowCount).toBe(0);
   // Les usages lus sont ceux du compte courant : aucun pour ce collègue.
   expect((await db.query("SELECT * FROM drivy.observation_theme_usage($1,'Europe/Zurich')",[id.schoolA])).rows).toEqual([]);
   await db.query('ROLLBACK');
  }finally{db.release();}
 });
});
