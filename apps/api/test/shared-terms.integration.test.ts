import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
const admin='demo-admin',cancellation='Recette uniquement';
const today=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Zurich'});
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
async function sharedProducts(){
 const termsText=`Paiement selon les modalités convenues.\n\n${cancellation}`;
 const terms=await call('POST','/commercial-terms',{operationId:randomUUID(),label:'Conditions partagées synthétiques',termsText,validFrom:today(),validUntil:null,approved:true,approvalReason:'Recette synthétique'},null,admin);
 expect(terms.statusCode,terms.body).toBe(201);
 const termsId=terms.json().data.id as string,products:{id:string;key:string;siteId:string|null}[]=[];
 for(const siteId of [null,randomUUID()]){
  const key=`shared-${randomUUID()}`;
  const response=await call('POST','/service-products',{operationId:randomUUID(),productKey:key,label:'Leçon synthétique',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9000,validFrom:today(),validUntil:null,termsVersionId:termsId,enabled:true},null,admin);
  expect(response.statusCode,response.body).toBe(201);products.push({id:response.json().data.id as string,key,siteId});
 }
 return {termsId,termsText,products};
}
const revise=(body:Record<string,unknown>,subject=admin)=>call('POST','/formations/terms/revise',body,null,subject);
const command=(fixture:Awaited<ReturnType<typeof sharedProducts>>)=>({operationId:randomUUID(),termsVersionId:fixture.termsId,expectedProductVersionIds:fixture.products.map(item=>item.id),termsText:`Paiement à réception de la facture.\n\n${cancellation}`,reviewAcknowledged:true});
const configuration=async()=>(await pool.query('SELECT version,configuration_version FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0];

it('révise ensemble les tarifs relus, conserve prix, sites et engagements, et rejoue sans doubler les versions',async()=>{
 const fixture=await sharedProducts(),body=command(fixture),before=await configuration();
 const planned=await call('POST','/lessons',lessonBody({terms:{id:fixture.termsId},product:{id:fixture.products[0]!.id}},school.policy,90));
 expect(planned.statusCode,planned.body).toBe(201);
 const response=await revise(body);expect(response.statusCode,response.body).toBe(201);
 const revised=response.json().data;expect(revised).toMatchObject({previousTermsVersionId:fixture.termsId,updatedTariffs:2});
 expect(await configuration()).toEqual({version:before.version+1,configuration_version:before.configuration_version+1});
 for(const product of fixture.products){
  const versions=(await pool.query('SELECT version,terms_version_id,unit_price_cents::int,site_id FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 ORDER BY version',[id.schoolA,product.key])).rows;
  expect(versions).toEqual([
   {version:1,terms_version_id:fixture.termsId,unit_price_cents:9000,site_id:product.siteId},
   {version:2,terms_version_id:revised.id,unit_price_cents:9000,site_id:product.siteId},
  ]);
 }
 expect((await call('GET',`/lessons/${planned.json().data.id}`)).json().data.commercialSelection.acceptedTermsVersionId).toBe(fixture.termsId);
 expect((await pool.query('SELECT terms_text FROM drivy.commercial_terms_version WHERE id=$1',[fixture.termsId])).rows[0].terms_text).toBe(fixture.termsText);
 expect((await revise(body)).json().data).toEqual(revised);expect(await configuration()).toEqual({version:before.version+1,configuration_version:before.configuration_version+1});
});

it('refuse une liste partielle, une version concurrente, un changement d’annulation ou un rôle sans droit sans écriture',async()=>{
 const fixture=await sharedProducts(),body=command(fixture),before=await configuration();
 for(const expectedProductVersionIds of [[fixture.products[0]!.id],[fixture.products[0]!.id,randomUUID()]]){
  const denied=await revise({...body,operationId:randomUUID(),expectedProductVersionIds});expect(denied.json().code).toBe('TERMS_USAGE_CHANGED');
 }
 const cancellationChange=await revise({...body,operationId:randomUUID(),termsText:'Paiement à réception. Aucune règle d’annulation conservée.'});
 expect(cancellationChange.json().code).toBe('CANCELLATION_REVIEW_REQUIRED');
 for(const subject of ['demo-instructor','demo-alice','demo-foreign'])expect([403,404]).toContain((await revise({...body,operationId:randomUUID()},subject)).statusCode);
 expect(await configuration()).toEqual(before);
 const parallel=await Promise.all([revise(body),revise({...body,operationId:randomUUID(),termsText:`Autres modalités de paiement relues.\n\n${cancellation}`})]);
 expect(parallel.map(response=>response.statusCode).sort()).toEqual([201,409]);
 expect(parallel.find(response=>response.statusCode===409)!.json().code).toBe('TERMS_USAGE_CHANGED');
});

it('conserve la fenêtre passée d’un tarif expiré sans bloquer ni réactiver tout le groupe',async()=>{
 const fixture=await sharedProducts(),expired=fixture.products[1]!;
 await pool.query("UPDATE drivy.service_product_version SET valid_from='2020-01-01',valid_until='2020-12-31' WHERE id=$1",[expired.id]);
 const response=await revise(command(fixture));expect(response.statusCode,response.body).toBe(201);
 const rows=(await pool.query("SELECT version,to_char(valid_from,'YYYY-MM-DD') AS starts,to_char(valid_until,'YYYY-MM-DD') AS ends FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 ORDER BY version",[id.schoolA,expired.key])).rows;
 expect(rows).toEqual([{version:1,starts:'2020-01-01',ends:'2020-12-31'},{version:2,starts:'2020-01-01',ends:'2020-12-31'}]);
});

it.each([
 {label:'futures',starts:'2100-01-01',ends:'2100-12-31',status:'TERMS_NOT_YET',revisedStarts:'2100-01-01'},
 {label:'expirées',starts:'2020-01-01',ends:'2020-12-31',status:'TERMS_EXPIRED',revisedStarts:'2020-01-01'},
 {label:'actives avec une fin',starts:'2020-01-01',ends:'2100-12-31',status:'OFFERED',revisedStarts:null},
])('conserve les bornes des conditions $label même si les tarifs n’ont aucune date de fin',async window=>{
 const fixture=await sharedProducts();
 await pool.query('UPDATE drivy.commercial_terms_version SET valid_from=$2,valid_until=$3 WHERE id=$1',[fixture.termsId,window.starts,window.ends]);
 const sheet=async()=>{
  const response=await call('GET','/formations/sheet?category=B',undefined,undefined,admin);
  expect(response.statusCode,response.body).toBe(200);
  return response.json().data.tariffs as {productKey:string;status:string;head:{validUntil:string|null};terms:{id:string;validFrom:string;validUntil:string|null}}[];
 };
 for(const tariff of (await sheet()).filter(item=>fixture.products.some(product=>product.key===item.productKey)))expect(tariff.status).toBe(window.status);
 const revised=await revise(command(fixture));expect(revised.statusCode,revised.body).toBe(201);
 const tariffs=await sheet();
 for(const product of fixture.products){
  const tariff=tariffs.find(item=>item.productKey===product.key);
  expect(tariff).toMatchObject({status:window.status,head:{validUntil:null},
   terms:{id:revised.json().data.id,validFrom:window.revisedStarts??today(),validUntil:window.ends}});
 }
 const previous=(await pool.query("SELECT to_char(valid_from,'YYYY-MM-DD') AS starts,to_char(valid_until,'YYYY-MM-DD') AS ends,terms_text AS text FROM drivy.commercial_terms_version WHERE id=$1",[fixture.termsId])).rows[0];
 expect(previous).toEqual({starts:window.starts,ends:window.ends,text:fixture.termsText});
});
