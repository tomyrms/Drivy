import {describe,it,expect} from 'vitest';
import {programmeUpdate,type ProgrammeTemplate} from '../client/formation-programme-update.js';
import {prerequisiteHints} from '../client/swiss-prerequisites.js';
import {civilDateIn} from '../client/agenda-model.js';

const old={key:'preparation',label:'Préparation de notre école',description:'Note pédagogique conservée.'};
const extra={key:'school-note',label:'Complément de l’école',description:'Exercice local.'};
const added={key:'trailer-coupling',label:'Atteler et dételer',description:'Sécuriser l’ensemble.'};
const template:ProgrammeTemplate={id:'pedagogy-be',version:'2026-10-28.1',categoryCode:'BE',label:'Permis BE',competencies:[{...old,label:'Préparer l’ensemble'},added],
  procedureText:'Déroulement',durationMinutes:45,change:{kind:'PEDAGOGICAL',effectiveFrom:null,summary:'Ajout',application:'Nouvelles inscriptions'}};
describe('proposition de programme non destructive',()=>{
  it('conserve ordre, clés, formulations et compléments de l’école',()=>{
    const diff=programmeUpdate([extra,old],template);
    expect(diff.competencies).toEqual([extra,old,added]);expect(diff.differences).toHaveLength(1);expect(diff.canApply).toBe(true);
  });
  it('ne repropose pas la même compétence après application',()=>{
    const applied=programmeUpdate([old],template).competencies;
    expect(programmeUpdate(applied,template).additions).toEqual([]);
  });
  it('suspend les ajouts en cas de même nom sous une clé différente',()=>{
    expect(programmeUpdate([old,{...added,key:'legacy-local'}],template).canApply).toBe(false);
  });
  it('ne transforme pas une évolution réglementaire en ajout automatique',()=>{
    expect(programmeUpdate([old],{...template,change:{...template.change!,kind:'REGULATORY',effectiveFrom:'2027-01-01'}}).canApply).toBe(false);
  });
});
describe('aide ciblée aux prérequis suisses',()=>{
  it('ne demande pas le CTC avant la théorie en 2026',()=>{
    expect(prerequisiteHints({categoryCode:'B',moment:'THEORY',today:'2026-12-31'})).toEqual([]);
  });
  it('n’utilise pas une date de formation comme date de dépôt en 2027',()=>{
    const [hint]=prerequisiteHints({categoryCode:'B',moment:'THEORY',today:'2027-01-01'});
    expect(hint?.conclusion).toContain('Date de demande inconnue');expect(hint?.blocking).toBe(false);
  });
  it('distingue le dépôt avant et après la frontière vaudoise',()=>{
    const context={categoryCode:'B',moment:'THEORY' as const,today:'2027-01-01',canton:'VD'};
    expect(prerequisiteHints({...context,applicationSubmittedOn:'2026-12-31'})[0]?.conclusion).toContain('Transition applicable');
    expect(prerequisiteHints({...context,applicationSubmittedOn:'2027-01-01'})[0]?.conclusion).toBe('Preuve non renseignée');
  });
  it('utilise le jour local de l’école autour de minuit UTC',()=>{
    const today=civilDateIn('Europe/Zurich',Date.parse('2026-12-31T23:15:00Z'));
    expect(today).toBe('2027-01-01');expect(prerequisiteHints({categoryCode:'A1',moment:'THEORY',today})).toHaveLength(1);
  });
  it('distingue déclaration, contrôle et panne de lecture sans certification',()=>{
    const context={categoryCode:'B',moment:'APPLICATION' as const,today:'2026-10-28'};
    expect(prerequisiteHints({...context,evidence:{'first-aid':{state:'DECLARED'}}})[0]?.conclusion).toBe('Cours déclaré suivi');
    expect(prerequisiteHints({...context,evidence:{'first-aid':{state:'DOCUMENT_REVIEWED'}}})[0]?.conclusion).toBe('Justificatif contrôlé par l’école');
    expect(prerequisiteHints({...context,evidence:{'first-aid':{state:'READ_ERROR'}}})[0]?.conclusion).toBe('Preuve non consultable');
  });
  it('ne calcule les six ans que pour les premiers secours',()=>{
    const context={categoryCode:'B',today:'2026-10-28',evidence:{'first-aid':{state:'DOCUMENT_REVIEWED' as const,completedOn:'2020-10-27'},awareness:{state:'DOCUMENT_REVIEWED' as const,completedOn:'2018-01-01'}}};
    expect(prerequisiteHints({...context,moment:'APPLICATION'})[0]?.conclusion).toContain('plus de 6 ans');
    expect(prerequisiteHints({...context,moment:'PRACTICAL'})[0]?.conclusion).not.toContain('6 ans');
  });
  it('ne demande pas les cours B à un permis C, BE ou M',()=>{
    for(const categoryCode of ['C','BE','M'])expect(prerequisiteHints({categoryCode,moment:'APPLICATION',today:'2026-10-28'})).toEqual([]);
    expect(prerequisiteHints({categoryCode:'C',moment:'PRACTICAL',today:'2026-10-28'}).map(item=>item.id)).toEqual(['additional-theory']);
  });
});
