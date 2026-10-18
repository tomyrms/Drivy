/** Contrat d’accueil personnel avec l’identité issue du navigateur réel ; ce n’est pas un parcours UI natif. */
import {randomUUID} from 'node:crypto';
import {z} from 'zod';

const progressSchema=z.object({id:z.uuid(),schoolId:z.uuid(),kind:z.enum(['STUDENT','STAFF']),version:z.number().int().positive(),
  status:z.enum(['IN_PROGRESS','READY','COMPLETED']),currentStep:z.string(),policyVersionId:z.uuid(),
  skippedOptionalSteps:z.array(z.string()),pendingActions:z.array(z.object({code:z.string()}))});
type Progress=z.infer<typeof progressSchema>;

export async function verifyPersonalWelcome(options:{apiOrigin:string;schoolId:string;kind:'STUDENT'|'STAFF';
  getAccessToken:()=>Promise<string>;assert:(value:unknown,label:string)=>void;setStage:(value:string)=>void}):Promise<void> {
  const {apiOrigin,schoolId,kind,getAccessToken,assert,setStage}=options;
  const label=kind==='STAFF'?'moniteur':'élève';
  setStage(`accueil personnel ${label} : état courant et progression par l’API de l’app`);
  async function request(method:'GET'|'PATCH'|'POST',state?:Progress,step?:string):Promise<Progress> {
    const operationId=randomUUID();
    const body=state?{operationId,kind,policyVersionId:state.policyVersionId,
      ...(method==='PATCH'?{currentStep:step,skippedOptionalSteps:['DEVICE']}: {})}:undefined;
    const suffix=method==='GET'?`?kind=${kind}`:method==='POST'?'/complete':'';
    const response=await fetch(`${apiOrigin}/v1/schools/${schoolId}/my-onboarding${suffix}`,{
      method,redirect:'error',signal:AbortSignal.timeout(15_000),
      headers:{Authorization:`Bearer ${await getAccessToken()}`,...(state?{'Content-Type':'application/json','Idempotency-Key':operationId,'If-Match':`"${state.version}"`}:{})},
      ...(body?{body:JSON.stringify(body)}:{})});
    if(!response.ok)throw new Error('PERSONAL_WELCOME_REQUEST_FAILED');
    return z.object({data:progressSchema}).parse(await response.json()).data;
  }
  const initial=await request('GET');
  assert(initial.schoolId===schoolId&&initial.kind===kind&&initial.currentStep==='IDENTITY'
    &&initial.pendingActions.every(action=>action.code==='ONBOARDING_REVIEW_REQUIRED'),
    `L’accueil ${label} connaît son rôle et ne réclame aucune information déjà donnée au compte`);
  const formation=await request('PATCH',initial,'FORMATIONS');
  assert(formation.currentStep==='FORMATIONS'&&formation.version===initial.version+1,
    `L’accueil ${label} avance après l’enregistrement de l’étape, sans modification du profil`);
  const resumed=await request('GET');
  assert(resumed.id===formation.id&&resumed.version===formation.version&&resumed.currentStep==='FORMATIONS',
    `Relire l’accueil ${label} reprend l’étape enregistrée et ne recommence pas à l’identité`);
  const reviewed=await request('PATCH',resumed,'REVIEW');
  assert(reviewed.status==='READY'&&reviewed.pendingActions.length===0&&reviewed.skippedOptionalSteps.includes('DEVICE'),
    `L’accueil ${label} reste terminable sans permission de localisation ni accord GPS fabriqué`);
  const completed=await request('POST',reviewed);
  const reopened=await request('GET');
  assert(completed.status==='COMPLETED'&&reopened.status==='COMPLETED'&&reopened.id===completed.id&&reopened.version===completed.version,
    `L’accueil ${label} terminé reste terminé à la relecture sans nouvelle commande`);
}
