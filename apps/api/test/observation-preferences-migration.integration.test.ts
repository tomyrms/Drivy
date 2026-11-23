import {readFile} from 'node:fs/promises';
import {Pool} from 'pg';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {freshDatabase,harness,id,type Call} from './support/harness.js';
import {observationThemes} from '../src/observation-themes.js';

/** Migration 20261111 sur une copie synthétique peuplée à l'état antérieur : reprise répétable, sans écrasement, divergences gardées. */
let pool:Pool,migrator:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
const order=(head:string)=>[head,...observationThemes.map(theme=>theme.key as string).filter(key=>key!==head)];
const adopt=async()=>(await migrator.query('SELECT drivy.adopt_legacy_observation_rankings() AS n')).rows[0].n as number;
const account=async(person:string)=>(await pool.query('SELECT version,theme_order,hidden_themes,mode,ranked_order,to_char(ranked_on,\'YYYY-MM-DD\') AS ranked_on,learning_generation,learning_since FROM drivy.person_observation_preference WHERE person_id=$1',[person])).rows[0];
const legacy=(school:string,member:string,mode:string,ranked:string[],day:string|null)=>migrator.query(
 `INSERT INTO drivy.observation_ranking(school_id,membership_id,version,mode,ranked_order,ranked_on) VALUES($1,$2,2,$3,$4,$5::date)
  ON CONFLICT(school_id,membership_id) DO UPDATE SET mode=EXCLUDED.mode,ranked_order=EXCLUDED.ranked_order,ranked_on=EXCLUDED.ranked_on`,[school,member,mode,ranked,day]);

beforeAll(async()=>{
 pool=await freshDatabase({skipMigrations:/^20261111_observation_preferences/});
 migrator=new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});
 // État antérieur : une école avec sa configuration, des classements par adhésion dont un contradictoire.
 await migrator.query(`INSERT INTO drivy.observation_theme_settings(school_id,version,theme_order,hidden_themes,updated_by) VALUES($1,4,$2,$3,$4)`,[id.schoolA,order('speed'),['motorway'],id.adminMember]);
 await legacy(id.schoolA,id.otherInstructorMember,'SMART',order('motorway'),'2026-11-10');
 await legacy(id.schoolA,id.instructorMember,'SMART',order('speed'),'2026-11-10');
 await legacy(id.schoolB,id.instructorMemberB,'MANUAL',[],null);
 await legacy(id.schoolA,id.adminMember,'MANUAL',[],null);
 // Ancien droit de gestion scolaire, accordé avant la migration à un moniteur : il doit rester enregistré sans rien ouvrir.
 await pool.query("UPDATE drivy.membership SET grants=ARRAY['MANAGE_OBSERVATION_THEMES'] WHERE id=$1",[id.otherInstructorMember]);
 await migrator.query(await readFile(new URL('../migrations/20261111_observation_preferences.sql',import.meta.url),'utf8'));
 ({call,app}=await harness(pool));
});
afterAll(async()=>{await app?.close();await migrator?.end();await pool?.end();});

describe('migration 20261111 sur des données antérieures',()=>{
 it('les écoles existantes restent en visibilité imposée, avec leur configuration intacte',async()=>{
  expect((await pool.query('SELECT school_id,version,theme_order,hidden_themes,personalization_allowed FROM drivy.observation_theme_settings')).rows).toEqual([{school_id:id.schoolA,version:4,theme_order:order('speed'),hidden_themes:['motorway'],personalization_allowed:false}]);
  expect((await call('GET','/observation-themes')).json().data).toMatchObject({personalizationAllowed:false,version:4});
 });
 it('reprend le classement intelligent d’une seule configuration ; laisse une divergence ou un choix manuel',async()=>{
  expect(await account(id.otherInstructor)).toEqual({version:2,theme_order:null,hidden_themes:null,mode:'SMART',ranked_order:order('motorway'),ranked_on:'2026-11-10',learning_generation:0,learning_since:null});
  // Intelligent dans une école, manuel dans l'autre : rien n'est départagé à la place de la personne. Un choix manuel seul ne crée rien.
  expect(await account(id.instructor)).toBeUndefined();expect(await account(id.admin)).toBeUndefined();
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.person_observation_preference')).rows[0].n).toBe(1);
  // Les anciennes lignes sont conservées, telles quelles.
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.observation_ranking')).rows[0].n).toBe(4);
 });
 it('la personne dont les écoles divergent reçoit les candidats et choisit à sa première personnalisation',async()=>{
  const read=await call('GET','/observation-preferences');expect(read.statusCode,read.body).toBe(200);
  const data=read.json().data;expect(data).toMatchObject({version:1,mode:'MANUAL',orderCustomized:false});
  expect(data.adoption.candidates).toHaveLength(2);
  expect(data.adoption.candidates.map((candidate:{schoolId:string;mode:string})=>[candidate.schoolId,candidate.mode]).sort()).toEqual([[id.schoolA,'SMART'],[id.schoolB,'MANUAL']].sort());
  expect(data.adoption.candidates.every((candidate:{schoolName:string;themes:unknown[]})=>candidate.schoolName.length>0&&candidate.themes.length===18)).toBe(true);
  // Sans préférence de compte, la liste de l'école s'applique (sa ligne ancienne ne masque que « Autoroute »).
  expect(data.palette).toEqual(order('speed').filter(key=>key!=='motorway'));
  // Le collègue qui a été repris lit son classement, sans candidat.
  const adopted=(await call('GET','/observation-preferences',undefined,null,'demo-other-instructor')).json().data;
  // Sa première lecture du jour refait le classement (le dernier datait du 10 novembre) : la version avance.
  expect(adopted).toMatchObject({mode:'SMART',adoption:null});expect(adopted.version).toBeGreaterThanOrEqual(2);
  // Il enregistre : l'adoption devient un choix explicite et ne propose plus rien.
  const saved=await call('PUT','/observation-preferences',{operationId:crypto.randomUUID(),mode:'SMART'},1);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data.adoption).toBeNull();
 });
 it('répétable et sans écrasement : un compte initialisé n’est jamais touché ; des configurations identiques se reprennent',async()=>{
  const before=await account(id.otherInstructor);
  await legacy(id.schoolA,id.otherInstructorMember,'SMART',order('anticipation'),'2026-11-11');
  expect(await adopt()).toBe(0);expect(await account(id.otherInstructor)).toEqual(before);
  // Le compte de la personne à deux écoles existe maintenant (enregistré ci-dessus) : il n'est pas non plus écrasé.
  const own=await account(id.instructor);expect(own).toBeDefined();
  await legacy(id.schoolB,id.instructorMemberB,'SMART',order('speed'),'2026-11-10');
  expect(await adopt()).toBe(0);expect(await account(id.instructor)).toEqual(own);
  // Deux écoles aux classements identiques : reprise pour un compte vierge.
  await migrator.query('DELETE FROM drivy.person_observation_preference WHERE person_id=$1',[id.instructor]);
  expect(await adopt()).toBe(1);
  expect(await account(id.instructor)).toMatchObject({version:2,mode:'SMART',ranked_order:order('speed'),theme_order:null,hidden_themes:null});
  expect(await adopt()).toBe(0);
 });
 it('école sans configuration, ancien grant de gestion et anciens clients : rien ne change de sens ni de droit (R08 #470)',async()=>{
  type Theme={key:string;visible:boolean};
  // L'école B n'a jamais eu de configuration : références Drivy, visibilité imposée, gérable par son administrateur.
  const themesB=`/v1/schools/${id.schoolB}/observation-themes`;
  const b=(await call('GET',themesB)).json().data;
  expect(b).toMatchObject({personalizationAllowed:false,canManage:true});
  expect(b.themes.map((theme:Theme)=>[theme.key,theme.visible])).toEqual(observationThemes.map(theme=>[theme.key,theme.defaultVisible]));
  const prefsB=(await call('GET',`/v1/schools/${id.schoolB}/observation-preferences`)).json().data;
  expect(prefsB).toMatchObject({schoolId:id.schoolB,personalizationAllowed:false,visibilityCustomized:false});
  expect(prefsB.themes.every((theme:{visible:boolean;schoolVisible:boolean;visibilityEditable:boolean})=>theme.visible===theme.schoolVisible&&!theme.visibilityEditable)).toBe(true);
  // L'ancien droit « Gérer les signalements » accordé avant la migration reste enregistré et n'ouvre ni la lecture de gestion ni l'écriture.
  const grantee=(await call('GET','/observation-themes',undefined,null,'demo-other-instructor')).json().data;
  expect(grantee.canManage).toBe(false);
  const refused=await call('PUT','/observation-themes',{operationId:crypto.randomUUID(),themes:grantee.themes.map((theme:Theme)=>({key:theme.key,visible:theme.visible})),personalizationAllowed:true},grantee.version,'demo-other-instructor');
  expect(refused.statusCode).toBe(403);expect(refused.json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  expect((await pool.query('SELECT grants FROM drivy.membership WHERE id=$1',[id.otherInstructorMember])).rows[0].grants).toEqual(['MANAGE_OBSERVATION_THEMES']);
  expect((await call('GET','/observation-themes',undefined,null,'demo-other-instructor')).json().data.personalizationAllowed).toBe(false);
  // Ancien client des thèmes de l'école (sans politique) : la configuration reprise est réécrite à l'identique, la politique reste imposée.
  const school=(await call('GET','/observation-themes',undefined,null,'demo-admin')).json().data;
  expect(school.themes[0].key).toBe('speed');expect(school.themes.find((theme:Theme)=>theme.key==='motorway').visible).toBe(false);
  const rewritten=await call('PUT','/observation-themes',{operationId:crypto.randomUUID(),themes:school.themes.map((theme:Theme)=>({key:theme.key,visible:theme.visible}))},school.version,'demo-admin');
  expect(rewritten.statusCode,rewritten.body).toBe(200);
  expect(rewritten.json().data).toMatchObject({personalizationAllowed:false,version:school.version+1});
  expect(rewritten.json().data.themes.map((theme:Theme)=>[theme.key,theme.visible])).toEqual(school.themes.map((theme:Theme)=>[theme.key,theme.visible]));
  // Ancien client du classement : même forme, lit et écrit le compte repris.
  const legacyRanking=await call('GET','/observation-ranking',undefined,null,'demo-other-instructor');expect(legacyRanking.statusCode,legacyRanking.body).toBe(200);
  expect(legacyRanking.json().data).toMatchObject({membershipId:id.otherInstructorMember,schoolId:id.schoolA,mode:'SMART'});
  const accountBefore=await account(id.otherInstructor);
  const legacyOff=await call('PUT','/observation-ranking',{operationId:crypto.randomUUID(),mode:'MANUAL'},legacyRanking.json().data.version,'demo-other-instructor');
  expect(legacyOff.statusCode,legacyOff.body).toBe(200);
  expect(await account(id.otherInstructor)).toMatchObject({mode:'MANUAL',version:accountBefore.version+1});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.observation_ranking WHERE membership_id=$1 AND mode=$2',[id.otherInstructorMember,'MANUAL'])).rows[0].n).toBe(0);
 });
 it('l’ancienne table n’est plus modifiable par le service',async()=>{
  const db=await pool.connect();
  try{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await expect(db.query("UPDATE drivy.observation_ranking SET mode='MANUAL'")).rejects.toThrow(/permission denied/);
   await db.query('ROLLBACK');
  }finally{db.release();}
 });
});
