import {describe,expect,it} from 'vitest';
import {readFile} from 'node:fs/promises';
import {z} from 'zod';
import {coursePrerequisiteEvidence,learnerCourseFactsSchema,type LearnerCourseFacts} from '../client/learner-course-facts.js';
import {prerequisiteHints} from '../client/swiss-prerequisites.js';
import {matchSchoolRoute} from '../server/school-routes.js';

const school='10000000-0000-4000-8000-000000000001',learner='10000000-0000-4000-8000-000000000002';
const id='10000000-0000-4000-8000-000000000003',series='10000000-0000-4000-8000-000000000004';
const empty: LearnerCourseFacts={schoolId:school,learnerId:learner,completions:[],enrollments:[]};
const conclusion=(data:LearnerCourseFacts)=>prerequisiteHints({categoryCode:'B',moment:'APPLICATION',today:'2026-10-28',evidence:coursePrerequisiteEvidence({status:'READY',data})})[0]!.conclusion;
describe('faits de cours et aide aux prérequis',()=>{
 it('le client lit exactement les champs du contrat API séparé',async()=>{
  const contract=JSON.parse(await readFile(new URL('../../api/contracts/learner-course-facts.json',import.meta.url),'utf8')) as {$defs:Record<string,unknown>};
  const {$schema:_,...expected}=z.toJSONSchema(learnerCourseFactsSchema);
  expect(contract.$defs.LearnerCourseFacts).toEqual(expected);
 });
 it('relaye uniquement la lecture précise sans paramètres',()=>{
  const path=`/schools/${school}/learners/${learner}/course-facts`;
  expect(matchSchoolRoute('GET',path,'')?.path).toBe(`/v1${path}`);
  expect(matchSchoolRoute('GET',path,'?all=1')).toBeUndefined();
  expect(matchSchoolRoute('POST',path,'')).toBeUndefined();
  expect(matchSchoolRoute('GET',path.replace(learner,'all'),'')).toBeUndefined();
 });
 it('ne transforme aucune absence, erreur ou restriction en prérequis manquant',()=>{
  expect(conclusion(empty)).toBe('Aucun fait de cours enregistré');
  for(const [status,text] of [['READ_ERROR','Preuve non consultable'],['ACCESS_DENIED','Faits de cours non consultables avec vos droits'],['NOT_FOUND','Dossier indisponible pour cette lecture']] as const){
   const hint=prerequisiteHints({categoryCode:'B',moment:'APPLICATION',today:'2026-10-28',evidence:coursePrerequisiteEvidence({status})})[0]!;
   expect(hint.conclusion).toBe(text);expect(hint.blocking).toBe(false);
  }
 });
 it('garde la date interne sans lui attribuer la validité de six ans d’une attestation',()=>{
  const data: LearnerCourseFacts={...empty,completions:[{id,typeKey:'FIRST_AID',seriesId:series,validatedAt:'2010-01-01T12:00:00Z'}]};
  expect(coursePrerequisiteEvidence({status:'READY',data})['first-aid']).toEqual({state:'INTERNAL_VALIDATION',validatedAt:'2010-01-01T12:00:00Z'});
  expect(conclusion(data)).toBe('Accomplissement enregistré dans Drivy');
 });
 it('n’additionne pas plusieurs cours ni les séances facultatives pour valider un accomplissement',()=>{
  const enrollment={enrollmentId:id,seriesId:series,typeKey:'FIRST_AID' as const,requirements:{required:0,present:0,missing:0},attendance:[]};
  expect(conclusion({...empty,enrollments:[enrollment]})).toBe('Inscription enregistrée · accomplissement non validé');
  const attended={...enrollment,attendance:[{occurrenceId:id,status:'PRESENT' as const}]};
  expect(conclusion({...empty,enrollments:[attended,{...attended,enrollmentId:series}]})).toBe('Présences enregistrées · accomplissement non validé');
 });
 it('rejette un type inconnu au lieu de reconnaître le titre d’un cours personnalisé',()=>{
  expect(learnerCourseFactsSchema.safeParse({...empty,completions:[{id,typeKey:'MOTO',seriesId:null,validatedAt:'2026-10-28T12:00:00Z'}]}).success).toBe(false);
 });
 it('la validation interne ne renseigne pas la date de dépôt de la demande vaudoise',()=>{
  const data: LearnerCourseFacts={...empty,completions:[{id,typeKey:'AWARENESS',seriesId:series,validatedAt:'2026-10-28T12:00:00Z'}]};
  expect(prerequisiteHints({categoryCode:'B',moment:'THEORY',canton:'VD',today:'2027-01-01',evidence:coursePrerequisiteEvidence({status:'READY',data})})[0]?.conclusion).toBe('Date de demande inconnue — transition à vérifier');
 });
});
