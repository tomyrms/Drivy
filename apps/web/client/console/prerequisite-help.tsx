import {useState} from 'react';
import {prerequisiteHints,type PrerequisiteMoment} from '../swiss-prerequisites';
import {SelectField,formatCivilDate} from '../ui';
import {civilDateIn} from '../agenda-model';
import {coursePrerequisiteEvidence,learnerCourseFactsSchema,prerequisiteCourseTypes,type CourseFactsRead} from '../learner-course-facts';
import {readSchool} from '../school-api';
import {RequestFailure} from '../protocol';
import {useCommandSnapshot} from '../command-store';
import {useLoad} from './context';

/** Ouvert au besoin dans le dossier : aucune donnée supplémentaire demandée ni obligation déduite d'une absence de lecture. */
export function PrerequisiteHelp({schoolId,learnerId,categoryCode,today,timeZone}:{schoolId:string;learnerId:string;categoryCode:string;today:string;timeZone:string}) {
  const [moment,setMoment]=useState<PrerequisiteMoment>('PRACTICAL');
  const [open,setOpen]=useState(false);
  const {revision}=useCommandSnapshot();
  const usesCourses=['A','A35','A1','B','B1'].includes(categoryCode);
  const facts=useLoad(async():Promise<CourseFactsRead|null>=>{
    if(!open||!usesCourses)return null;
    try {
      const data=await readSchool(schoolId,`learners/${learnerId}/course-facts`,learnerCourseFactsSchema);
      if(data.schoolId!==schoolId||data.learnerId!==learnerId)throw new RequestFailure('INVALID_RESPONSE');
      return {status:'READY',data};
    } catch(error) {
      if(error instanceof RequestFailure&&error.status===403)return {status:'ACCESS_DENIED'};
      if(error instanceof RequestFailure&&error.status===404)return {status:'NOT_FOUND'};
      throw error;
    }
  },[schoolId,learnerId,open,usesCourses,revision],`${schoolId}/${learnerId}`);
  const read=facts.status==='error'?{status:'READ_ERROR' as const}:facts.status==='ready'?facts.data:null;
  const evidence=read?coursePrerequisiteEvidence(read):{};
  const hints=prerequisiteHints({categoryCode,today,moment,evidence});
  const source=categoryCode==='A35'?'https://www.vd.ch/mobilite/automobile-et-navigation/permis/motocycles-a1-et-a':`https://lepermisdeconduire.ch/categories-de-permis/categorie-${categoryCode.toLowerCase()}/`;
  const known=['A1','A35','A','B','B1','BE','C1','C','C1E','CE','D1','D','D1E','DE','F','G','M'].includes(categoryCode);
  if(!known)return null;
  if(categoryCode==='G'||categoryCode==='M')return <details className="disclosure compact"><summary>Prérequis du permis {categoryCode}</summary>
    <p>Préparation théorique ; aucun permis d’élève ni examen pratique ordinaire. Les cas particuliers restent à vérifier auprès du canton.</p>
    <a className="text-link" href={source} target="_blank" rel="noreferrer noopener">Exigences officielles · vérifiées le 28 octobre 2026</a>
  </details>;
  return <details className="disclosure compact" onToggle={event=>setOpen(event.currentTarget.open)}><summary>Prérequis du permis {categoryCode}</summary>
    <SelectField label="Démarche à préparer" value={moment} onChange={value=>setMoment(value as PrerequisiteMoment)} options={[
      {value:'APPLICATION',label:'Demande de permis d’élève'},{value:'THEORY',label:'Examen théorique'},{value:'PRACTICAL',label:'Examen pratique'}]}/>
    <p className="row-meta">Situation consultée le {formatCivilDate(today)}</p>
    {facts.status==='error'&&<p role="alert">La lecture des faits de cours a échoué. <button type="button" className="text-link" onClick={facts.reload}>Réessayer la lecture</button></p>}
    {read?.status==='ACCESS_DENIED'&&<p>Vos droits ne permettent pas de consulter les faits de cours de ce dossier.</p>}
    {read?.status==='NOT_FOUND'&&<p>Ce dossier n’est pas disponible pour la lecture des faits de cours.</p>}
    {hints.length?<ul className="plain-list">{hints.map(hint=>{
      const type=prerequisiteCourseTypes[hint.id as keyof typeof prerequisiteCourseTypes];
      const course=read?.status==='READY'?read.data:null;
      const completion=course?.completions.find(item=>item.typeKey===type);
      const enrollments=course?.enrollments.filter(item=>item.typeKey===type)??[];
      return <li key={hint.id}><p><strong>{hint.label}</strong> · {type&&facts.status==='loading'?'Lecture des faits de cours…':hint.conclusion}</p>
      <details className="disclosure compact"><summary>Vérifier ce prérequis</summary><p>{hint.detail}</p>
        {completion&&<p>Validation interne enregistrée le {formatCivilDate(civilDateIn(timeZone,Date.parse(completion.validatedAt)))}. Cette date n’est pas la date d’une attestation de cours.</p>}
        {enrollments.map((item,index)=><p key={item.enrollmentId}>Cours {index+1} : {item.requirements.present} / {item.requirements.required} présences obligatoires enregistrées.{!completion?' Accomplissement non validé.':''}</p>)}
        <p>Les faits de cours Drivy ne remplacent pas une attestation officielle ou une dispense. Consultez le justificatif ou le service cantonal avant la démarche.</p>
        <a className="text-link" href={hint.sourceUrl} target="_blank" rel="noreferrer noopener">Source · vérifiée le {formatCivilDate(hint.checkedOn)}</a><p className="row-meta">Règle Drivy {hint.version}</p>
      </details></li>;})}</ul>:<p>Aucune conclusion automatique pour cette démarche. <a className="text-link" href={source} target="_blank" rel="noreferrer noopener">Consulter les exigences de ce permis</a></p>}
  </details>;
}
