import { useEffect,useRef,useState } from 'react';
import { z } from 'zod';
import * as c from '../server/profile-contract';
import { errorMessage,okSchema,request,RequestFailure,type Member } from './protocol';

const labels:Record<c.Field,string>={firstName:'Prénom',lastName:'Nom',birthDate:'Date de naissance',postalAddress:'Adresse postale',contactEmail:'E-mail de contact',contactPhone:'Téléphone de contact',profilePhotoDocumentId:'Photo de profil'};
const stages={JOIN:'À l’entrée dans l’école',BEFORE_LESSON:'Avant une leçon',BEFORE_COURSE:'Avant un cours',OPTIONAL:'Facultatif'};
const purposes={IDENTIFICATION:'Identification',LESSON_CONTACT:'Contact pour les leçons',COURSE_ELIGIBILITY:'Admissibilité aux cours',CERTIFICATE:'Attestation',POSTAL_CONTACT:'Contact postal',PERSONALISATION:'Personnalisation'};
const requirements={REQUIRED:'Requis au stade indiqué',CONDITIONAL:'Selon l’action demandée',OPTIONAL:'Facultatif'};
const initialRules:c.FieldRule[]=[
  {field:'firstName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identifier l’élève dans les documents de cette école.'},
  {field:'lastName',requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identifier l’élève dans les documents de cette école.'}
];
const message=(error:unknown)=>{
  if(!(error instanceof RequestFailure))return errorMessage(error);
  const text:Record<string,string>={PROFILE_POLICY_NOT_READY:'L’école doit publier sa politique de champs avant de compléter les profils.',PROFILE_POLICY_CHANGED:'La politique a changé. Relisez les informations de l’école avant de préparer une nouvelle demande.',
    PROFILE_FORM_INVALID:'Vérifiez les champs modifiés : noms non vides, e-mail valide et adresse complète lorsqu’elle est renseignée.',
    VERSION_CONFLICT:'Le dossier a été modifié. Votre demande n’a pas remplacé ces changements. Rechargez et comparez les informations avant de recommencer.',
    PROFILE_SCOPE_CHANGED:'Vos accès à cette école ont changé. Cette demande ne peut pas être renvoyée avec les anciens accès.',PROFILE_FIELD_FORBIDDEN:'Un champ de cette demande n’est pas modifiable avec vos accès actuels.',
    PROFILE_COMMAND_PENDING:'Une demande préparée ou incertaine doit être examinée avant d’en préparer une autre.',PROFILE_CONFIRMATION_CHANGED:'Cette confirmation a changé dans une autre page. Retrouvez la demande avant de continuer.'};
  return text[error.code]??errorMessage(error);
};
const profileSchema=c.profileView;
export function SchoolWorkspace({member,csrf,onClose,onDirty}:{member:Member;csrf:string;onClose:()=>void;onDirty:(dirty:boolean)=>void}) {
  const [school,setSchool]=useState<z.infer<typeof c.scopeSchool>|null>(null);
  const [learners,setLearners]=useState<z.infer<typeof c.learner>[]>([]);
  const [cursor,setCursor]=useState<string|null>(null);
  const [policies,setPolicies]=useState<c.Policy[]>([]);
  const [policyCursor,setPolicyCursor]=useState<string|null>(null);
  const [notice,setNotice]=useState<z.infer<typeof c.notice>|null>(null);
  const [tab,setTab]=useState<'learners'|'policy'>('learners');
  const [detail,setDetail]=useState<z.infer<typeof profileSchema>|null>(null);
  const [draft,setDraft]=useState<Record<string,string>>({});
  const [dirty,setDirty]=useState(false);
  const [rules,setRules]=useState<c.FieldRule[]>(initialRules);
  const [effective,setEffective]=useState('');
  const [impact,setImpact]=useState(false);
  const [intent,setIntent]=useState<c.IntentView|null>(null);
  const [confirmation,setConfirmation]=useState(false);
  const [busy,setBusy]=useState(true);
  const [error,setError]=useState<string|null>(null);
  const [success,setSuccess]=useState<string|null>(null);
  const generation=useRef(0);const active=useRef(false);const dirtyRef=useRef(false);
  const base=`schools/${member.schoolId}`;
  const editing=dirty||!!intent && !['COMMITTED','REJECTED'].includes(intent.state);
  useEffect(()=>{dirtyRef.current=editing;onDirty(editing);return()=>onDirty(false);},[editing,onDirty]);
  useEffect(()=>{
    const leave=(event:BeforeUnloadEvent)=>{if(dirtyRef.current){event.preventDefault();event.returnValue='';}};
    window.addEventListener('beforeunload',leave);return()=>window.removeEventListener('beforeunload',leave);
  },[]);
  const drop=()=>{setSchool(null);setDetail(null);setDraft({});setLearners([]);setPolicies([]);setNotice(null);setDirty(false);setIntent(null);};
  async function run(action:(current:number)=>Promise<void>) {
    if(active.current)return;active.current=true;const current=++generation.current;setBusy(true);setError(null);setSuccess(null);
    try {await action(current);} catch(cause) {
      if(current!==generation.current)return;
      if(cause instanceof RequestFailure && [401,403].includes(cause.status))drop();
      setError(message(cause));
    } finally {if(current===generation.current){setBusy(false);active.current=false;}}
  }
  async function load(current:number) {
    const currentSchool=await request(base,c.scopeSchool);
    if(current!==generation.current)return;
    if(currentSchool.scope.membershipId!==member.membershipId||currentSchool.scope.accessEpoch!==member.accessEpoch) {drop();throw new RequestFailure('PROFILE_SCOPE_CHANGED',409);}
    setSchool(currentSchool);
    const rows=await request(`${base}/learners`,c.page(c.learner));if(current!==generation.current)return;setLearners(rows.data.items);setCursor(rows.data.nextCursor);
    const policyList=await request(`${base}/profile-field-policies`,c.page(c.policy));if(current!==generation.current)return;setPolicies(policyList.data.items);setPolicyCursor(policyList.data.nextCursor);
    if(currentSchool.scope.roles.includes('ADMIN')){const value=await request(`${base}/data-policy`,c.envelope(c.notice));if(current!==generation.current)return;setNotice(value.data);}
    const command=await request('profile-command',c.commandState);if(current!==generation.current)return;setIntent(command.command);setConfirmation(false);
  }
  async function openLearner(learnerId:string,current:number) {
    setDetail(null);setDraft({});setDirty(false);
    const value=await request(`${base}/learners/${learnerId}/profile`,profileSchema);if(current!==generation.current)return;
    if(value.scope.accessEpoch!==member.accessEpoch||value.scope.membershipId!==member.membershipId||value.learner.schoolId!==member.schoolId) {drop();throw new RequestFailure('PROFILE_SCOPE_CHANGED',409);}
    const values:Record<string,string>={};
    for(const field of value.editableFields){const v=value.profile[field];if(typeof v==='string')values[field]=v;}
    if(value.profile.postalAddress)for(const [key,part] of Object.entries(value.profile.postalAddress))values[`address.${key}`]=part??'';
    setDetail(value);setDraft(values);window.history.replaceState(null,'',`/app/schools/${member.schoolId}/learners/${learnerId}`);
  }
  useEffect(()=>{
    void run(async current=>{
      await load(current);if(current!==generation.current)return;
      const route=window.location.pathname.match(/\/learners\/([0-9a-f-]+)$/i);
      if(route?.[1]&&c.id.safeParse(route[1]).success)await openLearner(route[1],current);
    });
    const verify=()=>{
      // Returning to a tab rechecks scope without overwriting an unsent draft.
      const current=generation.current;
      void request(base,c.scopeSchool).then(value=>{if(current!==generation.current)return;
        if(value.scope.accessEpoch!==member.accessEpoch||value.scope.membershipId!==member.membershipId){generation.current++;active.current=false;drop();setBusy(false);setError('Vos accès ont changé. Revenez à vos écoles pour les actualiser.');}
      }).catch(cause=>{if(current!==generation.current)return;if(cause instanceof RequestFailure&&[401,403].includes(cause.status)){generation.current++;active.current=false;drop();setBusy(false);setError(message(cause));}});
    };
    window.addEventListener('focus',verify);return()=>{generation.current++;active.current=false;window.removeEventListener('focus',verify);};
  },[member.schoolId,member.membershipId,member.accessEpoch,csrf]);
  function canLeave(){return !editing||window.confirm('Des informations non confirmées restent sur cette page. Quitter peut perdre le brouillon. Une demande déjà préparée reste conservée sur le serveur pour ce compte et devra être relue après reconnexion. Continuer ?');}
  function change(field:string,value:string){setDraft(previous=>({...previous,[field]:value}));setDirty(true);setSuccess(null);}
  async function prepare(payload:c.Prepare,current:number){
    const prepared=await request('profile-command/prepare',c.commandState,{csrf,body:payload});if(current!==generation.current)return;
    setIntent(prepared.command);setConfirmation(false);setDirty(false);
  }
  function profileCommand():c.Prepare {
    if(!detail)throw new Error('Profil absent');
    const payload:Record<string,unknown>={policyVersionId:detail.profile.policyVersionId};
    for(const field of detail.editableFields) {
      if(field==='profilePhotoDocumentId')continue;
      if(field==='postalAddress') {
        const parts=['line1','line2','postalCode','locality','countryCode'];
        const entered=Object.fromEntries(parts.map(key=>[key,draft[`address.${key}`]??'']));
        const current=detail.profile.postalAddress;
        if(parts.some(key=>entered[key] !== (current?.[key as keyof typeof current]??'')))payload.postalAddress=parts.every(key=>!entered[key])?null:{...entered,line2:entered.line2||null};
      } else {
        const entered=draft[field]??'';if(entered===(detail.profile[field]??''))continue;
        payload[field]=field==='firstName'||field==='lastName'?entered:entered||null;
      }
    }
    const parsed=c.profilePayload.safeParse(payload);
    if(!parsed.success)throw new RequestFailure('PROFILE_FORM_INVALID',422);
    return {kind:'PROFILE',schoolId:member.schoolId,learnerId:detail.learner.id,expectedVersion:detail.profile.version,payload:parsed.data};
  }
  const locked=busy||!!intent&&!['COMMITTED','REJECTED'].includes(intent.state);
  const ruleFor=(field:c.Field)=>detail?.policy.fields.find(rule=>rule.field===field);
  const description=(field:c.Field)=>{const rule=ruleFor(field);return rule?`${requirements[rule.requirement]} · ${stages[rule.stage]}. ${rule.explanation}`:'Champ de contact du dossier scolaire. Le serveur vérifie les besoins de l’action.';};
  return <section className="workspace" aria-labelledby="school-title">
    <div className="workspace-heading"><button className="button quiet" disabled={busy} onClick={()=>{if(canLeave())onClose();}}>← Vos écoles</button><h2 id="school-title">{member.schoolName}</h2><p className="caption">Les informations de ce dossier restent propres à cette école.</p></div>
    <div aria-live="polite">{busy&&<p className="loading">Vérification des informations…</p>}</div>
    {error&&<div className="notice error" role="alert"><strong>À vérifier</strong><p>{error}</p><button className="button secondary" disabled={busy} onClick={()=>{if(canLeave())void run(async current=>{setDetail(null);setDirty(false);await load(current);});}}>Recharger les accès</button></div>}
    {success&&<div className="notice success" role="status">{success}</div>}
    {intent&&!['COMMITTED','REJECTED'].includes(intent.state)&&<section className="card command-review" aria-labelledby="command-title">
      <h3 id="command-title">{intent.state==='PREPARED'?'Relire avant de confirmer':'Résultat à vérifier'}</h3>
      <p>{intent.request.kind==='PROFILE'?'Enregistrer les champs du profil scolaire':intent.request.kind==='POLICY_CREATE'?'Créer un brouillon de politique de champs':'Publier la politique de champs'}{intent.request.schoolId!==member.schoolId?' dans une autre école de ce compte':''}.</p>
      {intent.request.schoolId===member.schoolId&&<><CommandSummary intent={intent}/>{intent.reviewNotice&&<section aria-label="Notice associée à cette demande"><h4>Notice de données · version {intent.reviewNotice.version}</h4><p className="policy-copy">{intent.reviewNotice.noticeText}</p><p className="policy-copy">{intent.reviewNotice.retentionText}</p></section>}</>}
      <p className="caption">Cette demande garde son contenu et sa version. Un échec réseau n’autorise pas à la remplacer par une nouvelle demande.</p>
      <label className="checkbox-row"><input type="checkbox" checked={confirmation} disabled={busy||intent.request.schoolId!==member.schoolId} onChange={event=>setConfirmation(event.target.checked)}/><span>J’ai relu cette demande et je confirme son envoi à cette école.</span></label>
      <div className="button-row"><button className="button primary" disabled={busy||!confirmation||intent.request.schoolId!==member.schoolId} onClick={()=>void run(async current=>{
        try {await request('profile-command/confirm',z.object({ok:z.literal(true),operationId:c.id}),{csrf,body:{operationId:intent.operationId,confirmation:intent.confirmation}});
          if(current!==generation.current)return;setIntent({...intent,state:'COMMITTED'});setConfirmation(false);await load(current);
          if(intent.request.kind==='PROFILE'&&intent.request.schoolId===member.schoolId)await openLearner(intent.request.learnerId,current);
          if(current===generation.current)setSuccess(intent.request.kind==='POLICY_PUBLISH'?'Publication confirmée par l’école.':'Enregistrement confirmé par l’école.');
        } catch(cause) {if(current!==generation.current)return;try{const state=await request('profile-command',c.commandState);if(current===generation.current){setIntent(state.command);setConfirmation(false);if(state.command?.state==='REJECTED')setDirty(true);}}catch(recovery){if(recovery instanceof RequestFailure&&[401,403].includes(recovery.status))throw recovery;if(current===generation.current)setIntent({...intent,state:'UNCERTAIN'});}throw cause;}
      })}>{intent.state==='PREPARED'?'Confirmer la demande':'Vérifier et réessayer'}</button>
      {intent.state==='PREPARED'&&<button className="button secondary" disabled={busy} onClick={()=>void run(async current=>{await request('profile-command/cancel',okSchema,{csrf,body:{operationId:intent.operationId,confirmation:intent.confirmation}});if(current===generation.current){setIntent(null);setConfirmation(false);setDirty(true);}})}>Reprendre le brouillon</button>}</div>
    </section>}
    {school&&<>
      <nav className="workspace-tabs" aria-label="Rubriques de l’école"><button aria-current={tab==='learners'?'page':undefined} className="button secondary" disabled={busy} onClick={()=>{if(canLeave()){setTab('learners');setDetail(null);setDirty(false);window.history.replaceState(null,'',`/app/schools/${member.schoolId}`);}}}>Dossiers élèves</button>
        <button aria-current={tab==='policy'?'page':undefined} className="button secondary" disabled={busy} onClick={()=>{if(canLeave()){setTab('policy');setDetail(null);setDirty(false);}}}>Politique des champs</button></nav>
      {tab==='learners'&&!detail&&<section className="card"><h3>Dossiers accessibles</h3><p className="caption">Seuls les dossiers autorisés par l’école sont affichés.</p>
        {learners.length?<ul className="learner-list">{learners.map(item=><li key={item.id}><div><strong>{item.displayName}</strong><span className="caption">{item.profileReadiness==='MINIMAL'?'Profil à compléter':item.profileReadiness==='READY'?'Profil renseigné':'Informations à vérifier'}</span></div><button className="button secondary" disabled={busy} onClick={()=>void run(current=>openLearner(item.id,current))}>Ouvrir le profil</button></li>)}</ul>:<p className="empty-state">Aucun dossier n’est accessible avec vos droits actuels.</p>}
        {cursor&&<button className="button secondary" disabled={busy} onClick={()=>void run(async current=>{const data=await request(`${base}/learners?cursor=${encodeURIComponent(cursor)}`,c.page(c.learner));if(current===generation.current){setLearners(previous=>[...previous,...data.data.items.filter(row=>!previous.some(item=>item.id===row.id))]);setCursor(data.data.nextCursor);}})}>Afficher la suite</button>}
      </section>}
      {tab==='learners'&&detail&&<section className="card profile-editor"><h3>Profil scolaire · {detail.learner.displayName}</h3><p>Les noms administratifs sont saisis séparément du nom d’affichage et du compte de connexion.</p>
        <p className="caption">Dernière saisie : {detail.profile.entrySource==='SELF'?'par le titulaire du profil':'accompagnée par une personne de l’école'}. Les noms et contacts peuvent être corrigés selon vos accès.</p>
        {!detail.readiness.ready&&<div className="notice warning"><strong>Informations utiles à l’entrée</strong><ul>{detail.readiness.blockers.map((item,index)=><li key={`${item.code}-${index}`}>{item.message}</li>)}</ul></div>}
        {detail.readiness.ready&&<p className="caption">L’accès au dossier est autorisé, même si le profil reste à compléter. La formation et les prochaines actions ont leurs propres vérifications.</p>}
        <form onSubmit={event=>{event.preventDefault();void run(current=>prepare(profileCommand(),current));}}>
          <div className="form-grid">{(['firstName','lastName','contactEmail','contactPhone','birthDate'] as const).filter(field=>field in detail.profile&&(ruleFor(field)||['firstName','lastName'].includes(field))).map(field=><label className="form-field" key={field}><span>{labels[field]}</span>
            <input type={field==='birthDate'?'date':field==='contactEmail'?'email':field==='contactPhone'?'tel':'text'} autoComplete="off" maxLength={field==='contactPhone'?32:field==='contactEmail'?254:150} value={draft[field]??detail.profile[field]??''} disabled={locked||!detail.editableFields.includes(field)} onChange={event=>change(field,event.target.value)}/><small>{description(field)}</small></label>)}</div>
          {detail.editableFields.includes('postalAddress')&&ruleFor('postalAddress')&&<fieldset disabled={locked}><legend>Adresse postale</legend><p className="caption">{description('postalAddress')}</p><div className="form-grid">{Object.entries({line1:'Rue et numéro',line2:'Complément (facultatif)',postalCode:'Code postal',locality:'Localité',countryCode:'Pays (code à deux lettres)'}).map(([key,label])=><label className="form-field" key={key}><span>{label}</span><input autoComplete="off" maxLength={key==='countryCode'?2:key==='postalCode'?20:200} value={draft[`address.${key}`]??''} onChange={event=>change(`address.${key}`,key==='countryCode'?event.target.value.toUpperCase():event.target.value)}/></label>)}</div></fieldset>}
          <p className="caption">La photo est facultative. Son dépôt sera disponible avec les documents ; son absence ne bloque pas ce formulaire.</p>
          <p className="caption">{dirty?'Brouillon présent uniquement dans cette page.':'Modifiez les champs utiles puis relisez la demande.'} Fermer ou quitter la page peut perdre les modifications non confirmées.</p>
          <button type="submit" className="button primary" disabled={locked||!dirty}>Relire les modifications</button>
        </form>
      </section>}
      {tab==='policy'&&<section className="card"><h3>Politique des champs</h3><p>Chaque champ précise sa finalité et le stade où il devient utile. La photo reste facultative.</p>
        {policies.map(policy=><article className="policy-version" key={policy.id}><h4>Version {policy.version} · {policy.status==='DRAFT'?'Brouillon':policy.status==='PUBLISHED'?'Publiée':'Retirée'}</h4><p className="caption">Effet prévu le {new Intl.DateTimeFormat('fr-CH',{dateStyle:'medium',timeStyle:'short'}).format(new Date(policy.effectiveFrom))}.</p><RuleList rules={policy.fields}/>
          {school.scope.roles.includes('ADMIN')&&policy.status==='DRAFT'&&<button className="button secondary" disabled={locked} onClick={()=>void run(current=>prepare({kind:'POLICY_PUBLISH',schoolId:member.schoolId,policyId:policy.id,expectedVersion:policy.version,payload:{}},current))}>Relire la publication</button>}</article>)}
        {!policies.length&&<p className="empty-state">Aucune politique de champs n’est publiée pour le moment.</p>}
        {policyCursor&&<button className="button secondary" disabled={busy} onClick={()=>void run(async current=>{const list=await request(`${base}/profile-field-policies?cursor=${encodeURIComponent(policyCursor)}`,c.page(c.policy));if(current===generation.current){setPolicies(previous=>[...previous,...list.data.items.filter(row=>!previous.some(item=>item.id===row.id))]);setPolicyCursor(list.data.nextCursor);}})}>Autres versions</button>}
        {school.scope.roles.includes('ADMIN')&&notice?.status==='APPROVED'&&<form onSubmit={event=>{event.preventDefault();void run(async current=>{
          const parsed=c.policyPayload.safeParse({effectiveFrom:new Date(effective).toISOString(),noticeVersionId:notice.noticeVersionId,fields:rules,impactAcknowledged:impact});
          if(!parsed.success)throw new RequestFailure('PROFILE_FORM_INVALID',422);await prepare({kind:'POLICY_CREATE',schoolId:member.schoolId,expectedVersion:school.school.version,payload:parsed.data},current);
        });}}><h3>Préparer une nouvelle politique</h3><p className="caption">Notice de données adoptée : version {notice.version}. La création reste un brouillon ; sa publication demandera une confirmation distincte.</p>
          <label className="form-field"><span>Date et heure d’effet, dans le fuseau de cet appareil</span><input type="datetime-local" required value={effective} disabled={locked} onChange={event=>{setEffective(event.target.value);setDirty(true);}}/></label>
          {c.field.options.map(field=>{const rule=rules.find(item=>item.field===field);const fixed=['firstName','lastName'].includes(field);return <fieldset className="rule-editor" key={field} disabled={locked}><legend>{labels[field]}</legend>
            <label className="checkbox-row"><input type="checkbox" checked={!!rule} disabled={fixed||locked} onChange={event=>{setRules(previous=>event.target.checked?[...previous,{field,requirement:'OPTIONAL',stage:'OPTIONAL',purposeCode:field==='profilePhotoDocumentId'?'PERSONALISATION':field==='postalAddress'?'POSTAL_CONTACT':'LESSON_CONTACT',explanation:''}]:previous.filter(item=>item.field!==field));setDirty(true);}}/><span>{fixed?'Champ d’identification de base':'Inclure ce champ dans la politique'}</span></label>
            {rule&&<div className="form-grid">{(['requirement','stage','purposeCode'] as const).map(key=><label className="form-field" key={key}><span>{key==='requirement'?'Niveau demandé':key==='stage'?'Stade':'Finalité'}</span><select value={rule[key]} disabled={fixed||field==='profilePhotoDocumentId'||locked} onChange={event=>{setRules(previous=>previous.map(item=>item.field===field?{...item,[key]:event.target.value}:item));setDirty(true);}}>{Object.entries(key==='requirement'?requirements:key==='stage'?stages:purposes).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>)}
              <label className="form-field full"><span>Pourquoi cette information est utile</span><textarea maxLength={1000} required value={rule.explanation} onChange={event=>{setRules(previous=>previous.map(item=>item.field===field?{...item,explanation:event.target.value}:item));setDirty(true);}}/></label></div>}</fieldset>;})}
          <label className="checkbox-row"><input type="checkbox" checked={impact} disabled={locked} onChange={event=>{setImpact(event.target.checked);setDirty(true);}}/><span>J’ai relu les finalités, les stades et les conséquences de ces demandes pour les élèves.</span></label>
          <button type="submit" className="button primary" disabled={locked||!impact||!effective}>Relire le brouillon de politique</button>
        </form>}
        {school.scope.roles.includes('ADMIN')&&notice?.status!=='APPROVED'&&<p className="notice warning">Adoptez d’abord la notice de données de l’école depuis sa configuration.</p>}
      </section>}
    </>}
  </section>;
}
function RuleList({rules}:{rules:c.FieldRule[]}){return <ul className="rule-list">{rules.map(rule=><li key={rule.field}><strong>{labels[rule.field]}</strong> — {requirements[rule.requirement]}, {stages[rule.stage]}.<p>{rule.explanation}</p></li>)}</ul>;}
function CommandSummary({intent}:{intent:c.IntentView}){
  if(intent.request.kind==='POLICY_CREATE')return <RuleList rules={intent.request.payload.fields}/>;
  if(intent.request.kind==='POLICY_PUBLISH')return <><p>Cette version sera publiée pour les prochaines actions concernées.</p>{intent.reviewPolicy&&<><p className="caption">Effet prévu : {new Date(intent.reviewPolicy.effectiveFrom).toLocaleString('fr-CH')}.</p><RuleList rules={intent.reviewPolicy.fields}/></>}</>;
  return <dl className="invitation-facts">{Object.entries(intent.request.payload).filter(([field])=>field!=='policyVersionId').map(([field,value])=><div key={field}><dt>{labels[field as c.Field]}</dt><dd>{value===null?'Effacer la valeur':typeof value==='object'?Object.values(value).filter(Boolean).join(', '):String(value)}</dd></div>)}</dl>;
}
