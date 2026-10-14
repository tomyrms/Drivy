import { issueStep, setupSteps, type SetupContent, type SetupPreview, type SetupStep } from './setup-model.js';

/** Only an explicit omission or a server review can mark a step; saved does not mean validated. */
export function setupStepState(step: SetupStep, content: SetupContent, savedStep: SetupStep, issues: readonly SetupPreview['issues'][number][]): 'Reporté' | 'À revoir' | null {
  const catalogue = content.selectedSections.includes('CATALOGUE');
  const afterFormations = setupSteps.indexOf(savedStep) > setupSteps.indexOf('FORMATIONS');
  const deferred = step === 'PROFILE' && !content.selectedSections.includes('PROFILE')
    || step === 'FORMATIONS' && !catalogue && (afterFormations || content.formations.length > 0)
    || step === 'PRICING' && savedStep === 'REVIEW' && (!catalogue || content.formations.every(formation => !formation.apply));
  if (deferred) return 'Reporté';
  if (issues.some(issue => issueStep(issue.field) === step)) return 'À revoir';
  return null;
}
