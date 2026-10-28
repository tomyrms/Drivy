import {describe,it,expect} from 'vitest';
import {individualCancellationDeadline} from '../client/lesson-planning-model.js';
import {instantToSchoolTime} from '../client/command-core.js';
import {catalogPolicySchema} from '../client/school-api.js';

describe('échéance de la réservation individuelle',()=>{
  const rules={cancellationHours:24,lateAction:'CONTACT' as const};
  it('retire 24 heures absolues lors du passage à l’heure d’été',()=>{
    const deadline=individualCancellationDeadline('2027-03-28T10:00:00Z',rules);
    expect(deadline).toBe('2027-03-27T10:00:00.000Z');
    expect(instantToSchoolTime(deadline!,'Europe/Zurich')).toBe('2027-03-27T11:00');
  });
  it('retire 24 heures absolues lors du passage à l’heure d’hiver',()=>{
    const deadline=individualCancellationDeadline('2027-10-31T10:00:00Z',rules);
    expect(deadline).toBe('2027-10-30T10:00:00.000Z');
    expect(instantToSchoolTime(deadline!,'Europe/Zurich')).toBe('2027-10-30T12:00');
  });
  it('ne fabrique pas d’échéance à partir des anciennes données ou d’une annulation sans frais',()=>{
    const start='2027-01-04T10:00:00Z';
    for(const value of [null,undefined,{cancellationHours:null,lateAction:'CONTACT' as const},{cancellationHours:24,lateAction:'NO_FEE' as const}])expect(individualCancellationDeadline(start,value)).toBeNull();
    expect(individualCancellationDeadline(start,{...rules,cancellationHours:0})).toBe('2027-01-04T10:00:00.000Z');
  });
  it('accepte une réponse de catalogue ancienne sans le nouveau champ',()=>{
    const policy={id:'11111111-1111-4111-8111-111111111111',schoolId:'22222222-2222-4222-8222-222222222222',version:1,categoryCode:'B',
      procedureText:'Déroulement',cancellationPolicyText:'Ancien texte de 24 heures, sans valeur structurée.',sourceUrls:[],approved:true,approvedAt:'2026-10-28T10:00:00Z'};
    expect(catalogPolicySchema.parse(policy).cancellationRules).toBeUndefined();
    expect(catalogPolicySchema.parse({...policy,cancellationRules:null}).cancellationRules).toBeNull();
  });
});
