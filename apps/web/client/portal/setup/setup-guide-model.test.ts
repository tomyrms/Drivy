import { expect, test } from 'vitest';
import { setupContentSchema, setupFormation } from '../../setup-model';
import { applyProfileChoice, guideNextStep, matchesReviewedField, priceInput, profileFieldDefaults, templatePrivacy } from './setup-guide-model';

const content = () => setupContentSchema.parse({ selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE'],
  identity: { name: 'École synthétique', contactEmail: 'ecole@example.invalid', contactPhone: null, timeZone: 'Europe/Zurich' },
  privacy: { noticeText: 'Texte propre à l’école.', retentionText: 'Conservation propre.', contactEmail: 'donnees@example.invalid', templateId: null, templateVersion: null },
  profile: { fields: structuredClone(profileFieldDefaults), effectiveFrom: null }, formations: [setupFormation(null, '2026-10-29')] });

test('la reprise des textes est une proposition, sans écraser le contenu adopté ni le contact dédié', () => {
  const previous = content();
  const proposal = templatePrivacy({ version: 'synthetic', privacy: { id: 'proposal', version: 'synthetic', noticeText: '[Nom de l’école] : [contact données]', retentionText: 'Écrire à [contact données].' }, profileFields: [], formations: [] }, previous);
  expect(proposal.noticeText).toBe('École synthétique : donnees@example.invalid');
  expect(proposal.contactEmail).toBe('donnees@example.invalid');
  expect(previous.privacy.noticeText).toBe('Texte propre à l’école.');
});

test('un changement de nécessité conserve l’explication de l’école et les autres champs', () => {
  const fields = content().profile.fields;
  const phone = { ...fields.find(field => field.field === 'contactPhone')!, explanation: 'Explication rédigée par cette école.' };
  const previous = fields.map(field => field.field === phone.field ? phone : field);
  const changed = applyProfileChoice(previous, profileFieldDefaults.find(field => field.field === 'contactPhone')!, 'BEFORE_LESSON');
  expect(changed.find(field => field.field === 'contactPhone')).toEqual({ ...phone, requirement: 'REQUIRED', stage: 'BEFORE_LESSON' });
  expect(changed.filter(field => field.field !== 'contactPhone')).toEqual(previous.filter(field => field.field !== 'contactPhone'));
  expect(previous.find(field => field.field === 'contactPhone')!.requirement).toBe('OPTIONAL');
});

test('une erreur de revue ne suit pas un autre permis ou une autre compétence après suppression', () => {
  const reviewed = content();
  const next = structuredClone(reviewed);
  expect(matchesReviewedField(next, reviewed, 'formations.0.priceCents')).toBe(true);
  next.formations[0]!.id = crypto.randomUUID();
  expect(matchesReviewedField(next, reviewed, 'formations.0.priceCents')).toBe(false);
  next.formations[0]!.id = reviewed.formations[0]!.id;
  next.formations[0]!.competencies[0]!.key = 'another';
  expect(matchesReviewedField(next, reviewed, 'formations.0.competencies.0.label')).toBe(false);
});

test('les éditeurs secondaires reviennent au résumé et le prix absent reste distinct de gratuit', () => {
  const steps = ['FORMATIONS', 'PRICING', 'REVIEW'] as const;
  expect(guideNextStep(steps, 'IDENTITY')).toBe('REVIEW');
  expect(guideNextStep(steps, 'PRIVACY')).toBe('REVIEW');
  expect(priceInput(null)).toBe('');
  expect(priceInput(0)).toBe('0');
  expect(priceInput(9550)).toBe('95.50');
});
