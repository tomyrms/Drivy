/**
 * Fixture synthétique des lectures et commandes « Formations et tarifs » pour la revue visuelle locale.
 * Elle reproduit la forme des réponses de l'API, pas ses garanties : la durabilité, l'atomicité et l'historique
 * sont prouvés par apps/api/test/formations.integration.test.ts et la recette intégrée.
 */
type Row = Record<string, any>;
interface FixtureOptions { db: Record<string, any>; schoolId: string; uuid: () => string; stamp: string; today: string; state: string | null; collectiveCourses?: boolean }
export type FixtureReply = { status: number; body: unknown } | null;

export function formationFixture({ db, schoolId, uuid, stamp, today, state }: FixtureOptions) {
  let conflictPending = state === 'conflict';
  const envelope = (data: unknown) => ({ data, requestId: uuid(), serverTime: stamp });
  const offerings = (): Row[] => db.offerings, curricula = (): Row[] => db.curricula, procedures = (): Row[] => db['policy-versions'];
  const products = (): Row[] => db['service-products'], terms = (): Row[] => db['commercial-terms'];
  const latest = (rows: Row[], key: string) => [...rows.reduce((map, row) => (map.get(row[key])?.version ?? 0) < row.version ? map.set(row[key], row) : map, new Map<string, Row>()).values()];
  const heads = () => latest(offerings(), 'offeringKey'), tariffHeads = () => latest(products(), 'productKey');
  const curriculum = (id: string | null) => { const row = curricula().find(item => item.id === id); return row ? { id: row.id, revision: row.revision, approved: row.approved, categoryCode: row.categoryCode, createdAt: row.createdAt ?? stamp,
    competencies: row.competencies.map((item: Row) => ({ id: item.id, key: item.key, label: item.label, description: item.description, sortOrder: item.sortOrder })) } : null; };
  const procedure = (id: string | null) => { const row = procedures().find(item => item.id === id); return row ? { id: row.id, version: row.version, approved: row.approved, categoryCode: row.categoryCode, createdAt: row.createdAt ?? stamp,
    procedureText: row.procedureText, cancellationPolicyText: row.cancellationPolicyText, sourceUrls: row.sourceUrls } : null; };
  const termsOf = (id: string) => { const row = terms().find(item => item.id === id); return row ? { id: row.id, version: row.version, label: row.label, termsText: row.termsText, validFrom: row.validFrom, validUntil: row.validUntil, approved: row.approved, createdAt: row.createdAt ?? stamp } : null; };
  const product = (row: Row) => ({ id: row.id, productKey: row.productKey, version: row.version, label: row.label, type: row.type, categoryCode: row.categoryCode, durationMinutes: row.durationMinutes, unitLabel: row.unitLabel,
    unitPriceCents: row.unitPriceCents, validFrom: row.validFrom, validUntil: row.validUntil, termsVersionId: row.termsVersionId, enabled: row.enabled, createdAt: row.createdAt ?? stamp });
  const status = (row: Row) => { const own = termsOf(row.termsVersionId);
    return !row.enabled ? 'DISABLED' : row.validUntil && row.validUntil < today ? 'ENDED' : !own?.approved ? 'TERMS_NOT_APPROVED' : own.validUntil && own.validUntil < today ? 'TERMS_EXPIRED' : row.validFrom > today ? 'NOT_YET' : 'OFFERED'; };
  const tariff = (row: Row) => ({ productKey: row.productKey, head: product(row), terms: termsOf(row.termsVersionId), status: status(row),
    termsSharedWith: tariffHeads().filter(other => other.termsVersionId === row.termsVersionId && other.productKey !== row.productKey).length,
    history: products().filter(item => item.productKey === row.productKey).sort((a, b) => b.version - a.version).map(product), historyTruncated: false });
  const ready = (head: Row) => head.enabled && !!curriculum(head.curriculumVersionId)?.approved && !!procedure(head.policyVersionId)?.approved;
  const complete = (head: Row) => !!curriculum(head.curriculumVersionId)?.approved && !!procedure(head.policyVersionId)?.approved && head.defaultDurationMinutes !== null;
  const trainings = (offeringId: string) => db.trainings.filter((item: Row) => item.offeringId === offeringId && ['ACTIVE', 'PAUSED'].includes(item.status)).length;
  function categoryState(own: Row[], prices: Row[]) {
    const issues: string[] = [];
    if (!own.length) issues.push('PROGRAMME_REQUIRED'); else if (own.some(head => !complete(head))) issues.push('PROGRAMME_INCOMPLETE');
    if (!prices.some(row => row.type === 'INDIVIDUAL_LESSON' && ['OFFERED', 'NOT_YET', 'TERMS_NOT_YET'].includes(status(row)))) issues.push('LESSON_TARIFF_REQUIRED');
    const offered = own.some(ready);
    return { state: own.length && !offered && own.every(complete) ? 'NOT_OFFERED' : issues.length ? 'INCOMPLETE' : 'READY', issues };
  }
  const categories = () => [...new Set([...heads().map(item => item.categoryCode), ...tariffHeads().flatMap(item => item.categoryCode ? [item.categoryCode] : []),
    ...curricula().map(item => item.categoryCode), ...procedures().map(item => item.categoryCode)])].sort((a, b) => a.localeCompare(b, 'fr'));
  const publicHead = (head: Row) => ({ id: head.id, version: head.version, enabled: head.enabled, label: head.label ?? null, defaultDurationMinutes: head.defaultDurationMinutes, hasReferencePrice: true,
    createdAt: head.createdAt ?? stamp, ready: ready(head), complete: complete(head) });
  function sheet(category: string) {
    const own = heads().filter(item => item.categoryCode === category), prices = tariffHeads().filter(item => item.categoryCode === category);
    if (!own.length && !prices.length && !curricula().some(item => item.categoryCode === category)) return null;
    return { categoryCode: category, today, canConfigureCatalog: state !== 'readonly', ...categoryState(own, prices),
      programmes: own.map(head => {
        const versions = offerings().filter(item => item.offeringKey === head.offeringKey).sort((a, b) => b.version - a.version);
        return { offeringKey: head.offeringKey, head: publicHead(head), curriculum: curriculum(head.curriculumVersionId), procedure: procedure(head.policyVersionId),
          enrollments: { current: trainings(head.id), previous: versions.slice(1).reduce((sum, item) => sum + trainings(item.id), 0) },
          sharedCurriculumWith: heads().filter(other => other.offeringKey !== head.offeringKey && other.curriculumVersionId === head.curriculumVersionId).map(other => other.offeringKey),
          sharedProcedureWith: heads().filter(other => other.offeringKey !== head.offeringKey && other.policyVersionId === head.policyVersionId).map(other => other.offeringKey),
          history: versions.map(item => ({ id: item.id, version: item.version, enabled: item.enabled, label: item.label ?? null, curriculumVersionId: item.curriculumVersionId, policyVersionId: item.policyVersionId,
            defaultDurationMinutes: item.defaultDurationMinutes, createdAt: item.createdAt ?? stamp, curriculumRevision: curriculum(item.curriculumVersionId)?.revision ?? null,
            policyVersion: procedure(item.policyVersionId)?.version ?? null, trainings: trainings(item.id) })), historyTruncated: false };
      }),
      tariffs: prices.map(tariff),
      unattached: { curricula: curricula().filter(item => item.categoryCode === category && !offerings().some(offer => offer.curriculumVersionId === item.id)).map(item => ({ id: item.id, number: item.revision, createdAt: stamp })),
        procedures: procedures().filter(item => item.categoryCode === category && !offerings().some(offer => offer.policyVersionId === item.id)).map(item => ({ id: item.id, number: item.version, createdAt: stamp })) } };
  }
  function reference(id: string) {
    const usage = (column: string) => [...new Set(offerings().filter(item => item[column] === id).map(item => item.offeringKey))].map(key => {
      const head = heads().find(item => item.offeringKey === key)!;
      return { offeringKey: key, categoryCode: head.categoryCode, label: head.label ?? null, headId: head.id, current: head[column] === id };
    });
    const offer = offerings().find(item => item.id === id);
    if (offer) { const head = heads().find(item => item.offeringKey === offer.offeringKey)!;
      return { kind: 'OFFERING', id, categoryCode: offer.categoryCode, current: head.id === id, offeringKey: offer.offeringKey, headId: head.id,
        programmes: [{ offeringKey: offer.offeringKey, categoryCode: offer.categoryCode, label: head.label ?? null, headId: head.id, current: head.id === id }],
        offering: { ...publicHead(offer), curriculumVersionId: offer.curriculumVersionId, policyVersionId: offer.policyVersionId },
        curriculum: curriculum(offer.curriculumVersionId), procedure: procedure(offer.policyVersionId) }; }
    const ownCurriculum = curriculum(id);
    if (ownCurriculum) { const programmes = usage('curriculumVersionId'); return { kind: 'CURRICULUM', id, categoryCode: ownCurriculum.categoryCode, current: programmes.some(item => item.current), programmes, curriculum: ownCurriculum }; }
    const ownProcedure = procedure(id);
    if (ownProcedure) { const programmes = usage('policyVersionId'); return { kind: 'PROCEDURE', id, categoryCode: ownProcedure.categoryCode, current: programmes.some(item => item.current), programmes, procedure: ownProcedure }; }
    const price = products().find(item => item.id === id);
    if (price) { const head = tariffHeads().find(item => item.productKey === price.productKey)!;
      return { kind: 'TARIFF', id, categoryCode: price.categoryCode, current: head.id === id, productKey: price.productKey, headId: head.id, programmes: [], tariff: product(price), terms: termsOf(price.termsVersionId), status: status(price) }; }
    const own = termsOf(id);
    if (own) { const users = products().filter(item => item.termsVersionId === id);
      return { kind: 'TERMS', id, categoryCode: null, current: users.some(item => tariffHeads().includes(item)), terms: own, programmes: [], usedBy: users.map(item => ({ ...product(item), current: tariffHeads().includes(item) })) }; }
    return null;
  }
  const newCurriculum = (category: string, items: Row[]) => {
    const row = { id: uuid(), schoolId, version: 1, categoryCode: category, revision: Math.max(0, ...curricula().filter(item => item.categoryCode === category).map(item => item.revision)) + 1, approved: true, createdAt: stamp,
      competencies: items.map((item, index) => ({ id: uuid(), key: item.key ?? `competence-${uuid().slice(-6)}`, label: item.label, description: item.description, sortOrder: index * 10 })) };
    curricula().push(row); return row.id;
  };
  const newProcedure = (category: string, value: Row) => {
    const row = { id: uuid(), schoolId, version: Math.max(0, ...procedures().filter(item => item.categoryCode === category).map(item => item.version)) + 1, categoryCode: category, ...value, approved: true, approvedAt: stamp, createdAt: stamp };
    procedures().push(row); return row.id;
  };
  const newTerms = (label: string, termsText: string, validFrom: string) => {
    const row = { id: uuid(), schoolId, version: Math.max(0, ...terms().map(item => item.version)) + 1, label: `Conditions · ${label}`, termsText, validFrom, validUntil: null, approved: true, approvalReason: '', approvedAt: stamp, createdAt: stamp };
    terms().push(row); return row.id;
  };
  const newProduct = (input: Row): Row => { const { id: _id, version: _version, ...value } = input;
    const row: Row = { ...value, id: uuid(), schoolId, version: Math.max(0, ...products().filter(item => item.productKey === value.productKey).map(item => item.version)) + 1, createdAt: stamp };
    products().push(row); return row; };

  return function handle(method: string, path: string, url: URL, body: Row | null): FixtureReply {
    if (method === 'GET') {
      if (path === 'formations') return { status: 200, body: envelope({ today, canConfigureCatalog: state !== 'readonly', uncategorizedTariffCount: tariffHeads().filter(item => !item.categoryCode).length,
        categories: categories().map(code => { const own = heads().filter(item => item.categoryCode === code), prices = tariffHeads().filter(item => item.categoryCode === code);
          return { categoryCode: code, ...categoryState(own, prices), programmeCount: own.length, tariffCount: prices.length,
            lessonDurations: [...new Set(own.map(head => head.defaultDurationMinutes).filter(Boolean))].sort((a, b) => a - b),
            lessonTariffs: prices.filter(row => row.type === 'INDIVIDUAL_LESSON' && ['OFFERED', 'NOT_YET'].includes(status(row))).map(row => ({ label: row.label, durationMinutes: row.durationMinutes, unitPriceCents: row.unitPriceCents, unitLabel: row.unitLabel, upcoming: status(row) !== 'OFFERED' })),
            competencyCounts: own.map(head => curriculum(head.curriculumVersionId)?.competencies.length ?? 0), activeTrainings: own.reduce((sum, head) => sum + offerings().filter(item => item.offeringKey === head.offeringKey).reduce((total, item) => total + trainings(item.id), 0), 0) }; }) }) };
      if (path === 'formations/sheet') { const value = sheet(url.searchParams.get('category') ?? ''); return value ? { status: 200, body: envelope(value) } : { status: 404, body: { code: 'NOT_FOUND' } }; }
      if (path === 'formations/uncategorized-tariffs') return { status: 200, body: envelope({ today, canConfigureCatalog: state !== 'readonly', tariffs: tariffHeads().filter(item => !item.categoryCode).map(tariff) }) };
      if (path === 'formations/terms') return { status: 200, body: envelope({ truncated: false, items: terms().map(item => ({ ...termsOf(item.id)!, tariffs: new Set(products().filter(row => row.termsVersionId === item.id).map(row => row.productKey)).size,
        currentTariffs: tariffHeads().filter(row => row.termsVersionId === item.id).length })) }) };
      if (path.startsWith('formations/references/')) { const value = reference(path.split('/')[2]!); return value ? { status: 200, body: envelope(value) } : { status: 404, body: { code: 'NOT_FOUND' } }; }
      return null;
    }
    if (method !== 'POST' || !body || !['formations', 'formations/programmes', 'formations/tariffs'].includes(path)) return null;
    if (state === 'mutation-error') return { status: 503, body: { code: 'SERVICE_UNAVAILABLE' } };
    if (state === 'forbidden') return { status: 403, body: { code: 'ACCESS_DENIED' } };
    if (path === 'formations/programmes') {
      let head = heads().find(item => item.offeringKey === body.offeringKey);
      if (!head) return { status: 404, body: { code: 'NOT_FOUND' } };
      if (conflictPending) { conflictPending = false; offerings().push({ ...head, id: uuid(), version: head.version + 1, defaultDurationMinutes: (head.defaultDurationMinutes ?? 45) + 5, createdAt: stamp }); head = heads().find(item => item.offeringKey === body.offeringKey)!; }
      if (head.id !== body.expectedOfferingVersionId) return { status: 409, body: { code: 'FORMATION_CHANGED' } };
      const next = { ...head, id: uuid(), version: head.version + 1, createdAt: stamp,
        ...(body.competencies ? { curriculumVersionId: newCurriculum(head.categoryCode, body.competencies) } : {}),
        ...(body.procedure ? { policyVersionId: newProcedure(head.categoryCode, body.procedure) } : {}),
        ...('label' in body ? { label: body.label } : {}), ...('enabled' in body ? { enabled: body.enabled } : {}), ...('defaultDurationMinutes' in body ? { defaultDurationMinutes: body.defaultDurationMinutes } : {}) };
      offerings().push(next);
      return { status: 201, body: envelope({ id: next.id, schoolId, version: next.version, offeringKey: next.offeringKey, categoryCode: next.categoryCode }) };
    }
    if (path === 'formations/tariffs') {
      if (body.mode === 'CREATE') {
        const row = newProduct({ productKey: `tarif-${uuid()}`, label: body.label, type: body.type, categoryCode: body.categoryCode, siteId: null, durationMinutes: body.durationMinutes, unitLabel: body.unitLabel,
          unitPriceCents: body.priceCents, validFrom: body.validFrom, validUntil: body.validUntil, enabled: body.enabled, termsVersionId: newTerms(body.label, body.termsText, body.validFrom) });
        return { status: 201, body: envelope({ id: row.id, schoolId, version: row.version, productKey: row.productKey }) };
      }
      let head = tariffHeads().find(item => item.productKey === body.productKey);
      if (!head) return { status: 404, body: { code: 'NOT_FOUND' } };
      if (conflictPending) { conflictPending = false; newProduct({ ...head, unitPriceCents: head.unitPriceCents + 200 }); head = tariffHeads().find(item => item.productKey === body.productKey)!; }
      if (head.id !== body.expectedProductVersionId) return { status: 409, body: { code: 'TARIFF_CHANGED' } };
      const validFrom = head.validFrom > today ? head.validFrom : today;
      const row = newProduct({ productKey: head.productKey, label: body.label, type: body.type, categoryCode: head.categoryCode, siteId: null, durationMinutes: body.durationMinutes, unitLabel: body.unitLabel,
        unitPriceCents: body.priceCents, validFrom, validUntil: body.validUntil, enabled: body.enabled, termsVersionId: body.terms.mode === 'NEW' ? newTerms(body.label, body.terms.termsText, validFrom) : head.termsVersionId });
      return { status: 201, body: envelope({ id: row.id, schoolId, version: row.version, productKey: row.productKey }) };
    }
    if (body.intent === 'NEW' && heads().some(item => item.categoryCode === body.categoryCode)) return { status: 409, body: { code: 'FORMATION_ALREADY_EXISTS' } };
    const offeringKey = `formation-${uuid()}`;
    const offer = { id: uuid(), schoolId, version: 1, offeringKey, categoryCode: body.categoryCode, enabled: true, label: body.programmeLabel, defaultDurationMinutes: body.tariff.durationMinutes, defaultPriceCents: body.tariff.priceCents,
      curriculumVersionId: newCurriculum(body.categoryCode, body.competencies), policyVersionId: newProcedure(body.categoryCode, body.procedure), createdAt: stamp };
    offerings().push(offer);
    newProduct({ productKey: `tarif-${uuid()}`, label: body.tariff.label, type: 'INDIVIDUAL_LESSON', categoryCode: body.categoryCode, siteId: null, durationMinutes: body.tariff.durationMinutes, unitLabel: 'leçon',
      unitPriceCents: body.tariff.priceCents, validFrom: body.tariff.validFrom, validUntil: body.tariff.validUntil, enabled: true, termsVersionId: newTerms(body.tariff.label, body.tariff.termsText, body.tariff.validFrom) });
    return { status: 201, body: envelope({ id: offer.id, schoolId, version: 1, offeringKey, categoryCode: body.categoryCode }) };
  };
}
