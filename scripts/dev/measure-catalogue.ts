import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {dirname,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import type {Pool,PoolClient,QueryConfig,QueryResult} from 'pg';
import {fixtureIds as ids} from '../../apps/api/scripts/fixtures.js';
import {freshDatabase,harness} from '../../apps/api/test/support/harness.js';

const sizes=[1,10,50,100] as const;
const warmups=5;
const samples=30;
const competenciesPerCurriculum=20;
const normalizedSource='Anticipation et partage de la route';
const normalizedLabel='Anticipation';

type Size=typeof sizes[number];
type Counters={total:number;children:number;roleSelections:number};
type Measurement={limit:Size;medianMs:number;p95Ms:number;minimumMs:number;maximumMs:number;medianSql:number;medianChildSql:number;responseBytes:number;itemsHash:string};
type CheckResults={pagination:boolean;curriculumOrder:boolean;competencyOrder:boolean;rls:boolean;labelNormalization:boolean;roleDrivyApp:boolean};
type Run={phase:string;createdAt:string;node:string;fixture:{curricula:number;competenciesPerCurriculum:number};warmups:number;samples:number;checks:CheckResults & {emptyPage:boolean};measurements:Measurement[]};
type Output={schemaVersion:1;runs:Run[];comparison?:{baselinePhase:string;afterPhase:string;measurements:Array<{limit:Size;medianMsDelta:number;p95MsDelta:number;medianChildSqlDelta:number}>}};

type CatalogueCompetency={id:string;curriculumVersionId:string;label:string;sortOrder:number};
type CatalogueItem={id:string;competencies:CatalogueCompetency[]};
type CataloguePage={data:{items:CatalogueItem[];nextCursor:string|null}};

function assert(condition:unknown,code:string):asserts condition {if(!condition)throw new Error(code);}
function fixed(value:number,digits=3){return Number(value.toFixed(digits));}
function quantile(values:number[],ratio:number){const ordered=[...values].sort((a,b)=>a-b);return ordered[Math.min(ordered.length-1,Math.floor((ordered.length-1)*ratio))]!;}
function median(values:number[]){return quantile(values,0.5);}
function uuid(prefix:string,value:number){return `${prefix}-0000-4000-8000-${value.toString().padStart(12,'0')}`;}
function queryText(value:unknown){if(typeof value==='string')return value;if(value&&typeof value==='object'&&'text' in value&&typeof (value as QueryConfig).text==='string')return (value as QueryConfig).text;return '';}
function isChildQuery(sql:string){return /FROM\s+drivy\.competency_definition\b/i.test(sql);}
function isRoleSelection(sql:string){return /^\s*SET\s+LOCAL\s+ROLE\s+drivy_app\s*$/i.test(sql);}

export function validateMeasurementDatabase(raw:string|undefined):URL {
 assert(raw,'MEASURE_DATABASE_URL_REQUIRED');
 const url=new URL(raw);
 assert(['localhost','127.0.0.1','[::1]','::1'].includes(url.hostname),'MEASURE_DATABASE_NOT_LOOPBACK');
 assert(url.pathname==='/drivy_test','MEASURE_DATABASE_NOT_DRIVY_TEST');
 return url;
}

function instrument(pool:Pool){
 let active:Counters|null=null;
 const wrapped=new WeakSet<PoolClient>();
 pool.on('acquire',(client:PoolClient)=>{
  if(!wrapped.has(client)){
   wrapped.add(client);
   const originalQuery=client.query.bind(client) as PoolClient['query'];
   client.query=((...args:unknown[])=>{
    const sql=queryText(args[0]);
    if(active){active.total++;if(isChildQuery(sql))active.children++;if(isRoleSelection(sql))active.roleSelections++;}
    return (originalQuery as (...queryArgs:unknown[])=>Promise<QueryResult>)(...args);
   }) as PoolClient['query'];
  }
 });
 return {
  start(){active={total:0,children:0,roleSelections:0};},
  stop(){const result=active;active=null;assert(result,'MEASURE_COUNTER_NOT_STARTED');return result;}
 };
}

async function seed(pool:Pool){
 const curriculumIds=Array.from({length:100},(_,index)=>uuid('81000000',index+1));
 const policyId=uuid('84000000',1);
 await pool.query(`INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at,created_at)
  VALUES($1,$2,'MEASURE',1,'Mesure synthétique','Mesure synthétique','{}',true,'Mesure synthétique',$3,now(),'2026-01-01T00:00:00Z')`,[policyId,ids.schoolA,ids.adminMember]);
 for(let offset=0;offset<100;offset+=20){
  const batch=curriculumIds.slice(offset,offset+20);
  await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at,created_at)
   SELECT id,$1,'MEASURE',revision,true,'Mesure synthétique',$2,now(),timestamptz '2026-01-01 00:00:00+00'+revision*interval '1 millisecond'
   FROM unnest($3::uuid[]) WITH ORDINALITY AS x(id,ordinality)
   CROSS JOIN LATERAL (SELECT $4::int+x.ordinality::int AS revision) r`,[ids.schoolA,ids.adminMember,batch,offset]);
  const competencyIds:string[]=[];const parents:string[]=[];const keys:string[]=[];const labels:string[]=[];const orders:number[]=[];
  for(let curriculumIndex=offset;curriculumIndex<offset+batch.length;curriculumIndex++)for(let competencyIndex=0;competencyIndex<competenciesPerCurriculum;competencyIndex++){
   const sequence=curriculumIndex*competenciesPerCurriculum+competencyIndex+1;
   competencyIds.push(uuid('82000000',sequence));parents.push(curriculumIds[curriculumIndex]!);keys.push(`measure-${competencyIndex.toString().padStart(2,'0')}`);
   labels.push(sequence===1?normalizedSource:`Compétence ${competencyIndex.toString().padStart(2,'0')}`);orders.push(Math.floor(competencyIndex/2));
  }
  await pool.query(`INSERT INTO drivy.competency_definition(id,school_id,curriculum_version_id,stable_key,label,description,sort_order)
   SELECT id,$1,parent,key,label,'Mesure synthétique',sort_order FROM unnest($2::uuid[],$3::uuid[],$4::text[],$5::text[],$6::int[]) AS x(id,parent,key,label,sort_order)`,[ids.schoolA,competencyIds,parents,keys,labels,orders]);
  const offeringIds=batch.map((_,index)=>uuid('83000000',offset+index+1));
  const offeringKeys=batch.map((_,index)=>`measure-${(offset+index+1).toString().padStart(3,'0')}`);
  await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,curriculum_version_id,policy_version_id,enabled,default_duration_minutes,default_price_cents,created_at)
   SELECT id,$1,key,'MEASURE',1,curriculum,$2,true,50,9000,timestamptz '2026-01-01 00:00:00+00'+ordinality*interval '1 millisecond'
   FROM unnest($3::uuid[],$4::text[],$5::uuid[]) WITH ORDINALITY AS x(id,key,curriculum,ordinality)`,[ids.schoolA,policyId,offeringIds,offeringKeys,batch]);
 }
 await pool.query(`INSERT INTO drivy.curriculum_version(id,school_id,category_code,revision,approved,approval_reason,created_by,approved_at,created_at)
  VALUES($1,$2,'FOREIGN_MEASURE',1,true,'Mesure synthétique',$3,now(),'2026-01-01T00:00:00Z')`,[uuid('85000000',1),ids.schoolB,ids.instructorMemberB]);
 return curriculumIds;
}

function orderedCompetencies(items:CatalogueItem[]){return items.every(item=>item.competencies.every((value,index,array)=>index===0||array[index-1]!.sortOrder<value.sortOrder||(array[index-1]!.sortOrder===value.sortOrder&&array[index-1]!.id<value.id)));}
function responseBytes(body:string){return Buffer.byteLength(body,'utf8');}

async function checks(call:Awaited<ReturnType<typeof harness>>['call'],expected:string[]):Promise<Omit<CheckResults,'roleDrivyApp'>>{
 const first=await call('GET','/curricula?limit=50',undefined,null,'demo-admin');assert(first.statusCode===200,'MEASURE_PAGE_ONE_FAILED');
 const pageOne=first.json() as CataloguePage;assert(pageOne.data.nextCursor,'MEASURE_CURSOR_MISSING');
 const second=await call('GET',`/curricula?limit=50&cursor=${encodeURIComponent(pageOne.data.nextCursor)}`,undefined,null,'demo-admin');assert(second.statusCode===200,'MEASURE_PAGE_TWO_FAILED');
 const pageTwo=second.json() as CataloguePage;
 const all=[...pageOne.data.items,...pageTwo.data.items];
 const pageIds=all.map(item=>item.id);
 const pagination=pageIds.length===100&&new Set(pageIds).size===100&&pageTwo.data.nextCursor===null;
 const curriculumOrder=pageIds.every((id,index)=>id===expected[index]);
 const competencyOrder=orderedCompetencies(all);
 const labelNormalization=all[0]?.competencies[0]?.label===normalizedLabel;
 const instructor=await call('GET','/curricula?limit=100',undefined,null,'demo-instructor');
 const foreign=await call('GET','/curricula?limit=1',undefined,null,'demo-foreign');
 const rls=instructor.statusCode===200&&(instructor.json() as CataloguePage).data.items.length===100&&foreign.statusCode===403;
 assert(pagination,'MEASURE_PAGINATION_FAILED');assert(curriculumOrder,'MEASURE_CURRICULUM_ORDER_FAILED');assert(competencyOrder,'MEASURE_COMPETENCY_ORDER_FAILED');assert(labelNormalization,'MEASURE_LABEL_FAILED');assert(rls,'MEASURE_RLS_FAILED');
 return {pagination,curriculumOrder,competencyOrder,rls,labelNormalization};
}

async function measure(call:Awaited<ReturnType<typeof harness>>['call'],counter:ReturnType<typeof instrument>,limit:Size):Promise<{measurement:Measurement;roleDrivyApp:boolean}>{
 for(let index=0;index<warmups;index++){const warm=await call('GET',`/curricula?limit=${limit}`,undefined,null,'demo-admin');assert(warm.statusCode===200,'MEASURE_WARMUP_FAILED');}
 const timings:number[]=[];const totals:number[]=[];const children:number[]=[];let bytes=0;let itemsHash='';let roleDrivyApp=true;
 for(let index=0;index<samples;index++){
  counter.start();const started=performance.now();const response=await call('GET',`/curricula?limit=${limit}`,undefined,null,'demo-admin');const elapsed=performance.now()-started;const sql=counter.stop();
  assert(response.statusCode===200,'MEASURE_REQUEST_FAILED');const page=response.json() as CataloguePage;assert(page.data.items.length===limit,'MEASURE_LIMIT_FAILED');
  const hash=createHash('sha256').update(JSON.stringify(page.data.items)).digest('hex');
  assert(!itemsHash||itemsHash===hash,'MEASURE_ITEMS_UNSTABLE');itemsHash=hash;
  timings.push(elapsed);totals.push(sql.total);children.push(sql.children);bytes=responseBytes(response.body);roleDrivyApp=roleDrivyApp&&sql.roleSelections===1;
 }
 return {measurement:{limit,medianMs:fixed(median(timings)),p95Ms:fixed(quantile(timings,0.95)),minimumMs:fixed(Math.min(...timings)),maximumMs:fixed(Math.max(...timings)),medianSql:median(totals),medianChildSql:median(children),responseBytes:bytes,itemsHash},roleDrivyApp};
}

function compare(runs:Run[]):Output['comparison']|undefined{
 if(runs.length<2)return undefined;const baseline=runs[0]!,after=runs[runs.length-1]!;
 return {baselinePhase:baseline.phase,afterPhase:after.phase,measurements:sizes.map(limit=>{const before=baseline.measurements.find(value=>value.limit===limit)!;const current=after.measurements.find(value=>value.limit===limit)!;assert(before.itemsHash===current.itemsHash,'MEASURE_RESPONSE_CHANGED');return {limit,medianMsDelta:fixed(current.medianMs-before.medianMs),p95MsDelta:fixed(current.p95Ms-before.p95Ms),medianChildSqlDelta:current.medianChildSql-before.medianChildSql};})};
}

async function save(outputPath:string,run:Run){
 let previous:Output={schemaVersion:1,runs:[]};
 try{previous=JSON.parse(await readFile(outputPath,'utf8')) as Output;}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
 assert(previous.schemaVersion===1&&Array.isArray(previous.runs),'MEASURE_OUTPUT_INVALID');
 const runs=[...previous.runs.filter(value=>value.phase!==run.phase),run];const output:Output={schemaVersion:1,runs};const comparison=compare(runs);if(comparison)output.comparison=comparison;
 await mkdir(dirname(outputPath),{recursive:true});await writeFile(outputPath,`${JSON.stringify(output,null,2)}\n`,'utf8');
 return output;
}

export async function runMeasurement(){
 const database=validateMeasurementDatabase(process.env.TEST_DATABASE_URL);process.env.TEST_DATABASE_URL=database.toString();
 const outputPath=resolve(process.env.OUTPUT??'artifacts/catalogue-measurement.json');const phase=(process.env.MEASURE_PHASE??'baseline').trim();assert(phase,'MEASURE_PHASE_EMPTY');
 const pool=await freshDatabase();const counter=instrument(pool);const {app,call}=await harness(pool);
 try{
  counter.start();const empty=await call('GET','/curricula?limit=100',undefined,null,'demo-admin');const emptyQueries=counter.stop();
  assert(empty.statusCode===200&&empty.json().data.items.length===0&&empty.json().data.nextCursor===null&&emptyQueries.children===0,'MEASURE_EMPTY_FAILED');
  const expected=await seed(pool);const baseChecks=await checks(call,expected);const measurements:Measurement[]=[];let roleDrivyApp=true;
  for(const limit of sizes){const measured=await measure(call,counter,limit);measurements.push(measured.measurement);roleDrivyApp=roleDrivyApp&&measured.roleDrivyApp;}
  assert(roleDrivyApp,'MEASURE_ROLE_FAILED');
  const run:Run={phase,createdAt:new Date().toISOString(),node:process.version,fixture:{curricula:100,competenciesPerCurriculum},warmups,samples,checks:{...baseChecks,roleDrivyApp,emptyPage:true},measurements};
  const output=await save(outputPath,run);process.stdout.write(`${JSON.stringify({phase,runs:output.runs.length,comparison:Boolean(output.comparison)})}\n`);return output;
 }finally{await app.close();await pool.end();}
}

const invoked=process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href;
if(invoked)await runMeasurement();
