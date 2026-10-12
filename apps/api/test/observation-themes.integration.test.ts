import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {arrangeObservationThemes,observationThemes} from '../src/observation-themes.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const path='/observation-themes',schoolB=`/v1/schools/${id.schoolB}/observation-themes`;
const defaults=observationThemes.map(theme=>({key:theme.key as string,visible:theme.defaultVisible as boolean}));
const save=(themes:{key:string;visible:boolean}[])=>({operationId:randomUUID(),themes});
const keysOf=(data:{themes:{key:string}[]})=>data.themes.map(theme=>theme.key);
const visibleOf=(data:{themes:{key:string;visible:boolean}[]})=>data.themes.filter(theme=>theme.visible).map(theme=>theme.key);
const first=(key:string,themes=defaults)=>[themes.find(theme=>theme.key===key)!,...themes.filter(theme=>theme.key!==key)];
async function grant(grants:string[]){
 const member=(await call('GET','/members',undefined,null,'demo-admin')).json().data.items.find((item:{id:string})=>item.id===id.instructorMember);
 return call('PATCH',`/members/${id.instructorMember}`,{operationId:randomUUID(),roles:member.roles,grants,reason:'Recette des signalements'},member.version,'demo-admin');
}

describe('catalogue des signalements',()=>{
 it('porte dix-huit thèmes à clés uniques, douze affichés à l’origine, les onze premiers inchangés',()=>{
  expect(observationThemes).toHaveLength(18);expect(new Set(observationThemes.map(theme=>theme.key)).size).toBe(18);
  expect(observationThemes.filter(theme=>theme.defaultVisible)).toHaveLength(12);
  expect(observationThemes.slice(0,11).map(theme=>theme.key)).toEqual(['vehicle','observation','right-priority','signage','give-way','intersections','speed','placement','manoeuvres','motorway','anticipation']);
  for(const theme of observationThemes)expect(theme.key).toMatch(/^[a-z][a-z0-9-]{0,39}$/);
 });
 it('ramène une configuration enregistrée au catalogue courant',()=>{
  expect(arrangeObservationThemes(undefined).map(theme=>theme.key)).toEqual(observationThemes.map(theme=>theme.key));
  // Clé inconnue ignorée ; thème absent de la ligne remis à sa place d'origine avec son affichage d'origine.
  const arranged=arrangeObservationThemes({theme_order:['speed','retired-theme','vehicle'],hidden_themes:['vehicle','retired-theme']});
  expect(arranged).toHaveLength(18);expect(arranged.map(theme=>theme.key)).not.toContain('retired-theme');
  expect(arranged.find(theme=>theme.key==='vehicle')!.visible).toBe(false);
  expect(arranged.find(theme=>theme.key==='braking')!.visible).toBe(false);
  expect(arranged.find(theme=>theme.key==='indicators')!.visible).toBe(true);
  expect(arranged.findIndex(theme=>theme.key==='speed')).toBeLessThan(arranged.findIndex(theme=>theme.key==='lane-change'));
  // Une ligne dont tous les thèmes connus seraient masqués ne vide pas « Signaler ».
  expect(arrangeObservationThemes({theme_order:observationThemes.map(theme=>theme.key),hidden_themes:observationThemes.map(theme=>theme.key)}).filter(theme=>theme.visible)).toHaveLength(12);
 });
});

describe('configuration des signalements par école',()=>{
 it('une école qui n’a rien réglé a dix-huit thèmes dont douze affichés, sans ligne en base',async()=>{
  const read=await call('GET',path);expect(read.statusCode,read.body).toBe(200);
  const data=read.json().data;
  expect(data).toMatchObject({id:id.schoolA,schoolId:id.schoolA,version:1,canManage:false});expect(read.headers.etag).toBe('"1"');
  expect(data.themes).toHaveLength(18);expect(visibleOf(data)).toHaveLength(12);
  expect(data.themes[0]).toEqual({key:'vehicle',title:'Maîtrise du véhicule',competencyKeys:['vehicule'],visible:true,defaultVisible:true,defaultPosition:0});
  expect(data.themes.map((theme:{defaultPosition:number})=>theme.defaultPosition)).toEqual([...Array(18).keys()]);
  expect((await call('GET',path,undefined,null,'demo-admin')).json().data.canManage).toBe(true);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.observation_theme_settings')).rows[0].n).toBe(0);
 });
 it('refuse la lecture à un élève et à un compte étranger à l’école',async()=>{
  expect((await call('GET',path,undefined,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('GET',path,undefined,null,'demo-foreign')).statusCode).toBe(403);
 });
 it('un moniteur sans le droit lit mais ne modifie pas, même en rejouant ou en forçant la base',async()=>{
  const refused=await call('PUT',path,save(first('right-priority')),1);
  expect(refused.statusCode,refused.body).toBe(403);expect(refused.json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  expect((await call('PUT',path,save(defaults),1,'demo-alice')).statusCode).toBe(403);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.observation_theme_settings')).rows[0].n).toBe(0);
  // La RLS porte la même règle que la commande.
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject','demo-instructor',true),set_config('app.school_id',$2,true),set_config('app.person_id',$3,true),set_config('app.membership_id',$4,true)",[issuer,id.schoolA,id.instructor,id.instructorMember]);
   await expect(db.query('INSERT INTO drivy.observation_theme_settings(school_id,version,theme_order,updated_by) VALUES($1,2,$2,$3)',[id.schoolA,['vehicle'],id.instructorMember])).rejects.toThrow(/row-level security/);
   await db.query('ROLLBACK');
  }finally{db.release();}
 });
 it('l’administrateur affiche les dix-huit, masque, réordonne ; version, idempotence, audit et conflit',async()=>{
  const all=save(defaults.map(theme=>({...theme,visible:true}))),saved=await call('PUT',path,all,1,'demo-admin');
  expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.version).toBe(2);expect(saved.headers.etag).toBe('"2"');
  expect(visibleOf(saved.json().data)).toHaveLength(18);expect(saved.json().data.canManage).toBe(true);
  // Rejeu : même réponse, aucune seconde écriture.
  expect((await call('PUT',path,all,1,'demo-admin')).json().data.version).toBe(2);
  expect((await call('PUT',path,{...all,themes:defaults},1,'demo-admin')).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('PUT',path,save(defaults),1,'demo-admin')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',path,save(defaults),null,'demo-admin')).statusCode).toBe(428);
  expect((await call('GET',`/operations/${all.operationId}`,undefined,null,'demo-admin')).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_THEMES',resourceType:'ObservationThemeSettings',resourceId:id.schoolA,resourceVersion:2});
  expect((await pool.query("SELECT action FROM drivy.audit_event WHERE operation_id=$1",[all.operationId])).rows).toEqual([{action:'ObservationThemesSaved'}]);
  // Masquer plusieurs thèmes et placer « Priorité à droite » en tête.
  const custom=first('right-priority').map(theme=>({...theme,visible:!['motorway','manoeuvres','braking'].includes(theme.key)}));
  const changed=await call('PUT',path,save(custom),2,'demo-admin');expect(changed.statusCode,changed.body).toBe(200);
  expect(changed.json().data.version).toBe(3);expect(keysOf(changed.json().data)[0]).toBe('right-priority');
  expect(visibleOf(changed.json().data)).toHaveLength(15);expect(visibleOf(changed.json().data)).not.toContain('motorway');
  // Le moniteur de la même école reçoit l'ordre et l'affichage de son école.
  const seen=(await call('GET',path)).json().data;expect(seen.version).toBe(3);expect(keysOf(seen)).toEqual(custom.map(theme=>theme.key));expect(seen.canManage).toBe(false);
 });
 it('refuse une liste incomplète, en double, inconnue, ou qui masque tout',async()=>{
  const bodies=[save(defaults.slice(1)),save([defaults[0]!,...defaults.slice(0,17)]),save([{key:'unknown',visible:true},...defaults.slice(1)]),
   save(defaults.map(theme=>({...theme,visible:false}))),{...save(defaults),reset:true},save(defaults.map(theme=>({...theme,title:'Autre'})) as never)];
  for(const body of bodies){const response=await call('PUT',path,body,3,'demo-admin');expect(response.statusCode,response.body).toBe(400);}
  expect((await call('GET',path)).json().data.version).toBe(3);
 });
 it('le droit « Gérer les signalements » ouvre la modification au moniteur, son retrait la referme',async()=>{
  const given=await grant(['MANAGE_OBSERVATION_THEMES']);expect(given.statusCode,given.body).toBe(200);expect(given.json().data.grants).toEqual(['MANAGE_OBSERVATION_THEMES']);
  expect((await call('GET',path)).json().data.canManage).toBe(true);
  const body=save(first('speed')),saved=await call('PUT',path,body,3);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data.version).toBe(4);expect(keysOf(saved.json().data)[0]).toBe('speed');
  expect((await call('GET',`/operations/${body.operationId}`)).statusCode).toBe(200);
  expect((await pool.query('SELECT updated_by FROM drivy.observation_theme_settings WHERE school_id=$1',[id.schoolA])).rows[0].updated_by).toBe(id.instructorMember);
  const removed=await grant([]);expect(removed.statusCode,removed.body).toBe(200);
  expect((await call('GET',path)).json().data.canManage).toBe(false);
  expect((await call('PUT',path,save(defaults),4)).json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  // Le rejeu de sa propre commande ne contourne pas le retrait du droit.
  expect((await call('PUT',path,body,3)).statusCode).toBe(403);
  expect((await call('GET',`/operations/${body.operationId}`)).statusCode).toBe(403);
  expect((await call('GET',path)).json().data.version).toBe(4);
 });
 it('deux écoles gardent des configurations indépendantes',async()=>{
  const other=await call('GET',schoolB);expect(other.statusCode,other.body).toBe(200);
  expect(other.json().data).toMatchObject({schoolId:id.schoolB,version:1});expect(keysOf(other.json().data)).toEqual(defaults.map(theme=>theme.key));
  expect((await call('GET',schoolB,undefined,null,'demo-admin')).statusCode).toBe(403);
  expect((await call('PUT',schoolB,save(defaults),1,'demo-admin')).statusCode).toBeGreaterThanOrEqual(403);
  expect(keysOf((await call('GET',path)).json().data)[0]).toBe('speed');
 });
 it('deux enregistrements concurrents : un seul passe, l’autre reçoit un conflit de version',async()=>{
  const writes=await Promise.all([call('PUT',path,save(first('braking')),4,'demo-admin'),call('PUT',path,save(first('signage')),4,'demo-admin')]);
  expect(writes.map(response=>response.statusCode).sort()).toEqual([200,412]);
  expect((await call('GET',path)).json().data.version).toBe(5);
 });
 it('réinitialise par l’ordre et l’affichage d’origine publiés par le service',async()=>{
  const current=(await call('GET',path,undefined,null,'demo-admin')).json().data;
  const original=[...current.themes].sort((a:{defaultPosition:number},b:{defaultPosition:number})=>a.defaultPosition-b.defaultPosition).map((theme:{key:string;defaultVisible:boolean})=>({key:theme.key,visible:theme.defaultVisible}));
  const reset=await call('PUT',path,save(original),5,'demo-admin');expect(reset.statusCode,reset.body).toBe(200);
  expect(keysOf(reset.json().data)).toEqual(defaults.map(theme=>theme.key));expect(visibleOf(reset.json().data)).toHaveLength(12);expect(reset.json().data.version).toBe(6);
 });
});

describe('observations et thèmes',()=>{
 let lesson:string,look:string,route:string;
 const live=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:look,text:'Clignotants',origin:'LIVE',
  observedAt:new Date().toISOString(),eventKind:'QUALIFIED',eventStatus:'TO_REWORK',...extra});
 beforeAll(async()=>{
  lesson=randomUUID();look=randomUUID();route=`/lessons/${lesson}/geo-observations`;
  await pool.query(`INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$2,$3,'observation','Observation et contrôles','Synthétique',2)`,[look,id.schoolA,school.curriculum]);
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
   VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,school.policy]);
 });
 it('garde la clé du thème, refuse un thème d’une autre compétence, reste compatible sans clé',async()=>{
  const created=await call('POST',route,live({themeKey:'indicators'}));expect(created.statusCode,created.body).toBe(201);
  expect(created.json().data).toMatchObject({themeKey:'indicators',competencyId:look,text:'Clignotants',eventStatus:'TO_REWORK'});
  const mismatch=await call('POST',route,live({themeKey:'braking'}));expect(mismatch.statusCode,mismatch.body).toBe(422);expect(mismatch.json().code).toBe('OBSERVATION_THEME_MISMATCH');
  expect((await call('POST',route,live({themeKey:'unknown'}))).statusCode).toBe(400);
  // Un repère n'a ni compétence ni thème.
  expect((await call('POST',route,live({competencyId:null,eventKind:'MARKER',eventStatus:null,themeKey:'indicators',text:'Moment à revoir'}))).statusCode).toBe(400);
  // Un client antérieur au catalogue n'envoie pas le champ.
  const legacy=await call('POST',route,live({text:'Observation et contrôles'}));expect(legacy.statusCode,legacy.body).toBe(201);expect(legacy.json().data.themeKey).toBeNull();
 });
 it('masquer un thème ne retire aucune observation et n’empêche pas un envoi resté en file',async()=>{
  const current=(await call('GET',path,undefined,null,'demo-admin')).json().data;
  const hidden=current.themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.visible&&!['indicators','observation'].includes(theme.key)}));
  const saved=await call('PUT',path,save(hidden),current.version,'demo-admin');expect(saved.statusCode,saved.body).toBe(200);
  expect(visibleOf(saved.json().data)).not.toContain('indicators');
  const list=(await call('GET',route)).json().data.items as {themeKey:string|null;text:string}[];
  expect(list.map(item=>item.themeKey)).toEqual(['indicators',null]);expect(list[0]!.text).toBe('Clignotants');
  // Signalement saisi avant le masquage, envoyé après : accepté.
  const late=await call('POST',route,live({themeKey:'indicators'}));expect(late.statusCode,late.body).toBe(201);expect(late.json().data.themeKey).toBe('indicators');
  expect((await call('GET',route)).json().data.items).toHaveLength(3);
 });
 it('la reprise de migration ne renseigne la clé que là où le texte est encore le titre de la tuile',async()=>{
  // Même requête que la migration 026, rejouée sur les lignes créées sans clé.
  await pool.query(`UPDATE drivy.geo_observation o SET theme_key=x.key FROM drivy.competency_definition c,(VALUES('observation','Observation et contrôles','observation')) AS x(competency_key,title,key)
   WHERE c.school_id=o.school_id AND c.id=o.competency_id AND c.stable_key=x.competency_key AND o.text=x.title AND o.event_kind='QUALIFIED' AND o.removed_at IS NULL AND o.theme_key IS NULL`);
  const list=(await call('GET',route)).json().data.items as {themeKey:string|null}[];
  expect(list.map(item=>item.themeKey)).toEqual(['indicators','observation','indicators']);
 });
});
