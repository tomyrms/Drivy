import {describe,it,expect} from 'vitest';
import {swissCategories,swissProgrammeTemplates} from '../src/swiss-programmes.js';
describe('référentiel suisse par catégorie',()=>{
  it('inventorie chaque catégorie avec sources et limites explicites',()=>{
    const templates=swissProgrammeTemplates();expect(templates.map(item=>item.categoryCode)).toEqual([...swissCategories]);
    for(const template of templates){expect(template.sourceUrls.length).toBeGreaterThan(0);expect(template.qualification).toBe('NOT_QUALIFIED');
      expect(template.coverageNote.length).toBeGreaterThan(20);expect(new Set(template.competencies.map(item=>item.key)).size).toBe(template.competencies.length);}
  });
  it('distingue moto, remorque, poids lourd, passagers et préparation théorique',()=>{
    const keys=(code:string)=>swissProgrammeTemplates().find(item=>item.categoryCode===code)!.competencies.map(item=>item.key);
    expect(keys('A1')).toContain('motorcycle-braking');expect(keys('BE')).toContain('trailer-coupling');
    expect(keys('C')).toContain('load-security');expect(keys('D')).toContain('passenger-safety');
    expect(keys('G')).toContain('agricultural-rules');expect(keys('M')).toContain('moped-rules');
    expect(keys('G')).not.toContain('manoeuvres');expect(keys('M')).not.toContain('driver-assistance');
  });
});
