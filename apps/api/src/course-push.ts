import { connect, constants, type ClientHttp2Session } from 'node:http2';
import { importPKCS8, SignJWT } from 'jose';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import { rollbackQuietly } from './database.js';
import { decideMessagingNotification, isQueuedMessagingCategory, messagingNotificationInputs, messagingPushPayload, messagingSkipCode, queuedMessagingCategories, type MessagingSnapshotRow } from './messaging-notifications.js';

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

/** Un passage : tâches temporelles et outbox (SQL), puis envoi d'au plus `limit` notifications dues. Idempotent. */
export async function processPushBatch(pool:Pool,sender:PushSender|undefined,limit=50):Promise<number>{
 const db:PoolClient=await pool.connect();let broken=false;
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');await db.query('SELECT drivy.course_notifications_tick()');await db.query('COMMIT');
  if(!sender)return 0;
  await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_course_worker');
  const due=(await db.query<{id:string;person_id:string;title:string;body:string;series_id:string|null;conversation_id:string|null;message_id:string|null;school_id:string;message_sequence:string|null;valid_until:Date|null;category:string;dedupe_key:string;attempts:number}>(
   `SELECT id,person_id,title,body,series_id,conversation_id,message_id,school_id,message_sequence,valid_until,category,dedupe_key,attempts FROM drivy.push_notification WHERE status='PENDING' AND available_at<=now() ORDER BY available_at LIMIT $1 FOR UPDATE SKIP LOCKED`,[limit])).rows;
  for(const n of due){
   const devices=(await db.query<{id:string;token:string;environment:'SANDBOX'|'PRODUCTION'}>('SELECT id,token,environment FROM drivy.push_device WHERE person_id=$1 AND revoked_at IS NULL',[n.person_id])).rows;
   // Messagerie : faits relus ici, décision par decideMessagingNotification (messaging-notifications.ts). Aucun accès direct aux tables métier.
   let messagingPayload:ReturnType<typeof messagingPushPayload>|undefined;
   if(isQueuedMessagingCategory(n.category)){
    const facts=(await db.query<MessagingSnapshotRow>('SELECT * FROM drivy.push_messaging_snapshot($1::uuid)',[n.id])).rows[0];
    // Plus en attente ou périmée (la fonction l'a alors marquée) : rien à envoyer.
    if(!facts)continue;
    const {event,snapshot}=messagingNotificationInputs({person_id:n.person_id,school_id:n.school_id,conversation_id:n.conversation_id??'',message_id:n.message_id},facts,devices.length>0);
    const decision=decideMessagingNotification(event,snapshot),sequence=Number(n.message_sequence);
    // La catégorie mise en file doit rester celle de l'événement relu : une mention ne devient jamais une alerte du général.
    const skip=!decision.allowed?messagingSkipCode(decision.reason)
     :queuedMessagingCategories[n.category]!==decision.category||!Number.isSafeInteger(sequence)||sequence<1?'EVENT_OBSOLETE':undefined;
    if(skip!==undefined||!decision.allowed){await db.query("UPDATE drivy.push_notification SET status='SKIPPED',failure_code=$2 WHERE id=$1",[n.id,skip??'EVENT_OBSOLETE']);continue;}
    // Titre générique de la ligne en file, corps vide : ni contenu ni nom d'auteur ni nom de conversation.
    messagingPayload=messagingPushPayload(event,decision,sequence,{title:n.title,body:n.body});
   }else{
    // Relecture à chaque notification, y compris après un tick ancien ou une reprise.
    if(!(await db.query<{allowed:boolean}>('SELECT drivy.push_revalidate($1::uuid) AS allowed',[n.id])).rows[0]?.allowed)continue;
    if(!devices.length){await db.query("UPDATE drivy.push_notification SET status='SKIPPED',failure_code='NO_DEVICE' WHERE id=$1",[n.id]);continue;}
   }
   let sent=false,retry=false;
   for(const d of devices){
    const payload=messagingPayload??{aps:{alert:{title:n.title,body:n.body},sound:'default'},seriesId:n.series_id,category:n.category};
    const result=await sender.send(d.token,d.environment,payload,n.valid_until,n.dedupe_key);
    if(result==='SENT')sent=true;else if(result==='INVALID_TOKEN')await db.query('UPDATE drivy.push_device SET revoked_at=now() WHERE id=$1',[d.id]);else retry=true;
   }
   // Un envoi réussi ne vaut ni lecture ni acceptation. Un échec est retenté au plus 5 fois, puis abandonné (la donnée reste visible dans l'app).
   if(sent)await db.query("UPDATE drivy.push_notification SET status='SENT',sent_at=now(),attempts=attempts+1 WHERE id=$1",[n.id]);
   else if(retry&&n.attempts<4)await db.query("UPDATE drivy.push_notification SET attempts=attempts+1,available_at=now()+make_interval(mins=>power(2,attempts+1)::int) WHERE id=$1",[n.id]);
   else await db.query("UPDATE drivy.push_notification SET status='FAILED',attempts=attempts+1,failure_code=$2 WHERE id=$1",[n.id,retry?'APNS_UNAVAILABLE':'NO_VALID_DEVICE']);
  }
  await db.query('COMMIT');return due.length;
 }catch(error){broken=!(await rollbackQuietly(db));throw error;}finally{db.release(broken);}
}
