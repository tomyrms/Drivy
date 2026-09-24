import { createCipheriv,createDecipheriv,randomBytes,randomUUID } from 'node:crypto';
import nodemailer from 'nodemailer';
import type { Pool,PoolClient } from 'pg';
import { z } from 'zod';

export interface InvitationMailConfig {
  webURL:string; encryptionKey:string; host:string; port:number; secure:boolean; from:string;
  requireTLS:boolean; user?:string; password?:string;
}
const loopback=(host:string)=>['localhost','127.0.0.1','[::1]','::1'].includes(host);
export function invitationMailConfig(env:NodeJS.ProcessEnv=process.env):InvitationMailConfig|undefined {
  if(!env.INVITATION_WEB_URL && !env.INVITATION_OUTBOX_KEY && !env.SMTP_HOST) return undefined;
  const webURL=new URL(z.url().parse(env.INVITATION_WEB_URL));
  const local=env.NODE_ENV!=='production' && loopback(webURL.hostname);
  if(webURL.username || webURL.password || webURL.search || webURL.hash || (webURL.protocol!=='https:' && !(local && webURL.protocol==='http:'))) throw new Error('Configuration du lien d’invitation invalide.');
  const host=z.string().min(1).parse(env.SMTP_HOST);
  const secure=z.enum(['true','false']).default('false').parse(env.SMTP_SECURE)==='true';
  const user=env.SMTP_USER;const password=env.SMTP_PASSWORD;
  if(Boolean(user)!==Boolean(password)) throw new Error('Configuration SMTP incomplète.');
  return {webURL:webURL.href,encryptionKey:z.string().regex(/^[a-fA-F0-9]{64}$/).parse(env.INVITATION_OUTBOX_KEY),host,
    port:z.coerce.number().int().min(1).max(65535).default(587).parse(env.SMTP_PORT),secure,
    from:z.email().parse(env.SMTP_FROM),requireTLS:env.NODE_ENV==='production' || !loopback(host),
    ...(user && password?{user,password}:{})};
}
interface MailPayload { email:string; token:string; schoolName:string; roles:string[] }
export function encryptMail(id:string,payload:MailPayload,key:string):Buffer {
  const iv=randomBytes(12);const cipher=createCipheriv('aes-256-gcm',Buffer.from(key,'hex'),iv);
  cipher.setAAD(Buffer.from(id));const ciphertext=Buffer.concat([cipher.update(JSON.stringify(payload),'utf8'),cipher.final()]);
  return Buffer.concat([iv,cipher.getAuthTag(),ciphertext]);
}
function decryptMail(id:string,encrypted:Buffer,key:string):MailPayload {
  const cipher=createDecipheriv('aes-256-gcm',Buffer.from(key,'hex'),encrypted.subarray(0,12));
  cipher.setAAD(Buffer.from(id));cipher.setAuthTag(encrypted.subarray(12,28));
  const value=JSON.parse(Buffer.concat([cipher.update(encrypted.subarray(28)),cipher.final()]).toString('utf8')) as unknown;
  return z.object({email:z.email(),token:z.string().regex(/^[A-Za-z0-9_-]{43}$/),schoolName:z.string().min(1),roles:z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER']))}).strict().parse(value);
}
export async function queueInvitationMail(db:PoolClient,config:InvitationMailConfig,schoolId:string,invitationId:string,version:number,payload:MailPayload) {
  const id=randomUUID();await db.query(`INSERT INTO drivy.invitation_mail(id,school_id,invitation_id,invitation_version,payload)
    VALUES($1,$2,$3,$4,$5)`,[id,schoolId,invitationId,version,encryptMail(id,payload,config.encryptionKey)]);
}
export async function cancelInvitationMail(db:PoolClient,invitationId:string) {
  await db.query(`UPDATE drivy.invitation_mail SET status='CANCELLED',payload=NULL,lease_id=NULL,lease_until=NULL
    WHERE invitation_id=$1 AND status IN('QUEUED','PROCESSING','FAILED')`,[invitationId]);
}
interface Job { id:string; payload:Buffer; invitation_id:string; invitation_version:number; lease_id:string; attempts:number }
async function workerTransaction<T>(pool:Pool,work:(db:PoolClient)=>Promise<T>):Promise<T> {
  const db=await pool.connect();try {await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_invitation_mailer');
    const result=await work(db);await db.query('COMMIT');return result;
  } catch(error) {await db.query('ROLLBACK');throw error;} finally {db.release();}
}
/** Une itération bornée ; aucune adresse, jeton ou réponse SMTP n'est journalisée. */
export async function deliverOneInvitation(pool:Pool,config:InvitationMailConfig):Promise<boolean> {
  const job=await workerTransaction(pool,async db=>{
    // La purge concerne aussi les échecs définitifs expirés, sans attendre une nouvelle commande.
    await db.query(`UPDATE drivy.invitation_mail o SET status='CANCELLED',payload=NULL,lease_id=NULL,lease_until=NULL
      FROM drivy.invitation i WHERE i.id=o.invitation_id AND o.status IN('QUEUED','PROCESSING','FAILED')
      AND (i.status<>'PENDING' OR i.expires_at<=now() OR i.version<>o.invitation_version)`);
    const selected=await db.query<Job>(`SELECT id,payload,invitation_id,invitation_version,attempts FROM drivy.invitation_mail
      WHERE (status='QUEUED' AND available_at<=now()) OR (status='PROCESSING' AND lease_until<now())
      ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1`);
    const current=selected.rows[0];if(!current) return undefined;
    if(current.attempts>=5) {await db.query("UPDATE drivy.invitation_mail SET status='FAILED',failure_code='RETRY_EXHAUSTED',lease_id=NULL,lease_until=NULL WHERE id=$1",[current.id]);return undefined;}
    current.lease_id=randomUUID();await db.query(`UPDATE drivy.invitation_mail SET status='PROCESSING',attempts=attempts+1,
      lease_id=$2,lease_until=now()+interval '60 seconds' WHERE id=$1`,[current.id,current.lease_id]);return current;
  });
  if(!job) return false;
  const valid=await workerTransaction(pool,async db=>(await db.query(`SELECT 1 FROM drivy.invitation i
    JOIN drivy.school s ON s.id=i.school_id JOIN drivy.membership m ON m.id=i.inviter_membership_id
    JOIN drivy.person p ON p.id=m.person_id JOIN drivy.invitation_mail o ON o.invitation_id=i.id
    WHERE o.id=$1 AND o.status='PROCESSING' AND o.lease_id=$2 AND i.version=$3 AND i.status='PENDING'
      AND i.expires_at>now() AND s.status='ACTIVE' AND m.status='ACTIVE' AND p.status='ACTIVE'
      AND ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND i.roles=ARRAY['LEARNER']::text[]))`,[job.id,job.lease_id,job.invitation_version])).rowCount);
  if(!valid) {await workerTransaction(pool,async db=>{await db.query(`UPDATE drivy.invitation_mail SET status='CANCELLED',payload=NULL,lease_id=NULL,lease_until=NULL
    WHERE id=$1 AND lease_id=$2`,[job.id,job.lease_id]);});return true;}
  let failure='PAYLOAD_INVALID';
  try {
    const message=decryptMail(job.id,job.payload,config.encryptionKey);failure='SMTP_FAILED';
    const transport=nodemailer.createTransport({host:config.host,port:config.port,secure:config.secure,requireTLS:config.requireTLS,
      ...(config.user && config.password?{auth:{user:config.user,pass:config.password}}:{}),logger:false,debug:false,
      connectionTimeout:10_000,greetingTimeout:10_000,socketTimeout:20_000,disableFileAccess:true,disableUrlAccess:true});
    try {
      const link=new URL(config.webURL);link.hash=`token=${message.token}`;
      const labels:Record<string,string>={ADMIN:'Administration',INSTRUCTOR:'Moniteur',LEARNER:'Élève'};
      await transport.sendMail({from:config.from,to:message.email,messageId:`<drivy-invitation-${job.id}@${new URL(config.webURL).hostname}>`,
        subject:`Invitation Drivy — ${message.schoolName}`,text:`L’école ${message.schoolName} vous invite sur Drivy.\nRôles proposés : ${message.roles.map(role=>labels[role]).join(', ')}.\n\nOuvrez ce lien pour lire les informations de l’école et choisir explicitement d’accepter :\n${link.href}\n\nCe lien expire après sept jours. Si cette invitation ne vous concerne pas, vous pouvez l’ignorer.`});
    } finally {transport.close();}
    await workerTransaction(pool,async db=>{await db.query(`UPDATE drivy.invitation_mail SET status='SENT',payload=NULL,sent_at=now(),lease_id=NULL,lease_until=NULL,failure_code=NULL
      WHERE id=$1 AND status='PROCESSING' AND lease_id=$2`,[job.id,job.lease_id]);});
  } catch {
    await workerTransaction(pool,async db=>{await db.query(`UPDATE drivy.invitation_mail SET status=CASE WHEN attempts>=5 OR $3='PAYLOAD_INVALID' THEN 'FAILED' ELSE 'QUEUED' END,
      failure_code=$3,available_at=now()+interval '60 seconds',lease_id=NULL,lease_until=NULL WHERE id=$1 AND status='PROCESSING' AND lease_id=$2`,[job.id,job.lease_id,failure]);});
  }
  return true;
}
