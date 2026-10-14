/** Suite de la recette synthétique : Formations et tarifs dans le build réel (OIDC, BFF, API, PostgreSQL isolés). */
import {randomUUID} from 'node:crypto';
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

export async function verifySchoolFormations(options:FormationsOptions):Promise<void> {
  try {await run(options);}
  catch(error) {
    // Diagnostic local explicite : capture de la page synthétique au moment de l'échec, jamais en CI.
    if(process.env.DRIVY_E2E_DEBUG==='1'&&!process.env.CI)await options.page.screenshot({path:resolve(options.artifactDirectory,'99-formations-echec-synthetic.png'),fullPage:true}).catch(()=>undefined);
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
    (SELECT status FROM drivy.school WHERE id=$1) AS status`,[schoolId])).rows[0] as Record<string,number|string>;
  const existing=(await administration.query(`SELECT t.id AS training,t.offering_id,l.id AS lesson,l.price_cents_snapshot,l.commercial_selection,l.policy_version_id
    FROM drivy.training t JOIN drivy.lesson l ON l.training_id=t.id WHERE t.school_id=$1 AND l.status='PLANNED' ORDER BY l.created_at LIMIT 1`,[schoolId])).rows[0];
  if(!existing)throw new Error('FORMATIONS_FIRST_LESSON_MISSING');

  setStage('formations : liste des permis puis fiche du permis B');
  await page.setViewportSize({width:1440,height:1000});
  await page.goto(`${schoolPath}/formations`);await page.getByRole('heading',{name:'Formations et tarifs',exact:true}).waitFor();
  const documentOrigin=await page.evaluate(()=>performance.timeOrigin);
  await page.getByRole('link',{name:'Permis B',exact:true}).click();
  await page.getByRole('heading',{level:1,name:'Permis B'}).waitFor();
  assert(new URL(page.url()).searchParams.get('category')==='B'&&await page.evaluate(()=>performance.timeOrigin)===documentOrigin,'Permis B s’ouvre directement dans sa fiche, sans catalogue intermédiaire');
  const tabs=page.getByRole('navigation',{name:'Rubriques du permis B'});
  for(const name of ['Général','Compétences','Déroulement et annulation','Tarifs'])await tabs.getByRole('link',{name,exact:true}).waitFor();
  assert(true,'La fiche présente Général, Compétences, Déroulement et annulation et Tarifs');
  await page.screenshot({path:resolve(artifactDirectory,'09-formation-fiche-synthetic.png'),fullPage:true});

  setStage('formations : modification des compétences sur place, clavier compris');
  const before=await counts(),initial=await sheet('B');
  await tabs.getByRole('link',{name:'Compétences',exact:true}).click();
  await page.getByRole('heading',{name:'Compétences',exact:true}).waitFor();
  await page.getByRole('button',{name:'Modifier les compétences',exact:true}).click();
  await page.getByRole('button',{name:'Ajouter une compétence',exact:true}).click();
  const count=initial.programmes[0]!.curriculum!.competencies.length;
  const added=page.locator('.competency-row').nth(count);
  await added.getByLabel(`Compétence ${count+1}`,{exact:true}).fill('Conduite de nuit');
  await added.locator('textarea').fill('Adapter sa conduite à l’obscurité et à l’éblouissement.');
  const up=page.getByRole('button',{name:'Monter Conduite de nuit',exact:true});await up.focus();await page.keyboard.press('Enter');
  assert(await page.evaluate(()=>document.activeElement?.getAttribute('aria-label')?.includes('Conduite de nuit')),'Le déplacement au clavier garde le focus sur la compétence déplacée');
  setStage('formations : changer de rubrique conserve la saisie en cours');
  await tabs.getByRole('link',{name:'Tarifs',exact:true}).click();await page.getByRole('heading',{name:'Tarifs',exact:true}).waitFor();
  assert(await tabs.getByRole('link',{name:/Compétences.*modification en cours/}).count()===1,'La rubrique Compétences signale la modification en cours');
  await tabs.getByRole('link',{name:/Compétences/}).click();
  assert(await page.getByLabel(`Compétence ${count}`,{exact:true}).inputValue()==='Conduite de nuit','Revenir à Compétences retrouve la saisie non enregistrée, dans l’ordre choisi');
  assert(await page.evaluate(()=>localStorage.length)===0,'Aucune saisie n’est placée dans le stockage local');
  await page.getByRole('button',{name:'Enregistrer les compétences',exact:true}).click();
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
  await tabs.getByRole('link',{name:'Tarifs',exact:true}).click();await page.getByRole('heading',{name:'Tarifs',exact:true}).waitFor();
  await page.getByRole('button',{name:'Ajouter un tarif',exact:true}).click();
  await page.getByLabel('Nom du tarif',{exact:true}).fill('Leçon de 90 minutes');
  await page.getByLabel('Durée (minutes)',{exact:true}).fill('90');
  await page.getByLabel('Prix (CHF)',{exact:true}).fill('170');
  await page.getByLabel('Conditions commerciales',{exact:true}).fill('Tarif synthétique de 90 minutes, réservé à cette recette.');
  const tariffEndpoint=`${bff}/formations/tariffs`;let writes=0,lostOperation='',lostStatus=0;
  await page.route(tariffEndpoint,async route=>{
    if(route.request().method()!=='POST'){await route.continue();return;}
    writes++;if(writes!==1){await route.continue();return;}
    lostOperation=route.request().headers()['idempotency-key']??'';const committed=await route.fetch();lostStatus=committed.status();await route.abort('failed');
  });
  await page.getByRole('button',{name:'Ajouter le tarif',exact:true}).click();
  await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor();
  assert(lostStatus===201&&z.uuid().safeParse(lostOperation).success,'Le tarif est durable avant la perte de la réponse');
  assert(await page.getByRole('button',{name:'Ajouter le tarif',exact:true}).isDisabled(),'Le formulaire reste visible et bloqué tant que le résultat est inconnu');
  const recovery=page.waitForResponse(response=>new URL(response.url()).pathname===`/app/bff/schools/${schoolId}/operations/${lostOperation}`);
  await page.getByRole('button',{name:'Vérifier auprès de l’école',exact:true}).click();const recovered=await recovery;
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
  await page.getByRole('button',{name:`Modifier ${lessonTariff.head.label}`,exact:true}).click();
  await page.getByLabel('Prix (CHF)',{exact:true}).fill('99');
  const concurrent=await page.evaluate(async({path,body})=>{
    const session=await (await fetch('/app/bff/session',{credentials:'same-origin'})).json() as {csrfToken:string};
    const response=await fetch(path,{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':session.csrfToken,'Idempotency-Key':body.operationId},body:JSON.stringify(body)});
    return response.status;
  },{path:`/app/bff/schools/${schoolId}/formations/tariffs`,body:{operationId:randomUUID(),mode:'UPDATE',productKey:lessonTariff.productKey,expectedProductVersionId:lessonTariff.head.id,
    type:'INDIVIDUAL_LESSON',label:lessonTariff.head.label,durationMinutes:50,unitLabel:'leçon',priceCents:9800,validUntil:null,enabled:true,terms:{mode:'KEEP'}}});
  assert(concurrent===201,'Une autre session enregistre d’abord un prix de 98 CHF');
  await page.getByRole('button',{name:'Enregistrer le tarif',exact:true}).click();
  await page.getByText(/Ce tarif a été modifié entre-temps/).first().waitFor();
  assert(await page.getByLabel('Prix (CHF)',{exact:true}).inputValue()==='99','Le conflit conserve la saisie, sans écraser la version concurrente');
  await page.getByRole('button',{name:'Recharger la fiche',exact:true}).click();
  await page.getByText('Ce tarif a changé pendant votre modification',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Enregistrer le tarif',exact:true}).click();
  await page.getByText('Le tarif est enregistré. Les réservations existantes gardent leur prix et leurs conditions.',{exact:true}).waitFor();
  const prices=(await administration.query('SELECT version,unit_price_cents FROM drivy.service_product_version WHERE school_id=$1 AND product_key=$2 ORDER BY version',[schoolId,lessonTariff.productKey])).rows;
  assert(JSON.stringify(prices.map(row=>Number(row.unit_price_cents)))==='[9500,9800,9900]','Les deux modifications sont conservées comme versions successives, sans écrasement silencieux');
  const lesson=(await administration.query('SELECT price_cents_snapshot,commercial_selection,policy_version_id FROM drivy.lesson WHERE id=$1',[existing.lesson])).rows[0];
  assert(Number(lesson.price_cents_snapshot)===Number(existing.price_cents_snapshot)&&JSON.stringify(lesson.commercial_selection)===JSON.stringify(existing.commercial_selection)
    &&lesson.policy_version_id===existing.policy_version_id,'La réservation existante garde son prix, ses conditions et sa procédure photographiés');

  setStage('formations : assistant de création du permis A');
  await page.getByRole('link',{name:'Formations et tarifs',exact:true}).first().click();
  await page.getByRole('heading',{name:'Formations et tarifs',exact:true}).waitFor();
  await page.getByRole('link',{name:'Ajouter une formation',exact:true}).click();
  await page.getByRole('heading',{name:'Permis',exact:true,level:1}).waitFor();
  await page.getByLabel('Permis',{exact:true}).click();
  await page.getByRole('combobox',{name:'Rechercher : Permis',exact:true}).fill('A');
  await page.getByRole('option',{name:'Permis A',exact:true}).click();
  await page.getByRole('button',{name:'Continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Compétences et règles',exact:true,level:1}).waitFor();
  assert(await page.getByText('Proposition Drivy à relire',{exact:true}).count()===1,'Les modèles Drivy sont présentés comme une proposition à relire, pas comme un texte adopté');
  await page.getByRole('button',{name:'Continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Premier tarif',exact:true,level:1}).waitFor();
  assert(await page.getByLabel('Prix (CHF)',{exact:true}).inputValue()==='','Le prix n’est jamais prérempli');
  await page.getByLabel('Nom du tarif',{exact:true}).fill('Leçon moto 50 minutes');
  await page.getByLabel('Durée (minutes)',{exact:true}).fill('50');
  await page.getByRole('button',{name:'Continuer',exact:true}).click();
  assert(await page.getByLabel('Prix (CHF)',{exact:true}).getAttribute('aria-invalid')==='true','Un prix absent bloque l’étape, sans être remplacé par zéro');
  await page.getByLabel('Prix (CHF)',{exact:true}).fill('110');
  await page.getByRole('button',{name:'Continuer',exact:true}).click();
  await page.getByRole('heading',{name:'Vérification',exact:true,level:1}).waitFor();
  const beforeCreation=await counts();
  await page.getByRole('button',{name:'Créer la formation',exact:true}).click();
  await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  await page.getByText('La formation du permis A est créée.',{exact:true}).waitFor();
  const created=await sheet('A'),afterCreation=await counts();
  assert(created.programmes.length===1&&created.tariffs.length===1&&created.tariffs[0]!.head.unitPriceCents===11000&&afterCreation.notices===beforeCreation.notices
    &&afterCreation.profiles===beforeCreation.profiles&&afterCreation.status==='ACTIVE','La création enregistre programme, règles et premier tarif sans réadopter les textes ni réactiver l’école');
  await page.reload();await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  assert(true,'Le permis créé se relit après rechargement');

  setStage('formations : ancienne adresse d’une version précédente, historique et navigation');
  await page.goto(`${schoolPath}/offres?selection=${existing.offering_id}&category=B&from=formations`);
  await page.getByRole('heading',{level:1,name:'Permis B'}).waitFor();
  await page.getByText('Version précédente',{exact:true}).first().waitFor();
  const target=new URL(page.url());
  assert(target.pathname.endsWith('/formations')&&target.searchParams.get('view')==='historique'&&target.searchParams.get('selection')===existing.offering_id,
    'Une ancienne URL retrouve la version exacte demandée, sans redirection silencieuse vers la dernière');
  await page.goBack();await page.getByRole('heading',{level:1,name:'Permis A'}).waitFor();
  await page.goForward();await page.getByRole('heading',{level:1,name:'Permis B'}).waitFor();
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
