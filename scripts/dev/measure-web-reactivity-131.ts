import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import type { IdentityProvider } from '../../apps/web/server/oidc.js';
import { build, preview } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';
import { fixtureSource } from './reactivity-131/fixture.js';
import { summarize } from './reactivity-131/stats.js';
import { accessReason, verifyMetadataOnly, type AccessVerdict } from './reactivity-131/guards.js';
import { waitForAccessVerdict } from './reactivity-131/observe.js';
const runId = new Date().toISOString().replaceAll(':','-');
const outputRelative = `artifacts/web-reactivity-131/correction-1/run-${runId}`;
const output = resolve(outputRelative);
await mkdir(output, { recursive:true });
const harnessBaseSha = execFileSync('git', ['rev-parse', 'HEAD'], {encoding:'utf8'}).trim();
const sha = 'e2edc85ed092237016620079d52d11eb7a2d02b5';
assert.equal(execFileSync('git',['diff',sha,'--','apps/web'],{encoding:'utf8'}),'','product sources must match qualified SHA');
const entryBuildSha = (await readFile('apps/web/dist/client/index.html','utf8')).match(/name="drivy-build" content="([a-f0-9]{40})"/)?.[1];
assert.equal(entryBuildSha,sha,'entry production build must match product SHA');
const hash = createHash('sha256');
for (const path of ['scripts/dev/measure-web-reactivity-131.ts','scripts/dev/reactivity-131/fixture.ts','scripts/dev/reactivity-131/stats.ts','scripts/dev/reactivity-131/guards.ts','scripts/dev/reactivity-131/observe.ts']) hash.update(await readFile(path));
const results: any = { date:new Date().toISOString(), sourceSha:sha, entryBuildSha, harnessBaseSha, output:outputRelative, harnessSha256:hash.digest('hex'), node:process.version, os:`${os.platform()} ${os.release()} ${os.arch()}`, modes:['Vite production entry served by buildWebApp','Vite production isolated real AccessPilot/PortalPendingRequests and PortalPreferencesPage, real demo transport'], samples:[], captures:[], checks:[], limits:['Synthetic BFF, no database or physical device','No concurrent tests launched by this worker during campaign; other machine workloads are uncontrolled','Added delay plus unchanged demo transport 650ms access / 500ms preferences','No p95; n=3 at 0/1s, n=1 at 5/15s; warmup separate','Bodies memory only; metadata sessionStorage is not body durability'] };
const flush = async () => writeFile(`${output}/results.json`, JSON.stringify(results,null,2));
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><div id="root"></div><script type="module" src="./fixture.tsx"></script></html>');
await writeFile(`${output}/fixture.tsx`, fixtureSource);
const config = { configFile:false as const, root:resolve('.'), base:'/', plugins:[react(),tailwind()], resolve:{alias:{'@':resolve('apps/web/client'),react:resolve('apps/web/node_modules/react'),'react-dom':resolve('apps/web/node_modules/react-dom'),zod:resolve('apps/web/node_modules/zod'),'lucide-react':resolve('apps/web/node_modules/lucide-react')}}, define:{__DRIVY_BUILD_SHA__:JSON.stringify(sha)}, build:{outDir:`${output}/dist`,emptyOutDir:true,rollupOptions:{input:`${output}/index.html`}}, logLevel:'error' as const };
await build(config);
const server = await preview({...config,preview:{host:'127.0.0.1',port:0}});
const address = server.httpServer.address(); assert(address && typeof address !== 'string');
const fixtureOrigin = `http://127.0.0.1:${address.port}/${outputRelative}/index.html`;
const unavailable = async (): Promise<never> => { throw new Error('Unexpected identity call'); };
const identity: IdentityProvider = {begin:unavailable,complete:unavailable,password:unavailable,refresh:unavailable,revoke:unavailable};
let app: Awaited<ReturnType<typeof buildWebApp>> | undefined;
let browser: Awaited<ReturnType<typeof chromium.launch>> | undefined;
async function arm(page: Page, trigger: string, event: string, expected: {selector:string; text?:string; attribute?:string; value?:string; property?:string; timeoutMs?:number}) {
  await page.evaluate("globalThis.__name = (fn) => fn"); // tsx keepNames helper for serialized browser callbacks; no clock patch
  await page.evaluate(({trigger,event,expected}) => {
    const target = document.querySelector(trigger); if(!target) throw new Error(`Missing trigger ${trigger}`);
    const w = window as any; const measurement = w.m = {start:null, first:null, error:null};
    const listener = () => { w.m.start = performance.now(); const poll = () => {
      if (w.m !== measurement) return;
      const el = document.querySelector(expected.selector);
      if(el && (expected.text === undefined || el.textContent?.includes(expected.text)) && (expected.attribute === undefined || el.getAttribute(expected.attribute) === expected.value) && (expected.property === undefined || (el as any)[expected.property] === expected.value)) w.m.first = performance.now();
      else if(performance.now() - w.m.start < (expected.timeoutMs ?? 22000)) requestAnimationFrame(poll);
      else w.m.error = 'NON_MESURÉ: expected DOM not observed';
    }; requestAnimationFrame(poll); };
    target.addEventListener(event, listener, {once:true,capture:true});
  }, {trigger,event,expected});
}
async function duration(page: Page) {
  await page.waitForFunction(() => (window as any).m?.first !== null || (window as any).m?.error, null, {timeout:23000});
  return page.evaluate(() => { const m=(window as any).m; if(m.error || m.start === null || m.first === null) throw new Error(m.error || 'Missing event'); return m.first-m.start; });
}
async function capture(page: Page, label:string) {
  await page.evaluate(async()=> { await document.fonts.ready; await new Promise<void>(done=>requestAnimationFrame(()=>done())); });
  const file=`${label}.png`; await page.screenshot({path:`${output}/${file}`,fullPage:true});
  results.captures.push({file,at:new Date().toISOString(),sha,viewport:page.viewportSize(),theme:await page.evaluate(()=>document.documentElement.dataset.theme),overflow:await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1)});
}
try {
  app = await buildWebApp({config:{origin:'http://127.0.0.1',apiBaseURL:'http://127.0.0.1:9',issuer:'http://127.0.0.1:9',clientId:'synthetic',clientSecret:'synthetic-unused',development:true,host:'127.0.0.1',port:0},identity,staticRoot:resolve('apps/web/dist/client')});
  const origin = await app.listen({host:'127.0.0.1',port:0});
  browser = await chromium.launch({headless:true}); results.browser=browser.version();
  const page = await browser.newPage();
  await page.setContent('<button id="trigger">Calibration</button>');
  await assert.rejects(arm(page,'#absent','click',{selector:'#absent'}), /Missing trigger/);
  await arm(page,'#trigger','click',{selector:'#absent',timeoutMs:100}); await page.click('#trigger'); await assert.rejects(duration(page), /NON_MESURÉ/);
  await page.evaluate(() => { (window as any).q = { matches: () => false }; });
  await assert.rejects(waitForAccessVerdict(page,'confirmed',100), /Timeout/);
  results.checks.push('missing trigger rejects; missing expected DOM rejects; absent store verdict times out without PASS'); await page.close();
  const delays = process.argv.includes('--smoke') ? [0] : [0,1000,5000,15000];
  for(const delay of delays) for(let repeat=delay===0?-1:0; repeat<(delay<=1000?3:1); repeat++) {
    const p: Page=await browser.newPage({viewport:{width:390,height:844}});
    const boot=performance.now(); let release!:()=>void; const gate=new Promise<void>(done=>release=done);
    await p.route('**/app/bff/**',async route=> {
      const path=new URL(route.request().url()).pathname;
      if(path.endsWith('/session')) { await gate; await new Promise(done=>setTimeout(done,delay)); return route.fulfill({json:{authenticated:true,csrfToken:'synthetic',invitationPending:false,user:{displayName:'Compte synthétique',emailVerified:true}}}); }
      if(path.endsWith('/me')) { await new Promise(done=>setTimeout(done,delay)); return route.fulfill({json:{data:{personId:'10000000-0000-4000-8000-000000000001',displayName:'Compte synthétique',version:1,memberships:[]}}}); }
      return route.fulfill({status:503,json:{code:'API_UNAVAILABLE'}});
    });
    await p.goto(`${origin}/app/`); await p.getByRole('button',{name:'J’ai un code',exact:true}).click();
    const input=p.locator('input[name=code]'); await input.waitFor();
    const startupMs=performance.now()-boot;
    await input.focus(); await arm(p,'input[name=code]','keydown',{selector:'input[name=code]',property:'value',value:'A'});
    await p.keyboard.type('A'); const feedbackMs=await duration(p);
    await input.fill('ABCDEFGH'); await p.keyboard.press('Home'); await p.keyboard.press('ArrowRight'); await p.keyboard.press('Shift+ArrowRight');
    const before=await input.evaluate((el:HTMLInputElement)=>({value:el.value,start:el.selectionStart,end:el.selectionEnd,focus:document.activeElement===el}));
    await p.evaluate(()=>{const w=window as any; w.releaseAt=performance.now(); const poll=()=>{if(document.querySelector('main[aria-busy="false"]')) w.entryConvergedAt=performance.now(); else if(performance.now()-w.releaseAt<40000) requestAnimationFrame(poll);}; requestAnimationFrame(poll);}); release();
    if(delay===15000) await capture(p,'entry-wait-390-light');
    await p.locator('main[aria-busy="false"]').waitFor({timeout:40000});
    await p.waitForFunction(()=>(window as any).entryConvergedAt !== undefined); const convergenceMs=await p.evaluate(()=>(window as any).entryConvergedAt-(window as any).releaseAt);
    assert.deepEqual(await input.evaluate((el:HTMLInputElement)=>({value:el.value,start:el.selectionStart,end:el.selectionEnd,focus:document.activeElement===el})),before);
    results.samples.push({surface:'entry',delay,repeat,warmup:repeat===-1,startupMs,feedbackMs,convergenceMs,localBody:'NON_MESURÉ: mémoire uniquement, aucune conservation durable',confirmation:'NON_MESURÉ: aucune mutation envoyée',focusSelectionPreserved:true}); await p.close(); await flush();
  }
  for(const surface of ['access','preferences']) for(const delay of delays) for(let repeat=delay===0?-1:0;repeat<(delay<=1000?3:1);repeat++) await mutation(surface,delay,repeat,'');
  if(!process.argv.includes('--smoke')) for(let repeat=0;repeat<3;repeat++) for(const fault of ['lost','refused','reread','storage','account']) await mutation('access',1000,repeat,fault);
  async function mutation(surface:string,delay:number,repeat:number,fault:string) {
    const p=await browser!.newPage({viewport:{width:1440,height:1000}}); p.setDefaultTimeout(8000);
    const errors:string[]=[]; p.on('pageerror',error=>errors.push(String(error)));
    const boot=performance.now(); await p.goto(`${fixtureOrigin}?surface=${surface}&delay=${delay}&fault=${fault}`);
    if(surface==='access') {
      await p.locator('#role-ADMIN').waitFor(); await p.locator('label[for=role-ADMIN]').click();
      await p.getByRole('button',{name:'Continuer',exact:true}).click(); await p.getByRole('button',{name:'Continuer',exact:true}).click();
      await p.locator('#access-reason').fill(accessReason);
      await p.getByRole('button',{name:'Confirmer les changements',exact:true}).click();
    } else await p.getByRole('switch').first().waitFor();
    const startupAndPreparationMs=performance.now()-boot;
    const trigger=surface==='access' ? '[role=dialog] button:last-child' : '[role=switch]';
    const expected=surface==='access'?{selector:'[role=dialog]',text:'Confirmation…'}:{selector:'[role=switch]',attribute:'aria-checked',value:'false'};
    await arm(p,trigger,'click',expected);
    if(surface==='access') await p.getByRole('button',{name:'Confirmer',exact:true}).click(); else await p.getByRole('switch').first().click();
    const feedbackMs=await duration(p), start=await p.evaluate(()=>(window as any).m.start);
    const sample:any={surface,delay,repeat,warmup:repeat===-1,fault,startupAndPreparationMs,feedbackMs,bodyDurability:'NON_MESURÉ: corps en mémoire uniquement'};
    if(delay===15000 && surface==='preferences') {
      await p.getByRole('radio',{name:'Sombre',exact:true}).evaluate(el=>el.setAttribute('data-q-theme','')); await arm(p,'[data-q-theme]','click',{selector:'html',attribute:'data-theme',value:'dark'});
      await p.getByRole('radio',{name:'Sombre',exact:true}).click(); sample.independentThemeMs=await duration(p);
      await p.keyboard.press('Tab'); await capture(p,'preferences-wait-1440-dark-keyboard');
    }
    if(delay===15000 && surface==='access') { await capture(p,'access-wait-1440-light'); sample.independentAction='NON_MESURÉ: modal active; measured theme action on preferences instead'; }
    if(fault==='account') await p.evaluate(()=>(window as any).q.switchAccount());
    if(surface==='access') {
      verifyMetadataOnly(await p.evaluate(()=>sessionStorage.getItem('drivy-gestion-demandes-v1')));
      const expectedVerdict: AccessVerdict = fault === 'lost' || fault === 'refused' || fault === 'account' ? fault : 'confirmed';
      await waitForAccessVerdict(p, expectedVerdict);
      if(fault === 'refused') await p.getByText('Modification refusée',{exact:true}).waitFor();
      if(fault === 'account') await p.getByRole('dialog').waitFor({state:'hidden'});
      const q=await p.evaluate(()=>(window as any).q);
      assert.equal(q.metadataViolations,0,'every persisted write contains valid metadata only');
      if(fault !== 'storage') assert(q.metadataCheckedEntries > 0,'non-empty metadata actually checked');
      sample.expectedVerdict=expectedVerdict; sample.verdict='PASS';
      sample.metadataChecks=q.metadataChecks; sample.metadataCheckedEntries=q.metadataCheckedEntries; sample.metadataViolations=q.metadataViolations;
      if(expectedVerdict === 'confirmed') assert.equal(q.confirmed,true,'positive confirmation required');
      sample.transportResponseMs=q.events.find((e:any)=>['write-response','response-lost'].includes(e.name)).at-start;
      sample.confirmed=q.confirmed; sample.metadata=q.metadata; sample.events=q.events;
      const confirmed=q.events.find((e:any)=>e.name==='store-confirmed'); sample.confirmedMs=confirmed?confirmed.at-start:'NON_MESURÉ: aucune confirmation';
      const local=q.events.find((e:any)=>e.name==='metadata-saved'&&e.at>=start); sample.metadataMs=local ? local.at-start:'NON_MESURÉ: écriture des métadonnées refusée';
      if(['lost','refused','account'].includes(fault)) assert.equal(q.confirmed,false,'no false confirmed');
      if(fault==='lost') {
        await p.getByRole('button',{name:'Vérifier le résultat',exact:true}).waitFor();
        await arm(p,'section[aria-label="Demandes en cours"] button','click',{selector:'body',text:'Le résultat de la demande est confirmé.'});
        await p.getByRole('button',{name:'Vérifier le résultat',exact:true}).click(); sample.reconciliationMs=await duration(p); await waitForAccessVerdict(p,'confirmed'); sample.reconciledConfirmed=true;
      }
      if(fault==='storage') await p.getByText(/Le suivi local n’a pas pu/).waitFor();
      if(fault==='reread') { await p.getByText('Actualisation impossible',{exact:true}).waitFor(); sample.readFailedAfterRealConfirmation=true; }
      if(repeat===0 && ['refused','storage'].includes(fault)) {
        await p.setViewportSize({width:390,height:844}); await p.evaluate(()=>{document.documentElement.dataset.theme='dark';}); await p.keyboard.press('Tab'); await capture(p,`access-${fault}-390-dark-keyboard`);
      }
    } else {
      await p.getByText('Préférences synchronisées.',{exact:true}).waitFor({timeout:22000});
      sample.confirmedObservedMs=await p.evaluate(()=>performance.now())-start; sample.confirmedTimingLimit='DOM observed after Playwright wait: upper bound, includes driver overhead';
    }
    if(surface==='access') { const finalStorage=await p.evaluate(()=>({checks:(window as any).q.metadataChecks,violations:(window as any).q.metadataViolations})); assert.equal(finalStorage.violations,0,'metadata verified through recovery'); sample.finalMetadataChecks=finalStorage.checks; }
    assert.deepEqual(errors,[]); results.samples.push(sample); console.log(JSON.stringify({surface,delay,repeat,fault,feedbackMs})); await p.close(); await flush();
  }
  results.summaries=Object.fromEntries(['entry','access','preferences'].flatMap(surface=>delays.map(delay=>[`${surface}/${delay}`,summarize(results.samples.filter((s:any)=>s.surface===surface&&s.delay===delay&&!s.fault&&!s.warmup).map((s:any)=>s.feedbackMs))])));
  results.metricSummaries = {};
  for(const sample of results.samples.filter((s:any)=>!s.warmup)) for(const key of ['feedbackMs','metadataMs','confirmedMs','confirmedObservedMs','transportResponseMs','convergenceMs','reconciliationMs','independentThemeMs']) { if(typeof sample[key] !== 'number') continue; const group=sample.surface+'/'+sample.delay+'/'+(sample.fault||'normal')+'/'+key; (results.metricSummaries[group] ??= []).push(sample[key]); }
  for(const key in results.metricSummaries) results.metricSummaries[key]=summarize(results.metricSummaries[key]);
  results.completed=true;
} catch(error) { results.completed=false; results.error=String(error); throw error; }
finally { await flush(); await browser?.close(); await app?.close(); await new Promise<void>((done,reject)=>server.httpServer.close(error=>error?reject(error):done())); }
