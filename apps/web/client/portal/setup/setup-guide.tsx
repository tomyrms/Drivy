import { useEffect, useRef } from 'react';
import { ArrowLeft, Check } from 'lucide-react';
import { setupStepState } from '../../setup-progress';
import { issueStep, setupStepLabels, type SetupStep } from '../../setup-model';
import { useConsole } from '../../console/context';
import type { SectionKey } from '../../console/sections';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Skeleton } from '../../components/ui/skeleton';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import { CheckRow } from './setup-fields';
import { SetupSummary } from './setup-review';
import { FormationsStep, IdentityEditor, PricingStep, PrivacyEditor, ProfileEditor } from './setup-steps';
import { useSetupGuide, type SetupGuideState } from './use-setup-guide';
import './setup.css';

const shortLabels: Record<SetupStep, string> = { IDENTITY: 'Votre école', PRIVACY: 'Confidentialité', PROFILE: 'Informations des élèves', FORMATIONS: 'Permis', PRICING: 'Prix et règles', REVIEW: 'Résumé' };

/** Short progression: the current step, what is set aside and what the server asks to review. Editors opened from the summary stay outside it. */
function GuideProgress({ guide }: { guide: SetupGuideState }) {
  const { steps, step, content, document, reviewIssues, blocked, jump, secondary } = guide;
  if (!content || !document) return null;
  const position = steps.indexOf(step);
  return <nav className="setup-progress" aria-label="Étapes de préparation">
    <p className="setup-progress-count">{secondary ? 'Depuis le résumé' : `Étape ${position + 1} sur ${steps.length}`}</p>
    <ol>{steps.map((item, index) => {
      const state = setupStepState(item, content, document.currentStep, reviewIssues);
      const passed = !secondary && index < position;
      return <li key={item} data-current={item === step || undefined} data-passed={passed || undefined}>
        <button type="button" aria-label={shortLabels[item]} aria-current={item === step ? 'step' : undefined} disabled={blocked} onClick={() => jump(item)}>
          <span className="setup-progress-mark" aria-hidden="true">{passed ? <Check /> : index + 1}</span>
          <span className="setup-progress-label">{shortLabels[item]}</span>
          {state && <Badge variant={state === 'À revoir' ? 'destructive' : 'outline'} className="setup-progress-state">{state}</Badge>}
        </button>
      </li>;
    })}</ol>
  </nav>;
}

/**
 * The single preparation guide (#320): Permis → Prix et règles → Résumé, editors opened from the summary, catalogue mode
 * (`from=formations`) that never re-adopts the school's texts. Commands, versions and receipts are those of the historical guide.
 */
export function SetupGuide({ catalogueOnly }: { catalogueOnly: boolean }) {
  const { routeQuery, canConfigureCatalog, navigate } = useConsole();
  const exitTo: SectionKey = routeQuery?.from === 'prestations' ? 'prestations' : 'formations';
  const guide = useSetupGuide({ catalogueOnly, initialCategory: routeQuery?.category, exitTo });
  const { loaded, content, document, step, steps, dirty, saving, blocked, reviewing, preview, acknowledged, runner, focusField } = guide;
  const heading = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      heading.current?.focus({ preventScroll: true });
      window.scrollTo({ top: 0, behavior: 'instant' });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [step]);
  // A summary issue opens its step, then its field (its disclosure is opened by the same issue).
  useEffect(() => {
    if (!focusField || issueStep(focusField) !== step) return;
    const frame = window.requestAnimationFrame(() => {
      const root = heading.current?.parentElement;
      const path = focusField.replace(/^content\./, '');
      const target = path === 'commonLessonRules.lateAction' ? window.document.getElementById('setup-late-action')
        : [...(root?.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('input[name],textarea[name]') ?? [])]
          .find(input => input.type !== 'hidden' && (input.name === path || input.name.startsWith(`${path}.`)));
      if (target) { target.focus({ preventScroll: true }); target.scrollIntoView({ block: 'center', behavior: 'instant' }); }
      guide.setFocusField(null);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [step, focusField]);

  const title = catalogueOnly && step === 'REVIEW' ? 'Vérifier la formation' : setupStepLabels[step];
  const skippable = !catalogueOnly && (['PROFILE', 'FORMATIONS', 'PRICING'] as SetupStep[]).includes(step);
  const position = steps.indexOf(step);
  const primary = step === 'REVIEW' ? preview?.activate ? 'Adopter les textes et activer l’école' : 'Confirmer la préparation'
    : guide.secondary ? 'Enregistrer et revenir au résumé' : 'Enregistrer et continuer';

  return <section className="setup-page" aria-labelledby="setup-title">
    <header className="setup-heading">
      {catalogueOnly && <Button variant="ghost" size="sm" className="setup-back" onClick={() => navigate(exitTo)}><ArrowLeft aria-hidden="true" />{exitTo === 'prestations' ? 'Prestations' : 'Formations'}</Button>}
      <div className="setup-heading-row">
        <h1 id="setup-title">{catalogueOnly ? 'Préparer une formation' : 'Préparer votre école'}</h1>
        {content && <span className="setup-saved" role="status" data-dirty={dirty || undefined}>{saving || runner.busy ? 'Enregistrement…' : dirty ? 'Modifications non enregistrées' : 'Enregistré'}</span>}
      </div>
    </header>
    <ReadFeedback loaded={loaded} label="Lecture de votre préparation" />
    {guide.readFailure && <Alert variant="destructive"><AlertTitle>Vérification impossible</AlertTitle><AlertDescription>{guide.readFailure}</AlertDescription>
      <Button variant="outline" className="setup-start mt-3" onClick={guide.retryRead}>Réessayer</Button></Alert>}
    {content && document && loaded.data && <>
      <GuideProgress guide={guide} />
      <div className="setup-workspace">
        <h2 ref={heading} tabIndex={-1} className="setup-step-title">{title}</h2>
        <form noValidate onSubmit={event => { event.preventDefault(); if (step === 'REVIEW') void guide.finish(); else void guide.save(guide.nextStep); }}>
          <fieldset className="setup-fieldset" disabled={blocked}>
            {step === 'IDENTITY' && <IdentityEditor content={content} onChange={guide.update} errorFor={guide.errorFor} />}
            {step === 'PRIVACY' && <PrivacyEditor content={content} templates={loaded.data.templates} onChange={guide.update} errorFor={guide.errorFor} />}
            {step === 'PROFILE' && <ProfileEditor content={content} onChange={guide.update} errorFor={guide.errorFor} />}
            {step === 'FORMATIONS' && <FormationsStep content={content} templates={loaded.data.templates} offerings={loaded.data.offerings} initialOfferingId={routeQuery?.selection}
              today={guide.today} onChange={guide.update} canWrite={canConfigureCatalog} errorFor={guide.errorFor} />}
            {step === 'PRICING' && <PricingStep key={`${document.version}:${guide.editorRevision}`} content={content} onChange={guide.update} canWrite={canConfigureCatalog} errorFor={guide.errorFor} />}
            {step === 'REVIEW' && <div className="setup-step-body">
              {!preview && !reviewing && <Button type="button" variant="outline" className="setup-start" onClick={() => dirty ? void guide.save('REVIEW') : void guide.refreshReview(document)}>Vérifier la préparation</Button>}
              {!preview && reviewing && <div className="grid gap-3" role="status" aria-label="Vérification de la préparation"><Skeleton className="h-16 w-full" /><Skeleton className="h-28 w-full" /></div>}
              {preview && <SetupSummary preview={preview} onEdit={guide.jump} />}
              {preview?.ready && <div className="setup-ack"><CheckRow checked={acknowledged} onChange={guide.setAcknowledged} label={preview.activate
                ? 'J’ai relu ces choix et ces textes. Je les adopte pour mon école et confirme son activation.'
                : 'J’ai relu les formations et tarifs sélectionnés. Je confirme leur mise à disposition.'} /></div>}
            </div>}
          </fieldset>
          <div className="setup-feedback">
            <CommandFeedback runner={runner} showSuccess={false} />
            {runner.outcome?.code === 'VERSION_CONFLICT' && <Button type="button" variant="outline" className="setup-start" onClick={() => guide.setDiscard(true)}>Relire la version enregistrée</Button>}
          </div>
          <div className="setup-actions">
            <div className="setup-actions-secondary">
              {position > 0 && <Button type="button" variant="ghost" disabled={blocked} onClick={() => guide.jump(steps[position - 1]!)}><ArrowLeft aria-hidden="true" />Retour</Button>}
              {skippable && <Button type="button" variant="ghost" disabled={blocked} onClick={guide.skip}>Plus tard</Button>}
            </div>
            <div className="setup-actions-main">
              <Button type="button" variant="outline" disabled={blocked} onClick={() => void guide.save(step, content, true)}>Enregistrer et quitter</Button>
              <Button type="submit" disabled={blocked || (step === 'REVIEW' && (!preview?.ready || !acknowledged || dirty))} aria-busy={saving || runner.busy || undefined}>{primary}</Button>
            </div>
          </div>
        </form>
      </div>
    </>}
    <Dialog open={guide.discard} onOpenChange={open => { if (!open) guide.setDiscard(false); }}><DialogContent>
      <DialogHeader><DialogTitle>Relire la préparation enregistrée ?</DialogTitle>
        <DialogDescription>Votre saisie non enregistrée sera remplacée par la version actuellement conservée par l’école.</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" disabled={blocked} onClick={() => guide.setDiscard(false)}>Garder ma saisie</Button>
        <Button disabled={blocked} onClick={guide.discardAndReload}>Abandonner ma saisie et relire</Button></DialogFooter>
    </DialogContent></Dialog>
    <Dialog open={guide.leave !== null} onOpenChange={(open, details) => { if (blocked) details.cancel(); else if (!open) guide.setLeave(null); }}><DialogContent showCloseButton={!blocked}>
      <DialogHeader><DialogTitle>Enregistrer avant de quitter ?</DialogTitle><DialogDescription>Les dernières modifications ne sont pas encore enregistrées.</DialogDescription></DialogHeader>
      <CommandFeedback runner={runner} showSuccess={false} />
      <DialogFooter className="setup-leave-actions">
        <Button variant="ghost" disabled={blocked} onClick={guide.leaveWithoutSaving}>Quitter sans enregistrer</Button>
        <Button variant="outline" disabled={blocked} onClick={() => guide.setLeave(null)}>Continuer la saisie</Button>
        <Button disabled={blocked} onClick={() => { const proceed = guide.leave; if (proceed) void guide.save(step, content, false, proceed); }}>Enregistrer et quitter</Button>
      </DialogFooter>
    </DialogContent></Dialog>
  </section>;
}
