import { createHash } from 'node:crypto';
import { connect, constants, type ClientHttp2Session } from 'node:http2';
import { importPKCS8, SignJWT } from 'jose';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import { rollbackQuietly } from './database.js';
import { chooseCoalescedMessagingAlert, decideMessagingNotification, MESSAGING_PUSH_QUIET_WINDOW_SECONDS, messagingNotificationInputs, messagingPushPayload, messagingSkipCode, queuedMessagingCategories, type MessagingSnapshotRow, type QueuedMessagingCategory } from './messaging-notifications.js';

/**
 * Notifications push des cours (#43). APNs en HTTP/2 avec jeton de fournisseur ES256 (clé .p8 d'Apple). Aucun e-mail.
 * Sans configuration complète, le service ne démarre pas : rien n'est envoyé ni présumé envoyé.
 * Contrat : docs/implementation/cours-collectifs-notifications-43-44.md.
 */
export interface PushConfig { teamId:string; keyId:string; privateKey:string; topic:string; environment:'SANDBOX'|'PRODUCTION' }
export function pushConfig(env:NodeJS.ProcessEnv=process.env):PushConfig|undefined{
 if(!env.APNS_KEY_ID&&!env.APNS_TEAM_ID&&!env.APNS_PRIVATE_KEY)return undefined;
 return {teamId:z.string().regex(/^[A-Z0-9]{10}$/).parse(env.APNS_TEAM_ID),keyId:z.string().regex(/^[A-Z0-9]{10}$/).parse(env.APNS_KEY_ID),
  privateKey:z.string().includes('BEGIN PRIVATE KEY').parse(env.APNS_PRIVATE_KEY?.replace(/\\n/g,'\n')),
  topic:z.string().regex(/^[A-Za-z0-9.-]{3,155}$/).parse(env.APNS_TOPIC),
  environment:z.enum(['SANDBOX','PRODUCTION']).default('PRODUCTION').parse(env.APNS_ENVIRONMENT)};
}
export interface PushSender { send(token:string,environment:'SANDBOX'|'PRODUCTION',payload:object,expiresAt:Date|null,collapseId:string):Promise<'SENT'|'INVALID_TOKEN'|'RETRY'>; close():void }

/** Client APNs réel. Le jeton de fournisseur est renouvelé toutes les 50 minutes (Apple : entre 20 et 60). */
export function apnsSender(config:PushConfig):PushSender{
 const sessions=new Map<string,ClientHttp2Session>();let jwt:{value:string;at:number}|undefined;
 const token=async()=>{if(!jwt||Date.now()-jwt.at>50*60_000){const key=await importPKCS8(config.privateKey,'ES256');
  jwt={value:await new SignJWT({}).setProtectedHeader({alg:'ES256',kid:config.keyId}).setIssuer(config.teamId).setIssuedAt().sign(key),at:Date.now()};}return jwt.value;};
 const session=(environment:string)=>{const host=environment==='SANDBOX'?'https://api.sandbox.push.apple.com':'https://api.push.apple.com';
  let s=sessions.get(host);if(!s||s.closed||s.destroyed){s=connect(host);s.on('error',()=>sessions.delete(host));sessions.set(host,s);}return s;};
 return {
  async send(device,environment,payload,expiresAt,collapseId){
   const auth=await token();
   return await new Promise<'SENT'|'INVALID_TOKEN'|'RETRY'>(resolve=>{
    const request=session(environment).request({[constants.HTTP2_HEADER_METHOD]:'POST',[constants.HTTP2_HEADER_PATH]:`/3/device/${device}`,
     authorization:`bearer ${auth}`,'apns-topic':config.topic,'apns-push-type':'alert','apns-priority':'10','apns-collapse-id':collapseId.slice(0,64),
     'apns-expiration':expiresAt?String(Math.floor(expiresAt.getTime()/1000)):'0'});
    let status=0,bytes=0,settled=false;const chunks:Buffer[]=[];
    const finish=(result:'SENT'|'INVALID_TOKEN'|'RETRY')=>{if(!settled){settled=true;chunks.length=0;resolve(result);}};
    request.on('response',headers=>{status=Number(headers[constants.HTTP2_HEADER_STATUS]);});
    request.on('data',(chunk:Buffer)=>{
     if(settled)return;
     bytes+=chunk.length;
     // Ne conserver ni journaliser un corps fournisseur arbitrairement volumineux.
     if(bytes>4096){finish('RETRY');request.close();return;}
     chunks.push(chunk);
    });
    request.on('error',()=>finish('RETRY'));
    request.on('aborted',()=>finish('RETRY'));
    request.setTimeout(10_000,()=>{finish('RETRY');request.close();});
    request.on('end',()=>{
     if(settled)return;
     if(request.rstCode!==0){finish('RETRY');return;}
     if(status===200){finish('SENT');return;}
     let reason:unknown;
     try{const body:unknown=JSON.parse(Buffer.concat(chunks,bytes).toString('utf8'));
      if(body!==null&&typeof body==='object'&&!Array.isArray(body))reason=(body as {reason?:unknown}).reason;
     }catch{/* Réponse absente ou invalide : aucune révocation présumée. */}
     // Apple distingue les erreurs de requête/configuration des jetons invalides.
     // DeviceTokenNotForTopic peut être une erreur de topic, pas un appareil révoqué.
     finish((status===400&&reason==='BadDeviceToken')||
      (status===410&&(reason==='Unregistered'||reason==='ExpiredToken'))?'INVALID_TOKEN':'RETRY');
    });
    // close seul ne prouve jamais que le corps et END_STREAM ont été reçus.
    request.on('close',()=>finish('RETRY'));
    request.end(JSON.stringify(payload));request.resume();
   }).catch(()=>'RETRY' as const);
  },
  close(){for(const s of sessions.values())s.close();}
 };
}

/** Demandes de leçon et examens (#43/#44) : la charge ne porte que le texte générique et la catégorie. */
export const lessonExamCategories=Object.freeze(['LESSON_REQUEST','LESSON_REQUEST_ANSWER','EXAM'] as const);
export const isLessonExamCategory=(category:string)=>lessonExamCategories.some(value=>value===category);

/** Catégories de la file portées par la messagerie, pour les sélections SQL du service d'envoi. */
const messagingQueuedCategories:string[]=Object.keys(queuedMessagingCategories);

/** Identifiant de regroupement APNs : 64 octets au plus. Une clé plus longue est résumée (jamais tronquée : deux événements
 * distincts qui ne diffèrent que par la fin de leur clé ne doivent pas se regrouper). */
export const collapseIdFor=(key:string)=>key.length<=64?key:createHash('sha256').update(key).digest('hex');

/** Politique de reprise d'une destination : 5 envois au plus, délai de 2, 4, 8 puis 16 minutes entre deux essais. */
const MAX_DELIVERY_ATTEMPTS=5;

/** `recorded` : au moins un résultat de destination est écrit dans la transaction courante (voir `inWorkerTransaction`). */
interface UnitState{recorded:boolean}
interface NotificationToSend{id:string;person_id:string;valid_until:Date|null;dedupe_key:string}

/** Une unité de travail (une notification de cours, un groupe de messagerie) par transaction, sous le rôle du service.
 * Si l'envoi lève une exception après qu'un appareil a été confirmé ou écarté, ces résultats sont conservés : l'appareil déjà
 * servi n'est pas renvoyé au passage suivant. Sans résultat écrit, l'unité entière est annulée, comme avant. */
async function inWorkerTransaction<T>(db:PoolClient,work:(state:UnitState)=>Promise<T>):Promise<T>{
 const state:UnitState={recorded:false};
 await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');
 try{const result=await work(state);await db.query('COMMIT');return result;}
 catch(error){
  if(state.recorded){try{await db.query('COMMIT');}catch{/* La transaction est alors annulée par l'appelant. */}}
  throw error;
 }
}

/** Un passage : tâches temporelles et outbox (SQL), puis envoi d'au plus `limit` notifications dues. Idempotent.
 * Les alertes de cours partent une par une ; les alertes de messagerie sont regroupées par personne et conversation
 * (une au plus par groupe) et freinées par une fenêtre de calme de `MESSAGING_PUSH_QUIET_WINDOW_SECONDS` (#74).
 * Chaque destination (appareil) a son propre état (#448) : une notification n'est close que lorsqu'aucune destination
 * n'a de reprise valide, et seules les destinations en échec transitoire sont reprises. */
export async function processPushBatch(pool:Pool,sender:PushSender|undefined,limit=50):Promise<number>{
 const db:PoolClient=await pool.connect();let broken=false;
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');await db.query('SELECT drivy.course_notifications_tick()');await db.query('COMMIT');
  if(!sender)return 0;
  // Alertes de cours : une par une. La messagerie suit son propre regroupement ci-dessous et ne consomme donc pas leur quota.
  const due=await inWorkerTransaction(db,async()=>(await db.query<{id:string}>(
   `SELECT id FROM drivy.push_notification WHERE status='PENDING' AND available_at<=now() AND category<>ALL($2::text[]) ORDER BY available_at LIMIT $1`,[limit,messagingQueuedCategories])).rows);
  let processed=0;
  for(const {id} of due)if(await inWorkerTransaction(db,state=>sendCourseNotification(db,sender,id,state)))processed++;
  // Messagerie : un groupe par personne et conversation. Le quota porte sur les groupes, pas sur les messages en attente.
  const groups=await inWorkerTransaction(db,async()=>(await db.query<{person_id:string;school_id:string;conversation_id:string}>(
   `SELECT person_id,school_id,conversation_id FROM drivy.push_notification
    WHERE status='PENDING' AND available_at<=now() AND category=ANY($1::text[])
    GROUP BY person_id,school_id,conversation_id ORDER BY min(available_at) LIMIT $2`,[messagingQueuedCategories,limit])).rows);
  for(const group of groups)processed+=await inWorkerTransaction(db,state=>sendCoalescedMessaging(db,sender,group.person_id,group.school_id,group.conversation_id,state));
  return processed;
 }catch(error){broken=!(await rollbackQuietly(db));throw error;}finally{db.release(broken);}
}

/** Ligne de `push_notification` lue par le service d'envoi. */
interface PushNotificationRow{
 id:string;person_id:string;title:string;body:string;series_id:string|null;conversation_id:string|null;message_id:string|null;
 school_id:string;message_sequence:string|null;valid_until:Date|null;category:string;dedupe_key:string;attempts:number;
}
interface LockedMessagingAlert{
 id:string;title:string;body:string;category:QueuedMessagingCategory;message_id:string|null;message_sequence:string|null;
 valid_until:Date|null;dedupe_key:string;attempts:number;
}

/** Premier passage d'une notification : une destination par appareil actif. Les passages suivants reprennent les destinations
 * existantes, sans en ajouter (un appareil enregistré plus tard ne reçoit pas une alerte ancienne). Faux : aucun appareil. */
async function openDeliveries(db:PoolClient,notification:NotificationToSend):Promise<boolean>{
 if((await db.query('SELECT 1 FROM drivy.push_delivery WHERE notification_id=$1 LIMIT 1',[notification.id])).rowCount!==0)return true;
 return (await db.query('INSERT INTO drivy.push_delivery(notification_id,device_id) SELECT $1,id FROM drivy.push_device WHERE person_id=$2 AND revoked_at IS NULL ON CONFLICT DO NOTHING',
  [notification.id,notification.person_id])).rowCount!==0;
}

const finishDelivery=(db:PoolClient,notificationId:string,deviceId:string,status:'SENT'|'REJECTED'|'REVOKED'|'EXPIRED',code:string|null)=>
 db.query('UPDATE drivy.push_delivery SET status=$3,failure_code=$4,attempts=attempts+$5,completed_at=statement_timestamp() WHERE notification_id=$1 AND device_id=$2',
  [notificationId,deviceId,status,code,status==='REVOKED'?0:1]);

/** Envoie aux seules destinations encore en attente et écrit le résultat de chacune.
 * Autorisation par tentative : après tout envoi attendu (pendant lequel droits, préférences, échéance ou appareils ont pu
 * changer dans une autre connexion), `revalidate` est relu AVANT la destination suivante ; s'il refuse, la fonction SQL a déjà
 * clos la notification et, par déclencheur, ses destinations restantes. L'appareil est relu juste avant son envoi (jamais depuis
 * un instantané pris avant la boucle) : révoqué ou repris par une autre personne, il est clos sans envoi.
 * Retourne faux quand l'autorisation est perdue : l'appelant ne doit alors pas clore la notification lui-même. */
async function attemptDeliveries(db:PoolClient,sender:PushSender,notification:NotificationToSend,payload:object,state:UnitState,
 revalidate:()=>Promise<boolean>):Promise<boolean>{
 const targets=(await db.query<{device_id:string;attempts:number}>(
  `SELECT device_id,attempts FROM drivy.push_delivery WHERE notification_id=$1 AND status='PENDING' ORDER BY device_id FOR UPDATE`,[notification.id])).rows;
 let awaited=false;
 for(const target of targets){
  if(awaited){if(!(await revalidate()))return false;awaited=false;}
  const device=(await db.query<{token:string;environment:'SANDBOX'|'PRODUCTION';revoked_at:Date|null;owned:boolean;version:string}>(
   'SELECT token,environment,revoked_at,(person_id=$2) AS owned,last_seen_at::text AS version FROM drivy.push_device WHERE id=$1',[target.device_id,notification.person_id])).rows[0];
  if(!device||device.revoked_at!==null||!device.owned){await finishDelivery(db,notification.id,target.device_id,'REVOKED','DEVICE_UNAVAILABLE');state.recorded=true;continue;}
  const result=await sender.send(device.token,device.environment,payload,notification.valid_until,collapseIdFor(notification.dedupe_key));
  awaited=true;
  if(result==='SENT')await finishDelivery(db,notification.id,target.device_id,'SENT',null);
  else if(result==='INVALID_TOKEN'){
   await finishDelivery(db,notification.id,target.device_id,'REJECTED','INVALID_TOKEN');
   // Garde de version : `last_seen_at` change à chaque (ré)enregistrement du jeton, y compris par la même personne avec un
   // nouveau secret. Une réponse tardive portant sur l'état lu avant l'envoi ne révoque pas un enregistrement renouvelé.
   // Les destinations sont traitées par identifiant d'appareil croissant : deux notifications concurrentes verrouillent les
   // appareils communs dans le même ordre (pas d'interblocage).
   await db.query('UPDATE drivy.push_device SET revoked_at=now() WHERE id=$1 AND token=$2 AND person_id=$3 AND environment=$4 AND last_seen_at::text=$5 AND revoked_at IS NULL',
    [target.device_id,device.token,notification.person_id,device.environment,device.version]);
  }else if(target.attempts+1>=MAX_DELIVERY_ATTEMPTS)await finishDelivery(db,notification.id,target.device_id,'EXPIRED','RETRY_EXHAUSTED');
  else await db.query("UPDATE drivy.push_delivery SET attempts=attempts+1,failure_code='APNS_RETRY' WHERE notification_id=$1 AND device_id=$2",[notification.id,target.device_id]);
  state.recorded=true;
 }
 return true;
}

/** Clôture globale : seulement quand aucune destination n'a de reprise valide. Un envoi accepté par APNs ne vaut ni lecture ni
 * acceptation. Avec des reprises restantes, la notification reste PENDING et revient à l'échéance de la politique de reprise. */
async function settleNotification(db:PoolClient,notificationId:string):Promise<void>{
 const s=(await db.query<{pending:number;sent:number;exhausted:number;next_attempts:number|null}>(
  `SELECT count(*) FILTER (WHERE status='PENDING')::int AS pending,count(*) FILTER (WHERE status='SENT')::int AS sent,
    count(*) FILTER (WHERE status='EXPIRED')::int AS exhausted,max(attempts) FILTER (WHERE status='PENDING')::int AS next_attempts
   FROM drivy.push_delivery WHERE notification_id=$1`,[notificationId])).rows[0]!;
 if(s.pending>0)await db.query("UPDATE drivy.push_notification SET attempts=attempts+1,available_at=now()+make_interval(mins=>power(2,$2::int)::int) WHERE id=$1",[notificationId,s.next_attempts??1]);
 else if(s.sent>0)await db.query("UPDATE drivy.push_notification SET status='SENT',sent_at=statement_timestamp(),attempts=attempts+1 WHERE id=$1",[notificationId]);
 else await db.query("UPDATE drivy.push_notification SET status='FAILED',attempts=attempts+1,failure_code=$2 WHERE id=$1",[notificationId,s.exhausted>0?'APNS_UNAVAILABLE':'NO_VALID_DEVICE']);
}

/** Une alerte de cours (ou de demande de leçon, d'examen) : relue, puis envoyée destination par destination.
 * Retourne faux quand une autre instance du service l'a déjà prise ou qu'elle n'est plus due. */
async function sendCourseNotification(db:PoolClient,sender:PushSender,id:string,state:UnitState):Promise<boolean>{
 const n=(await db.query<PushNotificationRow>(
  `SELECT id,person_id,title,body,series_id,conversation_id,message_id,school_id,message_sequence,valid_until,category,dedupe_key,attempts FROM drivy.push_notification
   WHERE id=$1 AND status='PENDING' AND available_at<=now() AND category<>ALL($2::text[]) FOR UPDATE SKIP LOCKED`,[id,messagingQueuedCategories])).rows[0];
 if(!n)return false;
 // Relecture à chaque tentative, y compris après un tick ancien ou une reprise (un refus clôt aussi les destinations restantes).
 if(!(await db.query<{allowed:boolean}>('SELECT drivy.push_revalidate($1::uuid) AS allowed',[n.id])).rows[0]?.allowed)return true;
 if(!(await openDeliveries(db,n))){await db.query("UPDATE drivy.push_notification SET status='SKIPPED',failure_code='NO_DEVICE' WHERE id=$1",[n.id]);return true;}
 // Demandes et examens n'emportent que le texte et la catégorie ; les cours gardent leur charge déployée.
 const payload=isLessonExamCategory(n.category)?{aps:{alert:{title:n.title,body:n.body}},category:n.category}
  :{aps:{alert:{title:n.title,body:n.body},sound:'default'},seriesId:n.series_id,category:n.category};
 if(await attemptDeliveries(db,sender,n,payload,state,async()=>(await db.query<{allowed:boolean}>('SELECT drivy.push_revalidate($1::uuid) AS allowed',[n.id])).rows[0]?.allowed===true))
  await settleNotification(db,n.id);
 return true;
}

/** Relit les faits d'une alerte de messagerie et décide. Retourne la charge à envoyer, ou null : l'alerte est alors close
 * (SKIPPED avec son motif, ou déjà EXPIRED/non PENDING par la fonction SQL) et ses destinations restantes avec elle. */
async function evaluateMessagingAlert(db:PoolClient,alert:LockedMessagingAlert,personId:string,schoolId:string,conversationId:string):Promise<ReturnType<typeof messagingPushPayload>|null>{
 const hasDevice=(await db.query('SELECT 1 FROM drivy.push_device WHERE person_id=$1 AND revoked_at IS NULL LIMIT 1',[personId])).rowCount!==0;
 const facts=(await db.query<MessagingSnapshotRow>('SELECT * FROM drivy.push_messaging_snapshot($1::uuid)',[alert.id])).rows[0];
 // Plus en attente ou périmée (la fonction l'a alors marquée) : rien à envoyer.
 if(!facts)return null;
 const {event,snapshot}=messagingNotificationInputs({person_id:personId,school_id:schoolId,conversation_id:conversationId,message_id:alert.message_id},facts,hasDevice);
 const decision=decideMessagingNotification(event,snapshot),sequence=Number(alert.message_sequence);
 // La catégorie mise en file doit rester celle de l'événement relu : une mention ne devient jamais une alerte du général.
 const skip=!decision.allowed?messagingSkipCode(decision.reason)
  :queuedMessagingCategories[alert.category]!==decision.category||!Number.isSafeInteger(sequence)||sequence<1?'EVENT_OBSOLETE':undefined;
 if(skip!==undefined||!decision.allowed){await db.query("UPDATE drivy.push_notification SET status='SKIPPED',failure_code=$2 WHERE id=$1",[alert.id,skip??'EVENT_OBSOLETE']);return null;}
 return messagingPushPayload(event,decision,sequence,{title:alert.title,body:alert.body});
}

/** Regroupement anti-rafale de la messagerie (#74) : au plus une alerte par personne et par conversation.
 * Toutes les alertes PENDING dues de ce groupe sont verrouillées dans la transaction courante ; un verrou consultatif par
 * groupe empêche deux passages du service de traiter le même groupe, sans jamais bloquer les autres personnes.
 * Ordre : la plus récente alerte autorisée par la revalidation existante part ; une mention autorisée prime. Les autres
 * passent en SKIPPED/COALESCED, et une alerte refusée garde son motif de refus. Un envoi récent pour la conversation
 * reporte le groupe à `sent_at + MESSAGING_PUSH_QUIET_WINDOW_SECONDS` sans consommer de tentative.
 * Une alerte déjà partie vers certains appareils (#448) n'est jamais regroupée : elle reprend ses seules destinations en
 * attente, hors fenêtre de calme, pour ne pas perdre l'appareil resté en échec transitoire.
 * Retourne le nombre d'alertes examinées (envoyées, regroupées, refusées ou reportées). */
async function sendCoalescedMessaging(db:PoolClient,sender:PushSender,personId:string,schoolId:string,conversationId:string,state:UnitState):Promise<number>{
 const locked=(await db.query<{locked:boolean}>('SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) AS locked',
  [`messaging-push:${personId}:${conversationId}`])).rows[0]?.locked===true;
 if(!locked)return 0;
 const rows=(await db.query<LockedMessagingAlert>(
  `SELECT id,title,body,category::text AS category,message_id,message_sequence,valid_until,dedupe_key,attempts FROM drivy.push_notification
   WHERE person_id=$1 AND conversation_id=$2 AND status='PENDING' AND available_at<=now() AND category=ANY($3::text[])
   ORDER BY message_sequence DESC NULLS LAST,created_at DESC,id DESC FOR UPDATE`,[personId,conversationId,messagingQueuedCategories])).rows;
 if(!rows.length)return 0;
 const resuming=new Set((await db.query<{notification_id:string}>('SELECT DISTINCT notification_id FROM drivy.push_delivery WHERE notification_id=ANY($1::uuid[])',[rows.map(row=>row.id)])).rows.map(row=>row.notification_id));
 // Fenêtre de calme : un envoi récent de la même conversation reporte les alertes neuves du groupe, sans incrémenter attempts.
 // Un envoi compte dès qu'une destination l'a accepté, même si la notification attend encore la reprise d'un autre appareil.
 const lastSentAt=(await db.query<{sent_at:Date}>(
  `SELECT max(t) AS sent_at FROM (
    SELECT sent_at AS t FROM drivy.push_notification WHERE person_id=$1 AND conversation_id=$2 AND category=ANY($3::text[]) AND status='SENT'
     AND sent_at>statement_timestamp()-make_interval(secs=>$4)
    UNION ALL
    SELECT d.completed_at FROM drivy.push_delivery d JOIN drivy.push_notification n ON n.id=d.notification_id
     WHERE n.person_id=$1 AND n.conversation_id=$2 AND n.category=ANY($3::text[]) AND d.status='SENT'
     AND d.completed_at>statement_timestamp()-make_interval(secs=>$4)) sent`,
  [personId,conversationId,messagingQueuedCategories,MESSAGING_PUSH_QUIET_WINDOW_SECONDS])).rows[0]?.sent_at;
 const examined=lastSentAt?rows.filter(row=>resuming.has(row.id)):rows;
 if(lastSentAt){
  const deferred=rows.filter(row=>!resuming.has(row.id)).map(row=>row.id);
  if(deferred.length)await db.query(
   `UPDATE drivy.push_notification SET available_at=$2::timestamptz+make_interval(secs=>$3) WHERE id=ANY($1::uuid[])`,
   [deferred,lastSentAt,MESSAGING_PUSH_QUIET_WINDOW_SECONDS]);
  if(!examined.length)return rows.length;
 }
 // Messagerie : faits relus alerte par alerte (et avant chaque destination), décision par decideMessagingNotification.
 const allowed:{alert:LockedMessagingAlert;payload:ReturnType<typeof messagingPushPayload>}[]=[];
 for(const alert of examined){
  const payload=await evaluateMessagingAlert(db,alert,personId,schoolId,conversationId);
  if(payload)allowed.push({alert,payload});
 }
 const toSend=(item:typeof allowed[number])=>({id:item.alert.id,person_id:personId,valid_until:item.alert.valid_until,dedupe_key:item.alert.dedupe_key});
 // Reprises : chaque alerte déjà entamée garde ses destinations en attente, sans regroupement.
 for(const item of allowed.filter(item=>resuming.has(item.alert.id))){
  if(await attemptDeliveries(db,sender,toSend(item),item.payload,state,async()=>(await evaluateMessagingAlert(db,item.alert,personId,schoolId,conversationId))!==null))
   await settleNotification(db,item.alert.id);
 }
 const fresh=allowed.filter(item=>!resuming.has(item.alert.id));
 const chosen=chooseCoalescedMessagingAlert(fresh.map(item=>({...item,category:item.alert.category})));
 if(!chosen)return rows.length;
 // Les autres alertes autorisées du groupe ne partent pas : elles sont regroupées dans celle qui part.
 for(const other of fresh)if(other.alert.id!==chosen.alert.id)
  await db.query("UPDATE drivy.push_notification SET status='SKIPPED',failure_code='COALESCED' WHERE id=$1",[other.alert.id]);
 if(!(await openDeliveries(db,toSend(chosen)))){
  await db.query("UPDATE drivy.push_notification SET status='FAILED',attempts=attempts+1,failure_code='NO_VALID_DEVICE' WHERE id=$1",[chosen.alert.id]);
  return rows.length;
 }
 if(await attemptDeliveries(db,sender,toSend(chosen),chosen.payload,state,async()=>(await evaluateMessagingAlert(db,chosen.alert,personId,schoolId,conversationId))!==null))
  await settleNotification(db,chosen.alert.id);
 return rows.length;
}
