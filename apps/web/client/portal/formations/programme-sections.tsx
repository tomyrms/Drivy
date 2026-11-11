import { useEffect, useRef, type FormEvent, type ReactNode, type RefObject } from 'react';
import { Pencil } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import type { LaneOutcome } from '../../command-lane';
import type { FormationSheet, Programme, TextProposalsLite } from '../../formation-api';
import {
  competenciesChanged, competencyDrafts, competencyPayload, competencyProblems, emptyCompetency, generalChanges, generalDraft, generalProblems,
  minutes, programmeName, rebaseRules, rulesChanged, rulesDraft, rulesPayload, rulesProblems, type CompetencyDraft, type GeneralDraft, type RulesDraft,
} from '../../console/formation-model';
import { ActionSlot, ChangeList, ReviewDialog, StateBadge } from './catalogue-ui';
import { LaneFeedback, RefusalBanner } from './formation-feedback';
import type { ProgrammeRefusal, ProgrammeLane } from './formation-commands';
import { competencyChangeCount, competencyChanges, generalDifferences, rulesChanges, type CompetencyChanges, type TextChange } from './formation-diff';
import { formationMarkLabels, type FormationMark } from './formation-projection';
import { useProgrammeEditor, type ProgrammeEditor } from './formation-controllers';
import { duration, plural } from './formation-format';
import { CompetencyFields, GeneralFields, RulesFields } from './programme-fields';
import { CompetencyList, ProgrammeOverview, RulesReader } from './programme-read';
import { ReferenceUpdate } from './reference-update';
import { editorTitles } from './sheet-routing';

interface SectionProps {
  sheet: FormationSheet; programme: Programme; commands: ProgrammeLane; proposals: TextProposalsLite | undefined;
  onTariffs: () => void; onHistory: () => void;
  /** Une édition ouverte occupe toute la page : la fiche masque son en-tête et ses onglets. */
  onEditing: (editing: boolean) => void;
  /** Emplacement des actions de rubrique, sur la rangée des onglets. */
  actionSlot: HTMLElement | null;
}
const effectText = (programme: Programme) => programme.enrollments.current + programme.enrollments.previous > 0
  ? 'S’applique aux nouvelles inscriptions. Les élèves déjà inscrits gardent leur programme, leurs règles et leurs évaluations, y compris pour leurs prochaines leçons.'
  : 'S’applique aux nouvelles inscriptions.';

/** Rend le focus au titre une fois l'édition fermée, et signale à la fiche qu'une édition occupe la page. */
function useRestoreFocus(editing: boolean, onEditing: (editing: boolean) => void) {
  const heading = useRef<HTMLHeadingElement>(null);
  const was = useRef(false);
  useEffect(() => { if (was.current && !editing) heading.current?.focus(); was.current = editing; }, [editing]);
  useEffect(() => { onEditing(editing); return () => onEditing(false); }, [editing]);
  return heading;
}

/**
 * Édition d'une seule section en page entière : l'élément modifié est seul à l'écran, avec sa portée. Le formulaire n'est jamais
 * verrouillé par un envoi : le magasin conserve la demande, l'éditeur se ferme et la rubrique dit ce qui est en cours.
 */
function EditorFrame({ view, scope, rebased, saved, restored, dirty, reviewing, onCancel, onSubmit, children }: {
  view: keyof typeof editorTitles; scope: string; rebased: boolean; saved: ReactNode; restored: LaneOutcome | null;
  dirty: boolean; reviewing: boolean; onCancel: () => void; onSubmit: () => void; children: ReactNode;
}) {
  const title = useRef<HTMLHeadingElement>(null);
  useEffect(() => { title.current?.focus(); }, []);
  const submit = (event: FormEvent) => { event.preventDefault(); onSubmit(); };
  return <form className="cat-editor" noValidate onSubmit={submit} aria-labelledby="cat-editor-title">
    <header className="cat-editor-head"><h2 id="cat-editor-title" ref={title} tabIndex={-1}>{editorTitles[view]}</h2><p className="cat-muted">{scope}</p></header>
    {rebased && <Alert><AlertTitle>La fiche a changé pendant votre modification</AlertTitle>
      <AlertDescription>La version enregistrée entre-temps est disponible ci-dessous. Votre saisie est conservée : relisez-la avant d’enregistrer.</AlertDescription>
      <Collapsible className="cat-collapsible"><CollapsibleTrigger render={<Button type="button" variant="outline" />}>Voir la version enregistrée</CollapsibleTrigger><CollapsibleContent className="cat-saved">{saved}</CollapsibleContent></Collapsible></Alert>}
    {!reviewing && <LaneFeedback outcome={restored} />}
    {children}
    <footer className="cat-editor-bar">
      <Button type="button" variant="ghost" onClick={onCancel}>Annuler</Button>
      <Button type="submit" disabled={!dirty}>Relire les changements</Button>
    </footer>
  </form>;
}

/** Le titre de la rubrique est déjà celui de l'onglet : il reste pour les lecteurs d'écran, l'écran garde un repère utile et l'action. */
function SectionHead({ title, headingRef, lead, slot, children }: {
  title: string; headingRef: RefObject<HTMLHeadingElement | null>; lead?: ReactNode; slot: HTMLElement | null; children?: ReactNode;
}) {
  return <>
    <h2 id="cat-section-title" className="visually-hidden" ref={headingRef} tabIndex={-1}>{title}</h2>
    {lead ? <p className="cat-section-lead">{lead}</p> : null}
    {children ? <ActionSlot slot={slot}>{children}</ActionSlot> : null}
  </>;
}

/**
 * Ce que la rubrique montre quand l'éditeur est fermé : un refus avec sa saisie à reprendre, puis la marque de la demande en cours.
 * La version publiée reste celle de l'école ; la ligne ne dit que ce qui est en attente.
 */
function SectionState({ mark, refusals, blocked, line, onResume }: {
  mark: FormationMark | null; refusals: readonly ProgrammeRefusal[]; blocked: boolean; line?: string | null; onResume: (refusal: ProgrammeRefusal) => void;
}) {
  return <>
    {refusals.map(refusal => <RefusalBanner key={refusal.intention.operationId} outcome={refusal.outcome} onResume={() => onResume(refusal)} />)}
    {mark && <p className="cat-hint" role="status"><StateBadge badge={{ tone: 'neutral', label: formationMarkLabels[mark] }} />{line ? <span className="cat-muted"> · {line}</span> : null}</p>}
    {blocked && !mark && refusals.length === 0 && <p className="cat-hint">Une demande sur ce parcours attend sa confirmation.</p>}
  </>;
}

function EditButton({ label, disabled, onClick }: { label: string; disabled: boolean; onClick: () => void }) {
  return <Button variant="outline" disabled={disabled} onClick={onClick}><Pencil data-icon="inline-start" />{label}</Button>;
}

function ScopedNotice({ shared }: { shared: boolean }) {
  return shared ? <Alert><AlertDescription>Ce contenu est aussi celui d’un autre parcours ; l’enregistrer ici ne modifie que ce parcours.</AlertDescription></Alert> : null;
}

const generalLine = (draft: GeneralDraft) => [draft.label.trim() || null, minutes(draft.duration) !== null ? duration(minutes(draft.duration)) : null].filter(Boolean).join(' · ');

export function ProgrammeSection({ view, ...props }: SectionProps & { view: 'general' | 'competences' | 'deroulement' }) {
  return view === 'general' ? <GeneralSection {...props} /> : view === 'competences' ? <CompetenciesSection {...props} /> : <RulesSection {...props} />;
}

function GeneralSection({ sheet, programme, commands, onTariffs, onHistory, onEditing, actionSlot }: SectionProps) {
  const multiple = sheet.programmes.length > 1;
  const others = sheet.programmes.filter(item => item !== programme).flatMap(item => item.head.label ? [item.head.label] : []);
  const editor: ProgrammeEditor<GeneralDraft> = useProgrammeEditor<GeneralDraft>({ programme, section: 'general', commands, success: 'Le parcours est enregistré.',
    initial: () => generalDraft(programme), valid: draft => generalProblems(draft, multiple, others).valid,
    changed: draft => Object.keys(generalChanges(draft, programme)).length > 0, body: draft => generalChanges(draft, programme) });
  const heading = useRestoreFocus(editor.editing, onEditing);
  if (editor.editing && editor.draft) {
    const problems = generalProblems(editor.draft, multiple, others);
    return <>
      <EditorFrame view="general" scope={`Permis ${sheet.categoryCode}${multiple ? ` · ${programmeName(programme, sheet.programmes)}` : ''}`} rebased={editor.rebased} dirty={editor.dirty} reviewing={editor.reviewing}
        restored={editor.restored} onCancel={editor.cancel} onSubmit={() => { if (!editor.review()) focusInvalid(); }} saved={<ProgrammeOverview sheet={sheet} programme={programme} onTariffs={onTariffs} onHistory={onHistory} />}>
        <GeneralFields draft={editor.draft} onChange={editor.update} disabled={false} showErrors={editor.attempted} problems={problems} nameRequired={multiple} />
      </EditorFrame>
      <ReviewDialog open={editor.reviewing} title="Enregistrer ces changements ?" description={`Permis ${sheet.categoryCode}`} outcome={editor.restored} busy={false}
        disabled={editor.blocked} confirmLabel="Enregistrer" onClose={editor.closeReview} onConfirm={editor.confirm}>
        <ChangeList rows={generalDifferences(editor.draft, programme)} /><p className="cat-muted">{effectText(programme)}</p>
        {editor.blocked && <p className="cat-muted">Une demande sur ce parcours attend sa confirmation.</p>}
      </ReviewDialog>
    </>;
  }
  const shown = editor.shown;
  return <section className="cat-section cat-surface" aria-labelledby="cat-section-title">
    <SectionHead title="Général" headingRef={heading} slot={actionSlot} lead={multiple ? `Parcours ${programmeName(programme, sheet.programmes)}` : null}>
      {sheet.canConfigureCatalog && <EditButton label="Modifier" disabled={editor.blocked} onClick={editor.open} />}
    </SectionHead>
    <SectionState mark={shown.mark} refusals={editor.refusals} blocked={editor.blocked} line={shown.wanted ? generalLine(shown.wanted.draft) : null} onResume={editor.resume} />
    <ProgrammeOverview sheet={sheet} programme={programme} onTariffs={onTariffs} onHistory={onHistory} />
  </section>;
}

function CompetenciesSection({ sheet, programme, commands, onEditing, actionSlot }: SectionProps) {
  const current = programme.curriculum?.competencies ?? [];
  const editor: ProgrammeEditor<CompetencyDraft[]> = useProgrammeEditor<CompetencyDraft[]>({ programme, section: 'competences', commands,
    success: 'Les compétences sont enregistrées pour les nouvelles inscriptions.',
    initial: () => current.length ? competencyDrafts(current) : [emptyCompetency()], valid: draft => competencyProblems(draft).valid,
    changed: draft => competenciesChanged(draft, current) || !programme.curriculum?.approved, body: draft => ({ competencies: competencyPayload(draft) }) });
  const heading = useRestoreFocus(editor.editing, onEditing);
  if (editor.editing && editor.draft) {
    const changes = competencyChanges(current, editor.draft);
    return <>
      <EditorFrame view="competences" scope={`Permis ${sheet.categoryCode}${sheet.programmes.length > 1 ? ` · ${programmeName(programme, sheet.programmes)}` : ''}`} rebased={editor.rebased} dirty={editor.dirty}
        reviewing={editor.reviewing} restored={editor.restored} onCancel={editor.cancel} onSubmit={() => { if (!editor.review()) focusInvalid(); }} saved={<CompetencyList items={current} />}>
        <ScopedNotice shared={programme.sharedCurriculumWith.length > 0} />
        <CompetencyFields items={editor.draft} onChange={editor.update} disabled={false} showErrors={editor.attempted} />
      </EditorFrame>
      <ReviewDialog open={editor.reviewing} title="Enregistrer les compétences ?" description={`Permis ${sheet.categoryCode} · ${plural(changes.total, 'compétence')} au total`}
        outcome={editor.restored} busy={false} disabled={editor.blocked} confirmLabel="Enregistrer les compétences" onClose={editor.closeReview} onConfirm={editor.confirm}>
        <CompetencyReview changes={changes} /><p className="cat-muted">{effectText(programme)}</p>
        {editor.blocked && <p className="cat-muted">Une demande sur ce parcours attend sa confirmation.</p>}
      </ReviewDialog>
    </>;
  }
  const shown = editor.shown;
  return <section className="cat-section cat-surface" aria-labelledby="cat-section-title">
    <SectionHead title="Compétences" headingRef={heading} slot={actionSlot} lead={current.length ? plural(current.length, 'compétence') : null}>
      {sheet.canConfigureCatalog && <EditButton label={current.length ? 'Modifier les compétences' : 'Ajouter les compétences'} disabled={editor.blocked} onClick={editor.open} />}
    </SectionHead>
    <SectionState mark={shown.mark} refusals={editor.refusals} blocked={editor.blocked}
      line={shown.wanted ? plural(shown.wanted.draft.length, 'compétence') : null} onResume={editor.resume} />
    {current.length ? <>
      {programme.curriculum && !programme.curriculum.approved && <p className="cat-muted">Ces compétences n’ont jamais été appliquées.</p>}
      <CompetencyList items={current} />
    </> : <p className="cat-muted">Aucune compétence enregistrée pour ce parcours.</p>}
    {sheet.canConfigureCatalog && <div className="cat-section-foot"><ReferenceUpdate programme={programme} categoryCode={sheet.categoryCode} canConfigure={sheet.canConfigureCatalog} commands={commands} /></div>}
  </section>;
}

function RulesSection({ sheet, programme, commands, proposals, onEditing, actionSlot }: SectionProps) {
  const current = programme.procedure;
  const editor: ProgrammeEditor<RulesDraft> = useProgrammeEditor<RulesDraft>({ programme, section: 'deroulement', commands,
    success: 'Le déroulement et l’annulation sont enregistrés pour les nouvelles inscriptions.',
    initial: () => rulesDraft(current), valid: draft => rulesProblems(draft).valid, changed: draft => rulesChanged(draft, current) || !current?.approved,
    rebase: (draft, next) => rebaseRules(draft, next.procedure), body: draft => ({ procedure: rulesPayload(draft) }) });
  const heading = useRestoreFocus(editor.editing, onEditing);
  if (editor.editing && editor.draft) {
    const changes = rulesChanges(current, editor.draft);
    return <>
      <EditorFrame view="deroulement" scope={`Permis ${sheet.categoryCode}${sheet.programmes.length > 1 ? ` · ${programmeName(programme, sheet.programmes)}` : ''}`} rebased={editor.rebased} dirty={editor.dirty}
        reviewing={editor.reviewing} restored={editor.restored} onCancel={editor.cancel} onSubmit={() => { if (!editor.review()) focusInvalid(); }}
        saved={current ? <RulesReader procedure={current} /> : <p className="cat-muted">Aucune règle enregistrée.</p>}>
        <ScopedNotice shared={programme.sharedProcedureWith.length > 0} />
        <RulesFields draft={editor.draft} onChange={editor.update} disabled={false} showErrors={editor.attempted} example={proposals?.procedure ?? null} />
      </EditorFrame>
      <ReviewDialog open={editor.reviewing} title="Enregistrer les règles ?" description={`Permis ${sheet.categoryCode}`} outcome={editor.restored} busy={false}
        disabled={editor.blocked} confirmLabel="Enregistrer les règles" onClose={editor.closeReview} onConfirm={editor.confirm}>
        {changes.length === 0 ? <p>Les textes sont identiques à ceux déjà enregistrés ; les règles seront appliquées aux nouvelles inscriptions.</p> : <RulesReview changes={changes} />}
        <p className="cat-muted">{effectText(programme)}</p>
        {editor.blocked && <p className="cat-muted">Une demande sur ce parcours attend sa confirmation.</p>}
      </ReviewDialog>
    </>;
  }
  const shown = editor.shown;
  return <section className="cat-section cat-surface" aria-labelledby="cat-section-title">
    <SectionHead title="Règles" headingRef={heading} slot={actionSlot} lead={null}>
      {sheet.canConfigureCatalog && <EditButton label={current ? 'Modifier les règles' : 'Rédiger les règles'} disabled={editor.blocked} onClick={editor.open} />}
    </SectionHead>
    <SectionState mark={shown.mark} refusals={editor.refusals} blocked={editor.blocked} onResume={editor.resume} />
    {current ? <RulesReader procedure={current} /> : <p className="cat-muted">Aucune règle enregistrée pour ce parcours.</p>}
  </section>;
}

/** Après un envoi refusé par la validation locale, le focus va au premier champ à corriger. */
function focusInvalid() {
  window.requestAnimationFrame(() => document.querySelector<HTMLElement>('.cat-editor [aria-invalid="true"]')?.focus());
}

function CompetencyReview({ changes }: { changes: CompetencyChanges }) {
  if (competencyChangeCount(changes) === 0) return <p>La liste est identique à celle déjà enregistrée ; elle sera appliquée aux nouvelles inscriptions.</p>;
  return <div className="cat-review">
    {changes.added.length > 0 && <section><h3>{plural(changes.added.length, 'compétence ajoutée', 'compétences ajoutées')}</h3><ul>{changes.added.map((row, index) => <li key={index}><strong>{row.item.label}</strong><span className="cat-muted"> · position {row.position}</span></li>)}</ul></section>}
    {changes.removed.length > 0 && <section><h3>{plural(changes.removed.length, 'compétence retirée', 'compétences retirées')}</h3><ul>{changes.removed.map(item => <li key={item.key}>{item.label}</li>)}</ul></section>}
    {changes.edited.length > 0 && <section><h3>{plural(changes.edited.length, 'formulation modifiée', 'formulations modifiées')}</h3><ul>{changes.edited.map(row => <li key={row.before.key}>
      <span className="cat-before">{row.before.label}</span> → <strong>{row.after.label}</strong>{row.before.description !== row.after.description && <span className="cat-muted"> · description modifiée</span>}</li>)}</ul></section>}
    {changes.reordered && <section><h3>Ordre modifié</h3></section>}
  </div>;
}

function RulesReview({ changes }: { changes: TextChange[] }) {
  return <div className="cat-review">{changes.map(row => <section key={row.field}><h3>{row.label}</h3>
    <div className="cat-diff"><div><span>Avant</span><p>{row.before || 'Non rédigé'}</p></div><div><span>Après</span><p>{row.after || 'Retiré'}</p></div></div></section>)}</div>;
}
