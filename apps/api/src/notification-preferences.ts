import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier,Identity} from './auth.js';
import {rollbackQuietly,withActor} from './database.js';
import {ApiError,forbidden,notFound} from './errors.js';

/**
 * Préférences de notification (#44), appareils push et abonnement aux prochaines sessions (#40). La personne connectée
 * ne gère que ses propres données ; les jetons d'appareil ne sont jamais relus par l'application.
 */
const empty=z.object({}).strict();
const preferenceBody=z.object({courseOffers:z.boolean(),courseReminders:z.boolean(),courseChanges:z.boolean(),courseStaffAlerts:z.boolean()}).strict();
const deviceBody=z.object({token:z.string().regex(/^[0-9a-fA-F]{64,200}$/),environment:z.enum(['SANDBOX','PRODUCTION'])}).strict();
interface Preferences {version:number;courseOffers:boolean;courseReminders:boolean;courseChanges:boolean;courseStaffAlerts:boolean}
const defaults:Preferences={version:1,courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true};

export function registerNotificationPreferences(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 /** Transaction d'écriture limitée à la personne connectée (et à une école si fournie, pour les abonnements). */
 async function own<T>(identity:Identity,schoolId:string|null,work:(db:PoolClient,personId:string)=>Promise<T>):Promise<T>{
  const db=await options.pool.connect();let broken=false;
  try{
   await db.query('BEGIN');await db.query("SET LOCAL statement_timeout='10s'");await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true)",[identity.issuer,identity.subject,schoolId??'']);
   const personId=(await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[identity.issuer,identity.subject])).rows[0]?.person_id;
   if(!personId)throw new ApiError(403,'IDENTITY_NOT_LINKED','Ce compte ne dispose pas encore d’un accès Drivy.');
   await db.query("SELECT set_config('app.person_id',$1,true)",[personId]);
   if(!(await db.query("SELECT 1 FROM drivy.person WHERE id=$1 AND status='ACTIVE'",[personId])).rowCount)throw forbidden();
   const value=await work(db,personId);await db.query('COMMIT');return value;
  }catch(error){broken=!(await rollbackQuietly(db));throw error;}finally{db.release(broken);}
 }
 const read=async(db:PoolClient,personId:string):Promise<Preferences>=>(await db.query<Preferences>(`SELECT version,course_offers AS "courseOffers",course_reminders AS "courseReminders",
  course_changes AS "courseChanges",course_staff_alerts AS "courseStaffAlerts" FROM drivy.notification_preference WHERE person_id=$1`,[personId])).rows[0]??defaults;

 app.get('/v1/me/notification-preferences',async(r,reply)=>{
  empty.parse(r.query);const identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,undefined,async(db,actor)=>read(db,actor.personId));
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.put('/v1/me/notification-preferences',{bodyLimit:1_024},async(r,reply)=>{
  empty.parse(r.query);const body=preferenceBody.parse(r.body),identity=await options.verifyToken(r.headers.authorization);
  const expected=z.string().regex(/^"[1-9][0-9]*"$/).transform(v=>Number(v.slice(1,-1))).parse(r.headers['if-match']);
  const data=await own(identity,null,async(db,personId)=>{
   // Lock the owner, which exists even before the first preference row. Reading the version before
   // this lock lets two devices both accept the same If-Match and overwrite each other's choices.
   await db.query('SELECT id FROM drivy.person WHERE id=$1 FOR UPDATE',[personId]);
   const current=await read(db,personId);
   if(current.version!==expected)throw new ApiError(412,'VERSION_CONFLICT','Vos préférences ont changé. Rechargez-les.');
   await db.query(`INSERT INTO drivy.notification_preference(person_id,version,course_offers,course_reminders,course_changes,course_staff_alerts) VALUES($1,2,$2,$3,$4,$5)
    ON CONFLICT(person_id) DO UPDATE SET version=notification_preference.version+1,course_offers=$2,course_reminders=$3,course_changes=$4,course_staff_alerts=$5,updated_at=now()`,
    [personId,body.courseOffers,body.courseReminders,body.courseChanges,body.courseStaffAlerts]);
   return read(db,personId);
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 // Enregistrement d'un appareil : idempotent par jeton ; un jeton repris par une autre personne est réattribué.
 app.put('/v1/me/push-devices',{bodyLimit:1_024},async r=>{
  empty.parse(r.query);const body=deviceBody.parse(r.body),identity=await options.verifyToken(r.headers.authorization);
  const token=body.token.toLowerCase();
  return envelope(await own(identity,null,async(db,personId)=>{
   await db.query('SELECT drivy.push_device_claim($1,$2,$3)',[personId,token,body.environment]);
   return {registered:true};
  }),r);
 });
 app.post('/v1/me/push-devices/revoke',{bodyLimit:1_024},async r=>{
  empty.parse(r.query);const body=z.object({token:deviceBody.shape.token}).strict().parse(r.body),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await own(identity,null,async(db,personId)=>{
   await db.query('SELECT drivy.push_device_revoke($1,$2)',[personId,body.token.toLowerCase()]);return {revoked:true};
  }),r);
 });

 // Abonnements « prochaines sessions de ce type » (#40) : volontaires, révocables, sans inscription ni file.
 const school=(r:FastifyRequest)=>z.object({schoolId:z.uuid()}).passthrough().parse(r.params).schoolId;
 app.get('/v1/schools/:schoolId/course-follows/me',async r=>{
  empty.parse(r.query);const schoolId=school(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   if(!member)throw forbidden();
   return {typeIds:(await db.query<{type_id:string}>(`SELECT f.type_id FROM drivy.course_type_follow f JOIN drivy.learner_profile l ON l.id=f.learner_id
    WHERE f.school_id=$1 AND l.person_id=$2 ORDER BY f.created_at`,[schoolId,actor.personId])).rows.map(row=>row.type_id)};
  }),r);
 });
 for(const [method,suffix,follow] of [['put','',true],['post','/unfollow',false]] as const)app[method](`/v1/schools/:schoolId/course-follows/me/:typeId${suffix}`,async r=>{
  empty.parse(r.query);const schoolId=school(r),typeId=z.object({typeId:z.uuid()}).passthrough().parse(r.params).typeId,identity=await options.verifyToken(r.headers.authorization);
  return envelope(await own(identity,schoolId,async(db,personId)=>{
   const learner=(await db.query<{id:string}>('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2 AND archived_at IS NULL',[schoolId,personId])).rows[0];
   if(!learner)throw notFound();
   if(follow){
    if(!(await db.query('SELECT 1 FROM drivy.course_type WHERE id=$1 AND archived_at IS NULL AND (school_id IS NULL OR school_id=$2)',[typeId,schoolId])).rowCount)throw notFound();
    await db.query('INSERT INTO drivy.course_type_follow(school_id,learner_id,type_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[schoolId,learner.id,typeId]);
   }else await db.query('DELETE FROM drivy.course_type_follow WHERE learner_id=$1 AND type_id=$2',[learner.id,typeId]);
   return {typeId,following:follow};
  }),r);
 });
}
