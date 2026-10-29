import { ids, previewId, previewSchool, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewFamily } from '../family';

/** Synthetic privacy settings (#330): adopted texts, Drivy proposals, GPS impact, published field policy, GPS option. */
const notice = 'Votre école utilise Drivy pour organiser vos leçons, suivre votre progression et, si vous l’acceptez, enregistrer les trajets de vos leçons.';
const retention = 'Les données de formation sont conservées pendant la durée de la formation puis deux ans après la dernière leçon, sauf obligation légale.';
const policy: FixtureRecord = { schoolId: ids.school, version: 2, status: 'APPROVED', noticeText: notice, retentionText: retention, contactEmail: 'donnees@example.test', approvedAt: stamp, noticeVersionId: previewId(820) };
const proposals = { dataPolicy: { noticeText: notice, retentionText: retention, contactEmail: 'donnees@example.test' },
  profileFields: [{ field: 'contactPhone', requirement: 'REQUIRED', stage: 'BEFORE_LESSON', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous joindre en cas de changement de rendez-vous.' }],
  procedure: { procedureText: '', cancellationPolicyText: '' }, commercialTerms: { label: 'Conditions de l’école', termsText: '' } };
let policies: FixtureRecord[] = [{ id: previewId(830), schoolId: ids.school, version: 1, status: 'PUBLISHED', effectiveFrom: stamp, noticeVersionId: previewId(820), approvedByMembershipId: ids.admin,
  fields: [
    { field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous identifier dans votre école.' },
    { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous identifier dans votre école.' },
    { field: 'contactPhone', requirement: 'REQUIRED', stage: 'BEFORE_LESSON', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous joindre en cas de changement de rendez-vous.' },
    { field: 'birthDate', requirement: 'REQUIRED', stage: 'BEFORE_LESSON', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Pour vérifier l’âge minimal du permis demandé.' },
    { field: 'contactEmail', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Pour recevoir vos bilans par e-mail.' },
  ] }];

export const privacyFamily: PreviewFamily = {
  name: 'privacy',
  read(request, tools) {
    if (request.path === 'data-policy') return tools.reply(200, tools.envelope(policy));
    if (request.path === 'data-policy/impact') return tools.reply(200, tools.envelope({ gpsAgreements: 3, activeCaptures: 1 }));
    if (request.path === 'text-proposals') return tools.reply(200, tools.envelope(proposals));
    if (request.path === 'profile-field-policies') return tools.reply(200, tools.list(policies));
    return undefined;
  },
  write(request, tools) {
    if (request.path === 'data-policy' && request.method === 'PUT') {
      if (!tools.versionMatches(policy)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
      Object.assign(policy, { noticeText: request.body.noticeText, retentionText: request.body.retentionText, contactEmail: request.body.contactEmail,
        status: 'APPROVED', approvedAt: new Date().toISOString(), noticeVersionId: tools.nextId(), version: policy.version + 1 });
      return tools.commit('saveDataPolicy', policy);
    }
    if (request.path === 'profile-field-policies' && request.method === 'POST') {
      const created = { id: tools.nextId(), schoolId: ids.school, version: 1, status: 'PUBLISHED', effectiveFrom: new Date().toISOString(),
        noticeVersionId: request.body.noticeVersionId, approvedByMembershipId: ids.admin, fields: request.body.fields };
      policies = [...policies.map(item => item.status === 'PUBLISHED' ? { ...item, status: 'RETIRED' } : item), created];
      return tools.commit('createProfilePolicy', created);
    }
    if (request.path === 'modules' && request.method === 'PUT') {
      if (!tools.versionMatches(previewSchool)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
      previewSchool.modules = { ...previewSchool.modules, gpsEnabled: request.body.gpsEnabled === true };
      previewSchool.version += 1;
      return tools.commit('updateModules', previewSchool);
    }
    return undefined;
  },
  refusalCode: request => ['data-policy', 'profile-field-policies', 'modules'].includes(request.path) ? 'PRIVACY_CHANGE_REJECTED' : undefined,
};
