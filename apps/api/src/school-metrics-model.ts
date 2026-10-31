import {z} from 'zod';
import {ApiError} from './errors.js';

/**
 * Pilotage de l'école (#373, T02 #375) : règles pures, sans base ni réseau.
 * Source de vérité des définitions : docs/implementation/pilotage-373-indicateurs.md. Toute modification d'une formule, d'un statut inclus
 * ou d'une règle de rattachement change `definitionsVersion`.
 */
export const definitionsVersion='2026-10-31.1';
export const maxPeriodDays=366,maxBuckets=400,maxDetailPage=100,maxExportLines=10_000;

// ---------------------------------------------------------------- dates civiles de l'école
const civilPattern=/^(\d{4})-(\d{2})-(\d{2})$/;
export function isCivilDate(value:string):boolean{
 const match=civilPattern.exec(value);if(!match)return false;
 const year=Number(match[1]),month=Number(match[2]),day=Number(match[3]),date=new Date(Date.UTC(year,month-1,day));
 return year>=2000&&year<=2100&&date.getUTCFullYear()===year&&date.getUTCMonth()===month-1&&date.getUTCDate()===day;
}
const utc=(civil:string)=>{const m=civilPattern.exec(civil)!;return Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3]));};
const iso=(ms:number)=>new Date(ms).toISOString().slice(0,10);
export const addDays=(civil:string,days:number)=>{const m=civilPattern.exec(civil)!;return iso(Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3])+days));};
export const daysBetween=(from:string,to:string)=>Math.round((utc(to)-utc(from))/86_400_000);
export const firstOfMonth=(civil:string)=>`${civil.slice(0,8)}01`;
/** Premier jour du mois situé `months` mois après le mois de la date. */
export const addMonths=(civil:string,months:number)=>{const m=civilPattern.exec(civil)!;return iso(Date.UTC(Number(m[1]),Number(m[2])-1+months,1));};
/** Lundi de la semaine de la date (même convention que l'agenda). */
export const weekStart=(civil:string)=>addDays(civil,-((new Date(utc(civil)).getUTCDay()+6)%7));

export const invalidPeriod=()=>new ApiError(422,'INVALID_PERIOD','Choisissez une période valide : dates réelles, début avant la fin.');
/** Dates civiles de l'école, début inclus, fin exclue, 366 jours au plus. */
export function validatePeriod(from:string,toExclusive:string):number{
 if(!isCivilDate(from)||!isCivilDate(toExclusive))throw invalidPeriod();
 const days=daysBetween(from,toExclusive);
 if(days<1)throw invalidPeriod();
 if(days>maxPeriodDays)throw new ApiError(422,'PERIOD_TOO_LARGE','La période dépasse 366 jours.');
 return days;
}

// ---------------------------------------------------------------- comparaisons
export type ComparisonMode='FULL_MONTH'|'MONTH_TO_DATE'|'EQUIVALENT_PERIOD';
export interface ComparisonPlan {mode:ComparisonMode;base:{from:string;toExclusive:string;days:number;clipped:boolean}}
/**
 * Base de comparaison déduite des seules dates de la période et du jour courant de l'école.
 * Mois complet contre mois complet ; mois à date contre la même plage du mois précédent (tronquée s'il est plus court) ;
 * période équivalente = même nombre de jours civils juste avant. Toute autre demande de « mois précédent » est refusée.
 */
export function planComparison(compare:'previous-month'|'equivalent-period',from:string,toExclusive:string,today:string):ComparisonPlan{
 const days=daysBetween(from,toExclusive);
 if(compare==='equivalent-period')return {mode:'EQUIVALENT_PERIOD',base:{from:addDays(from,-days),toExclusive:from,days,clipped:false}};
 if(from!==firstOfMonth(from))throw invalidPeriod();
 const previous=addMonths(from,-1),next=addMonths(from,1);
 if(toExclusive===next)return {mode:'FULL_MONTH',base:{from:previous,toExclusive:from,days:daysBetween(previous,from),clipped:false}};
 if(toExclusive===addDays(today,1)&&today>=from&&today<next){
  const limit=addDays(previous,days),end=limit<=from?limit:from;
  return {mode:'MONTH_TO_DATE',base:{from:previous,toExclusive:end,days:daysBetween(previous,end),clipped:end!==limit}};
 }
 throw invalidPeriod();
}
/** Écart en dixièmes de pour cent, entiers seulement, arrondi demi à l'écart de zéro. `base` doit être strictement positif. */
export function percentTenths(delta:number,base:number):number{
 const numerator=BigInt(delta)*1000n,denominator=BigInt(base),magnitude=numerator<0n?-numerator:numerator;
 const rounded=(magnitude*2n+denominator)/(2n*denominator);
 return Number(numerator<0n?-rounded:rounded);
}
export type PercentReason='BASE_ZERO'|'BASE_BEFORE_DATA_START'|'PARTIAL_COVERAGE';
export interface Comparison {current:number|null;base:number|null;delta:number|null;percentTenths:number|null;percentReason:PercentReason|null}
export function compareValues(current:{value:number|null;complete:boolean},base:{value:number|null;complete:boolean;beforeData:boolean}):Comparison{
 const empty={current:current.value,base:base.value,delta:null,percentTenths:null};
 if(base.beforeData)return {...empty,percentReason:'BASE_BEFORE_DATA_START'};
 if(current.value===null||base.value===null||!current.complete||!base.complete)return {...empty,percentReason:'PARTIAL_COVERAGE'};
 const delta=current.value-base.value;
 if(base.value===0)return {current:current.value,base:0,delta,percentTenths:null,percentReason:'BASE_ZERO'};
 return {current:current.value,base:base.value,delta,percentTenths:percentTenths(delta,base.value),percentReason:null};
}

// ---------------------------------------------------------------- intervalles des séries
export type Granularity='day'|'week'|'month';
export interface Bucket {key:string;from:string;toExclusive:string;partial:boolean}
/** Intervalles civils couvrant la période. `key` est le début naturel (jour, lundi, premier du mois) ; from et toExclusive sont rognés à la période. */
export function buckets(from:string,toExclusive:string,granularity:Granularity):Bucket[]{
 const result:Bucket[]=[];
 const next=(start:string)=>granularity==='day'?addDays(start,1):granularity==='week'?addDays(start,7):addMonths(start,1);
 let start=granularity==='day'?from:granularity==='week'?weekStart(from):firstOfMonth(from);
 while(start<toExclusive){
  const end=next(start);
  result.push({key:start,from:start<from?from:start,toExclusive:end>toExclusive?toExclusive:end,partial:start<from||end>toExclusive});
  if(result.length>maxBuckets)throw new ApiError(422,'PERIOD_TOO_LARGE','La période dépasse 400 intervalles.');
  start=end;
 }
 return result;
}

// ---------------------------------------------------------------- mesures
export type Unit='count'|'seconds'|'cents'|'permille';
export type CoverageStatus='COMPLETE'|'PARTIAL'|'UNAVAILABLE'|'NOT_APPLICABLE';
export interface Reason {code:string;count?:number}
export interface Coverage {status:CoverageStatus;reasons:Reason[]}
export interface Measure {value:number|null;unit:Unit;coverage:Coverage;lineCount?:number;parts?:Record<string,number|null>}
export const complete=(reasons:Reason[]=[]):Coverage=>({status:'COMPLETE',reasons});
export const partial=(reasons:Reason[]):Coverage=>({status:'PARTIAL',reasons});
export const unavailable=(code:string):Coverage=>({status:'UNAVAILABLE',reasons:[{code}]});
export const notApplicable=():Coverage=>({status:'NOT_APPLICABLE',reasons:[]});
export function measure(value:number|null,unit:Unit,coverage:Coverage,extra:{lineCount?:number;parts?:Record<string,number|null>}={}):Measure{
 return {value,unit,coverage,...(extra.lineCount===undefined?{}:{lineCount:extra.lineCount}),...(extra.parts?{parts:extra.parts}:{})};
}
/** Un entier JSON sûr : un cumul plus grand est refusé plutôt qu'arrondi. */
export function safeInteger(value:string|number|bigint|null|undefined):number{
 const big=BigInt(value??0);
 if(big>BigInt(Number.MAX_SAFE_INTEGER)||big<BigInt(Number.MIN_SAFE_INTEGER))throw new ApiError(409,'AMOUNT_OUT_OF_RANGE','Un cumul dépasse la limite acceptée.');
 return Number(big);
}

export const activityStates=['COMPLETED','UPCOMING','CANCELLED','NO_SHOW','TO_VERIFY','IN_PROGRESS','TO_FINALIZE'] as const;
export type LessonState=typeof activityStates[number];
/** Identifiant du dictionnaire -> état de leçon qu'il compte. */
export const lessonStateOf:Record<string,LessonState>={L01:'COMPLETED',L02:'UPCOMING',L03:'CANCELLED',L04:'NO_SHOW',L05:'TO_VERIFY',L06:'IN_PROGRESS',L07:'TO_FINALIZE'};
export const programmedStates:readonly LessonState[]=['COMPLETED','UPCOMING','TO_VERIFY','IN_PROGRESS','TO_FINALIZE'];
export const pendingStates:readonly LessonState[]=['TO_VERIFY','IN_PROGRESS','TO_FINALIZE'];

export type Domain='activity'|'finance';
export interface Definition {id:string;domain:Domain;unit:Unit;label:string;formula:string;snapshot:boolean;additive:boolean;series:boolean;details:boolean}
const def=(id:string,domain:Domain,unit:Unit,label:string,formula:string,flags:{snapshot?:boolean;additive?:boolean;series?:boolean;details?:boolean}={}):Definition=>
 ({id,domain,unit,label,formula,snapshot:flags.snapshot??false,additive:flags.additive??true,series:flags.series??false,details:flags.details??false});
/** Dictionnaire servi par GET /metrics/definitions : libellés courts, formules en clair, sans donnée d'école. */
export const definitions:readonly Definition[]=[
 def('L01','activity','count','Leçons réalisées','Leçons au statut réalisé, rattachées à leur début réel.',{series:true,details:true}),
 def('L02','activity','count','Leçons à venir','Leçons planifiées dont le début prévu est futur et qui n\'ont pas démarré.',{series:true,details:true}),
 def('L03','activity','count','Leçons annulées','Leçons annulées, rattachées à leur début prévu.',{series:true,details:true}),
 def('L04','activity','count','Absences','Absences constatées, rattachées à leur début prévu.',{series:true,details:true}),
 def('L05','activity','count','À vérifier','Leçons planifiées dont l\'heure est passée, sans départ ni constat.',{series:true,details:true}),
 def('L06','activity','count','En cours','Leçons démarrées dont la fin prévue n\'est pas atteinte.',{series:true,details:true}),
 def('L07','activity','count','À finaliser','Leçons démarrées dont la fin prévue est passée, sans constat de fin.',{series:true,details:true}),
 def('L08','activity','count','Total des leçons','Somme des états ci-dessus ; contrôle de cohérence.',{series:true,details:true}),
 def('H01','activity','seconds','Heures programmées','Durée prévue des leçons planifiées ou réalisées.',{series:true,details:true}),
 def('H02','activity','seconds','Heures réalisées (durées connues)','Somme des durées réelles connues ; une durée manquante n\'est ni zéro ni la durée prévue.',{series:true,details:true}),
 def('H03','activity','seconds','Heures à venir','Durée prévue des leçons à venir.',{series:true,details:true}),
 def('P01','activity','count','Élèves ayant eu une activité','Élèves distincts ayant une leçon réalisée ou une présence à une séance de cours.',{series:true}),
 def('C01','activity','count','Séances de cours','Séances des cours publiés (hors brouillons et cours annulés).',{series:true,details:true}),
 def('C02','activity','count','Cours concernés','Cours distincts ayant une séance dans la période.'),
 def('C03','activity','count','Séances avec appel renseigné','Séances ayant au moins une présence saisie.',{series:true,details:true}),
 def('C04','activity','count','Appels à renseigner','Séances passées dont au moins une inscription attendue n\'a pas de présence saisie.',{snapshot:true,additive:false,details:true}),
 def('C05','activity','count','Présences','Présences saisies aux séances de la période ; absents et excusés en parties.'),
 def('C06','activity','count','Inscriptions actives','Inscriptions actives des cours publiés, une fois par cours.',{snapshot:true,additive:false}),
 def('C07','activity','count','Places retenues','Propositions de place actives non échues.',{snapshot:true,additive:false}),
 def('C08','activity','count','Places','Capacité, places occupées et libres des cours publiés.',{snapshot:true,additive:false}),
 def('C09','activity','permille','Remplissage des cours à venir','Places occupées sur capacité des cours publiés dont la première séance est future et dans la période.',{snapshot:true,additive:false}),
 def('C10','activity','count','Mouvements d\'inscription','Inscriptions créées et annulées dans la période.'),
 def('C11','activity','count','Cours annulés','Cours annulés dans la période.'),
 def('A01','activity','count','Leçons à finaliser','Leçons démarrées sans constat de fin, sans borne de période.',{snapshot:true,additive:false}),
 def('A02','activity','count','Appels à renseigner','Séances passées sans appel complet, sans borne de période.',{snapshot:true,additive:false}),
 def('A03','activity','count','Leçons à vérifier','Leçons dont l\'heure est passée, jamais démarrées, sans borne de période.',{snapshot:true,additive:false}),
 def('F01','finance','cents','Valeur des leçons réalisées','Prix convenus à la réservation des leçons réalisées ; pas une preuve d\'encaissement.',{series:true,details:true}),
 def('F02','finance','cents','Valeur des leçons à venir','Prix convenus des réservations confirmées futures.',{series:true,details:true}),
 def('F03','finance','cents','Total attendu selon le planning','Réalisé plus à venir ; ni prévision garantie ni encaissement.',{series:true,details:true}),
 def('F04','finance','cents','Valeur en attente de constat','Leçons à vérifier, en cours ou à finaliser ; hors du total attendu.',{series:true,details:true}),
 def('F05','finance','cents','Règlements de cours enregistrés','Saisies de règlements de cours sur place non annulées, par date de saisie ; pas un rapprochement bancaire.',{series:true,details:true}),
 def('F06','finance','cents','Saisies annulées et corrections','Saisies annulées et corrections postérieures ; annuler une saisie n\'est pas un remboursement.',{details:true}),
 def('F07','finance','cents','Valeur des cours collectifs','Indisponible : un cours n\'a ni prix ni lien produit.'),
];
export const definitionIds=new Set(definitions.map(item=>item.id));

// ---------------------------------------------------------------- paramètres validés
const civilDate=z.string().refine(isCivilDate,'Date civile AAAA-MM-JJ attendue.');
const text=(max:number)=>z.string().min(1).max(max).regex(/^[^\u0000-\u001f\u007f]+$/u);
export const filterFields={instructorMembershipId:z.uuid().optional(),categoryCode:text(30).optional(),productKey:text(100).optional(),scope:z.enum(['school','self']).optional()};
export const metricsQuery=z.object({domain:z.enum(['activity','finance']),from:civilDate,toExclusive:civilDate,compare:z.enum(['none','previous-month','equivalent-period']).default('none'),
 breakdown:z.enum(['instructor','category','product']).optional(),...filterFields}).strict();
export const seriesQuery=z.object({from:civilDate,toExclusive:civilDate,granularity:z.enum(['day','week','month']),
 measures:z.string().regex(/^[A-Z][0-9]{2}(,[A-Z][0-9]{2}){0,4}$/),...filterFields}).strict();
const detailFields={measure:z.string().regex(/^[A-Z][0-9]{2}$/),from:civilDate,toExclusive:civilDate,part:z.enum(['a','b']).optional(),...filterFields,
 expectedLineCount:z.coerce.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional(),expectedAmountCents:z.coerce.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional()};
export const detailsQuery=z.object({...detailFields,limit:z.coerce.number().int().min(1).max(maxDetailPage).default(50),cursor:z.string().max(6000).optional(),
 bucketFrom:civilDate.optional(),bucketToExclusive:civilDate.optional()}).strict();
export const exportBody=z.object({...detailFields,expectedLineCount:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional(),
 expectedAmountCents:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional(),bucketFrom:civilDate.optional(),bucketToExclusive:civilDate.optional()}).strict();

// ---------------------------------------------------------------- réponses (forme du contrat)
const coverageSchema=z.object({status:z.enum(['COMPLETE','PARTIAL','UNAVAILABLE','NOT_APPLICABLE']),
 reasons:z.array(z.object({code:z.string().min(1).max(60),count:z.number().int().nonnegative().optional()}).strict()).max(10)}).strict();
export const measureSchema=z.object({value:z.number().int().nullable(),unit:z.enum(['count','seconds','cents','permille']),coverage:coverageSchema,
 lineCount:z.number().int().nonnegative().optional(),parts:z.record(z.string().min(1).max(40),z.number().int().nullable()).optional()}).strict();
const measures=z.record(z.string().regex(/^[A-Z][0-9]{2}$/),measureSchema);
const comparisonValue=z.object({current:z.number().int().nullable(),base:z.number().int().nullable(),delta:z.number().int().nullable(),
 percentTenths:z.number().int().nullable(),percentReason:z.enum(['BASE_ZERO','BASE_BEFORE_DATA_START','PARTIAL_COVERAGE']).nullable()}).strict();
const periodSchema=z.object({from:civilDate,toExclusive:civilDate,days:z.number().int().positive(),fromInstant:z.iso.datetime({offset:true}),toInstant:z.iso.datetime({offset:true})}).strict();
const header={definitionsVersion:z.literal(definitionsVersion),schoolId:z.uuid(),timeZone:z.string().min(1).max(100),currency:z.literal('CHF'),
 computedAt:z.iso.datetime({offset:true}),dataSince:civilDate.nullable()};
const scopeSchema=z.object({kind:z.enum(['school','self']),filters:z.object({instructorMembershipId:z.uuid().nullable(),categoryCode:z.string().nullable(),productKey:z.string().nullable()}).strict()}).strict();
export const metricsResponse=z.object({...header,domain:z.enum(['activity','finance']),period:periodSchema,scope:scopeSchema,
 coverageNotes:z.object({lessons:z.literal('INDIVIDUAL_UNIT_PRICE_ONLY'),payments:z.literal('COURSE_ON_SITE_ENTRIES_ONLY'),paymentDate:z.literal('ENTRY_DATE')}).strict().optional(),
 measures,
 comparison:z.object({mode:z.enum(['FULL_MONTH','MONTH_TO_DATE','EQUIVALENT_PERIOD']),
  base:z.object({from:civilDate,toExclusive:civilDate,days:z.number().int().positive(),clipped:z.boolean()}).strict(),
  measures:z.record(z.string().regex(/^[A-Z][0-9]{2}$/),comparisonValue)}).strict().optional(),
 breakdown:z.object({by:z.enum(['instructor','category','product']),
  groups:z.array(z.object({key:z.string().min(1).max(100),label:z.string().nullable(),measures}).strict())}).strict().optional()}).strict();
export const seriesResponse=z.object({...header,domain:z.enum(['activity','finance']),period:periodSchema,scope:scopeSchema,granularity:z.enum(['day','week','month']),
 buckets:z.array(z.object({from:civilDate,toExclusive:civilDate,partial:z.boolean(),
  measures:z.record(z.string().regex(/^[A-Z][0-9]{2}$/),z.object({value:z.number().int().nullable(),coverage:coverageSchema.optional()}).strict())}).strict()).max(maxBuckets)}).strict();
const lineSchema=z.object({kind:z.enum(['LESSON','COURSE_OCCURRENCE','COURSE_PAYMENT']),id:z.uuid(),eventAt:z.iso.datetime({offset:true}),status:z.string().min(1).max(40),
 instructorMembershipId:z.uuid().nullable(),instructorLabel:z.string().nullable(),learnerLabel:z.string().nullable(),categoryCode:z.string().nullable(),productKey:z.string().nullable(),
 quantity:z.number().int().nullable(),durationSeconds:z.number().int().nullable(),amountCents:z.number().int().nullable(),
 courseTypeLabel:z.string().nullable(),markedCount:z.number().int().nullable(),missingMarks:z.number().int().nullable(),enrollmentId:z.uuid().nullable(),seriesId:z.uuid().nullable(),voidedAt:z.iso.datetime({offset:true}).nullable()}).strict();
export const detailsResponse=z.object({...header,measure:z.string().regex(/^[A-Z][0-9]{2}$/),period:periodSchema,scope:scopeSchema,
 total:z.object({lineCount:z.number().int().nonnegative(),amountCents:z.number().int().nullable(),durationSeconds:z.number().int().nullable()}).strict(),
 pageSum:z.object({amountCents:z.number().int().nullable(),durationSeconds:z.number().int().nullable()}).strict(),
 drift:z.object({lineCount:z.object({expected:z.number().int(),actual:z.number().int()}).strict().optional(),
  amountCents:z.object({expected:z.number().int(),actual:z.number().int().nullable()}).strict().optional()}).strict().nullable(),
 lines:z.array(lineSchema).max(maxDetailPage),page:z.object({limit:z.number().int().min(1).max(maxDetailPage),nextCursor:z.string().nullable()}).strict()}).strict();
export const definitionsResponse=z.object({definitionsVersion:z.literal(definitionsVersion),currency:z.literal('CHF'),
 measures:z.array(z.object({id:z.string().regex(/^[A-Z][0-9]{2}$/),domain:z.enum(['activity','finance']),unit:z.enum(['count','seconds','cents','permille']),label:z.string(),formula:z.string(),
  snapshot:z.boolean(),additive:z.boolean(),series:z.boolean(),details:z.boolean()}).strict()),
 limits:z.object({maxPeriodDays:z.literal(maxPeriodDays),maxBuckets:z.literal(maxBuckets),maxDetailPage:z.literal(maxDetailPage),maxExportLines:z.literal(maxExportLines)}).strict()}).strict();

// ---------------------------------------------------------------- CSV (export synchrone, décision D8)
export const csvColumns=['line_kind','line_id','event_at','status','instructor_id','instructor_name','category_code','product_key','quantity','duration_seconds','amount_cents','currency'] as const;
const dangerousStart=/^[=+\-@\t\r]/;
const quoteCell=(value:string)=>/[;"\r\n]/.test(value)?`"${value.replaceAll('"','""')}"`:value;
/** Cellule texte : neutralisée si un tableur pourrait y lire une formule, puis protégée (séparateur, guillemet, saut de ligne). */
export function textCell(value:string|null|undefined):string{
 if(value===null||value===undefined||value==='')return '';
 return quoteCell(dangerousStart.test(value)?`'${value}`:value);
}
export const numberCell=(value:number|bigint|null|undefined):string=>value===null||value===undefined?'':String(value);
/** UTF-8 avec BOM, séparateur « ; », fin de ligne CRLF ; métadonnées en tête, lignes commençant par « # ». */
export function csvDocument(meta:readonly (readonly [string,string])[],rows:readonly (readonly string[])[]):string{
 const lines=[...meta.map(([key,value])=>`#${key};${textCell(value)}`),csvColumns.join(';'),...rows.map(row=>row.join(';'))];
 return `﻿${lines.join('\r\n')}\r\n`;
}
