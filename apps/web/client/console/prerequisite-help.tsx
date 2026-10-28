import {useState} from 'react';
import {prerequisiteHints,type PrerequisiteMoment} from '../swiss-prerequisites';
import {SelectField,formatCivilDate} from '../ui';

/** Ouvert au besoin dans le dossier : aucune donnée supplémentaire demandée ni obligation déduite d'une absence de lecture. */
export function PrerequisiteHelp({categoryCode,today}:{categoryCode:string;today:string}) {
  const [moment,setMoment]=useState<PrerequisiteMoment>('PRACTICAL');
  const hints=prerequisiteHints({categoryCode,today,moment});
  const source=categoryCode==='A35'?'https://www.vd.ch/mobilite/automobile-et-navigation/permis/motocycles-a1-et-a':`https://lepermisdeconduire.ch/categories-de-permis/categorie-${categoryCode.toLowerCase()}/`;
  const known=['A1','A35','A','B','B1','BE','C1','C','C1E','CE','D1','D','D1E','DE','F','G','M'].includes(categoryCode);
  if(!known)return null;
  if(categoryCode==='G'||categoryCode==='M')return <details className="disclosure compact"><summary>Prérequis du permis {categoryCode}</summary>
    <p>Préparation théorique ; aucun permis d’élève ni examen pratique ordinaire. Les cas particuliers restent à vérifier auprès du canton.</p>
    <a className="text-link" href={source} target="_blank" rel="noreferrer noopener">Exigences officielles · vérifiées le 28 octobre 2026</a>
  </details>;
  return <details className="disclosure compact"><summary>Prérequis du permis {categoryCode}</summary>
    <SelectField label="Démarche à préparer" value={moment} onChange={value=>setMoment(value as PrerequisiteMoment)} options={[
      {value:'APPLICATION',label:'Demande de permis d’élève'},{value:'THEORY',label:'Examen théorique'},{value:'PRACTICAL',label:'Examen pratique'}]}/>
    <p className="row-meta">Situation consultée le {formatCivilDate(today)}</p>
    {hints.length?<ul className="plain-list">{hints.map(hint=><li key={hint.id}><p><strong>{hint.label}</strong> · {hint.conclusion}</p>
      <details className="disclosure compact"><summary>Vérifier ce prérequis</summary><p>{hint.detail}</p><p>Les justificatifs de cours et les dispenses ne sont pas encore suivis dans ce dossier. Consultez le justificatif ou le service cantonal avant la démarche.</p>
        <a className="text-link" href={hint.sourceUrl} target="_blank" rel="noreferrer noopener">Source · vérifiée le {formatCivilDate(hint.checkedOn)}</a><p className="row-meta">Règle Drivy {hint.version}</p>
      </details></li>)}</ul>:<p>Aucune conclusion automatique pour cette démarche. <a className="text-link" href={source} target="_blank" rel="noreferrer noopener">Consulter les exigences de ce permis</a></p>}
  </details>;
}
