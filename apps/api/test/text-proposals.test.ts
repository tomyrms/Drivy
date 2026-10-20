import { describe, expect, it } from 'vitest';
import { proposedCommercialTerms, proposedDataPolicy, proposedProcedure, proposedProfileFields } from '../src/text-proposals.js';
import { POLICY_TEXT_MINIMUM } from '../src/school-setup.js';
import { PLANNING_STAGES } from '../src/profile-completeness.js';

const context = { schoolName: 'École du Lac', contactEmail: 'contact@example.invalid' };

describe('Textes proposés par Drivy', () => {
  it('nomment l’école et son contact, et passent la longueur minimale d’adoption', () => {
    const policy = proposedDataPolicy(context);
    expect(policy.noticeText).toContain('École du Lac');
    expect(policy.noticeText).toContain('contact@example.invalid');
    expect(policy.contactEmail).toBe('contact@example.invalid');
    for (const text of [policy.noticeText, policy.retentionText]) expect([...text.trim()].length).toBeGreaterThanOrEqual(POLICY_TEXT_MINIMUM);
  });
  it('ne citent Mapbox que si le recalage routier passe par Mapbox', () => {
    expect(proposedDataPolicy(context).noticeText).not.toContain('Mapbox');
    expect(proposedDataPolicy({ ...context, mapMatchingProvider: 'osrm' }).noticeText).not.toContain('Mapbox');
    expect(proposedDataPolicy({ ...context, mapMatchingProvider: 'mapbox' }).noticeText).toContain('Mapbox');
  });
  it('ne promettent aucune durée de conservation chiffrée tant qu’aucune suppression automatique ne l’applique', () => {
    expect(proposedDataPolicy(context).retentionText).not.toMatch(/\d+\s*(jours?|mois|ans?)/);
  });
  it('décrit le recalage OSRM dans l’hébergement Drivy sans envoi des positions à un tiers', () => {
    const notice = proposedDataPolicy({ ...context, mapMatchingProvider: 'osrm' }).noticeText;
    expect(notice).toContain('dans l’hébergement de Drivy');
    expect(notice).toContain('sans envoyer vos positions à un service tiers');
    expect(notice).toContain('Apple Plans');
    expect(notice).not.toContain('Mapbox');
    expect(proposedDataPolicy(context).noticeText).not.toContain('Pour caler le trajet');
  });
  it('ne demandent que le prénom et le nom, sans rien qui bloque la planification', () => {
    const required = proposedProfileFields.filter(rule => rule.requirement === 'REQUIRED').map(rule => rule.field);
    expect(required).toEqual(['firstName', 'lastName']);
    expect(proposedProfileFields.filter(rule => rule.requirement !== 'OPTIONAL' && rule.stage !== 'JOIN'
      && (PLANNING_STAGES as readonly string[]).includes(rule.stage))).toEqual([]);
    for (const rule of proposedProfileFields) expect(rule.explanation.trim().length).toBeGreaterThan(0);
  });
  it('proposent un déroulement, une annulation et des conditions non vides', () => {
    const procedure = proposedProcedure(), terms = proposedCommercialTerms(context);
    expect(procedure.procedureText.length).toBeGreaterThan(0);
    expect(procedure.cancellationPolicyText.length).toBeGreaterThan(0);
    expect(terms.termsText).toContain('contact@example.invalid');
  });
});
