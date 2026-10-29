import { useEffect, useRef, type FormEvent } from 'react';
import { ChevronRight, FileText, Search } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import type { CatalogueReference } from '../../formation-api';
import { useConsole } from '../../console/context';
import { PortalSelect } from '../components/portal-select';
import { BackButton, CommandFeedback, ReadFeedback, ReviewDialog } from '../formations/catalogue-ui';
import { useCatalogueCommand, type CatalogueCommand } from '../formations/catalogue-command';
import { plural, shortDate, validity } from '../formations/formation-format';
import { useReference, useSharedTermsRevision, useTermsList } from './pricing-controllers';
import '../formations/formations.css';
import './pricing.css';

/**
 * Conditions commerciales versionnées. Elles se lisent par portée : à quels tarifs elles s'appliquent, depuis quand.
 * Une révision crée une nouvelle version pour les tarifs concernés ; les engagements déjà pris gardent leurs conditions.
 */
export function TermsPage() {
  const { routeQuery = {}, navigate, setRouteQuery } = useConsole();
  const selection = routeQuery.selection;
  const command = useCatalogueCommand();
  const select = (id: string | null) => setRouteQuery?.(id ? { selection: id } : {}, false, true);
  return <section className="cat-page">
    <BackButton onClick={() => selection ? select(null) : navigate('prestations', {})}>{selection ? 'Conditions commerciales' : 'Prestations'}</BackButton>
    {selection ? <TermsDetail selection={selection} command={command} onSelect={id => setRouteQuery?.({ selection: id }, true, true)} /> : <TermsList onOpen={select} />}
  </section>;
}

function TermsList({ onOpen }: { onOpen: (id: string) => void }) {
  const state = useTermsList();
  const data = state.list.data;
  return <>
    <header className="cat-heading"><h1 tabIndex={-1}>Conditions commerciales</h1></header>
    <ReadFeedback loaded={state.list} label="Lecture des conditions" />
    {data && (data.items.length === 0
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><FileText /></EmptyMedia><EmptyTitle>Aucune condition commerciale</EmptyTitle></EmptyHeader></Empty>
      : <>
        <div className="cat-toolbar">
          <Field className="cat-search"><FieldLabel className="sr-only" htmlFor="terms-search">Rechercher des conditions</FieldLabel><Search aria-hidden="true" />
            <Input id="terms-search" type="search" placeholder="Rechercher des conditions" value={state.search} onChange={event => state.setSearch(event.target.value)} /></Field>
          <PortalSelect id="terms-usage" label="Utilisation" value={state.usage} onValueChange={value => { if (value === 'all' || value === 'used' || value === 'unused') state.setUsage(value); }}
            options={[{ value: 'all', label: 'Toutes les versions' }, { value: 'used', label: 'Utilisées' }, { value: 'unused', label: 'Sans tarif actuel' }]} />
        </div>
        {data.truncated && <p className="cat-hint">Les 500 versions les plus récentes sont chargées.</p>}
        {state.items.length === 0
          ? <Empty className="cat-empty"><EmptyHeader><EmptyTitle>Aucune condition trouvée</EmptyTitle></EmptyHeader><EmptyContent><Button variant="outline" onClick={() => { state.setSearch(''); state.setUsage('all'); }}>Réinitialiser les filtres</Button></EmptyContent></Empty>
          : <ul className="cat-list" aria-label="Versions des conditions">{state.items.map(item => <li key={item.id}>
            <button type="button" className="cat-row cat-terms-row" onClick={() => onOpen(item.id)} aria-label={`Ouvrir ${item.label}, version ${item.version}`}>
              <span className="cat-row-main"><strong>{item.label}</strong><span className="cat-row-meta">Version {item.version} · {validity(item.validFrom, item.validUntil)}</span></span>
              <span className="cat-row-state">{item.currentTariffs === 0 && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Sans tarif actuel</Badge>}</span>
              <span className="cat-row-count">{plural(item.currentTariffs, 'tarif actuel', 'tarifs actuels')}</span>
              <ChevronRight aria-hidden="true" className="cat-chevron" />
            </button></li>)}</ul>}
      </>)}
  </>;
}

function TermsDetail({ selection, command, onSelect }: { selection: string; command: CatalogueCommand; onSelect: (id: string) => void }) {
  const { navigate } = useConsole();
  const detail = useReference(selection);
  const reference = detail.data;
  return <>
    <ReadFeedback loaded={detail} label="Lecture des conditions" />
    {reference && (reference.kind === 'TERMS'
      ? <TermsReader reference={reference} command={command} onRevised={id => { if (id) onSelect(id); }} />
      : <Empty className="cat-empty"><EmptyHeader><EmptyTitle>Cet élément n’est pas une version de conditions</EmptyTitle></EmptyHeader>
        <EmptyContent><Button variant="outline" onClick={() => navigate('formations', { selection: reference.id })}>Ouvrir l’élément</Button></EmptyContent></Empty>)}
  </>;
}

function TermsReader({ reference, command, onRevised }: { reference: Extract<CatalogueReference, { kind: 'TERMS' }>; command: CatalogueCommand; onRevised: (id: string | null) => void }) {
  const { navigate, canConfigureCatalog } = useConsole();
  const revision = useSharedTermsRevision(reference, command, onRevised);
  const title = useRef<HTMLHeadingElement>(null);
  const editorTitle = useRef<HTMLHeadingElement>(null);
  const was = useRef(false);
  useEffect(() => { if (was.current && !revision.editing) title.current?.focus(); if (!was.current && revision.editing) editorTitle.current?.focus(); was.current = revision.editing; }, [revision.editing]);
  const blocked = command.busy;
  const submit = (event: FormEvent) => { event.preventDefault(); revision.review(); };
  if (revision.editing) return <>
    <form className="cat-editor" noValidate onSubmit={submit} aria-labelledby="terms-editor-title">
      <header className="cat-editor-head"><h2 id="terms-editor-title" tabIndex={-1} ref={editorTitle}>Réviser les conditions communes</h2>
        <p className="cat-muted">{reference.terms.label} · version {reference.terms.version}</p></header>
      {!revision.reviewing && <CommandFeedback runner={command.runner} />}
      <FieldGroup>
        <Field data-invalid={revision.attempted && !!revision.problem}>
          <FieldLabel htmlFor="terms-text">Conditions communes</FieldLabel>
          <Textarea id="terms-text" rows={14} maxLength={20_000} value={revision.text} disabled={blocked} aria-invalid={revision.attempted && !!revision.problem} onChange={event => revision.setText(event.target.value)} />
          {revision.attempted && revision.problem && <FieldError>{revision.problem}</FieldError>}
          <FieldDescription>S’applique à {plural(revision.impacted.length, 'tarif')} proposé{revision.impacted.length > 1 ? 's' : ''} aujourd’hui.</FieldDescription>
        </Field>
      </FieldGroup>
      <footer className="cat-editor-bar">
        <Button type="button" variant="ghost" disabled={blocked} onClick={revision.cancel}>Annuler</Button>
        <Button type="submit" disabled={blocked || !revision.changed}>Relire les changements</Button>
      </footer>
    </form>
    <ReviewDialog open={revision.reviewing} title="Adopter ces conditions ?" description={`${reference.terms.label} · version ${reference.terms.version}`} runner={command.runner} busy={blocked}
      confirmLabel="Adopter les nouvelles conditions" disabled={!revision.acknowledged} onClose={revision.closeReview} onConfirm={() => void revision.confirm()}>
      <section className="cat-review"><h3>Texte</h3>
        <div className="cat-diff"><div><span>Avant</span><p>{reference.terms.termsText}</p></div><div><span>Après</span><p>{revision.text.trim()}</p></div></div></section>
      <section className="cat-review"><h3>{plural(revision.impacted.length, 'tarif concerné', 'tarifs concernés')}</h3>
        <ul>{revision.impacted.map(item => <li key={item.id}><strong>{item.label}</strong><span className="cat-muted"> · {item.categoryCode ? `permis ${item.categoryCode}` : 'sans permis'}</span></li>)}</ul></section>
      <p className="cat-muted">Chacun de ces tarifs reçoit une nouvelle version. Les réservations existantes gardent leurs conditions.</p>
      <Field orientation="horizontal" className="cat-ack"><Checkbox id="terms-ack" checked={revision.acknowledged} disabled={blocked} onCheckedChange={value => revision.setAcknowledged(value === true)} />
        <FieldLabel htmlFor="terms-ack">J’ai relu le texte et les tarifs concernés.</FieldLabel></Field>
    </ReviewDialog>
  </>;
  return <article className="cat-section cat-surface" aria-labelledby="terms-title">
    <header className="cat-detail-head">
      <div><h1 id="terms-title" ref={title} tabIndex={-1}>{reference.terms.label}</h1><p className="cat-muted">Version {reference.terms.version} · {validity(reference.terms.validFrom, reference.terms.validUntil)}</p></div>
      {!reference.current && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Plus utilisées par un tarif actuel</Badge>}
    </header>
    <CommandFeedback runner={command.runner} onDismiss={command.runner.clearOutcome} />
    {canConfigureCatalog && revision.canRevise && <div className="cat-detail-actions"><Button variant="outline" disabled={blocked} onClick={revision.open}>Réviser les conditions communes</Button></div>}
    <section className="cat-detail-section"><h2>Texte</h2><p className="cat-reader">{reference.terms.termsText}</p></section>
    <section className="cat-detail-section"><h2>Tarifs concernés</h2>
      {reference.usedBy.length === 0 ? <p className="cat-muted">Aucun tarif n’utilise ces conditions.</p>
        : <ul className="cat-history">{reference.usedBy.map(item => <li key={item.id}>
          <span className="cat-history-main"><strong>{item.label}</strong><span className="cat-muted">v{item.version}</span></span>
          <span className="cat-muted">{item.categoryCode ? `Permis ${item.categoryCode}` : 'Sans permis'} · {item.current ? 'version actuelle' : 'version précédente'} · dès le {shortDate(item.validFrom)}</span>
          <span />
          <Button variant="outline" size="sm" aria-label={`Ouvrir ${item.label}, version ${item.version}`}
            onClick={() => item.categoryCode ? navigate('formations', { category: item.categoryCode, view: item.current ? 'tarifs' : 'historique', selection: item.id }) : navigate('prestations', { selection: item.id })}>Ouvrir</Button>
        </li>)}</ul>}
    </section>
  </article>;
}
