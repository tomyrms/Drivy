import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';

/**
 * Cours collectifs : aucun paiement en ligne, partenaire externe ni parcours documentaire dans l'API (#83 : #38 et #39).
 * Données synthétiques. Ce test couvre la surface serveur (routes, corps acceptés, champs rendus). Les écrans web et iOS ne
 * sont pas inspectés ici : leur revue reste à faire à la main.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const FORBIDDEN=/pay|paiement|price|prix|amount|invoice|facture|document|checkout|twint|stripe|card|partner|partenaire/i;
const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
function keys(value:unknown,path='$'):string[]{
 if(Array.isArray(value))return value.flatMap((item,index)=>keys(item,`${path}[${index}]`));
 if(value!==null&&typeof value==='object')return Object.entries(value).flatMap(([key,item])=>[`${path}.${key}`,...keys(item,`${path}.${key}`)]);
 return [];
}
async function published(){
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 const created=await call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours de recette',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',
  occurrences:[{startsAt:at(15,8),endsAt:at(15,11),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin');
 if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
 return res.json().data as {id:string};
}

describe('aucun paiement en ligne, partenaire ni document pour s’inscrire',()=>{
 it('les seules routes de cours qui parlent d’argent sont les règlements sur place du personnel',()=>{
  const lines=app.printRoutes({commonPrefix:false}).split('\n').map(line=>line.replace(/^[│├└─\s]+/u,'')).filter(line=>/course/i.test(line)&&/pay|checkout|invoice|stripe|twint|partner|document|online|card/i.test(line));
  expect(lines.sort()).toEqual(['/course-enrollments/:enrollmentId/payments (POST)','/course-payments/:paymentId/void (POST)']);
 });
 it('l’inscription ne demande rien d’autre qu’une opération et refuse tout champ de paiement, de document ou de partenaire',async()=>{
  const series=await published();
  for(const extra of [{paymentToken:'tok_synthetique'},{payment:{method:'CARD'}},{documents:[]},{partnerReference:'x'},{amountCents:12000}]){
   const res=await call('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID(),...extra},null,'demo-alice');
   expect(res.statusCode,JSON.stringify(extra)).toBe(400);
  }
  expect(await pool.query('SELECT 1 FROM drivy.course_enrollment WHERE series_id=$1',[series.id]).then(r=>r.rowCount)).toBe(0);
  const ok=await call('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-alice');
  expect(ok.statusCode,ok.body).toBe(201);
  // La même règle vaut pour l'inscription faite par le personnel et pour l'attente.
  expect((await call('POST',`/course-series/${series.id}/enrollments`,{operationId:randomUUID(),learnerId:id.bobLearner,paymentToken:'x'},null,'demo-admin')).statusCode).toBe(400);
  expect((await call('POST',`/course-series/${series.id}/waitlist`,{operationId:randomUUID(),paymentToken:'x'},null,'demo-bob')).statusCode).toBe(400);
 });
 it('aucune réponse de série, d’état personnel ou d’inscription n’expose de champ de paiement, de prix ou de document',async()=>{
  const series=await published();
  const enrolled=await call('POST',`/course-series/${series.id}/enroll`,{operationId:randomUUID()},null,'demo-alice');
  expect(enrolled.statusCode,enrolled.body).toBe(201);
  const responses={
   inscription:enrolled.json().data,
   serie:(await call('GET',`/course-series/${series.id}`,undefined,null,'demo-alice')).json().data,
   etatPersonnel:(await call('GET',`/course-series/${series.id}/me`,undefined,null,'demo-alice')).json().data,
   mesInscriptions:(await call('GET','/course-enrollments/me',undefined,null,'demo-alice')).json().data,
   liste:(await call('GET','/course-series',undefined,null,'demo-alice')).json().data,
   catalogue:(await call('GET','/course-catalogue',undefined,null,'demo-alice')).json().data,
   inscritsDuPersonnel:(await call('GET',`/course-series/${series.id}/enrollments`,undefined,null,'demo-admin')).json().data,
  };
  for(const [name,body] of Object.entries(responses)){
   const offending=keys(body).filter(path=>FORBIDDEN.test(path.split('.').pop()!));
   expect(offending,`${name} : champs interdits`).toEqual([]);
  }
 });
});
