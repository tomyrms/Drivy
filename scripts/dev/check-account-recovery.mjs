/** UI only, synthetic BFF. Does not send mail and does not replace the real Keycloak qualification. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5194';
assert(['localhost','127.0.0.1'].includes(new URL(origin).hostname));
const directory = resolve('docs/implementation/proofs/account-recovery-20261026');
await mkdir(directory,{recursive:true});
const browser = await chromium.launch({channel:'msedge',headless:true});
const checks = [];
try {
  for (const colorScheme of ['light','dark']) for (const available of [false,true]) {
    const width = available ? 1440 : 390;
    const context = await browser.newContext({viewport:{width,height:900},colorScheme,locale:'fr-CH'});
    let failRead = false, starts = 0;
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin !== origin) return route.abort();
      if (!url.pathname.startsWith('/app/bff/')) return route.continue();
      let body;
      if (url.pathname.endsWith('/options')) {
        if (failRead) return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({code:'SERVICE_UNAVAILABLE'})});
        body={data:{available,recoveryUrl:available?`${origin}/app/recover`:null}};
      } else if (url.pathname.endsWith('/session')) body={authenticated:false,csrfToken:'synthetic-only',invitationPending:false};
      else if (url.pathname.endsWith('/start')) { starts++; return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({code:'ACCOUNT_RECOVERY_UNAVAILABLE'})}); }
      else return route.fulfill({status:404,body:'{}'});
      return route.fulfill({contentType:'application/json',body:JSON.stringify(body)});
    });
    const page = await context.newPage(), errors=[];
    page.on('pageerror',error=>errors.push(error.name));
    await page.goto(`${origin}/app/recover`);
    const expected = available ? page.getByRole('button',{name:'Récupérer mon accès',exact:true})
      : page.getByText('L’envoi du lien de récupération n’est pas encore disponible.',{exact:true});
    await expected.waitFor();
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    await page.screenshot({path:resolve(directory,`recovery-${available?'available':'unavailable'}-${colorScheme}.png`),fullPage:true});
    if (available) {
      await expected.click();
      await page.getByText('La récupération est momentanément indisponible.',{exact:true}).waitFor();
      assert.equal(starts,1);
      await page.getByRole('button',{name:'Réessayer',exact:true}).click(); await expected.waitFor();
    }
    failRead=true; await page.reload();
    await page.getByText('La récupération est momentanément indisponible.',{exact:true}).waitFor();
    failRead=false; await page.getByRole('button',{name:'Réessayer',exact:true}).click(); await expected.waitFor();
    assert.deepEqual(errors,[]); checks.push({available,colorScheme,width,passed:true});
    await context.close();
  }
  await writeFile(resolve(directory,'browser-results.json'),JSON.stringify({scope:'Edge, UI réelle, BFF synthétique; aucun courrier ni fournisseur d’identité',checks},null,2));
  console.log(`${checks.length} recovery UI cases passed`);
} finally { await browser.close(); }
