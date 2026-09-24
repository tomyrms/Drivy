import { createCipheriv,createDecipheriv,createHash,randomBytes } from 'node:crypto';
import { exportJWK,importJWK,jwtVerify,SignJWT,type JWK } from 'jose';
import { z } from 'zod';
import { ApiError } from './errors.js';
import { trackPoint,type CaptureRow,type ChunkInput,type TrackPoint } from './capture-contracts.js';

const profile=z.object({version:z.string().min(1).max(100),platform:z.enum(['IOS','ANDROID']),deviceClass:z.enum(['PHONE','TABLET']),modelCode:z.string().min(1).max(100),osVersion:z.string().min(1).max(100),appBuild:z.string().min(1).max(100),expiresAt:z.iso.datetime({offset:true}),maxSampleAgeSeconds:z.number().int().min(0).max(60),maxHorizontalAccuracyMeters:z.number().positive().max(1000),minimumFreeBytes:z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),requireBackground:z.boolean(),requirePreciseLocation:z.boolean()}).strict();
export type QualificationProfile=z.infer<typeof profile>;
export interface CaptureConfig {encryptionKey:Buffer;encryptionKeyId:string;signingKey:JWK&{kid:string};issuer:string;profiles:QualificationProfile[];uploadHours:number}
/** Configuration absente : les diagnostics restent possibles, aucune autorisation n'est fabriquée. */
export function readCaptureConfig(env:NodeJS.ProcessEnv=process.env):CaptureConfig|undefined {
 const names=['CAPTURE_ENCRYPTION_KEY_HEX','CAPTURE_ENCRYPTION_KEY_ID','CAPTURE_SIGNING_PRIVATE_JWK','CAPTURE_AUTHORITY_ISSUER'];
 if(names.every(n=>!env[n]))return undefined;
 try {
  const key=z.string().regex(/^[a-fA-F0-9]{64}$/).parse(env.CAPTURE_ENCRYPTION_KEY_HEX),encryptionKeyId=z.string().regex(/^[a-zA-Z0-9_-]{1,80}$/).parse(env.CAPTURE_ENCRYPTION_KEY_ID);
  const signingKey=z.object({kty:z.literal('OKP'),crv:z.literal('Ed25519'),x:z.string().min(1),d:z.string().min(1),kid:z.string().regex(/^[a-zA-Z0-9_-]{1,80}$/)}).parse(JSON.parse(env.CAPTURE_SIGNING_PRIVATE_JWK??''));
  const issuer=z.url().parse(env.CAPTURE_AUTHORITY_ISSUER),url=new URL(issuer);
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash)throw new Error();
  const profiles=z.array(profile).max(100).parse(JSON.parse(env.CAPTURE_QUALIFICATION_PROFILES_JSON??'[]'));
  if(new Set(profiles.map(p=>[p.platform,p.deviceClass,p.modelCode,p.osVersion,p.appBuild].join('/'))).size!==profiles.length)throw new Error();
  return {encryptionKey:Buffer.from(key,'hex'),encryptionKeyId,signingKey,issuer,profiles,uploadHours:z.coerce.number().int().min(1).max(168).default(72).parse(env.CAPTURE_UPLOAD_HOURS)};
 }catch{throw new Error('Configuration capture invalide ; aucun secret n’est affiché.');}
}
/** Le hash porte uniquement sur ce contenu canonique, jamais sur le jeton ou operationId. */
export function canonicalCaptureJSON(value:unknown):string {
 if(Array.isArray(value))return `[${value.map(canonicalCaptureJSON).join(',')}]`;
 if(value!==null&&typeof value==='object')return `{${Object.entries(value).sort(([a],[b])=>a<b?-1:a>b?1:0).map(([key,v])=>`${JSON.stringify(key)}:${canonicalCaptureJSON(v)}`).join(',')}}`;
 return JSON.stringify(value);
}
export function trackContentHash(body:Pick<ChunkInput,'segmentIndex'|'segmentStartedAt'|'segmentStartReason'|'points'>){return createHash('sha256').update(canonicalCaptureJSON({segmentIndex:body.segmentIndex,segmentStartedAt:body.segmentStartedAt,segmentStartReason:body.segmentStartReason,points:body.points})).digest('hex');}
export function chunkAAD(schoolId:string,captureId:string,segmentId:string,chunkIndex:number,hash:string){return Buffer.from(canonicalCaptureJSON({schoolId,captureId,segmentId,chunkIndex,hash}));}
export function encryptPoints(config:CaptureConfig,points:TrackPoint[],aad:Buffer){const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',config.encryptionKey,nonce);cipher.setAAD(aad);const ciphertext=Buffer.concat([cipher.update(JSON.stringify(points),'utf8'),cipher.final()]);return Buffer.concat([nonce,cipher.getAuthTag(),ciphertext]);}
export function decryptPoints(config:CaptureConfig,encrypted:Buffer,keyId:string,aad:Buffer):TrackPoint[]{
 if(keyId!==config.encryptionKeyId)throw new ApiError(503,'CAPTURE_KEY_UNAVAILABLE','La clé de cette capture n’est pas disponible.');
 try{const decipher=createDecipheriv('aes-256-gcm',config.encryptionKey,encrypted.subarray(0,12));decipher.setAuthTag(encrypted.subarray(12,28));decipher.setAAD(aad);return z.array(trackPoint).max(1000).parse(JSON.parse(Buffer.concat([decipher.update(encrypted.subarray(28)),decipher.final()]).toString('utf8')));}catch{throw new ApiError(503,'CAPTURE_DATA_UNAVAILABLE','La capture chiffrée ne peut pas être relue.');}
}
export class CaptureAuthority {
 constructor(readonly config:CaptureConfig){}
 private publicJWK(){const {d:_private,...publicKey}=this.config.signingKey;return publicKey;}
 async publicKeys(){const key=await importJWK(this.publicJWK(),'EdDSA');return {keys:[{...await exportJWK(key),kid:this.config.signingKey.kid,alg:'EdDSA',use:'sig'}]};}
 async sign(capture:CaptureRow,scope:'capture:collect'|'capture:upload'){
  const expiry=scope==='capture:collect'?capture.expires_at:capture.upload_deadline;
  return new SignJWT({scope,schoolId:capture.school_id,captureId:capture.id,lessonId:capture.lesson_id,deviceId:capture.device_id,deviceAssessmentId:capture.device_assessment_id,authorizedAt:capture.authorized_at.toISOString(),expiresAt:capture.expires_at.toISOString(),uploadDeadline:capture.upload_deadline.toISOString()})
   .setProtectedHeader({alg:'EdDSA',kid:this.config.signingKey.kid,typ:'drivy-capture+jwt'}).setIssuer(this.config.issuer).setAudience('drivy-native-capture').setSubject(capture.person_id).setJti(`${capture.id}:${scope}`).setIssuedAt(Math.floor(capture.authorized_at.getTime()/1000)).setExpirationTime(Math.floor(expiry.getTime()/1000)).sign(await importJWK(this.config.signingKey,'EdDSA'));
 }
 async verifyUpload(token:string,capture:CaptureRow,personId:string){
  try{const result=await jwtVerify(token,await importJWK(this.publicJWK(),'EdDSA'),{algorithms:['EdDSA'],issuer:this.config.issuer,audience:'drivy-native-capture',typ:'drivy-capture+jwt'}),p=result.payload;
   if(result.protectedHeader.kid!==this.config.signingKey.kid||p.scope!=='capture:upload'||p.sub!==personId||p.sub!==capture.person_id||p.captureId!==capture.id||p.schoolId!==capture.school_id||p.lessonId!==capture.lesson_id||p.deviceId!==capture.device_id||p.deviceAssessmentId!==capture.device_assessment_id||p.exp!==Math.floor(capture.upload_deadline.getTime()/1000))throw new Error();
  }catch{throw new ApiError(403,'CAPTURE_UPLOAD_AUTHORIZATION_INVALID','L’autorisation de transfert n’est pas valide ou a expiré.');}
 }
}
