import { SharedTermsEditor } from './shared-terms-editor';
import { useEffect } from 'react';
import { formatCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { readReference, termsListSchema, textProposalsLite, uncategorizedTariffsSchema, type CatalogueReference } from '../formation-api';
import { readSchool } from '../school-api';
import { EmptyState, Notice, StatusBadge, Symbol, formatCivilDate, formatDateTime, formatDuration } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';
import type { FormationView, NavigationQuery } from './route';
import type { SectionKey } from './sections';
import { tariffStatusBadge, tariffTypeLabels } from './formation-model';
import { CompetencyList, ConsoleLink, RulesText, TariffsPanel, useEditorSubmission, useFormationEditors } from './formation-sheet';

/*
 * Anciennes adresses (/offres, /referentiels, /procedures, /prestations, /conditions) : la version exacte désignée est
 * retrouvée. Une version actuelle et sans ambiguïté ouvre sa rubrique ; une ancienne version, un contenu partagé ou un
 * élément non rattaché s'affiche dans l'historique du permis, sans choisir de parcours à la place de la personne.
 */

/** Destination d'une référence : jamais la dernière version à la place de celle demandée. */
export function referenceDestination(reference: CatalogueReference, from: SectionKey): { section: 'formations' | 'prestations' | 'conditions'; query: NavigationQuery } {
  const history = (category: string): { section: 'formations'; query: NavigationQuery } => ({ section: 'formations', query: { category, view: 'historique', selection: reference.id } });
  switch (reference.kind) {
    case 'OFFERING': return reference.current ? { section: 'formations', query: { category: reference.categoryCode, view: 'general', programme: reference.offeringKey } } : history(reference.categoryCode);
    case 'CURRICULUM': case 'PROCEDURE': {
      const view: FormationView = reference.kind === 'CURRICULUM' ? 'competences' : 'deroulement';
      const only = reference.programmes.length === 1 ? reference.programmes[0]! : null;
      return only?.current ? { section: 'formations', query: { category: reference.categoryCode, view, programme: only.offeringKey } } : history(reference.categoryCode);
    }
    case 'TARIFF':
      if (reference.categoryCode === null) return { section: 'prestations', query: { selection: reference.id } };
      return reference.current ? { section: 'formations', query: { category: reference.categoryCode, view: 'tarifs', selection: reference.id } } : history(reference.categoryCode);
    case 'TERMS': return { section: 'conditions', query: { selection: reference.id } };
  }
  void from;
}

/** Résout une ancienne adresse puis remplace l'entrée d'historique par la destination ; en cas d'échec, l'explique. */
export function LegacyReferenceRoute({ section }: { section: SectionKey }) {
  const { schoolId, routeQuery = {}, navigate } = useConsole();
  const selection = routeQuery.selection;
  const loaded = useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection], `${schoolId}/${selection ?? ''}`);
  useEffect(() => {
    if (selection) return;
    // Sans référence : la fiche du permis demandé, ou la liste.
    navigate('formations', routeQuery.category ? { category: routeQuery.category, ...(section === 'prestations' ? { view: 'tarifs' as const } : {}) } : {}, { replace: true });
  }, [selection]);
  useEffect(() => {
    if (!loaded.data) return;
    const target = referenceDestination(loaded.data, section);
    if (target.section === section && target.query.selection === selection) return;
    navigate(target.section, target.query, { replace: true });
  }, [loaded.data]);
  return <div className="section-stack formation-studio">
    <SectionHeading title="Formations et tarifs" symbol="book" />
    {loaded.status === 'error' ? <EmptyState symbol="book" title="Référence introuvable" message={loaded.error ?? 'Cet élément n’existe pas ou n’est pas accessible avec vos accès.'}
      action={<ConsoleLink section="formations" query={{}} className="button secondary">Voir les formations</ConsoleLink>} />
      : <LoadState loaded={loaded} label="Recherche de l’élément demandé…">{() => null}</LoadState>}
  </div>;
}

/** Contenu exact d'une version, avec ses usages réels. */
export function ReferenceContent({ reference }: { reference: CatalogueReference }) {
  const status = <StatusBadge tone="neutral" symbol={reference.current ? 'check' : 'clock'}>{reference.current ? 'Version actuelle' : 'Version précédente'}</StatusBadge>;
  const usage = reference.programmes.length > 0 && <div className="reference-usage"><h3>Utilisé par</h3><ul className="plain-list">{reference.programmes.map(item =>
    <li key={item.offeringKey}>{item.label ?? 'Parcours'} du permis {item.categoryCode} · {item.current ? 'version actuelle' : 'version précédente'} ·{' '}
      <ConsoleLink section="formations" keepForms query={{ category: item.categoryCode, view: 'general', programme: item.offeringKey }}>Ouvrir le parcours</ConsoleLink></li>)}</ul></div>;
  switch (reference.kind) {
    case 'OFFERING': return <article className="reference-content" aria-labelledby="reference-title">
      <div className="settings-section-heading"><h2 id="reference-title" tabIndex={-1} className="section-title">Programme · version {reference.offering.version}</h2>{status}</div>
      <p className="row-meta">Enregistrée le {formatDateTime(reference.offering.createdAt)}{reference.offering.label ? ` · ${reference.offering.label}` : ''}{!reference.offering.enabled ? ' · non proposée' : ''}</p>
      {reference.curriculum ? <><h3>Compétences</h3><CompetencyList items={reference.curriculum.competencies} /></> : <p className="empty-inline">Sans compétences enregistrées.</p>}
      {reference.procedure ? <RulesText procedure={reference.procedure} /> : <p className="empty-inline">Sans règles enregistrées.</p>}
    </article>;
    case 'CURRICULUM': return <article className="reference-content" aria-labelledby="reference-title">
      <div className="settings-section-heading"><h2 id="reference-title" tabIndex={-1} className="section-title">Compétences · révision {reference.curriculum.revision}</h2>{status}</div>
      <p className="row-meta">Enregistrées le {formatDateTime(reference.curriculum.createdAt)}{!reference.curriculum.approved ? ' · jamais appliquées' : ''}</p>
      {reference.programmes.length === 0 && <p className="caption">Élément non rattaché à un parcours.</p>}
      <CompetencyList items={reference.curriculum.competencies} />{usage}
    </article>;
    case 'PROCEDURE': return <article className="reference-content" aria-labelledby="reference-title">
      <div className="settings-section-heading"><h2 id="reference-title" tabIndex={-1} className="section-title">Déroulement et annulation · version {reference.procedure.version}</h2>{status}</div>
      <p className="row-meta">Enregistrés le {formatDateTime(reference.procedure.createdAt)}{!reference.procedure.approved ? ' · jamais appliqués' : ''}</p>
      {reference.programmes.length === 0 && <p className="caption">Élément non rattaché à un parcours.</p>}
      <RulesText procedure={reference.procedure} />{usage}
    </article>;
    case 'TARIFF': {
      const badge = tariffStatusBadge(reference.status, reference.tariff, formatCivilDate);
      return <article className="reference-content" aria-labelledby="reference-title">
        <div className="settings-section-heading"><h2 id="reference-title" tabIndex={-1} className="section-title">{reference.tariff.label} · version {reference.tariff.version}</h2>{status}</div>
        <dl className="settings-values">
          <div><dt>Type</dt><dd>{tariffTypeLabels[reference.tariff.type]}</dd></div>
          <div><dt>Prix</dt><dd>{formatCents(reference.tariff.unitPriceCents)} par {reference.tariff.unitLabel}</dd></div>
          {reference.tariff.durationMinutes && <div><dt>Durée</dt><dd>{formatDuration(reference.tariff.durationMinutes)}</dd></div>}
          <div><dt>Validité</dt><dd>{reference.tariff.validUntil ? `Du ${formatCivilDate(reference.tariff.validFrom)} au ${formatCivilDate(reference.tariff.validUntil)}` : `À partir du ${formatCivilDate(reference.tariff.validFrom)}`}</dd></div>
          <div><dt>Enregistré le</dt><dd>{formatDateTime(reference.tariff.createdAt)}</dd></div>
          {reference.current && badge && <div><dt>État</dt><dd><StatusBadge tone={badge.tone} symbol="dot">{badge.label}</StatusBadge></dd></div>}
        </dl>
        <h3>Conditions commerciales</h3>{reference.terms ? <p className="policy-copy">{reference.terms.termsText}</p> : <p className="caption">Non visibles avec vos accès.</p>}
        <p className="caption">Les réservations faites avec cette version gardent ce prix et ces conditions.</p>
      </article>;
    }
    case 'TERMS': return <article className="reference-content" aria-labelledby="reference-title">
      <div className="settings-section-heading"><h2 id="reference-title" tabIndex={-1} className="section-title">{reference.terms.label} · version {reference.terms.version}</h2>
        {!reference.current && <StatusBadge tone="neutral" symbol="clock">Plus utilisées par un tarif actuel</StatusBadge>}</div>
      <p className="row-meta">Valables {reference.terms.validUntil ? `du ${formatCivilDate(reference.terms.validFrom)} au ${formatCivilDate(reference.terms.validUntil)}` : `à partir du ${formatCivilDate(reference.terms.validFrom)}`}</p>
      <p className="policy-copy">{reference.terms.termsText}</p>
      {reference.current && <SharedTermsEditor key={reference.id} reference={reference} />}
      <div className="reference-usage"><h3>Tarifs concernés</h3>{reference.usedBy.length === 0 ? <p className="caption">Aucun tarif n’utilise ces conditions.</p>
        : <ul className="plain-list">{reference.usedBy.map(item => <li key={item.id}>{item.label} · v{item.version}{item.categoryCode ? ` · permis ${item.categoryCode}` : ' · sans permis'} · {item.current ? 'version actuelle' : 'version précédente'} ·{' '}
          <ConsoleLink section={item.categoryCode ? 'formations' : 'prestations'} query={item.categoryCode ? { category: item.categoryCode, view: item.current ? 'tarifs' : 'historique', selection: item.id } : { selection: item.id }}>Ouvrir</ConsoleLink></li>)}</ul>}</div>
    </article>;
  }
}

/** Ancienne destination « Conditions » : consultation des conditions et de leurs usages ; elles se modifient depuis le tarif. */
export function TermsArchiveSection() {
  const { schoolId, routeQuery = {} } = useConsole();
  const { revision } = useCommandSnapshot();
  const selection = routeQuery.selection;
  const list = useLoad(() => readSchool(schoolId, 'formations/terms', termsListSchema), [schoolId, revision]);
  const detail = useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection, revision], `${schoolId}/${selection ?? ''}`);
  return <div className="section-stack formation-studio settings-studio">
    <div className="formation-back"><ConsoleLink section="formations" query={{}} className="button quiet compact"><Symbol kind="back" bare />Formations et tarifs</ConsoleLink></div>
    <SectionHeading title="Conditions commerciales" symbol="file" />
    {selection && <section className="settings-section"><LoadState loaded={detail} label="Lecture des conditions…">{value => value && (value.kind === 'TERMS'
      ? <ReferenceContent reference={value} /> : <Notice tone="info" title="Cet élément n’est pas une version de conditions"><p>
        <ConsoleLink section="formations" query={{ selection: value.id }}>Ouvrir l’élément</ConsoleLink></p></Notice>)}</LoadState></section>}
    <LoadState loaded={list} label="Lecture des conditions…">{data => data.items.length === 0 ? <EmptyState symbol="file" title="Aucune condition commerciale" />
      : <table className="data-table record-table">
        <caption className="visually-hidden">Conditions commerciales enregistrées{data.truncated ? ' (500 plus récentes)' : ''}</caption>
        <thead><tr><th scope="col">Conditions</th><th scope="col">Validité</th><th scope="col" className="numeric">Tarifs actuels</th></tr></thead>
        <tbody>{data.items.map(item => <tr key={item.id} className={item.id === selection ? 'selected' : undefined}>
          <th scope="row"><ConsoleLink section="conditions" query={{ selection: item.id }} className="row-link">{item.label} · v{item.version}</ConsoleLink></th>
          <td data-label="Validité">{item.validUntil ? `${formatCivilDate(item.validFrom)} – ${formatCivilDate(item.validUntil)}` : `dès le ${formatCivilDate(item.validFrom)}`}</td>
          <td className="numeric" data-label="Tarifs actuels">{item.currentTariffs}</td>
        </tr>)}</tbody>
      </table>}</LoadState>
  </div>;
}

/** Prestations sans permis : mêmes tarifs, même éditeur, sans catégorie. */
export function UncategorizedTariffsSection() {
  const { schoolId, school, routeQuery = {}, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'formations/uncategorized-tariffs', uncategorizedTariffsSchema), [schoolId, revision]);
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  const editors = useFormationEditors();
  const submission = useEditorSubmission(editors, loaded.reload);
  const selection = routeQuery.selection;
  // Une référence d'un tarif rattaché à un permis ouvre la fiche de ce permis.
  useEffect(() => { if (routeQuery.category) navigate('formations', { category: routeQuery.category, view: 'tarifs', ...(selection ? { selection } : {}) }, { replace: true }); }, [routeQuery.category]);
  // Version actuelle : surlignée dans la liste. Ancienne version ou référence absente de la liste : relue telle quelle.
  const owner = selection && loaded.data ? loaded.data.tariffs.find(item => item.history.some(version => version.id === selection)) : undefined;
  const consult = !!selection && !!loaded.data && owner?.head.id !== selection;
  const reference = useLoad(async () => consult ? readReference(schoolId, selection!) : null, [schoolId, selection, consult], `${schoolId}/${selection ?? ''}/${consult}`);
  useEffect(() => {
    const value = reference.data;
    if (value && value.kind === 'TARIFF' && value.categoryCode) navigate('formations', { category: value.categoryCode, view: value.current ? 'tarifs' : 'historique', selection: value.id }, { replace: true });
    else if (value && value.kind !== 'TARIFF') navigate('formations', { selection: value.id }, { replace: true });
  }, [reference.data]);
  return <div className="section-stack formation-studio settings-studio">
    <div className="formation-back"><ConsoleLink section="formations" query={{}} className="button quiet compact"><Symbol kind="back" bare />Formations et tarifs</ConsoleLink></div>
    <SectionHeading title="Prestations sans permis" symbol="receipt" />
    <OutcomeArea submission={submission} reload={loaded.reload} />
    {consult && <section className="settings-section"><LoadState loaded={reference} label="Lecture de la version…">{value => value?.kind === 'TARIFF' && value.categoryCode === null ? <ReferenceContent reference={value} /> : null}</LoadState></section>}
    <LoadState loaded={loaded} label="Lecture des prestations…">{data => <TariffsPanel tariffs={data.tariffs} categoryCode={null} today={data.today} canConfigure={data.canConfigureCatalog}
      editors={editors} submission={submission} proposals={proposals.data} selection={selection} programmeCount={0}
      types={['EXTERNAL_SERVICE', 'EXAM_SUPPORT', ...(school.modules.collectiveCoursesEnabled ? ['COLLECTIVE_COURSE' as const] : [])]} />}</LoadState>
  </div>;
}

function OutcomeArea({ submission, reload }: { submission: ReturnType<typeof useEditorSubmission>; reload: () => void }) {
  const runner = submission.runner;
  return <>
    {runner.outcome && <Notice tone={runner.outcome.tone} title={runner.outcome.title} actions={<>
      {runner.outcome.code === 'TARIFF_CHANGED' && <button type="button" className="button secondary" onClick={() => { runner.clearOutcome(); reload(); }}>Recharger</button>}
      {runner.outcome.tone === 'success' && <button type="button" className="button quiet" onClick={runner.clearOutcome}>Masquer</button>}</>}><p>{runner.outcome.message}</p></Notice>}
    {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
  </>;
}
