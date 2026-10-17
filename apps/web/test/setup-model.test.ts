import { describe, expect, test } from 'vitest';
import { catalogueSetupContent, issueStep, setupFormation, setupPrice, setupContentSchema, setupProfileRequirement, setupExampleText, refreshSetupExamples, templateAlreadyAdded } from '../client/setup-model.js';
import { matchSchoolRoute } from '../server/school-routes.js';
import { commandSpecs, createCommand, receiptMatches } from '../client/command-core.js';
import { randomUUID } from 'node:crypto';

describe('Préparation : un permis ne se prépare qu’une fois', () => {
  test('un modèle dont le permis est déjà dans le brouillon est signalé', () => {
    const formations = [{ categoryCode: 'B' }, { categoryCode: 'A1' }];
    expect(templateAlreadyAdded(formations, 'B')).toBe(true);
    expect(templateAlreadyAdded(formations, 'BE')).toBe(false);
    expect(templateAlreadyAdded([], 'B')).toBe(false);
  });
});

describe('Préparation : préserver les choix avant adoption', () => {
  test('un tarif vide, invalide ou négatif ne devient pas gratuit', () => {
    for (const price of ['', ' ', '-4', 'NaN', '1e2', '12.345', '100 CHF']) expect(setupPrice(price)).toBeNull();
    expect(setupPrice('95,50')).toBe(9550);
    expect(setupPrice('0')).toBe(0);
  });
  test('ajouter deux propositions ne partage ni identité ni liste modifiable', () => {
    const source = { id: 'pedagogy-b', version: '1', categoryCode: 'B', label: 'Permis B', competencies: [{ key: 'a', label: 'Observer', description: 'Observer autour de soi.', sortOrder: 0 }], procedureText: 'Proposition', durationMinutes: 45 };
    const one = setupFormation(source, '2026-10-13'), two = setupFormation(source, '2026-10-13');
    one.competencies[0]!.label = 'Adapté';
    expect(two.id).not.toBe(one.id); expect(two.competencies[0]!.label).toBe('Observer');
    expect(one.apply).toBe(false); expect(one.priceCents).toBeNull();
  });
  test('les erreurs de relecture reviennent à leur étape utile', () => {
    expect(issueStep('content.privacy.retentionText')).toBe('PRIVACY');
    expect(issueStep('formations.0.priceCents')).toBe('PRICING');
    expect(issueStep('formations.1.competencies')).toBe('FORMATIONS');
    expect(issueStep('profile.fields')).toBe('PROFILE');
  });
  test('la lecture accepte un brouillon incomplet', () => {
    expect(setupContentSchema.safeParse({ selectedSections: ['IDENTITY'], identity: { name: '', timeZone: '', contactEmail: '', contactPhone: null },
      privacy: { noticeText: '', retentionText: '', contactEmail: '', templateId: null, templateVersion: null }, profile: { fields: [], effectiveFrom: null }, formations: [] }).success).toBe(true);
  });
  test('reprendre le catalogue ne peut pas réadopter les textes d’un brouillon initial', () => {
    const content = setupContentSchema.parse({ selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE', 'CATALOGUE'], identity: { name: 'École', timeZone: 'Europe/Zurich', contactEmail: '', contactPhone: null },
      privacy: { noticeText: 'Texte conservé', retentionText: '', contactEmail: '', templateId: null, templateVersion: null }, profile: { fields: [], effectiveFrom: null }, formations: [setupFormation(null, '2026-10-13'), { ...setupFormation(null, '2026-10-13'), apply: true }] });
    const resumed = catalogueSetupContent(content);
    expect(resumed.selectedSections).toEqual(['CATALOGUE']); expect(resumed.privacy).toEqual(content.privacy); expect(resumed.formations).toHaveLength(2);
    const afterApplication = catalogueSetupContent(content, true);
    expect(afterApplication.formations).toEqual([content.formations[0]]);
    expect(content.selectedSections).toHaveLength(4);
  });
  test('la relecture distingue un champ requis avant un cours et avant une leçon', () => {
    const field = { field: 'birthDate', requirement: 'REQUIRED', stage: 'BEFORE_COURSE', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Préparer le cours.' } as const;
    expect(setupProfileRequirement(field)).toBe('Avant un cours');
    expect(setupProfileRequirement({ ...field, stage: 'BEFORE_LESSON' })).toBe('Avant une leçon');
  });
  test('les coordonnées suivent le modèle intact sans écraser une rédaction adaptée', () => {
    const templates = { version: '2', privacy: { id: 'notice', version: '2', noticeText: '[Nom de l’école] · [contact données]', retentionText: 'Contact : [contact données]' }, profileFields: [], formations: [] };
    const previous = setupContentSchema.parse({ selectedSections: ['IDENTITY', 'PRIVACY'], identity: { name: 'Ancien nom', timeZone: 'Europe/Zurich', contactEmail: 'avant@example.invalid', contactPhone: null },
      privacy: { noticeText: 'Ancien nom · avant@example.invalid', retentionText: 'Contact : avant@example.invalid', contactEmail: 'avant@example.invalid', templateId: 'notice', templateVersion: '2' }, profile: { fields: [], effectiveFrom: null }, formations: [] });
    const identity = { ...previous.identity, name: 'Nouveau nom', contactEmail: 'apres@example.invalid' };
    const updated = refreshSetupExamples(previous, { ...previous, identity }, templates);
    expect(updated.privacy.noticeText).toBe('Nouveau nom · apres@example.invalid');
    expect(updated.privacy.retentionText).toBe('Contact : apres@example.invalid');
    const adapted = { ...previous, privacy: { ...previous.privacy, noticeText: 'Rédaction spécifique de l’école.' } };
    expect(refreshSetupExamples(adapted, { ...adapted, identity }, templates).privacy.noticeText).toBe(adapted.privacy.noticeText);
    expect(setupExampleText('Écrire à [contact données]', updated)).toBe('Écrire à apres@example.invalid');
  });
  test('écriture et adoption ont des reçus distincts et des versions obligatoires', () => {
    const schoolId = randomUUID();
    const command = createCommand({ schoolId, kind: 'saveSetupDraft', path: 'setup-draft', ifMatch: 3, resourceVersion: 3, body: {} });
    expect(commandSpecs.saveSetupDraft.operationType).not.toBe(commandSpecs.applySetupDraft.operationType);
    const receipt = { operationId: command.operationId, commandType: 'SAVE_SCHOOL_SETUP_DRAFT', resourceType: 'SchoolSetupDraft', resourceId: schoolId, resourceVersion: 4, committedAt: '2026-10-13T08:00:00.000Z' };
    expect(receiptMatches(command, receipt)).toBe(true);
    expect(receiptMatches(command, { ...receipt, commandType: 'APPLY_SCHOOL_SETUP_DRAFT' })).toBe(false);
  });
  test('le BFF transmet uniquement les routes et paramètres prévus', () => {
    const base = `/schools/${randomUUID()}/setup-draft`;
    expect(matchSchoolRoute('PUT', base, '')?.route.ifMatch).toBe(true);
    expect(matchSchoolRoute('POST', `${base}/complete`, '')?.route.ifMatch).toBe(true);
    expect(matchSchoolRoute('GET', `${base}/next-actions`, '')).toBeDefined();
    expect(matchSchoolRoute('GET', `${base}/preview`, '?activate=false')?.query).toBe('?activate=false');
    expect(matchSchoolRoute('GET', `${base}/preview`, '?activate=yes')).toBeUndefined();
    expect(matchSchoolRoute('GET', `${base}/preview`, '?activate=true&activate=false')).toBeUndefined();
    expect(matchSchoolRoute('DELETE', base, '')).toBeUndefined();
  });
});
