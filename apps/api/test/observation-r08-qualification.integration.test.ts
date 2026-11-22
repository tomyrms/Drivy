import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {observationThemes} from '../src/observation-themes.js';

/**
 * R08 (#470) : scénarios transverses du candidat final, sur une base PostgreSQL réelle. Les règles isolées sont prouvées dans
 * observation-preferences, observation-learning et observation-preferences-migration ; ce fichier ne garde que les combinaisons
 * que ces fichiers ne rejouent pas : même compte entre deux écoles de politiques opposées, trois personnes d'une école, verrouillage
 * pendant une édition et livraison tardive d'un signalement par la vraie route.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
const prefs='/observation-preferences',themes='/observation-themes';
const prefsB=`/v1/schools/${id.schoolB}/observation-preferences`,themesB=`/v1/schools/${id.schoolB}/observation-themes`;
const defaults=observationThemes.map(theme=>({key:theme.key as string,visible:theme.defaultVisible as boolean}));
const manual=defaults.filter(theme=>theme.visible).map(theme=>theme.key);
const save=(body:Record<string,unknown>={})=>({operationId:randomUUID(),...body});
const order=(head:string)=>[head,...defaults.map(theme=>theme.key).filter(key=>key!==head)];
const vis=(hide:string[]=[],show:string[]=[])=>defaults.map(theme=>({key:theme.key,visible:show.includes(theme.key)?true:hide.includes(theme.key)?false:theme.visible}));
const stored=async(person:string)=>(await pool.query('SELECT version,theme_order,hidden_themes,mode,learning_generation FROM drivy.person_observation_preference WHERE person_id=$1',[person])).rows[0];
const keysOf=(data:{themes:{key:string}[]})=>data.themes.map(theme=>theme.key);
const current=async(route=prefs,subject?:string)=>(await call('GET',route,undefined,null,subject)).json().data;
/** Politique de l'école : conserve sa référence et change seulement l'autorisation de personnaliser. */
const putPolicy=async(allowed:boolean,route=themes,subject='demo-admin')=>{
 const now=await current(route,subject);
 return call('PUT',route,save({themes:now.themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.visible})),personalizationAllowed:allowed}),now.version,subject);
};

beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

describe('scénario 1 · école A libre, école B imposée, même compte',()=>{
 it('seule la visibilité change d’une école à l’autre ; ordre, mode et choix personnels restent ceux du compte',async()=>{
  // Le moniteur est moniteur de A et administrateur de B ; B garde la politique par défaut (visibilité imposée).
  const opened=await putPolicy(true);expect(opened.statusCode,opened.body).toBe(200);
  const saved=await call('PUT',prefs,save({order:order('speed'),visibility:vis(['motorway'],['braking'])}),1);expect(saved.statusCode,saved.body).toBe(200);
  const onA=saved.json().data,onB=await current(prefsB);
  expect(onA).toMatchObject({personalizationAllowed:true,visibilityCustomized:true,mode:'MANUAL'});
  expect(onB).toMatchObject({schoolId:id.schoolB,personalizationAllowed:false,visibilityCustomized:false,orderCustomized:true,mode:'MANUAL',version:onA.version});
  // Même ordre personnel, visibilité différente.
  expect(keysOf(onB)).toEqual(keysOf(onA));
  expect(onA.palette).toContain('braking');expect(onA.palette).not.toContain('motorway');
  expect(onB.palette).toContain('motorway');expect(onB.palette).not.toContain('braking');expect(new Set(onB.palette)).toEqual(new Set(manual));
  // Les thèmes visibles dans les deux écoles gardent leur ordre relatif.
  const common=onA.palette.filter((key:string)=>onB.palette.includes(key));
  expect(onB.palette.filter((key:string)=>onA.palette.includes(key))).toEqual(common);expect(common.length).toBeGreaterThan(5);
  // L'administrateur de B ne contourne pas la politique de B pour sa visibilité : refus, rien d'écrit, choix de A intact.
  const before=await stored(id.instructor);
  const refused=await call('PUT',prefsB,save({visibility:vis(['speed'])}),onB.version);expect(refused.statusCode).toBe(403);expect(refused.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  expect(await stored(id.instructor)).toEqual(before);
  // Le mode intelligent est celui du compte : activé depuis B, il est lu tel quel dans A, et la visibilité de chaque école ne change pas.
  const smart=await call('PUT',prefsB,save({mode:'SMART'}),onB.version);expect(smart.statusCode,smart.body).toBe(200);
  const smartA=await current(),smartB=await current(prefsB);
  expect(smartA).toMatchObject({mode:'SMART',version:smart.json().data.version,visibilityCustomized:true});expect(smartB).toMatchObject({mode:'SMART',visibilityCustomized:false});
  expect(smartA.rankedOn).toBe(smartB.rankedOn);expect(smartA.rankedOn).not.toBeNull();
  expect(new Set(smartA.palette)).toEqual(new Set(onA.palette));expect(new Set(smartB.palette)).toEqual(new Set(onB.palette));
  const smartCommon=smartA.palette.filter((key:string)=>smartB.palette.includes(key));
  expect(smartB.palette.filter((key:string)=>smartA.palette.includes(key))).toEqual(smartCommon);
  // Retour en manuel puis à l'école A : les choix personnels y sont retrouvés.
  const manualAgain=await call('PUT',prefs,save({mode:'MANUAL'}),smartA.version);expect(manualAgain.statusCode,manualAgain.body).toBe(200);
  const backA=await current();
  expect(backA).toMatchObject({visibilityCustomized:true,mode:'MANUAL'});expect(backA.palette).toEqual(onA.palette);
  expect(backA.themes.find((theme:{key:string})=>theme.key==='motorway')).toMatchObject({visible:false,schoolVisible:true});
 });
});

describe('scénario 2 · deux moniteurs et un administrateur',()=>{
 it('chacun règle son propre compte, sans effet sur celui des autres',async()=>{
  const instructorBefore=await stored(id.instructor);
  const other=await call('PUT',prefs,save({order:order('observation'),visibility:vis(['speed'])}),1,'demo-other-instructor');expect(other.statusCode,other.body).toBe(200);
  const admin=await call('PUT',prefs,save({order:order('signage'),visibility:vis(['anticipation'])}),1,'demo-admin');expect(admin.statusCode,admin.body).toBe(200);
  expect(other.json().data.palette[0]).toBe('observation');expect(other.json().data.palette).not.toContain('speed');
  expect(admin.json().data.palette[0]).toBe('signage');expect(admin.json().data.palette).not.toContain('anticipation');
  // Le premier moniteur n'a pas bougé et ne voit rien des deux autres.
  expect(await stored(id.instructor)).toEqual(instructorBefore);
  const mine=await current();expect(mine.palette[0]).toBe('speed');expect(mine.palette).toContain('anticipation');
  expect(new Set([id.instructor,id.otherInstructor,id.admin]).size).toBe(3);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.person_observation_preference WHERE person_id=ANY($1)',[[id.instructor,id.otherInstructor,id.admin]])).rows[0].n).toBe(3);
 });
 it('aucune route, aucun paramètre ni aucun corps ne vise le compte d’autrui',async()=>{
  const row=await stored(id.instructor);
  const body=save({order:order('braking')});
  expect((await call('PUT',prefs,{...body,personId:id.instructor},1,'demo-other-instructor')).statusCode).toBe(400);
  expect((await call('PUT',prefs,{...body,id:id.instructor},1,'demo-admin')).statusCode).toBe(400);
  expect((await call('GET',`${prefs}?personId=${id.instructor}`,undefined,null,'demo-admin')).statusCode).toBe(400);
  expect((await call('GET',`${prefs}/${id.instructor}`,undefined,null,'demo-admin')).statusCode).toBe(404);
  expect((await call('POST',`${prefs}/presentation-reset`,{...save(),personId:id.instructor},1,'demo-admin')).statusCode).toBe(400);
  expect((await call('POST',`${prefs}/learning-reset`,{...save(),personId:id.instructor},1,'demo-admin')).statusCode).toBe(400);
  expect(await stored(id.instructor)).toEqual(row);
 });
 it('la politique appartient à l’administrateur de l’école : ni un moniteur ni l’administrateur d’une autre école ne la changent',async()=>{
  const body=save({themes:defaults,personalizationAllowed:false}),version=(await current(themes,'demo-admin')).version;
  for(const subject of ['demo-instructor','demo-other-instructor']){
   const refused=await call('PUT',themes,body,version,subject);expect(refused.statusCode,subject).toBe(403);expect(refused.json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  }
  // L'administrateur de A n'est rien dans B.
  expect((await call('PUT',themesB,save({themes:defaults,personalizationAllowed:true}),(await current(themesB)).version,'demo-admin')).statusCode).toBe(403);
  expect((await current(themes,'demo-admin')).personalizationAllowed).toBe(true);expect((await current(themesB)).personalizationAllowed).toBe(false);
  // L'administrateur de A impose sa visibilité : chacun voit celle de l'école, et ses choix restent en réserve, sans écrasement.
  const reserve=[await stored(id.instructor),await stored(id.otherInstructor),await stored(id.admin)];
  const imposed=await putPolicy(false);expect(imposed.statusCode,imposed.body).toBe(200);
  for(const [subject,palette0] of [['demo-instructor','speed'],['demo-other-instructor','observation'],['demo-admin','signage']] as const){
   const now=await current(prefs,subject);
   expect(now).toMatchObject({personalizationAllowed:false,visibilityCustomized:false});expect(now.palette[0]).toBe(palette0);
   expect(new Set(now.palette)).toEqual(new Set(manual));
  }
  expect([await stored(id.instructor),await stored(id.otherInstructor),await stored(id.admin)]).toEqual(reserve);
 });
});

describe('scénario 3 · verrouillage pendant une édition',()=>{
 it('libre → imposé sur un autre appareil : l’enregistrement de visibilité est refusé sans faux succès ; l’ordre passe ; le choix personnel est gardé',async()=>{
  const reopened=await putPolicy(true);expect(reopened.statusCode,reopened.body).toBe(200);
  const device=await current();
  const applied=save({visibility:vis(['motorway','signage'])});
  const first=await call('PUT',prefs,applied,device.version);expect(first.statusCode,first.body).toBe(200);
  // Les deux appareils sont à jour, puis l'école impose sa visibilité depuis le web.
  const edited=await current(),reserve=await stored(id.instructor);
  expect((await putPolicy(false)).statusCode).toBe(200);
  // Appareil 1 : visibilité seule, ou avec un ordre, refusées en entier.
  for(const body of [save({visibility:vis(['speed'])}),save({order:order('braking'),visibility:vis(['speed'])})]){
   const refused=await call('PUT',prefs,body,edited.version);expect(refused.statusCode,refused.body).toBe(403);expect(refused.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  }
  expect(await stored(id.instructor)).toEqual(reserve);
  // Appareil 2 : rejoue l'enregistrement déjà appliqué (file hors ligne). Aucune écriture, aucun état inventé.
  const replay=await call('PUT',prefs,applied,device.version);expect([200,403],replay.body).toContain(replay.statusCode);
  if(replay.statusCode===200){expect(replay.json().data).toMatchObject({version:edited.version,personalizationAllowed:false,visibilityCustomized:false});expect(replay.json().data.palette).toContain('motorway');}
  expect(await stored(id.instructor)).toEqual(reserve);
  // L'école montre sa visibilité, mais le choix personnel n'est pas effacé.
  const imposed=await current();expect(imposed).toMatchObject({personalizationAllowed:false,visibilityCustomized:false,version:edited.version});
  expect(imposed.palette).toContain('motorway');expect(imposed.palette).toContain('signage');
  // L'ordre reste personnel : accepté pendant que la visibilité est imposée.
  const moved=await call('PUT',prefs,save({order:order('placement')}),edited.version);expect(moved.statusCode,moved.body).toBe(200);expect(moved.json().data.palette[0]).toBe('placement');
  expect((await stored(id.instructor)).hidden_themes).toEqual(reserve.hidden_themes);
  // Retour à libre : le choix personnel est retrouvé, avec l'ordre choisi entre-temps.
  expect((await putPolicy(true)).statusCode).toBe(200);
  const back=await current();
  expect(back).toMatchObject({personalizationAllowed:true,visibilityCustomized:true});expect(back.palette[0]).toBe('placement');
  expect(back.palette).not.toContain('motorway');expect(back.palette).not.toContain('signage');
 });
});

describe('scénario 6 · signalement ancien livré tardivement par la vraie route',()=>{
 it('un geste observé avant « Recommencer l’apprentissage » ne compte pas, même reçu après ; rien n’est supprimé',async()=>{
  const lesson=randomUUID();
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
   VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,school.policy]);
  const account=await current();
  const reset=await call('POST',`${prefs}/learning-reset`,save(),account.version);expect(reset.statusCode,reset.body).toBe(200);
  // La borne est reculée de deux jours pour que « hier » soit après elle (l'usage s'arrête à la veille).
  await pool.query("UPDATE drivy.person_observation_preference SET learning_since=now()-interval '2 days' WHERE person_id=$1",[id.instructor]);
  const ago=(days:number)=>new Date(Date.now()-days*86_400_000).toISOString();
  const live=(themeKey:string,observedAt:string)=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:null,text:'Recette',origin:'LIVE',observedAt,eventKind:'QUALIFIED',eventStatus:'TO_REWORK',themeKey});
  // Livré maintenant, mais observé il y a trois jours (avant la borne) : file hors ligne tardive. L'autre est observé hier (après la borne).
  expect((await call('POST',`/lessons/${lesson}/geo-observations`,live('indicators',ago(3)))).statusCode).toBe(201);
  expect((await call('POST',`/lessons/${lesson}/geo-observations`,live('speed',ago(1)))).statusCode).toBe(201);
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true),set_config('app.person_id',$4,true)",[issuer,'demo-instructor',id.schoolA,id.instructor]);
   const usage=(await db.query("SELECT theme_key FROM drivy.observation_account_usage('Europe/Zurich')")).rows.map(row=>row.theme_key);
   expect(usage).toEqual(['speed']);
   await db.query('ROLLBACK');
  }finally{db.release();}
  // Aucune observation n'est supprimée : les deux sont conservées.
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.geo_observation WHERE lesson_id=$1 AND removed_at IS NULL',[lesson])).rows[0].n).toBe(2);
 });
});
