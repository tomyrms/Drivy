import { useEffect, useRef, type FormEvent, type ReactNode } from 'react';
import { Plus, ReceiptText } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import type { Tariff, TariffType, TextProposalsLite } from '../../formation-api';
import { ActionSlot, BackButton, ChangeList, ReviewDialog, useFocusOnMount } from '../formations/catalogue-ui';
import type { CatalogueCommand } from '../formations/catalogue-command';
import { civilDate } from '../formations/formation-format';
import { useTariffLane, type TariffRefusal } from './pricing-commands';
import { LaneFeedback, quietRunner, RefusalBanner } from './pricing-feedback';
import { useTariffEditor, type TariffEditor } from './pricing-controllers';
import { TariffForm } from './tariff-form';
import { effectiveFrom, tariffDifferences, tariffSummary } from './tariff-diff';
import { TariffDetail, TariffList } from './tariff-views';

export interface TariffsPanelProps {
  tariffs: readonly Tariff[]; categoryCode: string | null; today: string; canConfigure: boolean; types: readonly TariffType[];
  proposals: TextProposalsLite | undefined;
  /**
   * Coureur unique de la fiche (formations, programme). L'éditeur de tarif ne s'en sert plus : il passe par sa propre voie de
   * commandes (#124), et la prop reste acceptée pour les appelants qui en ont un jusqu'à leur migration.
   */
  command?: CatalogueCommand;
  reload: () => void; programmeCount: number;
  /** Identifiant de version ouvert (adresse), `null` pour revenir à la liste. */
  selection: string | undefined; onSelect: (versionId: string | null) => void; onConsultVersion: (versionId: string) => void;
  onOpenTerms: (termsId: string) => void;
  /** Libellé du retour depuis la fiche d'un tarif : le nom de la liste. */
  listLabel: string;
  /** Une édition de tarif occupe toute la page : la fiche masque son en-tête et ses onglets. */
  onEditing?: (editing: boolean) => void;
  /** Emplacement des actions sur la rangée des onglets de la fiche ; sans emplacement, l'action reste dans la page. */
  actionSlot?: HTMLElement | null;
  /** Actions complémentaires de la page, avant l'action d'ajout. */
  actions?: ReactNode;
}

/**
 * Tarifs d'un permis ou prestations sans permis : liste, fiche, création et révision avec la même composition.
 * Chaque écriture passe par la voie de commandes : une intention par produit, le formulaire se libère dès que le magasin la
 * conserve, la ligne dit ce qui est en cours et un refus rend la saisie.
 */
export function TariffsPanel(props: TariffsPanelProps) {
  const { tariffs, categoryCode, today, canConfigure } = props;
  const lane = useTariffLane(tariffs, id => props.onSelect(id), props.reload);
  const editor = useTariffEditor({ tariffs, categoryCode, today, types: props.types, proposals: props.proposals, commands: lane });
  const opened = props.selection ? tariffs.find(item => item.head.id === props.selection || item.history.some(version => version.id === props.selection)) : undefined;
  const heading = useRef<HTMLHeadingElement>(null);
  const was = useRef(false);
  useEffect(() => { if (was.current && !editor.editing) heading.current?.focus(); was.current = editor.editing && !editor.quick; }, [editor.editing, editor.quick]);
  const fullPage = editor.editing && !editor.quick;
  useEffect(() => { props.onEditing?.(fullPage); return () => props.onEditing?.(false); }, [fullPage]);
  const resume = (refusal: TariffRefusal) => { lane.dismiss(refusal); editor.reopen({ target: refusal.target, draft: refusal.intention.draft, outcome: refusal.outcome }); };
  const refusals = lane.refusals.map(refusal => <RefusalBanner key={refusal.intention.operationId} outcome={refusal.outcome} onResume={() => resume(refusal)} onDismiss={() => lane.dismiss(refusal)} />);
  const review = <TariffReviewDialog editor={editor} today={today} />;
  if (editor.editing && !editor.quick && editor.draft) {
    const create = editor.mode === 'CREATE';
    const submit = (event: FormEvent) => { event.preventDefault(); if (!editor.review()) window.requestAnimationFrame(() => document.querySelector<HTMLElement>('.cat-editor [aria-invalid="true"]')?.focus()); };
    return <>
      <form className="cat-editor" noValidate onSubmit={submit} aria-labelledby="cat-tariff-editor-title">
        <header className="cat-editor-head">
          <TariffEditorTitle>{create ? (categoryCode ? `Nouveau tarif · permis ${categoryCode}` : 'Nouvelle prestation') : `Modifier ${editor.current?.head.label ?? 'le tarif'}`}</TariffEditorTitle>
          {props.programmeCount > 1 && <p className="cat-muted">Commun aux {props.programmeCount} parcours du permis {categoryCode}.</p>}
        </header>
        <LaneFeedback outcome={lane.confirmation} onDismiss={() => lane.clearOutcome()} />
        <TariffForm editor={editor} types={props.types} sharedWith={editor.current?.termsSharedWith ?? 0} current={editor.current} today={today} disabled={false} />
        {editor.blocked && <p className="cat-hint">{editor.blockedReason}</p>}
        <footer className="cat-editor-bar">
          <Button type="button" variant="ghost" onClick={editor.cancel}>Annuler</Button>
          <Button type="submit" disabled={!create && !editor.changed}>Relire les changements</Button>
        </footer>
      </form>
      {review}
    </>;
  }
  if (opened) {
    const openedBlocked = lane.blocked(opened.productKey, opened.termsSharedWith > 0);
    return <>
      <BackButton onClick={() => props.onSelect(null)}>{props.listLabel}</BackButton>
      <LaneFeedback outcome={lane.confirmation} onDismiss={() => lane.clearOutcome()} />
      {refusals}
      <TariffDetail tariff={opened} today={today} canConfigure={canConfigure} busy={openedBlocked}
        blockedReason={openedBlocked ? 'Une demande sur ce tarif attend sa confirmation (voir en haut de la page).' : null}
        pending={lane.pending(opened.productKey)} onEdit={() => editor.openEdit(opened)}
        onToggle={enabled => editor.openToggle(opened, enabled)} onConsultVersion={props.onConsultVersion} onOpenTerms={props.onOpenTerms} />
      {review}
    </>;
  }
  const cannotAdd = lane.blocked(null, false);
  return <section className="cat-section" aria-labelledby="cat-tariffs-title">
    <h2 id="cat-tariffs-title" className="visually-hidden" ref={heading} tabIndex={-1}>{categoryCode ? 'Tarifs' : 'Prestations'}</h2>
    <ActionSlot slot={props.actionSlot}><div className={props.actionSlot ? undefined : 'cat-section-head'}><div className="cat-section-actions">{props.actions}{canConfigure && <Button disabled={cannotAdd} onClick={editor.openCreate}><Plus data-icon="inline-start" />{categoryCode ? 'Ajouter un tarif' : 'Ajouter une prestation'}</Button>}</div></div></ActionSlot>
    <LaneFeedback outcome={lane.confirmation} onDismiss={() => lane.clearOutcome()} />
    {refusals}
    {canConfigure && cannotAdd && <p className="cat-hint">Une demande sur le catalogue attend sa confirmation (voir en haut de la page).</p>}
    {!canConfigure && <p className="cat-hint">L’autorisation de configurer les tarifs est nécessaire pour les modifier ; certains tarifs non proposés peuvent ne pas être visibles.</p>}
    {categoryCode && props.programmeCount > 1 && <p className="cat-muted">Ces tarifs sont communs aux {props.programmeCount} parcours du permis {categoryCode}.</p>}
    {lane.rows.length === 0
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><ReceiptText /></EmptyMedia><EmptyTitle>{categoryCode ? 'Aucun tarif pour ce permis' : 'Aucune prestation sans permis'}</EmptyTitle></EmptyHeader>
        {canConfigure && <EmptyContent><Button onClick={editor.openCreate}>{categoryCode ? 'Ajouter un tarif' : 'Ajouter une prestation'}</Button></EmptyContent>}</Empty>
      : <TariffList rows={lane.rows} onOpen={tariff => props.onSelect(tariff.head.id)} />}
    {review}
  </section>;
}

function TariffEditorTitle({ children }: { children: string }) {
  const ref = useFocusOnMount<HTMLHeadingElement>();
  return <h2 id="cat-tariff-editor-title" tabIndex={-1} ref={ref}>{children}</h2>;
}

function TariffReviewDialog({ editor, today }: { editor: TariffEditor; today: string }) {
  const draft = editor.draft, current = editor.current;
  if (!draft) return null;
  const create = editor.mode === 'CREATE';
  const label = create ? 'Ajouter le tarif' : editor.quick ? (draft.enabled ? 'Proposer à nouveau' : 'Ne plus proposer') : 'Enregistrer le tarif';
  const rows = create || !current ? tariffSummary(draft) : tariffDifferences(draft, current, today);
  /** Refus rendu sur place, ou saisie rendue après un refus : la même raison, dans le dialogue. */
  const notice = editor.restored ?? (editor.outcome?.tone === 'error' ? editor.outcome : null);
  return <ReviewDialog open={editor.reviewing} title={create ? 'Ajouter ce tarif ?' : editor.quick ? `${draft.enabled ? 'Proposer à nouveau' : 'Ne plus proposer'} ce tarif ?` : 'Enregistrer ces changements ?'}
    description={draft.label.trim() || current?.head.label} runner={quietRunner(false)} busy={false} disabled={editor.blocked} confirmLabel={label} onClose={editor.closeReview} onConfirm={editor.confirm}>
    {notice && <Alert variant="destructive"><AlertTitle>{notice.title}</AlertTitle><AlertDescription>{notice.message}</AlertDescription></Alert>}
    {rows.length === 0 ? <p>Aucun changement de prix, de durée ni de dates.</p> : <ChangeList rows={rows} />}
    <p className="cat-muted">{create ? `Applicable dès le ${civilDate(draft.validFrom)}.`
      : `Applicable dès le ${civilDate(current ? effectiveFrom(current, today) : today)}, sans effet rétroactif. Les réservations déjà confirmées gardent leur prix et leurs conditions.`}</p>
    {!create && current && current.termsSharedWith > 0 && rows.some(row => row.label === 'Conditions') && <p className="cat-muted">Les {current.termsSharedWith} autres tarifs gardent les conditions communes.</p>}
    {editor.blocked && <p className="cat-muted">{editor.blockedReason}</p>}
  </ReviewDialog>;
}
