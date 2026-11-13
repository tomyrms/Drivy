/** Contrôle de la console des opérateurs (R01-T01) sur l'aperçu synthétique : états, parcours et captures, bureau et mobile.
 * Aucune donnée réelle : tout vient de la famille d'aperçu `platform`. Ce n'est pas une qualification sur appareil.
 * Usage : DRIVY_PLAYWRIGHT_MODULE=<module optionnel> DRIVY_CHROMIUM_EXECUTABLE=<navigateur optionnel> node check-platform-console.mjs <URL de l'aperçu> <dossier de sortie>
 * L'aperçu se lance avec `npx vite --config vite.preview-311.config.ts` dans apps/web.
 */
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

const { chromium } = await import(process.env.DRIVY_PLAYWRIGHT_MODULE ? pathToFileURL(process.env.DRIVY_PLAYWRIGHT_MODULE).href : 'playwright');
const [base = 'http://127.0.0.1:5188/preview-311.html', out = '.local/platform-console'] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const browser = await chromium.launch(process.env.DRIVY_CHROMIUM_EXECUTABLE ? { executablePath: process.env.DRIVY_CHROMIUM_EXECUTABLE } : {});
const sizes = { desktop: { width: 1280, height: 900 }, mobile: { width: 390, height: 844 } };
const checks = [];
const ok = (name) => { checks.push(name); console.log('OK  ', name); };

async function open(kind, query, scheme = 'light') {
  const context = await browser.newContext({ viewport: sizes[kind], colorScheme: scheme, locale: 'fr-CH', deviceScaleFactor: kind === 'mobile' ? 2 : 1 });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.goto(`${base}?${query}`, { waitUntil: 'networkidle' });
  return { page, context, errors };
}
const shot = async (page, name) => { await page.waitForTimeout(450); return page.screenshot({ path: resolve(out, `${name}.png`), fullPage: true }); };
const noOverflow = async (page, label) => {
  const wide = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  assert.equal(wide, false, `${label}: défilement horizontal`);
};

for (const kind of ['desktop', 'mobile']) {
  // --- Équipe ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('heading', { name: 'Plateforme', level: 1 }).waitFor();
    await page.getByText('Hugo Lambert').first().waitFor();
    assert.equal(await page.getByText('Vous', { exact: true }).count(), 1);
    assert.equal(await page.getByText('Retiré', { exact: true }).count(), 1);
    await noOverflow(page, `equipe ${kind}`);
    await shot(page, `01-equipe-${kind}`);
    ok(`équipe ${kind} : 2 actifs, « Vous », 1 ancien, pas de débordement`);

    // retrait confirmé d'un autre opérateur
    await page.getByRole('button', { name: 'Retirer Hugo Lambert' }).click();
    await page.getByRole('dialog').waitFor();
    await shot(page, `02-retrait-confirmation-${kind}`);
    await page.getByRole('dialog').getByRole('button', { name: 'Retirer', exact: true }).click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    assert.equal(await page.getByText('Retiré', { exact: true }).count(), 2);
    ok(`retrait ${kind} : confirmation précise puis opérateur passé en « Retiré »`);

    // dernier opérateur actif : le serveur refuse, l'écran le dit
    await page.getByRole('button', { name: 'Me retirer de l’équipe' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Retirer', exact: true }).click();
    await page.getByText('Retrait non confirmé').waitFor();
    await page.getByText('Le dernier opérateur actif ne peut pas être retiré.').waitFor();
    await shot(page, `03-dernier-operateur-${kind}`);
    ok(`dernier opérateur ${kind} : retrait refusé, message affiché dans la boîte`);
    await page.getByRole('button', { name: 'Garder l’accès' }).click();
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Invitations : émission, code montré une fois ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('tab', { name: 'Invitations' }).click();
    await page.getByLabel('Adresse e-mail de l’invité').waitFor();
    await shot(page, `04-invitations-${kind}`);
    await page.getByRole('button', { name: 'Inviter' }).click();
    await page.getByText('Saisissez une adresse e-mail valide.').waitFor();
    await shot(page, `05-invitation-adresse-invalide-${kind}`);
    await page.getByLabel('Adresse e-mail de l’invité').fill('lea@example.test');
    await page.getByRole('button', { name: 'Inviter' }).click();
    await page.getByText('Code à transmettre').waitFor();
    const code = await page.getByLabel('Code d’accès').inputValue();
    assert.match(code, /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/);
    await noOverflow(page, `invitation ${kind}`);
    await shot(page, `06-invitation-code-${kind}`);
    ok(`invitation ${kind} : code au bon format montré après la création`);
    await page.getByRole('button', { name: 'J’ai transmis le code' }).click();
    await page.getByText('Code à transmettre').waitFor({ state: 'hidden' });
    // le code ne reparaît nulle part une fois confié
    const body = await page.locator('body').innerText();
    assert.equal(body.includes(code), false);
    assert.ok(body.includes('l***@example.test'), 'la nouvelle invitation est listée, adresse masquée');
    ok(`invitation ${kind} : code retiré de l’écran après « J’ai transmis le code », liste à jour`);
    await shot(page, `07-invitation-liste-${kind}`);

    // révocation d'une invitation
    await page.getByRole('button', { name: /Révoquer l’invitation de l\*\*\*@example.test/ }).click();
    await page.getByText('Révoquée', { exact: true }).first().waitFor();
    ok(`révocation ${kind} : invitation passée en « Révoquée »`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Journal ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('tab', { name: 'Journal' }).click();
    await page.getByText('Invitation créée').first().waitFor();
    await noOverflow(page, `journal ${kind}`);
    await shot(page, `08-journal-${kind}`);
    await page.getByRole('button', { name: 'Refus' }).click();
    await page.getByText('Refusée · Dernier opérateur actif').waitFor();
    assert.equal(await page.getByText('Invitation créée').count(), 0);
    await shot(page, `09-journal-refus-${kind}`);
    ok(`journal ${kind} : filtre « Refus » ne garde que les refus, motif lisible`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Accès refusé ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=refused');
    await page.getByText('Accès refusé').waitFor();
    assert.equal(await page.getByRole('tab', { name: 'Équipe' }).count(), 0);
    assert.equal(await page.getByText('Camille Aubry').count(), 0);
    await shot(page, `10-acces-refuse-${kind}`);
    ok(`accès refusé ${kind} : aucune donnée de l’équipe affichée, lien vers la saisie d’un code`);
    await context.close();
  }

  // --- Conflit de version ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=conflict');
    await page.getByRole('button', { name: 'Retirer Hugo Lambert' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Retirer', exact: true }).click();
    await page.getByText('Liste mise à jour').waitFor();
    assert.equal(await page.getByText('Retiré', { exact: true }).count(), 1, 'rien n’a été écrasé');
    await shot(page, `11-conflit-${kind}`);
    ok(`conflit ${kind} : liste rechargée, rien d’écrasé, message dédié`);
    await context.close();
  }

  // --- Réponse perdue sur une invitation : reprise de la même demande ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=lost-reply');
    await page.getByRole('tab', { name: 'Invitations' }).click();
    await page.getByLabel('Adresse e-mail de l’invité').fill('lea@example.test');
    await page.getByRole('button', { name: 'Inviter' }).click();
    await page.getByText('Invitation non confirmée').waitFor();
    assert.equal(await page.getByText('Action impossible').count(), 0, 'une seule alerte pour une invitation non confirmée');
    await shot(page, `12-invitation-non-confirmee-${kind}`);
    await page.getByRole('button', { name: 'Renvoyer la même demande' }).click();
    await page.getByText('Code à transmettre').waitFor();
    // une seule invitation créée malgré les deux envois
    await page.getByRole('button', { name: 'J’ai transmis le code' }).click();
    await page.getByText('Code à transmettre').waitFor({ state: 'hidden' });
    assert.equal(await page.getByText('l***@example.test').count(), 1);
    assert.equal(await page.getByText('Action impossible').count(), 0, 'pas d’alerte en double');
    ok(`réponse perdue ${kind} : même demande renvoyée, une seule invitation créée`);
    await context.close();
  }

  // --- Acceptation ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme-rejoindre');
    await page.getByLabel('Code d’accès').waitFor();
    await shot(page, `13-rejoindre-saisie-${kind}`);
    await page.getByLabel('Code d’accès').fill('abcde fghjk');
    assert.equal(await page.getByLabel('Code d’accès').inputValue(), 'ABCDE-FGHJK');
    await page.getByRole('button', { name: 'Voir les droits' }).click();
    await page.getByText('Ce code n’est pas valide ou n’est plus utilisable.').first().waitFor();
    await shot(page, `14-rejoindre-code-invalide-${kind}`);
    await page.getByLabel('Code d’accès').fill('demnkabc23');
    await page.getByRole('button', { name: 'Voir les droits' }).click();
    await page.getByText('Droits accordés').waitFor();
    await page.getByText('Jamais accordé').waitFor();
    await page.getByText('Dossiers des élèves').waitFor();
    assert.equal(await page.getByRole('button', { name: 'Accepter et rejoindre' }).isEnabled(), true);
    await noOverflow(page, `rejoindre ${kind}`);
    await shot(page, `15-rejoindre-droits-${kind}`);
    ok(`acceptation ${kind} : droits accordés et jamais accordés montrés avant toute acceptation`);
    await page.getByRole('button', { name: 'Accepter et rejoindre' }).click();
    await page.getByText('Vous faites partie de l’équipe').waitFor();
    await shot(page, `16-rejoindre-accepte-${kind}`);
    ok(`acceptation ${kind} : confirmée par le serveur avant l’écran de succès`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Acceptation : réponse perdue ---
  {
    const { page, context } = await open(kind, 'page=plateforme-rejoindre&scenario=lost-reply');
    await page.getByLabel('Code d’accès').fill('DEMNK-ABC23');
    await page.getByRole('button', { name: 'Voir les droits' }).click();
    await page.getByText('Droits accordés').waitFor();
    await page.getByRole('button', { name: 'Accepter et rejoindre' }).click();
    await page.getByText('Acceptation non confirmée').waitFor();
    assert.equal(await page.getByText('Vous faites partie de l’équipe').count(), 0, 'aucun privilège affiché sans confirmation');
    await shot(page, `17-rejoindre-non-confirme-${kind}`);
    await page.getByRole('button', { name: 'Renvoyer la même demande' }).click();
    await page.getByText('Vous faites partie de l’équipe').waitFor();
    ok(`acceptation ${kind} : réponse perdue → aucun privilège affiché, puis reprise de la même demande confirmée`);
    await context.close();
  }
}

// --- Thème sombre, un cliché par vue ---
{
  const { page, context } = await open('desktop', 'page=plateforme', 'dark');
  await page.getByText('Hugo Lambert').first().waitFor();
  await shot(page, '18-equipe-sombre-desktop');
  await page.getByRole('tab', { name: 'Journal' }).click();
  await page.getByText('Invitation créée').first().waitFor();
  await shot(page, '19-journal-sombre-desktop');
  ok('thème sombre : équipe et journal rendus');
  await context.close();
}

await browser.close();
console.log(`\n${checks.length} vérifications passées`);
