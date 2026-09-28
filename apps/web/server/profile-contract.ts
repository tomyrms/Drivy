import { z } from 'zod';
export const id=z.uuid();
export const version=z.number().int().positive().max(2_147_483_647);
export const field=z.enum(['firstName','lastName','birthDate','postalAddress','contactEmail','contactPhone','profilePhotoDocumentId']);
export const fieldRule=z.object({field,requirement:z.enum(['REQUIRED','CONDITIONAL','OPTIONAL']),stage:z.enum(['JOIN','BEFORE_LESSON','BEFORE_COURSE','OPTIONAL']),
  purposeCode:z.enum(['IDENTIFICATION','LESSON_CONTACT','COURSE_ELIGIBILITY','CERTIFICATE','POSTAL_CONTACT','PERSONALISATION']),explanation:z.string().trim().min(1).max(1000)}).strict().superRefine((value,context)=>{
  if (['firstName','lastName'].includes(value.field) && (value.requirement!=='REQUIRED'||value.stage!=='JOIN'||value.purposeCode!=='IDENTIFICATION')) context.addIssue({code:'custom',message:'Noms : identification à l’entrée.'});
  if (value.field==='profilePhotoDocumentId' && (value.requirement!=='OPTIONAL'||value.stage!=='OPTIONAL'||value.purposeCode!=='PERSONALISATION')) context.addIssue({code:'custom',message:'La photo reste facultative.'});
});
export const policy=z.object({id,schoolId:id,version,status:z.enum(['DRAFT','PUBLISHED','RETIRED']),effectiveFrom:z.iso.datetime({offset:true}),fields:z.array(fieldRule).min(2).max(7),noticeVersionId:id,approvedByMembershipId:id.nullable()});
export const policyPayload=z.object({effectiveFrom:z.iso.datetime({offset:true}),fields:z.array(fieldRule).min(2).max(7),noticeVersionId:id,impactAcknowledged:z.literal(true)}).strict().refine(value=>new Set(value.fields.map(rule=>rule.field)).size===value.fields.length && ['firstName','lastName'].every(name=>value.fields.some(rule=>rule.field===name)));
export const address=z.object({line1:z.string().trim().min(1).max(200),line2:z.string().max(200).nullable(),postalCode:z.string().trim().min(1).max(20),locality:z.string().trim().min(1).max(150),countryCode:z.string().regex(/^[A-Z]{2}$/)}).strict();
export const profileValues={firstName:z.string().trim().min(1).max(150),lastName:z.string().trim().min(1).max(150),birthDate:z.iso.date().nullable(),postalAddress:address.nullable(),contactEmail:z.email().max(254).nullable(),contactPhone:z.string().max(32).nullable(),profilePhotoDocumentId:id.nullable()};
export const profilePayload=z.object({policyVersionId:id,...profileValues}).partial({firstName:true,lastName:true,birthDate:true,postalAddress:true,contactEmail:true,contactPhone:true,profilePhotoDocumentId:true}).strict().refine(value=>Object.keys(value).length>1);
export const profile=z.object({id,schoolId:id,learnerId:id,version,firstName:profileValues.firstName.nullable(),lastName:profileValues.lastName.nullable(),birthDate:profileValues.birthDate.optional(),postalAddress:profileValues.postalAddress.optional(),contactEmail:profileValues.contactEmail.optional(),contactPhone:profileValues.contactPhone.optional(),profilePhotoDocumentId:profileValues.profilePhotoDocumentId.optional(),updatedAt:z.iso.datetime({offset:true}),enteredByMembershipId:id,entrySource:z.enum(['SELF','STAFF_ASSISTED']),policyVersionId:id});
export const member=z.object({schoolId:id,schoolName:z.string(),membershipId:id,accessEpoch:version,roles:z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER'])),grants:z.array(z.string())});
export const me=z.object({data:z.object({personId:id,memberships:z.array(member)})});
export const learner=z.object({id,schoolId:id,personId:id,version,displayName:z.string(),contactEmail:z.string().nullable(),contactPhone:z.string().nullable(),archivedAt:z.string().nullable(),profileReadiness:z.enum(['MINIMAL','ACTION_REQUIRED','READY'])});
export const blocker=z.object({code:z.string(),message:z.string(),field:z.string().nullable(),purpose:z.string().nullable(),resourceId:id.nullable(),destinationKey:z.string().nullable()});
export const readiness=z.object({learnerId:id,action:z.enum(['ENTER','PLAN_LESSON','ENROLL_COURSE']),resourceId:id.nullable(),ready:z.boolean(),blockers:z.array(blocker),policyVersionId:id,computedAt:z.iso.datetime({offset:true})});
export const scope=member.extend({personId:id});
export const school=z.object({id,schoolId:id,version,name:z.string(),status:z.enum(['DRAFT','ACTIVE','ARCHIVED'])});
export const notice=z.object({noticeVersionId:id,status:z.enum(['DRAFT','APPROVED']),noticeText:z.string(),retentionText:z.string(),version});
export const page=<T extends z.ZodType>(item:T)=>z.object({data:z.object({items:z.array(item),nextCursor:z.string().nullable()})});
export const envelope=<T extends z.ZodType>(item:T)=>z.object({data:item});
export const prepare=z.discriminatedUnion('kind',[
  z.object({kind:z.literal('PROFILE'),schoolId:id,learnerId:id,expectedVersion:version,payload:profilePayload}).strict(),
  z.object({kind:z.literal('POLICY_CREATE'),schoolId:id,expectedVersion:version,payload:policyPayload}).strict(),
  z.object({kind:z.literal('POLICY_PUBLISH'),schoolId:id,policyId:id,expectedVersion:version,payload:z.object({}).strict()}).strict()
]);
export const intentView=z.object({operationId:id,confirmation:z.string().min(32),request:prepare,reviewPolicy:policy.optional(),reviewNotice:notice.optional(),state:z.enum(['PREPARED','SUBMITTED','UNCERTAIN','COMMITTED','REJECTED'])});
export const commandState=z.object({command:intentView.nullable()});
export const scopeSchool=z.object({scope,school});
export const profileView=z.object({scope,learner,profile,policy,readiness,editableFields:z.array(field)});
export type Field=z.infer<typeof field>;
export type FieldRule=z.infer<typeof fieldRule>;
export type Profile=z.infer<typeof profile>;
export type Policy=z.infer<typeof policy>;
export type Prepare=z.infer<typeof prepare>;
export type IntentView=z.infer<typeof intentView>;
