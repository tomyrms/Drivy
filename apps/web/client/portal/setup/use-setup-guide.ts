import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { civilDateIn } from '../../agenda-model';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { RequestFailure } from '../../protocol';
import { confirmedData, offeringSchema, readAll, readSchool } from '../../school-api';
import {
  catalogueSetupContent, initialSetupStep, issueStep, refreshSetupExamples, selectSetupSection, setupContentSchema, setupDraftSchema, setupFormation,
  setupNavigationSteps, setupPreviewSchema, setupTemplatesSchema, type SetupContent, type SetupDraft, type SetupPreview, type SetupStep,
} from '../../setup-model';
import { readError, useCommandLane, useCommandRunner, useConsole, useLoad } from '../../console/context';
import { rebaseConfirmedDraft } from '../../console/draft-model';
import type { SectionKey } from '../../console/sections';
import { guideNextStep, matchesReviewedField, templatePrivacy, type StoredSetupDraft } from './setup-guide-model';
import { reviewGate } from './setup-review-gate';
import { contentKey, saveOutcome, SetupSaveQueue, type SetupDraftBody, type SetupSaveSend } from './setup-save-queue';

const focusPendingRequest = () => window.requestAnimationFrame(() => window.document.getElementById('pending-title')?.focus());
const clone = <T,>(value: T): T => structuredClone(value);
const secondarySteps: readonly SetupStep[] = ['IDENTITY', 'PRIVACY', 'PROFILE'];
const saveTag = 'setup-draft';

/**
 * State and commands of the preparation guide (#320), with the coalesced save of #123: one persisted draft
 * (`setup-draft`, If-Match), a server review (`setup-draft/preview`) and an explicit adoption
 * (`setup-draft/complete`). « Enregistrer et continuer » hands the draft to a background queue and opens the next step
 * at once; the school's answer is the only thing that makes a draft held, and a refusal keeps the typing.
 */
export function useSetupGuide({ catalogueOnly, initialCategory, exitTo }: { catalogueOnly: boolean; initialCategory?: string | undefined; exitTo: SectionKey }) {
  const { schoolId, school, navigate, drafts, setNavigationGuard, routeQuery, me, membership } = useConsole();
  const snapshot = useCommandSnapshot();
  const [document, setDocument] = useState<SetupDraft | null>(null);
  const [content, setContent] = useState<SetupContent | null>(null);
  const [step, setStep] = useState<SetupStep>(catalogueOnly ? 'FORMATIONS' : 'IDENTITY');
  // Latest editor state, available to the confirmation callback before the next render.
  const contentRef = useRef<SetupContent | null>(content);
  const stepRef = useRef<SetupStep>(step);
  contentRef.current = content;
  stepRef.current = step;
  const [editorRevision, setEditorRevision] = useState(0);
  const [preview, setPreview] = useState<SetupPreview | null>(null);
  const [reviewIssues, setReviewIssues] = useState<SetupPreview['issues']>([]);
  const [reviewContent, setReviewContent] = useState<SetupContent | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const [readFailure, setReadFailure] = useState<string | null>(null);
  const [discard, setDiscard] = useState(false);
  const [leave, setLeave] = useState<(() => void) | null>(null);
  const [focusField, setFocusField] = useState<string | null>(null);
  const needsAdoption = useRef(false);
  const localOperation = useRef<string | null>(null);
  const followedSetup = useRef<{ operationId: string; kind: 'saveSetupDraft' | 'applySetupDraft' } | null>(null);
  const reloadDraft = useRef<() => void>(() => {});

  // One draft save at a time, coalesced; the queue is dropped with the school, the account and the access epoch it was opened for.
  const lane = useCommandLane();
  const runLane = lane.run;
  const scope = `${me.personId}/${schoolId}/${membership.membershipId}/${membership.accessEpoch}`;
  const send = useCallback<SetupSaveSend>(async request => {
    const command = createCommand({ schoolId, kind: 'saveSetupDraft', path: 'setup-draft',
      ifMatch: request.ifMatch, resourceVersion: request.ifMatch, body: { currentStep: request.body.currentStep, content: request.body.content } });
    localOperation.current = command.operationId;
    const started = runLane(command, 'La préparation est enregistrée.', saveTag);
    if (!started.admitted) return { status: 'refused', message: 'Cette préparation est déjà en cours d’enregistrement.' };
    const result = await started.result;
    if (result.status === 'confirmed') {
      const parsed = setupDraftSchema.safeParse(confirmedData(result.body));
      if (!parsed.success || parsed.data.schoolId !== schoolId || parsed.data.id !== schoolId) return { status: 'refused', message: 'La réponse de l’école n’a pas pu être lue.' };
      return { status: 'confirmed', version: parsed.data.version, body: { currentStep: parsed.data.currentStep, content: parsed.data.content } };
    }
    if (result.status === 'rejected') {
      if (result.code === 'VERSION_CONFLICT') return { status: 'conflict' };
      return { status: 'refused', message: result.message };
    }
    return { status: 'unknown', message: result.message };
  }, [schoolId, runLane]);
  const savedDraft = useRef<(body: SetupDraftBody, version: number, sent: SetupDraftBody) => void>(() => {});
  const conflictedDraft = useRef<() => void>(() => {});
  const queue = useMemo(() => new SetupSaveQueue({
    send,
    confirmed: (body, version, sent) => savedDraft.current(body, version, sent),
    conflict: () => conflictedDraft.current(),
  }), [scope, send]);
  useEffect(() => () => queue.dispose(), [queue]);
  const saveState = useSyncExternalStore(queue.subscribe, queue.getSnapshot);
  const runner = useCommandRunner();
  const loaded = useLoad(async () => {
    const [draft, templates, offerings] = await Promise.all([
      readSchool(schoolId, 'setup-draft', setupDraftSchema),
      readSchool(schoolId, 'setup-draft/templates', setupTemplatesSchema),
      readAll(schoolId, 'offerings', offeringSchema),
    ]);
    if (draft.schoolId !== schoolId || draft.id !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { draft, templates, offerings: offerings.items.filter(item => item.enabled) };
  }, [schoolId, snapshot.revision]);
  reloadDraft.current = loaded.reload;
  savedDraft.current = (body, version, sent) => {
    setDocument(previous => previous ? { ...previous, version, currentStep: body.currentStep, content: body.content, status: 'DRAFT' } : previous);
    // The durable answer reaches the real editor: server-only fields are adopted, newer typing is kept, and a
    // same-field conflict stays local. This is also what the next PUT will carry.
    const local = contentRef.current;
    if (local !== null) {
      const rebased = rebaseConfirmedDraft(sent, body, { currentStep: stepRef.current, content: local });
      contentRef.current = rebased.value.content;
      setContent(rebased.value.content);
      if (rebased.value.currentStep !== stepRef.current) {
        stepRef.current = rebased.value.currentStep;
        setStep(rebased.value.currentStep);
      }
    }
    // A summary read for an older version is out of date: it is read again once the save is confirmed.
    setPreview(previous => previous && previous.draftVersion !== version ? null : previous);
  };
  conflictedDraft.current = () => {
    setPreview(null); setReviewIssues([]); setReviewContent(null); setAcknowledged(false);
    reloadDraft.current();
  };

  const steps = setupNavigationSteps(content, catalogueOnly);
  /** A draft request the school must still settle blocks the section; a save still in flight does not. */
  const following = [...snapshot.entries.values()].find(entry => entry.meta.schoolId === schoolId
    && (entry.meta.kind === 'saveSetupDraft' || entry.meta.kind === 'applySetupDraft'));
  const verifying = following !== undefined && (following.meta.kind === 'applySetupDraft' || following.phase !== 'sending');
  const hasPendingRequest = useRef(false);
  hasPendingRequest.current = verifying;
  if (following && (following.meta.kind === 'saveSetupDraft' || following.meta.kind === 'applySetupDraft')) {
    followedSetup.current = { operationId: following.meta.operationId, kind: following.meta.kind };
  }
  const blocked = saving || runner.busy || !!runner.pending || verifying || reviewing || needsAdoption.current;
  const dirty = content !== null && document !== null && !saveState.synced;
  const dirtyRef = useRef(false);
  dirtyRef.current = dirty;
  const key = `setup-draft:${catalogueOnly ? 'catalogue' : 'initial'}`;
  const today = civilDateIn(school.timeZone);
  const finished = () => navigate(catalogueOnly ? exitTo : 'agenda');
  // Le résumé se lit sur un geste de cette visite : naviguer vers « Résumé », ou enregistrer une étape qui y conduit.
  const reviewWanted = useRef(false);
  const review = reviewGate({ step, requested: reviewWanted.current, synced: saveState.synced, blocked, reviewing,
    preview, acknowledged, readFailure: readFailure !== null, phase: saveState.phase });

  // A receipt may settle a command restored after a page reload, with no local runner.
  useEffect(() => {
    const confirmed = snapshot.confirmed;
    const followed = followedSetup.current;
    if (!confirmed || confirmed.operationId !== followed?.operationId) return;
    followedSetup.current = null;
    if (confirmed.operationId === localOperation.current) return;
    if (followed.kind === 'applySetupDraft') {
      drafts?.delete(key);
      finished();
      return;
    }
    needsAdoption.current = true;
    drafts?.delete(key);
    setReadFailure(null);
    loaded.reload();
  }, [snapshot.confirmed]);

  // Adopt the saved draft once, or again after a discard. A remembered draft is resumed only on the same version.
  useEffect(() => {
    if (!loaded.data || loaded.status !== 'ready') return;
    if (document && !needsAdoption.current) return;
    const saved = loaded.data.draft;
    const remembered = needsAdoption.current ? undefined : drafts?.get(key) as StoredSetupDraft | undefined;
    let next = clone(saved.content), nextStep = catalogueOnly ? saved.currentStep : initialSetupStep(saved, school.status);
    if (remembered && remembered.version === saved.version && setupContentSchema.safeParse(remembered.content).success) {
      next = remembered.content; nextStep = remembered.step;
    } else if (catalogueOnly && (saved.status === 'APPLIED' || saved.content.selectedSections.length === 0)) {
      next = catalogueSetupContent(next, saved.status === 'APPLIED'); nextStep = 'FORMATIONS';
    } else if (!catalogueOnly && !next.privacy.noticeText && !next.privacy.templateId) {
      next.privacy = templatePrivacy(loaded.data.templates, next);
    }
    if (catalogueOnly) {
      next = catalogueSetupContent(next);
      const template = loaded.data.templates.formations.find(item => item.categoryCode === initialCategory);
      if (template && next.formations.length === 0 && !loaded.data.offerings.some(item => item.categoryCode === template.categoryCode)) {
        next = { ...next, formations: [setupFormation(template, today)] };
      }
    }
    const availableSteps = setupNavigationSteps(next, catalogueOnly);
    if (nextStep === 'PRICING' && !availableSteps.includes('PRICING')) nextStep = 'REVIEW';
    needsAdoption.current = false;
    // Un brouillon relu ne vaut pas relecture : la revue se redemande par un geste.
    reviewWanted.current = false;
    const shownStep = availableSteps.includes(nextStep) || !catalogueOnly && secondarySteps.includes(nextStep) ? nextStep : availableSteps[0]!;
    setDocument(saved); contentRef.current = next; setContent(next);
    stepRef.current = shownStep; setStep(shownStep);
    setEditorRevision(revision => revision + 1);
    setPreview(null); setReviewIssues([]); setReviewContent(null); setAcknowledged(false); setReadFailure(null);
    queue.adopt(saved.version, { currentStep: saved.currentStep, content: saved.content });
    queue.track({ currentStep: nextStep, content: next });
  }, [loaded.data, loaded.status]);

  // The school's draft moved (another administrator, or a save of ours): the local typing is never replaced by it.
  useEffect(() => {
    if (loaded.status !== 'ready' || !loaded.data || !document || needsAdoption.current) return;
    const saved = loaded.data.draft;
    if (saved.version === document.version || saved.version < document.version) return;
    const edited = content !== null && contentKey(content) !== contentKey(document.content);
    queue.adopt(saved.version, { currentStep: saved.currentStep, content: saved.content });
    setDocument(previous => previous ? { ...previous, ...saved } : previous);
    // A summary read is bound to one draft version: it is read again on the new one.
    setPreview(null); setReviewIssues([]); setReviewContent(null); setAcknowledged(false);
    // Les éditeurs à état local (prix) repartent du contenu relu, pas d'une confirmation de notre propre saisie.
    setEditorRevision(revision => revision + 1);
    if (!edited) {
      const adopted = clone(saved.content);
      contentRef.current = adopted;
      setContent(adopted);
    }
  }, [loaded.data, loaded.status, document]);

  // Memory only, scoped to the school and access: resumed after an in-console navigation, never on another version.
  useEffect(() => {
    if (content && document) drafts?.set(key, { version: document.version, content, step, dirty } satisfies StoredSetupDraft);
  }, [content, document, step, dirty, drafts, key]);
  useEffect(() => {
    if (!content) return;
    queue.track({ currentStep: step, content });
  }, [content, step, queue]);
  useEffect(() => {
    const preventLoss = (event: BeforeUnloadEvent) => { if (dirty) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', preventLoss);
    return () => window.removeEventListener('beforeunload', preventLoss);
  }, [dirty]);
  useEffect(() => {
    setNavigationGuard?.(proceed => {
      if (hasPendingRequest.current) { focusPendingRequest(); return; }
      if (dirtyRef.current) setLeave(() => proceed); else proceed();
    });
    return () => setNavigationGuard?.(null);
  }, [setNavigationGuard]);

  // The summary reads what the school holds: it opens on an explicit gesture, once nothing is being sent.
  useEffect(() => {
    if (!review.read) return;
    reviewWanted.current = false;
    void refreshReview(document?.version);
  }, [review.read, document?.version]);

  const update = (next: SetupContent) => {
    const value = content && loaded.data ? refreshSetupExamples(content, next, loaded.data.templates) : next;
    contentRef.current = value;
    setContent(value);
    setPreview(null); setAcknowledged(false); runner.clearOutcome();
  };
  const errorFor = (path: string): string | null => reviewContent && matchesReviewedField(content, reviewContent, path)
    ? reviewIssues.filter(issue => issue.field.replace(/^content\./, '') === path).map(issue => issue.message).join(' ') || null : null;

  async function refreshReview(version = document?.version) {
    if (version === undefined) return;
    setReviewing(true); setReadFailure(null); setAcknowledged(false); setPreview(null);
    try {
      const result = await readSchool(schoolId, 'setup-draft/preview', setupPreviewSchema, { activate: String(school.status === 'DRAFT') });
      if (result.schoolId !== schoolId || result.draftVersion !== version) throw new RequestFailure('VERSION_CONFLICT', 412);
      if (catalogueOnly && result.selectedSections.some(section => section !== 'CATALOGUE')) throw new RequestFailure('SETUP_REVIEW_CHANGED', 409);
      setPreview(result); setReviewIssues(result.issues); setReviewContent(result.content);
    } catch (error) { setReadFailure(readError(error)); } finally { setReviewing(false); }
  }

  /** « Enregistrer et continuer » : le brouillon part en arrière-plan, l'étape suivante s'ouvre tout de suite. */
  function continueStep(nextStep: SetupStep, value = content) {
    if (!value || !document || blocked) return;
    setReadFailure(null); setAcknowledged(false);
    if (nextStep === 'REVIEW') reviewWanted.current = true;
    queue.enqueue({ currentStep: nextStep, content: value });
    contentRef.current = value; stepRef.current = nextStep;
    setStep(nextStep);
    setFocusField(null);
  }

  /**
   * Explicit save, waited for (« Enregistrer et quitter ») : the same queue, so a request already in flight is awaited
   * instead of being doubled. Nothing is announced unless the school confirmed this exact draft; a lost reply keeps the
   * durable command followed by the store, closes the exit dialog and leaves the verification to the pending panel.
   */
  async function save(nextStep: SetupStep, value = content, exit = false, afterSave?: () => void) {
    if (!value || !document || blocked) return;
    contentRef.current = value; stepRef.current = nextStep;
    setSaving(true); setReadFailure(null); setAcknowledged(false);
    try {
      const body: SetupDraftBody = { currentStep: nextStep, content: value };
      const outcome = saveOutcome(await queue.flush(body), body);
      if (outcome !== 'confirmed') {
        // Un refus, un conflit ou un résultat inconnu se lit sur la page, jamais derrière un dialogue qui bloque la sortie.
        if (afterSave) setLeave(null);
        if (outcome === 'pending') focusPendingRequest();
        return;
      }
      if (afterSave) { setLeave(null); afterSave(); }
      else if (exit) navigate(catalogueOnly ? exitTo : 'configuration');
    } finally { setSaving(false); }
  }

  async function finish() {
    if (!preview || !document || !review.activate || preview.draftVersion !== document.version) return;
    const command = createCommand({ schoolId, kind: 'applySetupDraft', path: 'setup-draft/complete', ifMatch: document.version,
      resourceVersion: document.version, body: { expectedSchoolVersion: preview.schoolVersion, expectedConfigurationVersion: preview.configurationVersion,
        reviewDigest: preview.reviewDigest, reviewAcknowledged: true, activate: preview.activate } });
    localOperation.current = command.operationId;
    const result = await runner.run(command, preview.activate ? 'Votre école est activée.' : 'La préparation est appliquée.');
    if (result.status === 'confirmed') { drafts?.delete(key); finished(); }
    else localOperation.current = null;
  }

  /** « Plus tard » : the step is set aside explicitly, never validated by omission. */
  function skip() {
    if (!content || !document || blocked) return;
    const target: SetupStep = step === 'PROFILE' ? 'FORMATIONS' : 'REVIEW';
    const next = step === 'PROFILE' ? selectSetupSection(content, 'PROFILE', false)
      : step === 'FORMATIONS' ? selectSetupSection({ ...content, formations: content.formations.map(item => ({ ...item, apply: false })) }, 'CATALOGUE', false)
        : { ...content, formations: content.formations.map(item => ({ ...item, apply: false })) };
    update(next);
    continueStep(target, next);
  }

  /**
   * Moving between steps never waits for the school. Reaching the summary is an explicit gesture: it is read on the
   * draft the school holds, so anything typed is handed to the same queue and the summary opens once confirmed.
   */
  function jump(target: SetupStep, field?: string) {
    if (blocked || !steps.includes(target) && (catalogueOnly || !secondarySteps.includes(target))) return;
    setFocusField(field ?? null);
    setReadFailure(null);
    if (target === 'REVIEW') reviewWanted.current = true;
    stepRef.current = target;
    setStep(target);
    if (target === 'REVIEW' && content && document) queue.enqueue({ currentStep: target, content });
  }

  function discardAndReload() {
    setDiscard(false); reviewWanted.current = false; queue.forgetLocal(); runner.clearOutcome(); drafts?.delete(key); needsAdoption.current = true; setReadFailure(null); loaded.reload();
  }
  function leaveWithoutSaving() {
    const proceed = leave; setLeave(null); reviewWanted.current = false; queue.forgetLocal(); drafts?.delete(key); proceed?.();
  }
  function retryRead() {
    if (needsAdoption.current) loaded.reload(); else void refreshReview();
  }

  return {
    loaded, document, content, step, steps, dirty, saving, blocked, reviewing, preview, reviewIssues, acknowledged, setAcknowledged,
    readFailure, discard, setDiscard, leave, setLeave, focusField, setFocusField, editorRevision, runner, today, routeQuery,
    nextStep: guideNextStep(steps, step), secondary: !steps.includes(step),
    saveState, synced: saveState.synced, staleStep: saveState.conflictStep, review,
    update, errorFor, save, continueStep, finish, skip, jump, refreshReview, discardAndReload, leaveWithoutSaving, retryRead,
    retrySave: () => queue.retry(),
    stepField: (field: string) => issueStep(field),
  };
}
export type SetupGuideState = ReturnType<typeof useSetupGuide>;
