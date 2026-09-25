import { useMemo, useState } from 'react';
import { centsToInput, createCommand, filled, formatCents, isCivilDate, parseCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { productSchema, productTypes, readAll, termsSchema, type CommercialTerms, type ServiceProduct } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatCivilDate, formatDateTime, formatDuration } from '../ui';
import { useCommandRunner, useConsole, useLoad } from './context';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';
import { approvalBadge } from './catalog';

type ProductType = typeof productTypes[number];
const typeLabels: Record<ProductType, string> = {
  INDIVIDUAL_LESSON: 'Leçon individuelle', COLLECTIVE_COURSE: 'Cours collectif', EXAM_SUPPORT: 'Accompagnement à l’examen', EXTERNAL_SERVICE: 'Prestation externe',
};
const today = () => new Date().toLocaleDateString('sv-SE');
const period = (from: string, until: string | null) => until ? `${formatCivilDate(from)} → ${formatCivilDate(until)}` : `Dès le ${formatCivilDate(from)}`;
function periodProblem(from: string, until: string): string | null {
  if (!isCivilDate(from)) return 'Choisissez la date de début.';
  if (until && !isCivilDate(until)) return 'Date de fin invalide.';
  if (until && until < from) return 'La fin de validité précède le début.';
  return null;
}

/** Commercial writes need the CONFIGURE_CATALOG grant; shown here, enforced by the API. */
function GrantNotice() {
  return <Notice tone="info" title="Consultation seule" live={false}>
    <p>Créer des prestations ou des conditions commerciales demande l’autorisation « Configurer les prestations et tarifs ». Un membre de l’administration peut l’ajouter dans Équipe et accès.</p>
  </Notice>;
}

/* ---------------------------------------------------------------- Conditions commerciales */

type TermsDraft = { label: string; termsText: string; validFrom: string; validUntil: string; approved: boolean; approvalReason: string; basedOn: CommercialTerms | null };

export function TermsSection() {
  const { schoolId, school, canConfigureCatalog } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setDraft(null); setSelected(null); });
  const loaded = useLoad(() => readAll(schoolId, 'commercial-terms', termsSchema), [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<TermsDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const items = useMemo(() => [...(loaded.data?.items ?? [])].sort((a, b) => b.version - a.version), [loaded.data]);
  const current = items.find(item => item.id === selected) ?? null;
  const canWrite = canConfigureCatalog && !runner.pending && !runner.busy;
  const update = (change: Partial<TermsDraft>) => setDraft(value => value ? { ...value, ...change } : value);
  const problems = draft ? (() => {
    const result = {
      label: filled(draft.label, 200) ? null : 'Indiquez un libellé (200 caractères au plus).',
      text: filled(draft.termsText, 20_000) ? null : 'Rédigez les conditions (20 000 caractères au plus).',
      period: periodProblem(draft.validFrom, draft.validUntil),
      reason: filled(draft.approvalReason, 1000) ? null : 'Motif requis.',
    };
    return { ...result, valid: Object.values(result).every(value => value === null) };
  })() : null;
  function edit(from: CommercialTerms | null, approve = false) {
    runner.clearOutcome(); setShowErrors(false);
    setDraft({ label: from?.label ?? '', termsText: from?.termsText ?? '', validFrom: from?.validFrom ?? today(), validUntil: from?.validUntil ?? '',
      approved: approve, approvalReason: '', basedOn: from });
  }
  async function confirm() {
    if (!draft || !problems?.valid) return;
    const command = createCommand({ schoolId, kind: 'createCommercialTerms', path: 'commercial-terms', resourceVersion: 0, body: {
      label: draft.label.trim(), termsText: draft.termsText.trim(), validFrom: draft.validFrom, validUntil: draft.validUntil || null,
      approved: draft.approved, approvalReason: draft.approvalReason.trim() } });
    const result = await runner.run(command, draft.approved ? 'Les conditions commerciales approuvées sont créées.' : 'Le brouillon de conditions commerciales est enregistré.');
    setReviewing(false);
    if (result.status === 'confirmed') { setDraft(null); setSelected(null); }
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Catalogue" title="Conditions commerciales" description="Textes contractuels auxquels se rattachent les prestations. Chaque modification crée une nouvelle version ; l’approbation est explicite."
        actions={canConfigureCatalog ? <button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { setSelected(null); edit(null); }}><Symbol kind="plus" bare />Nouvelles conditions</button> : undefined} />
      {!canConfigureCatalog && <GrantNotice />}
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des conditions commerciales…">{() => <SplitView
        list={items.length === 0 ? <EmptyState symbol="receipt" title="Aucune condition commerciale" message="Rédigez et approuvez des conditions avant d’activer une prestation." />
          : <table className="data-table">
            <caption className="visually-hidden">Conditions commerciales</caption>
            <thead><tr><th scope="col">Libellé</th><th scope="col" className="numeric">Version</th><th scope="col">Validité</th><th scope="col">Statut</th></tr></thead>
            <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>{item.label}</RowButton></th>
              <td className="numeric">{item.version}</td><td>{period(item.validFrom, item.validUntil)}</td><td>{approvalBadge(item.approved, true)}</td>
            </tr>)}</tbody>
          </table>}
        detail={draft && problems ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title={draft.basedOn ? `Nouvelle version · ${draft.basedOn.label}` : 'Nouvelles conditions commerciales'}
            meta={draft.basedOn ? `À partir de la version ${draft.basedOn.version}, qui reste inchangée.` : undefined}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (problems.valid) { setAcknowledged(false); setReviewing(true); } }}>Relire avant d’enregistrer</button>
              <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <TextField label="Libellé" value={draft.label} maxLength={200} disabled={!canWrite} onChange={label => update({ label })} error={showErrors ? problems.label : null} />
              <TextArea label="Texte des conditions" rows={10} maxLength={20_000} value={draft.termsText} disabled={!canWrite} onChange={termsText => update({ termsText })} error={showErrors ? problems.text : null} />
              <div className="form-row">
                <TextField label="Valables dès le" type="date" value={draft.validFrom} disabled={!canWrite} onChange={validFrom => update({ validFrom })} error={showErrors ? problems.period : null} />
                <TextField label="Jusqu’au" type="date" required={false} value={draft.validUntil} disabled={!canWrite} onChange={validUntil => update({ validUntil })} hint="Sans date, les conditions restent valables." />
              </div>
              <fieldset className="fieldset">
                <legend>Validation</legend>
                <CheckField label="Approuver ces conditions" checked={draft.approved} onChange={approved => update({ approved })} disabled={!canWrite}
                  description="Seules des conditions approuvées permettent d’activer une prestation. Une version existante n’est jamais réécrite." />
                <TextArea label="Motif de cette version" rows={2} maxLength={1000} value={draft.approvalReason} disabled={!canWrite}
                  onChange={approvalReason => update({ approvalReason })} error={showErrors ? problems.reason : null} />
              </fieldset>
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={current.label} meta={`Version ${current.version} · ${period(current.validFrom, current.validUntil)}`} badge={approvalBadge(current.approved, true)}
            actions={canConfigureCatalog ? <>
              {!current.approved && <button type="button" className="button primary" disabled={!canWrite} onClick={() => edit(current, true)}>Approuver…</button>}
              <button type="button" className={current.approved ? 'button primary' : 'button secondary'} disabled={!canWrite} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle version</button>
            </> : undefined}>
            {current.approvedAt && <p className="caption">Approuvées le {formatDateTime(current.approvedAt, school.timeZone)}{current.approvalReason ? ` · ${current.approvalReason}` : ''}</p>}
            <p className="policy-copy">{current.termsText}</p>
          </DetailPanel>
          : <Placeholder>Choisissez des conditions pour les relire.</Placeholder>} />}
      </LoadState>
      {draft && problems && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title={draft.approved ? 'Approuver ces conditions' : 'Enregistrer ce brouillon'} confirmLabel={draft.approved ? 'Créer les conditions approuvées' : 'Enregistrer le brouillon'}
        acknowledgement={draft.approved ? 'J’ai relu ce texte et je confirme son approbation.' : 'Je confirme l’enregistrement de ce brouillon.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
        <p className="dialog-lead">{draft.label.trim()}</p>
        <p className="policy-copy review-copy">{draft.termsText.trim()}</p>
        <Facts items={[['Validité', period(draft.validFrom, draft.validUntil || null)], ['Motif', draft.approvalReason.trim()]]} />
      </ConfirmDialog>}
    </div>
  );
}

/* ---------------------------------------------------------------- Prestations et tarifs */

type ProductDraft = {
  productKey: string; label: string; type: ProductType; categoryCode: string; duration: string; unitLabel: string; price: string;
  validFrom: string; validUntil: string; termsVersionId: string; enabled: boolean; basedOn: ServiceProduct | null;
};

export function ProductsSection() {
  const { schoolId, canConfigureCatalog, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setDraft(null); setSelected(null); });
  const loaded = useLoad(async () => {
    const [products, terms] = await Promise.all([readAll(schoolId, 'service-products', productSchema), readAll(schoolId, 'commercial-terms', termsSchema)]);
    return { products: products.items, terms: terms.items };
  }, [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<ProductDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const data = loaded.data;
  const rows = useMemo(() => [...(data?.products ?? [])].sort((a, b) => a.label.localeCompare(b.label, 'fr') || b.version - a.version), [data]);
  const current = rows.find(item => item.id === selected) ?? null;
  const terms = (id: string) => data?.terms.find(item => item.id === id);
  const canWrite = canConfigureCatalog && !runner.pending && !runner.busy;
  const update = (change: Partial<ProductDraft>) => setDraft(value => value ? { ...value, ...change } : value);
  const problems = draft ? (() => {
    const lesson = draft.type === 'INDIVIDUAL_LESSON';
    const duration = Number(draft.duration);
    const result = {
      key: filled(draft.productKey, 100) ? null : 'Indiquez une référence (100 caractères au plus).',
      label: filled(draft.label, 200) ? null : 'Indiquez un libellé (200 caractères au plus).',
      category: draft.categoryCode.trim() ? (filled(draft.categoryCode, 30) ? null : '30 caractères au plus.') : lesson ? 'Une leçon individuelle exige une catégorie.' : null,
      duration: draft.duration.trim() ? (/^\d{1,4}$/.test(draft.duration) && duration >= 1 && duration <= 1440 ? null : 'Durée en minutes, de 1 à 1 440.') : lesson ? 'Une leçon individuelle exige une durée.' : null,
      unit: filled(draft.unitLabel, 100) ? null : 'Indiquez l’unité facturée, par exemple « leçon ».',
      price: parseCents(draft.price) === null ? 'Indiquez un prix valide en CHF.' : null,
      period: periodProblem(draft.validFrom, draft.validUntil),
      terms: data?.terms.some(item => item.id === draft.termsVersionId) ? null : 'Choisissez des conditions commerciales.',
      enabled: draft.enabled && terms(draft.termsVersionId)?.approved !== true ? 'Une prestation activée exige des conditions commerciales approuvées.' : null,
    };
    return { ...result, valid: Object.values(result).every(value => value === null) };
  })() : null;
  function edit(from: ServiceProduct | null) {
    runner.clearOutcome(); setShowErrors(false);
    setDraft({ productKey: from?.productKey ?? '', label: from?.label ?? '', type: from?.type ?? 'INDIVIDUAL_LESSON', categoryCode: from?.categoryCode ?? '',
      duration: from?.durationMinutes ? String(from.durationMinutes) : '', unitLabel: from?.unitLabel ?? 'leçon', price: from ? centsToInput(from.unitPriceCents) : '',
      validFrom: from?.validFrom ?? today(), validUntil: from?.validUntil ?? '', termsVersionId: from?.termsVersionId ?? '', enabled: false, basedOn: from });
  }
  async function confirm() {
    if (!draft || !problems?.valid) return;
    const command = createCommand({ schoolId, kind: 'createServiceProduct', path: 'service-products', resourceVersion: 0, body: {
      productKey: draft.productKey.trim(), label: draft.label.trim(), type: draft.type, categoryCode: draft.categoryCode.trim() || null, siteId: null,
      durationMinutes: draft.duration.trim() ? Number(draft.duration) : null, unitLabel: draft.unitLabel.trim(), unitPriceCents: parseCents(draft.price)!,
      validFrom: draft.validFrom, validUntil: draft.validUntil || null, termsVersionId: draft.termsVersionId, enabled: draft.enabled } });
    const result = await runner.run(command, draft.enabled ? 'La prestation est créée et activée.' : 'La prestation est créée, désactivée.');
    setReviewing(false);
    if (result.status === 'confirmed') { setDraft(null); setSelected(null); }
  }
  const state = (item: ServiceProduct) => item.enabled ? <StatusBadge tone="success" symbol="check">Active</StatusBadge> : <StatusBadge tone="neutral" symbol="dot">Désactivée</StatusBadge>;

  return (
    <div className="section-stack">
      <SectionHeading context="Catalogue" title="Prestations et tarifs" description="Ce que l’école facture, à quel prix et sous quelles conditions. Chaque modification crée une nouvelle version."
        actions={canConfigureCatalog ? <button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { setSelected(null); edit(null); }}><Symbol kind="plus" bare />Nouvelle prestation</button> : undefined} />
      {!canConfigureCatalog && <GrantNotice />}
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des prestations…">{value => <SplitView
        list={rows.length === 0 ? <EmptyState symbol="tag" title="Aucune prestation" message={value.terms.some(item => item.approved)
            ? 'Créez une prestation et rattachez-la aux conditions commerciales approuvées.' : 'Commencez par approuver des conditions commerciales.'}
            action={value.terms.some(item => item.approved) ? undefined : <button type="button" className="button secondary" onClick={() => navigate('conditions')}>Ouvrir les conditions commerciales</button>} />
          : <table className="data-table">
            <caption className="visually-hidden">Prestations et tarifs</caption>
            <thead><tr><th scope="col">Prestation</th><th scope="col">Type</th><th scope="col" className="numeric">Prix</th><th scope="col">Validité</th><th scope="col">État</th></tr></thead>
            <tbody>{rows.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>{item.label}</RowButton>
                <span className="caption"> · v{item.version}</span></th>
              <td>{typeLabels[item.type]}</td><td className="numeric">{formatCents(item.unitPriceCents)} / {item.unitLabel}</td>
              <td>{period(item.validFrom, item.validUntil)}</td><td>{state(item)}</td>
            </tr>)}</tbody>
          </table>}
        detail={draft && problems ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title={draft.basedOn ? `Nouvelle version · ${draft.basedOn.label}` : 'Nouvelle prestation'}
            meta={draft.basedOn ? `À partir de la version ${draft.basedOn.version}, qui reste inchangée.` : undefined}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (problems.valid) { setAcknowledged(false); setReviewing(true); } }}>Relire avant d’enregistrer</button>
              <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <div className="form-row">
                <TextField label="Référence" value={draft.productKey} maxLength={100} disabled={!canWrite || !!draft.basedOn} placeholder="Par exemple lecon-b-45"
                  onChange={productKey => update({ productKey })} error={showErrors ? problems.key : null} hint={draft.basedOn ? 'Une nouvelle version garde sa référence.' : undefined} />
                <SelectField label="Type" value={draft.type} disabled={!canWrite} options={productTypes.map(type => ({ value: type, label: typeLabels[type] }))} onChange={type => update({ type })} />
              </div>
              <TextField label="Libellé" value={draft.label} maxLength={200} disabled={!canWrite} onChange={label => update({ label })} error={showErrors ? problems.label : null} />
              <div className="form-row">
                <TextField label="Catégorie" required={draft.type === 'INDIVIDUAL_LESSON' ? undefined : false} value={draft.categoryCode} maxLength={30} disabled={!canWrite} placeholder="Par exemple B"
                  onChange={categoryCode => update({ categoryCode })} error={showErrors ? problems.category : null} />
                <TextField label="Durée (minutes)" required={draft.type === 'INDIVIDUAL_LESSON' ? undefined : false} value={draft.duration} inputMode="numeric" disabled={!canWrite}
                  onChange={duration => update({ duration })} error={showErrors ? problems.duration : null} />
              </div>
              <div className="form-row">
                <TextField label="Prix unitaire (CHF)" value={draft.price} inputMode="decimal" disabled={!canWrite} onChange={price => update({ price })} error={showErrors ? problems.price : null} />
                <TextField label="Unité facturée" value={draft.unitLabel} maxLength={100} disabled={!canWrite} onChange={unitLabel => update({ unitLabel })} error={showErrors ? problems.unit : null} />
              </div>
              <div className="form-row">
                <TextField label="Valable dès le" type="date" value={draft.validFrom} disabled={!canWrite} onChange={validFrom => update({ validFrom })} error={showErrors ? problems.period : null} />
                <TextField label="Jusqu’au" type="date" required={false} value={draft.validUntil} disabled={!canWrite} onChange={validUntil => update({ validUntil })} />
              </div>
              <SelectField label="Conditions commerciales" value={draft.termsVersionId} placeholder="Choisir des conditions" disabled={!canWrite}
                options={[...value.terms].sort((a, b) => b.version - a.version).map(item => ({ value: item.id, label: `${item.label} · v${item.version} · ${item.approved ? 'approuvées' : 'brouillon'}` }))}
                onChange={termsVersionId => update({ termsVersionId })} error={showErrors ? problems.terms : null} />
              <CheckField label="Activer cette prestation" checked={draft.enabled} onChange={enabled => update({ enabled })} disabled={!canWrite}
                description="Une prestation active peut être proposée. Elle exige des conditions commerciales approuvées ; ce choix ne les approuve pas." />
              {problems.enabled && <p className="field-error"><Symbol kind="alert" bare />{problems.enabled}</p>}
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={current.label} meta={`${typeLabels[current.type]} · version ${current.version}`} badge={state(current)}
            actions={canConfigureCatalog ? <button type="button" className="button primary" disabled={!canWrite} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle version</button> : undefined}>
            <Facts items={[
              ['Référence', <code key="key">{current.productKey}</code>],
              ['Prix unitaire', `${formatCents(current.unitPriceCents)} / ${current.unitLabel}`],
              ['Catégorie', current.categoryCode ?? 'Non renseignée'],
              ['Durée', formatDuration(current.durationMinutes)],
              ['Validité', period(current.validFrom, current.validUntil)],
              ['Conditions', terms(current.termsVersionId) ? <>{terms(current.termsVersionId)!.label} · v{terms(current.termsVersionId)!.version} {approvalBadge(terms(current.termsVersionId)!.approved, true)}</> : 'Non disponibles'],
            ]} />
          </DetailPanel>
          : <Placeholder>Choisissez une prestation pour la consulter.</Placeholder>} />}
      </LoadState>
      {draft && problems && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title="Relire la prestation" confirmLabel={draft.enabled ? 'Créer et activer la prestation' : 'Créer la prestation désactivée'}
        acknowledgement={draft.enabled ? 'J’ai relu le prix et les conditions, et je confirme l’activation.' : 'Je confirme la création de cette version désactivée.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
        <p className="dialog-lead">{draft.label.trim()}</p>
        <Facts items={[
          ['Type', typeLabels[draft.type]],
          ['Prix unitaire', parseCents(draft.price) !== null ? `${formatCents(parseCents(draft.price)!)} / ${draft.unitLabel.trim()}` : '—'],
          ['Catégorie', draft.categoryCode.trim() || 'Non renseignée'],
          ['Durée', draft.duration.trim() ? formatDuration(Number(draft.duration)) : 'Non renseignée'],
          ['Validité', period(draft.validFrom, draft.validUntil || null)],
          ['Conditions', terms(draft.termsVersionId) ? `${terms(draft.termsVersionId)!.label} · v${terms(draft.termsVersionId)!.version}` : '—'],
          ['État', draft.enabled ? 'Active' : 'Désactivée'],
        ]} />
      </ConfirmDialog>}
    </div>
  );
}
