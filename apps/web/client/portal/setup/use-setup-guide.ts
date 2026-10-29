import { useEffect, useRef, useState } from 'react';
import { civilDateIn } from '../../agenda-model';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { RequestFailure } from '../../protocol';
import { confirmedData, offeringSchema, readAll, readSchool } from '../../school-api';
import {
  catalogueSetupContent, initialSetupStep, issueStep, refreshSetupExamples, selectSetupSection, setupContentSchema, setupDraftSchema, setupFormation,
  setupNavigationSteps, setupPreviewSchema, setupTemplatesSchema, type SetupContent, type SetupDraft, type SetupPreview, type SetupStep,
} from '../../setup-model';
import { readError, useCommandRunner, useConsole, useLoad } from '../../console/context';
import type { SectionKey } from '../../console/sections';
import { guideNextStep, matchesReviewedField, templatePrivacy, type StoredSetupDraft } from './setup-guide-model';

const focusPendingRequest = () => window.requestAnimationFrame(() => window.document.getElementById('pending-title')?.focus());
const clone = <T,>(value: T): T => structuredClone(value);
const secondarySteps: readonly SetupStep[] = ['IDENTITY', 'PRIVACY', 'PROFILE'];

/**
 * State and commands of the preparation guide (#320), same behaviour as the historical `SchoolSetupGuide`:
 * one persisted draft (`setup-draft`, If-Match), a server review (`setup-draft/preview`) and an explicit adoption
 * (`setup-draft/complete`). Nothing is confirmed before the school's receipt; a refusal keeps the typing.
 */
export function useSetupGuide({ catalogueOnly, initialCategory, exitTo }: { catalogueOnly: boolean; initialCategory?: string | undefined; exitTo: SectionKey }) {
  const { schoolId, school, navigate, drafts, setNavigationGuard, routeQuery } = useConsole();
  const snapshot = useCommandSnapshot();
  const [document, setDocument] = useState<SetupDraft | null>(null);
  const [content, setContent] = useState<SetupContent | null>(null);
  const [step, setStep] = useState<SetupStep>(catalogueOnly ? 'FORMATIONS' : 'IDENTITY');
  const [dirty, setDirty] = useState(false);
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
  const dirtyRef = useRef(false);
  dirtyRef.current = dirty;
  const needsAdoption = useRef(false);
  const localOperation = useRef<string | null>(null);
  const followedSetup = useRef<{ operationId: string; kind: 'saveSetupDraft' | 'applySetupDraft' } | null>(null);
  const pending = [...snapshot.entries.values()].find(entry => entry.meta.schoolId === schoolId
    && (entry.meta.kind === 'saveSetupDraft' || entry.meta.kind === 'applySetupDraft'));
  const hasPendingRequest = useRef(false);
  hasPendingRequest.current = !!pending;
  if (pending?.meta.kind === 'saveSetupDraft' || pending?.meta.kind === 'applySetupDraft') followedSetup.current = { operationId: pending.meta.operationId, kind: pending.meta.kind };
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
  const steps = setupNavigationSteps(content, catalogueOnly);
  const blocked = saving || runner.busy || !!runner.pending || !!pending || reviewing || needsAdoption.current;
  const key = `setup-draft:${catalogueOnly ? 'catalogue' : 'initial'}`;
  const today = civilDateIn(school.timeZone);
  const finished = () => navigate(catalogueOnly ? exitTo : 'agenda');

  // A receipt may settle a command restored after a page reload, with no local runner.
  useEffect(() => {
    const confirmed = snapshot.confirmed;
    const followed = followedSetup.current;
    if (!confirmed || confirmed.operationId !== followed?.operationId) return;
    followedSetup.current = null;
    if (confirmed.operationId === localOperation.current) return;
    if (followed.kind === 'applySetupDraft') {
      setDirty(false); dirtyRef.current = false; drafts?.delete(key);
      finished();
      return;
    }
    needsAdoption.current = true;
    drafts?.delete(key);
    setReadFailure(null);
    loaded.reload();
  }, [snapshot.confirmed]);

  // Adopt the saved draft once, or again after a save, a conflict or a receipt. A remembered draft is resumed only on the same version.
  useEffect(() => {
    if (!loaded.data || loaded.status !== 'ready') return;
    if (document && !needsAdoption.current) return;
    const saved = loaded.data.draft;
    const remembered = needsAdoption.current ? undefined : drafts?.get(key) as StoredSetupDraft | undefined;
    let next = clone(saved.content), nextStep = catalogueOnly ? saved.currentStep : initialSetupStep(saved, school.status), nextDirty = false;
    if (remembered && remembered.version === saved.version && setupContentSchema.safeParse(remembered.content).success) {
      next = remembered.content; nextStep = remembered.step; nextDirty = remembered.dirty;
    } else if (catalogueOnly && (saved.status === 'APPLIED' || saved.content.selectedSections.length === 0)) {
      next = catalogueSetupContent(next, saved.status === 'APPLIED'); nextStep = 'FORMATIONS'; nextDirty = true;
    } else if (!catalogueOnly && !next.privacy.noticeText && !next.privacy.templateId) {
      next.privacy = templatePrivacy(loaded.data.templates, next); nextDirty = true;
    }
    if (catalogueOnly) {
      nextDirty ||= next.selectedSections.length !== 1 || next.selectedSections[0] !== 'CATALOGUE';
      next = catalogueSetupContent(next);
      const template = loaded.data.templates.formations.find(item => item.categoryCode === initialCategory);
      if (template && next.formations.length === 0 && !loaded.data.offerings.some(item => item.categoryCode === template.categoryCode)) {
        next = { ...next, formations: [setupFormation(template, today)] }; nextDirty = true;
      }
    }
    const availableSteps = setupNavigationSteps(next, catalogueOnly);
    if (nextStep === 'PRICING' && !availableSteps.includes('PRICING')) nextStep = 'REVIEW';
    needsAdoption.current = false;
    setDocument(saved); setContent(next);
    setStep(availableSteps.includes(nextStep) || !catalogueOnly && secondarySteps.includes(nextStep) ? nextStep : availableSteps[0]!);
    setDirty(nextDirty);
    setEditorRevision(revision => revision + 1);
    setPreview(null); setReviewIssues([]); setReviewContent(null); setAcknowledged(false); setReadFailure(null);
  }, [loaded.data, loaded.status]);

  // Memory only, scoped to the school and access: resumed after an in-console navigation, never on another version.
  useEffect(() => {
    if (content && document) drafts?.set(key, { version: document.version, content, step, dirty } satisfies StoredSetupDraft);
  }, [content, document, step, dirty, drafts, key]);
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

  const update = (next: SetupContent) => {
    setContent(content && loaded.data ? refreshSetupExamples(content, next, loaded.data.templates) : next);
    setDirty(true); setPreview(null); setAcknowledged(false); runner.clearOutcome();
  };
  const errorFor = (path: string): string | null => reviewContent && matchesReviewedField(content, reviewContent, path)
    ? reviewIssues.filter(issue => issue.field.replace(/^content\./, '') === path).map(issue => issue.message).join(' ') || null : null;

  async function refreshReview(saved: SetupDraft) {
    setReviewing(true); setReadFailure(null); setAcknowledged(false); setPreview(null);
    try {
      const result = await readSchool(schoolId, 'setup-draft/preview', setupPreviewSchema, { activate: String(school.status === 'DRAFT') });
      if (result.schoolId !== schoolId || result.draftVersion !== saved.version) throw new RequestFailure('VERSION_CONFLICT', 412);
      if (catalogueOnly && result.selectedSections.some(section => section !== 'CATALOGUE')) throw new RequestFailure('SETUP_REVIEW_CHANGED', 409);
      setPreview(result); setReviewIssues(result.issues); setReviewContent(result.content);
    } catch (error) { setReadFailure(readError(error)); } finally { setReviewing(false); }
  }

  async function save(nextStep: SetupStep, value = content, exit = false, afterSave?: () => void) {
    if (!value || !document || blocked) return;
    setSaving(true);
    setReadFailure(null); setPreview(null); setAcknowledged(false);
    try {
      const command = createCommand({ schoolId, kind: 'saveSetupDraft', path: 'setup-draft',
        ifMatch: document.version, resourceVersion: document.version, body: { currentStep: nextStep, content: value } });
      localOperation.current = command.operationId;
      const result = await runner.run(command, 'La préparation est enregistrée.');
      if (result.status !== 'confirmed') {
        localOperation.current = null;
        if (result.status === 'pending') { setLeave(null); focusPendingRequest(); }
        return;
      }
      // Use the exact committed response: a later GET could contain another administrator’s edit.
      const parsed = setupDraftSchema.safeParse(confirmedData(result.body));
      if (!parsed.success || parsed.data.schoolId !== schoolId || parsed.data.id !== schoolId || parsed.data.version !== document.version + 1) throw new RequestFailure('INVALID_RESPONSE');
      const saved = parsed.data;
      setDirty(false); dirtyRef.current = false; needsAdoption.current = false;
      setDocument(saved); setContent(clone(saved.content)); setStep(nextStep);
      drafts?.delete(key);
      if (afterSave) { setLeave(null); afterSave(); }
      else if (exit) navigate(catalogueOnly ? exitTo : 'configuration');
      else if (nextStep === 'REVIEW') await refreshReview(saved);
    } catch (error) { needsAdoption.current = true; setReadFailure(readError(error)); loaded.reload(); }
    finally { setSaving(false); }
  }

  async function finish() {
    if (!preview?.ready || !acknowledged || !document || blocked || dirty || preview.draftVersion !== document.version) return;
    const command = createCommand({ schoolId, kind: 'applySetupDraft', path: 'setup-draft/complete', ifMatch: document.version,
      resourceVersion: document.version, body: { expectedSchoolVersion: preview.schoolVersion, expectedConfigurationVersion: preview.configurationVersion,
        reviewDigest: preview.reviewDigest, reviewAcknowledged: true, activate: preview.activate } });
    localOperation.current = command.operationId;
    const result = await runner.run(command, preview.activate ? 'Votre école est activée.' : 'La préparation est appliquée.');
    if (result.status === 'confirmed') { setDirty(false); dirtyRef.current = false; drafts?.delete(key); finished(); }
    else localOperation.current = null;
  }

  /** « Plus tard » : the step is set aside explicitly, never validated by omission. */
  function skip() {
    if (!content) return;
    if (step === 'PROFILE') void save('FORMATIONS', selectSetupSection(content, 'PROFILE', false));
    if (step === 'FORMATIONS') void save('REVIEW', selectSetupSection({ ...content, formations: content.formations.map(item => ({ ...item, apply: false })) }, 'CATALOGUE', false));
    if (step === 'PRICING') void save('REVIEW', { ...content, formations: content.formations.map(item => ({ ...item, apply: false })) });
  }

  function jump(target: SetupStep, field?: string) {
    if (blocked || !steps.includes(target) && (catalogueOnly || !secondarySteps.includes(target))) return;
    setFocusField(field ?? null);
    if (dirty) void save(target); else { setStep(target); if (target === 'REVIEW' && document) void refreshReview(document); }
  }

  function discardAndReload() {
    setDiscard(false); setDirty(false); runner.clearOutcome(); drafts?.delete(key); needsAdoption.current = true; loaded.reload();
  }
  function leaveWithoutSaving() {
    const proceed = leave; setLeave(null); dirtyRef.current = false; setDirty(false); drafts?.delete(key); proceed?.();
  }
  function retryRead() {
    if (needsAdoption.current) loaded.reload(); else if (document) void refreshReview(document);
  }

  return {
    loaded, document, content, step, steps, dirty, saving, blocked, reviewing, preview, reviewIssues, acknowledged, setAcknowledged,
    readFailure, discard, setDiscard, leave, setLeave, focusField, setFocusField, editorRevision, runner, today, routeQuery,
    nextStep: guideNextStep(steps, step), secondary: !steps.includes(step),
    update, errorFor, save, finish, skip, jump, refreshReview, discardAndReload, leaveWithoutSaving, retryRead,
    stepField: (field: string) => issueStep(field),
  };
}
export type SetupGuideState = ReturnType<typeof useSetupGuide>;
