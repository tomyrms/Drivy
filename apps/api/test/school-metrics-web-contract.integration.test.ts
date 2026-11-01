import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,type Call} from './support/harness.js';
import {NOW,seedBulk,seedReference,type Reference} from './support/metrics-seed.js';
import {definitionsSchema,detailsSchema,metricsSchema,seriesSchema} from '../../web/client/portal/pilotage/metrics-schemas.js';

/**
 * Pilotage de l'école (#373, T09 #382) : les schémas de lecture du web (apps/web/client/portal/pilotage/metrics-schemas.ts) lisent les VRAIES réponses
 * de l'API sur le jeu de référence. Sans ce contrôle, une dérive de forme n'apparaît qu'à l'écran, sous la forme « Lecture impossible ».
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],ref:Reference;
beforeAll(async()=>{
 pool=await freshDatabase();
 ({call,app}=await harness(pool,{metricsClock:()=>new Date(NOW)}));
 ref=await seedReference(pool);
 await seedBulk(pool);
},120_000);
afterAll(async()=>{await app?.close();await pool?.end();});

const October={from:'2026-10-01',toExclusive:'2026-11-01'};
const url=(path:string,params:Record<string,string|number>={})=>{
 const query=new URLSearchParams();for(const [key,value] of Object.entries(params))query.set(key,String(value));
 const text=query.toString();return `/v1/schools/${ref.school.id}/metrics${path}${text?`?${text}`:''}`;
};
const read=async(path:string,params:Record<string,string|number>={})=>{
 const res=await call('GET',url(path,params),undefined,null,ref.adm1.subject);
 expect(res.statusCode,`${path} ${JSON.stringify(params)} ${res.body}`).toBe(200);
 return res.json().data;
};
const accepted=(schema:{safeParse:(value:unknown)=>{success:boolean;error?:{issues:unknown[]}}},value:unknown)=>{
 const result=schema.safeParse(value);
 expect(result.success,JSON.stringify(result.error?.issues.slice(0,3))).toBe(true);
};

describe('le web lit les réponses réelles de l\'API',()=>{
 it('dictionnaire des mesures',async()=>{
  const body=await read('/definitions');
  accepted(definitionsSchema,body);
  // Le web s'appuie sur l'indicateur « lignes disponibles » pour proposer le détail.
  expect(body.measures.find((item:{id:string})=>item.id==='L01').details).toBe(true);
  expect(body.measures.find((item:{id:string})=>item.id==='P01').details).toBe(false);
 });
 it('cartes d\'activité et de finances, avec comparaison et répartitions',async()=>{
  for(const domain of ['activity','finance'])accepted(metricsSchema,await read('',{domain,...October}));
  accepted(metricsSchema,await read('',{domain:'activity',...October,compare:'previous-month'}));
  accepted(metricsSchema,await read('',{domain:'activity',from:'2026-10-05',toExclusive:'2026-10-12',compare:'equivalent-period'}));
  for(const breakdown of ['instructor','category','product']){
   for(const domain of ['activity','finance'])accepted(metricsSchema,await read('',{domain,...October,breakdown}));
  }
 });
 it('séries par jour, semaine et mois',async()=>{
  for(const granularity of ['day','week','month'])accepted(seriesSchema,await read('/series',{...October,granularity,measures:'L01,L02'}));
  accepted(seriesSchema,await read('/series',{...October,granularity:'week',measures:'F01,F02,F05'}));
 });
 it('lignes de détail de chaque nature : leçons, séances de cours et règlements, et concordance avec la carte',async()=>{
  const cards={...(await read('',{domain:'activity',...October})).measures,...(await read('',{domain:'finance',...October})).measures};
  for(const measure of ['L01','L02','L03','L05','L07','C01','F01','F02','F03','F04','F05']){
   const card=cards[measure],expected:Record<string,number>={};
   if(card.lineCount!==undefined)expected.expectedLineCount=card.lineCount;
   if(card.unit==='cents'&&card.value!==null)expected.expectedAmountCents=card.value;
   const body=await read('/details',{measure,...October,...expected});
   accepted(detailsSchema,body);
   expect(body.measure).toBe(measure);
   // Le chiffre de la carte, le total du détail et le montant concordent, et le serveur ne signale aucun écart.
   if(card.lineCount!==undefined)expect(body.total.lineCount,`${measure} : lignes`).toBe(card.lineCount);
   if(card.unit==='cents'&&card.value!==null)expect(body.total.amountCents,`${measure} : montant`).toBe(card.value);
   expect(body.drift,`${measure} : écart`).toBeNull();
  }
 });
 it('F06 se détaille en deux listes, dont les lignes font le total de la carte',async()=>{
  const card=(await read('',{domain:'finance',...October})).measures.F06;
  const a=await read('/details',{measure:'F06',part:'a',...October}),b=await read('/details',{measure:'F06',part:'b',...October});
  accepted(detailsSchema,a);accepted(detailsSchema,b);
  expect(a.total.lineCount+b.total.lineCount).toBe(card.lineCount);
  // Sans partie, le serveur refuse : le web ne peut pas proposer le détail de F06 sans elle.
  const refused=await call('GET',url('/details',{measure:'F06',...October}),undefined,null,ref.adm1.subject);
  expect(refused.statusCode).toBe(400);
 });
});
