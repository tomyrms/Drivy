import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {loadPreferences} from '../src/observation-preferences.js';
import {observationThemes} from '../src/observation-themes.js';

/** R08 (#467) : classement intelligent du compte, communs à plusieurs écoles, et « Recommencer l'apprentissage » durable. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>,policyB:string;
const prefs='/observation-preferences';
const manual=observationThemes.filter(theme=>theme.defaultVisible).map(theme=>theme.key as string);
const save=(body:Record<string,unknown>={})=>({operationId:randomUUID(),...body});
/** Vieillit le classement du compte : la prochaine lecture est la première d'un nouveau jour. */
let age=0;
const yesterday=(person:string)=>pool.query("UPDATE drivy.person_observation_preference SET ranked_on=(now() AT TIME ZONE 'Europe/Zurich')::date-$2::int WHERE person_id=$1",[person,++age]);
interface Where {school:string;training:string;learner:string;learnerPerson:string;member:string;policy:string}
const inA=():Where=>({school:id.schoolA,training:id.aliceTraining,learner:id.aliceLearner,learnerPerson:id.alice,member:id.instructorMember,policy:school.policy});
const inB=():Where=>({school:id.schoolB,training:id.foreignTraining,learner:id.foreignLearner,learnerPerson:id.foreign,member:id.instructorMemberB,policy:policyB});
/** Une leçon passée avec `uses` signalements d'un thème. `observedDaysAgo` distingue le geste observé de sa réception (file hors ligne). */
async function pastLesson(where:Where,daysAgo:number,slot:number,theme:string,uses:number,observedDaysAgo=daysAgo){
 const lesson=randomUUID();
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  VALUES($1,$2,$3,$4,$5,$6,now()-make_interval(days=>$7,hours=>$8),now()-make_interval(days=>$7,hours=>$8)+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$9,'{"mode":"UNIT_PRICE"}')`,
  [lesson,where.school,where.training,where.learner,where.learnerPerson,where.member,daysAgo,slot,where.policy]);
 for(let index=0;index<uses;index++)await pool.query(`INSERT INTO drivy.geo_observation(school_id,lesson_id,training_id,author_membership_id,competency_id,text,origin,observed_at,created_at,event_kind,event_status,theme_key)
  VALUES($1,$2,$3,$4,NULL,'Recette','LIVE',now()-make_interval(days=>$5,hours=>$7),now()-make_interval(days=>$6,hours=>$7),'QUALIFIED','TO_REWORK',$8)`,[where.school,lesson,where.training,where.member,observedDaysAgo,daysAgo,slot,theme]);
}

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);policyB=randomUUID();
 await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette uniquement','Recette uniquement','{}',true,'Synthétique',$3,now())`,[policyB,id.schoolB,id.instructorMemberB]);
});
afterAll(async()=>{await app?.close();await pool?.end();});

describe('classement du compte, communes à plusieurs écoles',()=>{
 it('les gestes faits dans toutes les écoles du compte comptent ; ceux d’un collègue, non',async()=>{
  // « Clignotants » est utilisé dans l'école A, « Vitesse » dans l'école B : le classement du compte les réunit.
  for(let day=1;day<=10;day++){await pastLesson(inA(),day,1,'indicators',3);await pastLesson(inB(),day,3,'speed',1);}
  for(let day=1;day<=10;day++)await pastLesson({...inA(),member:id.otherInstructorMember},day,5,'motorway',6);
  const on=await call('PUT',prefs,save({mode:'SMART'}),1);expect(on.statusCode,on.body).toBe(200);
  const palette=on.json().data.palette as string[];
  expect(palette.slice(0,2)).toEqual(['indicators','speed']);expect(palette).toHaveLength(manual.length);expect([...palette].sort()).toEqual([...manual].sort());
  expect(on.json().data).toMatchObject({version:2,mode:'SMART',learning:{generation:0,since:null}});
  // Le même classement est lu depuis l'autre école, et en miroir dans l'ancienne route.
  expect((await call('GET',`/v1/schools/${id.schoolB}/observation-preferences`)).json().data).toMatchObject({version:2,mode:'SMART'});
  expect((await call('GET','/observation-ranking')).json().data).toMatchObject({mode:'SMART',version:2,order:palette});
  // Le collègue n'est pas influencé par ces gestes.
  const other=await call('PUT',prefs,save({mode:'SMART'}),1,'demo-other-instructor');expect(other.statusCode,other.body).toBe(200);
  expect(other.json().data.palette[0]).toBe('motorway');expect(other.json().data.palette.indexOf('indicators')).toBeGreaterThan(1);
 });
 it('la première lecture du jour reclasse une fois ; un second appareil, ou l’autre école, lit le même ordre',async()=>{
  const count=async()=>(await pool.query("SELECT count(*)::int AS n FROM drivy.operation WHERE command_type='REFRESH_OBSERVATION_RANKING'")).rows[0].n as number;
  for(let day=1;day<=3;day++)for(const slot of [9,11,13])await pastLesson(inB(),day,slot,'give-way',3);
  const stored=(await call('GET',prefs)).json().data,before=await count();
  await yesterday(id.instructor);
  const [first,second]=await Promise.all([call('GET',prefs),call('GET',prefs)]);
  expect(first.statusCode,first.body).toBe(200);expect(second.statusCode,second.body).toBe(200);
  expect(first.json().data).toEqual(second.json().data);expect(await count()).toBe(before+1);
  const data=first.json().data;expect(data.version).toBe(stored.version+1);expect(data.palette.indexOf('give-way')).toBeLessThan(stored.palette.indexOf('give-way'));
  // L'autre école et l'ancienne route lisent la même chose, sans nouveau calcul.
  expect((await call('GET',`/v1/schools/${id.schoolB}/observation-preferences`)).json().data.palette).toEqual(data.palette);
  expect((await call('GET','/observation-ranking')).json().data.order).toEqual(data.palette);expect(await count()).toBe(before+1);
 });
});

describe('Recommencer l’apprentissage',()=>{
 let before:{version:number;palette:string[]};
 it('crée une borne durable : mode et ordre manuel conservés, classement reparti des références, aucune donnée supprimée',async()=>{
  before=(await call('GET',prefs)).json().data;
  const observations=(await pool.query('SELECT count(*)::int AS n FROM drivy.geo_observation')).rows[0].n as number,body=save();
  const reset=await call('POST',`${prefs}/learning-reset`,body,before.version);expect(reset.statusCode,reset.body).toBe(200);
  const data=reset.json().data;
  expect(data).toMatchObject({version:before.version+1,mode:'SMART',learning:{generation:1}});expect(data.learning.since).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  expect(data.palette).toEqual(manual);expect(data.palette).not.toEqual(before.palette);expect(reset.headers.etag).toBe(`"${before.version+1}"`);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.geo_observation')).rows[0].n).toBe(observations);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.geo_observation WHERE removed_at IS NOT NULL')).rows[0].n).toBe(0);
  // Rejeu sans seconde remise à zéro, conflit de version, preuve et audit.
  expect((await call('POST',`${prefs}/learning-reset`,body,before.version)).json().data.learning.generation).toBe(1);
  expect((await call('POST',`${prefs}/learning-reset`,save(),before.version)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',`${prefs}/learning-reset`,save(),null)).statusCode).toBe(428);
  expect((await call('POST',`${prefs}/learning-reset`,{...body,mode:'MANUAL'},before.version)).statusCode).toBe(400);
  expect((await pool.query('SELECT action,changed_fields FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationLearningReset',changed_fields:['learning']}]);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'RESET_OBSERVATION_LEARNING',resourceType:'ObservationPreferences',resourceId:id.instructor});
 });
 it('aucun chemin ne relit l’historique : ni le reclassement du jour, ni un geste ancien reçu après coup',async()=>{
  const reset=(await call('GET',prefs)).json().data;
  // La remise à zéro date de cinq jours : tout l'historique ci-dessus lui est antérieur (recalé de trente jours).
  await pool.query("UPDATE drivy.geo_observation SET observed_at=observed_at-interval '30 days',created_at=created_at-interval '30 days'");
  // Un geste observé avant la borne, mais reçu seulement hier (file hors ligne), reste ignoré.
  await pool.query("UPDATE drivy.person_observation_preference SET learning_since=now()-interval '5 days' WHERE person_id=$1",[id.instructor]);
  for(let day=1;day<=3;day++)for(const slot of [9,11])await pastLesson(inA(),day,slot,'anticipation',6,day+8);
  await yesterday(id.instructor);
  const stale=(await call('GET',prefs)).json().data;
  expect(stale.palette).toEqual(reset.palette);
  // Un geste observé après la borne compte : « Céder le passage » (gestes d'avant la borne ignorés) monte au-dessus de sa place d'origine.
  for(let day=1;day<=3;day++)for(const slot of [15,17,19])await pastLesson(inB(),day,slot,'give-way',3);
  await yesterday(id.instructor);
  const learned=(await call('GET',prefs)).json().data;
  expect(learned.palette.indexOf('give-way')).toBeLessThan(manual.indexOf('give-way'));
  // L'historique d'avant la borne (Clignotants, Vitesse) n'a pas repris la tête.
  expect(learned.palette.indexOf('indicators')).toBeGreaterThanOrEqual(learned.palette.indexOf('give-way'));
  expect(learned.palette.slice(0,2)).not.toEqual(['indicators','speed']);
  expect(learned.learning.generation).toBe(1);
 });
 it('désactiver puis réactiver le mode intelligent ne rend pas non plus l’historique',async()=>{
  const current=(await call('GET',prefs)).json().data;
  const off=await call('PUT',prefs,save({mode:'MANUAL'}),current.version);expect(off.statusCode,off.body).toBe(200);expect(off.json().data.palette).toEqual(manual);
  const on=await call('PUT',prefs,save({mode:'SMART'}),off.json().data.version);expect(on.statusCode,on.body).toBe(200);
  expect(on.json().data.learning.generation).toBe(1);expect(on.json().data.palette.slice(0,2)).not.toEqual(['indicators','speed']);
 });
 it('en mode manuel, la remise à zéro est aussi durable ; un élève ne peut pas la demander',async()=>{
  const other=(await call('GET',prefs,undefined,null,'demo-other-instructor')).json().data;
  const reset=await call('POST',`${prefs}/learning-reset`,save(),other.version,'demo-other-instructor');expect(reset.statusCode,reset.body).toBe(200);
  expect(reset.json().data).toMatchObject({mode:'SMART',learning:{generation:1}});expect(reset.json().data.palette).toEqual(manual);
  const manualAccount=await call('PUT',prefs,save({mode:'MANUAL'}),reset.json().data.version,'demo-other-instructor');expect(manualAccount.statusCode).toBe(200);
  const again=await call('POST',`${prefs}/learning-reset`,save(),manualAccount.json().data.version,'demo-other-instructor');
  expect(again.json().data).toMatchObject({mode:'MANUAL',palette:manual,rankedOn:null,learning:{generation:2}});
  expect((await call('POST',`${prefs}/learning-reset`,save(),1,'demo-alice')).statusCode).toBe(403);
 });
 it('après la remise à zéro, le classement est daté d’aujourd’hui : aucun rafraîchissement ancien n’est dû',async()=>{
  // La génération entre dans l'identifiant de l'opération quotidienne et est relue sous verrou : un rafraîchissement en vol ne survit pas à la remise à zéro.
  const account=(await call('GET',prefs)).json().data,generation=account.learning.generation;
  await yesterday(id.instructor);
  const reset=await call('POST',`${prefs}/learning-reset`,save(),account.version);expect(reset.statusCode,reset.body).toBe(200);
  expect(reset.json().data.learning.generation).toBe(generation+1);
  // Après la remise à zéro, le classement est daté d'aujourd'hui : plus aucun rafraîchissement ancien n'est dû.
  const count=async()=>(await pool.query("SELECT count(*)::int AS n FROM drivy.operation WHERE command_type='REFRESH_OBSERVATION_RANKING'")).rows[0].n as number;
  const before=await count();
  expect((await call('GET',prefs)).json().data.palette).toEqual(reset.json().data.palette);expect(await count()).toBe(before);
 });
});

describe('classement du compte sur le catalogue complet',()=>{
 const themesRoute='/observation-themes';
 const fullRank=async()=>(await pool.query('SELECT ranked_order FROM drivy.person_observation_preference WHERE person_id=$1',[id.instructor])).rows[0].ranked_order as string[];
 /** Masque (ou réaffiche) « Placement » dans la référence de l'école A, qui reste en visibilité imposée. */
 const setPlacement=async(visible:boolean)=>{
  const school=(await call('GET',themesRoute,undefined,null,'demo-admin')).json().data;
  const saved=await call('PUT',themesRoute,save({themes:school.themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.key==='placement'?visible:theme.visible}))}),school.version,'demo-admin');
  expect(saved.statusCode,saved.body).toBe(200);
 };
 it('masquer un thème dans A puis ouvrir B ne détruit ni son rang global ni ses habitudes, même après un rafraîchissement fait depuis A',async()=>{
  // Les habitudes de « Placement » sont acquises dans l'école B, où il est affiché ; la borne d'apprentissage est reculée pour les compter.
  await pool.query("UPDATE drivy.person_observation_preference SET learning_since=now()-interval '60 days' WHERE person_id=$1",[id.instructor]);
  for(let day=1;day<=10;day++)for(const slot of [21,22,23])await pastLesson(inB(),day,slot,'placement',5);
  for(let round=0;round<4;round++){await yesterday(id.instructor);expect((await call('GET',prefs)).statusCode).toBe(200);}
  const rankInB=(await fullRank()).indexOf('placement');
  expect(rankInB).toBeGreaterThanOrEqual(0);
  // L'école A masque « Placement ». Un nouveau jour : le classement est refait DEPUIS A.
  await setPlacement(false);
  await yesterday(id.instructor);
  const fromA=await call('GET',prefs);expect(fromA.statusCode,fromA.body).toBe(200);
  expect(fromA.json().data.palette).not.toContain('placement');
  const ranked=await fullRank();
  // Le classement du compte garde les dix-huit thèmes, « Placement » compris, à un rang qui n'a pas reculé.
  expect(ranked).toHaveLength(18);expect(ranked.indexOf('placement')).toBeGreaterThanOrEqual(0);expect(ranked.indexOf('placement')).toBeLessThanOrEqual(rankInB);
  // B (où il est affiché) montre ce même classement, filtré par sa propre visibilité : « Placement » est là, à son rang.
  const inSchoolB=(await call('GET',`/v1/schools/${id.schoolB}/observation-preferences`)).json().data;
  expect(inSchoolB.palette).toContain('placement');
  expect(inSchoolB.palette).toEqual(ranked.filter(key=>inSchoolB.themes.find((theme:{key:string;visible:boolean})=>theme.key===key)!.visible));
  // Les autres chemins qui écrivent le classement partent eux aussi du catalogue complet.
  const mode=await call('PUT',prefs,save({mode:'MANUAL'}),fromA.json().data.version);expect(mode.statusCode,mode.body).toBe(200);
  const again=await call('PUT',prefs,save({mode:'SMART'}),mode.json().data.version);expect(again.statusCode,again.body).toBe(200);
  expect(await fullRank()).toHaveLength(18);
  const learning=await call('POST',`${prefs}/learning-reset`,save(),again.json().data.version);expect(learning.statusCode,learning.body).toBe(200);
  expect(await fullRank()).toHaveLength(18);expect(learning.json().data.palette).not.toContain('placement');
  await setPlacement(true);
 });
});

describe('course entre « Recommencer l’apprentissage » et un recalcul quotidien démarré avant',()=>{
 it('le recalcul périmé n’écrit rien : l’ancien apprentissage n’est pas réintroduit',async()=>{
  const log={warn:()=>undefined} as never;
  // Un classement appris, et un nouveau jour : la prochaine lecture est due.
  await pool.query("UPDATE drivy.person_observation_preference SET learning_since=now()-interval '60 days' WHERE person_id=$1",[id.instructor]);
  for(let day=1;day<=10;day++)for(const slot of [20])await pastLesson(inA(),day,slot,'braking',4);
  await yesterday(id.instructor);
  const account=(await call('GET',prefs)).json().data as {version:number;palette:string[];learning:{generation:number}};
  await yesterday(id.instructor);
  let resetPalette:string[]=[];
  const refresh=await loadPreferences(pool,{issuer,subject:'demo-instructor'},id.schoolA,log,'race',async()=>{
   // Entre la lecture (qui a vu le recalcul dû) et son exécution, le moniteur recommence l'apprentissage.
   const reset=await call('POST',`${prefs}/learning-reset`,save(),account.version);expect(reset.statusCode,reset.body).toBe(200);resetPalette=reset.json().data.palette;
  });
  const after=(await call('GET',prefs)).json().data;
  expect(after.learning.generation).toBe(account.learning.generation+1);
  // La remise à zéro a repris la main : classement des références, version seulement avancée par elle, rien écrit par le recalcul périmé.
  expect(after.palette).toEqual(resetPalette);expect(refresh.data.palette).toEqual(resetPalette);expect(after.version).toBe(account.version+1);
  expect(after.rankedOn).toBe(new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Zurich'}));
  // Les gestes d'avant la remise à zéro n'ont aucune influence : le classement est celui des références seules.
  expect(after.palette).toEqual((await call('GET',prefs)).json().data.palette);
 });
});
