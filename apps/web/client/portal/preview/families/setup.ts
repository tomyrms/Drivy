import { setupContentSchema, setupSteps, resolvedSetupFormation, type SetupDraft, type SetupPreview, type SetupTemplates } from '../../../setup-model';
import { db, ids, previewSchool, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewFamily, PreviewTools } from '../family';

/** Only the isolated preview imports these synthetic proposals; they are never adopted by a real school. */
const templates: SetupTemplates = { version: 'preview-311', privacy: { id: 'preview-notice', version: 'preview-311',
  noticeText: '[Nom de l’école] utilise ces données synthétiques pour cette démonstration. Contact : [contact données].',
  retentionText: 'Texte synthétique de démonstration. Aucune règle de conservation réelle n’est définie par cet aperçu.' },
  profileFields: ['firstName', 'lastName'].map(field => ({ field: field as 'firstName' | 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' })),
  formations: ['A', 'A1', 'B', 'BE'].map(categoryCode => ({ id: `preview-${categoryCode}`, version: 'preview-311', categoryCode, label: `Permis ${categoryCode}`, durationMinutes: 45,
    competencies: ['Préparer le véhicule', 'Observer et anticiper', 'Adapter son allure'].map((label, sortOrder) => ({ key: `competency-${sortOrder}`, label, description: 'Exemple pédagogique synthétique.', sortOrder })),
    procedureText: 'Déroulement synthétique à relire dans cet aperçu.', qualification: 'NOT_QUALIFIED', coverageNote: 'Programme synthétique, sans qualification réglementaire.' })) };
let draft: SetupDraft;
function review(activate: boolean): SetupPreview {
  const content = draft.content, issues: SetupPreview['issues'] = [];
  const add = (field: string, message: string) => issues.push({ field, message, code: 'SETUP_FIELD_REQUIRED' });
  if (!content.identity.name.trim()) add('identity.name', 'Indiquez le nom de l’école.');
  if (!content.identity.contactEmail.includes('@')) add('identity.contactEmail', 'Indiquez une adresse e-mail valide.');
  if (activate || content.selectedSections.includes('PRIVACY')) for (const field of ['noticeText', 'retentionText'] as const) {
    if (!content.privacy[field].trim()) add(`privacy.${field}`, 'Complétez ce texte avant de confirmer.');
  }
  if (content.selectedSections.includes('CATALOGUE')) content.formations.forEach((item, index) => {
    if (!item.apply) return;
    const formation = resolvedSetupFormation(content, item);
    if (formation.priceCents === null) add(`formations.${index}.priceCents`, 'Saisissez le prix de la leçon.');
    if (!formation.durationMinutes || formation.durationMinutes < 1) add(`formations.${index}.durationMinutes`, 'Indiquez une durée.');
    if (!formation.categoryCode.trim()) add(`formations.${index}.categoryCode`, 'Indiquez le permis.');
    if (!formation.termsText.trim()) add(`formations.${index}.termsText`, 'Complétez les conditions du tarif.');
    if (!formation.validFrom) add(`formations.${index}.validFrom`, 'Indiquez la date de disponibilité.');
  });
  return { schoolId: ids.school, draftVersion: draft.version, schoolVersion: previewSchool.version, configurationVersion: previewSchool.configurationVersion,
    activate, reviewDigest: `preview-${draft.version}-${previewSchool.version}`, ready: !issues.length, issues,
    selectedSections: [...content.selectedSections], content: structuredClone(content), effects: [] };
}
function append(key: string, row: FixtureRecord) { (db[key] ??= []).push(row); }
function applyCatalogue(tools: PreviewTools) {
  for (const item of draft.content.formations) {
    if (!item.apply || !draft.content.selectedSections.includes('CATALOGUE')) continue;
    const value = resolvedSetupFormation(draft.content, item), createdAt = new Date().toISOString();
    const curriculumId = tools.nextId(), policyId = tools.nextId(), offeringId = tools.nextId(), termsId = tools.nextId();
    if (!value.existingOfferingId) {
      const curriculum = { id: curriculumId, schoolId: ids.school, version: 1, revision: 1, categoryCode: value.categoryCode, approved: true, createdAt,
        competencies: value.competencies.map(row => ({ ...row, id: tools.nextId() })) };
      const policy = { id: policyId, schoolId: ids.school, version: 1, categoryCode: value.categoryCode, approved: true, createdAt, approvedAt: createdAt,
        procedureText: value.procedureText, cancellationPolicyText: value.cancellationPolicyText, sourceUrls: value.sourceUrls };
      const offering = { id: offeringId, schoolId: ids.school, version: 1, offeringKey: `preview-${offeringId}`, categoryCode: value.categoryCode, label: value.label, enabled: true,
        curriculumVersionId: curriculumId, policyVersionId: policyId, defaultDurationMinutes: value.durationMinutes, defaultPriceCents: value.priceCents, createdAt, trainings: 0 };
      for (const key of ['curricula', 'catalogue-curricula']) append(key, structuredClone(curriculum));
      for (const key of ['policy-versions', 'catalogue-procedures']) append(key, structuredClone(policy));
      for (const key of ['offerings', 'catalogue-offerings']) append(key, structuredClone(offering));
    }
    const terms = { id: termsId, schoolId: ids.school, version: 1, label: value.label, termsText: value.termsText, validFrom: value.validFrom,
      validUntil: null, approved: true, approvedAt: createdAt, createdAt };
    const productId = tools.nextId();
    const product = { id: productId, schoolId: ids.school, version: 1, productKey: `preview-${productId}`, label: value.label, type: 'INDIVIDUAL_LESSON', categoryCode: value.categoryCode,
      durationMinutes: value.durationMinutes, unitLabel: 'leçon', unitPriceCents: value.priceCents, validFrom: value.validFrom, validUntil: null,
      termsVersionId: termsId, enabled: true, current: true, siteId: null, createdAt };
    for (const key of ['commercial-terms', 'catalogue-terms']) append(key, structuredClone(terms));
    for (const key of ['service-products', 'catalogue-tariffs']) append(key, structuredClone(product));
  }
}
export const setupFamily: PreviewFamily = {
  name: 'setup',
  seed() {
    if (new URLSearchParams(window.location.search).get('page') === 'preparation') previewSchool.status = 'DRAFT';
    draft = { id: ids.school, schoolId: ids.school, version: 1, status: 'DRAFT', currentStep: 'FORMATIONS', updatedAt: stamp, updatedByMembershipId: ids.admin, appliedAt: null,
      content: { selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE'], identity: { name: previewSchool.name, timeZone: previewSchool.timeZone, contactEmail: previewSchool.contactEmail ?? '', contactPhone: null },
        privacy: { noticeText: '', retentionText: '', contactEmail: 'ecole@example.test', templateId: null, templateVersion: null }, profile: { fields: structuredClone(templates.profileFields), effectiveFrom: null },
        formations: [] } };
  },
  read(request, tools) {
    if (request.path === 'setup-draft') return tools.reply(200, tools.envelope(draft));
    if (request.path === 'setup-draft/templates') return tools.reply(200, tools.envelope(templates));
    if (request.path === 'setup-draft/preview') return tools.reply(200, tools.envelope(review(request.query.get('activate') === 'true')));
    return undefined;
  },
  write(request, tools) {
    if (!['setup-draft', 'setup-draft/complete'].includes(request.path)) return undefined;
    if (!tools.versionMatches(draft)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    if (request.path === 'setup-draft' && request.method === 'PUT') {
      const parsed = setupContentSchema.safeParse(request.body.content);
      if (!parsed.success || !setupSteps.includes(request.body.currentStep)) return tools.reply(400, { code: 'INVALID_REQUEST' });
      draft = { ...draft, version: draft.version + 1, content: parsed.data, currentStep: request.body.currentStep, status: 'DRAFT', updatedAt: new Date().toISOString(), appliedAt: null };
      return tools.commit('saveSetupDraft', draft);
    }
    if (request.path === 'setup-draft/complete' && request.method === 'POST') {
      const checked = review(request.body.activate === true);
      if (!checked.ready || request.body.reviewAcknowledged !== true) return tools.reply(409, { code: 'SETUP_REVIEW_REQUIRED' });
      if (request.body.reviewDigest !== checked.reviewDigest || request.body.expectedSchoolVersion !== checked.schoolVersion || request.body.expectedConfigurationVersion !== checked.configurationVersion) return tools.reply(412, { code: 'VERSION_CONFLICT' });
      applyCatalogue(tools);
      if (draft.content.selectedSections.includes('IDENTITY')) Object.assign(previewSchool, draft.content.identity);
      if (checked.activate) previewSchool.status = 'ACTIVE';
      previewSchool.version++; previewSchool.configurationVersion++;
      draft = { ...draft, version: draft.version + 1, status: 'APPLIED', appliedAt: new Date().toISOString() };
      return tools.commit('applySetupDraft', { id: ids.school, schoolId: ids.school, version: draft.version });
    }
    return tools.reply(405, { code: 'METHOD_NOT_ALLOWED' });
  },
  refusalCode: request => request.path.startsWith('setup-draft') ? 'SETUP_REVIEW_REQUIRED' : undefined,
};
