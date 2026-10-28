import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createCommand, formatCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { formationListSchema, proposalsSchema, readFormationSheet, readReference, textProposalsLite, type FormationSheet, type Programme, type Tariff, type TariffType, type TextProposalsLite } from '../formation-api';
import { programmeUpdate } from '../formation-programme-update';
import { readSchool } from '../school-api';
import { ConfirmDialog, EmptyState, Notice, SegmentField, SelectField, StatusBadge, Symbol, formatCivilDate, formatDateTime, formatDuration } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges, type Outcome } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { consolePath, type FormationView, type NavigationQuery } from './route';
import {
  categoryBadge, categoryIssueText, competenciesChanged, competencyDrafts, competencyPayload, competencyProblems, emptyCompetency, generalChanges, generalDraft,
  generalProblems, newTariffDraft, programmeName, rulesChanged, rulesDraft, rulesPayload, rulesProblems, tariffChanged, tariffDraft, tariffProblems,
  tariffStatusBadge, tariffTypeLabels, updateTariffBody, updatedValidFrom, createTariffBody,
  type CompetencyDraft, type GeneralDraft, type RulesDraft, type TariffDraft,
} from './formation-model';
import { CompetenciesEditor, GeneralEditor, RulesEditor, SaveBar, TariffFields } from './formation-editors';
import { ReferenceContent } from './formation-references';

/* ---------------------------------------------------------------- Liens internes */

/** Lien réel (nouvel onglet possible) qui navigue dans la console sans recharger. */
export function ConsoleLink({ section, query, className = 'text-link', children, keepForms = false, current }: {
  section: 'formations' | 'prestations' | 'conditions'; query: NavigationQuery; className?: string; children: ReactNode; keepForms?: boolean; current?: boolean;
}) {
  const { schoolId, navigate, setRouteQuery } = useConsole();
  return <a className={className} href={consolePath(schoolId, section, query)} aria-current={current ? 'page' : undefined} onClick={event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    if (keepForms && section === 'formations' && setRouteQuery) setRouteQuery(query, false, true); else navigate(section, query);
  }}>{children}</a>;
}

/* ---------------------------------------------------------------- Liste des permis */

export function FormationList() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'formations', formationListSchema), [schoolId, revision]);
  return <div className="section-stack formation-studio">
    <SectionHeading title="Formations et tarifs" symbol="book" actions={loaded.data && (loaded.data.canConfigureCatalog
      ? <ConsoleLink section="formations" query={{ view: 'nouvelle' }} className="button primary"><Symbol kind="plus" bare />Ajouter une formation</ConsoleLink>
      : <button type="button" className="button primary" disabled aria-describedby="formation-add-right"><Symbol kind="plus" bare />Ajouter une formation</button>)} />
    <LoadState loaded={loaded} label="Lecture des formations…">{data => <>
      {!data.canConfigureCatalog && <p className="caption with-symbol" id="formation-add-right"><Symbol kind="lock" bare />L’autorisation de configurer les tarifs est nécessaire pour ajouter une formation ou un tarif.</p>}
      {data.categories.length === 0
        ? <EmptyState symbol="book" title="Aucune formation préparée" message="Ajoutez la formation d’un premier permis, avec ses compétences, ses règles et son premier tarif."
          action={data.canConfigureCatalog ? <ConsoleLink section="formations" query={{ view: 'nouvelle' }} className="button secondary">Ajouter une formation</ConsoleLink> : undefined} />
        : <table className="data-table record-table formation-table">
          <caption className="visually-hidden">Permis préparés par l’école</caption>
          <thead><tr><th scope="col">Permis</th><th scope="col">Durée habituelle</th><th scope="col">Prix d’une leçon</th>
            <th scope="col" className="numeric">Compétences</th><th scope="col" className="numeric">Tarifs</th><th scope="col" className="numeric">Élèves en formation</th></tr></thead>
          <tbody>{data.categories.map(item => {
            const badge = categoryBadge(item.state);
            const lessons = item.lessonTariffs.slice(0, 3);
            return <tr key={item.categoryCode}>
              <th scope="row"><div className="formation-row-title">
                <ConsoleLink section="formations" query={{ category: item.categoryCode }} className="row-link">Permis {item.categoryCode}</ConsoleLink>
                {item.programmeCount > 1 && <span className="row-meta">{item.programmeCount} parcours</span>}
                {badge && <StatusBadge tone={badge.tone} symbol={badge.tone === 'warning' ? 'alert' : 'dot'}>{badge.label}</StatusBadge>}
              </div></th>
              <td data-label="Durée habituelle">{item.lessonDurations.length ? item.lessonDurations.map(formatDuration).join(' · ') : <span className="secondary-text">—</span>}</td>
              <td data-label="Prix d’une leçon">{lessons.length ? <ul className="formation-lesson-prices">{lessons.map((lesson, index) => <li key={index}>
                <span className="lesson-price">{formatCents(lesson.unitPriceCents)}</span>
                <span className="row-meta">{lesson.durationMinutes ? formatDuration(lesson.durationMinutes) : lesson.label}{lesson.upcoming ? ' · à venir' : ''}</span>
              </li>)}{item.lessonTariffs.length > lessons.length && <li className="row-meta">+ {item.lessonTariffs.length - lessons.length} autre{item.lessonTariffs.length - lessons.length > 1 ? 's' : ''}</li>}</ul>
                : <span className="secondary-text">Aucun tarif de leçon</span>}</td>
              <td className="numeric" data-label="Compétences">{item.competencyCounts.length ? item.competencyCounts.join(' · ') : '—'}</td>
              <td className="numeric" data-label="Tarifs">{item.tariffCount}</td>
              <td className="numeric" data-label="Élèves en formation">{item.activeTrainings}</td>
            </tr>;
          })}</tbody>
        </table>}
      <section className="formation-other-link" aria-labelledby="other-services-title">
        <h2 id="other-services-title" className="section-title">Prestations sans permis</h2>
        <p className="row-meta">{data.uncategorizedTariffCount === 0 ? 'Aucune prestation' : `${data.uncategorizedTariffCount} prestation${data.uncategorizedTariffCount > 1 ? 's' : ''}`}</p>
        <ConsoleLink section="prestations" query={{}} className="button secondary">Ouvrir les prestations sans permis</ConsoleLink>
      </section>
    </>}</LoadState>
  </div>;
}

/* ---------------------------------------------------------------- Éditions en mémoire */

export type EditorState =
  | { kind: 'general'; programmeKey: string; baseId: string; initial: string; draft: GeneralDraft; rebased?: boolean; rebase?: boolean }
  | { kind: 'competences'; programmeKey: string; baseId: string; initial: string; draft: CompetencyDraft[]; rebased?: boolean; rebase?: boolean }
  | { kind: 'deroulement'; programmeKey: string; baseId: string; initial: string; draft: RulesDraft; rebased?: boolean; rebase?: boolean }
  | { kind: 'tariff'; productKey: string | null; baseId: string | null; initial: string; draft: TariffDraft; rebased?: boolean; rebase?: boolean };
type EditorInput = EditorState extends infer S ? S extends EditorState ? Omit<S, 'initial'> : never : never;
type DraftOf<K extends EditorState['kind']> = Extract<EditorState, { kind: K }>['draft'];
export const editorKey = (state: Pick<EditorState, 'kind'> & { programmeKey?: string; productKey?: string | null }) =>
  state.kind === 'tariff' ? `tariff:${state.productKey ?? 'new'}` : `${state.kind}:${state.programmeKey}`;
const dirty = (state: EditorState) => JSON.stringify(state.draft) !== state.initial;

/**
 * Éditions d'une fiche, gardées en mémoire tant que la fiche est ouverte : changer de rubrique les conserve,
 * quitter la fiche les protège. Rien n'est écrit dans le stockage du navigateur.
 */
export function useFormationEditors() {
  const [editors, setEditors] = useState<Record<string, EditorState>>({});
  const [attempted, setAttempted] = useState<Record<string, boolean>>({});
  useUnsavedChanges(Object.values(editors).some(dirty));
  return {
    editors, attempted: (key: string) => attempted[key] === true,
    open: (state: EditorInput) => {
      const value = { ...state, initial: JSON.stringify(state.draft) } as EditorState;
      setEditors(current => ({ ...current, [editorKey(value)]: value }));
      setAttempted(current => ({ ...current, [editorKey(value)]: false }));
    },
    update: <K extends EditorState['kind']>(key: string, draft: DraftOf<K>) => setEditors(current => current[key] ? { ...current, [key]: { ...current[key]!, draft } as EditorState } : current),
    patch: (key: string, change: Partial<EditorState>) => setEditors(current => current[key] ? { ...current, [key]: { ...current[key]!, ...change } as EditorState } : current),
    close: (key: string) => setEditors(current => { const next = { ...current }; delete next[key]; return next; }),
    attempt: (key: string) => setAttempted(current => ({ ...current, [key]: true })),
    isDirty: (key: string) => !!editors[key] && dirty(editors[key]!),
  };
}
export type FormationEditors = ReturnType<typeof useFormationEditors>;

/** Une commande composée par édition ; le résultat incertain reste suivi par le panneau de vérification de la console. */
export function useEditorSubmission(editors: FormationEditors, reload: () => void) {
  const submitted = useRef<{ key: string; heading: string } | null>(null);
  const [saved, setSaved] = useState<{ key: string; message: string } | null>(null);
  const runner = useCommandRunner(() => {
    const target = submitted.current;
    if (!target) return;
    submitted.current = null;
    editors.close(target.key);
    window.requestAnimationFrame(() => document.getElementById(target.heading)?.focus());
  });
  async function submit(key: string, heading: string, command: Parameters<typeof runner.run>[0], message: string) {
    submitted.current = { key, heading }; setSaved({ key, message });
    const result = await runner.run(command, message);
    if (result.status === 'rejected') submitted.current = null;
    if (result.status === 'rejected' && (result.code === 'FORMATION_CHANGED' || result.code === 'TARIFF_CHANGED')) editors.patch(key, { rebase: true });
    if (result.status === 'rejected' && (result.code === 'FORMATION_UNCHANGED' || result.code === 'TARIFF_UNCHANGED')) reload();
    return result;
  }
  return { runner, submit, saved };
}

/* ---------------------------------------------------------------- Fiche d'un permis */

const rubrics: readonly { view: FormationView; label: string }[] = [
  { view: 'general', label: 'Général' }, { view: 'competences', label: 'Compétences' }, { view: 'deroulement', label: 'Déroulement et annulation' }, { view: 'tarifs', label: 'Tarifs' },
];

export function FormationSheetView({ category }: { category: string }) {
  const { schoolId, school, routeQuery = {}, setRouteQuery, drafts } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readFormationSheet(schoolId, category), [schoolId, category, revision], `${schoolId}/${category}`);
  const [flash, setFlash] = useState<string | null>(() => { const value = drafts?.get('flash/formations'); drafts?.delete('flash/formations'); return typeof value === 'string' ? value : null; });
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  const editors = useFormationEditors();
  const submission = useEditorSubmission(editors, loaded.reload);
  const view: FormationView = routeQuery.view && routeQuery.view !== 'nouvelle' ? routeQuery.view : 'general';
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, [category]);
  // Après un conflit rechargé, l'édition repart de la version actuelle, signalée comme telle.
  useEffect(() => {
    const data = loaded.data;
    if (!data || loaded.status !== 'ready') return;
    for (const [key, state] of Object.entries(editors.editors)) {
      if (!state.rebase) continue;
      const current = state.kind === 'tariff' ? data.tariffs.find(item => item.productKey === state.productKey)?.head.id
        : data.programmes.find(item => item.offeringKey === state.programmeKey)?.head.id;
      if (current && current !== state.baseId) editors.patch(key, { baseId: current, rebase: false, rebased: true });
    }
  }, [loaded.data, loaded.status]);
  const go = (query: NavigationQuery) => setRouteQuery?.({ category, ...query }, false, true);
  return <div className="section-stack formation-studio settings-studio">
    <div className="formation-back"><ConsoleLink section="formations" query={{}} className="button quiet compact"><Symbol kind="back" bare />Formations et tarifs</ConsoleLink></div>
    <LoadState loaded={loaded} label={`Lecture du permis ${category}…`}>{data => {
      const badge = categoryBadge(data.state);
      const selected = data.programmes.find(item => item.offeringKey === routeQuery.programme) ?? data.programmes[0];
      const learners = data.programmes.reduce((sum, item) => sum + item.enrollments.current + item.enrollments.previous, 0);
      const editing = (rubric: FormationView) => Object.values(editors.editors).some(state => dirty(state) && (rubric === 'tarifs' ? state.kind === 'tariff' : state.kind === rubric));
      return <>
        <header className="formation-header">
          <div className="formation-title">
            <h1 ref={heading} tabIndex={-1}><span className="formation-kicker">Permis</span> {data.categoryCode}</h1>
            <p className="row-meta">{[data.programmes.length > 1 ? `${data.programmes.length} parcours` : null, `${data.tariffs.length} tarif${data.tariffs.length > 1 ? 's' : ''}`,
              `${learners} élève${learners > 1 ? 's' : ''} en formation`].filter(Boolean).join(' · ')}</p>
            {badge && <StatusBadge tone={badge.tone} symbol={badge.tone === 'warning' ? 'alert' : 'dot'}>{badge.label}</StatusBadge>}
          </div>
          <div className="section-head-actions">
            <ConsoleLink section="formations" query={{ category, view: 'historique' }} keepForms className={`button ${view === 'historique' ? 'secondary' : 'quiet'}`} current={view === 'historique'}>
              <Symbol kind="clock" bare />Historique</ConsoleLink>
          </div>
        </header>
        <nav className="formation-tabs" aria-label={`Rubriques du permis ${data.categoryCode}`}>
          <ul>{rubrics.map(rubric => <li key={rubric.view}>
            <ConsoleLink section="formations" keepForms current={view === rubric.view}
              query={{ category, view: rubric.view, ...(selected && rubric.view !== 'tarifs' ? { programme: selected.offeringKey } : {}) }}>
              {rubric.label}{editing(rubric.view) && <span className="formation-tab-dot"><Symbol kind="dot" bare /><span className="visually-hidden"> (modification en cours)</span></span>}
            </ConsoleLink></li>)}</ul>
        </nav>
        {data.issues.length > 0 && view !== 'historique' && <Notice tone="warning" title="À compléter" live={false}><ul className="plain-list">{data.issues.map(issue => <li key={issue}>{categoryIssueText(issue)}</li>)}</ul></Notice>}
        {flash && !submission.runner.outcome && <Notice tone="success" title="Confirmé par l’école" actions={<button type="button" className="button quiet" onClick={() => setFlash(null)}>Masquer</button>}><p>{flash}</p></Notice>}
        <OutcomeNotice outcome={submission.runner.outcome} onDismiss={submission.runner.clearOutcome}
          actions={['FORMATION_CHANGED', 'TARIFF_CHANGED'].includes(submission.runner.outcome?.code ?? '')
            ? <button type="button" className="button secondary" onClick={() => { submission.runner.clearOutcome(); loaded.reload(); }}>Recharger la fiche</button> : undefined} />
        {submission.runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{submission.runner.blockedReason}</p>}
        {view === 'historique'
          ? <HistoryView sheet={data} selection={routeQuery.selection} />
          : view === 'tarifs'
            ? <TariffsPanel tariffs={data.tariffs} categoryCode={data.categoryCode} today={data.today} canConfigure={data.canConfigureCatalog} editors={editors} submission={submission}
                proposals={proposals.data} selection={routeQuery.selection} programmeCount={data.programmes.length}
                types={['INDIVIDUAL_LESSON', 'EXAM_SUPPORT', ...(school.modules.collectiveCoursesEnabled ? ['COLLECTIVE_COURSE' as const] : [])]} />
            : !selected
              ? <EmptyState symbol="book" title="Aucun parcours pour ce permis" message="Préparez ses compétences, ses règles et son premier tarif."
                  action={data.canConfigureCatalog ? <ConsoleLink section="formations" query={{ view: 'nouvelle', category: data.categoryCode }} className="button secondary">Préparer ce permis</ConsoleLink> : undefined} />
              : <ProgrammeRubric view={view} sheet={data} programme={selected} editors={editors} submission={submission} proposals={proposals.data}
                  onProgramme={key => go({ view, programme: key })} />}
      </>;
    }}</LoadState>
  </div>;
}

function ProgrammeSwitch({ sheet, programme, onChange }: { sheet: FormationSheet; programme: Programme; onChange: (key: string) => void }) {
  if (sheet.programmes.length < 2) return null;
  const options = sheet.programmes.map(item => ({ value: item.offeringKey, label: programmeName(item, sheet.programmes) }));
  return <div className="programme-switch">
    {options.length <= 4
      ? <SegmentField label="Parcours" value={programme.offeringKey} options={options} onChange={onChange} />
      : <SelectField label="Parcours" value={programme.offeringKey} options={options} onChange={onChange} search />}
    <p className="caption">Chaque parcours a son propre programme ; les tarifs sont communs au permis.</p>
  </div>;
}

function ProgrammeRubric({ view, sheet, programme, editors, submission, proposals, onProgramme }: {
  view: 'general' | 'competences' | 'deroulement'; sheet: FormationSheet; programme: Programme; editors: FormationEditors;
  submission: ReturnType<typeof useEditorSubmission>; proposals: TextProposalsLite | undefined; onProgramme: (key: string) => void;
}) {
  const { schoolId } = useConsole();
  const key = editorKey({ kind: view, programmeKey: programme.offeringKey }), state = editors.editors[key];
  const runner = submission.runner, blocked = !!runner.pending || runner.busy;
  const name = programmeName(programme, sheet.programmes), multiple = sheet.programmes.length > 1;
  const headingId = `rubric-${view}`;
  const focusOnOpen = useRef(false);
  useLayoutEffect(() => {
    if (!focusOnOpen.current || !state) return;
    focusOnOpen.current = false;
    document.querySelector<HTMLElement>(`#${headingId}-form input, #${headingId}-form textarea`)?.focus();
  }, [state, headingId]);
  const title = { general: 'Général', competences: 'Compétences', deroulement: 'Déroulement et annulation' }[view];
  const others = sheet.programmes.filter(item => item !== programme);
  const effect = programme.enrollments.current + programme.enrollments.previous > 0
    ? 'S’applique aux nouvelles inscriptions. Les élèves déjà inscrits gardent leur programme et leurs règles, y compris pour leurs prochaines leçons.'
    : 'S’applique aux nouvelles inscriptions.';
  const save = (body: Record<string, unknown>, message: string) => {
    if (!state) return;
    void submission.submit(key, headingId, createCommand({ schoolId, kind: 'saveFormationProgramme', path: 'formations/programmes', resourceVersion: 0,
      body: { offeringKey: programme.offeringKey, expectedOfferingVersionId: state.baseId, ...body } }), message);
  };
  const rebasedNotice = state?.rebased && <Notice tone="warning" title="La fiche a changé pendant votre modification" live={false}>
    <p>La version enregistrée entre-temps est affichée ci-dessous. Relisez votre saisie avant d’enregistrer.</p></Notice>;
  const openButton = (label: string, open: () => void) => !state && <button type="button" className="button secondary" disabled={blocked} onClick={() => {
    focusOnOpen.current = true; open();
  }}><Symbol kind="edit" bare />{label}</button>;
  const scope = multiple ? <p className="formation-scope">Vous modifiez le parcours <strong>{name}</strong>.</p> : null;
  let body: ReactNode, action: ReactNode;
  if (view === 'general') {
    const draft = state?.kind === 'general' ? state.draft : null;
    const problems = draft ? generalProblems(draft, multiple, others.flatMap(item => item.head.label ? [item.head.label] : [])) : null;
    const changes = draft ? generalChanges(draft, programme) : {};
    action = openButton('Modifier', () => editors.open({ kind: 'general', programmeKey: programme.offeringKey, baseId: programme.head.id, draft: generalDraft(programme) }));
    body = draft && problems ? <form id={`${headingId}-form`} className="settings-editor formation-editor" noValidate onSubmit={event => {
      event.preventDefault(); editors.attempt(key);
      if (!problems.valid) { window.requestAnimationFrame(() => document.querySelector<HTMLElement>(`#${headingId}-form [aria-invalid="true"]`)?.focus()); return; }
      save(changes, 'Le parcours est enregistré.');
    }}>
      {scope}{rebasedNotice}
      <GeneralEditor draft={draft} onChange={value => editors.update<'general'>(key, value)} disabled={blocked} showErrors={editors.attempted(key)} problems={problems} nameRequired={multiple} />
      <SaveBar busy={runner.busy} dirty={Object.keys(changes).length > 0} disabled={blocked} saveLabel="Enregistrer" effect={effect} onCancel={() => editors.close(key)} />
    </form> : <dl className="settings-values">
      {(multiple || programme.head.label) && <div><dt>Parcours</dt><dd>{name}</dd></div>}
      <div><dt>Nouvelles inscriptions</dt><dd>{programme.head.enabled ? 'Proposée' : <StatusBadge tone="neutral" symbol="dot">Non proposée</StatusBadge>}</dd></div>
      <div><dt>Durée habituelle d’une leçon</dt><dd>{programme.head.defaultDurationMinutes ? formatDuration(programme.head.defaultDurationMinutes) : <span className="secondary-text">Non renseignée</span>}</dd></div>
      <div><dt>Élèves en formation</dt><dd>{programme.enrollments.current + programme.enrollments.previous === 0 ? 'Aucun'
        : [programme.enrollments.current ? `${programme.enrollments.current} sur la version actuelle` : null,
          programme.enrollments.previous ? `${programme.enrollments.previous} sur une version précédente` : null].filter(Boolean).join(' · ')}</dd></div>
      <div><dt>Dernière modification</dt><dd>{formatDateTime(programme.head.createdAt)}</dd></div>
    </dl>;
  } else if (view === 'competences') {
    const draft = state?.kind === 'competences' ? state.draft : null;
    const current = programme.curriculum?.competencies ?? [];
    action = openButton(current.length ? 'Modifier les compétences' : 'Ajouter les compétences', () => editors.open({ kind: 'competences', programmeKey: programme.offeringKey, baseId: programme.head.id,
      draft: current.length ? competencyDrafts(current) : [emptyCompetency()] }));
    body = draft ? <form id={`${headingId}-form`} className="settings-editor formation-editor wide" noValidate onSubmit={event => {
      event.preventDefault(); editors.attempt(key);
      if (!competencyProblems(draft).valid) { window.requestAnimationFrame(() => document.querySelector<HTMLElement>(`#${headingId}-form [aria-invalid="true"]`)?.focus()); return; }
      save({ competencies: competencyPayload(draft) }, 'Les compétences sont enregistrées pour les nouvelles inscriptions.');
    }}>
      {scope}{rebasedNotice}
      {programme.sharedCurriculumWith.length > 0 && <p className="caption">Cette liste est aussi celle d’un autre parcours ; l’enregistrer ici ne modifie que ce parcours.</p>}
      {state?.rebased && <details className="disclosure compact"><summary>Version enregistrée</summary><CompetencyList items={current} /></details>}
      <CompetenciesEditor items={draft} onChange={value => editors.update<'competences'>(key, value)} disabled={blocked} showErrors={editors.attempted(key)} />
      <SaveBar busy={runner.busy} dirty={competenciesChanged(draft, current) || !programme.curriculum?.approved} disabled={blocked} saveLabel="Enregistrer les compétences" effect={effect} onCancel={() => editors.close(key)} />
    </form> : current.length
      ? <>{programme.curriculum && !programme.curriculum.approved && <StatusBadge tone="warning" symbol="edit">Jamais appliquées</StatusBadge>}<CompetencyList items={current} /></>
      : <p className="empty-inline">Aucune compétence enregistrée pour ce parcours.</p>;
  } else {
    const draft = state?.kind === 'deroulement' ? state.draft : null;
    const current = programme.procedure;
    action = openButton(current ? 'Modifier les règles' : 'Rédiger les règles', () => editors.open({ kind: 'deroulement', programmeKey: programme.offeringKey, baseId: programme.head.id, draft: rulesDraft(current) }));
    body = draft ? <form id={`${headingId}-form`} className="settings-editor formation-editor wide" noValidate onSubmit={event => {
      event.preventDefault(); editors.attempt(key);
      if (!rulesProblems(draft).valid) { window.requestAnimationFrame(() => document.querySelector<HTMLElement>(`#${headingId}-form [aria-invalid="true"]`)?.focus()); return; }
      save({ procedure: rulesPayload(draft) }, 'Le déroulement et l’annulation sont enregistrés pour les nouvelles inscriptions.');
    }}>
      {scope}{rebasedNotice}
      {programme.sharedProcedureWith.length > 0 && <p className="caption">Ces règles sont aussi celles d’un autre parcours ; les enregistrer ici ne modifie que ce parcours.</p>}
      {state?.rebased && current && <details className="disclosure compact"><summary>Version enregistrée</summary><RulesText procedure={current} /></details>}
      <RulesEditor draft={draft} onChange={value => editors.update<'deroulement'>(key, value)} disabled={blocked} showErrors={editors.attempted(key)} example={proposals?.procedure ?? null} />
      <SaveBar busy={runner.busy} dirty={rulesChanged(draft, current) || !current?.approved} disabled={blocked} saveLabel="Enregistrer les règles" effect={effect} onCancel={() => editors.close(key)} />
    </form> : current ? <RulesText procedure={current} /> : <p className="empty-inline">Aucune règle enregistrée pour ce parcours.</p>;
  }
  return <>
    <ProgrammeSwitch sheet={sheet} programme={programme} onChange={onProgramme} />
    <section className="settings-section" aria-labelledby={headingId}>
      <div className="settings-section-heading"><h2 id={headingId} tabIndex={-1} className="section-title">{title}</h2>{action}</div>
      <div className="settings-section-body">{body}</div>
      {view === 'competences' && !state && <ProgrammeReference key={programme.offeringKey} programme={programme} categoryCode={sheet.categoryCode} canConfigure={sheet.canConfigureCatalog} submission={submission} />}
    </section>
  </>;
}

/** Mise à jour proposée à la demande : le serveur relit la version et limite l'écriture aux ajouts du référentiel. */
function ProgrammeReference({programme,categoryCode,canConfigure,submission}:{programme:Programme;categoryCode:string;canConfigure:boolean;submission:ReturnType<typeof useEditorSubmission>}) {
  const {schoolId}=useConsole();
  const [open,setOpen]=useState(false);
  const [review,setReview]=useState<(ReturnType<typeof programmeUpdate>&{baseId:string})|null>(null);
  const loaded=useLoad(async()=>open?readSchool(schoolId,'setup-draft/templates',proposalsSchema):null,[schoolId,open]);
  const template=loaded.data?.formations.find(item=>item.categoryCode===categoryCode);
  const diff=template?programmeUpdate(programme.curriculum?.competencies??[],template):null;
  const runner=submission.runner;
  return <details className="disclosure" open={open} onToggle={event=>setOpen(event.currentTarget.open)}>
    <summary>Référence et mise à jour du programme</summary>
    {open && <LoadState loaded={loaded} label="Lecture du programme de référence…">{data=>data && (template&&diff?<>
      <p className="row-meta">Programme actuel : révision {programme.curriculum?.revision??'—'} · Proposition Drivy : {template.version}</p>
      {template.qualification==='NOT_QUALIFIED'&&<StatusBadge tone="warning" symbol="alert">Couverture réglementaire à qualifier</StatusBadge>}
      <p>{template.coverageNote}</p>
      {template.change&&<p>{{EDITORIAL:'Correction rédactionnelle',PEDAGOGICAL:'Amélioration pédagogique',REGULATORY:'Évolution réglementaire'}[template.change.kind]}{template.change.effectiveFrom?` · dès le ${formatCivilDate(template.change.effectiveFrom)}`:''} : {template.change.summary}</p>}
      <p>{diff.additions.length?`${diff.additions.length} compétence${diff.additions.length>1?'s':''} à ajouter.`:'Aucune compétence à ajouter.'} {diff.differences.length>0?`${diff.differences.length} formulation${diff.differences.length>1?'s':''} différente${diff.differences.length>1?'s':''} conservée${diff.differences.length>1?'s':''}.`:''}</p>
      {diff.additions.length>0&&<CompetencyList items={diff.additions}/>}
      {diff.differences.length>0&&<details className="disclosure compact"><summary>Comparer les formulations</summary><ul className="plain-list">{diff.differences.map(({previous,proposed})=><li key={previous.key}>
        <p><strong>École : {previous.label}</strong> · {previous.description}</p><p>Référence : {proposed.label} · {proposed.description}</p>
      </li>)}</ul></details>}
      {diff.collisions.length>0&&<Notice tone="warning" title="Correspondance à vérifier" live={false}><p>Une compétence proposée porte déjà le nom d’une compétence de l’école avec une autre référence. Les ajouts restent suspendus pour éviter un doublon.</p></Notice>}
      <details className="disclosure compact"><summary>Sources et portée</summary><p>Sources consultées le {template.verifiedOn?formatCivilDate(template.verifiedOn):'jour non renseigné'}. Ces compétences sont une proposition pédagogique, sans certification officielle.</p>
        <p>{template.change?.application}</p><ul className="plain-list">{template.sourceUrls?.map(url=><li key={url}><a className="text-link" href={url} target="_blank" rel="noreferrer noopener">{url.includes('criteres-devaluation')?'Critères d’examen':'Conditions d’accès'} · {new URL(url).hostname}</a></li>)}</ul>
      </details>
      {canConfigure&&diff.canApply&&<button type="button" className="button secondary" disabled={runner.busy||!!runner.pending} onClick={()=>{runner.clearOutcome();setReview({...diff,baseId:programme.head.id});}}>Ajouter les compétences proposées</button>}
      <ConfirmDialog open={!!review} busy={runner.busy} title="Ajouter ces compétences ?" confirmLabel="Ajouter aux nouvelles inscriptions" onCancel={()=>setReview(null)} onConfirm={()=>{
        if(!review||!canConfigure||runner.pending||runner.busy)return;
        void submission.submit(`reference:${programme.offeringKey}`,'rubric-competences',createCommand({schoolId,kind:'saveFormationProgramme',path:'formations/programmes',resourceVersion:0,
          body:{offeringKey:programme.offeringKey,expectedOfferingVersionId:review.baseId,competencies:review.competencies,source:review.source}}),'Le programme est mis à jour pour les nouvelles inscriptions.').then(()=>setReview(null));
      }}><p>{review?.additions.map(item=>item.label).join(' · ')}</p><p>Les formulations et compléments de l’école sont conservés. Les élèves déjà inscrits, leurs leçons et leurs évaluations gardent leur programme actuel.</p></ConfirmDialog>
    </>:<p>Aucun programme de référence n’est disponible pour ce permis.</p>)}</LoadState>}
  </details>;
}

export function CompetencyList({ items }: { items: readonly { id?: string; key: string; label: string; description: string }[] }) {
  return <ol className="competency-read">{items.map((item, index) => <li key={item.id ?? `${item.key}-${index}`}><p className="row-title">{item.label}</p><p className="row-meta">{item.description}</p></li>)}</ol>;
}
export function RulesText({ procedure }: { procedure: { procedureText: string; cancellationPolicyText: string; sourceUrls: readonly string[] } }) {
  return <div className="rules-read">
    <section><h3>Déroulement d’une leçon</h3><p className="policy-copy">{procedure.procedureText}</p></section>
    <section><h3>Conditions d’annulation</h3><p className="policy-copy">{procedure.cancellationPolicyText}</p></section>
    {procedure.sourceUrls.length > 0 && <details className="disclosure compact"><summary>Sources ({procedure.sourceUrls.length})</summary>
      <ul className="plain-list">{procedure.sourceUrls.map(url => <li key={url}><a className="text-link" href={url} target="_blank" rel="noreferrer noopener">{url}</a></li>)}</ul></details>}
  </div>;
}

/* ---------------------------------------------------------------- Tarifs (fiche et prestations sans permis) */

export function TariffsPanel({ tariffs, categoryCode, today, canConfigure, editors, submission, proposals, selection, programmeCount, types }: {
  tariffs: readonly Tariff[]; categoryCode: string | null; today: string; canConfigure: boolean; editors: FormationEditors; submission: ReturnType<typeof useEditorSubmission>;
  proposals: TextProposalsLite | undefined; selection?: string | undefined; programmeCount: number; types: readonly TariffType[];
}) {
  const { schoolId } = useConsole();
  const runner = submission.runner, blocked = !!runner.pending || runner.busy;
  const openKey = Object.keys(editors.editors).find(key => key.startsWith('tariff:'));
  const state = openKey ? editors.editors[openKey] : undefined;
  const editingTariff = state?.kind === 'tariff' ? tariffs.find(item => item.productKey === state.productKey) : undefined;
  const focusOnOpen = useRef(false);
  useLayoutEffect(() => {
    if (!focusOnOpen.current || state?.kind !== 'tariff') return;
    focusOnOpen.current = false;
    document.querySelector<HTMLElement>('#tariff-editor input')?.focus();
  }, [state]);
  const selected = useRef<HTMLLIElement>(null);
  useEffect(() => { if (selection) selected.current?.scrollIntoView({ block: 'center' }); }, [selection]);
  const lockedBy = state && editors.isDirty(openKey!) ? 'Terminez la modification en cours avant d’en ouvrir une autre.' : null;
  const open = (tariff: Tariff | null) => {
    focusOnOpen.current = true;
    if (openKey) editors.close(openKey);
    editors.open(tariff ? { kind: 'tariff', productKey: tariff.productKey, baseId: tariff.head.id, draft: tariffDraft(tariff) }
      : { kind: 'tariff', productKey: null, baseId: null, draft: newTariffDraft(types[0]!, today, tariffs.find(item => item.terms)?.terms?.termsText ?? proposals?.commercialTerms.termsText ?? '') });
  };
  const headingId = 'rubric-tarifs';
  let editor: ReactNode = null;
  if (state?.kind === 'tariff' && openKey) {
    const mode = state.productKey ? 'UPDATE' as const : 'CREATE' as const;
    const start = editingTariff ? updatedValidFrom(editingTariff, today) : state.draft.validFrom;
    const problems = tariffProblems(state.draft, mode, today, start);
    const changed = mode === 'CREATE' ? editors.isDirty(openKey) || state.draft.label !== '' : !!editingTariff && tariffChanged(state.draft, editingTariff, today);
    editor = <form id="tariff-editor" className="settings-editor formation-editor tariff-form" noValidate aria-labelledby="tariff-editor-title" onSubmit={event => {
      event.preventDefault(); editors.attempt(openKey);
      if (!problems.valid) { window.requestAnimationFrame(() => document.querySelector<HTMLElement>('#tariff-editor [aria-invalid="true"]')?.focus()); return; }
      const body = mode === 'CREATE' ? createTariffBody(state.draft, categoryCode) : { ...updateTariffBody(state.draft, editingTariff!, today), expectedProductVersionId: state.baseId! };
      void submission.submit(openKey, headingId, createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0, body }),
        mode === 'CREATE' ? 'Le tarif est ajouté.' : 'Le tarif est enregistré. Les réservations existantes gardent leur prix et leurs conditions.');
    }}>
      <h3 id="tariff-editor-title" className="editor-title">{mode === 'CREATE' ? (categoryCode ? `Nouveau tarif · permis ${categoryCode}` : 'Nouvelle prestation sans permis') : `Modifier « ${editingTariff?.head.label ?? ''} »`}</h3>
      {state.rebased && <Notice tone="warning" title="Ce tarif a changé pendant votre modification" live={false}><p>La version enregistrée entre-temps est affichée dans la liste. Relisez votre saisie avant d’enregistrer.</p></Notice>}
      <TariffFields draft={state.draft} onChange={value => editors.update<'tariff'>(openKey, value)} disabled={blocked} showErrors={editors.attempted(openKey)} mode={mode}
        today={today} types={types} start={start} {...(editingTariff ? { sharedTerms: editingTariff.termsSharedWith } : {})} />
      <SaveBar busy={runner.busy} dirty={changed} disabled={blocked} saveLabel={mode === 'CREATE' ? 'Ajouter le tarif' : 'Enregistrer le tarif'} onCancel={() => editors.close(openKey)}
        effect={mode === 'UPDATE' ? 'Les réservations déjà confirmées gardent leur prix et leurs conditions.' : undefined} />
    </form>;
  }
  return <section className="settings-section" aria-labelledby={headingId}>
    <div className="settings-section-heading"><h2 id={headingId} tabIndex={-1} className="section-title">{categoryCode ? 'Tarifs' : 'Prestations'}</h2>
      {canConfigure && <button type="button" className="button secondary" disabled={blocked || !!lockedBy} title={lockedBy ?? undefined} onClick={() => open(null)}>
        <Symbol kind="plus" bare />{categoryCode ? 'Ajouter un tarif' : 'Ajouter une prestation'}</button>}
    </div>
    <div className="settings-section-body">
      {!canConfigure && <p className="caption with-symbol"><Symbol kind="lock" bare />L’autorisation de configurer les tarifs est nécessaire pour les modifier ; certains tarifs non proposés peuvent ne pas être visibles.</p>}
      {programmeCount > 1 && <p className="caption">Ces tarifs sont communs aux {programmeCount} parcours du permis {categoryCode}.</p>}
      {editor}
      {tariffs.length === 0 ? <p className="empty-inline">{categoryCode ? 'Aucun tarif pour ce permis.' : 'Aucune prestation sans permis.'}</p>
        : <ul className="tariff-list">{tariffs.map(tariff => {
          const badge = tariffStatusBadge(tariff.status, tariff.head, formatCivilDate);
          const isSelected = selection !== undefined && tariff.history.some(item => item.id === selection);
          return <li key={tariff.productKey} ref={isSelected ? selected : undefined} className={isSelected ? 'selected' : undefined} aria-current={isSelected ? 'true' : undefined}>
            <div className="tariff-main">
              <div className="row-text">
                <p className="row-title">{tariff.head.label}</p>
                <p className="row-meta">{[tariffTypeLabels[tariff.head.type], tariff.head.durationMinutes ? formatDuration(tariff.head.durationMinutes) : null].filter(Boolean).join(' · ')}</p>
                {badge && <StatusBadge tone={badge.tone} symbol={badge.tone === 'warning' ? 'alert' : 'dot'}>{badge.label}</StatusBadge>}
              </div>
              <p className="price">{formatCents(tariff.head.unitPriceCents)}<span className="row-meta block">par {tariff.head.unitLabel}</span></p>
              {canConfigure && <button type="button" className="button quiet compact" disabled={blocked || (!!lockedBy && openKey !== `tariff:${tariff.productKey}`)}
                aria-label={`Modifier ${tariff.head.label}`} onClick={() => open(tariff)}><Symbol kind="edit" bare />Modifier</button>}
            </div>
            <details className="disclosure compact tariff-terms"><summary>Conditions commerciales{tariff.termsSharedWith > 0 ? ` · partagées avec ${tariff.termsSharedWith} autre${tariff.termsSharedWith > 1 ? 's' : ''} tarif${tariff.termsSharedWith > 1 ? 's' : ''}` : ''}</summary>
              {tariff.terms ? <p className="policy-copy">{tariff.terms.termsText}</p> : <p className="caption">Ces conditions ne sont pas visibles avec vos accès.</p>}
            </details>
          </li>;
        })}</ul>}
    </div>
  </section>;
}

/* ---------------------------------------------------------------- Historique */

function HistoryView({ sheet, selection }: { sheet: FormationSheet; selection?: string | undefined }) {
  const { schoolId } = useConsole();
  const reference = useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection], `${schoolId}/${selection ?? ''}`);
  const consult = (id: string, label = 'Consulter') => <ConsoleLink section="formations" keepForms query={{ category: sheet.categoryCode, view: 'historique', selection: id }} className="text-link">{label}</ConsoleLink>;
  const headingId = 'rubric-historique';
  const tariffRows = useMemo(() => sheet.tariffs.flatMap(tariff => tariff.history.map(version => ({ tariff, version }))), [sheet]);
  return <>
    {selection && <section className="settings-section history-selected" aria-label="Version consultée">
      <LoadState loaded={reference} label="Lecture de la version…">{value => value && <ReferenceContent reference={value} />}</LoadState>
    </section>}
    <section className="settings-section" aria-labelledby={headingId}>
      <div className="settings-section-heading"><h2 id={headingId} tabIndex={-1} className="section-title">Historique</h2></div>
      <div className="settings-section-body">
        <p className="caption">Chaque enregistrement crée une version. Les élèves, leçons et bilans gardent la version qu’ils utilisent.</p>
        {sheet.programmes.map(programme => <div key={programme.offeringKey} className="history-block">
          <h3>{sheet.programmes.length > 1 ? programmeName(programme, sheet.programmes) : 'Programme'}</h3>
          <table className="data-table record-table history-table">
            <caption className="visually-hidden">Versions du programme {programmeName(programme, sheet.programmes)}</caption>
            <thead><tr><th scope="col">Version</th><th scope="col">Enregistrée le</th><th scope="col">Inscriptions</th><th scope="col"><span className="visually-hidden">Consulter</span></th></tr></thead>
            <tbody>{programme.history.map((item, index) => <tr key={item.id} className={item.id === selection ? 'selected' : undefined}>
              <th scope="row">Version {item.version}{index === 0 ? ' · actuelle' : ''}{!item.enabled ? ' · non proposée' : ''}</th>
              <td data-label="Enregistrée le">{formatDateTime(item.createdAt)}</td>
              <td data-label="Inscriptions">{item.trainings ? `${item.trainings} élève${item.trainings > 1 ? 's' : ''}` : '—'}</td>
              <td>{consult(item.id)}</td>
            </tr>)}</tbody>
          </table>
          {programme.historyTruncated && <p className="caption">Seules les 100 dernières versions sont listées.</p>}
        </div>)}
        {tariffRows.length > 0 && <div className="history-block"><h3>Tarifs</h3>
          <table className="data-table record-table history-table">
            <caption className="visually-hidden">Versions des tarifs du permis {sheet.categoryCode}</caption>
            <thead><tr><th scope="col">Tarif</th><th scope="col">Prix</th><th scope="col">Valable</th><th scope="col">Enregistré le</th><th scope="col"><span className="visually-hidden">Consulter</span></th></tr></thead>
            <tbody>{tariffRows.map(({ tariff, version }) => <tr key={version.id} className={version.id === selection ? 'selected' : undefined}>
              <th scope="row">{version.label} · v{version.version}{version.id === tariff.head.id ? ' · actuelle' : ''}{!version.enabled ? ' · non proposée' : ''}</th>
              <td data-label="Prix" className="numeric">{formatCents(version.unitPriceCents)}</td>
              <td data-label="Valable">{version.validUntil ? `${formatCivilDate(version.validFrom)} – ${formatCivilDate(version.validUntil)}` : `dès le ${formatCivilDate(version.validFrom)}`}</td>
              <td data-label="Enregistré le">{formatDateTime(version.createdAt)}</td>
              <td>{consult(version.id)}</td>
            </tr>)}</tbody>
          </table></div>}
        {(sheet.unattached.curricula.length > 0 || sheet.unattached.procedures.length > 0) && <div className="history-block"><h3>Éléments non rattachés</h3>
          <p className="caption">Préparés sans être utilisés par un parcours ; ils restent consultables.</p>
          <ul className="plain-list">
            {sheet.unattached.curricula.map(item => <li key={item.id}>Compétences, révision {item.number} · {formatDateTime(item.createdAt)} · {consult(item.id)}</li>)}
            {sheet.unattached.procedures.map(item => <li key={item.id}>Règles, version {item.number} · {formatDateTime(item.createdAt)} · {consult(item.id)}</li>)}
          </ul></div>}
      </div>
    </section>
  </>;
}

export type { Outcome };
