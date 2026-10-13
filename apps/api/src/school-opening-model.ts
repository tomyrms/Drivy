import { z } from 'zod';
import { createHash } from 'node:crypto';

export const openingToken = z.string().regex(/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/);
export const openingIdentity = z.object({ issuer:z.url().max(2048), subject:z.string().trim().min(1).max(512) }).strict();
export type OpeningOperator = z.infer<typeof openingIdentity>;
export type SchoolOpeningConfig = { operators: OpeningOperator[]; validityDays: number };
export function readSchoolOpeningConfig(env:NodeJS.ProcessEnv=process.env):SchoolOpeningConfig {
  const operators=z.array(openingIdentity).max(100).parse(JSON.parse(env.SCHOOL_OPENING_OPERATORS_JSON ?? '[]'));
  const validityDays=z.coerce.number().int().min(1).max(30).parse(env.SCHOOL_OPENING_VALIDITY_DAYS ?? '7');
  return {operators,validityDays};
}
export const openingHash=(token:string)=>createHash('sha256').update(token).digest('hex');
export const createOpeningLinkBody=z.object({operationId:z.uuid(),token:openingToken}).strict();
export const openingPreviewBody=z.object({token:openingToken}).strict();
export const schoolOpeningBody=z.object({operationId:z.uuid(),token:openingToken,
  schoolName:z.string().trim().min(1).max(150),displayName:z.string().trim().min(1).max(200),
  contactEmail:z.email().max(254),contactPhone:z.string().trim().min(1).max(50).nullable(),
  timeZone:z.string().max(100).refine(value=>{try{new Intl.DateTimeFormat('fr',{timeZone:value});return true;}catch{return false;}}),
  instructs:z.boolean()}).strict();
export type SchoolOpeningCommand=z.infer<typeof schoolOpeningBody>;
export interface OpeningLinkRow {
  id:string;token_hash:string;reserved_school_id:string;reserved_membership_id:string;
  created_by_issuer:string;created_by_subject:string;create_operation_id:string;create_hash:string;
  created_at:Date;expires_at:Date;status:'AVAILABLE'|'USED'|'REVOKED';revoked_at:Date|null;
  revoke_operation_id:string|null;used_at:Date|null;used_by_issuer:string|null;used_by_subject:string|null;
  used_by_person_id:string|null;consume_operation_id:string|null;consume_hash:string|null;
}
export function openingLinkProjection(row:OpeningLinkRow) {
  return {id:row.id,status:row.status==='AVAILABLE' && row.expires_at.getTime()<=Date.now()?'EXPIRED':row.status,
    createdAt:row.created_at.toISOString(),expiresAt:row.expires_at.toISOString(),usedAt:row.used_at?.toISOString() ?? null,
    revokedAt:row.revoked_at?.toISOString() ?? null};
}
