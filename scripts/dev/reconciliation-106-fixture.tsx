import React, { useCallback, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { useDraft } from '/apps/web/client/console/context';
import { IdentityEditor } from '/apps/web/client/portal/setup/setup-steps';
import { useSetupGuide } from '/apps/web/client/portal/setup/use-setup-guide';
import '/apps/web/client/portal/portal.css';

const schoolId = '10000000-0000-4000-8000-000000000001';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const serverTime = '2030-01-01T10:00:00Z';
const baseContent = {
  selectedSections: [] as string[],
  identity: { name: '', timeZone: 'Europe/Zurich', contactEmail: '', contactPhone: null as string | null },
  privacy: { noticeText: 'Information synthétique.', retentionText: 'Conservation synthétique.', contactEmail: '', templateId: null as string | null, templateVersion: null as string | null },
  profile: { fields: [] as unknown[], effectiveFrom: null as string | null },
  formations: [] as unknown[],
};
const content = () => structuredClone(baseContent);
const draft = (version: number, currentStep: string, value: typeof baseContent) => ({
  id: schoolId, schoolId, version, status: 'DRAFT', currentStep, content: value,
  updatedAt: '2030-01-01T09:00:00Z', updatedByMembershipId: membershipId, appliedAt: null,
});
const templates = {
  version: 'synthetic-1',
  privacy: { id: 'templates-privacy', version: '1', noticeText: 'Information proposée.', retentionText: 'Conservation proposée.' },
  profileFields: [],
  formations: [],
};

let state = { version: 1, currentStep: 'IDENTITY', content: content() };
let writes: { currentStep: string; content: typeof baseContent }[] = [];
let holding = false, release: (() => void) | null = null, failingDraftRead = false, conflictResponse = false, failedReads = 0, draftReads = 0;

function reply(data: unknown, status = 200) {
  const response = new Response(JSON.stringify(data), {
    status, headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
  });
  Object.defineProperty(response, 'url', { value: currentURL });
  return response;
}
let currentURL = '';
function envelope(data: unknown) { return { data, requestId, serverTime }; }

if (new URLSearchParams(location.search).get('mode') !== 'draft') {
  window.fetch = async (input, init) => {
    const url = String(input);
    currentURL = url;
    const path = new URL(url, location.origin).pathname;
    const method = init?.method ?? 'GET';
    if (method === 'PUT' && path.endsWith('/setup-draft')) {
      const body = JSON.parse(String(init?.body)) as { currentStep: string; content: typeof baseContent };
      writes.push({ currentStep: body.currentStep, content: structuredClone(body.content) });
      if (holding) await new Promise<void>(done => { release = done; });
      state.version += 1;
      state.currentStep = body.currentStep;
      state.content = structuredClone(body.content);
      // Première réponse seulement : l'école normalise le nom reçu avec des espaces.
      if (writes.length === 1) state.content.identity.name = conflictResponse ? 'Serveur Normalisé' : state.content.identity.name.trim();
      return reply(envelope(draft(state.version, state.currentStep, state.content)));
    }
    if (path.endsWith('/setup-draft/templates')) return reply(envelope(templates));
    if (path.endsWith('/setup-draft')) {
      draftReads += 1;
      if (failingDraftRead) { failedReads += 1; return reply({ code: 'SERVICE_UNAVAILABLE' }, 503); }
      return reply(envelope(draft(state.version, state.currentStep, state.content)));
    }
    if (path.endsWith('/offerings')) return reply(envelope({ items: [], nextCursor: null }));
    return reply({ code: 'NOT_FOUND' }, 404);
  };
}

const school = {
  id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'DRAFT',
  contactEmail: 'ecole@example.invalid', contactPhone: null, configurationVersion: 1,
  modules: { gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false },
};
const me = { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN'], grants: [], accessEpoch: 1 };
const consoleValue = {
  schoolId, school, me, membership, canConfigureCatalog: true, routeQuery: {}, navigate: () => {},
  reloadSchool: async () => {}, csrf: () => 'synthetic', refreshCsrf: async () => 'synthetic', login: () => {},
  drafts: new Map(), setNavigationGuard: () => {},
};

type DraftShape = { name: string; email: string; phone: string };
const initialDraft: DraftShape = { name: 'École A', email: 'ecole@example.invalid', phone: '' };
let guardCount = 0;
function DraftInner() {
  const [baseline, setBaseline] = useState(initialDraft);
  const draftState = useDraft<DraftShape>(baseline);
  const latest = useRef(draftState);
  latest.current = draftState;
  (window as any).fixture = {
    batchConflict: () => {
      const sent = latest.current.draft!;
      latest.current.setDraft({ ...sent, email: 'local@example.invalid' });
      latest.current.markSaved({ ...sent, email: 'server@example.invalid' }, sent);
    },
    refresh: () => setBaseline({ ...initialDraft, email: 'server@example.invalid' }),
    resolve: () => { const current = latest.current.draft!; latest.current.setDraft({ ...current, email: 'server@example.invalid' }); },
    adoptEdit: () => {
      const sent = { ...latest.current.draft!, name: ' Ecole ' };
      latest.current.setDraft(sent);
      latest.current.markSaved({ ...sent, name: 'Ecole' }, sent);
      setBaseline({ ...initialDraft, name: 'Ecole' });
    },
    editName: () => { const current = latest.current.draft!; latest.current.setDraft({ ...current, name: 'Autre école' }); },
    editEmail: () => { const current = latest.current.draft!; latest.current.setDraft({ ...current, email: 'autre@example.invalid' }); },
    state: () => ({ draft: latest.current.draft, conflicts: latest.current.conflicts,
      edited: latest.current.edited, guards: guardCount }),
  };
  return <>
    <button id="batch-conflict" onClick={() => (window as any).fixture.batchConflict()}>confirmation concurrente</button>
    <button id="refresh" onClick={() => (window as any).fixture.refresh()}>rafraîchir</button>
    <button id="resolve" onClick={() => (window as any).fixture.resolve()}>résoudre</button>
    <button id="adopt-edit" onClick={() => (window as any).fixture.adoptEdit()}>adoption puis édition</button>
    <button id="edit-name" onClick={() => (window as any).fixture.editName()}>éditer le nom</button>
    <button id="edit-email" onClick={() => (window as any).fixture.editEmail()}>éditer l’e-mail</button>
    <pre id="draft">{JSON.stringify(draftState.draft)}</pre>
    <pre id="conflicts">{JSON.stringify(draftState.conflicts)}</pre>
    <pre id="edited">{String(draftState.edited)}</pre>
  </>;
}

function DraftProbe() {
  const register = useCallback(() => {
    guardCount += 1;
    let released = false;
    return () => { if (!released) { released = true; guardCount -= 1; } };
  }, []);
  return <ConsoleContext.Provider value={{ ...consoleValue, registerUnsavedChanges: register } as any}>
    <DraftInner />
  </ConsoleContext.Provider>;
}

function SetupInner() {
  const guide = useSetupGuide({ catalogueOnly: false, exitTo: 'formations' });
  const latest = useRef(guide);
  latest.current = guide;
  (window as any).fixture = {
    saveSameStep: () => latest.current.continueStep('IDENTITY', latest.current.content),
    content: () => structuredClone(latest.current.content),
    document: () => latest.current.document && structuredClone(latest.current.document),
    step: () => latest.current.step,
    phase: () => latest.current.saveState.phase,
    saveConflicts: () => latest.current.saveState.conflicts,
    reload: () => latest.current.loaded.reload(),
    writes: () => structuredClone(writes),
    waiting: () => holding,
    hold: () => { holding = true; },
    release: () => { holding = false; release?.(); release = null; },
    failRead: () => { failingDraftRead = true; },
    retryRead: () => { failingDraftRead = false; },
    failedReads: () => failedReads,
    draftReads: () => draftReads,
    conflictResponse: () => { conflictResponse = true; },
    state: () => ({ version: state.version, currentStep: state.currentStep, content: structuredClone(state.content) }),
  };
  if (!guide.content) return <p>Chargement…</p>;
  return <main>
    <IdentityEditor content={guide.content} onChange={guide.update} errorFor={guide.errorFor} />
    <pre id="step">{guide.step}</pre>
  </main>;
}

function SetupProbe() {
  return <ConsoleContext.Provider value={consoleValue as any}><SetupInner /></ConsoleContext.Provider>;
}

const mode = new URLSearchParams(location.search).get('mode');
createRoot(document.getElementById('root')!).render(mode === 'draft' ? <DraftProbe /> : <SetupProbe />);
