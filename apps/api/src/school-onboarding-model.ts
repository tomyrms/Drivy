import {z} from 'zod';
import {fieldRule,validateRules} from './profiles.js';
import {curriculumBody,policyBody} from './catalogue.js';
import {policyCommand,POLICY_TEXT_MINIMUM} from './school-setup.js';
import {proposedCommercialTerms,proposedDataPolicy,proposedProcedure,proposedProfileFields,type ProposalContext} from './text-proposals.js';

export const setupSteps=['IDENTITY','PRIVACY','PROFILE','FORMATIONS','PRICING','REVIEW'] as const;
export const setupSections=['IDENTITY','PRIVACY','PROFILE','CATALOGUE'] as const;
const text=(max:number)=>z.string().max(max);
const nullableText=(max:number)=>text(max).nullable();
const sourceURL=z.url().max(2048).refine(value=>{const url=new URL(value);return ['https:','http:'].includes(url.protocol)&&!url.username&&!url.password;});
const competency=z.object({key:text(80),label:text(200),description:text(4000),sortOrder:z.number().int().min(0).max(100000)}).strict();
const draftFieldRule=fieldRule.extend({explanation:text(1000)});
export const setupFormationSchema=z.object({
  id:z.uuid(),apply:z.boolean(),categoryCode:text(30),label:text(200),templateId:nullableText(100),templateVersion:nullableText(40),
  competencies:z.array(competency).max(200),procedureText:text(4000),cancellationPolicyText:text(4000),sourceUrls:z.array(sourceURL).max(30),
  durationMinutes:z.number().int().min(0).max(480).nullable(),priceCents:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).nullable(),
  termsText:text(20000),validFrom:z.iso.date().nullable(),existingOfferingId:z.uuid().nullable()
}).strict();
export const setupContentSchema=z.object({
  selectedSections:z.array(z.enum(setupSections)).max(4).refine(items=>new Set(items).size===items.length),
  identity:z.object({name:text(150),timeZone:text(100),contactEmail:text(320),contactPhone:nullableText(32)}).strict(),
  privacy:z.object({noticeText:text(20000),retentionText:text(20000),contactEmail:text(320),templateId:nullableText(100),templateVersion:nullableText(40)}).strict(),
  profile:z.object({fields:z.array(draftFieldRule).max(7),effectiveFrom:z.iso.datetime({offset:true}).nullable()}).strict(),
  formations:z.array(setupFormationSchema).max(12).refine(items=>new Set(items.map(item=>item.id)).size===items.length)
}).strict();
export type SetupContent=z.infer<typeof setupContentSchema>;
export type SetupFormation=z.infer<typeof setupFormationSchema>;
export const setupDraftSchema=z.object({id:z.uuid(),schoolId:z.uuid(),version:z.number().int().positive(),status:z.enum(['DRAFT','APPLIED']),currentStep:z.enum(setupSteps),
  content:setupContentSchema,updatedAt:z.iso.datetime().nullable(),updatedByMembershipId:z.uuid(),appliedAt:z.iso.datetime().nullable()}).strict();
export interface SetupIssue {field:string;code:string;message:string}
export const templateVersion='2026-10-13.2';
export const defaultProfileFields:z.infer<typeof fieldRule>[]=structuredClone([...proposedProfileFields]);
const competencies=(twoWheels:boolean)=>[
  {key:'preparation',label:'Préparer la conduite',description:'Préparer le véhicule et son installation avant de partir.',sortOrder:0},
  {key:'observation',label:'Observer et anticiper',description:'Observer l’environnement et anticiper les situations de circulation.',sortOrder:1},
  {key:'position',label:twoWheels?'Trajectoire et équilibre':'Placement et trajectoire',description:'Adapter son placement et sa trajectoire à la situation.',sortOrder:2},
  {key:'speed',label:'Adapter son allure',description:'Choisir une allure adaptée à la visibilité et aux conditions.',sortOrder:3},
  {key:'intersections',label:'Franchir les intersections',description:'Observer, décider et communiquer avant de franchir une intersection.',sortOrder:4},
  {key:'manoeuvres',label:'Manœuvrer',description:'Réaliser les manœuvres travaillées en tenant compte des autres usagers.',sortOrder:5}
];
/** Le guide et les réglages proposent les mêmes textes ; aucune lecture ne vaut adoption. */
export function schoolSetupTemplates(context:ProposalContext) {
  const privacy=proposedDataPolicy(context),procedure=proposedProcedure(),commercial=proposedCommercialTerms(context);
  return {version:templateVersion,privacy:{id:'school-data-information',version:templateVersion,
    noticeText:privacy.noticeText,retentionText:privacy.retentionText},
    commercial:{id:'individual-lesson-commercial',version:templateVersion,cancellationPolicyText:procedure.cancellationPolicyText,termsText:commercial.termsText},
    profileFields:structuredClone(defaultProfileFields),
    // Bases pédagogiques, sans âge, durée légale, habilitation ou attestation réglementaire.
    formations:['A','A1','B','BE'].map(categoryCode=>({id:`pedagogy-${categoryCode.toLowerCase()}`,version:templateVersion,categoryCode,label:`Permis ${categoryCode}`,
      competencies:competencies(categoryCode==='A'||categoryCode==='A1'),procedureText:procedure.procedureText,durationMinutes:45}))};
}
/** Identifiants/version stables pour les validations et bases synthétiques sans école. */
export const setupTemplates=schoolSetupTemplates({schoolName:'[Nom de l’école]',contactEmail:'[contact données]'});

export function emptySetupContent(school:{name:string;timeZone:string;contactEmail:string;contactPhone:string|null;status:string}):SetupContent {
  return {selectedSections:school.status==='DRAFT'?['IDENTITY','PRIVACY','PROFILE']:[],identity:{name:school.name,timeZone:school.timeZone,contactEmail:school.contactEmail,contactPhone:school.contactPhone},
    privacy:{noticeText:'',retentionText:'',contactEmail:school.contactEmail,templateId:null,templateVersion:null},
    profile:{fields:structuredClone(defaultProfileFields),effectiveFrom:null},formations:[]};
}
const unresolved=(value:string)=>/\[(?:[^\]]*(?:compl[eé]ter|nom de l.[eé]cole|contact donn[eé]es)[^\]]*)\]/iu.test(value);
const validationOperation='11111111-1111-4111-8111-111111111111';
/** Sauvegarder accepte les champs vides ; seule l'application exige un contenu complet. */
export function contentIssues(content:SetupContent):SetupIssue[] {
  const issues:SetupIssue[]=[];
  const add=(field:string,message:string,code='SETUP_FIELD_REQUIRED')=>issues.push({field,message,code});
  const nonblank=(value:string,field:string,message:string)=>{if(!value.trim())add(field,message);else if(unresolved(value))add(field,'Remplacez les éléments à compléter avant de confirmer.','SETUP_PLACEHOLDER');};
  if(content.selectedSections.includes('IDENTITY')) {
    nonblank(content.identity.name,'identity.name','Indiquez le nom de l’école.');
    if(!z.email().safeParse(content.identity.contactEmail).success)add('identity.contactEmail','Indiquez un e-mail professionnel valide.');
    try {new Intl.DateTimeFormat('fr',{timeZone:content.identity.timeZone});if(/^[+-]/.test(content.identity.timeZone))throw new Error();}
    catch {add('identity.timeZone','Choisissez un fuseau horaire valide.');}
  }
  if(content.selectedSections.includes('PRIVACY')) {
    const privacy=content.privacy;
    for(const key of ['noticeText','retentionText'] as const)nonblank(privacy[key],`privacy.${key}`,'Complétez le texte avant de l’adopter.');
    const validated=policyCommand.safeParse({operationId:validationOperation,noticeText:privacy.noticeText,retentionText:privacy.retentionText,contactEmail:privacy.contactEmail,reviewAcknowledged:true});
    if(!validated.success)for(const error of validated.error.issues) {
      const field=error.path[0];
      if(field==='contactEmail')add('privacy.contactEmail','Indiquez un contact valide pour les demandes de données.');
      else if(field==='noticeText'||field==='retentionText')add(`privacy.${field}`,`Rédigez un texte d’au moins ${POLICY_TEXT_MINIMUM} caractères utiles avant de l’adopter.`,'POLICY_TEXT_TOO_SHORT');
    }
    if(privacy.templateId!==null&&(privacy.templateId!==setupTemplates.privacy.id||privacy.templateVersion!==templateVersion))add('privacy.templateVersion','Relisez la version actuelle du modèle ou retirez sa référence pour utiliser votre texte.','SETUP_TEMPLATE_CHANGED');
  }
  if(content.selectedSections.includes('PROFILE')) {
    const rules=z.array(fieldRule).safeParse(content.profile.fields);
    if(!rules.success)for(const issue of rules.error.issues)add(`profile.fields${issue.path.length?`.${issue.path.join('.')}`:''}`,
      issue.path.at(-1)==='explanation'?'Expliquez à l’élève pourquoi cette information est demandée.':'Vérifiez cette information et les choix associés.','PROFILE_POLICY_RULE_INVALID');
    else try {validateRules(rules.data);}catch {add('profile.fields','Vérifiez les informations, leur utilité et le moment où elles sont demandées.','PROFILE_POLICY_RULE_INVALID');}
    if(content.profile.effectiveFrom!==null)add('profile.effectiveFrom','Les informations demandées prennent effet dès la confirmation. Retirez la date enregistrée pour continuer.','PROFILE_EFFECTIVE_NOW_REQUIRED');
  }
  if(content.selectedSections.includes('CATALOGUE')) {
    for(const [index,formation] of content.formations.entries()) {
      if(!formation.apply)continue;
      const prefix=`formations.${index}`;
      nonblank(formation.categoryCode,`${prefix}.categoryCode`,'Choisissez un permis.');
      nonblank(formation.label,`${prefix}.label`,'Indiquez le nom de la formation.');
      if(formation.priceCents===null)add(`${prefix}.priceCents`,'Saisissez le prix réel de la leçon.');
      if(formation.durationMinutes===null||formation.durationMinutes<1)add(`${prefix}.durationMinutes`,'Confirmez une durée de leçon entre 1 et 480 minutes.');
      if(formation.validFrom===null)add(`${prefix}.validFrom`,'Choisissez la date d’entrée en vigueur du tarif.');
      nonblank(formation.termsText,`${prefix}.termsText`,'Complétez les conditions de cette prestation.');
      if(formation.existingOfferingId===null) {
        const curriculum=curriculumBody.safeParse({operationId:validationOperation,categoryCode:formation.categoryCode,approved:true,approvalReason:'Configuration relue',competencies:formation.competencies});
        if(!curriculum.success)add(`${prefix}.competencies`,'Complétez les compétences avec des clés distinctes, des noms et des descriptions.');
        const procedure=policyBody.safeParse({operationId:validationOperation,categoryCode:formation.categoryCode,procedureText:formation.procedureText,cancellationPolicyText:formation.cancellationPolicyText,sourceUrls:formation.sourceUrls,approved:true,approvalReason:'Configuration relue'});
        if(!procedure.success)add(`${prefix}.procedureText`,'Complétez le déroulement et les conditions d’annulation.');
        nonblank(formation.procedureText,`${prefix}.procedureText`,'Complétez le déroulement de la formation.');
        nonblank(formation.cancellationPolicyText,`${prefix}.cancellationPolicyText`,'Complétez les conditions d’annulation.');
      } else if(formation.cancellationPolicyText.trim())add(`${prefix}.cancellationPolicyText`,'Les conditions d’annulation de la formation sont conservées. Retirez ce texte du brouillon, ou modifiez la procédure depuis la fiche de formation.','SETUP_INHERITED_CANCELLATION');
      if(formation.templateId!==null&&!setupTemplates.formations.some(template=>template.id===formation.templateId&&template.version===formation.templateVersion&&template.categoryCode===formation.categoryCode))add(`${prefix}.templateVersion`,'Relisez le modèle correspondant à ce permis ou retirez sa référence.','SETUP_TEMPLATE_CHANGED');
    }
  }
  return issues;
}
