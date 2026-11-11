import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {observationThemes} from '../src/observation-themes.js';

/** R08 (#465, #466, #467) : politique de l'école, préférences du compte, palette effective. Base PostgreSQL réelle. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
const prefs='/observation-preferences',themes='/observation-themes',prefsB=`/v1/schools/${id.schoolB}/observation-preferences`,themesB=`/v1/schools/${id.schoolB}/observation-themes`;
const defaults=observationThemes.map(theme=>({key:theme.key as string,visible:theme.defaultVisible as boolean}));
const manual=defaults.filter(theme=>theme.visible).map(theme=>theme.key);
const save=(body:Record<string,unknown>)=>({operationId:randomUUID(),...body});
const first=(key:string,hide:string[]=[],show:string[]=[])=>[defaults.find(theme=>theme.key===key)!,...defaults.filter(theme=>theme.key!==key)]
 .map(theme=>({...theme,visible:show.includes(theme.key)?true:hide.includes(theme.key)?false:theme.visible}));
const rows=async()=>(await pool.query('SELECT count(*)::int AS n FROM drivy.person_observation_preference')).rows[0].n as number;
let validate:{envelope:(value:unknown)=>boolean;save:(value:unknown)=>boolean;reset:(value:unknown)=>boolean;legacy:(value:unknown)=>boolean;school:(value:unknown)=>boolean;schoolCommand:(value:unknown)=>boolean;errors:()=>string};

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);
 const contract=JSON.parse(await readFile(new URL('../contracts/observation-preferences.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 const compile=(name:string)=>ajv.compile({$ref:`${contract.$id}#/$defs/${name}`});
 const compiled={envelope:compile('Envelope'),save:compile('SaveCommand'),reset:compile('ResetCommand'),legacy:compile('LegacyRanking'),school:compile('SchoolThemes'),schoolCommand:compile('SchoolThemesCommand')};
 let last=compiled.envelope;
 const wrap=(name:keyof typeof compiled)=>(value:unknown)=>{last=compiled[name];return compiled[name](value) as boolean;};
 validate={envelope:wrap('envelope'),save:wrap('save'),reset:wrap('reset'),legacy:wrap('legacy'),school:wrap('school'),schoolCommand:wrap('schoolCommand'),errors:()=>JSON.stringify(last.errors)};
});
afterAll(async()=>{await app?.close();await pool?.end();});

describe('compte sans préférence',()=>{
 it('rend la configuration de l’école, version 1, sans ligne en base ; le contrat est respecté',async()=>{
  const read=await call('GET',prefs);expect(read.statusCode,read.body).toBe(200);
  const data=read.json().data;
  expect(data).toMatchObject({id:id.instructor,schoolId:id.schoolA,version:1,personalizationAllowed:false,customized:false,mode:'MANUAL',rankedOn:null,learning:{generation:0,since:null},adoption:null});
  expect(data.palette).toEqual(manual);expect(data.themes).toHaveLength(18);expect(read.headers.etag).toBe('"1"');
  expect(validate.envelope(read.json()),validate.errors()).toBe(true);
  expect(await rows()).toBe(0);
  // L'administrateur de l'école a lui aussi son propre compte.
  expect((await call('GET',prefs,undefined,null,'demo-admin')).json().data).toMatchObject({id:id.admin,version:1});
 });
 it('refuse la lecture et l’écriture à un élève et à un compte étranger',async()=>{
  for(const subject of ['demo-alice','demo-foreign']){
   expect((await call('GET',prefs,undefined,null,subject)).statusCode).toBe(403);
   expect((await call('PUT',prefs,save({mode:'SMART'}),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
   expect((await call('POST',`${prefs}/learning-reset`,save({}),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
  }
  expect(await rows()).toBe(0);
 });
});

describe('visibilité imposée par l’école (état de toutes les écoles existantes)',()=>{
 it('refuse l’ordre et l’affichage personnels, sans rien écrire',async()=>{
  const refused=await call('PUT',prefs,save({themes:first('speed')}),1);
  expect(refused.statusCode,refused.body).toBe(403);expect(refused.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  const reset=await call('POST',`${prefs}/presentation-reset`,save({}),1);expect(reset.statusCode,reset.body).toBe(403);expect(reset.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  // L'administrateur de l'école n'y échappe pas : il change la politique, pas son propre compte.
  expect((await call('PUT',prefs,save({themes:first('speed')}),1,'demo-admin')).statusCode).toBe(403);
  expect(await rows()).toBe(0);
 });
 it('autorise le mode intelligent, qui classe la liste imposée sans la modifier',async()=>{
  const saved=await call('PUT',prefs,save({mode:'SMART'}),1);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({version:2,mode:'SMART',customized:false,personalizationAllowed:false});
  expect(saved.json().data.palette).toEqual(manual);expect(saved.json().data.rankedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  const back=await call('PUT',prefs,save({mode:'MANUAL'}),2);expect(back.statusCode,back.body).toBe(200);expect(back.json().data).toMatchObject({version:3,mode:'MANUAL',rankedOn:null});
 });
});

describe('visibilité personnalisable',()=>{
 it('seul l’administrateur ouvre la politique ; un moniteur ne le peut pas',async()=>{
  const current=(await call('GET',themes,undefined,null,'demo-admin')).json().data;expect(current).toMatchObject({personalizationAllowed:false,canManage:true,version:1});
  const body=save({themes:defaults,personalizationAllowed:true});
  expect((await call('PUT',themes,body,1)).statusCode).toBe(403);
  const opened=await call('PUT',themes,body,1,'demo-admin');expect(opened.statusCode,opened.body).toBe(200);
  expect(opened.json().data).toMatchObject({version:2,personalizationAllowed:true});
  expect(validate.school(opened.json().data),validate.errors()).toBe(true);expect(validate.schoolCommand(body),validate.errors()).toBe(true);
  // Le moniteur voit la politique sans pouvoir la gérer.
  expect((await call('GET',themes)).json().data).toMatchObject({personalizationAllowed:true,canManage:false});
 });
 it('le moniteur enregistre son ordre et son affichage ; la configuration de l’école n’est pas touchée',async()=>{
  const before=(await call('GET',themes)).json().data,body=save({themes:first('speed',['motorway'],['braking'])});
  expect(validate.save(body),validate.errors()).toBe(true);
  const saved=await call('PUT',prefs,body,3);expect(saved.statusCode,saved.body).toBe(200);
  const data=saved.json().data;expect(data).toMatchObject({version:4,customized:true,mode:'MANUAL',personalizationAllowed:true});
  expect(data.palette[0]).toBe('speed');expect(data.palette).toContain('braking');expect(data.palette).not.toContain('motorway');
  expect(data.themes.find((theme:{key:string})=>theme.key==='braking').visible).toBe(true);
  expect(saved.headers.etag).toBe('"4"');expect(validate.envelope(saved.json()),validate.errors()).toBe(true);
  // La palette est calculée : l'école garde sa référence, et chaque lecture rend le même résultat.
  expect((await call('GET',themes)).json().data).toEqual(before);
  expect((await call('GET',prefs)).json().data).toEqual(data);
  // Un collègue et l'administrateur gardent la configuration de l'école.
  expect((await call('GET',prefs,undefined,null,'demo-other-instructor')).json().data).toMatchObject({customized:false,version:1,palette:manual});
  expect((await call('GET',prefs,undefined,null,'demo-admin')).json().data).toMatchObject({customized:false,version:1});
 });
 it('version, idempotence, preuve, audit et corps invalides',async()=>{
  const body=save({themes:first('observation')}),saved=await call('PUT',prefs,body,4);expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.version).toBe(5);
  // Rejeu : même réponse, aucune seconde écriture ; un autre contenu sous la même opération est refusé.
  const replay=await call('PUT',prefs,body,4);expect(replay.statusCode,replay.body).toBe(200);expect(replay.json().data.version).toBe(5);
  expect((await call('PUT',prefs,{...body,mode:'SMART'},4)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('PUT',prefs,save({themes:first('signage')}),4)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',prefs,save({themes:first('signage')}),null)).statusCode).toBe(428);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_PRESENTATION',resourceType:'ObservationPreferences',resourceId:id.instructor,resourceVersion:5});
  expect((await pool.query('SELECT action,changed_fields FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationPresentationSaved',changed_fields:['order','visibility']}]);
  // La preuve appartient à son auteur.
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-other-instructor')).statusCode).toBeGreaterThanOrEqual(403);
  const bad=[save({}),save({themes:defaults.slice(1)}),save({themes:[defaults[0],...defaults.slice(0,17)]}),save({themes:defaults.map(theme=>({...theme,visible:false}))}),
   save({themes:[{key:'unknown',visible:true},...defaults.slice(1)]}),save({mode:'AUTO'}),save({mode:'SMART',order:manual}),{mode:'SMART'}];
  for(const invalid of bad)expect((await call('PUT',prefs,invalid as never,5)).statusCode,JSON.stringify(invalid)).toBe(400);
  expect((await call('GET',prefs)).json().data.version).toBe(5);
 });
 it('deux enregistrements concurrents de la même version : un seul passe',async()=>{
  const writes=await Promise.all([call('PUT',prefs,save({themes:first('braking')}),5),call('PUT',prefs,save({themes:first('signage')}),5)]);
  expect(writes.map(response=>response.statusCode).sort()).toEqual([200,412]);expect((await call('GET',prefs)).json().data.version).toBe(6);
 });
 it('le compte est commun à ses écoles : même ordre dans l’école B quand elle est personnalisable, école inchangée sinon',async()=>{
  const mine=(await call('GET',prefs)).json().data;
  const imposed=await call('GET',prefsB);expect(imposed.statusCode,imposed.body).toBe(200);
  expect(imposed.json().data).toMatchObject({id:id.instructor,schoolId:id.schoolB,version:mine.version,personalizationAllowed:false,customized:false,palette:manual});
  expect((await call('GET',prefsB,undefined,null,'demo-admin')).statusCode).toBe(403);
  const opened=await call('PUT',themesB,save({themes:defaults,personalizationAllowed:true}),1);expect(opened.statusCode,opened.body).toBe(200);
  const shared=await call('GET',prefsB);expect(shared.json().data).toMatchObject({schoolId:id.schoolB,version:mine.version,customized:true,palette:mine.palette});
  expect(await rows()).toBe(1);
  // Écrire depuis l'école B change le compte, donc aussi l'école A.
  const fromB=await call('PUT',prefsB,save({themes:first('anticipation')}),mine.version);expect(fromB.statusCode,fromB.body).toBe(200);
  expect((await call('GET',prefs)).json().data).toMatchObject({version:mine.version+1,customized:true});expect((await call('GET',prefs)).json().data.palette[0]).toBe('anticipation');
  // Même une école qui ne connaît pas la personne comme moniteur ne la lit pas.
  expect((await call('GET',prefsB,undefined,null,'demo-other-instructor')).statusCode).toBe(403);
 });
 it('une école qui impose de nouveau son affichage reprend la main sans effacer les réglages du compte',async()=>{
  const mine=(await call('GET',prefs)).json().data,current=(await call('GET',themes,undefined,null,'demo-admin')).json().data;
  const closed=await call('PUT',themes,save({themes:defaults,personalizationAllowed:false}),current.version,'demo-admin');expect(closed.statusCode,closed.body).toBe(200);
  const imposed=(await call('GET',prefs)).json().data;
  expect(imposed).toMatchObject({customized:false,personalizationAllowed:false,version:mine.version});expect(imposed.palette).toEqual(manual);
  expect((await pool.query('SELECT theme_order[1] AS head FROM drivy.person_observation_preference WHERE person_id=$1',[id.instructor])).rows[0].head).toBe('anticipation');
  expect((await call('PUT',prefs,save({themes:first('speed')}),mine.version)).json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  const reopened=await call('PUT',themes,save({themes:defaults,personalizationAllowed:true}),closed.json().data.version,'demo-admin');expect(reopened.statusCode,reopened.body).toBe(200);
  expect((await call('GET',prefs)).json().data.palette[0]).toBe('anticipation');
 });
 it('rétablir remet la configuration de l’école, sans toucher au mode ni à l’apprentissage',async()=>{
  const mode=await call('PUT',prefs,save({mode:'SMART'}),(await call('GET',prefs)).json().data.version);expect(mode.statusCode,mode.body).toBe(200);
  const before=mode.json().data,body=save({});expect(validate.reset(body)).toBe(true);
  const reset=await call('POST',`${prefs}/presentation-reset`,body,before.version);expect(reset.statusCode,reset.body).toBe(200);
  expect(reset.json().data).toMatchObject({customized:false,mode:'SMART',version:before.version+1,learning:before.learning});
  expect(reset.json().data.themes.map((theme:{key:string})=>theme.key)).toEqual(defaults.map(theme=>theme.key));
  expect((await pool.query('SELECT theme_order,hidden_themes FROM drivy.person_observation_preference WHERE person_id=$1',[id.instructor])).rows[0]).toEqual({theme_order:null,hidden_themes:null});
  // Rejeu, conflit de version, preuve et audit.
  expect((await call('POST',`${prefs}/presentation-reset`,body,before.version)).json().data.version).toBe(before.version+1);
  expect((await call('POST',`${prefs}/presentation-reset`,save({}),before.version)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',`${prefs}/presentation-reset`,save({}),null)).statusCode).toBe(428);
  expect((await call('POST',`${prefs}/presentation-reset`,{...body,extra:true},before.version)).statusCode).toBe(400);
  expect((await pool.query('SELECT action FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationPresentationReset'}]);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'RESET_OBSERVATION_PRESENTATION',resourceType:'ObservationPreferences',resourceId:id.instructor});
 });
});

describe('droits scolaires relus côté serveur',()=>{
 it('l’ancien droit « Gérer les signalements » ne donne rien, ni sur l’école ni sur le compte d’un tiers',async()=>{
  const member=(await call('GET','/members',undefined,null,'demo-admin')).json().data.items.find((item:{id:string})=>item.id===id.otherInstructorMember);
  const granted=await call('PATCH',`/members/${id.otherInstructorMember}`,{operationId:randomUUID(),roles:member.roles,grants:['MANAGE_OBSERVATION_THEMES'],reason:'Recette'},member.version,'demo-admin');expect(granted.statusCode,granted.body).toBe(200);
  const current=(await call('GET',themes,undefined,null,'demo-other-instructor')).json().data;expect(current.canManage).toBe(false);
  const refused=await call('PUT',themes,save({themes:defaults,personalizationAllowed:false}),current.version,'demo-other-instructor');
  expect(refused.statusCode).toBe(403);expect(refused.json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  expect((await call('GET',themes,undefined,null,'demo-other-instructor')).json().data.personalizationAllowed).toBe(true);
 });
 it('la base isole la ligne de chaque compte, et ne la montre pas depuis une école où la personne n’est pas moniteur',async()=>{
  const db=await pool.connect();
  const as=async(subject:string,person:string,school:string,run:()=>Promise<void>)=>{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true),set_config('app.person_id',$4,true)",[issuer,subject,school,person]);
   try{await run();}finally{await db.query('ROLLBACK');}
  };
  try{
   await as('demo-instructor',id.instructor,id.schoolA,async()=>{expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([{person_id:id.instructor}]);});
   // Un collègue ne lit ni n'écrit la ligne d'un autre.
   await as('demo-other-instructor',id.otherInstructor,id.schoolA,async()=>{
    expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([]);
    expect((await db.query("UPDATE drivy.person_observation_preference SET mode='MANUAL' WHERE person_id=$1",[id.instructor])).rowCount).toBe(0);
    await expect(db.query("INSERT INTO drivy.person_observation_preference(person_id,version) VALUES($1,2)",[id.instructor])).rejects.toThrow();
   });
   // L'administration de l'école ne lit pas non plus les préférences d'un moniteur.
   await as('demo-admin',id.admin,id.schoolA,async()=>{expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([]);});
   // Un élève n'est jamais moniteur : même sa propre ligne n'existerait pas pour lui.
   await as('demo-alice',id.alice,id.schoolA,async()=>{
    await expect(db.query("INSERT INTO drivy.person_observation_preference(person_id,version) VALUES($1,2)",[id.alice])).rejects.toThrow(/row-level security/);
   });
  }finally{db.release();}
  // Les anciennes lignes par école ne s'écrivent plus.
  const legacy=await pool.connect();
  try{
   await legacy.query('BEGIN');await legacy.query('SET LOCAL ROLE drivy_app');
   await expect(legacy.query("UPDATE drivy.observation_ranking SET mode='MANUAL'")).rejects.toThrow(/permission denied/);
   await legacy.query('ROLLBACK');
  }finally{legacy.release();}
 });
});

describe('anciennes routes',()=>{
 it('/observation-ranking garde sa forme et écrit le compte',async()=>{
  const read=await call('GET','/observation-ranking');expect(read.statusCode,read.body).toBe(200);
  const account=(await call('GET',prefs)).json().data;
  expect(read.json().data).toMatchObject({id:id.instructorMember,membershipId:id.instructorMember,schoolId:id.schoolA,version:account.version,mode:account.mode});
  expect(validate.legacy(read.json().data),validate.errors()).toBe(true);
  const off=save({mode:'MANUAL'}),saved=await call('PUT','/observation-ranking',off,account.version);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({mode:'MANUAL',order:[],rankedOn:null,version:account.version+1});
  expect((await call('GET',prefs)).json().data).toMatchObject({mode:'MANUAL',version:account.version+1});
  expect((await call('GET',`/operations/${off.operationId}`)).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_RANKING',resourceId:id.instructor});
  const on=await call('PUT','/observation-ranking',save({mode:'SMART'}),account.version+1);expect(on.json().data.mode).toBe('SMART');expect(on.json().data.order).toHaveLength(manual.length);
  expect(await pool.query('SELECT 1 FROM drivy.observation_ranking').then(result=>result.rowCount)).toBe(0);
 });
 it('un ancien client de /observation-themes qui n’envoie pas la politique la laisse inchangée',async()=>{
  const current=(await call('GET',themes,undefined,null,'demo-admin')).json().data;
  const saved=await call('PUT',themes,{operationId:randomUUID(),themes:defaults},current.version,'demo-admin');
  expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.personalizationAllowed).toBe(current.personalizationAllowed);
 });
});

describe('rang noté au moment du geste',()=>{
 it('le signalement garde le rang de sa tuile dans la palette effective du compte',async()=>{
  const lesson=randomUUID();
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
   VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,school.policy]);
  const account=(await call('GET',prefs)).json().data;
  const saved=await call('PUT',prefs,save({themes:first('motorway'),mode:'MANUAL'}),account.version);expect(saved.statusCode,saved.body).toBe(200);
  const palette=saved.json().data.palette as string[];
  const live=(themeKey:string)=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:null,text:'Recette',origin:'LIVE',observedAt:new Date().toISOString(),eventKind:'QUALIFIED',eventStatus:'TO_REWORK',themeKey});
  for(const key of ['motorway','speed'])expect((await call('POST',`/lessons/${lesson}/geo-observations`,live(key))).statusCode).toBe(201);
  const stored=(await pool.query('SELECT theme_key,palette_position FROM drivy.geo_observation WHERE lesson_id=$1 ORDER BY created_at,id',[lesson])).rows;
  expect(stored).toEqual([{theme_key:'motorway',palette_position:1},{theme_key:'speed',palette_position:palette.indexOf('speed')+1}]);
  // Un thème que la palette n'affiche pas n'a pas de rang.
  const hidden=defaults.find(theme=>!palette.includes(theme.key))!.key;
  expect((await call('POST',`/lessons/${lesson}/geo-observations`,live(hidden))).statusCode).toBe(201);
  expect((await pool.query('SELECT palette_position FROM drivy.geo_observation WHERE lesson_id=$1 AND theme_key=$2',[lesson,hidden])).rows[0].palette_position).toBeNull();
 });
});
