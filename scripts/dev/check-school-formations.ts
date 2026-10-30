/** Suite de la recette synthétique : Formations et tarifs dans le build réel (OIDC, BFF, API, PostgreSQL isolés). */
import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {Pool} from 'pg';
import {z} from 'zod';
import type {Browser} from '../../infra/dev/browser.js';

type BrowserContext=Awaited<ReturnType<Browser['newContext']>>;
type Page=Awaited<ReturnType<BrowserContext['newPage']>>;
export interface FormationsOptions {
  page:Page;consumerContext:BrowserContext;schoolId:string;origin:string;administration:Pool;artifactDirectory:string;
  assert:(value:unknown,label:string)=>void;setStage:(value:string)=>void;
}
const sheetSchema=z.object({categoryCode:z.string(),programmes:z.array(z.object({offeringKey:z.string(),head:z.object({id:z.uuid(),version:z.number()}),
  curriculum:z.object({id:z.uuid(),competencies:z.array(z.object({key:z.string(),label:z.string()}))}).nullable()})),
  tariffs:z.array(z.object({productKey:z.string(),head:z.object({id:z.uuid(),label:z.string(),unitPriceCents:z.number(),durationMinutes:z.number().nullable(),type:z.string()})}))});

/** Reproduit un rendu retardé : la personne peut choisir le champ suivant avant un callback d'animation. */
async function deferAnimationCallbacks(page:Page):Promise<()=>Promise<void>> {
  const pending=await page.evaluateHandle(()=>{
    const request=window.requestAnimationFrame.bind(window),cancel=window.cancelAnimationFrame.bind(window);
    let next=0;const callbacks=new Map<number,FrameRequestCallback>();
    window.requestAnimationFrame=callback=>{callbacks.set(++next,callback);return next;};
    window.cancelAnimationFrame=id=>{callbacks.delete(id);};
    return ()=>{window.requestAnimationFrame=request;window.cancelAnimationFrame=cancel;
      for(const callback of callbacks.values())callback(performance.now());};
  });
  let released=false;
  return async()=>{if(released)return;released=true;try{await pending.evaluate(release=>release());}finally{await pending.dispose();}};
}

export async function verifySchoolFormations(options:FormationsOptions):Promise<void> {
  let stage='formations : préparation';
  const setStage=(value:string)=>{stage=value;options.setStage(value);};
  try {await run({...options,setStage});}
  catch(error) {
    // Liste fermée : aucun message d'exception, URL, identifiant, texte saisi ou journal réseau dans l'artefact.
    const failure=error instanceof z.ZodError?'INVALID_RESPONSE_SCHEMA':error instanceof Error&&error.name==='TimeoutError'?'UI_WAIT_TIMEOUT'
      :error instanceof Error&&error.message.includes('strict mode violation')?'UI_SELECTOR_NOT_UNIQUE'
      :error instanceof Error&&['FORMATIONS_READ_FAILED','FORMATIONS_FIRST_LESSON_MISSING'].includes(error.message)?error.message:'CHECK_OR_BROWSER_FAILED';
    const ui=await options.page.evaluate(()=>({
      formationVisible:!!document.querySelector('.cat-page'),
      competencyRows:document.querySelectorAll('.cat-competency').length,
      competencyInputs:document.querySelectorAll('.cat-competency input').length,
      competencyDescriptions:document.querySelectorAll('.cat-competency textarea').length,
      invalidFields:document.querySelectorAll('[aria-invalid="true"]').length,
      alerts:document.querySelectorAll('[role="alert"]').length,
      newCompetencyHasFocus:document.activeElement?.getAttribute('aria-label')?.includes('Conduite de nuit')??false,
    })).catch(()=>null);
    await writeFile(resolve(options.artifactDirectory,'99-formations-diagnostic.json'),JSON.stringify({stage,failure,ui},null,2)).catch(()=>undefined);
    // Cette recette utilise seulement une école synthétique. Cadrer la fiche exclut compte, navigation et secrets de connexion.
    const sheet=options.page.locator('.cat-page');
    if(await sheet.count().catch(()=>0)===1)await sheet.screenshot({path:resolve(options.artifactDirectory,'99-formations-echec-synthetic.png')}).catch(()=>undefined);
    throw error;
  }
}
async function run(options:FormationsOptions):Promise<void> {
  const {page,consumerContext,schoolId,origin,administration,artifactDirectory,assert,setStage}=options;
  const schoolPath=`${origin}/app/gestion/${schoolId}`,bff=`${origin}/app/bff/schools/${schoolId}`;
  const sheet=async(category:string)=>{const response=await consumerContext.request.get(`${bff}/formations/sheet?category=${encodeURIComponent(category)}`);
    if(!response.ok())throw new Error('FORMATIONS_READ_FAILED');return sheetSchema.parse(z.object({data:z.unknown()}).parse(await response.json()).data);};
  const counts=async()=>(await administration.query(`SELECT
    (SELECT count(*)::int FROM drivy.offering_version WHERE school_id=$1) AS offerings,(SELECT count(*)::int FROM drivy.curriculum_version WHERE school_id=$1) AS curricula,
    (SELECT count(*)::int FROM drivy.school_policy_version WHERE school_id=$1) AS policies,(SELECT count(*)::int FROM drivy.service_product_version WHERE school_id=$1) AS products,
    (SELECT count(*)::int FROM drivy.school_data_policy WHERE school_id=$1) AS notices,(SELECT count(*)::int FROM drivy.profile_field_policy WHERE school_id=$1) AS profiles,
    (SELECT status FROM drivy.school WHERE id=$1) AS status`,[schoolId])).rows[0] as {
      offerings:number;curricula:number;policies:number;products:number;notices:number;profiles:number;status:string;
    };
  const existing=(await administration.query(`SELECT t.id AS training,t.offering_id,l.id AS lesson,l.price_cents_snapshot,l.commercial_selection,l.policy_version_id
    FROM drivy.training t JOIN drivy.lesson l ON l.training_id=t.id WHERE t.school_id=$1 AND l.status='PLANNED' ORDER BY l.created_at LIMIT 1`,[schoolId])).rows[0];
  if(!existing)throw new Error('FORMATIONS_FIRST_LESSON_MISSING');

  setStage('formations : liste des permis puis fiche du permis B');
  await page.setViewportSize({width:1440,height:1000});
  await page.goto(`${schoolPath}/formations`);await page.getByRole('heading',{name:'Formations',exact:true}).waitFor();
  const permits=page.getByRole('list',{name:'Permis préparés par l’école',exact:true});
  const documentOrigin=await page.evaluate(()=>performance.timeOrigin);
  await permits.getByRole('button',{name:/Permis B/}).click();
  await page.getByRole('heading',{level:1,name:'Permis B'}).waitFor();
  assert(new URL(page.url()).searchParams.get('category')==='B'&&await page.evaluate(()=>performance.timeOrigin)===documentOrigin,'Permis B s’ouvre directement dans sa fiche, sans catalogue intermédiaire');
  const tabs=page.getByRole('tablist',{name:'Rubriques du permis B',exact:true});
  for(const name of ['Général','Compétences','Règles','Tarifs'])await tabs.getByRole('tab',{name,exact:true}).waitFor();
  assert(true,'La fiche présente Général, Compétences, Règles et Tarifs');
  await page.screenshot({path:resolve(artifactDirectory,'09-formation-fiche-synthetic.png'),fullPage:true});

  setStage('formations : comptage des versions avant modification');
  const before=await counts();
  setStage('formations : lecture serveur du programme avant modification');
  const initial=await sheet('B');
  setStage('formations : ouverture de la rubrique Compétences');
  await tabs.getByRole('tab',{name:'Compétences',exact:true}).click();
  setStage('formations : affichage du titre Compétences');
  await page.getByRole('heading',{name:'Compétences',exact:true}).waitFor();
  setStage('formations : ouverture de l’éditeur de compétences');
  await page.getByRole('button',{name:'Modifier les compétences',exact:true}).click();
  setStage('formations : ajout d’une ligne de compétence');
  const count=initial.programmes[0]!.curriculum!.competencies.length;
  const added=page.locator('.cat-competency').nth(count);
  const releaseFrames=await deferAnimationCallbacks(page);
  try {
    await page.getByRole('button',{name:'Ajouter une compétence',exact:true}).click();
    setStage('formations : saisie du nom de la nouvelle compétence');
    await added.getByLabel(`Compétence ${count+1}`,{exact:true}).fill('Conduite de nuit');
    setStage('formations : saisie de la description après un rendu retardé');
    await added.locator('textarea').focus();
    await releaseFrames();
    await page.keyboard.insertText('Adapter sa conduite à l’obscurité et à l’éblouissement.');
  } finally {await releaseFrames();}
  assert(await added.getByLabel(`Compétence ${count+1}`,{exact:true}).inputValue()==='Conduite de nuit'
    &&await added.locator('textarea').inputValue()==='Adapter sa conduite à l’obscurité et à l’éblouissement.'
    &&await added.locator('textarea').evaluate(element=>document.activeElement===element),
    'L’ajout conserve chaque saisie dans son champ, sans déplacement de focus tardif');
  setStage('formations : déplacement de la compétence au clavier');
  await page.getByRole('button',{name:'Actions pour Conduite de nuit',exact:true}).focus();await page.keyboard.press('Enter');
  const up=page.getByRole('menuitem',{name:'Monter',exact:true});await up.waitFor();
  for(let step=0;step<4&&!await up.evaluate(element=>document.activeElement===element);step++)await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  setStage('formations : ordre et focus après le déplacement clavier');
  await page.waitForFunction(()=>document.activeElement?.getAttribute('aria-label')==='Actions pour Conduite de nuit');
  assert(await page.getByLabel(`Compétence ${count}`,{exact:true}).inputValue()==='Conduite de nuit','Le déplacement au clavier garde le focus sur la compétence déplacée, à la position choisie');
  setStage('formations : quitter la page protège la saisie en cours');
  assert(await tabs.count()===0,'L’édition occupe la page : aucune rubrique ne peut remplacer la saisie');
  await page.getByRole('navigation',{name:'Navigation principale',exact:true}).locator('.portal-nav-item').first().click();
  const departure=page.getByRole('dialog',{name:'Quitter sans enregistrer ?',exact:true});
  await departure.getByRole('button',{name:'Continuer la saisie',exact:true}).click();await departure.waitFor({state:'hidden'});
  assert(await page.getByLabel(`Compétence ${count}`,{exact:true}).inputValue()==='Conduite de nuit','Quitter demande confirmation ; continuer retrouve la saisie non enregistrée, dans l’ordre choisi');
  assert(await page.evaluate(()=>localStorage.length)===0,'Aucune saisie n’est placée dans le stockage local');
  await page.getByRole('button',{name:'Relire les changements',exact:true}).click();
  await page.getByRole('dialog',{name:'Enregistrer les compétences ?',exact:true}).getByRole('button',{name:'Enregistrer les compétences',exact:true}).click();
  await page.getByText('Les compétences sont enregistrées pour les nouvelles inscriptions.',{exact:true}).waitFor();
  const afterCompetencies=await counts(),edited=await sheet('B');
  assert(afterCompetencies.curricula===before.curricula+1&&afterCompetencies.offerings===before.offerings+1&&afterCompetencies.policies===before.policies,
    'Une seule opération crée la révision des compétences et la nouvelle version du parcours, sans toucher les règles');
  assert(edited.programmes[0]!.curriculum!.competencies[count-1]!.label==='Conduite de nuit'&&edited.programmes[0]!.curriculum!.competencies.slice(0,count-1).every((item,index)=>item.key===initial.programmes[0]!.curriculum!.competencies[index]!.key),
    'Les compétences reprises gardent leur identifiant ; la nouvelle reçoit le sien, à la position choisie');
  const keptTraining=(await administration.query('SELECT offering_id FROM drivy.training WHERE id=$1',[existing.training])).rows[0];
  assert(keptTraining.offering_id===existing.offering_id&&existing.offering_id!==edited.programmes[0]!.head.id,'L’élève déjà inscrit garde la version pédagogique de son inscription');
  await page.reload();await page.getByRole('heading',{name:'Compétences',exact:true}).waitFor();
  await page.getByText('Conduite de nuit',{exact:true}).waitFor();
  assert(new URL(page.url()).searchParams.get('view')==='competences','Après rechargement, la même rubrique relit exactement les compétences confirmées');

  setStage('formations : ajout d’un tarif, réponse perdue après commit et reçu AP72');
  await tabs.getByRole('tab',{name:'Tarifs',exact:true}).click();await page.getByRole('heading',{name:'Tarifs',exact:true}).waitFor();
  await page.getByRole('button',{name:'Ajouter un tarif',exact:true}).click();
  await page.getByLabel('Nom du tarif',{exact:true}).fill('Leçon de 90 minutes');
  await page.getByLabel('Durée (minutes)',{exact:true}).fill('90');
  await page.getByLabel('Prix (CHF)',{exact:true}).fill('170');
  await page.getByRole('button',{name:'Autres options',exact:true}).click();
  await page.getByLabel('Conditions commerciales',{exact:true}).fill('Tarif synthétique de 90 minutes, réservé à cette recette.');
  const tariffEndpoint=`${bff}/formations/tariffs`;let writes=0,lostOperation='',lostStatus=0;
  await page.route(tariffEndpoint,async route=>{
    if(route.request().method()!=='POST'){await route.continue();return;}
    writes++;if(writes!==1){await route.continue();return;}
    lostOperation=route.request().headers()['idempotency-key']??'';const committed=await route.fetch();lostStatus=committed.status();await route.abort('failed');
  });
  await page.getByRole('button',{name:'Relire les changements',exact:true}).click();
  await page.getByRole('dialog',{name:'Ajouter ce tarif ?',exact:true}).getByRole('button',{name:'Ajouter le tarif',exact:true}).click();
  const requests=page.getByRole('region',{name:'Demandes en cours',exact:true});
  await requests.getByText('Résultat à vérifier',{exact:true}).waitFor();
  assert(lostStatus===201&&z.uuid().safeParse(lostOperation).success,'Le tarif est durable avant la perte de la réponse');
  assert(await page.getByRole('button',{name:'Relire les changements',exact:true}).isDisabled()&&await page.getByLabel('Prix (CHF)',{exact:true}).inputValue()==='170',
    'Le formulaire reste visible, avec sa saisie, et bloqué tant que le résultat est inconnu');
  const recovery=page.waitForResponse(response=>new URL(response.url()).pathname===`/app/bff/schools/${schoolId}/operations/${lostOperation}`);
  await requests.getByRole('button',{name:'Vérifier le résultat',exact:true}).click();const recovered=await recovery;
  const receipt=z.object({data:z.object({operationId:z.uuid(),commandType:z.literal('SAVE_TARIFF'),resourceType:z.literal('ServiceProductVersion'),resourceId:z.uuid()})}).parse(await recovered.json()).data;
  await page.getByText('Leçon de 90 minutes',{exact:true}).waitFor();
  const afterTariff=await counts();
  assert(receipt.operationId===lostOperation&&writes===1&&afterTariff.products===afterCompetencies.products+1&&afterTariff.offerings===afterCompetencies.offerings
    &&afterTariff.notices===before.notices&&afterTariff.profiles===before.profiles&&afterTariff.status==='ACTIVE',
    'AP72 confirme un seul tarif, sans nouvelle formation ni texte scolaire réadopté');
  await page.unroute(tariffEndpoint);
  await page.screenshot({path:resolve(artifactDirectory,'10-formation-tarifs-synthetic.png'),fullPage:true});

  setStage('formations : modification du prix concurrente puis conflit explicite');
  const lessonTariff=(await sheet('B')).tariffs.find(item=>item.head.unitPriceCents===9500&&item.head.durationMinutes===50)!;
  await page.getByRole('button',{name:`Ouvrir le tarif ${lessonTariff.head.label}`,exact:true}).click();
  const releaseTariffFrames=await deferAnimationCallbacks(page);
  const priceInput=page.getByLabel('Prix (CHF)',{exact:true});
  try {
    await page.getByRole('button',{name:'Modifier le tarif',exact:true}).click();
    await priceInput.focus();await page.keyboard.press('ControlOrMeta+A');
    await releaseTariffFrames();
    await page.keyboard.insertText('99');
  } finally {await releaseTariffFrames();}
  assert(await priceInput.inputValue()==='99'
    &&await page.getByLabel('Nom du tarif',{exact:true}).inputValue()===lessonTariff.head.label
    &&await priceInput.evaluate(element=>document.activeElement===element),
    'L’ouverture du tarif conserve la saisie et le focus dans le prix malgré un rendu retardé');
  const concurrent=await page.evaluate(async({path,body})=>{
    const session=await (await fetch('/app/bff/session',{credentials:'same-origin'})).json() as {csrfToken:string};
    const response=await fetch(path,{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':session.csrfToken,'Idempotency-Key':body.operationId},body:JSON.stringify(body)});
    return response.status;
  },{path:`/app/bff/schools/${schoolId}/formations/tariffs`,body:{operationId:randomUUID(),mode:'UPDATE',productKey:lessonTariff.productKey,expectedProductVersionId:lessonTariff.head.id,
    type:'INDIVIDUAL_LESSON',label:lessonTariff.head.label,durationMinutes:50,unitLabel:'leçon',priceCents:9800,validUntil:null,enabled:true,terms:{mode:'KEEP'}}});
  assert(concurrent===201,'Une autre session enregistre d’abord un prix de 98 CHF');
  const priceReview=page.getByRole('dialog',{name:'Enregistrer ces changements ?',exact:true});
  await page.getByRole('button',{name:'Relire les changements',exact:true}).click();
  await priceReview.getByRole('button',{name:'Enregistrer le tarif',exact:true}).click();
  await page.getByText(/Ce tarif a été modifié entre-temps/).first().waitFor();
  await page.getByText('Ce tarif a changé pendant votre modification',{exact:true}).waitFor();
  assert(await page.getByLabel('Prix (CHF)',{exact:true}).inputValue()==='99','Le conflit relit la fiche et conserve la saisie, sans écraser la version concurrente');
  await page.getByRole('button',{name:'Relire les changements',exact:true}).click();
  await priceReview.getByText(/Les réservations déjà confirmées gardent leur prix et leurs conditions\./).waitFor();
  await priceReview.getByRole('button',{name:'Enregistrer le tarif',exact:true}).click();
  await page.getByText('Le tarif est enregistré.',{exact:true}).waitFor();
  const prices=(await administration.query('SELECT version,unit_price_cents FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 ORDER BY version',[schoolId,lessonTariff.productKey])).rows;
  assert(JSON.stringify(prices.map(row=>Number(row.unit_price_cents)))==='[9500,9800,9900]','Les deux modifications sont conservées comme versions successives, sans écrasement silencieux');
  const lesson=(await administration.query('SELECT price_cents_snapshot,commercial_selection,policy_version_id FROM drivy.lesson WHERE id=$1',[existing.lesson])).rows[0];
  assert(Number(lesson.price_cents_snapshot)===Number(existing.price_cents_snapshot)&&JSON.stringify(lesson.commercial_selection)===JSON.stringify(existing.commercial_selection)
    &&lesson.policy_version_id===existing.policy_version_id,'La réservation existante garde son prix, ses conditions et sa procédure photographiés');

  setStage('formations : guide unique de création du permis A');
  await page.goto(`${schoolPath}/formations`);await page.getByRole('heading',{name:'Formations',exact:true}).waitFor();
  await page.getByRole('button',{name:'Préparer un permis',exact:true}).click();
  await page.getByRole('heading',{name:'Préparer une formation',exact:true,level:1}).waitFor();
  await page.getByRole('heading',{name:'Permis enseignés',exact:true}).waitFor();
  await page.getByRole('button',{name:'Permis A',exact:true}).click();
  await page.getByRole('button',{name:'Référence du programme',exact:true}).click();
  const reference=page.locator('.setup-reference');
  assert(await reference.getByText(/^Proposition Drivy · /).isVisible()
    &&await reference.getByText('À relire par l’école ; ce programme ne certifie pas les prérequis de l’élève.',{exact:true}).isVisible(),
    'Les modèles Drivy sont présentés comme une proposition à relire, pas comme un texte adopté');
  await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Prix et règles de l’école',exact:true}).waitFor();
  assert(await page.getByLabel('Prix de la leçon',{exact:true}).inputValue()==='','Le prix n’est jamais prérempli');
  await page.getByLabel('Durée',{exact:true}).fill('50');
  await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Vérifier la formation',exact:true}).waitFor();
  assert(await page.getByRole('button',{name:'Confirmer la préparation',exact:true}).isDisabled(),'Un prix absent bloque la confirmation, sans être remplacé par zéro');
  await page.getByRole('button',{name:'Saisissez le prix réel de la leçon.',exact:true}).click();
  await page.waitForFunction(()=>document.activeElement?.getAttribute('name')==='formations.0.priceCents');
  assert(await page.getByLabel('Prix de la leçon',{exact:true}).getAttribute('aria-invalid')==='true','L’erreur de prix retrouve le champ exact et lui associe son explication');
  await page.getByLabel('Prix de la leçon',{exact:true}).fill('110');
  await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Vérifier la formation',exact:true}).waitFor();
  const beforeCreation=await counts();
  const acknowledgement=page.getByLabel('J’ai relu les formations et tarifs sélectionnés. Je confirme leur mise à disposition.',{exact:true});
  await acknowledgement.waitFor();
  assert(!(await acknowledgement.isChecked())&&beforeCreation.offerings===afterCompetencies.offerings,'La formation reste un brouillon sans confirmation précochée ni publication anticipée');
  await acknowledgement.check();await page.getByRole('button',{name:'Confirmer la préparation',exact:true}).click();
  await page.getByRole('heading',{name:'Formations',exact:true}).waitFor();
  await permits.getByRole('button',{name:/Permis A/}).click();
  await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  const created=await sheet('A'),afterCreation=await counts();
  assert(created.programmes.length===1&&created.tariffs.length===1&&created.tariffs[0]!.head.unitPriceCents===11000&&afterCreation.notices===beforeCreation.notices
    &&afterCreation.profiles===beforeCreation.profiles&&afterCreation.status==='ACTIVE','La création enregistre programme, règles et premier tarif sans réadopter les textes ni réactiver l’école');
  await page.reload();await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  assert(true,'Le permis créé se relit après rechargement');

  setStage('formations : ancienne adresse d’une version précédente, historique et navigation');
  await page.goto(`${schoolPath}/offres?selection=${existing.offering_id}&category=B&from=formations`);
  await page.getByRole('heading',{level:1,name:'Historique'}).waitFor();
  await page.getByText('Version précédente',{exact:true}).first().waitFor();
  const target=new URL(page.url());
  assert(target.pathname.endsWith('/formations')&&target.searchParams.get('view')==='historique'&&target.searchParams.get('selection')===existing.offering_id,
    'Une ancienne URL retrouve la version exacte demandée, sans redirection silencieuse vers la dernière');
  await page.goBack();await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  await page.goForward();await page.getByRole('heading',{level:1,name:'Historique'}).waitFor();
  assert(true,'Précédent et suivant traversent la fiche et l’historique');

  setStage('formations : petit écran et thème sombre');
  await page.setViewportSize({width:390,height:844});await page.goto(`${schoolPath}/formations?category=B&view=tarifs`);
  await page.getByRole('heading',{name:'Tarifs',exact:true}).waitFor();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'La fiche ne déborde pas horizontalement à 390 pixels');
  await page.screenshot({path:resolve(artifactDirectory,'11-formation-mobile-synthetic.png'),fullPage:true});
  await page.emulateMedia({colorScheme:'dark'});await page.setViewportSize({width:1024,height:900});await page.reload();
  await page.getByRole('heading',{name:'Tarifs',exact:true}).waitFor();
  await page.screenshot({path:resolve(artifactDirectory,'12-formation-sombre-synthetic.png'),fullPage:true});
  await page.emulateMedia({colorScheme:'light'});await page.setViewportSize({width:1440,height:1100});
}
