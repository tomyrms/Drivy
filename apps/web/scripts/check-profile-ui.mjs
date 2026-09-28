import {TestMemoryCommandStore} from '../dist/server/test-memory-commands.js';
// Synthetic UI harness only: no PostgreSQL, OAuth exchange, real user or remote API.
import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
await mkdir(new URL('../node_modules/.cache/',import.meta.url),{recursive:true});
import {fileURLToPath} from 'node:url';
import {buildWebApp} from '../dist/server/app.js';
import {SessionStore} from '../dist/server/session.js';
const {chromium}=await import(process.env.DRIVY_BROWSER_MODULE??new URL('../../../infra/dev/browser.ts',import.meta.url).href);
const id=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const schoolId=id(1),personId=id(2),memberId=id(3),learnerId=id(4),policyId=id(5),profileId=id(6),noticeId=id(7),draftId=id(8);
const rules=[{field:'firstName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identification scolaire.'},{field:'lastName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identification scolaire.'}];
const school={id:schoolId,schoolId,version:1,name:'École de recette locale',status:'ACTIVE'};
const member={membershipId:memberId,schoolId,schoolName:school.name,accessEpoch:1,roles:['ADMIN'],grants:[]};
const learner={id:learnerId,schoolId,personId,version:1,displayName:'Nom affiché conservé',contactEmail:null,contactPhone:null,archivedAt:null,profileReadiness:'MINIMAL'};
const policy={id:policyId,schoolId,version:2,status:'PUBLISHED',effectiveFrom:'2026-01-01T00:00:00Z',fields:rules,noticeVersionId:noticeId,approvedByMembershipId:memberId};
const draft={...policy,id:draftId,version:1,status:'DRAFT',approvedByMembershipId:null};
const profile={id:profileId,schoolId,learnerId,version:1,firstName:null,lastName:null,contactEmail:null,contactPhone:null,birthDate:null,postalAddress:null,profilePhotoDocumentId:null,policyVersionId:policyId,updatedAt:'2026-01-01T00:00:00Z',enteredByMembershipId:memberId,entrySource:'STAFF_ASSISTED'};
const config={origin:'http://127.0.0.1:3004',apiBaseURL:'https://unused.example',issuer:'https://unused.example',clientId:'fixture-web',clientSecret:'fixture-only'.repeat(4),development:true,host:'127.0.0.1',port:3004};
const store=new SessionStore();const session=store.create();session.tokens={accessToken:'mock-ui-access',expiresAt:Date.now()+600000,principal:{subject:id(9),displayName:'Compte de recette',emailVerified:true}};
let mutations=0;
const gateway=async(path,_token,body)=>{
 const ok=data=>({status:200,body:{data}});
 if(path==='/v1/me')return ok({personId,displayName:'Compte de recette',version:1,memberships:[member]});
 if(body){mutations++;if(path.endsWith('/administrative-profile')){Object.assign(profile,{firstName:body.firstName,lastName:body.lastName,version:2});learner.version=2;return ok(profile);}if(path.endsWith('/publish')){draft.status='PUBLISHED';draft.version=2;draft.approvedByMembershipId=memberId;return ok(draft);}throw Error('Mutation imprévue');}
 if(path===`/v1/schools/${schoolId}`)return ok(school);
 if(path.includes('/profile-field-policies?'))return ok({items:[policy,draft],nextCursor:null});
 if(path.includes('/data-policy'))return ok({noticeVersionId:noticeId,status:'APPROVED',noticeText:'Notice synthétique locale.',retentionText:'Conservation synthétique.',version:1});
 if(path.endsWith('/administrative-profile'))return ok(profile);
 if(path.includes('/action-readiness?'))return ok({learnerId,action:'ENTER',resourceId:null,ready:!!profile.firstName&&!!profile.lastName,blockers:profile.firstName&&profile.lastName?[]:[{code:'PROFILE_ACTION_REQUIRED',message:'Les noms administratifs restent à renseigner.',field:'firstName',purpose:'Identification',resourceId:null,destinationKey:null}],policyVersionId:policyId,computedAt:'2026-01-01T00:00:00Z'});
 if(path.includes('/learners?'))return ok({items:[learner],nextCursor:null});
 if(path===`/v1/schools/${schoolId}/learners/${learnerId}`)return ok(learner);
 return {status:404,body:{code:'NOT_FOUND'}};
};
const identity={begin:async()=>{throw Error();},complete:async()=>session.tokens,refresh:async()=>session.tokens,revoke:async()=>{}};
let browser;const app=await buildWebApp({commandStore:new TestMemoryCommandStore(),config,store,identity,gateway,staticRoot:fileURLToPath(new URL('../dist/client/',import.meta.url))});
let stage='services';
try{
 await app.listen({host:'127.0.0.1',port:3004});browser=await chromium.launch({channel:'msedge',headless:true});const context=await browser.newContext({viewport:{width:1280,height:1100}});
 await context.route('**/*',route=>new URL(route.request().url()).origin===config.origin?route.continue():route.abort());
 await context.addCookies([{name:'drivy-dev-session',value:session.id,url:config.origin,httpOnly:true,sameSite:'Lax'}]);const page=await context.newPage();page.setDefaultTimeout(8000);
 await page.goto(config.origin+'/app');await page.getByRole('button',{name:'Ouvrir l’école',exact:true}).click();stage='profil';await page.getByRole('button',{name:'Ouvrir le profil',exact:true}).click();
 assert.equal(await page.getByLabel('Prénom').inputValue(),'');assert.equal(await page.getByLabel('Nom',{exact:false}).filter({visible:true}).count(),2);
 await page.getByLabel('Prénom').fill('Éléonore');await page.locator('input[type=text]').nth(1).fill('Recette');await page.getByRole('button',{name:'Relire les modifications',exact:true}).click();
 await page.getByRole('heading',{name:'Relire avant de confirmer'}).waitFor();assert.equal(mutations,0);stage='confirmation profil';
 await page.getByRole('checkbox',{name:'J’ai relu cette demande',exact:false}).check();await page.getByRole('button',{name:'Confirmer la demande',exact:true}).click();await page.getByRole('status').filter({hasText:'Enregistrement confirmé'}).waitFor();assert.equal(mutations,1);
 await page.screenshot({path:fileURLToPath(new URL('../node_modules/.cache/profile-desktop.png',import.meta.url)),fullPage:true});
 await page.emulateMedia({colorScheme:'dark'});await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);await page.screenshot({path:fileURLToPath(new URL('../node_modules/.cache/profile-phone-dark.png',import.meta.url)),fullPage:true});await page.emulateMedia({colorScheme:'light'});await page.setViewportSize({width:1280,height:1100});stage='publication politique';await page.getByRole('button',{name:'Politique des champs',exact:true}).click();await page.getByRole('button',{name:'Relire la publication',exact:true}).click();
 await page.getByRole('checkbox',{name:'J’ai relu cette demande',exact:false}).check();await page.getByRole('button',{name:'Confirmer la demande',exact:true}).click();await page.getByRole('status').filter({hasText:'Publication confirmée'}).waitFor();assert.equal(mutations,2);
 await page.screenshot({path:fileURLToPath(new URL('../node_modules/.cache/policy-desktop.png',import.meta.url)),fullPage:true});
 console.log('UI synthétique Edge : noms vides, préparation sans effet, confirmation profil et publication distincte réussis.');
}catch{console.error('UI synthétique interrompue : '+stage);process.exitCode=1;}finally{await browser?.close();await app.close();}

