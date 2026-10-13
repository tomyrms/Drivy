import { useEffect, useRef, useState } from 'react';
import { z } from 'zod';
import { BrandSymbol } from './BrandSymbol';
import { request, sessionSchema, loginSchema, okSchema, type Session, RequestFailure } from './protocol';
import { CheckField, Loading, Notice, TextField, formatDateTime } from './ui';
import { openingState, openingPreview, openingReceipt, openingLinks, createdOpeningLink, openingLinkSchema,
  openingFailure, openingFieldErrors, schoolOpeningDestination, type OpeningFieldErrors, type OpeningLink, type OpeningFields, type OpeningReceipt } from './school-opening-model';

export function SchoolOpeningPage({link,operator=false}:{link:OpeningLink;operator?:boolean}) {
  const [session,setSession]=useState<Session|null>(null),[loaded,setLoaded]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState<string|null>(null);
  const [ready,setReady]=useState(false),[uncertain,setUncertain]=useState(false),[result,setResult]=useState<OpeningReceipt|null>(null);
  const [fields,setFields]=useState<OpeningFields>({schoolName:'',displayName:'',contactEmail:'',contactPhone:null,timeZone:'Europe/Zurich',instructs:false});
  const [fieldErrors,setFieldErrors]=useState<OpeningFieldErrors>({}),[invalidField,setInvalidField]=useState<keyof OpeningFields|null>(null);
  const [items,setItems]=useState<z.infer<typeof openingLinkSchema>[]>([]),[generated,setGenerated]=useState<string|null>(null),[copied,setCopied]=useState(false);
  const operatorOperation=useRef<string|null>(null),started=useRef(false),heading=useRef<HTMLHeadingElement>(null),form=useRef<HTMLFormElement>(null);
  const returnTo=operator?'/app/operateur':'/app/ouvrir';
  async function list() {
    const response=await request('operator/school-opening-links',openingLinks);setItems(response.data.items);
    operatorOperation.current=response.pendingOperationId ?? operatorOperation.current;setReady(true);
  }
  async function inspect(current:Session) {
    const state=await request('opening',openingState);setUncertain(state.uncertain);
    if(state.draft)setFields(state.draft);
    if(state.result){setResult(state.result);return;}
    if(state.uncertain){setReady(true);return;}
    const preview=await request('opening/preview',openingPreview,{csrf:current.csrfToken,body:{}});
    if(preview.data.status==='USED')setResult(preview.data.school);else setReady(true);
  }
  async function boot() {
    setError(null);setLoaded(false);setReady(false);setResult(null);setItems([]);setGenerated(null);setCopied(false);
    try {
      let current=await request('session',sessionSchema);setSession(current);
      if(link.error)throw new RequestFailure('OPENING_LINK_INVALID');
      if(!operator && link.token){await request('opening',okSchema,{csrf:current.csrfToken,body:{token:link.token}});current=await request('session',sessionSchema);setSession(current);}
      if(current.authenticated){setFields(previous=>({...previous,displayName:current.user?.displayName ?? '',contactEmail:current.user?.email ?? ''}));if(operator)await list();else await inspect(current);}
    }catch(reason){setError(openingFailure(reason));}finally{setLoaded(true);}
  }
  useEffect(()=>{if(started.current)return;started.current=true;document.title=operator?'Liens d’ouverture · Drivy':'Préparer votre école · Drivy';void boot();},[]);
  useEffect(()=>{
    if(!invalidField)return;
    const input=form.current?.elements.namedItem(invalidField);
    if(input instanceof HTMLInputElement){for(let parent=input.parentElement;parent&&parent!==form.current;parent=parent.parentElement)if(parent instanceof HTMLDetailsElement)parent.open=true;input.focus();}
    setInvalidField(null);
  },[invalidField]);
  async function login(changeAccount=false) {
    if(!session)return;setBusy(true);setError(null);
    try{const next=await request('login',loginSchema,{csrf:session.csrfToken,body:{returnTo,...(changeAccount?{reauthenticate:true}:{})}});window.location.assign(next.url);}
    catch(reason){setError(openingFailure(reason));setBusy(false);}
  }
  async function createSchool() {
    if(!session)return;
    if(!uncertain){const errors=openingFieldErrors(fields);setFieldErrors(errors);const first=(['displayName','schoolName','contactEmail','contactPhone','timeZone'] as const).find(field=>errors[field]);if(first){setInvalidField(first);setError(null);return;}}
    setBusy(true);setError(null);
    try {const response=await request('opening/create',z.object({data:openingReceipt}),{csrf:session.csrfToken,body:fields});setResult(response.data);setUncertain(false);heading.current?.focus();}
    catch(reason){setError(openingFailure(reason));try{const state=await request('opening',openingState);setUncertain(state.uncertain);if(state.draft)setFields(state.draft);if(state.result){setResult(state.result);setError(null);}}catch{/* Keep the last known intention. */}}
    finally{setBusy(false);}
  }
  async function verify() {
    setBusy(true);setError(null);try{const response=await request('opening/result',z.object({data:openingReceipt}));setResult(response.data);setUncertain(false);}
    catch(reason){setError(reason instanceof RequestFailure && reason.status===404?'Le résultat n’est pas encore confirmé. Vous pouvez renvoyer la même demande.':openingFailure(reason));}finally{setBusy(false);}
  }
  async function createLink() {
    if(!session)return;setBusy(true);setError(null);setCopied(false);
    try {
      if(generated){await request('operator/school-opening-links/clear',okSchema,{csrf:session.csrfToken,body:{}});operatorOperation.current=null;setGenerated(null);}
      operatorOperation.current ??= crypto.randomUUID();
      const response=await request('operator/school-opening-links',createdOpeningLink,{csrf:session.csrfToken,body:{operationId:operatorOperation.current}});
      setGenerated(response.link);await list();
    }catch(reason){setError(openingFailure(reason));}finally{setBusy(false);}
  }
  async function revoke(id:string) {
    if(!session)return;setBusy(true);setError(null);
    try{await request(`operator/school-opening-links/${id}/revoke`,z.object({data:openingLinkSchema}),{csrf:session.csrfToken,body:{operationId:crypto.randomUUID()}});await list();}
    catch(reason){setError(openingFailure(reason));}finally{setBusy(false);}
  }
  async function copy() {
    if(!generated)return;try{await navigator.clipboard.writeText(generated);setCopied(true);}catch{setError('La copie a échoué. Sélectionnez et copiez le lien affiché.');}
  }
  const update=<K extends keyof OpeningFields>(key:K,value:OpeningFields[K])=>{setFields(previous=>({...previous,[key]:value}));setFieldErrors(previous=>({...previous,[key]:undefined}));};
  const statuses={AVAILABLE:'Disponible',USED:'Utilisé',EXPIRED:'Expiré',REVOKED:'Révoqué'};
  return <div className="app-shell account-shell opening-shell">
    <a className="skip-link" href="#main">Aller au contenu</a>
    <header className="site-header"><a className="brand" href="/app/" aria-label="Drivy, votre espace"><BrandSymbol/><span>Drivy</span></a>
      {session?.authenticated && <a className="button quiet" href="/app/">Mes écoles</a>}</header>
    <main id="main" className="main" aria-busy={!loaded || busy}>
      <div className="page-heading"><h1 ref={heading} tabIndex={-1}>{operator?'Liens d’ouverture':result?'Votre école est créée':'Préparer votre école'}</h1></div>
      {error && <Notice tone="error" title={error} actions={!loaded?undefined:<button type="button" className="button quiet" disabled={busy} onClick={()=>void boot()}>Actualiser</button>}/>}
      {!loaded && <Loading label="Chargement…"/>}
      {loaded && !session?.authenticated && !link.error && <section className="section">
        <button className="button primary" type="button" disabled={busy} onClick={()=>void login()}>Créer mon compte ou me connecter</button>
      </section>}
      {loaded && session?.authenticated && <>
        <section className="section"><div className="identity-row"><div className="row-text"><strong>{session.user?.displayName}</strong><span className="row-meta">{session.user?.email}</span></div>
          <button className="button quiet" type="button" disabled={busy || uncertain} onClick={()=>void login(true)}>Changer de compte</button></div></section>
        {result ? <section className="panel form-grid"><h2>{result.schoolName}</h2><a className="button primary" href={schoolOpeningDestination(result)}>Continuer la préparation</a></section>
          : operator && ready ? <>
            <section className="section form-grid"><button className="button primary" type="button" disabled={busy} onClick={()=>void createLink()}>{busy?'Création…':operatorOperation.current&&!generated?'Retrouver le lien':'Créer un lien d’ouverture'}</button>
              {generated && <div className="panel form-grid"><TextField label="Lien à transmettre" value={generated} onChange={()=>{}} readOnly/>
                <button type="button" className="button secondary" onClick={()=>void copy()}>Copier le lien</button>{copied && <p role="status">Lien copié.</p>}</div>}
            </section>
            <section className="section" aria-labelledby="opening-links"><h2 id="opening-links">Liens créés</h2>
              {items.length===0?<p>Aucun lien créé.</p>:<ul className="opening-links">{items.map(item=><li key={item.id}><div className="row-text"><strong>{statuses[item.status]}</strong><span className="row-meta">Créé le {formatDateTime(item.createdAt)} · Expire le {formatDateTime(item.expiresAt)}</span></div>
                {item.status==='AVAILABLE' && <button type="button" className="button quiet" disabled={busy} onClick={()=>void revoke(item.id)} aria-label={`Révoquer le lien créé le ${formatDateTime(item.createdAt)}`}>Révoquer</button>}</li>)}</ul>}
            </section>
          </> : !operator && ready && <form ref={form} noValidate className="panel form-grid" onSubmit={event=>{event.preventDefault();void createSchool();}}>
            <h2>Votre école</h2><fieldset disabled={busy || uncertain} className="opening-fields"><legend className="visually-hidden">Coordonnées de l’école et du responsable</legend>
              <TextField name="displayName" label="Votre nom" value={fields.displayName} onChange={value=>update('displayName',value)} error={fieldErrors.displayName} maxLength={200} autoComplete="name" required/>
              <TextField name="schoolName" label="Nom de l’auto-école" value={fields.schoolName} onChange={value=>update('schoolName',value)} error={fieldErrors.schoolName} maxLength={150} autoComplete="organization" required/>
              <TextField name="contactEmail" label="E-mail professionnel" value={fields.contactEmail} onChange={value=>update('contactEmail',value)} error={fieldErrors.contactEmail} maxLength={254} type="email" autoComplete="email" required/>
              <TextField name="contactPhone" label="Téléphone (facultatif)" value={fields.contactPhone??''} onChange={value=>update('contactPhone',value||null)} error={fieldErrors.contactPhone} maxLength={32} type="tel" autoComplete="tel"/>
              <CheckField label="Je donne aussi des leçons" checked={fields.instructs} onChange={value=>update('instructs',value)}/>
              <details><summary>Fuseau horaire</summary><TextField name="timeZone" label="Fuseau horaire" value={fields.timeZone} onChange={value=>update('timeZone',value)} error={fieldErrors.timeZone} maxLength={100} required/></details>
            </fieldset>
            {uncertain && <Notice tone="warning" title="Création à vérifier" actions={<button type="button" className="button secondary" disabled={busy} onClick={()=>void verify()}>Vérifier le résultat</button>}/>}
            <button className="button primary" type="submit" disabled={busy}>{busy?'Création…':uncertain?'Renvoyer la même demande':'Créer mon école'}</button>
          </form>}
      </>}
    </main><footer className="site-footer"><span>Drivy</span></footer>
  </div>;
}
