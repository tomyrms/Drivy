import { useEffect, useRef, type FormEvent, type ReactNode } from 'react';
import { Plus, ReceiptText } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import type { Tariff, TariffType, TextProposalsLite } from '../../formation-api';
import { BackButton, ChangeList, CommandFeedback, ReviewDialog, useFocusOnMount } from '../formations/catalogue-ui';
import type { CatalogueCommand } from '../formations/catalogue-command';
import { civilDate } from '../formations/formation-format';
import { TariffForm } from './tariff-form';
import { effectiveFrom, tariffDifferences, tariffSummary } from './tariff-diff';
import { tariffGroups } from './tariff-groups';
import { TariffDetail, TariffList } from './tariff-views';
import { useTariffEditor, type TariffEditor } from './pricing-controllers';

export interface TariffsPanelProps {
  tariffs: readonly Tariff[]; categoryCode: string | null; today: string; canConfigure: boolean; types: readonly TariffType[];
  proposals: TextProposalsLite | undefined; command: CatalogueCommand; reload: () => void; programmeCount: number;
  /** Identifiant de version ouvert (adresse), `null` pour revenir à la liste. */
  selection: string | undefined; onSelect: (versionId: string | null) => void; onConsultVersion: (versionId: string) => void;
  onOpenTerms: (termsId: string) => void;
  /** Libellé du retour depuis la fiche d'un tarif : le nom de la liste. */
  listLabel: string;
  /** Une édition de tarif occupe toute la page : la fiche masque son en-tête et ses onglets. */
  onEditing?: (editing: boolean) => void;
  /** Actions complémentaires de la page, avant l'action d'ajout. */
  actions?: ReactNode;
}

/** Tarifs d'un permis ou prestations sans permis : liste, fiche, création et révision avec la même composition. */
export function TariffsPanel(props: TariffsPanelProps) {
  const { tariffs, categoryCode, today, canConfigure, command } = props;
  const editor = useTariffEditor({ tariffs, categoryCode, today, types: props.types, proposals: props.proposals, command, reload: props.reload, onSaved: id => { if (id) props.onSelect(id); } });
  const opened = props.selection ? tariffs.find(item => item.head.id === props.selection || item.history.some(version => version.id === props.selection)) : undefined;
  const groups = tariffGroups(tariffs);
  const heading = useRef<HTMLHeadingElement>(null);
  const was = useRef(false);
  useEffect(() => { if (was.current && !editor.editing) heading.current?.focus(); was.current = editor.editing && !editor.quick; }, [editor.editing, editor.quick]);
  const fullPage = editor.editing && !editor.quick;
  useEffect(() => { props.onEditing?.(fullPage); return () => props.onEditing?.(false); }, [fullPage]);
  const blocked = command.busy;
  const review = <TariffReviewDialog editor={editor} command={command} today={today} />;
  if (editor.editing && !editor.quick && editor.draft) {
    const create = editor.mode === 'CREATE';
    const submit = (event: FormEvent) => { event.preventDefault(); if (!editor.review()) window.requestAnimationFrame(() => document.querySelector<HTMLElement>('.cat-editor [aria-invalid="true"]')?.focus()); };
    return <>
      <form className="cat-editor" noValidate onSubmit={submit} aria-labelledby="cat-tariff-editor-title">
        <header className="cat-editor-head">
          <TariffEditorTitle>{create ? (categoryCode ? `Nouveau tarif · permis ${categoryCode}` : 'Nouvelle prestation') : `Modifier ${editor.current?.head.label ?? 'le tarif'}`}</TariffEditorTitle>
          {props.programmeCount > 1 && <p className="cat-muted">Commun aux {props.programmeCount} parcours du permis {categoryCode}.</p>}
        </header>
        {!editor.reviewing && <CommandFeedback runner={command.runner} />}
        <TariffForm editor={editor} types={props.types} sharedWith={editor.current?.termsSharedWith ?? 0} current={editor.current} today={today} disabled={blocked} />
        <footer className="cat-editor-bar">
          <Button type="button" variant="ghost" disabled={blocked} onClick={editor.cancel}>Annuler</Button>
          <Button type="submit" disabled={blocked || (!create && !editor.changed)}>Relire les changements</Button>
        </footer>
      </form>
      {review}
    </>;
  }
  if (opened) return <>
    <BackButton onClick={() => props.onSelect(null)}>{props.listLabel}</BackButton>
    <CommandFeedback runner={command.runner} onDismiss={command.runner.clearOutcome} />
    <TariffDetail tariff={opened} today={today} canConfigure={canConfigure} busy={blocked} onEdit={() => editor.openEdit(opened)} onToggle={enabled => editor.openToggle(opened, enabled)}
      onConsultVersion={props.onConsultVersion} onOpenTerms={props.onOpenTerms} />
    {review}
  </>;
  return <section className="cat-section" aria-labelledby="cat-tariffs-title">
    <div className="cat-section-head"><h2 id="cat-tariffs-title" className="visually-hidden" ref={heading} tabIndex={-1}>{categoryCode ? 'Tarifs' : 'Prestations'}</h2>
      <div className="cat-section-actions">{props.actions}{canConfigure && <Button disabled={blocked} onClick={editor.openCreate}><Plus data-icon="inline-start" />{categoryCode ? 'Ajouter un tarif' : 'Ajouter une prestation'}</Button>}</div></div>
    <CommandFeedback runner={command.runner} onDismiss={command.runner.clearOutcome} />
    {!canConfigure && <p className="cat-hint">L’autorisation de configurer les tarifs est nécessaire pour les modifier ; certains tarifs non proposés peuvent ne pas être visibles.</p>}
    {categoryCode && props.programmeCount > 1 && <p className="cat-muted">Ces tarifs sont communs aux {props.programmeCount} parcours du permis {categoryCode}.</p>}
    {tariffs.length === 0
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><ReceiptText /></EmptyMedia><EmptyTitle>{categoryCode ? 'Aucun tarif pour ce permis' : 'Aucune prestation sans permis'}</EmptyTitle></EmptyHeader>
        {canConfigure && <EmptyContent><Button onClick={editor.openCreate}>{categoryCode ? 'Ajouter un tarif' : 'Ajouter une prestation'}</Button></EmptyContent>}</Empty>
      : <TariffList current={groups.current} archived={groups.archived} onOpen={tariff => props.onSelect(tariff.head.id)} />}
    {review}
  </section>;
}

function TariffEditorTitle({ children }: { children: string }) {
  const ref = useFocusOnMount<HTMLHeadingElement>();
  return <h2 id="cat-tariff-editor-title" tabIndex={-1} ref={ref}>{children}</h2>;
}

function TariffReviewDialog({ editor, command, today }: { editor: TariffEditor; command: CatalogueCommand; today: string }) {
  const draft = editor.draft, current = editor.current;
  if (!draft) return null;
  const create = editor.mode === 'CREATE';
  const label = create ? 'Ajouter le tarif' : editor.quick ? (draft.enabled ? 'Proposer à nouveau' : 'Ne plus proposer') : 'Enregistrer le tarif';
  const rows = create || !current ? tariffSummary(draft) : tariffDifferences(draft, current, today);
  return <ReviewDialog open={editor.reviewing} title={create ? 'Ajouter ce tarif ?' : editor.quick ? `${draft.enabled ? 'Proposer à nouveau' : 'Ne plus proposer'} ce tarif ?` : 'Enregistrer ces changements ?'}
    description={draft.label.trim() || current?.head.label} runner={command.runner} busy={command.busy} confirmLabel={label} onClose={editor.closeReview} onConfirm={() => void editor.confirm()}>
    {rows.length === 0 ? <p>Aucun changement de prix, de durée ni de dates.</p> : <ChangeList rows={rows} />}
    <p className="cat-muted">{create ? `Applicable dès le ${civilDate(draft.validFrom)}.`
      : `Applicable dès le ${civilDate(current ? effectiveFrom(current, today) : today)}, sans effet rétroactif. Les réservations déjà confirmées gardent leur prix et leurs conditions.`}</p>
    {!create && current && current.termsSharedWith > 0 && rows.some(row => row.label === 'Conditions') && <p className="cat-muted">Les {current.termsSharedWith} autres tarifs gardent les conditions communes.</p>}
  </ReviewDialog>;
}
