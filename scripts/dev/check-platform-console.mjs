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

const openingCode = /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;
const schoolRows = (page) => page.getByRole('list', { name: 'Écoles clientes' }).getByRole('listitem');
const search = async (page, text) => {
  await page.getByLabel('Rechercher une école', { exact: true }).fill(text);
  await page.getByRole('button', { name: 'Rechercher', exact: true }).click();
};
const filter = (page, name) => page.getByRole('button', { name, exact: true }).click();

for (const kind of ['desktop', 'mobile']) {
  // --- Écoles : annuaire, recherche, filtres, pagination ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('heading', { name: 'Plateforme', level: 1 }).waitFor();
    assert.equal(await page.getByRole('tab', { name: 'Écoles', exact: true }).getAttribute('aria-selected'), 'true', 'la console s’ouvre sur les écoles');
    await page.getByText('Auto-école Jura').first().waitFor();
    assert.equal(await schoolRows(page).count(), 25);
    await page.getByText('25 sur 45 écoles').waitFor();
    await noOverflow(page, `annuaire ${kind}`);
    await shot(page, `20-annuaire-${kind}`);
    ok(`annuaire ${kind} : la console s’ouvre sur les écoles, première page de 25 sur 45, pas de débordement`);

    await page.getByRole('button', { name: 'Afficher plus', exact: true }).click();
    await page.getByText('45 sur 45 écoles').waitFor();
    assert.equal(await schoolRows(page).count(), 45);
    assert.equal(await page.getByRole('button', { name: 'Afficher plus', exact: true }).count(), 0);
    await shot(page, `21-annuaire-complet-${kind}`);
    ok(`pagination ${kind} : « Afficher plus » charge la suite, 45 écoles sans doublon, plus de bouton au bout`);

    await search(page, 'leman');
    await page.getByText('1 sur 1 école').waitFor();
    assert.equal(await schoolRows(page).count(), 1);
    await shot(page, `22-recherche-${kind}`);
    await search(page, 'zzz');
    await page.getByText('Aucune école trouvée').waitFor();
    ok(`recherche ${kind} : sans accent ni casse, résultat unique puis état vide dédié`);

    await search(page, '');
    for (const [name, total] of [['En attente', 16], ['En préparation', 14], ['Actives', 14], ['Archivées', 1]]) {
      await filter(page, name);
      await page.getByText(`${total} sur ${total} ${total > 1 ? 'écoles' : 'école'}`).waitFor();
      assert.equal(await page.getByRole('button', { name, exact: true }).getAttribute('aria-pressed'), 'true');
    }
    await filter(page, 'En préparation');
    await page.getByText('14 sur 14 écoles').waitFor();
    await shot(page, `23-filtre-preparation-${kind}`);
    await filter(page, 'Toutes');
    await page.getByText('25 sur 45 écoles').waitFor();
    ok(`filtres ${kind} : en attente 16, en préparation 14, actives 14, archivées 1, retour à toutes`);

    // un code expiré ou révoqué est l'inhabituel : seul lui porte un badge
    await search(page, 'gruy');
    await page.getByText('Code expiré', { exact: true }).waitFor();
    await search(page, 'saleve');
    await page.getByText('Code révoqué', { exact: true }).waitFor();
    assert.equal(await page.getByText('Code expiré', { exact: true }).count(), 0);
    ok(`annuaire ${kind} : badge seulement pour un code expiré ou révoqué`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Écoles : fiche, contenu autorisé, modification ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await search(page, 'leman');
    await page.getByRole('button', { name: /Auto-école du Léman/ }).click();
    await page.getByRole('button', { name: 'Enregistrer', exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Enregistrer', exact: true }).isDisabled(), true, 'rien à enregistrer sans modification');
    const facts = await page.locator('dl.platform-facts').innerText();
    for (const expected of ['École', 'Préparation terminée', 'Ouverte avec un code', 'Offre', 'Non configurée', 'Échéances', 'Aucune'])
      assert.ok(facts.includes(expected), `la fiche montre « ${expected} »`);
    assert.equal(/élève|trajet|message|dossier/i.test(facts), false, 'aucun contenu pédagogique dans la fiche');
    assert.equal(await page.getByLabel('Contact commercial', { exact: true }).inputValue(), 'Sophie Rochat');
    assert.equal(await page.getByLabel('Rue', { exact: true }).inputValue(), 'Rue du Lac 12');
    await noOverflow(page, `fiche ${kind}`);
    await shot(page, `24-fiche-${kind}`);
    ok(`fiche ${kind} : école, contact, préparation, ouverture, offre et échéances réservées, aucun contenu pédagogique`);

    await page.getByLabel('E-mail du contact', { exact: true }).fill('pas-un-email');
    await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
    await page.getByText('Saisissez une adresse e-mail valide.').waitFor();
    await shot(page, `25-fiche-email-invalide-${kind}`);
    await page.getByLabel('E-mail du contact', { exact: true }).fill('sophie@example.test');
    await page.getByLabel('Contact commercial', { exact: true }).fill('Sophie Rochat-Martin');
    await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
    await page.waitForFunction(() => [...document.querySelectorAll('button')].some(button => button.textContent === 'Enregistrer' && button.disabled));
    assert.equal(await page.getByLabel('Contact commercial', { exact: true }).inputValue(), 'Sophie Rochat-Martin');
    ok(`fiche ${kind} : adresse invalide signalée, modification enregistrée sans autre saisie obligatoire`);

    await page.getByRole('button', { name: 'Écoles', exact: true }).click();
    await page.getByRole('list', { name: 'Écoles clientes' }).waitFor();
    assert.equal(await page.getByLabel('Contact commercial', { exact: true }).count(), 0);
    await page.getByRole('tab', { name: 'Journal' }).click();
    await page.getByText('Fiche modifiée').first().waitFor();
    ok(`journal ${kind} : la modification de la fiche est au journal commercial`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Écoles : « Créer un code », copie, code montré une seule fois ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.getByText('Auto-école Jura').first().waitFor();
    await page.getByRole('button', { name: 'Créer un code', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('heading', { name: 'Créer un code' }).waitFor();
    await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
    await dialog.getByText('Saisissez le nom de l’école.').waitFor();
    await shot(page, `26-code-nom-requis-${kind}`);
    await dialog.getByLabel('Nom de l’école', { exact: true }).fill('Auto-école Test');
    await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
    await dialog.getByText('Code à transmettre').waitFor();
    const code = await dialog.getByLabel('Code d’ouverture', { exact: true }).inputValue();
    const link = await dialog.getByLabel('Lien d’ouverture', { exact: true }).inputValue();
    assert.match(code, openingCode);
    assert.ok(link.endsWith(`/app/ouvrir#token=${code}`), 'le lien porte le code après le #');
    await noOverflow(page, `code ${kind}`);
    await shot(page, `27-code-cree-${kind}`);
    ok(`code ${kind} : le nom suffit, code au bon format montré avec son lien d’ouverture`);

    await dialog.getByRole('button', { name: 'Copier le code', exact: true }).click();
    await dialog.getByText('Code copié.').waitFor();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), code);
    await dialog.getByRole('button', { name: 'Copier le lien', exact: true }).click();
    await dialog.getByText('Lien copié.').waitFor();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), link);
    ok(`code ${kind} : copie manuelle du code puis du lien, confirmées`);

    await dialog.getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    const body = await page.locator('body').innerText();
    assert.equal(body.includes(code), false, 'le code ne reparaît nulle part');
    await page.getByText('Auto-école Test').first().waitFor();
    await shot(page, `28-annuaire-apres-code-${kind}`);
    ok(`code ${kind} : retiré de l’écran une fois confié, école listée en attente avec la validité du code`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Écoles : fermer sans confier le code, puis le retrouver ---
  {
    const { page, context } = await open(kind, 'page=plateforme');
    await page.getByRole('button', { name: 'Créer un code', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Nom de l’école', { exact: true }).fill('Auto-école Reprise');
    await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
    await dialog.getByText('Code à transmettre').waitFor();
    const code = await dialog.getByLabel('Code d’ouverture', { exact: true }).inputValue();
    await dialog.getByRole('button', { name: 'Fermer', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    await page.getByText('Code non transmis', { exact: true }).waitFor();
    assert.equal((await page.locator('body').innerText()).includes(code), false, 'le code n’est pas affiché tant qu’on ne le redemande pas');
    await shot(page, `29-code-non-transmis-${kind}`);
    await page.getByRole('button', { name: 'Afficher le code', exact: true }).click();
    await page.getByRole('dialog').getByText('Code à transmettre').waitFor();
    assert.equal(await page.getByRole('dialog').getByLabel('Code d’ouverture', { exact: true }).inputValue(), code, 'le même code, pas un second');
    await page.getByRole('dialog').getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    assert.equal(await page.getByText('Code non transmis', { exact: true }).count(), 0);
    await search(page, 'reprise');
    await page.getByText('1 sur 1 école').waitFor();
    ok(`reprise ${kind} : un code non confié reste proposé, le même code revient, une seule école créée`);
    await context.close();
  }

  // --- Écoles : réponse perdue sur la création d'un code ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=lost-reply');
    await page.getByRole('button', { name: 'Créer un code', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Nom de l’école', { exact: true }).fill('Auto-école Perdue');
    await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
    await dialog.getByText('Code non confirmé').waitFor();
    assert.equal(await page.getByText('Action impossible').count(), 0, 'une seule alerte, dans la boîte');
    await shot(page, `30-code-non-confirme-${kind}`);
    await dialog.getByRole('button', { name: 'Renvoyer la même demande', exact: true }).click();
    await dialog.getByText('Code à transmettre').waitFor();
    assert.match(await dialog.getByLabel('Code d’ouverture', { exact: true }).inputValue(), openingCode);
    await dialog.getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    await search(page, 'perdue');
    await page.getByText('1 sur 1 école').waitFor();
    ok(`réponse perdue ${kind} : même demande renvoyée, un seul code et une seule école`);
    await context.close();
  }

  // --- Écoles : révoquer puis recréer depuis la fiche ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await search(page, 'jura');
    await page.getByRole('button', { name: /Auto-école Jura/ }).click();
    await page.getByRole('heading', { name: 'Codes d’ouverture' }).waitFor();
    await page.getByText('Disponible', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Créer un code', exact: true }).count(), 0, 'pas de second code tant que le premier est disponible');
    assert.equal(await page.getByRole('button', { name: 'Rattacher une école', exact: true }).count(), 0);
    await shot(page, `31-fiche-code-disponible-${kind}`);
    await page.getByRole('button', { name: /^Révoquer le code créé le/ }).click();
    await page.getByText('Révoqué', { exact: true }).waitFor();
    await shot(page, `32-fiche-code-revoque-${kind}`);
    await page.getByRole('button', { name: 'Créer un code', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByText('Auto-école Jura').waitFor();
    assert.equal(await dialog.getByLabel('Nom de l’école', { exact: true }).count(), 0, 'la fiche connaît déjà l’école');
    await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
    await dialog.getByText('Code à transmettre').waitFor();
    await dialog.getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    await page.getByText('Disponible', { exact: true }).waitFor();
    assert.equal(await page.getByText('Révoqué', { exact: true }).count(), 1);
    ok(`fiche ${kind} : code révoqué puis nouveau code depuis la fiche, ancien code conservé en « Révoqué »`);

    await page.getByRole('button', { name: 'Écoles', exact: true }).click();
    await search(page, 'gruy');
    await page.getByRole('button', { name: /Drive Gruyère/ }).click();
    await page.getByText('Expiré', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Créer un code', exact: true }).waitFor();
    await shot(page, `33-fiche-code-expire-${kind}`);
    ok(`fiche ${kind} : code expiré lisible, nouveau code possible`);
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Écoles : rattacher une école existante ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('button', { name: 'Rattacher une école', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('heading', { name: 'Rattacher une école existante' }).waitFor();
    assert.equal(await dialog.getByRole('listitem').count(), 3);
    await noOverflow(page, `rattachement ${kind}`);
    await shot(page, `34-rattacher-${kind}`);
    await dialog.getByLabel('Rechercher une école existante', { exact: true }).fill('nord');
    await dialog.getByRole('button', { name: 'Rechercher', exact: true }).click();
    await dialog.getByText('Conduite Pilote Sud').waitFor({ state: 'hidden' });
    assert.equal(await dialog.getByRole('listitem').count(), 1);
    await dialog.getByRole('button', { name: 'Rattacher Auto-école Pilote Nord', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    await page.getByRole('heading', { name: 'Auto-école Pilote Nord', level: 3 }).waitFor();
    const facts = await page.locator('dl.platform-facts').innerText();
    assert.ok(facts.includes('École existante rattachée'), 'la fiche dit que l’école existait déjà');
    assert.ok(facts.includes('Non configurée'), 'aucune offre ni échéance inventée');
    await shot(page, `35-ecole-rattachee-${kind}`);
    ok(`rattachement ${kind} : école existante rattachée à une nouvelle fiche, offre non configurée`);

    // depuis une fiche sans école : le même rattachement, sans création de fiche
    await page.getByRole('button', { name: 'Écoles', exact: true }).click();
    await search(page, 'saleve');
    await page.getByRole('button', { name: /École Salève/ }).click();
    await page.getByRole('button', { name: 'Rattacher une école', exact: true }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Rattacher Conduite Pilote Sud', exact: true }).click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    await page.getByText('École existante rattachée').first().waitFor();
    assert.equal(await page.getByRole('button', { name: 'Créer un code', exact: true }).count(), 0, 'une fiche rattachée n’émet plus de code');
    ok(`rattachement ${kind} : depuis une fiche existante, l’école rejoint cette fiche`);
    await page.getByRole('tab', { name: 'Journal' }).click();
    await page.getByText('École existante rattachée').first().waitFor();
    assert.equal(errors.length, 0, `erreurs console: ${errors.join(' | ')}`);
    await context.close();
  }

  // --- Écoles : conflit de version ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=conflict');
    await search(page, 'leman');
    await page.getByRole('button', { name: /Auto-école du Léman/ }).click();
    await page.getByLabel('Contact commercial', { exact: true }).fill('Autre contact');
    await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
    await page.getByText('Données mises à jour').waitFor();
    await shot(page, `36-fiche-conflit-${kind}`);
    ok(`conflit ${kind} : fiche relue sous la dernière version, message dédié`);
    await context.close();
  }

  // --- Équipe ---
  {
    const { page, context, errors } = await open(kind, 'page=plateforme');
    await page.getByRole('heading', { name: 'Plateforme', level: 1 }).waitFor();
    await page.getByRole('tab', { name: 'Équipe', exact: true }).click();
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
    assert.equal(await page.getByRole('tab', { name: 'Écoles' }).count(), 0);
    assert.equal(await page.getByText('Camille Aubry').count(), 0);
    assert.equal(await page.getByText('Auto-école du Léman').count(), 0);
    // Un lien de navigation est annoncé comme un lien : rôle link, pas button.
    assert.equal(await page.getByRole('link', { name: 'Saisir un code d’accès' }).count(), 1);
    assert.equal(await page.getByRole('button', { name: 'Saisir un code d’accès' }).count(), 0);
    await shot(page, `10-acces-refuse-${kind}`);
    ok(`accès refusé ${kind} : aucune donnée de l’équipe affichée, lien vers la saisie d’un code`);
    await context.close();
  }

  // --- Conflit de version ---
  {
    const { page, context } = await open(kind, 'page=plateforme&scenario=conflict');
    await page.getByRole('tab', { name: 'Équipe', exact: true }).click();
    await page.getByRole('button', { name: 'Retirer Hugo Lambert' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Retirer', exact: true }).click();
    await page.getByText('Données mises à jour').waitFor();
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
  await page.getByText('Auto-école Jura').first().waitFor();
  await shot(page, '18-ecoles-sombre-desktop');
  await search(page, 'leman');
  await page.getByRole('button', { name: /Auto-école du Léman/ }).click();
  await page.getByRole('button', { name: 'Enregistrer' }).waitFor();
  await shot(page, '18b-fiche-sombre-desktop');
  await page.getByRole('tab', { name: 'Équipe', exact: true }).click();
  await page.getByText('Hugo Lambert').first().waitFor();
  await shot(page, '18c-equipe-sombre-desktop');
  await page.getByRole('tab', { name: 'Journal' }).click();
  await page.getByText('Invitation créée').first().waitFor();
  await shot(page, '19-journal-sombre-desktop');
  ok('thème sombre : écoles, fiche, équipe et journal rendus');
  await context.close();
}

await browser.close();
console.log(`\n${checks.length} vérifications passées`);
