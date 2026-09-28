import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat,open} from 'node:fs/promises';
import {z} from 'zod';
import * as c from './profile-contract.js';

export class JournalError extends Error {constructor(readonly code:string,readonly status=503){super(code);}}
export const ownerSchema=z.object({issuer:z.string().min(1).max(2048),subject:z.string().min(1).max(255)}).strict();
export type CommandOwner=z.infer<typeof ownerSchema>;
export const keyringSchema=z.object({activeKeyId:z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),keys:z.record(z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),z.string().regex(/^[a-fA-F0-9]{64}$/))}).strict().refine(value=>!!value.keys[value.activeKeyId]);
export type CommandKeyring=z.infer<typeof keyringSchema>;
export const payloadSchema=z.object({request:c.prepare,reviewPolicy:c.policy.optional(),reviewNotice:c.notice.optional()}).strict();
export type CommandPayload=z.infer<typeof payloadSchema>;
export type CommandBinding={personId:string;schoolId:string;membershipId:string;accessEpoch:number;kind:c.Prepare['kind'];targetId:string;expectedVersion:number};
export type CommandState='PREPARED'|'SUBMITTED'|'UNCERTAIN'|'COMMITTED'|'REJECTED'|'CANCELLED';
export type CommandRecord=CommandPayload & CommandBinding & CommandOwner & {operationId:string;state:CommandState;revision:number;
  keyId:string;leaseId:string|null;leaseUntil:Date|null;reviewHash:string|null;reviewSessionHash:string|null;createdAt:Date;updatedAt:Date;finishedAt:Date|null};
export type CommandRow={operation_id:string;issuer:string;subject:string;person_id:string;school_id:string;membership_id:string;access_epoch:number;
  kind:c.Prepare['kind'];target_id:string;expected_version:number;key_id:string;sealed:Buffer;state:CommandState;revision:number;
  lease_id:string|null;lease_until:Date|null;review_hash:string|null;review_session_hash:string|null;created_at:Date;updated_at:Date;finished_at:Date|null};
export const digest=(value:string)=>createHash('sha256').update(value).digest('hex');
const aad=(row:Pick<CommandRow,'operation_id'|'issuer'|'subject'|'person_id'|'school_id'|'membership_id'|'access_epoch'|'kind'|'target_id'|'expected_version'|'key_id'>)=>Buffer.from(JSON.stringify([
  'drivy-web-command-v1',row.operation_id,row.issuer,row.subject,row.person_id,row.school_id,row.membership_id,row.access_epoch,row.kind,row.target_id,row.expected_version,row.key_id]));
export function encryptPayload(row:Parameters<typeof aad>[0],payload:CommandPayload,ring:CommandKeyring):Buffer {
  const key=ring.keys[row.key_id];if(!key)throw new JournalError('COMMAND_KEY_UNAVAILABLE');
  const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',Buffer.from(key,'hex'),nonce);cipher.setAAD(aad(row));
  const encrypted=Buffer.concat([cipher.update(JSON.stringify(payloadSchema.parse(payload)),'utf8'),cipher.final()]);return Buffer.concat([nonce,cipher.getAuthTag(),encrypted]);
}
export function decodeRow(row:CommandRow,ring:CommandKeyring):CommandRecord {
  const key=ring.keys[row.key_id];if(!key)throw new JournalError('COMMAND_KEY_UNAVAILABLE');
  try{
    if(!Buffer.isBuffer(row.sealed)||row.sealed.length<=28)throw new Error();
    const cipher=createDecipheriv('aes-256-gcm',Buffer.from(key,'hex'),row.sealed.subarray(0,12));cipher.setAAD(aad(row));cipher.setAuthTag(row.sealed.subarray(12,28));
    const payload=payloadSchema.parse(JSON.parse(Buffer.concat([cipher.update(row.sealed.subarray(28)),cipher.final()]).toString('utf8')));
    const targetId=payload.request.kind==='PROFILE'?payload.request.learnerId:payload.request.kind==='POLICY_PUBLISH'?payload.request.policyId:payload.request.schoolId;
    if(payload.request.schoolId!==row.school_id||payload.request.kind!==row.kind||payload.request.expectedVersion!==row.expected_version||targetId!==row.target_id)throw new Error();
    return {...payload,issuer:row.issuer,subject:row.subject,operationId:row.operation_id,personId:row.person_id,schoolId:row.school_id,
      membershipId:row.membership_id,accessEpoch:row.access_epoch,kind:row.kind,targetId:row.target_id,expectedVersion:row.expected_version,
      keyId:row.key_id,state:row.state,revision:row.revision,leaseId:row.lease_id,leaseUntil:row.lease_until,reviewHash:row.review_hash,
      reviewSessionHash:row.review_session_hash,createdAt:row.created_at,updatedAt:row.updated_at,finishedAt:row.finished_at};
  }catch(error){if(error instanceof JournalError)throw error;throw new JournalError('COMMAND_STORAGE_CORRUPTED');}
}
export async function loadCommandKeyring(path:string):Promise<CommandKeyring> {
  const before=await lstat(path);if(!before.isFile()||before.isSymbolicLink())throw new JournalError('COMMAND_KEY_FILE_UNSAFE');
  // Linux: owner may write; a private service group may read (0640). Never group-write/world access.
  if(process.platform!=='win32' && (before.mode&0o027)!==0)throw new JournalError('COMMAND_KEY_FILE_UNSAFE');
  const handle=await open(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));
  try{const actual=await handle.stat();if(!actual.isFile()||actual.ino!==before.ino||actual.dev!==before.dev||actual.size>65536||(process.platform!=='win32'&&(actual.mode&0o027)!==0))throw new JournalError('COMMAND_KEY_FILE_UNSAFE');
    return keyringSchema.parse(JSON.parse(await handle.readFile('utf8')));
  }finally{await handle.close();}
}
