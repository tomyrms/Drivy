import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,issuer,type Call} from './support/harness.js';
import {observationThemes} from '../src/observation-themes.js';

/** R08 (#465, #466, #467) : politique de l'école, préférences du compte, palette effective. Base PostgreSQL réelle. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
const prefs='/observation-preferences',themes='/observation-themes',prefsB=`/v1/schools/${id.schoolB}/observation-preferences`,themesB=`/v1/schools/${id.schoolB}/observation-themes`;
const defaults=observationThemes.map(theme=>({key:theme.key as string,visible:theme.defaultVisible as boolean}));
const manual=defaults.filter(theme=>theme.visible).map(theme=>theme.key);
const save=(body:Record<string,unknown>={})=>({operationId:randomUUID(),...body});
/** Ordre manuel complet (18 clés) avec `head` en tête. */
const order=(head:string)=>[head,...defaults.map(theme=>theme.key).filter(key=>key!==head)];
/** Visibilité complète (18 clés) : celle d'origine, avec les thèmes de `hide` masqués et ceux de `show` affichés. */
const vis=(hide:string[]=[],show:string[]=[])=>defaults.map(theme=>({key:theme.key,visible:show.includes(theme.key)?true:hide.includes(theme.key)?false:theme.visible}));
/** Configuration de l'école (corps de /observation-themes) : `head` en tête, avec masquages et affichages. */
const arrangement=(head:string,hide:string[]=[],show:string[]=[])=>order(head).map(key=>({key,visible:vis(hide,show).find(item=>item.key===key)!.visible}));
const rows=async()=>(await pool.query('SELECT count(*)::int AS n FROM drivy.person_observation_preference')).rows[0].n as number;
const stored=async(person:string)=>(await pool.query('SELECT version,theme_order,hidden_themes,mode,ranked_order,learning_generation FROM drivy.person_observation_preference WHERE person_id=$1',[person])).rows[0];
const keysOf=(data:{themes:{key:string}[]})=>data.themes.map(theme=>theme.key);
const current=async(route=prefs,subject?:string)=>(await call('GET',route,undefined,null,subject)).json().data;
let validate:{envelope:(value:unknown)=>boolean;save:(value:unknown)=>boolean;reset:(value:unknown)=>boolean;legacy:(value:unknown)=>boolean;school:(value:unknown)=>boolean;schoolCommand:(value:unknown)=>boolean;errors:()=>string};

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);
 const contract=JSON.parse(await readFile(new URL('../contracts/observation-preferences.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 const compile=(name:string)=>ajv.compile({$ref:`${contract.$id}#/$defs/${name}`});
 const compiled={envelope:compile('Envelope'),save:compile('SaveCommand'),reset:compile('ResetCommand'),legacy:compile('LegacyRanking'),school:compile('SchoolThemes'),schoolCommand:compile('SchoolThemesCommand')};
 let last=compiled.envelope;
 const wrap=(name:keyof typeof compiled)=>(value:unknown)=>{last=compiled[name];return compiled[name](value) as boolean;};
 validate={envelope:wrap('envelope'),save:wrap('save'),reset:wrap('reset'),legacy:wrap('legacy'),school:wrap('school'),schoolCommand:wrap('schoolCommand'),errors:()=>JSON.stringify(last.errors)};
});
afterAll(async()=>{await app?.close();await pool?.end();});

describe('compte sans préférence',()=>{
 it('rend la configuration de l’école, version 1, sans ligne en base ; le contrat est respecté',async()=>{
  const read=await call('GET',prefs);expect(read.statusCode,read.body).toBe(200);
  const data=read.json().data;
  expect(data).toMatchObject({id:id.instructor,schoolId:id.schoolA,version:1,personalizationAllowed:false,orderCustomized:false,visibilityCustomized:false,mode:'MANUAL',rankedOn:null,learning:{generation:0,since:null},adoption:null});
  expect(data.palette).toEqual(manual);expect(data.themes).toHaveLength(18);expect(read.headers.etag).toBe('"1"');
  // Chaque thème porte sa visibilité effective, celle de l'école et le droit de la modifier.
  expect(data.themes.every((theme:{visible:boolean;schoolVisible:boolean;visibilityEditable:boolean})=>theme.visible===theme.schoolVisible&&theme.visibilityEditable===false)).toBe(true);
  expect(validate.envelope(read.json()),validate.errors()).toBe(true);
  expect(await rows()).toBe(0);
  // L'administrateur de l'école a lui aussi son propre compte.
  expect((await call('GET',prefs,undefined,null,'demo-admin')).json().data).toMatchObject({id:id.admin,version:1});
 });
 it('refuse la lecture et l’écriture à un élève et à un compte étranger',async()=>{
  for(const subject of ['demo-alice','demo-foreign']){
   expect((await call('GET',prefs,undefined,null,subject)).statusCode).toBe(403);
   expect((await call('PUT',prefs,save({mode:'SMART'}),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
   expect((await call('PUT',prefs,save({order:order('speed')}),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
   expect((await call('POST',`${prefs}/learning-reset`,save(),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
   expect((await call('POST',`${prefs}/presentation-reset`,save(),1,subject)).statusCode).toBeGreaterThanOrEqual(403);
  }
  expect(await rows()).toBe(0);
 });
});

describe('visibilité imposée par l’école (état de toutes les écoles existantes)',()=>{
 it('l’ordre personnel est accepté ; la palette suit cet ordre, filtré par la visibilité de l’école',async()=>{
  const body=save({order:order('speed')});expect(validate.save(body),validate.errors()).toBe(true);
  const saved=await call('PUT',prefs,body,1);expect(saved.statusCode,saved.body).toBe(200);
  const data=saved.json().data;
  expect(data).toMatchObject({version:2,orderCustomized:true,visibilityCustomized:false,personalizationAllowed:false,mode:'MANUAL'});
  expect(data.palette[0]).toBe('speed');expect(data.palette).toHaveLength(manual.length);expect(new Set(data.palette)).toEqual(new Set(manual));
  expect(keysOf(data)).toEqual(order('speed'));
  expect(data.themes.every((theme:{visible:boolean;schoolVisible:boolean;visibilityEditable:boolean})=>theme.visible===theme.schoolVisible&&theme.visibilityEditable===false)).toBe(true);
  expect(validate.envelope(saved.json()),validate.errors()).toBe(true);
  // Aucune visibilité personnelle n'a été créée.
  expect((await stored(id.instructor)).hidden_themes).toBeNull();
  // L'administrateur règle lui aussi l'ordre de son propre compte, sans pouvoir changer sa visibilité ici.
  const admin=await call('PUT',prefs,save({order:order('observation')}),1,'demo-admin');expect(admin.statusCode,admin.body).toBe(200);expect(admin.json().data.palette[0]).toBe('observation');
  expect((await call('PUT',prefs,save({visibility:vis(['motorway'])}),2,'demo-admin')).json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
 });
 it('la visibilité personnelle est refusée, seule ou avec l’ordre, sans rien écrire',async()=>{
  for(const body of [save({visibility:vis(['motorway'],['braking'])}),save({order:order('signage'),visibility:vis(['motorway'])}),save({mode:'SMART',visibility:vis(['motorway'])})]){
   const refused=await call('PUT',prefs,body,2);expect(refused.statusCode,refused.body).toBe(403);expect(refused.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  }
  const after=await stored(id.instructor);expect(after.version).toBe(2);expect(after.theme_order[0]).toBe('speed');expect(after.hidden_themes).toBeNull();
 });
 it('le mode intelligent classe l’ordre personnel ; le classement du compte porte sur le catalogue complet',async()=>{
  const saved=await call('PUT',prefs,save({mode:'SMART'}),2);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({version:3,mode:'SMART',visibilityCustomized:false});
  expect(new Set(saved.json().data.palette)).toEqual(new Set(manual));expect(saved.json().data.rankedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  expect((await stored(id.instructor)).ranked_order).toHaveLength(18);
  const back=await call('PUT',prefs,save({mode:'MANUAL'}),3);expect(back.statusCode,back.body).toBe(200);expect(back.json().data).toMatchObject({version:4,mode:'MANUAL',rankedOn:null});
  expect(back.json().data.palette[0]).toBe('speed');
 });
});

describe('visibilité personnalisable',()=>{
 it('seul l’administrateur ouvre la politique ; un moniteur ne le peut pas',async()=>{
  const before=await current(themes,'demo-admin');expect(before).toMatchObject({personalizationAllowed:false,canManage:true,version:1});
  const body=save({themes:defaults,personalizationAllowed:true});
  expect((await call('PUT',themes,body,1)).statusCode).toBe(403);
  const opened=await call('PUT',themes,body,1,'demo-admin');expect(opened.statusCode,opened.body).toBe(200);
  expect(opened.json().data).toMatchObject({version:2,personalizationAllowed:true});
  expect(validate.school(opened.json().data),validate.errors()).toBe(true);expect(validate.schoolCommand(body),validate.errors()).toBe(true);
  // Le moniteur voit la politique sans pouvoir la gérer.
  expect(await current(themes)).toMatchObject({personalizationAllowed:true,canManage:false});
 });
 it('le moniteur enregistre sa visibilité ; son ordre est conservé ; la configuration de l’école n’est pas touchée',async()=>{
  const before=await current(themes),body=save({visibility:vis(['motorway'],['braking'])});
  expect(validate.save(body),validate.errors()).toBe(true);
  const saved=await call('PUT',prefs,body,4);expect(saved.statusCode,saved.body).toBe(200);
  const data=saved.json().data;expect(data).toMatchObject({version:5,orderCustomized:true,visibilityCustomized:true,mode:'MANUAL',personalizationAllowed:true});
  expect(data.palette[0]).toBe('speed');expect(data.palette).toContain('braking');expect(data.palette).not.toContain('motorway');
  const braking=data.themes.find((theme:{key:string})=>theme.key==='braking');
  expect(braking).toMatchObject({visible:true,schoolVisible:false,visibilityEditable:true});
  expect(data.themes.find((theme:{key:string})=>theme.key==='motorway')).toMatchObject({visible:false,schoolVisible:true});
  expect(saved.headers.etag).toBe('"5"');expect(validate.envelope(saved.json()),validate.errors()).toBe(true);
  // La palette est calculée : l'école garde sa référence, et chaque lecture rend le même résultat.
  expect(await current(themes)).toEqual(before);expect(await current()).toEqual(data);
  // Un collègue qui n'a rien enregistré suit la référence de l'école ; l'administrateur n'a que son ordre.
  expect(await current(prefs,'demo-other-instructor')).toMatchObject({orderCustomized:false,visibilityCustomized:false,version:1,palette:manual});
  expect(await current(prefs,'demo-admin')).toMatchObject({orderCustomized:true,visibilityCustomized:false,version:2});
 });
 it('version, idempotence, preuve, audit et corps invalides',async()=>{
  const body=save({order:order('observation'),visibility:vis(['motorway'],['braking'])}),saved=await call('PUT',prefs,body,5);expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.version).toBe(6);
  // Rejeu : même réponse, aucune seconde écriture ; un autre contenu sous la même opération est refusé.
  const replay=await call('PUT',prefs,body,5);expect(replay.statusCode,replay.body).toBe(200);expect(replay.json().data.version).toBe(6);
  expect((await call('PUT',prefs,{...body,mode:'SMART'},5)).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await call('PUT',prefs,save({order:order('signage')}),5)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',prefs,save({order:order('signage')}),null)).statusCode).toBe(428);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_PRESENTATION',resourceType:'ObservationPreferences',resourceId:id.instructor,resourceVersion:6});
  expect((await pool.query('SELECT action,changed_fields FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationPresentationSaved',changed_fields:['order','visibility']}]);
  // La preuve appartient à son auteur.
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-other-instructor')).statusCode).toBeGreaterThanOrEqual(403);
  const bad=[save({}),save({order:order('speed').slice(1)}),save({order:[order('speed')[0],...order('speed').slice(0,17)]}),save({order:['unknown',...order('speed').slice(1)]}),
   save({visibility:vis().map(item=>({...item,visible:false}))}),save({visibility:vis().slice(1)}),save({themes:arrangement('speed')}),save({mode:'AUTO'}),save({mode:'SMART',order:manual}),{mode:'SMART'}];
  for(const invalid of bad)expect((await call('PUT',prefs,invalid as never,6)).statusCode,JSON.stringify(invalid)).toBe(400);
  expect((await current()).version).toBe(6);
 });
 it('l’ordre et la visibilité se règlent séparément : l’un n’écrase pas l’autre',async()=>{
  const before=await stored(id.instructor);
  const orderOnly=await call('PUT',prefs,save({order:order('signage')}),6);expect(orderOnly.statusCode,orderOnly.body).toBe(200);
  const afterOrder=await stored(id.instructor);expect(afterOrder.theme_order[0]).toBe('signage');expect(afterOrder.hidden_themes).toEqual(before.hidden_themes);
  const visibilityOnly=await call('PUT',prefs,save({visibility:vis(['motorway'],['braking'])}),7);expect(visibilityOnly.statusCode,visibilityOnly.body).toBe(200);
  const afterVisibility=await stored(id.instructor);expect(afterVisibility.theme_order).toEqual(afterOrder.theme_order);expect(afterVisibility.hidden_themes).toEqual(before.hidden_themes);
 });
 it('deux enregistrements concurrents de la même version : un seul passe',async()=>{
  const writes=await Promise.all([call('PUT',prefs,save({order:order('braking')}),8),call('PUT',prefs,save({order:order('signage')}),8)]);
  expect(writes.map(response=>response.statusCode).sort()).toEqual([200,412]);expect((await current()).version).toBe(9);
 });
 it('le compte est commun à ses écoles : même ordre dans l’école B, visibilité de l’école si elle l’impose',async()=>{
  const mine=await current();
  const imposed=await call('GET',prefsB);expect(imposed.statusCode,imposed.body).toBe(200);
  const onB=imposed.json().data;
  expect(onB).toMatchObject({id:id.instructor,schoolId:id.schoolB,version:mine.version,personalizationAllowed:false,orderCustomized:true,visibilityCustomized:false});
  // Même ordre personnel, filtré par la visibilité de l'école B (référence d'origine) : « Autoroute » revient, « Freinage » reste masqué.
  expect(onB.palette).toEqual(keysOf(mine).filter(key=>manual.includes(key)));expect(onB.palette).toContain('motorway');expect(onB.palette).not.toContain('braking');
  expect(keysOf(onB)).toEqual(keysOf(mine));
  expect((await call('GET',prefsB,undefined,null,'demo-admin')).statusCode).toBe(403);
  // Le moniteur de A est administrateur de B : il ouvre la politique de B, où sa visibilité personnelle s'applique alors.
  expect((await current(themesB)).canManage).toBe(true);
  const opened=await call('PUT',themesB,save({themes:defaults,personalizationAllowed:true}),1);expect(opened.statusCode,opened.body).toBe(200);
  const shared=await current(prefsB);expect(shared).toMatchObject({schoolId:id.schoolB,version:mine.version,orderCustomized:true,visibilityCustomized:true,palette:mine.palette});
  expect(await rows()).toBe(2);
  // Écrire depuis l'école B change le compte, donc aussi l'école A.
  const fromB=await call('PUT',prefsB,save({order:order('anticipation')}),mine.version);expect(fromB.statusCode,fromB.body).toBe(200);
  const afterB=await current();expect(afterB).toMatchObject({version:mine.version+1,orderCustomized:true});expect(afterB.palette[0]).toBe('anticipation');
  // Même une école qui ne connaît pas la personne comme moniteur ne la lit pas.
  expect((await call('GET',prefsB,undefined,null,'demo-other-instructor')).statusCode).toBe(403);
 });
});

/** Corps de /observation-themes qui conserve la configuration actuelle de l'école, avec la politique voulue. */
const schoolBody=async(personalizationAllowed:boolean,extra:{themes?:{key:string;visible:boolean}[]}={})=>save({themes:extra.themes??(await current(themes,'demo-admin')).themes.map((theme:{key:string;visible:boolean})=>({key:theme.key,visible:theme.visible})),personalizationAllowed});
const putSchool=async(body:Record<string,unknown>)=>call('PUT',themes,body,(await current(themes,'demo-admin')).version,'demo-admin');

describe('libre, puis imposé, puis libre',()=>{
 it('conserve la visibilité personnelle ; l’ordre reste modifiable pendant la phase imposée',async()=>{
  const base=await stored(id.instructor),hiddenBefore=base.hidden_themes as string[];
  const closed=await putSchool(await schoolBody(false));expect(closed.statusCode,closed.body).toBe(200);
  const imposed=await current();
  expect(imposed).toMatchObject({personalizationAllowed:false,visibilityCustomized:false,orderCustomized:true,version:base.version});
  expect(imposed.palette[0]).toBe('anticipation');expect(new Set(imposed.palette)).toEqual(new Set(manual));expect(imposed.palette).toContain('motorway');
  // L'ordre se modifie pendant la phase imposée ; la visibilité, non.
  const moved=await call('PUT',prefs,save({order:order('signage')}),imposed.version);expect(moved.statusCode,moved.body).toBe(200);expect(moved.json().data.palette[0]).toBe('signage');
  expect((await call('PUT',prefs,save({visibility:vis(['speed'])}),imposed.version+1)).json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  // La visibilité enregistrée est restée intacte, en réserve.
  expect((await stored(id.instructor)).hidden_themes).toEqual(hiddenBefore);
  const reopened=await putSchool(await schoolBody(true));expect(reopened.statusCode,reopened.body).toBe(200);
  const back=await current();
  expect(back).toMatchObject({personalizationAllowed:true,visibilityCustomized:true,orderCustomized:true});
  // Retrouvée à la réouverture, avec l'ordre choisi entre-temps.
  expect(back.palette).toEqual(order('signage').filter(key=>!hiddenBefore.includes(key)));expect(back.palette).not.toContain('motorway');
 });
});

describe('réinitialisation personnelle de la présentation',()=>{
 const refA=arrangement('right-priority',['speed'],['eco-driving']);
 const refKeys=refA.map(item=>item.key),refHidden=refA.filter(item=>!item.visible).map(item=>item.key);
 it('moniteur d’une école libre : copie la référence de l’école, sans toucher au mode ni à l’apprentissage',async()=>{
  const mode=await call('PUT',prefs,save({mode:'SMART'}),(await current()).version);expect(mode.statusCode,mode.body).toBe(200);
  const before=mode.json().data;
  const reference=await putSchool(await schoolBody(true,{themes:refA}));expect(reference.statusCode,reference.body).toBe(200);
  // Un compte qui n'a rien personnalisé suit la nouvelle référence ; le compte personnalisé, non.
  const follower=await current(prefs,'demo-other-instructor');expect(follower.palette[0]).toBe('right-priority');expect(follower.palette).not.toContain('speed');
  expect((await current()).palette).toEqual(before.palette);
  const body=save();expect(validate.reset(body)).toBe(true);
  const reset=await call('POST',`${prefs}/presentation-reset`,body,before.version);expect(reset.statusCode,reset.body).toBe(200);
  const data=reset.json().data;
  expect(data).toMatchObject({version:before.version+1,mode:'SMART',learning:before.learning,orderCustomized:true,visibilityCustomized:true,rankedOn:before.rankedOn});
  expect(keysOf(data)).toEqual(refKeys);expect(data.themes.filter((theme:{visible:boolean})=>!theme.visible).map((theme:{key:string})=>theme.key)).toEqual(refHidden);
  const row=await stored(id.instructor);expect(row.theme_order).toEqual(refKeys);expect(row.hidden_themes).toEqual(refHidden);
  // Rejeu, conflit de version, preuve et audit.
  expect((await call('POST',`${prefs}/presentation-reset`,body,before.version)).json().data.version).toBe(before.version+1);
  expect((await call('POST',`${prefs}/presentation-reset`,save(),before.version)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',`${prefs}/presentation-reset`,save(),null)).statusCode).toBe(428);
  expect((await call('POST',`${prefs}/presentation-reset`,{...body,extra:true},before.version)).statusCode).toBe(400);
  expect((await pool.query('SELECT action FROM drivy.audit_event WHERE operation_id=$1',[body.operationId])).rows).toEqual([{action:'ObservationPresentationReset'}]);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'RESET_OBSERVATION_PRESENTATION',resourceType:'ObservationPreferences',resourceId:id.instructor});
 });
 it('changer la référence de l’école ne réécrit pas un compte personnalisé',async()=>{
  const row=await stored(id.instructor);
  const changed=await putSchool(await schoolBody(true,{themes:arrangement('right-priority',['speed','signage'],['eco-driving'])}));expect(changed.statusCode,changed.body).toBe(200);
  expect(await stored(id.instructor)).toEqual(row);
  expect((await current(prefs,'demo-other-instructor')).palette).not.toContain('signage');
 });
 it('moniteur d’une école qui impose sa visibilité : refusé, rien d’écrit ; administrateur : accepté ; élève : refusé',async()=>{
  const closed=await putSchool(await schoolBody(false));expect(closed.statusCode,closed.body).toBe(200);
  const row=await stored(id.instructor);
  const refused=await call('POST',`${prefs}/presentation-reset`,save(),row.version);expect(refused.statusCode,refused.body).toBe(403);expect(refused.json().code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  expect(await stored(id.instructor)).toEqual(row);
  // L'administrateur réinitialise sa propre présentation quel que soit le mode : il copie la référence de l'école ouverte.
  const school=await current(themes,'demo-admin'),admin=await stored(id.admin);
  const reset=await call('POST',`${prefs}/presentation-reset`,save(),admin.version,'demo-admin');expect(reset.statusCode,reset.body).toBe(200);
  const copied=await stored(id.admin);expect(copied.theme_order).toEqual(school.themes.map((theme:{key:string})=>theme.key));
  expect(copied.hidden_themes).toEqual(school.themes.filter((theme:{visible:boolean})=>!theme.visible).map((theme:{key:string})=>theme.key));
  // En visibilité imposée, c'est celle de l'école qui s'applique, même après la copie.
  expect((await current(prefs,'demo-admin')).themes.every((theme:{visible:boolean;schoolVisible:boolean})=>theme.visible===theme.schoolVisible)).toBe(true);
  expect((await call('POST',`${prefs}/presentation-reset`,save(),1,'demo-alice')).statusCode).toBe(403);
 });
 it('depuis une école libre, c’est la référence de cette école qui est copiée ; l’école imposée garde sa visibilité',async()=>{
  const row=await stored(id.instructor);
  const reset=await call('POST',`${prefsB}/presentation-reset`,save(),row.version);expect(reset.statusCode,reset.body).toBe(200);
  const copied=await stored(id.instructor);expect(copied.theme_order).toEqual(defaults.map(theme=>theme.key));expect(copied.hidden_themes).toEqual(defaults.filter(theme=>!theme.visible).map(theme=>theme.key));
  const onA=await current();expect(onA).toMatchObject({personalizationAllowed:false,visibilityCustomized:false});
  expect(onA.themes.every((theme:{visible:boolean;schoolVisible:boolean})=>theme.visible===theme.schoolVisible)).toBe(true);
 });
 it('le reset scolaire de l’ADMIN remet les valeurs d’origine de l’école, sans toucher à aucun compte',async()=>{
  const accounts=async()=>(await pool.query('SELECT * FROM drivy.person_observation_preference ORDER BY person_id')).rows;
  const before=await accounts();
  // La route est PUT /observation-themes avec l'ordre et l'affichage d'origine publiés (defaultPosition, defaultVisible).
  const school=await current(themes,'demo-admin');
  const original=[...school.themes].sort((a:{defaultPosition:number},b:{defaultPosition:number})=>a.defaultPosition-b.defaultPosition).map((theme:{key:string;defaultVisible:boolean})=>({key:theme.key,visible:theme.defaultVisible}));
  expect((await call('PUT',themes,save({themes:original,personalizationAllowed:true}),school.version,'demo-other-instructor')).statusCode).toBe(403);
  const reset=await call('PUT',themes,save({themes:original,personalizationAllowed:true}),school.version,'demo-admin');expect(reset.statusCode,reset.body).toBe(200);
  expect(reset.json().data.themes.map((theme:{key:string;visible:boolean})=>[theme.key,theme.visible])).toEqual(defaults.map(theme=>[theme.key,theme.visible]));
  expect(await accounts()).toEqual(before);
 });
});

describe('droits scolaires relus côté serveur',()=>{
 it('l’ancien droit « Gérer les signalements » ne donne rien, ni sur l’école ni sur le compte d’un tiers',async()=>{
  const member=(await call('GET','/members',undefined,null,'demo-admin')).json().data.items.find((item:{id:string})=>item.id===id.otherInstructorMember);
  const granted=await call('PATCH',`/members/${id.otherInstructorMember}`,{operationId:randomUUID(),roles:member.roles,grants:['MANAGE_OBSERVATION_THEMES'],reason:'Recette'},member.version,'demo-admin');expect(granted.statusCode,granted.body).toBe(200);
  const now=await current(themes,'demo-other-instructor');expect(now.canManage).toBe(false);
  const refused=await call('PUT',themes,save({themes:defaults,personalizationAllowed:false}),now.version,'demo-other-instructor');
  expect(refused.statusCode).toBe(403);expect(refused.json().code).toBe('OBSERVATION_THEMES_ACCESS_REQUIRED');
  expect((await current(themes,'demo-other-instructor')).personalizationAllowed).toBe(true);
 });
 it('la base isole la ligne de chaque compte, et ne la montre pas depuis une école où la personne n’est pas moniteur',async()=>{
  const db=await pool.connect();
  const as=async(subject:string,person:string,school:string,run:()=>Promise<void>)=>{
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true),set_config('app.person_id',$4,true)",[issuer,subject,school,person]);
   try{await run();}finally{await db.query('ROLLBACK');}
  };
  try{
   await as('demo-instructor',id.instructor,id.schoolA,async()=>{expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([{person_id:id.instructor}]);});
   // Un collègue ne lit ni n'écrit la ligne d'un autre.
   await as('demo-other-instructor',id.otherInstructor,id.schoolA,async()=>{
    expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([]);
    expect((await db.query("UPDATE drivy.person_observation_preference SET mode='MANUAL' WHERE person_id=$1",[id.instructor])).rowCount).toBe(0);
    await expect(db.query("INSERT INTO drivy.person_observation_preference(person_id,version) VALUES($1,2)",[id.instructor])).rejects.toThrow();
   });
   // L'administration de l'école ne lit pas non plus les préférences d'un moniteur : elle ne voit que la sienne.
   await as('demo-admin',id.admin,id.schoolA,async()=>{expect((await db.query('SELECT person_id FROM drivy.person_observation_preference')).rows).toEqual([{person_id:id.admin}]);});
   // Un élève n'est jamais moniteur : même sa propre ligne n'existerait pas pour lui.
   await as('demo-alice',id.alice,id.schoolA,async()=>{
    await expect(db.query("INSERT INTO drivy.person_observation_preference(person_id,version) VALUES($1,2)",[id.alice])).rejects.toThrow(/row-level security/);
   });
  }finally{db.release();}
  // Les anciennes lignes par école ne s'écrivent plus.
  const legacy=await pool.connect();
  try{
   await legacy.query('BEGIN');await legacy.query('SET LOCAL ROLE drivy_app');
   await expect(legacy.query("UPDATE drivy.observation_ranking SET mode='MANUAL'")).rejects.toThrow(/permission denied/);
   await legacy.query('ROLLBACK');
  }finally{legacy.release();}
 });
});

describe('anciennes routes',()=>{
 it('/observation-ranking garde sa forme et écrit le compte',async()=>{
  const read=await call('GET','/observation-ranking');expect(read.statusCode,read.body).toBe(200);
  const account=await current();
  expect(read.json().data).toMatchObject({id:id.instructorMember,membershipId:id.instructorMember,schoolId:id.schoolA,version:account.version,mode:account.mode});
  expect(validate.legacy(read.json().data),validate.errors()).toBe(true);
  const off=save({mode:'MANUAL'}),saved=await call('PUT','/observation-ranking',off,account.version);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({mode:'MANUAL',order:[],rankedOn:null,version:account.version+1});
  expect(await current()).toMatchObject({mode:'MANUAL',version:account.version+1});
  expect((await call('GET',`/operations/${off.operationId}`)).json().data).toMatchObject({commandType:'SAVE_OBSERVATION_RANKING',resourceId:id.instructor});
  const on=await call('PUT','/observation-ranking',save({mode:'SMART'}),account.version+1);expect(on.json().data.mode).toBe('SMART');
  expect(on.json().data.order).toEqual((await current()).palette);expect(on.json().data.order).toHaveLength(manual.length);
  expect(await pool.query('SELECT 1 FROM drivy.observation_ranking').then(result=>result.rowCount)).toBe(0);
 });
 it('un ancien client de /observation-themes qui n’envoie pas la politique la laisse inchangée',async()=>{
  const now=await current(themes,'demo-admin');
  const saved=await call('PUT',themes,{operationId:randomUUID(),themes:defaults},now.version,'demo-admin');
  expect(saved.statusCode,saved.body).toBe(200);expect(saved.json().data.personalizationAllowed).toBe(now.personalizationAllowed);
 });
});

describe('rang noté au moment du geste',()=>{
 it('le signalement garde le rang de sa tuile dans la palette effective du compte',async()=>{
  const lesson=randomUUID();
  await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
   VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lesson,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,school.policy]);
  const account=await current();
  const saved=await call('PUT',prefs,save({order:order('motorway'),visibility:vis(),mode:'MANUAL'}),account.version);expect(saved.statusCode,saved.body).toBe(200);
  const palette=saved.json().data.palette as string[];
  const live=(themeKey:string)=>({operationId:randomUUID(),draftId:null,captureId:null,segmentId:null,pointSequence:null,competencyId:null,text:'Recette',origin:'LIVE',observedAt:new Date().toISOString(),eventKind:'QUALIFIED',eventStatus:'TO_REWORK',themeKey});
  for(const key of ['motorway','speed'])expect((await call('POST',`/lessons/${lesson}/geo-observations`,live(key))).statusCode).toBe(201);
  const rowsOf=(await pool.query('SELECT theme_key,palette_position FROM drivy.geo_observation WHERE lesson_id=$1 ORDER BY created_at,id',[lesson])).rows;
  expect(rowsOf).toEqual([{theme_key:'motorway',palette_position:1},{theme_key:'speed',palette_position:palette.indexOf('speed')+1}]);
  // Un thème que la palette n'affiche pas n'a pas de rang.
  const hidden=defaults.find(theme=>!palette.includes(theme.key))!.key;
  expect((await call('POST',`/lessons/${lesson}/geo-observations`,live(hidden))).statusCode).toBe(201);
  expect((await pool.query('SELECT palette_position FROM drivy.geo_observation WHERE lesson_id=$1 AND theme_key=$2',[lesson,hidden])).rows[0].palette_position).toBeNull();
 });
});
