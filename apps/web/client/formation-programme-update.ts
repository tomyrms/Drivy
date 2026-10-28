import type {FormationProposals} from './formation-api.js';
type Competency = {key:string;label:string;description:string};
export type ProgrammeTemplate = FormationProposals['formations'][number];
/** Comparaison par clé, jamais par position : toute adaptation existante garde sa place et son texte. */
export function programmeUpdate(current:readonly Competency[],template:ProgrammeTemplate) {
  const byKey=new Map(current.map(item=>[item.key,item]));
  const additions=template.competencies.filter(item=>!byKey.has(item.key)).map(({key,label,description})=>({key,label,description}));
  const differences=template.competencies.flatMap(proposed=>{
    const previous=byKey.get(proposed.key);
    return previous&&(previous.label!==proposed.label||previous.description!==proposed.description)?[{previous,proposed}]:[];
  });
  const labels=new Set(current.map(item=>item.label.trim().toLocaleLowerCase('fr')));
  const collisions=additions.filter(item=>labels.has(item.label.trim().toLocaleLowerCase('fr')));
  const duplicateKeys=new Set(template.competencies.map(item=>item.key)).size!==template.competencies.length;
  return {additions,differences,collisions,preserved:current.filter(item=>!template.competencies.some(proposed=>proposed.key===item.key)),
    canApply:additions.length>0&&!duplicateKeys&&collisions.length===0&&current.length+additions.length<=200&&template.change?.kind==='PEDAGOGICAL',
    competencies:[...current.map(({key,label,description})=>({key,label,description})),...additions],
    source:{templateId:template.id,templateVersion:template.version}};
}
