import { z } from 'zod';
import { RequestFailure } from './protocol.js';

export interface OpeningLink {token:string|null;error:boolean}
/** The bearer secret is removed before any fetch or OIDC navigation. Never persist it in browser storage. */
export function readOpeningLink(location:Pick<Location,'pathname'|'search'|'hash'>=window.location,replace:(url:string)=>void=url=>window.history.replaceState(null,'',url)):OpeningLink {
  const hash=location.hash;if(!hash)return {token:null,error:false};
  replace(location.pathname+location.search);
  const values=new URLSearchParams(hash.slice(1)),token=values.get('token');
  if(location.pathname!=='/app/ouvrir' || [...values.keys()].length!==1 || !token || !/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(token))return {token:null,error:true};
  return {token,error:false};
}
export const openingReceipt=z.object({schoolId:z.uuid(),schoolName:z.string(),status:z.enum(['DRAFT','ACTIVE','ARCHIVED']),membershipId:z.uuid(),
  roles:z.array(z.string()),grants:z.array(z.string()),accessEpoch:z.number().int().positive(),operationId:z.uuid(),committedAt:z.string()});
export const openingFields=z.object({schoolName:z.string(),displayName:z.string(),contactEmail:z.string(),contactPhone:z.string().nullable(),timeZone:z.string(),instructs:z.boolean()});
export type OpeningFields=z.infer<typeof openingFields>;
export type OpeningFieldErrors=Partial<Record<keyof OpeningFields,string>>;
const openingInput=openingFields.extend({
  schoolName:z.string().trim().min(1).max(150),displayName:z.string().trim().min(1).max(200),
  contactEmail:z.email().max(254),contactPhone:z.string().trim().min(1).max(32).nullable(),
  timeZone:z.string().min(1).max(100).refine(value=>{try{new Intl.DateTimeFormat('fr',{timeZone:value});return !/^[+-]/.test(value);}catch{return false;}}),
});
/** Field feedback before sending; the API independently validates every value. */
export function openingFieldErrors(value:OpeningFields):OpeningFieldErrors {
  const parsed=openingInput.safeParse(value);
  if(parsed.success)return {};
  const messages:Partial<Record<keyof OpeningFields,string>>={
    displayName:'Indiquez votre nom (200 caractères maximum).',schoolName:'Indiquez le nom de l’école (150 caractères maximum).',
    contactEmail:'Indiquez une adresse e-mail valide.',contactPhone:'Indiquez un numéro ou laissez ce champ vide (32 caractères maximum).',
    timeZone:'Indiquez un fuseau horaire reconnu, par exemple Europe/Zurich.',
  };
  return Object.fromEntries(parsed.error.issues.map(issue=>{const field=issue.path[0] as keyof OpeningFields;return [field,messages[field]];}));
}
export type OpeningReceipt=z.infer<typeof openingReceipt>;
export const openingState=z.object({pending:z.boolean(),uncertain:z.boolean(),draft:openingFields.optional(),result:openingReceipt.optional()});
export const openingPreview=z.object({data:z.discriminatedUnion('status',[
  z.object({status:z.literal('AVAILABLE'),expiresAt:z.string()}),z.object({status:z.literal('USED'),school:openingReceipt})])});
export const openingLinkSchema=z.object({id:z.uuid(),status:z.enum(['AVAILABLE','USED','EXPIRED','REVOKED']),createdAt:z.string(),expiresAt:z.string(),usedAt:z.string().nullable(),revokedAt:z.string().nullable()});
export const openingLinks=z.object({data:z.object({items:z.array(openingLinkSchema)}),pendingOperationId:z.uuid().optional()});
export const createdOpeningLink=z.object({data:openingLinkSchema,link:z.string().url()});
export function openingFailure(error:unknown):string {
  const code=error instanceof RequestFailure?error.code:'';
  const messages:Record<string,string>={
    OPERATOR_REQUIRED:'Cet espace est réservé à l’opérateur Drivy.',
    OPENING_LINK_MISSING:'Rouvrez le lien remis par Drivy pour préparer votre école.',
    OPENING_LINK_INVALID:'Ce lien est incomplet ou invalide. Demandez un nouveau lien à Drivy.',
    OPENING_LINK_EXPIRED:'Ce lien a expiré. Demandez un nouveau lien à Drivy.',
    OPENING_LINK_REVOKED:'Ce lien a été révoqué. Demandez un nouveau lien à Drivy.',
    OPENING_LINK_USED:'Ce lien a déjà été utilisé. Connectez-vous avec le compte qui a créé l’école pour la retrouver.',
    OPENING_IDENTITY_CHANGED:'Cette demande appartient au compte utilisé avant la reconnexion. Reconnectez-vous avec ce compte pour la vérifier.',
    OPENING_IN_PROGRESS:'Une demande est en cours. Vérifiez son résultat avant de modifier les informations.',
    SESSION_EXPIRED:'Votre session a expiré. Reconnectez-vous, puis rouvrez le lien si nécessaire.',
    IDEMPOTENCY_MISMATCH:'Cette demande ne correspond plus aux informations envoyées. Retrouvez votre école depuis votre compte.',
    INVALID_REQUEST:'Certaines informations ne sont pas valides. Vérifiez votre nom, les coordonnées de l’école et le fuseau horaire.',
  };
  return messages[code] ?? 'La réponse n’a pas pu être confirmée. Réessayez avec la même demande.';
}
export function schoolOpeningDestination(receipt:OpeningReceipt):string {
  return `/app/gestion/${receipt.schoolId}/${receipt.status==='DRAFT'?'apercu':'agenda'}`;
}
