import { useEffect, useRef, useState } from 'react';
import { createCommand, formatCents, parseCents } from '../command-core';
import { formationListSchema, proposalsSchema, readFormationSheet, textProposalsLite } from '../formation-api';
import { civilDateIn } from '../agenda-model';
import { readSchool } from '../school-api';
import { Notice, SegmentField, SelectField, Symbol, TextField, formatCivilDate, formatDuration } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { LoadState, OutcomeNotice } from './layout';
import {
  commonCategories, competencyDrafts, competencyProblems, createFormationBody, emptyCompetency, newTariffDraft, rulesDraft, rulesProblems, tariffProblems,
  wizardCategoryProblem, type WizardDraft,
} from './formation-model';
import { CompetenciesEditor, RulesEditor, TariffFields } from './formation-editors';
import { ConsoleLink, CompetencyList, RulesText } from './formation-sheet';

/*
 * Assistant d'une seule formation : permis → compétences et règles → premier tarif → vérification et création.
 * Les propositions Drivy sont des points de départ modifiables, jamais une adoption ni une validation réglementaire.
 * La création est une seule commande serveur ; elle ne touche ni la confidentialité, ni les informations des élèves, ni l'état de l'école.
 * La saisie reste en mémoire dans cette page (protégée à la sortie), jamais dans le stockage du navigateur.
 */
const steps = ['Permis', 'Compétences et règles', 'Premier tarif', 'Vérification'] as const;
const otherCategory = '__autre__';

export function FormationWizard({ initialCategory }: { initialCategory?: string | undefined }) {
  const { schoolId, school, navigate } = useConsole();
  const list = useLoad(() => readSchool(schoolId, 'formations', formationListSchema), [schoolId]);
  const templates = useLoad(() => readSchool(schoolId, 'setup-draft/templates', proposalsSchema), [schoolId]);
  const texts = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  const today = list.data?.today ?? civilDateIn(school.timeZone);
  const [step, setStep] = useState(0);
  const [attempted, setAttempted] = useState<Record<number, boolean>>({});
  const [choice, setChoice] = useState<string>(initialCategory ? (commonCategories as readonly string[]).includes(initialCategory) ? initialCategory : otherCategory : '');
  const [draft, setDraft] = useState<WizardDraft>(() => ({ category: initialCategory ?? '', intent: 'NEW', programmeLabel: '', competencies: [], rules: rulesDraft(null),
    tariff: newTariffDraft('INDIVIDUAL_LESSON', today), source: null }));
  const [prepared, setPrepared] = useState<string | null>(null);
  // Contenu tel que proposé : un changement de permis le retire seulement s'il n'a pas été modifié.
  const proposed = useRef<string | null>(null);
  const changeCategory = (category: string) => setDraft(current => {
    const untouched = proposed.current !== null && proposed.current === JSON.stringify([current.competencies, current.rules]);
    if (untouched) { proposed.current = null; setPrepared(null); }
    return { ...current, category, intent: 'NEW', programmeLabel: '', ...(untouched ? { competencies: [], rules: rulesDraft(null), source: null } : current.source ? { source: null } : {}) };
  });
  const started = useRef(JSON.stringify(draft));
  const releaseGuard = useUnsavedChanges(JSON.stringify(draft) !== started.current);
  const { drafts } = useConsole();
  const runner = useCommandRunner(() => {
    releaseGuard();
    // Message de confirmation repris une fois par la fiche ouverte ensuite (mémoire de la console, jamais le stockage du navigateur).
    drafts?.set('flash/formations', `La formation du permis ${draft.category.trim()} est créée.`);
    navigate('formations', { category: draft.category.trim(), view: 'general' });
  });
  const headings = useRef<HTMLHeadingElement>(null);
  useEffect(() => { headings.current?.focus({ preventScroll: true }); }, [step]);
  const existing = list.data?.categories.map(item => item.categoryCode) ?? [];
  const category = draft.category.trim();
  const already = existing.includes(category);
  const existingSheet = useLoad(async () => already ? readFormationSheet(schoolId, category) : null, [schoolId, category, already], `${schoolId}/${category}/${already}`);
  const existingNames = existingSheet.data?.programmes.flatMap(item => item.head.label ? [item.head.label] : []) ?? [];
  const blocked = !!runner.pending || runner.busy;

  /** Propositions de départ, appliquées une seule fois par permis et seulement sur des champs vides. */
  function prepare() {
    if (prepared === category) return;
    const template = templates.data?.formations.find(item => item.categoryCode === category);
    setDraft(current => { const next: WizardDraft = {
      ...current,
      competencies: current.competencies.length ? current.competencies : template ? competencyDrafts(template.competencies.map(item => ({ key: item.key, label: item.label, description: item.description }))) : [emptyCompetency()],
      rules: {
        procedureText: current.rules.procedureText || (template?.procedureText ?? ''),
        cancellationPolicyText: current.rules.cancellationPolicyText || (texts.data?.procedure.cancellationPolicyText ?? ''),
        sources: current.rules.sources,
      },
      tariff: { ...current.tariff, duration: current.tariff.duration || String(template?.durationMinutes ?? 45), termsText: current.tariff.termsText || (texts.data?.commercialTerms.termsText ?? '') },
      source: template && !current.competencies.length ? { templateId: template.id, templateVersion: template.version } : current.source,
    }; proposed.current = JSON.stringify([next.competencies, next.rules]); return next; });
    setPrepared(category);
  }
  const problems = [
    wizardCategoryProblem(draft.category, draft.intent, draft.programmeLabel, existing, existingNames),
    competencyProblems(draft.competencies).valid && rulesProblems(draft.rules).valid ? null : 'Complétez les compétences et les règles.',
    tariffProblems(draft.tariff, 'CREATE', today).valid ? null : 'Complétez le premier tarif.',
    null,
  ];
  function next() {
    setAttempted(current => ({ ...current, [step]: true }));
    if (problems[step]) { window.requestAnimationFrame(() => document.querySelector<HTMLElement>('.formation-wizard [aria-invalid="true"], .formation-wizard .field-error')?.focus?.()); return; }
    if (step === 0) prepare();
    setStep(step + 1);
  }
  async function create() {
    if (problems.some(Boolean) || blocked) return;
    const body = createFormationBody(draft);
    if (body.tariff.priceCents === null || body.tariff.durationMinutes === null) return;
    await runner.run(createCommand({ schoolId, kind: 'createFormation', path: 'formations', resourceVersion: 0, body }), `La formation du permis ${category} est créée.`);
  }
  const showErrors = attempted[step] === true;
  const template = templates.data?.formations.find(item => item.categoryCode === category);
  return <div className="section-stack formation-studio settings-studio formation-wizard">
    <div className="formation-back"><ConsoleLink section="formations" query={{}} className="button quiet compact"><Symbol kind="back" bare />Formations et tarifs</ConsoleLink></div>
    <header className="formation-header"><div className="formation-title"><p className="context">Ajouter une formation</p>
      <h1 ref={headings} tabIndex={-1}>{steps[step]}</h1></div></header>
    <ol className="wizard-steps" aria-label="Étapes">{steps.map((label, index) => <li key={label} aria-current={index === step ? 'step' : undefined} className={index < step ? 'done' : undefined}>
      <span className="wizard-step-number" aria-hidden="true">{index + 1}</span>{label}</li>)}</ol>
    <LoadState loaded={list} label="Lecture des formations existantes…">{data => <>
      {!data.canConfigureCatalog && <Notice tone="warning" title="Autorisation nécessaire"><p>Créer une formation enregistre aussi son premier tarif : l’autorisation de configurer les tarifs est nécessaire.</p></Notice>}
      <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <form className="settings-editor formation-editor wide" noValidate onSubmit={event => { event.preventDefault(); if (step === 3) void create(); else next(); }}>
        {step === 0 && <>
          <SelectField label="Permis" value={choice} search placeholder="Choisir un permis" disabled={blocked}
            options={[...commonCategories.map(code => ({ value: code, label: `Permis ${code}${existing.includes(code) ? ' · déjà préparé' : ''}` })), { value: otherCategory, label: 'Autre code' }]}
            onChange={value => { setChoice(value); changeCategory(value === otherCategory ? '' : value); }}
            error={showErrors && choice === '' ? problems[0] : null} />
          {choice === otherCategory && <TextField label="Code du permis" value={draft.category} maxLength={30} disabled={blocked}
            onChange={changeCategory} error={showErrors ? problems[0] : null} />}
          {already && <Notice tone="info" title={`Le permis ${category} est déjà préparé`} live={false} actions={
            <ConsoleLink section="formations" query={{ category }} className="button primary">Ouvrir sa fiche</ConsoleLink>}>
            <p>Pour le modifier, ouvrez sa fiche. Un autre parcours n’est créé que si vous le choisissez ici.</p>
            <SegmentField label="Intention" value={draft.intent} disabled={blocked} options={[{ value: 'NEW', label: 'Ne rien ajouter' }, { value: 'ADDITIONAL_PROGRAMME', label: 'Ajouter un autre parcours' }]}
              onChange={intent => setDraft(current => ({ ...current, intent }))} />
          </Notice>}
          {draft.intent === 'ADDITIONAL_PROGRAMME' && <TextField label="Nom du nouveau parcours" value={draft.programmeLabel} maxLength={120} disabled={blocked}
            hint="Par exemple « Formation accélérée ». Les tarifs du permis restent communs à ses parcours." onChange={programmeLabel => setDraft(current => ({ ...current, programmeLabel }))}
            error={showErrors ? problems[0] : null} />}
          {showErrors && problems[0] && choice !== '' && choice !== otherCategory && draft.intent !== 'ADDITIONAL_PROGRAMME' && <p className="field-error" tabIndex={-1}><Symbol kind="alert" bare />{problems[0]}</p>}
        </>}
        {step === 1 && <>
          {draft.source && <Notice tone="info" title="Proposition Drivy à relire" live={false}
            actions={<button type="button" className="button quiet" disabled={blocked} onClick={() => setDraft(current => ({ ...current, competencies: [emptyCompetency()], source: null }))}>Partir d’une liste vide</button>}>
            <p>Ces compétences et ce déroulement sont des points de départ pour le permis {category}. Adaptez-les : rien n’est enregistré avant la création, et ils ne valent pas validation réglementaire.</p>
          </Notice>}
          <CompetenciesEditor items={draft.competencies} onChange={competencies => setDraft(current => ({ ...current, competencies }))} disabled={blocked} showErrors={showErrors} />
          <h2 className="section-title">Déroulement et annulation</h2>
          <RulesEditor draft={draft.rules} onChange={rules => setDraft(current => ({ ...current, rules }))} disabled={blocked} showErrors={showErrors}
            example={texts.data ? { procedureText: template?.procedureText ?? texts.data.procedure.procedureText, cancellationPolicyText: texts.data.procedure.cancellationPolicyText } : null} />
        </>}
        {step === 2 && <>
          <p className="caption">Un tarif de leçon pour le permis {category}. D’autres tarifs s’ajoutent ensuite depuis sa fiche. Le prix n’est jamais prérempli.</p>
          <TariffFields draft={draft.tariff} onChange={tariff => setDraft(current => ({ ...current, tariff }))} disabled={blocked} showErrors={showErrors} mode="CREATE" today={today} types={['INDIVIDUAL_LESSON']} />
        </>}
        {step === 3 && <WizardReview draft={draft} />}
        <div className="form-save-bar formation-save-bar">
          {step === 3 && <p className="caption save-effect">La création enregistre ces éléments en une seule opération. Elle ne modifie ni la confidentialité, ni les informations demandées aux élèves, ni l’état de l’école.</p>}
          <div className="button-row compact">
            {step > 0 && <button type="button" className="button quiet" disabled={blocked} onClick={() => setStep(step - 1)}><Symbol kind="back" bare />Précédent</button>}
            <button type="submit" className="button primary" disabled={blocked || !data.canConfigureCatalog || (step === 0 && already && draft.intent === 'NEW')} aria-busy={runner.busy}>
              {step === 3 ? (runner.busy ? 'Création…' : 'Créer la formation') : 'Continuer'}</button>
          </div>
        </div>
      </form>
    </>}</LoadState>
  </div>;
}

function WizardReview({ draft }: { draft: WizardDraft }) {
  const cents = parseCents(draft.tariff.price);
  return <div className="wizard-review">
    <dl className="settings-values">
      <div><dt>Permis</dt><dd>{draft.category.trim()}</dd></div>
      {draft.intent === 'ADDITIONAL_PROGRAMME' && <div><dt>Nouveau parcours</dt><dd>{draft.programmeLabel.trim()}</dd></div>}
      <div><dt>Premier tarif</dt><dd>{draft.tariff.label.trim()} · {formatDuration(Number(draft.tariff.duration))} · {cents === null ? '—' : formatCents(cents)} par {draft.tariff.unitLabel.trim()}</dd></div>
      <div><dt>Validité</dt><dd>{draft.tariff.validUntil ? `Du ${formatCivilDate(draft.tariff.validFrom)} au ${formatCivilDate(draft.tariff.validUntil)}` : `À partir du ${formatCivilDate(draft.tariff.validFrom)}`}</dd></div>
    </dl>
    <details className="disclosure compact" open><summary>Compétences ({draft.competencies.length})</summary>
      <CompetencyList items={draft.competencies.map(item => ({ key: item.uid, label: item.label.trim(), description: item.description.trim() }))} /></details>
    <details className="disclosure compact"><summary>Déroulement et annulation</summary>
      <RulesText procedure={{ procedureText: draft.rules.procedureText.trim(), cancellationPolicyText: draft.rules.cancellationPolicyText.trim(), sourceUrls: draft.rules.sources.split('\n').map(item => item.trim()).filter(Boolean) }} /></details>
    <details className="disclosure compact"><summary>Conditions commerciales</summary><p className="policy-copy">{draft.tariff.termsText.trim()}</p></details>
  </div>;
}
