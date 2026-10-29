import type { PreviewFamily, PreviewRequest, PreviewTools } from '../family';
import { dayAfter, db, ids, previewId, today, type FixtureRecord } from '../fixtures';

/**
 * Formations et tarifs, données fictives (#326, #327). Mêmes formes que /formations de l'API, mêmes règles de commande :
 * version attendue dans le corps (pas d'If-Match), tarif modifié = nouvelle version applicable dès aujourd'hui, jamais rétroactive,
 * conditions communes révisées pour les seuls tarifs actuels. Aucun prix n'est inventé : un parcours ancien n'a pas de prix de référence.
 */
const K = { offerings: 'catalogue-offerings', curricula: 'catalogue-curricula', procedures: 'catalogue-procedures', tariffs: 'catalogue-tariffs', terms: 'catalogue-terms' } as const;
const rows = (key: string) => (db[key] ??= []);
const when = (daysAgo: number) => new Date(Date.parse(`${today}T08:00:00Z`) - daysAgo * 86_400_000).toISOString();
const byVersion = (a: FixtureRecord, b: FixtureRecord) => a.version - b.version;
const latest = (list: FixtureRecord[]) => [...list].sort(byVersion).at(-1);
let counter = 3000;
const mint = () => previewId(counter++);

const competencyText = {
  preparation: ['Préparer la conduite', 'Régler le poste de conduite et vérifier le véhicule avant le départ.'],
  observation: ['Observer et anticiper', 'Chercher les indices utiles, contrôler les angles morts et anticiper les autres usagers.'],
  speed: ['Adapter son allure', 'Garder une marge de sécurité selon la visibilité, l’adhérence et les autres usagers.'],
  intersections: ['Franchir les intersections', 'Identifier la priorité, communiquer son intention et franchir sans imposer de freinage.'],
  position: ['Placement et trajectoire', 'Choisir sa voie et tenir une trajectoire avec une marge suffisante.'],
  manoeuvres: ['Manœuvrer', 'Stationner, reculer et repartir après observation de l’espace disponible.'],
} as const;
type Key = keyof typeof competencyText;
const items = (keys: readonly Key[], extra: [string, string, string][] = []): [string, string, string][] => [...keys.map(key => [key, ...competencyText[key]] as [string, string, string]), ...extra];
const procedureText = 'La leçon commence par un point sur l’objectif du jour, suivi de la conduite commentée. Le moniteur propose les exercices selon le niveau, puis résume ce qui a été travaillé et ce qui sera repris à la prochaine leçon.';
const cancellationText = 'Prévenez l’école dès que vous ne pouvez plus venir afin que le créneau puisse être proposé à une autre personne.';
const termsText = 'Le prix indiqué est celui de la prestation au moment de la réservation. Le règlement est effectué auprès de l’école. Les réservations déjà confirmées conservent le prix et les conditions applicables à la date de leur confirmation.';

function seed() {
  const curriculum = (categoryCode: string, revision: number, daysAgo: number, list: [string, string, string][]) => {
    const row = { id: mint(), schoolId: ids.school, categoryCode, revision, approved: true, createdAt: when(daysAgo),
      competencies: list.map(([key, label, description], index) => ({ id: mint(), key, label, description, sortOrder: index * 10 })) };
    rows(K.curricula).push(row); return row;
  };
  const procedure = (categoryCode: string, version: number, daysAgo: number, text = procedureText) => {
    const row = { id: mint(), schoolId: ids.school, categoryCode, version, approved: true, createdAt: when(daysAgo), procedureText: text, cancellationPolicyText: cancellationText, sourceUrls: [] as string[] };
    rows(K.procedures).push(row); return row;
  };
  const offering = (offeringKey: string, categoryCode: string, version: number, daysAgo: number, c: FixtureRecord, p: FixtureRecord, extra: FixtureRecord) => {
    const row = { id: mint(), schoolId: ids.school, offeringKey, categoryCode, version, enabled: true, label: null as string | null, curriculumVersionId: c.id, policyVersionId: p.id,
      defaultDurationMinutes: 45 as number | null, defaultPriceCents: 9000 as number | null, createdAt: when(daysAgo), trainings: 0, ...extra };
    rows(K.offerings).push(row); return row;
  };
  const term = (version: number, label: string, text: string, validFrom: string, validUntil: string | null, daysAgo: number) => {
    const row = { id: mint(), schoolId: ids.school, version, label, termsText: text, validFrom, validUntil, approved: true, createdAt: when(daysAgo) };
    rows(K.terms).push(row); return row;
  };
  const tariff = (productKey: string, version: number, daysAgo: number, t: FixtureRecord, extra: FixtureRecord) => {
    const row = { id: mint(), schoolId: ids.school, productKey, version, label: '', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45 as number | null, unitLabel: 'leçon', unitPriceCents: 9500,
      validFrom: dayAfter(-60), validUntil: null as string | null, termsVersionId: t.id, enabled: true, createdAt: when(daysAgo), siteId: null, ...extra };
    rows(K.tariffs).push(row); return row;
  };

  // Conditions : une version ancienne remplacée, des conditions communes actuelles, deux jeux propres à un tarif.
  const oldTerms = term(1, 'Conditions de l’école', termsText.replace('est effectué auprès de l’école', 'est effectué à l’école, en début de leçon'), dayAfter(-400), dayAfter(-61), 220);
  const commonTerms = term(2, 'Conditions de l’école', termsText, dayAfter(-60), null, 60);
  const examTerms = term(3, 'Conditions · Accompagnement à l’examen', `${termsText} L’accompagnement comprend la préparation du véhicule et la présence du moniteur à l’examen pratique.`, dayAfter(-60), null, 58);
  const vehicleTerms = term(4, 'Conditions · Location du véhicule d’examen', `${termsText} Le véhicule est mis à disposition pour la durée de l’examen uniquement.`, dayAfter(-45), null, 44);
  const trialTerms = term(5, 'Conditions · Séance d’essai', termsText, dayAfter(-200), null, 190);

  // Permis B : un parcours, quatre versions, un jeu de compétences non rattaché.
  const bCurriculum1 = curriculum('B', 1, 200, items(['preparation', 'observation', 'speed', 'intersections']));
  curriculum('B', 2, 120, items(['preparation', 'observation', 'speed', 'intersections', 'position']));
  const bCurriculum3 = curriculum('B', 3, 30, items(['preparation', 'observation', 'speed', 'intersections', 'position', 'manoeuvres'], [['school-local', 'Conduite en ville lausannoise', 'Circuler dans les rues étroites et les zones à priorité de droite fréquentes de la ville.']]));
  const bPolicy1 = procedure('B', 1, 200, 'La leçon commence par un point sur l’objectif du jour.');
  const bPolicy2 = procedure('B', 2, 30);
  const bKey = 'formation-b';
  offering(bKey, 'B', 1, 200, bCurriculum1, bPolicy1, { trainings: 1 });
  offering(bKey, 'B', 2, 160, bCurriculum1, bPolicy1, { trainings: 1 });
  offering(bKey, 'B', 3, 30, bCurriculum3, bPolicy2, { trainings: 1 });
  offering(bKey, 'B', 4, 12, bCurriculum3, bPolicy2, { trainings: 5 });
  tariff('tarif-b-45', 1, 200, oldTerms, { label: 'Leçon de 45 minutes', unitPriceCents: 9000, validFrom: dayAfter(-200) });
  tariff('tarif-b-45', 2, 60, commonTerms, { label: 'Leçon de 45 minutes' });
  tariff('tarif-b-60', 1, 60, commonTerms, { label: 'Leçon de 60 minutes', durationMinutes: 60, unitPriceCents: 12600 });
  tariff('tarif-b-discovery', 1, 40, commonTerms, { label: 'Leçon découverte', durationMinutes: 30, unitPriceCents: 0 });
  tariff('tarif-b-exam', 1, 58, examTerms, { label: 'Accompagnement à l’examen', type: 'EXAM_SUPPORT', durationMinutes: 90, unitLabel: 'accompagnement', unitPriceCents: 18000, validUntil: dayAfter(120) });
  tariff('tarif-b-90', 1, 90, commonTerms, { label: 'Leçon de 90 minutes', durationMinutes: 90, unitPriceCents: 17500, enabled: false });

  // Permis BE : deux parcours qui partagent leurs compétences et leurs règles ; l'ancien n'est plus proposé.
  const beCurriculum = curriculum('BE', 1, 150, items(['preparation', 'observation', 'manoeuvres'], [['trailer-coupling', 'Atteler et dételer', 'Sécuriser l’immobilisation, l’accouplement et les liaisons avant de contrôler l’ensemble.']]));
  const bePolicy = procedure('BE', 1, 150);
  offering('formation-be', 'BE', 1, 150, beCurriculum, bePolicy, { label: 'Standard', defaultDurationMinutes: 60, defaultPriceCents: 14000, trainings: 2 });
  offering('formation-be-intensif', 'BE', 1, 150, beCurriculum, bePolicy, { label: 'Intensif', defaultDurationMinutes: 60, defaultPriceCents: 14000, trainings: 1 });
  offering('formation-be-intensif', 'BE', 2, 20, beCurriculum, bePolicy, { label: 'Intensif', enabled: false, defaultDurationMinutes: 60, defaultPriceCents: 14000, trainings: 1 });
  tariff('tarif-be-60', 1, 90, commonTerms, { label: 'Leçon BE de 60 minutes', categoryCode: 'BE', durationMinutes: 60, unitPriceCents: 14000 });

  // Permis A : ancien parcours sans prix de référence, aucun tarif de leçon. Aucun prix n'est fabriqué.
  const aCurriculum = curriculum('A', 1, 300, items(['preparation', 'observation', 'speed', 'manoeuvres']));
  const aPolicy = procedure('A', 1, 300);
  offering('formation-a', 'A', 1, 300, aCurriculum, aPolicy, { defaultPriceCents: null, trainings: 0 });

  // Prestations sans permis.
  tariff('tarif-service-vehicle', 1, 44, vehicleTerms, { label: 'Location du véhicule d’examen', type: 'EXTERNAL_SERVICE', categoryCode: null, durationMinutes: null, unitLabel: 'forfait', unitPriceCents: 15000, validFrom: dayAfter(-45) });
  tariff('tarif-service-theory', 1, 80, commonTerms, { label: 'Documentation théorique', type: 'EXTERNAL_SERVICE', categoryCode: null, durationMinutes: null, unitLabel: 'unité', unitPriceCents: 3500 });
  tariff('tarif-service-trial', 1, 190, trialTerms, { label: 'Séance d’essai', type: 'EXTERNAL_SERVICE', categoryCode: null, durationMinutes: 30, unitLabel: 'séance', unitPriceCents: 5000, validFrom: dayAfter(-200) });
  tariff('tarif-service-trial', 2, 20, trialTerms, { label: 'Séance d’essai', type: 'EXTERNAL_SERVICE', categoryCode: null, durationMinutes: 30, unitLabel: 'séance', unitPriceCents: 5000, validFrom: dayAfter(-200), enabled: false });
}

/* ------------------------------------------------------------ Dérivations (miroir de formation-catalogue.ts) */

const termsById = (id: string) => rows(K.terms).find(item => item.id === id);
const productHeads = () => {
  const keys = [...new Set(rows(K.tariffs).map(item => item.productKey as string))];
  return keys.map(key => latest(rows(K.tariffs).filter(item => item.productKey === key))!);
};
const publicProduct = (row: FixtureRecord) => { const { schoolId, siteId, ...rest } = row; void schoolId; void siteId; return rest; };
function tariffStatus(product: FixtureRecord): string {
  const terms = termsById(product.termsVersionId);
  if (!product.enabled) return 'DISABLED';
  if (product.validUntil !== null && product.validUntil < today) return 'ENDED';
  if (!terms || !terms.approved) return 'TERMS_NOT_APPROVED';
  if (terms.validUntil !== null && terms.validUntil < today) return 'TERMS_EXPIRED';
  if (product.validFrom > today) return 'NOT_YET';
  if (terms.validFrom > today) return 'TERMS_NOT_YET';
  return 'OFFERED';
}
const offeringHeads = (category?: string) => {
  const keys = [...new Set(rows(K.offerings).filter(item => !category || item.categoryCode === category).map(item => item.offeringKey as string))];
  return keys.map(key => latest(rows(K.offerings).filter(item => item.offeringKey === key))!).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
};
const curriculumOf = (id: string | null) => rows(K.curricula).find(item => item.id === id) ?? null;
const procedureOf = (id: string | null) => rows(K.procedures).find(item => item.id === id) ?? null;
const complete = (head: FixtureRecord) => !!curriculumOf(head.curriculumVersionId)?.approved && !!procedureOf(head.policyVersionId)?.approved && head.defaultDurationMinutes !== null && head.defaultPriceCents !== null;
const ready = (head: FixtureRecord) => head.enabled && !!curriculumOf(head.curriculumVersionId)?.approved && !!procedureOf(head.policyVersionId)?.approved;
function categoryState(programmes: FixtureRecord[], tariffs: { product: FixtureRecord; status: string }[]) {
  const issues: string[] = [];
  if (!programmes.length) issues.push('PROGRAMME_REQUIRED'); else if (programmes.some(head => !complete(head))) issues.push('PROGRAMME_INCOMPLETE');
  if (!tariffs.some(item => item.product.type === 'INDIVIDUAL_LESSON' && ['OFFERED', 'NOT_YET', 'TERMS_NOT_YET'].includes(item.status))) issues.push('LESSON_TARIFF_REQUIRED');
  const state = programmes.length && !programmes.some(ready) && programmes.every(complete) ? 'NOT_OFFERED' : issues.length ? 'INCOMPLETE' : 'READY';
  return { state, issues };
}
const publicHead = (head: FixtureRecord) => ({ id: head.id, version: head.version, enabled: head.enabled, label: head.label, defaultDurationMinutes: head.defaultDurationMinutes,
  hasReferencePrice: head.defaultPriceCents !== null, createdAt: head.createdAt, ready: ready(head), complete: complete(head) });
const contentOf = (curriculum: FixtureRecord | null) => curriculum && { id: curriculum.id, revision: curriculum.revision, approved: curriculum.approved, categoryCode: curriculum.categoryCode, createdAt: curriculum.createdAt, competencies: curriculum.competencies };
const policyOf = (policy: FixtureRecord | null) => policy && { id: policy.id, version: policy.version, approved: policy.approved, categoryCode: policy.categoryCode, createdAt: policy.createdAt,
  procedureText: policy.procedureText, cancellationPolicyText: policy.cancellationPolicyText, sourceUrls: policy.sourceUrls };
const publicTerms = (row: FixtureRecord | undefined) => row ? { id: row.id, version: row.version, label: row.label, termsText: row.termsText, validFrom: row.validFrom, validUntil: row.validUntil, approved: row.approved, createdAt: row.createdAt } : null;
const usageCount = (termsId: string) => productHeads().filter(item => item.termsVersionId === termsId).length;

function tariffView(product: FixtureRecord) {
  const history = rows(K.tariffs).filter(item => item.productKey === product.productKey).sort((a, b) => b.version - a.version);
  return { productKey: product.productKey, head: publicProduct(product), terms: publicTerms(termsById(product.termsVersionId)), status: tariffStatus(product),
    termsSharedWith: Math.max(0, usageCount(product.termsVersionId) - 1), history: history.map(publicProduct), historyTruncated: false };
}
function list() {
  const programmes = offeringHeads(), products = productHeads().map(product => ({ product, status: tariffStatus(product) }));
  const categories = [...new Set([...programmes.map(item => item.categoryCode as string), ...products.flatMap(item => item.product.categoryCode ? [item.product.categoryCode as string] : [])])].sort();
  return { today, canConfigureCatalog: true, uncategorizedTariffCount: products.filter(item => item.product.categoryCode === null).length, categories: categories.map(code => {
    const own = programmes.filter(item => item.categoryCode === code), prices = products.filter(item => item.product.categoryCode === code);
    const lessons = prices.filter(item => item.product.type === 'INDIVIDUAL_LESSON' && ['OFFERED', 'NOT_YET', 'TERMS_NOT_YET'].includes(item.status))
      .sort((a, b) => (a.product.durationMinutes ?? 0) - (b.product.durationMinutes ?? 0) || a.product.unitPriceCents - b.product.unitPriceCents);
    return { categoryCode: code, ...categoryState(own, prices), programmeCount: own.length, tariffCount: prices.length,
      activeTrainings: own.reduce((sum, item) => sum + item.trainings, 0), lessonDurations: [...new Set(own.flatMap(item => item.defaultDurationMinutes ? [item.defaultDurationMinutes as number] : []))].sort((a, b) => a - b),
      lessonTariffs: lessons.map(item => ({ label: item.product.label, durationMinutes: item.product.durationMinutes, unitPriceCents: item.product.unitPriceCents, unitLabel: item.product.unitLabel, upcoming: item.status !== 'OFFERED' })),
      competencyCounts: own.map(item => curriculumOf(item.curriculumVersionId)?.competencies.length ?? 0) };
  }) };
}
function sheet(category: string) {
  const own = offeringHeads(category), products = productHeads().filter(item => item.categoryCode === category);
  if (!own.length && !products.length) return null;
  const all = offeringHeads();
  const programmes = own.map(head => {
    const versions = rows(K.offerings).filter(item => item.offeringKey === head.offeringKey).sort((a, b) => b.version - a.version);
    return { offeringKey: head.offeringKey, head: publicHead(head), curriculum: contentOf(curriculumOf(head.curriculumVersionId)), procedure: policyOf(procedureOf(head.policyVersionId)),
      enrollments: { current: versions[0]!.trainings, previous: versions.slice(1).reduce((sum, item) => sum + item.trainings, 0) },
      sharedCurriculumWith: all.filter(other => other.offeringKey !== head.offeringKey && other.curriculumVersionId === head.curriculumVersionId).map(other => other.offeringKey),
      sharedProcedureWith: all.filter(other => other.offeringKey !== head.offeringKey && other.policyVersionId === head.policyVersionId).map(other => other.offeringKey),
      history: versions.map(item => ({ id: item.id, version: item.version, enabled: item.enabled, label: item.label, curriculumVersionId: item.curriculumVersionId, policyVersionId: item.policyVersionId,
        defaultDurationMinutes: item.defaultDurationMinutes, createdAt: item.createdAt, curriculumRevision: curriculumOf(item.curriculumVersionId)?.revision ?? null, policyVersion: procedureOf(item.policyVersionId)?.version ?? null, trainings: item.trainings })),
      historyTruncated: false };
  });
  const tariffs = products.map(tariffView);
  const used = (column: 'curriculumVersionId' | 'policyVersionId', id: string) => rows(K.offerings).some(item => item[column] === id);
  return { categoryCode: category, today, canConfigureCatalog: true, ...categoryState(own, tariffs.map(item => ({ product: products.find(product => product.productKey === item.productKey)!, status: item.status }))),
    programmes, tariffs, unattached: {
      curricula: rows(K.curricula).filter(item => item.categoryCode === category && !used('curriculumVersionId', item.id)).map(item => ({ id: item.id, number: item.revision, createdAt: item.createdAt })),
      procedures: rows(K.procedures).filter(item => item.categoryCode === category && !used('policyVersionId', item.id)).map(item => ({ id: item.id, number: item.version, createdAt: item.createdAt })) } };
}
function reference(id: string) {
  const version = rows(K.offerings).find(item => item.id === id);
  const usingProgramme = (column: 'curriculumVersionId' | 'policyVersionId') => offeringHeads().filter(head => rows(K.offerings).some(item => item.offeringKey === head.offeringKey && item[column] === id))
    .map(head => ({ offeringKey: head.offeringKey, categoryCode: head.categoryCode, label: head.label, headId: head.id, current: head[column] === id }));
  if (version) {
    const head = latest(rows(K.offerings).filter(item => item.offeringKey === version.offeringKey))!;
    return { kind: 'OFFERING', id, categoryCode: version.categoryCode, current: head.id === id, offeringKey: version.offeringKey, headId: head.id,
      programmes: [{ offeringKey: version.offeringKey, categoryCode: version.categoryCode, label: head.label, headId: head.id, current: head.id === id }],
      offering: { ...publicHead(version), curriculumVersionId: version.curriculumVersionId, policyVersionId: version.policyVersionId },
      curriculum: contentOf(curriculumOf(version.curriculumVersionId)), procedure: policyOf(procedureOf(version.policyVersionId)) };
  }
  const curriculum = curriculumOf(id);
  if (curriculum) { const programmes = usingProgramme('curriculumVersionId'); return { kind: 'CURRICULUM', id, categoryCode: curriculum.categoryCode, current: programmes.some(item => item.current), programmes, curriculum: contentOf(curriculum) }; }
  const policy = procedureOf(id);
  if (policy) { const programmes = usingProgramme('policyVersionId'); return { kind: 'PROCEDURE', id, categoryCode: policy.categoryCode, current: programmes.some(item => item.current), programmes, procedure: policyOf(policy) }; }
  const product = rows(K.tariffs).find(item => item.id === id);
  if (product) {
    const head = latest(rows(K.tariffs).filter(item => item.productKey === product.productKey))!;
    return { kind: 'TARIFF', id, categoryCode: product.categoryCode, current: head.id === id, productKey: product.productKey, headId: head.id, tariff: publicProduct(product),
      terms: publicTerms(termsById(product.termsVersionId)), status: tariffStatus(product), programmes: [] };
  }
  const terms = termsById(id);
  if (terms) {
    const users = rows(K.tariffs).filter(item => item.termsVersionId === id).sort((a, b) => (a.categoryCode ?? '').localeCompare(b.categoryCode ?? '') || b.version - a.version);
    return { kind: 'TERMS', id, categoryCode: null, current: users.some(item => latest(rows(K.tariffs).filter(other => other.productKey === item.productKey))!.id === item.id), terms: publicTerms(terms), programmes: [],
      usedBy: users.map(item => ({ ...publicProduct(item), current: latest(rows(K.tariffs).filter(other => other.productKey === item.productKey))!.id === item.id })) };
  }
  return null;
}

/* ------------------------------------------------------------ Propositions (texte et programme de référence) */

const referenceCompetencies = [...items(['preparation', 'observation', 'speed', 'intersections', 'position', 'manoeuvres']).map(([key, label, description]) => ({ key, label, description })),
  { key: 'independent-driving', label: 'Conduire de façon autonome', description: 'Suivre une direction et préparer ses décisions sans guidage permanent.' },
  { key: 'driver-assistance', label: 'Utiliser les aides à la conduite', description: 'Identifier les limites des aides présentes et garder la responsabilité de la conduite.' }];
const sources = ['https://lepermisdeconduire.ch/categories-de-permis/categorie-b/', 'https://www.vd.ch/mobilite/automobile-et-navigation/permis/criteres-devaluation-a-a1-b-b1-be-f'];
const templates = {
  formations: [
    { id: 'pedagogy-b', version: '2026-10-28.1', categoryCode: 'B', label: 'Permis B', competencies: referenceCompetencies.map(item => item.key === 'preparation' ? { ...item, label: 'Préparer la conduite', description: 'Régler le poste de conduite, vérifier le véhicule et ses commandes avant le départ.' } : item),
      procedureText, durationMinutes: 45, sourceUrls: sources, qualification: 'NOT_QUALIFIED', verifiedOn: '2026-10-28', coverageNote: 'Durée d’apprentissage selon l’âge et transition du CTC 2027 à vérifier au dossier.',
      change: { kind: 'PEDAGOGICAL', effectiveFrom: null, summary: 'Programme propre au permis, avec conservation des adaptations déjà enregistrées.', application: 'Nouvelles inscriptions après confirmation de l’école. Aucune modification des dossiers et évaluations existants.' } },
    { id: 'pedagogy-be', version: '2026-10-28.1', categoryCode: 'BE', label: 'Permis BE', competencies: referenceCompetencies.slice(0, 3), procedureText, durationMinutes: 60, sourceUrls: sources, qualification: 'NOT_QUALIFIED', verifiedOn: '2026-10-28',
      coverageNote: 'Conditions du véhicule tracteur, de la remorque et des dispenses à confirmer.',
      change: { kind: 'REGULATORY', effectiveFrom: dayAfter(60), summary: 'Évolution des conditions de la remorque.', application: 'À relire avant toute application.' } },
  ],
};
const proposals = { procedure: { procedureText, cancellationPolicyText: cancellationText }, commercialTerms: { label: 'Conditions de l’école', termsText } };

/* ------------------------------------------------------------ Commandes */

const refuse = (tools: PreviewTools, status: number, code: string) => tools.reply(status, { code });
const sameCompetencies = (left: readonly FixtureRecord[], right: readonly FixtureRecord[]) => left.length === right.length && left.every((item, index) => item.key === right[index]!.key && item.label === right[index]!.label && item.description === right[index]!.description);

function writeProgramme(request: PreviewRequest, tools: PreviewTools) {
  const body = request.body, head = latest(rows(K.offerings).filter(item => item.offeringKey === body.offeringKey));
  if (!head) return refuse(tools, 404, 'NOT_FOUND');
  if (head.id !== body.expectedOfferingVersionId) return rows(K.offerings).some(item => item.id === body.expectedOfferingVersionId && item.offeringKey === body.offeringKey) ? refuse(tools, 409, 'FORMATION_CHANGED') : refuse(tools, 404, 'NOT_FOUND');
  if (body.source && (!body.competencies || ['label', 'enabled', 'defaultDurationMinutes', 'procedure'].some(key => key in body))) return refuse(tools, 422, 'PROGRAMME_REFERENCE_UPDATE_INVALID');
  const changed: string[] = [];
  let curriculumVersionId = head.curriculumVersionId, policyVersionId = head.policyVersionId;
  if (body.competencies) {
    const current = curriculumOf(head.curriculumVersionId), existing = current?.competencies ?? [];
    if (body.source) {
      const template = templates.formations.find(item => item.id === body.source.templateId && item.version === body.source.templateVersion && item.categoryCode === head.categoryCode);
      if (!template) return refuse(tools, 409, 'PROGRAMME_REFERENCE_CHANGED');
      if (existing.some((item: FixtureRecord, index: number) => { const proposed = body.competencies[index]; return !proposed || proposed.key !== item.key || proposed.label !== item.label || proposed.description !== item.description; })) return refuse(tools, 422, 'PROGRAMME_CUSTOMIZATION_PROTECTED');
    }
    const next = (body.competencies as FixtureRecord[]).map((item, index) => ({ id: mint(), key: item.key ?? `competence-${mint().slice(-6)}`, label: item.label, description: item.description, sortOrder: index * 10 }));
    if (!current || !current.approved || !sameCompetencies(next, existing)) {
      const revision = Math.max(0, ...rows(K.curricula).filter(item => item.categoryCode === head.categoryCode).map(item => item.revision)) + 1;
      const row = { id: mint(), schoolId: ids.school, categoryCode: head.categoryCode, revision, approved: true, createdAt: new Date().toISOString(), competencies: next };
      rows(K.curricula).push(row); curriculumVersionId = row.id; changed.push('competencies');
    }
  }
  if (body.procedure) {
    const current = procedureOf(head.policyVersionId), p = body.procedure;
    const same = current && current.approved && current.procedureText === p.procedureText && current.cancellationPolicyText === p.cancellationPolicyText && JSON.stringify(current.sourceUrls) === JSON.stringify(p.sourceUrls);
    if (!same) {
      const version = Math.max(0, ...rows(K.procedures).filter(item => item.categoryCode === head.categoryCode).map(item => item.version)) + 1;
      const row = { id: mint(), schoolId: ids.school, categoryCode: head.categoryCode, version, approved: true, createdAt: new Date().toISOString(), procedureText: p.procedureText, cancellationPolicyText: p.cancellationPolicyText, sourceUrls: p.sourceUrls };
      rows(K.procedures).push(row); policyVersionId = row.id; changed.push('procedure');
    }
  }
  const label = body.label === undefined ? head.label : body.label; if (label !== head.label) changed.push('label');
  const enabled = body.enabled ?? head.enabled; if (enabled !== head.enabled) changed.push('enabled');
  const duration = body.defaultDurationMinutes ?? head.defaultDurationMinutes; if (duration !== head.defaultDurationMinutes) changed.push('defaultDurationMinutes');
  if (!changed.length) return refuse(tools, 409, 'FORMATION_UNCHANGED');
  if (!curriculumVersionId || !policyVersionId || duration === null) return refuse(tools, 409, 'PROGRAMME_INCOMPLETE');
  // Ancien parcours sans prix de référence : aucun prix n'est fabriqué pour le compléter.
  if (head.defaultPriceCents === null) return refuse(tools, 409, 'PROGRAMME_REFERENCE_PRICE_MISSING');
  if (label !== null && label !== head.label && offeringHeads(head.categoryCode).some(other => other.offeringKey !== head.offeringKey && other.label?.toLowerCase() === label.toLowerCase())) return refuse(tools, 409, 'PROGRAMME_LABEL_TAKEN');
  const created = { ...head, id: tools.nextId(), version: head.version + 1, enabled, label, curriculumVersionId, policyVersionId, defaultDurationMinutes: duration, createdAt: new Date().toISOString(), trainings: 0 };
  rows(K.offerings).push(created);
  return tools.commit('saveFormationProgramme', { id: created.id, schoolId: ids.school, version: created.version, offeringKey: head.offeringKey, categoryCode: head.categoryCode, previousOfferingVersionId: head.id, curriculumVersionId, policyVersionId, changed });
}

function writeTariff(request: PreviewRequest, tools: PreviewTools) {
  const body = request.body;
  if (body.validUntil !== null && body.validUntil < today && body.enabled) return refuse(tools, 422, 'INVALID_INTERVAL');
  if (body.type === 'INDIVIDUAL_LESSON' && (body.durationMinutes === null || body.durationMinutes > 480)) return refuse(tools, 422, 'INVALID_SERVICE_PRODUCT');
  const newTerms = (label: string, text: string, validFrom: string) => {
    const row = { id: tools.nextId(), schoolId: ids.school, version: Math.max(0, ...rows(K.terms).map(item => item.version)) + 1, label: `Conditions · ${label}`.slice(0, 200), termsText: text, validFrom, validUntil: null, approved: true, createdAt: new Date().toISOString() };
    rows(K.terms).push(row); return row;
  };
  if (body.mode === 'CREATE') {
    if (body.type === 'INDIVIDUAL_LESSON' && body.categoryCode === null) return refuse(tools, 422, 'INVALID_SERVICE_PRODUCT');
    if (body.categoryCode !== null && !rows(K.offerings).some(item => item.categoryCode === body.categoryCode)) return refuse(tools, 404, 'NOT_FOUND');
    if (body.validUntil !== null && body.validUntil < body.validFrom) return refuse(tools, 422, 'INVALID_INTERVAL');
    const terms = newTerms(body.label, body.termsText, body.validFrom);
    const row = { id: tools.nextId(), schoolId: ids.school, productKey: `tarif-${tools.nextId().slice(-12)}`, version: 1, label: body.label, type: body.type, categoryCode: body.categoryCode, durationMinutes: body.durationMinutes,
      unitLabel: body.unitLabel, unitPriceCents: body.priceCents, validFrom: body.validFrom, validUntil: body.validUntil, termsVersionId: terms.id, enabled: body.enabled, createdAt: new Date().toISOString(), siteId: null };
    rows(K.tariffs).push(row);
    return tools.commit('saveTariff', { id: row.id, schoolId: ids.school, version: row.version, productKey: row.productKey, categoryCode: row.categoryCode, termsVersionId: terms.id, changed: ['created'] });
  }
  const head = productHeads().find(item => item.productKey === body.productKey);
  if (!head) return refuse(tools, 404, 'NOT_FOUND');
  if (head.id !== body.expectedProductVersionId) return rows(K.tariffs).some(item => item.id === body.expectedProductVersionId && item.productKey === body.productKey) ? refuse(tools, 409, 'TARIFF_CHANGED') : refuse(tools, 404, 'NOT_FOUND');
  const validFrom = head.validFrom > today ? head.validFrom : today;
  if (body.validUntil !== null && body.validUntil < validFrom) return refuse(tools, 422, 'INVALID_INTERVAL');
  const changed = [...(body.label !== head.label ? ['label'] : []), ...(body.type !== head.type ? ['type'] : []), ...(body.durationMinutes !== head.durationMinutes ? ['durationMinutes'] : []),
    ...(body.unitLabel !== head.unitLabel ? ['unitLabel'] : []), ...(body.priceCents !== head.unitPriceCents ? ['unitPriceCents'] : []), ...(body.validUntil !== head.validUntil ? ['validUntil'] : []), ...(body.enabled !== head.enabled ? ['enabled'] : [])];
  let termsVersionId = head.termsVersionId;
  if (body.terms.mode === 'NEW') {
    const current = termsById(head.termsVersionId);
    if (!current || current.termsText !== body.terms.termsText || !current.approved || (current.validUntil !== null && current.validUntil < today)) { termsVersionId = newTerms(body.label, body.terms.termsText, validFrom).id; changed.push('terms'); }
  }
  if (!changed.length) return refuse(tools, 409, 'TARIFF_UNCHANGED');
  const row = { ...head, id: tools.nextId(), version: head.version + 1, label: body.label, type: body.type, durationMinutes: body.durationMinutes, unitLabel: body.unitLabel, unitPriceCents: body.priceCents,
    validFrom, validUntil: body.validUntil, termsVersionId, enabled: body.enabled, createdAt: new Date().toISOString() };
  rows(K.tariffs).push(row);
  return tools.commit('saveTariff', { id: row.id, schoolId: ids.school, version: row.version, productKey: head.productKey, categoryCode: head.categoryCode, previousProductVersionId: head.id, termsVersionId, changed });
}

function writeSharedTerms(request: PreviewRequest, tools: PreviewTools) {
  const body = request.body, old = termsById(body.termsVersionId);
  if (!old) return refuse(tools, 404, 'NOT_FOUND');
  const products = productHeads().filter(item => item.termsVersionId === old.id);
  if (products.length !== body.expectedProductVersionIds.length || products.some(item => !body.expectedProductVersionIds.includes(item.id))) return refuse(tools, 409, 'TERMS_USAGE_CHANGED');
  if (old.termsText === body.termsText) return refuse(tools, 409, 'TERMS_UNCHANGED');
  if (/\[[^\]]*compl[eé]ter[^\]]*\]/iu.test(body.termsText)) return refuse(tools, 422, 'TERMS_INCOMPLETE');
  // Réviser le texte ne prolonge pas les conditions et n'avance pas leur entrée en vigueur.
  const terms = { id: tools.nextId(), schoolId: ids.school, version: Math.max(0, ...rows(K.terms).map(item => item.version)) + 1, label: old.label, termsText: body.termsText,
    validFrom: old.validFrom > today ? old.validFrom : today, validUntil: old.validUntil, approved: true, createdAt: new Date().toISOString() };
  rows(K.terms).push(terms);
  for (const product of products) rows(K.tariffs).push({ ...product, id: tools.nextId(), version: product.version + 1, termsVersionId: terms.id, validFrom: product.validFrom > today ? product.validFrom : today, createdAt: new Date().toISOString() });
  return tools.commit('reviseSharedTerms', { id: terms.id, schoolId: ids.school, version: terms.version, previousTermsVersionId: old.id, updatedTariffs: products.length });
}

export const catalogueFamily: PreviewFamily = {
  name: 'catalogue',
  seed() { if (!rows(K.offerings).length) seed(); },
  read(request, tools) {
    const [first, second, third] = request.segments;
    if (first === 'text-proposals') return tools.reply(200, tools.envelope(proposals));
    if (first === 'setup-draft' && second === 'templates') return tools.reply(200, tools.envelope(templates));
    if (first !== 'formations') return undefined;
    if (!second) return tools.reply(200, tools.envelope(list()));
    if (second === 'sheet') { const value = sheet(request.query.get('category') ?? ''); return value ? tools.reply(200, tools.envelope(value)) : tools.reply(404, { code: 'NOT_FOUND' }); }
    if (second === 'uncategorized-tariffs') return tools.reply(200, tools.envelope({ today, canConfigureCatalog: true, tariffs: productHeads().filter(item => item.categoryCode === null).map(tariffView) }));
    if (second === 'terms') {
      const items = [...rows(K.terms)].sort((a, b) => b.version - a.version).map(item => ({ ...publicTerms(item), tariffs: new Set(rows(K.tariffs).filter(row => row.termsVersionId === item.id).map(row => row.productKey)).size, currentTariffs: usageCount(item.id) }));
      return tools.reply(200, tools.envelope({ items, truncated: false }));
    }
    if (second === 'references' && third) { const value = reference(third); return value ? tools.reply(200, tools.envelope(value)) : tools.reply(404, { code: 'NOT_FOUND' }); }
    return undefined;
  },
  write(request, tools) {
    if (request.method !== 'POST' || request.collection !== 'formations') return undefined;
    if (request.resourceId === 'programmes') return writeProgramme(request, tools);
    if (request.resourceId === 'tariffs') return writeTariff(request, tools);
    if (request.resourceId === 'terms' && request.action === 'revise') return writeSharedTerms(request, tools);
    return undefined;
  },
  refusalCode(request) {
    if (request.collection !== 'formations') return undefined;
    // Un refus crédible pour une saisie valide : le nom de parcours déjà pris, sinon l'autorisation de configurer le catalogue retirée entre-temps.
    if (request.resourceId === 'programmes' && request.body.label) return 'PROGRAMME_LABEL_TAKEN';
    return ['programmes', 'tariffs', 'terms'].includes(request.resourceId ?? '') ? 'CATALOGUE_ACCESS_REQUIRED' : undefined;
  },
};
