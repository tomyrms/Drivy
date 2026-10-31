import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool,PoolClient} from 'pg';
import {freshDatabase,harness,id,issuer,type Call} from './support/harness.js';
import {NOW,addActor,addLearner,addLesson,createSchool,seedBulk,seedReference,type Actor,type Reference} from './support/metrics-seed.js';

/**
 * Pilotage de l'école (#373, T02 #375) : rejoue le jeu synthétique de docs/implementation/pilotage-373-indicateurs.md (section 6)
 * sur une vraie PostgreSQL, sous drivy_app, avec l'instant de calcul figé à NOW (2026-10-28T17:00:00Z, école en Europe/Zurich).
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],ref:Reference,bulk:Awaited<ReturnType<typeof seedBulk>>;
beforeAll(async()=>{
 pool=await freshDatabase();
 ({call,app}=await harness(pool,{metricsClock:()=>new Date(NOW)}));
 ref=await seedReference(pool);
 bulk=await seedBulk(pool);
},120_000);
afterAll(async()=>{await app?.close();await pool?.end();});

const October={from:'2026-10-01',toExclusive:'2026-11-01'};
const url=(school:string,path:string,params:Record<string,string|number|undefined>={})=>{
 const query=new URLSearchParams();for(const [key,value] of Object.entries(params))if(value!==undefined)query.set(key,String(value));
 const text=query.toString();return `/v1/schools/${school}/metrics${path}${text?`?${text}`:''}`;
};
const period=(from:string,to:string)=>({from,toExclusive:to});
const get=(subject:string,path:string,params:Record<string,string|number|undefined>={},school?:string)=>call('GET',url(school??ref.school.id,path,params),undefined,null,subject);
const metrics=(subject:string,domain:'activity'|'finance',params:Record<string,string|number|undefined>={},school?:string)=>get(subject,'',{domain,...October,...params},school);
const exportCsv=(subject:string,body:Record<string,unknown>,school?:string)=>call('POST',url(school??ref.school.id,'/exports'),body,null,subject);
const data=(res:{json:()=>any;statusCode:number;body:string})=>{expect(res.statusCode,res.body).toBe(200);return res.json().data;};
const values=(measures:Record<string,{value:number|null}>,ids:string[])=>Object.fromEntries(ids.map(key=>[key,measures[key]?.value]));
const problem=(res:{json:()=>any;statusCode:number})=>({status:res.statusCode,code:res.json().code});

describe('définitions et en-têtes',()=>{
 it('sert le dictionnaire versionné sans donnée d\'école, réservé au personnel',async()=>{
  const res=await get(ref.m1.subject,'/definitions');
  const body=data(res);
  expect(body.definitionsVersion).toBe('2026-10-31.1');
  expect(body.currency).toBe('CHF');
  expect(body.measures.map((m:{id:string})=>m.id)).toEqual(expect.arrayContaining(['L01','H02','P01','C09','F03','F07']));
  expect(body.limits).toEqual({maxPeriodDays:366,maxBuckets:400,maxDetailPage:100,maxExportLines:10000});
  expect(res.headers['cache-control']).toBe('no-store');
  expect(problem(await get(ref.learners.E1!.subject,'/definitions'))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
 });
 it('porte version de définition, instant de calcul, fuseau, devise et bornes civiles en instants',async()=>{
  const body=data(await metrics(ref.adm1.subject,'activity'));
  expect(body).toMatchObject({definitionsVersion:'2026-10-31.1',schoolId:ref.school.id,timeZone:'Europe/Zurich',currency:'CHF',computedAt:'2026-10-28T17:00:00.000Z',dataSince:'2026-09-01',domain:'activity'});
  // Octobre 2026 : 31 jours plus l'heure du changement d'heure.
  expect(body.period).toEqual({from:'2026-10-01',toExclusive:'2026-11-01',days:31,fromInstant:'2026-09-30T22:00:00.000Z',toInstant:'2026-10-31T23:00:00.000Z'});
  expect(body.scope).toEqual({kind:'school',filters:{instructorMembershipId:null,categoryCode:null,productKey:null}});
 });
 it('la semaine du 19/10 dure une heure de plus que sept fois 24 heures',async()=>{
  const body=data(await metrics(ref.adm1.subject,'activity',{from:'2026-10-19',toExclusive:'2026-10-26'}));
  expect(body.period).toMatchObject({fromInstant:'2026-10-18T22:00:00.000Z',toInstant:'2026-10-25T23:00:00.000Z'});
  // D1 débute le 25/10 à 23:30 local (22:30Z) : dans la semaine, malgré la septième journée de 25 heures.
  expect(body.measures.L01.value).toBe(1);
 });
});

describe('activité de l\'école, jeu de référence (section 6.4)',()=>{
 it('octobre : états, durées, élèves, cours et partition des leçons',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity'));
  expect(values(measures,['L01','L02','L03','L04','L05','L06','L07','L08'])).toEqual({L01:5,L02:3,L03:3,L04:1,L05:1,L06:1,L07:1,L08:15});
  // La partition : la somme des états égale le total de la période.
  expect(['L01','L02','L03','L04','L05','L06','L07'].reduce((sum,key)=>sum+measures[key].value,0)).toBe(measures.L08.value);
  expect(values(measures,['H01','H03'])).toEqual({H01:585*60,H03:150*60});
  // Une durée réelle manquante n'est ni zéro ni la durée prévue : 4 durées connues, 1 inconnue.
  expect(measures.H02).toMatchObject({value:218*60,coverage:{status:'PARTIAL',reasons:[{code:'DURATION_UNKNOWN',count:1}]},parts:{knownCount:4,unknownDurationCount:1}});
  expect(measures.L01.coverage).toEqual({status:'COMPLETE',reasons:[{code:'ACTUAL_START_MISSING',count:1}]});
  expect(measures.P01).toMatchObject({value:4,parts:{lessons:4,courses:2}});
  expect(values(measures,['C01','C02','C03'])).toEqual({C01:2,C02:1,C03:2});
  expect(measures.C05).toMatchObject({value:3,parts:{absent:1,excused:0}});
  expect(measures.C10).toMatchObject({value:12,parts:{cancelled:2,cancelledBySelf:1,cancelledByStaff:0,cancelledWithSeries:1}});
 });
 it('instantanés : à traiter, appels à renseigner, places',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity'));
  expect(values(measures,['A01','A03'])).toEqual({A01:1,A03:1});
  expect(measures.A02).toMatchObject({value:1,parts:{missingMarks:2}});
  expect(measures.C04).toMatchObject({value:1,parts:{missingMarks:2}});
  expect(values(measures,['C06','C07','C08'])).toEqual({C06:11,C07:1,C08:12});
  expect(measures.C08.parts).toEqual({capacity:28,free:16,overbooked:0});
  expect(measures.C11).toMatchObject({value:1,parts:{sessions:1}});
  // Aucun cours ne démarre en octobre après l'instant de calcul : pas de dénominateur, donc pas de pourcentage inventé.
  expect(measures.C09).toMatchObject({value:null,coverage:{status:'UNAVAILABLE',reasons:[{code:'NO_DENOMINATOR'}]}});
 });
 it('remplissage des cours à venir : somme des places sur somme des capacités, pas moyenne de pourcentages',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity',{from:'2026-11-01',toExclusive:'2026-12-01'}));
  expect(measures.C09).toMatchObject({value:450,parts:{numerator:9,denominator:20}});// 45 % ; la moyenne de 25 % et 75 % donnerait 50 %
  expect(values(measures,['L01','L02','C01','C02'])).toEqual({L01:0,L02:1,C01:2,C02:2});
 });
 it('un cours sur plusieurs séances compte une série ; les séances et les inscriptions ne se multiplient pas',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity'));
  expect(measures.C02.value).toBe(1);
  expect(measures.C01.value).toBe(2);
  expect(measures.C06.value).toBe(11);
  expect(JSON.stringify(measures)).not.toContain('"F');
 });
 it('septembre : mois précédent du jeu, sans cours ni correction',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity',period('2026-09-01','2026-10-01')));
  expect(values(measures,['L01','L02','L03','L04','L08','H01','P01'])).toEqual({L01:5,L02:0,L03:1,L04:1,L08:7,H01:18000,P01:3});
  expect(measures.H02).toMatchObject({value:18000,coverage:{status:'COMPLETE'},parts:{knownCount:5,unknownDurationCount:0}});
 });
 it('changement de mois : S7 en septembre, O1 en octobre (début réel le 01/10 à 00:30 local)',async()=>{
  const sept=data(await get(ref.adm1.subject,'/details',{measure:'L01',...period('2026-09-01','2026-10-01'),limit:100}));
  const oct=data(await get(ref.adm1.subject,'/details',{measure:'L01',...October,limit:100}));
  expect(sept.lines.map((l:{id:string})=>l.id).sort()).toEqual(['S1','S2','S3','S6','S7'].map(k=>ref.lessons[k]).sort());
  expect(oct.lines.map((l:{id:string})=>l.id).sort()).toEqual(['O1','O2','O3','O5','D1'].map(k=>ref.lessons[k]).sort());
 });
 it('août précède les données : inconnu, jamais zéro',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity',period('2026-08-01','2026-09-01')));
  expect(measures.L01).toMatchObject({value:null,coverage:{status:'UNAVAILABLE',reasons:[{code:'BEFORE_DATA_START'}]}});
  expect(measures.H02).toMatchObject({value:null});
 });
 it('une année qui commence avant les données est partielle, pas fausse',async()=>{
  const {measures}=data(await metrics(ref.adm1.subject,'activity',period('2026-01-01','2027-01-01')));
  expect(measures.L01).toMatchObject({value:10,coverage:{status:'PARTIAL'}});
  expect(measures.L01.coverage.reasons).toEqual(expect.arrayContaining([{code:'STARTS_BEFORE_DATA_START'}]));
 });
 it('répartitions : chaque colonne se somme au total d\'octobre',async()=>{
  const total=data(await metrics(ref.adm1.subject,'activity')).measures;
  for(const by of ['instructor','category','product'] as const){
   const {breakdown}=data(await metrics(ref.adm1.subject,'activity',{breakdown:by}));
   expect(breakdown.by).toBe(by);
   for(const key of ['L01','L02','L03','L04','L05','L06','L07'])
    expect(breakdown.groups.reduce((sum:number,g:{measures:Record<string,{value:number}>})=>sum+g.measures[key]!.value,0),`${by}/${key}`).toBe(total[key].value);
  }
  const byInstructor=data(await metrics(ref.adm1.subject,'activity',{breakdown:'instructor'})).breakdown.groups;
  const g=(member:Actor)=>byInstructor.find((x:{key:string})=>x.key===member.membershipId);
  expect(values(g(ref.m1).measures,['L01','L02','L03','L06','L07'])).toEqual({L01:4,L02:2,L03:2,L06:1,L07:1});
  expect(g(ref.m1).measures.H02).toMatchObject({value:218*60,coverage:{status:'COMPLETE'}});
  expect(values(g(ref.m2).measures,['L01','L02','L03','L04','L05'])).toEqual({L01:1,L02:1,L03:1,L04:1,L05:1});
  // M2 n'a qu'une leçon réalisée, sans durée : tout est exclu, donc inconnu et non zéro.
  expect(g(ref.m2).measures.H02).toMatchObject({value:null,coverage:{status:'UNAVAILABLE',reasons:[{code:'DURATION_UNKNOWN'}]}});
  expect(g(ref.m1).label).toBe('Acteur m1-ref');
  const byCategory=data(await metrics(ref.adm1.subject,'activity',{breakdown:'category'})).breakdown.groups;
  expect(Object.fromEntries(byCategory.map((x:{key:string;measures:{L01:{value:number}}})=>[x.key,x.measures.L01.value]))).toEqual({A:1,B:4});
  const byProduct=data(await metrics(ref.adm1.subject,'activity',{breakdown:'product'})).breakdown.groups;
  expect(Object.fromEntries(byProduct.map((x:{key:string;measures:{L01:{value:number}}})=>[x.key,x.measures.L01.value]))).toEqual({'a-60':1,'b-45':4});
 });
 it('filtres moniteur, permis et prestation',async()=>{
  expect(data(await metrics(ref.adm1.subject,'activity',{instructorMembershipId:ref.m1.membershipId})).measures.L01.value).toBe(4);
  expect(data(await metrics(ref.adm1.subject,'activity',{categoryCode:'A'})).measures.L01.value).toBe(1);
  expect(data(await metrics(ref.adm1.subject,'activity',{productKey:'b-45'})).measures.L01.value).toBe(4);
  const course=data(await metrics(ref.adm1.subject,'activity',{categoryCode:'A'})).measures;
  // Un cours n'a ni permis ni prestation : le filtre le rend sans objet, il n'est pas ignoré.
  expect(course.C01).toMatchObject({value:null,coverage:{status:'NOT_APPLICABLE'}});
 });
});

describe('comparaisons (règle K9)',()=>{
 it('mois à date contre la même plage du mois précédent, pas contre le mois complet',async()=>{
  const body=data(await metrics(ref.adm1.subject,'activity',{from:'2026-10-01',toExclusive:'2026-10-29',compare:'previous-month'}));
  expect(body.comparison.mode).toBe('MONTH_TO_DATE');
  expect(body.comparison.base).toEqual({from:'2026-09-01',toExclusive:'2026-09-29',days:28,clipped:false});
  expect(body.comparison.measures.L01).toEqual({current:5,base:3,delta:2,percentTenths:667,percentReason:null});
  // H02 courant est partiel (une durée inconnue) : aucun pourcentage.
  expect(body.comparison.measures.H02).toMatchObject({delta:null,percentTenths:null,percentReason:'PARTIAL_COVERAGE'});
  const money=data(await metrics(ref.adm1.subject,'finance',{from:'2026-10-01',toExclusive:'2026-10-29',compare:'previous-month'}));
  expect(money.comparison.measures.F01).toEqual({current:57000,base:38000,delta:19000,percentTenths:500,percentReason:null});
 });
 it('mois complet contre mois complet : longueurs différentes, écart négatif',async()=>{
  const body=data(await metrics(ref.adm1.subject,'finance',{compare:'previous-month'}));
  expect(body.comparison).toMatchObject({mode:'FULL_MONTH',base:{from:'2026-09-01',toExclusive:'2026-10-01',days:30}});
  expect(body.comparison.measures.F01).toEqual({current:57000,base:58000,delta:-1000,percentTenths:-17,percentReason:null});
  const activity=data(await metrics(ref.adm1.subject,'activity',{compare:'previous-month'}));
  expect(activity.comparison.measures.L01).toEqual({current:5,base:5,delta:0,percentTenths:0,percentReason:null});
 });
 it('mois précédent vide : pas de pourcentage, base inconnue',async()=>{
  const body=data(await metrics(ref.adm1.subject,'activity',{...period('2026-09-01','2026-10-01'),compare:'previous-month'}));
  expect(body.comparison.mode).toBe('FULL_MONTH');
  expect(body.comparison.measures.L01).toEqual({current:5,base:null,delta:null,percentTenths:null,percentReason:'BASE_BEFORE_DATA_START'});
 });
 it('base connue et nulle : écart absolu sans pourcentage',async()=>{
  const body=data(await metrics(ref.adm1.subject,'activity',{...period('2026-10-12','2026-10-19'),instructorMembershipId:ref.m2.membershipId,compare:'equivalent-period'}));
  expect(body.comparison).toMatchObject({mode:'EQUIVALENT_PERIOD',base:{from:'2026-10-05',toExclusive:'2026-10-12',days:7}});
  expect(body.comparison.measures.L01).toEqual({current:1,base:0,delta:1,percentTenths:null,percentReason:'BASE_ZERO'});
 });
 it('refuse une comparaison « mois précédent » qui n\'en est pas une',async()=>{
  expect(problem(await metrics(ref.adm1.subject,'activity',{from:'2026-10-05',toExclusive:'2026-10-20',compare:'previous-month'}))).toEqual({status:422,code:'INVALID_PERIOD'});
 });
});

describe('valeurs convenues et règlements de cours (finances)',()=>{
 it('octobre : réalisé, à venir, total attendu, en attente, règlements, corrections',async()=>{
  const body=data(await metrics(ref.adm1.subject,'finance'));
  const m=body.measures;
  expect(values(m,['F01','F02','F03','F04','F05'])).toEqual({F01:57000,F02:31000,F03:88000,F04:31000,F05:51000});
  expect(m.F05.parts).toEqual({entries:7});
  expect(m.F06).toMatchObject({value:12000,parts:{voidedEntries:1,laterCorrections:1,laterCorrectionsCents:12000}});
  expect(m.F07).toMatchObject({value:null,coverage:{status:'UNAVAILABLE',reasons:[{code:'COURSE_PRICE_SOURCE_MISSING'}]}});
  expect(body.coverageNotes).toEqual({lessons:'INDIVIDUAL_UNIT_PRICE_ONLY',payments:'COURSE_ON_SITE_ENTRIES_ONLY',paymentDate:'ENTRY_DATE'});
  expect(body.currency).toBe('CHF');
  // Jamais « prestations + règlements » : aucun champ ne porte 88 000 + 51 000.
  expect(JSON.stringify(body)).not.toContain('139000');
 });
 it('prix révisé et tarif historique : le snapshot fait foi, pas le tarif courant',async()=>{
  const lines=data(await get(ref.adm1.subject,'/details',{measure:'F01',...October,limit:100})).lines;
  const amount=(key:string)=>lines.find((l:{id:string})=>l.id===ref.lessons[key])?.amountCents;
  expect(amount('O3')).toBe(17000);// révisé de 18 000 à 17 000
  expect(amount('O2')).toBe(9000);// réservé avant la version 2 à 10 000
  expect(amount('O1')).toBe(10000);
 });
 it('septembre : règlement d\'octobre exclu, saisie annulée en octobre expliquée',async()=>{
  const m=data(await metrics(ref.adm1.subject,'finance',period('2026-09-01','2026-10-01'))).measures;
  expect(values(m,['F01','F02','F03','F04','F05'])).toEqual({F01:58000,F02:0,F03:58000,F04:0,F05:3000});
  expect(m.F06).toMatchObject({value:12000,parts:{voidedEntries:1,laterCorrections:0}});
 });
 it('un montant exclu rend la mesure partielle ou inconnue, jamais zéro',async()=>{
  const micro=await createSchool(pool,'micro');
  const instructor=await addActor(pool,micro,'m-micro',['INSTRUCTOR']),learner=await addLearner(pool,micro,'M1','B');
  const base={instructor,learner,product:'b45v2' as const,status:'COMPLETED' as const,price:10000};
  await addLesson(pool,micro,{...base,plannedStart:'2026-10-05T08:00:00Z',plannedEnd:'2026-10-05T08:45:00Z',actualStart:'2026-10-05T08:00:00Z',actualEnd:'2026-10-05T08:45:00Z'});
  await addLesson(pool,micro,{...base,plannedStart:'2026-10-06T08:00:00Z',plannedEnd:'2026-10-06T08:45:00Z',actualStart:'2026-10-06T08:00:00Z',actualEnd:'2026-10-06T08:45:00Z',charge:9000});
  const partial=data(await metrics(micro.admin.subject,'finance',{},micro.id)).measures;
  expect(partial.F01).toMatchObject({value:10000,coverage:{status:'PARTIAL',reasons:[{code:'CHARGE_MISMATCH',count:1}]},lineCount:1});
  const pack=await createSchool(pool,'pack'),packInstructor=await addActor(pool,pack,'m-pack',['INSTRUCTOR']),packLearner=await addLearner(pool,pack,'P1','B');
  await addLesson(pool,pack,{instructor:packInstructor,learner:packLearner,product:'b45v2',status:'COMPLETED',price:10000,mode:'ENTITLEMENT',
   plannedStart:'2026-10-05T08:00:00Z',plannedEnd:'2026-10-05T08:45:00Z',actualStart:'2026-10-05T08:00:00Z',actualEnd:'2026-10-05T08:45:00Z'});
  const entitlement=data(await metrics(pack.admin.subject,'finance',{},pack.id)).measures;
  expect(entitlement.F01).toMatchObject({value:null,coverage:{status:'UNAVAILABLE',reasons:[{code:'ENTITLEMENT_NOT_VALUED',count:1}]}});
  expect(data(await metrics(pack.admin.subject,'activity',{},pack.id)).measures.L01.value).toBe(1);
  const free=await createSchool(pool,'free'),freeInstructor=await addActor(pool,free,'m-free',['INSTRUCTOR']),freeLearner=await addLearner(pool,free,'F1','B');
  await addLesson(pool,free,{instructor:freeInstructor,learner:freeLearner,product:'b45v2',status:'COMPLETED',price:0,
   plannedStart:'2026-10-05T08:00:00Z',plannedEnd:'2026-10-05T08:45:00Z',actualStart:'2026-10-05T08:00:00Z',actualEnd:'2026-10-05T08:45:00Z'});
  expect(data(await metrics(free.admin.subject,'finance',{},free.id)).measures.F01).toMatchObject({value:0,coverage:{status:'COMPLETE'}});
 });
 it('une leçon corrigée en annulée ne vaut plus rien et se rattache à sa date prévue',async()=>{
  const lines=data(await get(ref.adm1.subject,'/details',{measure:'L03',...October,limit:100})).lines.map((l:{id:string})=>l.id);
  expect(lines).toContain(ref.lessons.O6);
  const realised=data(await get(ref.adm1.subject,'/details',{measure:'F01',...October,limit:100})).lines.map((l:{id:string})=>l.id);
  expect(realised).not.toContain(ref.lessons.O6);
 });
 it('un filtre moniteur ne s\'applique pas aux règlements de cours : sans objet dans les cartes, refusé ailleurs',async()=>{
  const m=data(await metrics(ref.adm1.subject,'finance',{instructorMembershipId:ref.m1.membershipId})).measures;
  expect(values(m,['F01','F02'])).toEqual({F01:46000,F02:20000});
  expect(m.F05).toMatchObject({value:null,coverage:{status:'NOT_APPLICABLE'}});
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'F05',...October,instructorMembershipId:ref.m1.membershipId}))).toEqual({status:400,code:'METRIC_FILTER_UNSUPPORTED'});
 });
});

describe('séries, détails et pages : total, série, détail et export concordent',()=>{
 it('semaines d\'octobre : intervalles partiels aux extrémités, somme égale au total',async()=>{
  const body=data(await get(ref.adm1.subject,'/series',{...October,granularity:'week',measures:'L01,L02'}));
  expect(body.buckets.map((b:{from:string;toExclusive:string;partial:boolean})=>[b.from,b.toExclusive,b.partial])).toEqual([
   ['2026-10-01','2026-10-05',true],['2026-10-05','2026-10-12',false],['2026-10-12','2026-10-19',false],['2026-10-19','2026-10-26',false],['2026-10-26','2026-11-01',true]]);
  expect(body.buckets.map((b:{measures:{L01:{value:number}}})=>b.measures.L01.value)).toEqual([1,1,2,1,0]);
  expect(body.buckets.map((b:{measures:{L02:{value:number}}})=>b.measures.L02.value)).toEqual([0,0,0,0,3]);
 });
 it('valeurs et règlements par semaine : la somme égale la carte',async()=>{
  const body=data(await get(ref.adm1.subject,'/series',{...October,granularity:'week',measures:'F01,F05'}));
  const column=(key:string)=>body.buckets.map((b:{measures:Record<string,{value:number}>})=>b.measures[key]!.value);
  expect(column('F01')).toEqual([10000,9000,28000,10000,0]);
  expect(column('F05')).toEqual([3000,12000,30000,6000,0]);
  expect(column('F01').reduce((a:number,b:number)=>a+b,0)).toBe(57000);
  expect(column('F05').reduce((a:number,b:number)=>a+b,0)).toBe(51000);
 });
 it('mois d\'une année : intervalles antérieurs aux données inconnus',async()=>{
  const body=data(await get(ref.adm1.subject,'/series',{...period('2026-01-01','2027-01-01'),granularity:'month',measures:'L01'}));
  const column=body.buckets.map((b:{measures:{L01:{value:number|null}}})=>b.measures.L01.value);
  expect(column).toEqual([null,null,null,null,null,null,null,null,5,5,0,0]);
  expect(body.buckets[0].measures.L01.coverage).toEqual({status:'UNAVAILABLE',reasons:[{code:'BEFORE_DATA_START'}]});
 });
 it('jours : un intervalle par jour civil, trois jours sur le changement d\'heure',async()=>{
  const body=data(await get(ref.adm1.subject,'/series',{...period('2026-10-24','2026-10-27'),granularity:'day',measures:'L01,H02'}));
  expect(body.buckets.map((b:{from:string})=>b.from)).toEqual(['2026-10-24','2026-10-25','2026-10-26']);
  expect(body.buckets.map((b:{measures:{L01:{value:number}}})=>b.measures.L01.value)).toEqual([0,1,0]);
  expect(body.buckets[1].measures.H02.value).toBe(45*60);
 });
 it('détail paginé sur plus d\'une page : total constant, somme de page distincte de la somme totale',async()=>{
  const pages:any[]=[];let cursor:string|undefined;
  do{
   const page=data(await get(ref.adm1.subject,'/details',{measure:'F01',...October,limit:2,cursor}));
   pages.push(page);cursor=page.page.nextCursor??undefined;
  }while(cursor);
  expect(pages.map(p=>p.lines.length)).toEqual([2,2,1]);
  expect(pages.every(p=>p.total.lineCount===5&&p.total.amountCents===57000)).toBe(true);
  expect(pages.map(p=>p.pageSum.amountCents)).toEqual([19000,28000,10000]);
  expect(pages.flatMap(p=>p.lines).map((l:{id:string})=>l.id)).toEqual(['O1','O2','O3','O5','D1'].map(k=>ref.lessons[k]));
  const carte=data(await metrics(ref.adm1.subject,'finance')).measures.F01;
  expect(carte.lineCount).toBe(5);
  expect(pages[0].lines[0]).toMatchObject({kind:'LESSON',status:'COMPLETED',categoryCode:'B',productKey:'b-45',quantity:1,durationSeconds:45*60,amountCents:10000});
 });
 it('un changement entre la carte et le détail est signalé, pas masqué',async()=>{
  const same=data(await get(ref.adm1.subject,'/details',{measure:'F01',...October,expectedLineCount:5,expectedAmountCents:57000}));
  expect(same.drift).toBeNull();
  const changed=data(await get(ref.adm1.subject,'/details',{measure:'F01',...October,expectedLineCount:4,expectedAmountCents:47000}));
  expect(changed.drift).toEqual({lineCount:{expected:4,actual:5},amountCents:{expected:47000,actual:57000}});
 });
 it('curseur lié à la mesure, aux filtres et à la taille de page',async()=>{
  const first=data(await get(ref.adm1.subject,'/details',{measure:'L01',...October,limit:2}));
  const cursor=first.page.nextCursor as string;
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'L01',...October,limit:3,cursor}))).toEqual({status:400,code:'INVALID_CURSOR'});
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'L02',...October,limit:2,cursor}))).toEqual({status:400,code:'INVALID_CURSOR'});
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'L01',...October,limit:2,cursor:'AAAA'}))).toEqual({status:400,code:'INVALID_CURSOR'});
 });
 it('détails des séances de cours et de leurs appels manquants',async()=>{
  const sessions=data(await get(ref.adm1.subject,'/details',{measure:'C01',...October}));
  expect(sessions.total.lineCount).toBe(2);
  const missing=data(await get(ref.adm1.subject,'/details',{measure:'C04',...October}));
  expect(missing.total.lineCount).toBe(1);
  expect(missing.lines[0]).toMatchObject({kind:'COURSE_OCCURRENCE',status:'TO_MARK',markedCount:1,missingMarks:2});
 });
 it('détail des règlements : saisies actives, annulées et corrections postérieures',async()=>{
  const active=data(await get(ref.adm1.subject,'/details',{measure:'F05',...October,limit:100}));
  expect(active.total).toEqual({lineCount:7,amountCents:51000,durationSeconds:null});
  const voided=data(await get(ref.adm1.subject,'/details',{measure:'F06',part:'a',...October}));
  expect(voided.total).toMatchObject({lineCount:1,amountCents:12000});
  const later=data(await get(ref.adm1.subject,'/details',{measure:'F06',part:'b',...October}));
  expect(later.total).toMatchObject({lineCount:1,amountCents:12000});
  expect(later.lines[0]).toMatchObject({kind:'COURSE_PAYMENT',status:'VOIDED'});
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'F06',...October}))).toEqual({status:400,code:'INVALID_REQUEST'});
  expect(problem(await get(ref.adm1.subject,'/details',{measure:'P01',...October}))).toEqual({status:400,code:'METRIC_DETAIL_UNSUPPORTED'});
 });
});

describe('jeu B : 8 000 + 2 000 = 10 000 CHF, un règlement de 500 CHF n\'y change rien',()=>{
 it('totaux, séries et pages concordent au-delà d\'une page',async()=>{
  const m=data(await metrics(bulk.admin.subject,'finance',{},bulk.school.id)).measures;
  expect(values(m,['F01','F02','F03','F05'])).toEqual({F01:800000,F02:200000,F03:1000000,F05:50000});
  expect(JSON.stringify(m)).not.toContain('1050000');
  expect(values(data(await metrics(bulk.admin.subject,'activity',{},bulk.school.id)).measures,['L01','L02'])).toEqual({L01:80,L02:20});
  const pages:any[]=[];let cursor:string|undefined;
  do{
   const page=data(await get(bulk.admin.subject,'/details',{measure:'F01',...October,limit:25,cursor},bulk.school.id));
   pages.push(page);cursor=page.page.nextCursor??undefined;
  }while(cursor);
  expect(pages.map(p=>p.lines.length)).toEqual([25,25,25,5]);
  expect(pages.reduce((sum,p)=>sum+p.pageSum.amountCents,0)).toBe(800000);
  expect(new Set(pages.flatMap(p=>p.lines.map((l:{id:string})=>l.id))).size).toBe(80);
  const series=data(await get(bulk.admin.subject,'/series',{...October,granularity:'day',measures:'F01,F02'},bulk.school.id));
  const sum=(key:string)=>series.buckets.reduce((s:number,b:{measures:Record<string,{value:number}>})=>s+b.measures[key]!.value,0);
  expect([sum('F01'),sum('F02')]).toEqual([800000,200000]);
 });
 it('l\'export contient exactement les lignes de la carte',async()=>{
  const res=await exportCsv(bulk.admin.subject,{measure:'F01',...October},bulk.school.id);
  expect(res.statusCode).toBe(403);// ADMIN sans EXPORT_MANAGEMENT (D2)
  const exporter=await addActor(pool,bulk.school,'exp-bulk',['ADMIN'],['EXPORT_MANAGEMENT']);
  const ok=await exportCsv(exporter.subject,{measure:'F01',...October,expectedLineCount:80,expectedAmountCents:800000},bulk.school.id);
  expect(ok.statusCode,ok.body).toBe(200);
  const lines=ok.body.split('\r\n'),header=lines.indexOf('line_kind;line_id;event_at;status;instructor_id;instructor_name;category_code;product_key;quantity;duration_seconds;amount_cents;currency');
  const rows=lines.slice(header+1).filter(Boolean);
  expect(rows).toHaveLength(80);
  expect(rows.reduce((sum,row)=>sum+Number(row.split(';')[10]),0)).toBe(800000);
  expect(ok.body).toContain('#lineCount;80\r\n');
  expect(ok.body).toContain('#totalAmountCents;800000\r\n');
  expect(ok.body).toContain('#complete;true\r\n');
  expect(ok.body).toContain('#driftFromDisplayed;false\r\n');
 });
});

describe('droits : refus côté serveur, avant tout calcul, sans montant interdit',()=>{
 it('moniteur sans grant : sa propre activité seulement, jamais de montant',async()=>{
  const body=data(await metrics(ref.m1.subject,'activity'));
  expect(body.scope.kind).toBe('self');
  expect(values(body.measures,['L01','L02','L03','L04','L05','L06','L07'])).toEqual({L01:4,L02:2,L03:2,L04:0,L05:0,L06:1,L07:1});
  expect(body.measures.H02.value).toBe(218*60);
  expect(body.measures.P01).toMatchObject({value:3});// E5, E1, E2 : ses leçons et les présences à ses séances
  expect(Object.keys(body.measures).some(key=>key.startsWith('F'))).toBe(false);
  expect(problem(await metrics(ref.m1.subject,'finance'))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect(problem(await metrics(ref.m1.subject,'activity',{scope:'school'}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect(problem(await metrics(ref.m1.subject,'activity',{instructorMembershipId:ref.m2.membershipId}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect(problem(await get(ref.m1.subject,'/details',{measure:'F01',...October}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect(problem(await get(ref.m1.subject,'/series',{...October,granularity:'week',measures:'F01'}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  // Même propre à lui, une comparaison ou une répartition ne divulgue pas l'école.
  const compared=data(await metrics(ref.m1.subject,'activity',{compare:'previous-month',breakdown:'instructor'}));
  expect(compared.breakdown.groups.map((g:{key:string})=>g.key)).toEqual([ref.m1.membershipId]);
  expect(compared.comparison.measures.L01.current).toBe(4);
 });
 it('moniteur sans grant : le détail est limité à ses leçons',async()=>{
  const lines=data(await get(ref.m1.subject,'/details',{measure:'L08',...October,limit:100}));
  expect(lines.total.lineCount).toBe(10);
  expect(lines.lines.every((l:{instructorMembershipId:string})=>l.instructorMembershipId===ref.m1.membershipId)).toBe(true);
 });
 it('VIEW_SCHOOL_METRICS : activité de l\'école, aucune clé financière',async()=>{
  const body=data(await metrics(ref.m2.subject,'activity'));
  expect(body.scope.kind).toBe('school');
  expect(values(body.measures,['L01','L02','L03','L04','L05','L06','L07'])).toEqual({L01:5,L02:3,L03:3,L04:1,L05:1,L06:1,L07:1});
  expect(Object.keys(body.measures).some(key=>key.startsWith('F'))).toBe(false);
  expect(problem(await metrics(ref.m2.subject,'finance'))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  // Le nom d'un élève n'est donné que là où la lecture est déjà permise : M2 n'est pas affecté à toutes les formations.
  const lines=data(await get(ref.m2.subject,'/details',{measure:'L01',...October,limit:100})).lines;
  expect(lines).toHaveLength(5);
  expect(lines.filter((l:{learnerLabel:string|null})=>l.learnerLabel===null).length).toBeGreaterThan(0);
 });
 it('VIEW_FINANCIAL_METRICS : finances de l\'école, filtre moniteur, aucune activité de l\'école',async()=>{
  const body=data(await metrics(ref.m3.subject,'finance'));
  expect(values(body.measures,['F01','F02','F03','F04','F05'])).toEqual({F01:57000,F02:31000,F03:88000,F04:31000,F05:51000});
  expect(Object.keys(body.measures).every(key=>key.startsWith('F'))).toBe(true);
  expect(problem(await metrics(ref.m3.subject,'activity',{scope:'school'}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  const own=data(await metrics(ref.m3.subject,'activity'));
  expect(own.scope.kind).toBe('self');
  expect(own.measures.L01.value).toBe(0);// M3 n'a aucune leçon : zéro connu, pas l'école
  const filtered=data(await metrics(ref.m3.subject,'finance',{instructorMembershipId:ref.m1.membershipId}));
  expect(values(filtered.measures,['F01','F02'])).toEqual({F01:46000,F02:20000});
  const detail=data(await get(ref.m3.subject,'/details',{measure:'F01',...October,limit:100}));
  expect(detail.total.amountCents).toBe(57000);
  expect(detail.lines.every((l:{amountCents:number|null})=>typeof l.amountCents==='number')).toBe(true);
 });
 it('élève, autre école et personne sans appartenance : refusés',async()=>{
  const learner=ref.learners.E1!.subject;
  const asked:[string,Record<string,string>][]=[['',{domain:'activity',...October}],['/series',{...October,granularity:'week',measures:'L01'}],['/details',{...October,measure:'L01'}],['/definitions',{}]];
  for(const [path,params] of asked)expect((await get(learner,path,params)).statusCode,path).toBe(403);
  expect(problem(await metrics(learner,'finance'))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect((await metrics(ref.adm1.subject,'activity',{},bulk.school.id)).statusCode).toBe(403);
  expect((await metrics(bulk.admin.subject,'finance',{},ref.school.id)).statusCode).toBe(403);
  expect((await get(ref.m1.subject,'/details',{measure:'L01',...October},bulk.school.id)).statusCode).toBe(403);
  expect((await exportCsv(ref.adm2.subject,{measure:'L01',...October},bulk.school.id)).statusCode).toBe(403);
  const anonymous=await app.inject({method:'GET',url:url(ref.school.id,'',{domain:'activity',...October})});
  expect(anonymous.statusCode).toBe(401);
 });
 it('une personne membre de deux écoles reçoit les totaux de chaque école, sans mélange',async()=>{
  await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,'{INSTRUCTOR}')",[randomUUID(),bulk.school.id,ref.m1.personId]);
  expect(data(await metrics(ref.m1.subject,'activity')).measures.L01.value).toBe(4);
  expect(data(await metrics(ref.m1.subject,'activity',{},bulk.school.id)).measures.L01.value).toBe(0);
 });
 it('école en préparation : rien à compter',async()=>{
  const draft=await createSchool(pool,'draft',{status:'DRAFT'});
  expect(problem(await metrics(draft.admin.subject,'activity',{},draft.id))).toEqual({status:409,code:'SCHOOL_NOT_ACTIVE'});
 });
 it('école sans donnée : zéros connus, aucune base de comparaison',async()=>{
  const empty=await createSchool(pool,'empty');
  const body=data(await metrics(empty.admin.subject,'activity',{compare:'previous-month'},empty.id));
  expect(body.dataSince).toBeNull();
  expect(body.measures.L01).toMatchObject({value:0,coverage:{status:'COMPLETE'}});
  expect(body.comparison.measures.L01).toMatchObject({percentTenths:null,percentReason:'BASE_ZERO'});
 });
});

describe('export CSV (D8)',()=>{
 it('exige EXPORT_MANAGEMENT et le droit de la mesure, à chaque demande',async()=>{
  const body={measure:'F01',...October};
  expect(problem(await exportCsv(ref.adm1.subject,body))).toEqual({status:403,code:'ACCESS_REVOKED'});// ADMIN sans le grant d'export
  expect(problem(await exportCsv(ref.m3.subject,body))).toEqual({status:403,code:'ACCESS_REVOKED'});// finance sans export
  expect(problem(await exportCsv(ref.m4.subject,body))).toEqual({status:403,code:'ACCESS_REVOKED'});// export sans finance
  expect(problem(await exportCsv(ref.learners.E1!.subject,{measure:'L01',...October}))).toEqual({status:403,code:'ACCESS_REVOKED'});
  const ok=await exportCsv(ref.adm2.subject,body);
  expect(ok.statusCode,ok.body).toBe(200);
  expect(ok.headers['content-type']).toBe('text/csv; charset=utf-8');
  expect(ok.headers['content-disposition']).toBe('attachment; filename="drivy-F01-2026-10-01_2026-11-01.csv"');
  expect(ok.headers['cache-control']).toBe('no-store');
 });
 it('même définition que la carte : mêmes lignes, mêmes totaux, couverture annoncée',async()=>{
  const res=await exportCsv(ref.adm2.subject,{measure:'F01',...October});
  const text=res.body;
  expect(text.startsWith('﻿#definitionsVersion;2026-10-31.1\r\n')).toBe(true);
  for(const meta of ['#computedAt;2026-10-28T17:00:00.000Z','#timeZone;Europe/Zurich','#periodFrom;2026-10-01','#periodToExclusive;2026-11-01','#currency;CHF','#scope;school','#measure;F01',
   '#lineCount;5','#totalAmountCents;57000','#complete;true','#driftFromDisplayed;false','#notAnAccountingDocument;true'])expect(text, meta).toContain(`${meta}\r\n`);
  const rows=text.split('\r\n').filter(line=>line.startsWith('LESSON;'));
  expect(rows).toHaveLength(5);
  expect(rows.reduce((sum,row)=>sum+Number(row.split(';')[10]),0)).toBe(57000);
  expect(rows.every(row=>row.endsWith(';CHF'))).toBe(true);
  expect(rows[0]).toContain(`LESSON;${ref.lessons.O1};2026-10-01T00:30:00+02:00;COMPLETED;`);
  // Aucun nom d'élève ni de note dans le fichier.
  expect(text).not.toMatch(/Élève|Camille|note/i);
  // Une mesure partielle n'est jamais annoncée complète.
  const partial=(await exportCsv(ref.adm2.subject,{measure:'H02',...October})).body;
  expect(partial).toContain('#complete;false\r\n');
  expect(partial).toContain('#coverage;PARTIAL:DURATION_UNKNOWN=1\r\n');
 });
 it('signale un écart avec le total affiché',async()=>{
  const res=await exportCsv(ref.adm2.subject,{measure:'F01',...October,expectedLineCount:4});
  expect(res.statusCode).toBe(200);
  expect(res.headers['x-metrics-drift']).toBe('true');
  expect(res.body).toContain('#driftFromDisplayed;true\r\n');
 });
 it('moniteur avec EXPORT_MANAGEMENT : export de sa seule activité, zéro ligne est un résultat',async()=>{
  const empty=await exportCsv(ref.m4.subject,{measure:'L01',...October});
  expect(empty.statusCode).toBe(200);
  expect(empty.body).toContain('#lineCount;0\r\n');
  expect(empty.body.split('\r\n').filter(line=>line.startsWith('LESSON;'))).toHaveLength(0);
  const mine=await addActor(pool,ref.school,'m1b-ref',['INSTRUCTOR'],['EXPORT_MANAGEMENT']);
  expect((await exportCsv(mine.subject,{measure:'L01',...October})).statusCode).toBe(200);
 });
 it('un droit retiré entre l\'affichage et l\'export : refus, aucun fichier',async()=>{
  const actor=await addActor(pool,ref.school,'rev-ref',['INSTRUCTOR'],['VIEW_FINANCIAL_METRICS','EXPORT_MANAGEMENT']);
  const body={measure:'F01',...October};
  expect((await exportCsv(actor.subject,body)).statusCode).toBe(200);
  await pool.query("UPDATE drivy.membership SET grants='{VIEW_FINANCIAL_METRICS}',access_epoch=access_epoch+1 WHERE id=$1",[actor.membershipId]);
  const refused=await exportCsv(actor.subject,body);
  expect(problem(refused)).toEqual({status:403,code:'ACCESS_REVOKED'});
  expect(refused.headers['content-type']).toContain('application/problem+json');
  await pool.query("UPDATE drivy.membership SET grants='{}',access_epoch=access_epoch+1 WHERE id=$1",[actor.membershipId]);
  expect(problem(await metrics(actor.subject,'finance'))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
  expect(problem(await get(actor.subject,'/details',{measure:'F01',...October}))).toEqual({status:403,code:'METRIC_SCOPE_FORBIDDEN'});
 });
 it('accents, guillemets, sauts de ligne et cellules de formule',async()=>{
  const school=await createSchool(pool,'csv');
  const exporter=await addActor(pool,school,'exp-csv',['ADMIN'],['EXPORT_MANAGEMENT']);
  const formula=await addActor(pool,school,'formula-csv',['INSTRUCTOR'],[],'=1+1;"x"');
  const accent=await addActor(pool,school,'accent-csv',['INSTRUCTOR'],[],'Élodie\nMüller');
  const learner=await addLearner(pool,school,'C1','B');
  for(const [instructor,day] of [[formula,'10'],[accent,'11']] as const)
   await addLesson(pool,school,{instructor,learner,product:'b45v2',status:'COMPLETED',price:10000,plannedStart:`2026-10-${day}T08:00:00Z`,plannedEnd:`2026-10-${day}T08:45:00Z`,
    actualStart:`2026-10-${day}T08:00:00Z`,actualEnd:`2026-10-${day}T08:45:00Z`});
  const res=await exportCsv(exporter.subject,{measure:'L01',...October},school.id);
  expect(res.statusCode,res.body).toBe(200);
  expect(res.body).toContain(`;"'=1+1;""x""";B;b-45;`);
  expect(res.body).toContain(';"Élodie\nMüller";B;b-45;');
  expect(res.body).toContain('2026-10-10T10:00:00+02:00');
 });
 it('plus de 10 000 lignes : refus explicite, jamais un fichier tronqué',async()=>{
  const big=await createSchool(pool,'big');
  const exporter=await addActor(pool,big,'exp-big',['ADMIN'],['EXPORT_MANAGEMENT']);
  const instructor=await addActor(pool,big,'m-big',['INSTRUCTOR']),learner=await addLearner(pool,big,'G1','B');
  await pool.query(`INSERT INTO drivy.lesson(school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,
    price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection,created_at)
   SELECT $1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,'2026-10-29T00:00:00Z'::timestamptz+n*interval '1 minute','2026-10-29T00:00:00Z'::timestamptz+n*interval '1 minute'+interval '30 seconds','Europe/Zurich','Gare (synthétique)',
    10000,0,$6::uuid,$7::jsonb,'2026-09-01T00:00:00Z'::timestamptz FROM generate_series(1,10001) AS n`,
   [big.id,learner.trainingId,learner.learnerId,learner.personId,instructor.membershipId,big.policy,JSON.stringify({mode:'UNIT_PRICE',serviceProductVersionId:big.products.b45v2,quantity:1,entitlementLotId:null,acceptedTermsVersionId:big.terms})]);
  // La carte compte tout, sans passer par une page de liste.
  expect(data(await metrics(big.admin.subject,'activity',{from:'2026-10-29',toExclusive:'2026-11-12'},big.id)).measures.L02.value).toBe(10001);
  const detail=data(await get(big.admin.subject,'/details',{measure:'L02',from:'2026-10-29',toExclusive:'2026-11-12',limit:100},big.id));
  expect(detail.total.lineCount).toBe(10001);
  expect(detail.lines).toHaveLength(100);
  const refused=await exportCsv(exporter.subject,{measure:'L02',from:'2026-10-29',toExclusive:'2026-11-12'},big.id);
  expect(problem(refused)).toEqual({status:413,code:'EXPORT_TOO_LARGE'});
  expect(refused.headers['content-type']).toContain('application/problem+json');
 },90_000);
});

describe('paramètres validés',()=>{
 it('refuse dates invalides, période trop longue, paramètres inconnus ou mal formés',async()=>{
  const ok={domain:'activity',from:'2026-10-01',toExclusive:'2026-11-01'};
  const status=async(params:Record<string,string|number|undefined>,path='')=>(await get(ref.adm1.subject,path,params)).json().code;
  expect(await status({...ok,from:'2026-11-01',toExclusive:'2026-10-01'})).toBe('INVALID_PERIOD');
  expect(await status({...ok,from:'2026-02-30'})).toBe('INVALID_REQUEST');
  expect(await status({...ok,from:'2026-01-01',toExclusive:'2027-01-03'})).toBe('PERIOD_TOO_LARGE');
  expect(await status({...ok,extra:'1'})).toBe('INVALID_REQUEST');
  expect(await status({...ok,instructorMembershipId:'pas-un-uuid'})).toBe('INVALID_REQUEST');
  expect(await status({...ok,compare:'annee'})).toBe('INVALID_REQUEST');
  expect(await status({...ok,domain:'autre'})).toBe('INVALID_REQUEST');
  const series={from:'2026-10-01',toExclusive:'2026-11-01',granularity:'week'};
  expect(await status({...series,measures:'L01,L01'},'/series')).toBe('INVALID_REQUEST');
  expect(await status({...series,measures:'P05'},'/series')).toBe('INVALID_REQUEST');
  expect(await status({...series,measures:'L01,F01'},'/series')).toBe('INVALID_REQUEST');
  expect(await status({...series,measures:'C04'},'/series')).toBe('INVALID_REQUEST');
  expect(await status({...series,measures:'L01',granularity:'year'},'/series')).toBe('INVALID_REQUEST');
  expect(await status({...ok,measure:'L01',limit:101},'/details')).toBe('INVALID_REQUEST');
  expect(await status({measure:'L01',from:'2026-10-01',toExclusive:'2026-11-01',part:'a'},'/details')).toBe('INVALID_REQUEST');
  expect(await status({measure:'C01',from:'2026-10-01',toExclusive:'2026-11-01',categoryCode:'B'},'/details')).toBe('METRIC_FILTER_UNSUPPORTED');
  expect((await call('POST',url(ref.school.id,'/exports'),{measure:'L01',...October,extra:true},null,ref.adm2.subject)).statusCode).toBe(400);
 });
});

describe('fonctions SQL : refus propres et empreinte de sécurité (condition de D1)',()=>{
 const lines=`SELECT count(*)::int AS n FROM drivy.metrics_lesson_lines($1::uuid,'2026-10-01'::date,'2026-11-01'::date,'2026-10-28T17:00:00Z'::timestamptz,$2::text,$3::uuid,NULL,NULL,$4::boolean,NULL)`;
 async function asApp<T>(school:string,person:string,work:(db:PoolClient)=>Promise<T>,role='drivy_app'):Promise<T>{
  const db=await pool.connect();
  try{
   await db.query('BEGIN READ ONLY');await db.query(`SET LOCAL ROLE ${role}`);
   await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)",[school,person]);
   return await work(db);
  }finally{await db.query('ROLLBACK').catch(()=>undefined);db.release();}
 }
 const refuses=async(school:string,person:string,sql:string,params:unknown[],message:string)=>
  expect(asApp(school,person,db=>db.query(sql,params))).rejects.toMatchObject({message});

 it('autre école : refusée, qu\'on parle de son école ou d\'une autre',async()=>{
  // Un ADMIN d'une autre école, dans le contexte de la sienne puis dans celui de l'école visée.
  await refuses(bulk.school.id,bulk.admin.personId,lines,[ref.school.id,'school',null,false],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,bulk.admin.personId,lines,[ref.school.id,'school',null,false],'METRIC_FORBIDDEN');
  // Un ADMIN de l'école, mais l'école demandée n'est pas celle de la requête.
  await refuses(ref.school.id,ref.adm1.personId,lines,[bulk.school.id,'school',null,false],'METRIC_FORBIDDEN');
 });
 it('autre moniteur : refusé ; portée école sans grant : refusée',async()=>{
  await refuses(ref.school.id,ref.m1.personId,lines,[ref.school.id,'self',ref.m2.membershipId,false],'METRIC_SCOPE_FORBIDDEN');
  await refuses(ref.school.id,ref.m1.personId,lines,[ref.school.id,'school',null,false],'METRIC_SCOPE_FORBIDDEN');
  await refuses(ref.school.id,ref.m1.personId,lines,[ref.school.id,'autre',null,false],'METRIC_SCOPE_FORBIDDEN');
  const own=await asApp(ref.school.id,ref.m1.personId,db=>db.query(lines,[ref.school.id,'self',null,false]));
  expect(own.rows[0].n).toBe(10);
 });
 it('élève : refusé partout, y compris dans son école',async()=>{
  const learner=ref.learners.E1!;
  await refuses(ref.school.id,learner.personId,lines,[ref.school.id,'self',null,false],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,learner.personId,lines,[ref.school.id,'school',null,false],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,learner.personId,'SELECT * FROM drivy.metrics_course_payment_lines($1::uuid,\'2026-10-01\'::date,\'2026-11-01\'::date)',[ref.school.id],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,learner.personId,'SELECT drivy.metrics_data_since($1::uuid)',[ref.school.id],'METRIC_FORBIDDEN');
 });
 it('montants : seulement ADMIN ou VIEW_FINANCIAL_METRICS, portée école',async()=>{
  await refuses(ref.school.id,ref.m1.personId,lines,[ref.school.id,'self',null,true],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,ref.m2.personId,lines,[ref.school.id,'school',null,true],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,ref.m3.personId,lines,[ref.school.id,'self',null,true],'METRIC_SCOPE_FORBIDDEN');
  const payments='SELECT count(*)::int AS n FROM drivy.metrics_course_payment_lines($1::uuid,\'2026-10-01\'::date,\'2026-11-01\'::date)';
  await refuses(ref.school.id,ref.m1.personId,payments,[ref.school.id],'METRIC_FORBIDDEN');
  await refuses(ref.school.id,ref.m2.personId,payments,[ref.school.id],'METRIC_FORBIDDEN');
  expect((await asApp(ref.school.id,ref.m3.personId,db=>db.query(payments,[ref.school.id]))).rows[0].n).toBe(9);
  expect((await asApp(ref.school.id,ref.adm1.personId,db=>db.query(lines,[ref.school.id,'school',null,true]))).rows[0].n).toBe(15);
 });
 it('période invalide : refusée par la fonction elle-même',async()=>{
  const call2=(from:string,to:string)=>asApp(ref.school.id,ref.adm1.personId,db=>db.query(
   `SELECT * FROM drivy.metrics_lesson_lines($1::uuid,$2::date,$3::date,now(),'school',NULL,NULL,NULL,false,NULL)`,[ref.school.id,from,to]));
  await expect(call2('2026-10-05','2026-10-05')).rejects.toMatchObject({message:'INVALID_PERIOD'});
  await expect(call2('2025-01-01','2026-12-31')).rejects.toMatchObject({message:'INVALID_PERIOD'});
 });
 it('exécution réservée au rôle applicatif, search_path fixé, lecture seule',async()=>{
  const functions=(await pool.query(`SELECT p.proname,p.prosecdef,p.provolatile,p.proconfig,has_function_privilege('public',p.oid,'EXECUTE') AS public_exec,
    has_function_privilege('drivy_app',p.oid,'EXECUTE') AS app_exec FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='drivy' AND p.proname LIKE 'metrics\\_%' ORDER BY p.proname`)).rows;
  expect(functions.map(f=>f.proname)).toEqual(['metrics_course_enrollment_events','metrics_course_payment_lines','metrics_course_series_lines','metrics_course_session_lines',
   'metrics_data_since','metrics_fail','metrics_gate','metrics_lesson_lines']);
  for(const f of functions){
   expect(f.public_exec,f.proname).toBe(false);
   if(f.proname==='metrics_fail'){expect(f.app_exec).toBe(false);continue;}
   expect(f.app_exec,f.proname).toBe(true);
   expect(f.prosecdef,f.proname).toBe(true);
   expect(f.provolatile,f.proname).toBe('s');
   expect(f.proconfig,f.proname).toContain('search_path=pg_catalog, drivy');
  }
  // Un autre rôle de la base ne peut pas les appeler.
  await expect(asApp(ref.school.id,ref.adm1.personId,db=>db.query('SELECT drivy.metrics_data_since($1::uuid)',[ref.school.id]),'drivy_invitation_mailer')).rejects.toMatchObject({code:'42501'});
  // Les appels s'exécutent dans une transaction en lecture seule : aucune écriture n'est possible.
  expect((await asApp(ref.school.id,ref.adm1.personId,db=>db.query(lines,[ref.school.id,'school',null,false]))).rows[0].n).toBe(15);
 });
 it('aucune table ni donnée n\'a été ajoutée par la migration',async()=>{
  const tables=await pool.query("SELECT count(*)::int AS n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relkind='r' AND NOT (c.relrowsecurity AND c.relforcerowsecurity)");
  expect(tables.rows[0].n).toBe(0);
  expect(issuer).toContain('harness-identity');void id;
 });
});

describe('coût des lectures : index justifiés par mesure',()=>{
 it('la somme des écritures d\'une leçon est servie par un index (mesuré : 4,7 s pour 10 064 leçons sans lui)',async()=>{
  const found=await pool.query("SELECT indexdef FROM pg_indexes WHERE schemaname='drivy' AND indexname='charge_entry_metrics_account'");
  expect(found.rows).toHaveLength(1);
  expect(found.rows[0].indexdef).toContain('(school_id, account_id)');
 });
 it('un export exactement à la limite est livré en entier, un de plus est refusé',async()=>{
  const edge=await createSchool(pool,'edge');
  const exporter=await addActor(pool,edge,'exp-edge',['ADMIN'],['EXPORT_MANAGEMENT']);
  const instructor=await addActor(pool,edge,'m-edge',['INSTRUCTOR']),learner=await addLearner(pool,edge,'E1','B');
  const insert=(first:number,last:number)=>pool.query(`INSERT INTO drivy.lesson(school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,
    price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection,created_at)
   SELECT $1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,'2026-10-29T00:00:00Z'::timestamptz+n*interval '1 minute','2026-10-29T00:00:00Z'::timestamptz+n*interval '1 minute'+interval '30 seconds','Europe/Zurich','Gare (synthétique)',
    10000,0,$6::uuid,$7::jsonb,'2026-09-01T00:00:00Z'::timestamptz FROM generate_series($8::int,$9::int) AS n`,
   [edge.id,learner.trainingId,learner.learnerId,learner.personId,instructor.membershipId,edge.policy,JSON.stringify({mode:'UNIT_PRICE',serviceProductVersionId:edge.products.b45v2,quantity:1,entitlementLotId:null,acceptedTermsVersionId:edge.terms}),first,last]);
  await insert(1,10_000);
  const full=await exportCsv(exporter.subject,{measure:'L02',from:'2026-10-29',toExclusive:'2026-11-12'},edge.id);
  expect(full.statusCode,full.body.slice(0,200)).toBe(200);
  expect(full.body).toContain('#lineCount;10000\r\n');
  await insert(10_001,10_001);
  const over=await exportCsv(exporter.subject,{measure:'L02',from:'2026-10-29',toExclusive:'2026-11-12'},edge.id);
  expect(problem(over)).toEqual({status:413,code:'EXPORT_TOO_LARGE'});
 },90_000);
});
