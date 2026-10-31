import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor,type Membership} from './database.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {Cursors,type Position} from './cursor.js';
import * as M from './school-metrics-model.js';
import type {Measure,Unit} from './school-metrics-model.js';

/**
 * Pilotage de l'école (#373, T02 #375). Extension hors canon OpenAPI 3.11.0 : contrat apps/api/contracts/school-metrics.json,
 * définitions docs/implementation/pilotage-373-indicateurs.md. Lecture seule : aucune opération, aucun audit, aucune écriture.
 * Les droits sont relus sur `membership` à chaque requête puis revérifiés par les fonctions SQL (metrics_gate) avant toute lecture.
 */
type Scope='school'|'self';
interface Rights {admin:boolean;instructor:boolean;school:boolean;finance:boolean;export:boolean;membershipId:string}
function rightsOf(member:Membership):Rights{
 const admin=member.roles.includes('ADMIN'),instructor=member.roles.includes('INSTRUCTOR'),staff=admin||instructor;
 return {admin,instructor,school:staff&&(admin||member.grants.includes('VIEW_SCHOOL_METRICS')),finance:staff&&(admin||member.grants.includes('VIEW_FINANCIAL_METRICS')),
  export:staff&&member.grants.includes('EXPORT_MANAGEMENT'),membershipId:member.id};
}
const scopeForbidden=()=>new ApiError(403,'METRIC_SCOPE_FORBIDDEN','Cette vue n’est pas autorisée pour votre accès.');
const accessRevoked=()=>new ApiError(403,'ACCESS_REVOKED','L’export n’est pas ou plus autorisé pour votre accès.');
const filterUnsupported=()=>new ApiError(400,'METRIC_FILTER_UNSUPPORTED','Ce filtre ne s’applique pas à cette mesure.');
const sqlFailures:Record<string,[number,string,string]>={
 METRIC_FORBIDDEN:[403,'METRIC_SCOPE_FORBIDDEN','Cette vue n’est pas autorisée pour votre accès.'],
 METRIC_SCOPE_FORBIDDEN:[403,'METRIC_SCOPE_FORBIDDEN','Cette vue n’est pas autorisée pour votre accès.'],
 ACCESS_REVOKED:[403,'ACCESS_REVOKED','L’export n’est pas ou plus autorisé pour votre accès.'],
 SCHOOL_NOT_ACTIVE:[409,'SCHOOL_NOT_ACTIVE','L’école doit être ouverte pour consulter ses indicateurs.'],
 INVALID_PERIOD:[422,'INVALID_PERIOD','Choisissez une période valide : dates réelles, début avant la fin.'],
};
function mapDbError(error:unknown):never{
 if(typeof error==='object'&&error!==null&&'code'in error){
  if(error.code==='P0001'&&'message'in error&&typeof error.message==='string'){const known=sqlFailures[error.message];if(known)throw new ApiError(known[0],known[1],known[2]);}
  if(error.code==='57014')throw new ApiError(503,'METRICS_UNAVAILABLE','Les indicateurs sont momentanément indisponibles.');
 }
 throw error;
}

/** Accumule les paramètres d'une requête pour numéroter $n sans jamais concaténer une valeur reçue. */
class Sql {
 readonly params:unknown[]=[];
 bind(value:unknown,cast=''):string{this.params.push(value);return `$${this.params.length}${cast}`;}
}
interface Ctx {schoolId:string;timeZone:string;nowIso:string;today:string;dataSince:string|null;scope:Scope;instructor:string|null;category:string|null;product:string|null;rights:Rights}
interface Instants {fromInstant:string;toInstant:string}
interface Filters {scope?:Scope|undefined;instructorMembershipId?:string|undefined;categoryCode?:string|undefined;productKey?:string|undefined}

function resolveScope(domain:M.Domain,rights:Rights,filters:Filters,denied:()=>ApiError):{scope:Scope;instructor:string|null}{
 if(domain==='finance'){
  if(!rights.finance||filters.scope==='self')throw denied();
  return {scope:'school',instructor:filters.instructorMembershipId??null};
 }
 const scope=filters.scope??(rights.school?'school':'self');
 if(scope==='school'){if(!rights.school)throw denied();return {scope,instructor:filters.instructorMembershipId??null};}
 if(!rights.instructor||(filters.instructorMembershipId&&filters.instructorMembershipId!==rights.membershipId))throw denied();
 return {scope:'self',instructor:rights.membershipId};
}
async function buildContext(db:PoolClient,member:Membership,schoolId:string,domain:M.Domain,filters:Filters,clock:(()=>Date)|undefined,denied:()=>ApiError=scopeForbidden):Promise<Ctx>{
 const rights=rightsOf(member),resolved=resolveScope(domain,rights,filters,denied);
 await db.query("SET LOCAL statement_timeout = '15s'");
 const school=(await db.query<{time_zone:string;status:string;now:Date;today:string}>(
  `SELECT s.time_zone,s.status,t.at AS now,(t.at AT TIME ZONE s.time_zone)::date::text AS today
   FROM drivy.school s CROSS JOIN (SELECT coalesce($2::timestamptz,now()) AS at) t WHERE s.id=$1`,[schoolId,clock?clock().toISOString():null])).rows[0];
 if(!school)throw notFound();
 if(school.status==='DRAFT')throw new ApiError(409,'SCHOOL_NOT_ACTIVE','L’école doit être ouverte pour consulter ses indicateurs.');
 const since=(await db.query<{d:string|null}>('SELECT drivy.metrics_data_since($1::uuid)::text AS d',[schoolId])).rows[0]!.d;
 return {schoolId,timeZone:school.time_zone,nowIso:school.now.toISOString(),today:school.today,dataSince:since,scope:resolved.scope,instructor:resolved.instructor,
  category:filters.categoryCode??null,product:filters.productKey??null,rights};
}
async function instantsOf(db:PoolClient,c:Ctx,from:string,toExclusive:string):Promise<Instants>{
 const row=(await db.query<{f:Date;t:Date}>(`SELECT ($1::date::timestamp AT TIME ZONE $3) AS f,($2::date::timestamp AT TIME ZONE $3) AS t`,[from,toExclusive,c.timeZone])).rows[0]!;
 return {fromInstant:row.f.toISOString(),toInstant:row.t.toISOString()};
}
type Availability='OK'|'BEFORE'|'STRADDLE';
const availabilityOf=(c:Ctx,from:string,toExclusive:string):Availability=>c.dataSince===null?'OK':toExclusive<=c.dataSince?'BEFORE':from<c.dataSince?'STRADDLE':'OK';

// ------------------------------------------------------------------ appels SQL
const lessonFn=(q:Sql,c:Ctx,from:string|null,to:string|null,money:boolean,status:string|null=null)=>
 `drivy.metrics_lesson_lines(${q.bind(c.schoolId,'::uuid')},${q.bind(from,'::date')},${q.bind(to,'::date')},${q.bind(c.nowIso,'::timestamptz')},${q.bind(c.scope,'::text')},${q.bind(c.instructor,'::uuid')},${q.bind(c.category,'::text')},${q.bind(c.product,'::text')},${q.bind(money,'::boolean')},${q.bind(status,'::text')})`;
const sessionFn=(q:Sql,c:Ctx,from:string|null,to:string|null)=>
 `drivy.metrics_course_session_lines(${q.bind(c.schoolId,'::uuid')},${q.bind(from,'::date')},${q.bind(to,'::date')},${q.bind(c.scope,'::text')},${q.bind(c.instructor,'::uuid')})`;
const paymentFn=(q:Sql,c:Ctx,from:string,to:string)=>`drivy.metrics_course_payment_lines(${q.bind(c.schoolId,'::uuid')},${q.bind(from,'::date')},${q.bind(to,'::date')})`;
/** Regroupements : constantes serveur, jamais une valeur reçue. Les intervalles s'appuient sur la date civile locale de la ligne. */
type Group='all'|'day'|'week'|'month'|'instructor'|'category'|'product';
const groupSql:Record<Group,string>={all:`'all'`,day:'local_day::text',week:`date_trunc('week',local_day::timestamp)::date::text`,month:`date_trunc('month',local_day::timestamp)::date::text`,
 instructor:'instructor_membership_id::text',category:'category_code',product:`coalesce(product_key,'UNRESOLVED')`};
const num=(value:string|number|bigint|null|undefined)=>M.safeInteger(value);
const courseFilterApplies=(c:Ctx)=>c.category===null&&c.product===null;
const seriesLevelApplies=(c:Ctx)=>courseFilterApplies(c)&&!(c.scope==='school'&&c.instructor!==null);

// ------------------------------------------------------------------ leçons : états, durées
interface StateRow {gk:string;state:M.LessonState;n:number;planned:number;known:number;actual:number;noStart:number;otherZone:number}
async function lessonStates(db:PoolClient,c:Ctx,from:string,to:string,group:Group):Promise<StateRow[]>{
 const q=new Sql(),fn=lessonFn(q,c,from,to,false);
 const rows=(await db.query<{gk:string;state:M.LessonState;n:number;planned:string;known:number;actual:string;no_start:number;other_zone:number}>(
  `SELECT ${groupSql[group]} AS gk,state,count(*)::int AS n,coalesce(sum(planned_seconds),0)::bigint AS planned,
   count(*) FILTER (WHERE actual_seconds IS NOT NULL)::int AS known,coalesce(sum(actual_seconds),0)::bigint AS actual,
   count(*) FILTER (WHERE state='COMPLETED' AND actual_start IS NULL)::int AS no_start,count(*) FILTER (WHERE other_time_zone)::int AS other_zone
   FROM ${fn} GROUP BY 1,2`,q.params)).rows;
 return rows.map(r=>({gk:r.gk,state:r.state,n:r.n,planned:num(r.planned),known:r.known,actual:num(r.actual),noStart:r.no_start,otherZone:r.other_zone}));
}
function lessonMeasures(rows:readonly StateRow[]):Record<string,Measure>{
 const by=(state:M.LessonState)=>rows.find(r=>r.state===state);
 const count=(state:M.LessonState)=>by(state)?.n??0;
 const out:Record<string,Measure>={};
 const completed=by('COMPLETED');
 for(const [id,state] of Object.entries(M.lessonStateOf)){
  const reasons=id==='L01'&&completed&&completed.noStart>0?[{code:'ACTUAL_START_MISSING',count:completed.noStart}]:[];
  out[id]=M.measure(count(state),'count',M.complete(reasons),{lineCount:count(state)});
 }
 const total=rows.reduce((sum,r)=>sum+r.n,0),mixed=rows.reduce((sum,r)=>sum+r.otherZone,0);
 out.L08=M.measure(total,'count',M.complete(mixed>0?[{code:'TIME_ZONE_MIXED',count:mixed}]:[]),{lineCount:total});
 const planned=(states:readonly M.LessonState[])=>rows.filter(r=>states.includes(r.state)).reduce((sum,r)=>sum+r.planned,0);
 out.H01=M.measure(planned(M.programmedStates),'seconds',M.complete(),{lineCount:rows.filter(r=>M.programmedStates.includes(r.state)).reduce((s,r)=>s+r.n,0)});
 out.H03=M.measure(planned(['UPCOMING']),'seconds',M.complete(),{lineCount:count('UPCOMING')});
 const done=completed?.n??0,known=completed?.known??0,unknown=done-known;
 const parts={knownCount:known,unknownDurationCount:unknown};
 out.H02=done===0?M.measure(0,'seconds',M.complete(),{lineCount:0,parts})
  :known===0?M.measure(null,'seconds',M.unavailable('DURATION_UNKNOWN'),{lineCount:done,parts})
  :unknown>0?M.measure(completed!.actual,'seconds',M.partial([{code:'DURATION_UNKNOWN',count:unknown}]),{lineCount:done,parts})
  :M.measure(completed!.actual,'seconds',M.complete(),{lineCount:done,parts});
 return out;
}

// ------------------------------------------------------------------ leçons : valeurs convenues
interface MoneyRow {gk:string;state:M.LessonState;n:number;eligible:number;cents:number;entitlement:number;mismatch:number}
async function lessonMoney(db:PoolClient,c:Ctx,from:string,to:string,group:Group):Promise<MoneyRow[]>{
 const q=new Sql(),fn=lessonFn(q,c,from,to,true);
 const ok=`commercial_mode='UNIT_PRICE' AND (state<>'COMPLETED' OR charge_cents=price_cents)`;
 const rows=(await db.query<{gk:string;state:M.LessonState;n:number;eligible:number;cents:string;entitlement:number;mismatch:number}>(
  `SELECT ${groupSql[group]} AS gk,state,count(*)::int AS n,count(*) FILTER (WHERE ${ok})::int AS eligible,
   coalesce(sum(price_cents) FILTER (WHERE ${ok}),0)::bigint AS cents,
   count(*) FILTER (WHERE commercial_mode<>'UNIT_PRICE')::int AS entitlement,
   count(*) FILTER (WHERE commercial_mode='UNIT_PRICE' AND state='COMPLETED' AND charge_cents IS DISTINCT FROM price_cents)::int AS mismatch
   FROM ${fn} GROUP BY 1,2`,q.params)).rows;
 return rows.map(r=>({gk:r.gk,state:r.state,n:r.n,eligible:r.eligible,cents:num(r.cents),entitlement:r.entitlement,mismatch:r.mismatch}));
}
function valueOf(rows:readonly MoneyRow[],states:readonly M.LessonState[]):Measure{
 const picked=rows.filter(r=>states.includes(r.state));
 const n=picked.reduce((s,r)=>s+r.n,0),eligible=picked.reduce((s,r)=>s+r.eligible,0),cents=picked.reduce((s,r)=>s+r.cents,0);
 const entitlement=picked.reduce((s,r)=>s+r.entitlement,0),mismatch=picked.reduce((s,r)=>s+r.mismatch,0);
 const reasons=[...(entitlement>0?[{code:'ENTITLEMENT_NOT_VALUED',count:entitlement}]:[]),...(mismatch>0?[{code:'CHARGE_MISMATCH',count:mismatch}]:[])];
 if(n===0)return M.measure(0,'cents',M.complete(),{lineCount:0});
 if(eligible===0)return M.measure(null,'cents',{status:'UNAVAILABLE',reasons},{lineCount:0});
 return M.measure(cents,'cents',reasons.length?M.partial(reasons):M.complete(),{lineCount:eligible});
}
function moneyMeasures(rows:readonly MoneyRow[]):Record<string,Measure>{
 const realised=valueOf(rows,['COMPLETED']),upcoming=valueOf(rows,['UPCOMING']),pending=valueOf(rows,M.pendingStates);
 const both=[realised,upcoming],values=both.filter(m=>m.value!==null);
 const reasons=both.flatMap(m=>m.coverage.reasons);
 const expected:Measure=values.length===0?M.measure(null,'cents',{status:'UNAVAILABLE',reasons},{lineCount:0})
  :M.measure(values.reduce((s,m)=>s+(m.value as number),0),'cents',both.every(m=>m.coverage.status==='COMPLETE')?M.complete():M.partial(reasons),{lineCount:both.reduce((s,m)=>s+(m.lineCount??0),0)});
 return {F01:realised,F02:upcoming,F03:expected,F04:pending};
}

// ------------------------------------------------------------------ cours et règlements
interface SessionRow {gk:string;sessions:number;series:number;marked:number;present:number;absent:number;excused:number}
async function courseSessions(db:PoolClient,c:Ctx,from:string,to:string,group:Group):Promise<SessionRow[]>{
 const q=new Sql(),fn=sessionFn(q,c,from,to);
 return (await db.query<{gk:string;sessions:number;series:number;marked:number;present:number;absent:number;excused:number}>(
  `SELECT ${groupSql[group]} AS gk,count(DISTINCT occurrence_id)::int AS sessions,count(DISTINCT series_id)::int AS series,
   count(DISTINCT occurrence_id) FILTER (WHERE attendance_status IS NOT NULL)::int AS marked,
   count(*) FILTER (WHERE attendance_status='PRESENT')::int AS present,count(*) FILTER (WHERE attendance_status='ABSENT')::int AS absent,
   count(*) FILTER (WHERE attendance_status='EXCUSED')::int AS excused FROM ${fn} GROUP BY 1`,q.params)).rows;
}
async function learnerCounts(db:PoolClient,c:Ctx,from:string,to:string,group:Group):Promise<{gk:string;total:number;lessons:number;courses:number}[]>{
 const q=new Sql(),lessons=lessonFn(q,c,from,to,false),sessions=courseFilterApplies(c)?sessionFn(q,c,from,to):null;
 const union=sessions?`UNION ALL SELECT ${groupSql[group]} AS gk,learner_id,false AS from_lessons FROM ${sessions} WHERE attendance_status='PRESENT'`:'';
 return (await db.query<{gk:string;total:number;lessons:number;courses:number}>(
  `SELECT gk,count(DISTINCT learner_id)::int AS total,count(DISTINCT learner_id) FILTER (WHERE from_lessons)::int AS lessons,
   count(DISTINCT learner_id) FILTER (WHERE NOT from_lessons)::int AS courses
   FROM (SELECT ${groupSql[group]} AS gk,learner_id,true AS from_lessons FROM ${lessons} WHERE state='COMPLETED' ${union}) u GROUP BY gk`,q.params)).rows;
}
const permille=(numerator:number,denominator:number)=>Number((BigInt(numerator)*2000n+BigInt(denominator))/(2n*BigInt(denominator)));

interface PaymentRow {entries:number;settled:number;voidedN:number;voidedCents:number;laterN:number;laterCents:number}
async function paymentTotals(db:PoolClient,c:Ctx,from:string,to:string,at:Instants):Promise<PaymentRow>{
 const q=new Sql(),fn=paymentFn(q,c,from,to),f=q.bind(at.fromInstant,'::timestamptz'),t=q.bind(at.toInstant,'::timestamptz');
 const row=(await db.query<{entries:number;settled:string;voided_n:number;voided_cents:string;later_n:number;later_cents:string}>(
  `SELECT count(*) FILTER (WHERE voided_at IS NULL AND recorded_at>=${f} AND recorded_at<${t})::int AS entries,
   coalesce(sum(amount_cents) FILTER (WHERE voided_at IS NULL AND recorded_at>=${f} AND recorded_at<${t}),0)::bigint AS settled,
   count(*) FILTER (WHERE voided_at IS NOT NULL AND recorded_at>=${f} AND recorded_at<${t})::int AS voided_n,
   coalesce(sum(amount_cents) FILTER (WHERE voided_at IS NOT NULL AND recorded_at>=${f} AND recorded_at<${t}),0)::bigint AS voided_cents,
   count(*) FILTER (WHERE voided_at>=${f} AND voided_at<${t} AND recorded_at<${f})::int AS later_n,
   coalesce(sum(amount_cents) FILTER (WHERE voided_at>=${f} AND voided_at<${t} AND recorded_at<${f}),0)::bigint AS later_cents
   FROM ${fn}`,q.params)).rows[0]!;
 return {entries:row.entries,settled:num(row.settled),voidedN:row.voided_n,voidedCents:num(row.voided_cents),laterN:row.later_n,laterCents:num(row.later_cents)};
}
function paymentMeasures(p:PaymentRow):Record<string,Measure>{
 return {F05:M.measure(p.settled,'cents',M.complete(),{lineCount:p.entries,parts:{entries:p.entries}}),
  F06:M.measure(p.voidedCents,'cents',M.complete(),{lineCount:p.voidedN+p.laterN,parts:{voidedEntries:p.voidedN,laterCorrections:p.laterN,laterCorrectionsCents:p.laterCents}})};
}
const courseUnavailable=(_id:string,unit:Unit):Measure=>M.measure(null,unit,M.notApplicable());
const unavailableFor=(ids:readonly string[],unitOf:(id:string)=>Unit,code:string):Record<string,Measure>=>
 Object.fromEntries(ids.map(id=>[id,M.measure(null,unitOf(id),M.unavailable(code))]));
const unitOfId=(id:string):Unit=>M.definitions.find(d=>d.id===id)?.unit??'count';
const additiveActivity=['L01','L02','L03','L04','L05','L06','L07','L08','H01','H02','H03','P01','C01','C02','C03','C05','C10'] as const;
const additiveFinance=['F01','F02','F03','F04','F05','F06'] as const;

/** Mesures liées à une période (comparables). Les instantanés sont calculés à part. */
async function activityPeriod(db:PoolClient,c:Ctx,from:string,to:string,at:Instants):Promise<Record<string,Measure>>{
 const availability=availabilityOf(c,from,to);
 if(availability==='BEFORE')return unavailableFor(additiveActivity,unitOfId,'BEFORE_DATA_START');
 const out:Record<string,Measure>={...lessonMeasures(await lessonStates(db,c,from,to,'all'))};
 const people=(await learnerCounts(db,c,from,to,'all'))[0]??{gk:'all',total:0,lessons:0,courses:0};
 out.P01=M.measure(people.total,'count',M.complete(),{parts:{lessons:people.lessons,courses:courseFilterApplies(c)?people.courses:null}});
 if(courseFilterApplies(c)){
  const s=(await courseSessions(db,c,from,to,'all'))[0]??{gk:'all',sessions:0,series:0,marked:0,present:0,absent:0,excused:0};
  out.C01=M.measure(s.sessions,'count',M.complete(),{lineCount:s.sessions});
  out.C02=M.measure(s.series,'count',M.complete());
  out.C03=M.measure(s.marked,'count',M.complete(),{lineCount:s.marked});
  out.C05=M.measure(s.present,'count',M.complete(),{parts:{absent:s.absent,excused:s.excused}});
 }else for(const id of ['C01','C02','C03','C05'])out[id]=courseUnavailable(id,'count');
 if(seriesLevelApplies(c)){
  const q=new Sql(),fn=`drivy.metrics_course_enrollment_events(${q.bind(c.schoolId,'::uuid')},${q.bind(from,'::date')},${q.bind(to,'::date')},${q.bind(c.scope,'::text')})`;
  const f=q.bind(at.fromInstant,'::timestamptz'),t=q.bind(at.toInstant,'::timestamptz');
  const e=(await db.query<{created:number;cancelled:number;own:number;staff:number;series:number}>(
   `SELECT count(*) FILTER (WHERE created_at>=${f} AND created_at<${t})::int AS created,count(*) FILTER (WHERE cancelled_at>=${f} AND cancelled_at<${t})::int AS cancelled,
    count(*) FILTER (WHERE cancelled_at>=${f} AND cancelled_at<${t} AND cancel_kind='SELF')::int AS own,
    count(*) FILTER (WHERE cancelled_at>=${f} AND cancelled_at<${t} AND cancel_kind='STAFF')::int AS staff,
    count(*) FILTER (WHERE cancelled_at>=${f} AND cancelled_at<${t} AND cancel_kind='SERIES_CANCELLED')::int AS series FROM ${fn}`,q.params)).rows[0]!;
  out.C10=M.measure(e.created,'count',M.complete(),{parts:{cancelled:e.cancelled,cancelledBySelf:e.own,cancelledByStaff:e.staff,cancelledWithSeries:e.series}});
 }else out.C10=courseUnavailable('C10','count');
 if(availability==='STRADDLE')for(const [id,m] of Object.entries(out))if(m.coverage.status==='COMPLETE'&&m.value!==null)out[id]={...m,coverage:M.partial([...m.coverage.reasons,{code:'STARTS_BEFORE_DATA_START'}])};
 return out;
}
async function financePeriod(db:PoolClient,c:Ctx,from:string,to:string,at:Instants):Promise<Record<string,Measure>>{
 const availability=availabilityOf(c,from,to);
 if(availability==='BEFORE')return unavailableFor(additiveFinance,unitOfId,'BEFORE_DATA_START');
 const out={...moneyMeasures(await lessonMoney(db,c,from,to,'all'))};
 const paymentFilter=c.instructor!==null||c.category!==null||c.product!==null;
 if(paymentFilter){out.F05=courseUnavailable('F05','cents');out.F06=courseUnavailable('F06','cents');}
 else Object.assign(out,paymentMeasures(await paymentTotals(db,c,from,to,at)));
 if(availability==='STRADDLE')for(const [id,m] of Object.entries(out))if(m.coverage.status==='COMPLETE'&&m.value!==null)out[id]={...m,coverage:M.partial([...m.coverage.reasons,{code:'STARTS_BEFORE_DATA_START'}])};
 return out;
}

/** Instantanés à l'instant de calcul : appels à renseigner, places, remplissage, états « à traiter », cours annulés de la période. */
async function activitySnapshots(db:PoolClient,c:Ctx,from:string,to:string,at:Instants):Promise<Record<string,Measure>>{
 const out:Record<string,Measure>={};
 {
  const q=new Sql(),fn=lessonFn(q,c,null,null,false,'PLANNED');
  const rows=(await db.query<{state:string;n:number}>(`SELECT state,count(*)::int AS n FROM ${fn} GROUP BY state`,q.params)).rows;
  const n=(state:string)=>rows.find(r=>r.state===state)?.n??0;
  out.A01=M.measure(n('TO_FINALIZE'),'count',M.complete(),{lineCount:n('TO_FINALIZE')});
  out.A03=M.measure(n('TO_VERIFY'),'count',M.complete(),{lineCount:n('TO_VERIFY')});
 }
 if(courseFilterApplies(c)){
  const q=new Sql(),fn=sessionFn(q,c,null,null),now=q.bind(c.nowIso,'::timestamptz');
  const row=(await db.query<{sessions:number;missing:number}>(
   `SELECT count(DISTINCT occurrence_id)::int AS sessions,count(*)::int AS missing FROM ${fn} WHERE starts_at<=${now} AND expected AND attendance_status IS NULL`,q.params)).rows[0]!;
  out.C04=M.measure(row.sessions,'count',M.complete(),{lineCount:row.sessions,parts:{missingMarks:row.missing}});
  out.A02=M.measure(row.sessions,'count',M.complete(),{lineCount:row.sessions,parts:{missingMarks:row.missing}});
 }else for(const id of ['C04','A02'])out[id]=courseUnavailable(id,'count');
 if(seriesLevelApplies(c)){
  const q=new Sql(),fn=`drivy.metrics_course_series_lines(${q.bind(c.schoolId,'::uuid')},${q.bind(from,'::date')},${q.bind(to,'::date')},${q.bind(c.nowIso,'::timestamptz')},${q.bind(c.scope,'::text')},${q.bind(c.scope==='self'?c.instructor:null,'::uuid')})`;
  const rows=(await db.query<{series_status:string;capacity:number;first_starts_at:Date|null;occurrence_count:number;active_enrollments:number;active_offers:number}>(`SELECT series_status,capacity,first_starts_at,occurrence_count,active_enrollments,active_offers FROM ${fn}`,q.params)).rows;
  const published=rows.filter(r=>r.series_status==='PUBLISHED'),sum=(f:(r:typeof published[number])=>number)=>published.reduce((s,r)=>s+f(r),0);
  const enrollments=sum(r=>r.active_enrollments),offers=sum(r=>r.active_offers),capacity=sum(r=>r.capacity),occupied=enrollments+offers;
  out.C06=M.measure(enrollments,'count',M.complete(),{lineCount:published.length});
  out.C07=M.measure(offers,'count',M.complete());
  out.C08=M.measure(occupied,'count',M.complete(),{parts:{capacity,free:sum(r=>Math.max(0,r.capacity-r.active_enrollments-r.active_offers)),overbooked:published.filter(r=>r.active_enrollments+r.active_offers>r.capacity).length}});
  const now=Date.parse(c.nowIso),upcoming=published.filter(r=>r.first_starts_at!==null&&r.first_starts_at.getTime()>now&&r.first_starts_at.toISOString()>=at.fromInstant&&r.first_starts_at.toISOString()<at.toInstant);
  const denominator=upcoming.reduce((s,r)=>s+r.capacity,0),numerator=upcoming.reduce((s,r)=>s+r.active_enrollments+r.active_offers,0);
  out.C09=Date.parse(at.toInstant)<=now?M.measure(null,'permille',M.unavailable('SNAPSHOT_ONLY'))
   :denominator===0?M.measure(null,'permille',M.unavailable('NO_DENOMINATOR'))
   :M.measure(permille(numerator,denominator),'permille',M.complete(),{parts:{numerator,denominator}});
  const cancelled=rows.filter(r=>r.series_status==='CANCELLED');
  out.C11=M.measure(cancelled.length,'count',M.complete(),{lineCount:cancelled.length,parts:{sessions:cancelled.reduce((s,r)=>s+r.occurrence_count,0)}});
 }else for(const id of ['C06','C07','C08','C11'])out[id]=courseUnavailable(id,'count');
 if(!seriesLevelApplies(c))out.C09=courseUnavailable('C09','permille');
 return out;
}

// ------------------------------------------------------------------ comparaison et répartition
async function comparisonOf(db:PoolClient,c:Ctx,domain:M.Domain,current:Record<string,Measure>,plan:M.ComparisonPlan):Promise<NonNullable<z.infer<typeof M.metricsResponse>['comparison']>>{
 const before=availabilityOf(c,plan.base.from,plan.base.toExclusive)==='BEFORE';
 const at=await instantsOf(db,c,plan.base.from,plan.base.toExclusive);
 const base=domain==='activity'?await activityPeriod(db,c,plan.base.from,plan.base.toExclusive,at):await financePeriod(db,c,plan.base.from,plan.base.toExclusive,at);
 const ids=domain==='activity'?additiveActivity:additiveFinance,measures:Record<string,M.Comparison>={};
 for(const id of ids){
  const a=current[id],b=base[id];if(!a||!b||a.coverage.status==='NOT_APPLICABLE')continue;
  const done=(m:Measure)=>m.coverage.status==='COMPLETE'&&m.value!==null;
  measures[id]=M.compareValues({value:a.value,complete:done(a)},{value:before?null:b.value,complete:done(b),beforeData:before});
 }
 return {mode:plan.mode,base:plan.base,measures};
}
async function breakdownOf(db:PoolClient,c:Ctx,domain:M.Domain,by:'instructor'|'category'|'product',from:string,to:string):Promise<NonNullable<z.infer<typeof M.metricsResponse>['breakdown']>>{
 if(availabilityOf(c,from,to)==='BEFORE')return {by,groups:[]};
 const rows:(StateRow|MoneyRow)[]=domain==='activity'?await lessonStates(db,c,from,to,by):await lessonMoney(db,c,from,to,by);
 const keys=[...new Set(rows.map(r=>r.gk))].sort();
 const labels=new Map<string,string|null>();
 for(const key of keys){
  if(by==='category'||key==='UNRESOLVED')labels.set(key,by==='category'?key:null);
  else if(by==='instructor')labels.set(key,(await db.query<{name:string|null}>('SELECT drivy.course_staff_name($1::uuid,$2::uuid) AS name',[c.schoolId,key])).rows[0]?.name??null);
  else labels.set(key,(await db.query<{label:string|null}>('SELECT label FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 ORDER BY version DESC LIMIT 1',[c.schoolId,key])).rows[0]?.label??null);
 }
 const groups=keys.map(key=>{
  const mine=rows.filter(r=>r.gk===key);
  return {key,label:labels.get(key)??null,measures:domain==='activity'?lessonMeasures(mine as StateRow[]):moneyMeasures(mine as MoneyRow[])};
 });
 return {by,groups};
}
function periodBlock(from:string,toExclusive:string,at:Instants){return {from,toExclusive,days:M.daysBetween(from,toExclusive),...at};}
const header=(c:Ctx)=>({definitionsVersion:M.definitionsVersion,schoolId:c.schoolId,timeZone:c.timeZone,currency:'CHF' as const,computedAt:c.nowIso,dataSince:c.dataSince});
const scopeBlock=(c:Ctx)=>({kind:c.scope,filters:{instructorMembershipId:c.instructor,categoryCode:c.category,productKey:c.product}});

// ------------------------------------------------------------------ détails et export
type LineSpec={kind:'lesson';pred:string;money:boolean;durationSource:'planned'|'actual'|'mixed'}|{kind:'occurrence';mode:'all'|'marked'|'missing'}|{kind:'payment';pred:'active'|'voided'|'later'};
function lineSpec(measure:string,part:'a'|'b'|undefined):LineSpec{
 if(measure!=='F06'&&part!==undefined)throw new ApiError(400,'INVALID_REQUEST','Paramètres invalides.');
 const state=(s:string)=>`state='${s}'`,list=(states:readonly string[])=>`state IN (${states.map(s=>`'${s}'`).join(',')})`;
 const realised=`state='COMPLETED' AND commercial_mode='UNIT_PRICE' AND charge_cents=price_cents`,upcoming=`state='UPCOMING' AND commercial_mode='UNIT_PRICE'`;
 switch(measure){
  case 'L01':case 'L02':case 'L03':case 'L04':case 'L05':case 'L06':case 'L07':return {kind:'lesson',pred:state(M.lessonStateOf[measure]!),money:false,durationSource:'mixed'};
  case 'L08':return {kind:'lesson',pred:'true',money:false,durationSource:'mixed'};
  case 'H01':return {kind:'lesson',pred:list(M.programmedStates),money:false,durationSource:'planned'};
  case 'H02':return {kind:'lesson',pred:state('COMPLETED'),money:false,durationSource:'actual'};
  case 'H03':return {kind:'lesson',pred:state('UPCOMING'),money:false,durationSource:'planned'};
  case 'F01':return {kind:'lesson',pred:realised,money:true,durationSource:'mixed'};
  case 'F02':return {kind:'lesson',pred:upcoming,money:true,durationSource:'mixed'};
  case 'F03':return {kind:'lesson',pred:`(${realised}) OR (${upcoming})`,money:true,durationSource:'mixed'};
  case 'F04':return {kind:'lesson',pred:`${list(M.pendingStates)} AND commercial_mode='UNIT_PRICE'`,money:true,durationSource:'planned'};
  case 'C01':return {kind:'occurrence',mode:'all'};
  case 'C03':return {kind:'occurrence',mode:'marked'};
  case 'C04':return {kind:'occurrence',mode:'missing'};
  case 'F05':return {kind:'payment',pred:'active'};
  case 'F06':if(part===undefined)throw new ApiError(400,'INVALID_REQUEST','Paramètres invalides.');return {kind:'payment',pred:part==='a'?'voided':'later'};
  default:throw new ApiError(400,'METRIC_DETAIL_UNSUPPORTED','Cette mesure n’a pas de détail.');
 }
}
const domainOfMeasure=(measure:string):M.Domain=>measure.startsWith('F')?'finance':'activity';
interface Line {kind:'LESSON'|'COURSE_OCCURRENCE'|'COURSE_PAYMENT';id:string;eventAt:string;eventLocal:string;cursorAt:string;status:string;instructorMembershipId:string|null;instructorLabel:string|null;learnerLabel:string|null;
 categoryCode:string|null;productKey:string|null;quantity:number|null;durationSeconds:number|null;amountCents:number|null;courseTypeLabel:string|null;markedCount:number|null;
 missingMarks:number|null;enrollmentId:string|null;seriesId:string|null;voidedAt:string|null}
const exportTooLarge=()=>new ApiError(413,'EXPORT_TOO_LARGE','L’export dépasse 10 000 lignes. Réduisez la période ou ajoutez un filtre.');
interface Loaded {total:{lineCount:number;amountCents:number|null;durationSeconds:number|null};lines:Line[];more:boolean}
interface Selection {measure:string;part?:'a'|'b'|undefined;from:string;toExclusive:string;bucketFrom?:string|undefined;bucketToExclusive?:string|undefined}

async function loadLines(db:PoolClient,c:Ctx,selection:Selection,at:Instants,options:{cursor?:Position|undefined;limit:number;local:boolean;refuseAbove?:number|undefined}):Promise<Loaded>{
 const spec=lineSpec(selection.measure,selection.part);
 const totalQ=new Sql(),pageQ=new Sql();
 const sessionBounds=(q:Sql)=>selection.bucketFrom&&selection.bucketToExclusive?` AND local_day>=${q.bind(selection.bucketFrom,'::date')} AND local_day<${q.bind(selection.bucketToExclusive,'::date')}`:'';
 const local=(column:string)=>options.local?`to_char(${column},'YYYY-MM-DD"T"HH24:MI:SS')||to_char(${column},'TZH":"TZM')`:`''`;
 if(options.local)await db.query("SELECT set_config('TimeZone',$1,true)",[c.timeZone]);
 const cursorAt=(column:string)=>`to_char(${column} AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
 const keyset=(q:Sql,at:string,id:string)=>options.cursor?` AND (${at},${id})>(${q.bind(options.cursor.createdAt,'::timestamptz')},${q.bind(options.cursor.id,'::uuid')})`:'';
 if(spec.kind==='lesson'){
  const base=(q:Sql)=>`FROM ${lessonFn(q,c,selection.from,selection.toExclusive,spec.money)} WHERE (${spec.pred})${sessionBounds(q)}`;
  const t=(await db.query<{n:number;amount:string;planned:string;actual:string}>(
   `SELECT count(*)::int AS n,coalesce(sum(price_cents),0)::bigint AS amount,coalesce(sum(planned_seconds),0)::bigint AS planned,coalesce(sum(actual_seconds),0)::bigint AS actual ${base(totalQ)}`,totalQ.params)).rows[0]!;
  const duration=spec.durationSource==='planned'?num(t.planned):spec.durationSource==='actual'?num(t.actual):null;
  const total={lineCount:t.n,amountCents:spec.money?num(t.amount):null,durationSeconds:duration};
  // Un export trop grand est refusé d'après le seul compte : aucune page de 10 000 noms n'est calculée pour rien.
  if(options.refuseAbove!==undefined&&t.n>options.refuseAbove)throw exportTooLarge();
  const school=pageQ.bind(c.schoolId,'::uuid');
  // Les noms (fonctions d'accès contrôlé) ne sont calculés qu'une fois par moniteur et par apprenant distincts de la page, pas une fois par ligne.
  const rows=(await db.query<Record<string,unknown>>(
   `WITH page AS MATERIALIZED (
     SELECT lesson_id,event_at,${cursorAt('event_at')} AS cursor_at,${local('event_at')} AS event_local,state,instructor_membership_id,training_id,learner_id,category_code,product_key,quantity,
     CASE WHEN ${spec.durationSource==='actual'?'true':'false'} OR (${spec.durationSource==='mixed'?'true':'false'} AND state='COMPLETED') THEN actual_seconds ELSE planned_seconds END AS seconds,
     price_cents
     ${base(pageQ)}${keyset(pageQ,'event_at','lesson_id')} ORDER BY event_at,lesson_id LIMIT ${pageQ.bind(options.limit+1,'::int')}),
    staff AS MATERIALIZED (SELECT d.m AS instructor_membership_id,drivy.course_staff_name(${school},d.m) AS label
     FROM (SELECT DISTINCT instructor_membership_id AS m FROM page) d),
    learner AS MATERIALIZED (SELECT d.t AS training_id,d.l AS learner_id,d.m AS instructor_membership_id,drivy.lesson_learner_name(${school},d.t,d.m,d.l) AS label
     FROM (SELECT DISTINCT training_id AS t,learner_id AS l,instructor_membership_id AS m FROM page) d)
    SELECT p.lesson_id,p.event_at,p.cursor_at,p.event_local,p.state,p.instructor_membership_id,p.learner_id,p.category_code,p.product_key,p.quantity,p.seconds,p.price_cents,
     s.label AS instructor_label,l.label AS learner_label
    FROM page p
    LEFT JOIN staff s ON s.instructor_membership_id=p.instructor_membership_id
    LEFT JOIN learner l ON l.training_id=p.training_id AND l.learner_id=p.learner_id AND l.instructor_membership_id=p.instructor_membership_id
    ORDER BY p.event_at,p.lesson_id`,pageQ.params)).rows;
  const lines=rows.slice(0,options.limit).map((r):Line=>({kind:'LESSON',id:String(r.lesson_id),eventAt:(r.event_at as Date).toISOString(),eventLocal:String(r.event_local),cursorAt:String(r.cursor_at),status:String(r.state),
   instructorMembershipId:r.instructor_membership_id as string,instructorLabel:(r.instructor_label as string|null)??null,learnerLabel:(r.learner_label as string|null)??null,
   categoryCode:r.category_code as string|null,productKey:r.product_key as string|null,quantity:r.quantity as number|null,durationSeconds:r.seconds===null?null:Number(r.seconds),
   amountCents:spec.money&&r.price_cents!==null?num(r.price_cents as string):null,courseTypeLabel:null,markedCount:null,missingMarks:null,enrollmentId:null,seriesId:null,voidedAt:null}));
  return {total,lines,more:rows.length>options.limit};
 }
 if(spec.kind==='occurrence'){
  const unbounded=spec.mode==='missing';
  const grouped=(q:Sql)=>`FROM (SELECT occurrence_id,series_id,type_id,starts_at,instructor_membership_id,
    count(*) FILTER (WHERE attendance_status IS NOT NULL)::int AS marked,count(*) FILTER (WHERE expected AND attendance_status IS NULL)::int AS missing
    FROM ${sessionFn(q,c,unbounded?null:selection.from,unbounded?null:selection.toExclusive)}
    WHERE true${unbounded?` AND starts_at<=${q.bind(c.nowIso,'::timestamptz')}`:''}${sessionBounds(q)}
    GROUP BY occurrence_id,series_id,type_id,starts_at,instructor_membership_id) o
    WHERE ${spec.mode==='marked'?'marked>0':spec.mode==='missing'?'missing>0':'true'}`;
  const t=(await db.query<{n:number}>(`SELECT count(*)::int AS n ${grouped(totalQ)}`,totalQ.params)).rows[0]!;
  if(options.refuseAbove!==undefined&&t.n>options.refuseAbove)throw exportTooLarge();
  const school=pageQ.bind(c.schoolId,'::uuid');
  const rows=(await db.query<Record<string,unknown>>(
   `SELECT occurrence_id,series_id,starts_at,${cursorAt('starts_at')} AS cursor_at,${local('starts_at')} AS event_local,marked,missing,instructor_membership_id,
    (SELECT title FROM drivy.course_type t WHERE t.id=o.type_id) AS type_label,drivy.course_staff_name(${school},instructor_membership_id) AS instructor_label
    ${grouped(pageQ)}${keyset(pageQ,'starts_at','occurrence_id')} ORDER BY starts_at,occurrence_id LIMIT ${pageQ.bind(options.limit+1,'::int')}`,pageQ.params)).rows;
  const lines=rows.slice(0,options.limit).map((r):Line=>({kind:'COURSE_OCCURRENCE',id:String(r.occurrence_id),eventAt:(r.starts_at as Date).toISOString(),eventLocal:String(r.event_local),cursorAt:String(r.cursor_at),
   status:(r.starts_at as Date).getTime()>Date.parse(c.nowIso)?'UPCOMING':(r.missing as number)>0?'TO_MARK':(r.marked as number)>0?'MARKED':'NO_ATTENDEE',instructorMembershipId:r.instructor_membership_id as string,instructorLabel:(r.instructor_label as string|null)??null,learnerLabel:null,categoryCode:null,productKey:null,
   quantity:null,durationSeconds:null,amountCents:null,courseTypeLabel:(r.type_label as string|null)??null,markedCount:r.marked as number,missingMarks:r.missing as number,enrollmentId:null,seriesId:String(r.series_id),voidedAt:null}));
  return {total:{lineCount:t.n,amountCents:null,durationSeconds:null},lines,more:rows.length>options.limit};
 }
 const pred=(q:Sql)=>{
  const f=q.bind(at.fromInstant,'::timestamptz'),t=q.bind(at.toInstant,'::timestamptz');
  return spec.pred==='active'?`voided_at IS NULL AND recorded_at>=${f} AND recorded_at<${t}`:spec.pred==='voided'?`voided_at IS NOT NULL AND recorded_at>=${f} AND recorded_at<${t}`
   :`voided_at>=${f} AND voided_at<${t} AND recorded_at<${f}`;
 };
 const base=(q:Sql)=>`FROM ${paymentFn(q,c,selection.from,selection.toExclusive)} WHERE ${pred(q)}${sessionBounds(q)}`;
 const t=(await db.query<{n:number;amount:string}>(`SELECT count(*)::int AS n,coalesce(sum(amount_cents),0)::bigint AS amount ${base(totalQ)}`,totalQ.params)).rows[0]!;
 if(options.refuseAbove!==undefined&&t.n>options.refuseAbove)throw exportTooLarge();
 const rows=(await db.query<Record<string,unknown>>(
  `SELECT payment_id,enrollment_id,series_id,recorded_at,${cursorAt('recorded_at')} AS cursor_at,${local('recorded_at')} AS event_local,amount_cents,voided_at,
   drivy.lesson_learner_display_name_for_course(enrollment_id) AS learner_label
   ${base(pageQ)}${keyset(pageQ,'recorded_at','payment_id')} ORDER BY recorded_at,payment_id LIMIT ${pageQ.bind(options.limit+1,'::int')}`,pageQ.params)).rows;
 const lines=rows.slice(0,options.limit).map((r):Line=>({kind:'COURSE_PAYMENT',id:String(r.payment_id),eventAt:(r.recorded_at as Date).toISOString(),eventLocal:String(r.event_local),cursorAt:String(r.cursor_at),
  status:r.voided_at===null?'ACTIVE':'VOIDED',instructorMembershipId:null,instructorLabel:null,learnerLabel:(r.learner_label as string|null)??null,categoryCode:null,productKey:null,quantity:null,durationSeconds:null,
  amountCents:num(r.amount_cents as string),courseTypeLabel:null,markedCount:null,missingMarks:null,enrollmentId:String(r.enrollment_id),seriesId:String(r.series_id),voidedAt:r.voided_at===null?null:(r.voided_at as Date).toISOString()}));
 return {total:{lineCount:t.n,amountCents:num(t.amount),durationSeconds:null},lines,more:rows.length>options.limit};
}
function publicLine(line:Line){
 const {eventLocal:_local,cursorAt:_cursor,...rest}=line;
 return rest;
}
function sumPage(lines:readonly Line[]){
 const has=lines.some(l=>l.amountCents!==null),hasDuration=lines.some(l=>l.durationSeconds!==null);
 return {amountCents:has?M.safeInteger(lines.reduce((s,l)=>s+BigInt(l.amountCents??0),0n)):null,durationSeconds:hasDuration?lines.reduce((s,l)=>s+(l.durationSeconds??0),0):null};
}
function driftOf(total:Loaded['total'],expectedLineCount:number|undefined,expectedAmountCents:number|undefined){
 const lineCount=expectedLineCount!==undefined&&expectedLineCount!==total.lineCount?{expected:expectedLineCount,actual:total.lineCount}:undefined;
 const amountCents=expectedAmountCents!==undefined&&expectedAmountCents!==total.amountCents?{expected:expectedAmountCents,actual:total.amountCents}:undefined;
 return lineCount||amountCents?{...(lineCount?{lineCount}:{}),...(amountCents?{amountCents}:{})}:null;
}
/** Filtres refusés pour une mesure demandée explicitement (règlements, cours) : jamais ignorés en silence. */
function checkFilters(measure:string,filters:Filters){
 const course=measure.startsWith('C'),payment=measure==='F05'||measure==='F06';
 if(payment&&(filters.instructorMembershipId||filters.categoryCode||filters.productKey))throw filterUnsupported();
 if(course&&(filters.categoryCode||filters.productKey))throw filterUnsupported();
}

/** `clock` n'existe que pour les tests (instant de calcul figé) ; l'application réelle lit l'horloge de la base. */
export function registerSchoolMetrics(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string;clock?:(()=>Date)|undefined}){
 const base='/v1/schools/:schoolId/metrics',cursors=new Cursors(options.cursorSecret);
 const schoolId=(r:FastifyRequest)=>z.object({schoolId:z.uuid()}).parse(r.params).schoolId;
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 async function read<T>(r:FastifyRequest,work:(db:PoolClient,member:Membership,school:string,personId:string)=>Promise<T>):Promise<T>{
  const identity=await options.verifyToken(r.headers.authorization),school=schoolId(r);
  return withActor(options.pool,identity,school,async(db,actor,member)=>{
   if(!member)throw forbidden();
   try{return await work(db,member,school,actor.personId);}catch(error){return mapDbError(error);}
  });
 }

 app.get(`${base}/definitions`,async r=>{
  z.object({}).strict().parse(r.query);
  const data=await read(r,async(_db,member)=>{
   const rights=rightsOf(member);
   if(!rights.admin&&!rights.instructor)throw scopeForbidden();
   return M.definitionsResponse.parse({definitionsVersion:M.definitionsVersion,currency:'CHF',measures:M.definitions,
    limits:{maxPeriodDays:M.maxPeriodDays,maxBuckets:M.maxBuckets,maxDetailPage:M.maxDetailPage,maxExportLines:M.maxExportLines}});
  });
  return envelope(data,r);
 });

 app.get(base,async r=>{
  const query=M.metricsQuery.parse(r.query);
  M.validatePeriod(query.from,query.toExclusive);
  const data=await read(r,async(db,member,school)=>{
   const c=await buildContext(db,member,school,query.domain,query,options.clock);
   const plan=query.compare==='none'?null:M.planComparison(query.compare,query.from,query.toExclusive,c.today);
   const at=await instantsOf(db,c,query.from,query.toExclusive);
   const current=query.domain==='activity'?await activityPeriod(db,c,query.from,query.toExclusive,at):await financePeriod(db,c,query.from,query.toExclusive,at);
   const measures:Record<string,Measure>={...current};
   if(query.domain==='activity')Object.assign(measures,await activitySnapshots(db,c,query.from,query.toExclusive,at));
   else measures.F07=M.measure(null,'cents',M.unavailable('COURSE_PRICE_SOURCE_MISSING'));
   const body={...header(c),domain:query.domain,period:periodBlock(query.from,query.toExclusive,at),scope:scopeBlock(c),
    ...(query.domain==='finance'?{coverageNotes:{lessons:'INDIVIDUAL_UNIT_PRICE_ONLY' as const,payments:'COURSE_ON_SITE_ENTRIES_ONLY' as const,paymentDate:'ENTRY_DATE' as const}}:{}),
    measures,
    ...(plan?{comparison:await comparisonOf(db,c,query.domain,current,plan)}:{}),
    ...(query.breakdown?{breakdown:await breakdownOf(db,c,query.domain,query.breakdown,query.from,query.toExclusive)}:{})};
   return M.metricsResponse.parse(body);
  });
  return envelope(data,r);
 });

 app.get(`${base}/series`,async r=>{
  const query=M.seriesQuery.parse(r.query);
  M.validatePeriod(query.from,query.toExclusive);
  const ids=query.measures.split(',');
  if(new Set(ids).size!==ids.length||!ids.every(id=>M.definitions.find(d=>d.id===id&&d.series)))throw new ApiError(400,'INVALID_REQUEST','Paramètres invalides.');
  const domain=domainOfMeasure(ids[0]!);
  if(ids.some(id=>domainOfMeasure(id)!==domain))throw new ApiError(400,'INVALID_REQUEST','Paramètres invalides.');
  ids.forEach(id=>checkFilters(id,query));
  const list=M.buckets(query.from,query.toExclusive,query.granularity);
  const data=await read(r,async(db,member,school)=>{
   const c=await buildContext(db,member,school,domain,query,options.clock);
   const at=await instantsOf(db,c,query.from,query.toExclusive),group:Group=query.granularity;
   const before=availabilityOf(c,query.from,query.toExclusive)==='BEFORE';
   const perBucket=new Map<string,Record<string,Measure>>();
   if(!before){
    if(domain==='activity'){
     const rows=await lessonStates(db,c,query.from,query.toExclusive,group);
     for(const key of new Set(rows.map(r=>r.gk)))perBucket.set(key,lessonMeasures(rows.filter(r=>r.gk===key)));
     if(ids.includes('P01'))for(const row of await learnerCounts(db,c,query.from,query.toExclusive,group))perBucket.set(row.gk,{...(perBucket.get(row.gk)??{}),P01:M.measure(row.total,'count',M.complete())});
     if(ids.some(id=>id==='C01'||id==='C03'))for(const row of await courseSessions(db,c,query.from,query.toExclusive,group))
      perBucket.set(row.gk,{...(perBucket.get(row.gk)??{}),C01:M.measure(row.sessions,'count',M.complete()),C03:M.measure(row.marked,'count',M.complete())});
    }else{
     const rows=await lessonMoney(db,c,query.from,query.toExclusive,group);
     for(const key of new Set(rows.map(r=>r.gk)))perBucket.set(key,moneyMeasures(rows.filter(r=>r.gk===key)));
     if(ids.includes('F05')){
      const q=new Sql(),fn=paymentFn(q,c,query.from,query.toExclusive),f=q.bind(at.fromInstant,'::timestamptz'),t=q.bind(at.toInstant,'::timestamptz');
      for(const row of (await db.query<{gk:string;cents:string;n:number}>(`SELECT ${groupSql[group]} AS gk,coalesce(sum(amount_cents),0)::bigint AS cents,count(*)::int AS n FROM ${fn} WHERE voided_at IS NULL AND recorded_at>=${f} AND recorded_at<${t} GROUP BY 1`,q.params)).rows)
       perBucket.set(row.gk,{...(perBucket.get(row.gk)??{}),F05:M.measure(num(row.cents),'cents',M.complete(),{lineCount:row.n})});
     }
    }
   }
   const zero=(id:string):Measure=>M.measure(0,unitOfId(id),M.complete());
   const body={...header(c),domain,period:periodBlock(query.from,query.toExclusive,at),scope:scopeBlock(c),granularity:query.granularity,
    buckets:list.map(bucket=>({from:bucket.from,toExclusive:bucket.toExclusive,partial:bucket.partial,
     measures:Object.fromEntries(ids.map(id=>{
      // Avant le début des données de l'école, un intervalle est inconnu (K10), jamais un zéro.
      const availability=availabilityOf(c,bucket.from,bucket.toExclusive);
      if(availability==='BEFORE')return [id,{value:null,coverage:M.unavailable('BEFORE_DATA_START')}];
      const m=perBucket.get(bucket.key)?.[id]??(domain==='activity'&&id.startsWith('L')?lessonMeasures([])[id]:undefined)??zero(id);
      const coverage=availability==='STRADDLE'&&m.coverage.status==='COMPLETE'&&m.value!==null?M.partial([...m.coverage.reasons,{code:'STARTS_BEFORE_DATA_START'}]):m.coverage;
      return [id,{value:m.value,...(coverage.status==='COMPLETE'?{}:{coverage})}];
     }))}))};
   return M.seriesResponse.parse(body);
  });
  return envelope(data,r);
 });

 app.get(`${base}/details`,async r=>{
  const query=M.detailsQuery.parse(r.query);
  M.validatePeriod(query.from,query.toExclusive);
  lineSpec(query.measure,query.part);checkFilters(query.measure,query);
  const domain=domainOfMeasure(query.measure);
  const data=await read(r,async(db,member,school,personId)=>{
   const c=await buildContext(db,member,school,domain,query,options.clock);
   const at=await instantsOf(db,c,query.from,query.toExclusive);
   const scope=JSON.stringify(['metrics-details',school,personId,member.accessEpoch,query.measure,query.part??null,query.from,query.toExclusive,query.bucketFrom??null,query.bucketToExclusive??null,c.scope,c.instructor,c.category,c.product,M.definitionsVersion,query.limit]);
   const loaded=await loadLines(db,c,query,at,{cursor:cursors.decode(query.cursor,scope),limit:query.limit,local:false});
   const last=loaded.lines.at(-1);
   return M.detailsResponse.parse({...header(c),measure:query.measure,period:periodBlock(query.from,query.toExclusive,at),scope:scopeBlock(c),total:loaded.total,pageSum:sumPage(loaded.lines),
    drift:driftOf(loaded.total,query.expectedLineCount,query.expectedAmountCents),lines:loaded.lines.map(publicLine),
    page:{limit:query.limit,nextCursor:loaded.more&&last?cursors.encode(scope,{id:last.id,createdAt:last.cursorAt}):null}});
  });
  return envelope(data,r);
 });

 app.post(`${base}/exports`,{bodyLimit:4_096},async(r,reply)=>{
  z.object({}).strict().parse(r.query);
  const body=M.exportBody.parse(r.body);
  M.validatePeriod(body.from,body.toExclusive);
  lineSpec(body.measure,body.part);checkFilters(body.measure,body);
  const domain=domainOfMeasure(body.measure);
  const csv=await read(r,async(db,member,school)=>{
   const c=await buildContext(db,member,school,domain,body,options.clock,accessRevoked);
   if(!c.rights.export)throw accessRevoked();
   // Le droit d'export et celui de la mesure sont aussi revérifiés par la base, sur le même instantané.
   await db.query('SELECT * FROM drivy.metrics_gate($1::uuid,$2,$3,$4::uuid,true)',[school,domain==='finance'?'FINANCE':'ACTIVITY',c.scope,c.instructor]);
   const at=await instantsOf(db,c,body.from,body.toExclusive);
   const loaded=await loadLines(db,c,body,at,{limit:M.maxExportLines,local:true,refuseAbove:M.maxExportLines});
   if(loaded.more)throw exportTooLarge();
   // Couverture de la mesure exportée, calculée sur le même périmètre : un export partiel n'est jamais annoncé complet.
   const all=domain==='activity'?{...await activityPeriod(db,c,body.from,body.toExclusive,at),...await activitySnapshots(db,c,body.from,body.toExclusive,at)}:await financePeriod(db,c,body.from,body.toExclusive,at);
   const coverage=all[body.measure]?.coverage??M.complete();
   const drift=driftOf(loaded.total,body.expectedLineCount,body.expectedAmountCents);
   const filters=[c.instructor?`instructor=${c.instructor}`:'',c.category?`category=${c.category}`:'',c.product?`product=${c.product}`:''].filter(Boolean).join('|');
   const meta:[string,string][]=[['definitionsVersion',M.definitionsVersion],['computedAt',c.nowIso],['timeZone',c.timeZone],['periodFrom',body.from],['periodToExclusive',body.toExclusive],
    ['currency','CHF'],['scope',c.scope],['filters',filters],['measure',body.part?`${body.measure}${body.part}`:body.measure],['lineCount',String(loaded.total.lineCount)],
    ...(loaded.total.amountCents!==null?[['totalAmountCents',String(loaded.total.amountCents)] as [string,string]]:[]),
    ...(loaded.total.durationSeconds!==null?[['totalDurationSeconds',String(loaded.total.durationSeconds)] as [string,string]]:[]),
    ['coverage',`${coverage.status}${coverage.reasons.length?`:${coverage.reasons.map(x=>x.count===undefined?x.code:`${x.code}=${x.count}`).join(',')}`:''}`],
    ['complete',String(coverage.status==='COMPLETE')],['driftFromDisplayed',String(drift!==null)],['notAnAccountingDocument','true']];
   const rows=loaded.lines.map(line=>[M.textCell(line.kind),M.textCell(line.id),M.textCell(line.eventLocal),M.textCell(line.status),M.textCell(line.instructorMembershipId),
    M.textCell(line.instructorLabel),M.textCell(line.categoryCode),M.textCell(line.productKey),M.numberCell(line.quantity),M.numberCell(line.durationSeconds),
    M.numberCell(line.amountCents),line.amountCents===null?'':'CHF']);
   return {text:M.csvDocument(meta,rows),drift:drift!==null};
  });
  reply.header('Content-Disposition',`attachment; filename="drivy-${body.measure}${body.part??''}-${body.from}_${body.toExclusive}.csv"`);
  if(csv.drift)reply.header('X-Metrics-Drift','true');
  return reply.type('text/csv; charset=utf-8').send(csv.text);
 });
}
