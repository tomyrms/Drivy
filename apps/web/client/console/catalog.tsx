import { useMemo, useState } from 'react';
import { centsToInput, createCommand, filled, formatCents, isHttpURL, parseCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { catalogPolicySchema, curriculumSchema, offeringSchema, readAll, type CatalogPolicy, type Curriculum, type Offering } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatDateTime, formatDuration } from '../ui';
import { useCommandRunner, useConsole, useLoad } from './context';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';

export const approvalBadge = (approved: boolean, feminine = false) => approved
  ? <StatusBadge tone="success" symbol="check">{feminine ? 'Approuvée' : 'Approuvé'}</StatusBadge>
  : <StatusBadge tone="warning" symbol="edit">Brouillon</StatusBadge>;
const uid = () => globalThis.crypto.randomUUID();
const byCategory = <T extends { categoryCode: string }>(order: (item: T) => number) => (a: T, b: T) =>
  a.categoryCode.localeCompare(b.categoryCode, 'fr') || order(b) - order(a);

/** Approval block shared by versioned catalog records: explicit checkbox, mandatory reason. */
function ApprovalFields({ approved, reason, onApproved, onReason, disabled, subject, showErrors }: {
  approved: boolean; reason: string; onApproved: (value: boolean) => void; onReason: (value: string) => void; disabled: boolean; subject: string; showErrors: boolean;
}) {
  return (
    <fieldset className="fieldset">
      <legend>Validation</legend>
      <CheckField label={`Approuver ${subject}`} checked={approved} onChange={onApproved} disabled={disabled}
        description="Sans approbation, cette version reste un brouillon. Une version existante n’est jamais réécrite." />
      <TextArea label="Motif de cette version" rows={2} maxLength={1000} value={reason} onChange={onReason} disabled={disabled}
        hint="Conservé avec la version pour expliquer ce changement." error={showErrors && !filled(reason, 1000) ? 'Indiquez le motif de cette version (1 000 caractères au plus).' : null} />
    </fieldset>
  );
}

/* ---------------------------------------------------------------- Référentiels */

type CompetencyDraft = { uid: string; key: string; label: string; description: string; sortOrder: string };
type CurriculumDraft = { categoryCode: string; approved: boolean; approvalReason: string; competencies: CompetencyDraft[]; basedOn: Curriculum | null };

function curriculumProblems(draft: CurriculumDraft) {
  const keys = draft.competencies.map(item => item.key.trim());
  const competency = draft.competencies.map((item, index) => ({
    key: !filled(item.key, 80) ? 'Clé requise (80 caractères au plus).' : keys.indexOf(item.key.trim()) !== index ? 'Cette clé est déjà utilisée.' : null,
    label: filled(item.label, 200) ? null : 'Libellé requis (200 caractères au plus).',
    description: filled(item.description, 4000) ? null : 'Description requise (4 000 caractères au plus).',
    sortOrder: /^\d{1,6}$/.test(item.sortOrder) && Number(item.sortOrder) <= 100_000 ? null : 'Nombre entier de 0 à 100 000.',
  }));
  const category = filled(draft.categoryCode, 30) ? null : 'Indiquez la catégorie (par exemple B).';
  const count = draft.competencies.length < 1 ? 'Ajoutez au moins une compétence.' : draft.competencies.length > 200 ? '200 compétences au plus.' : null;
  const reason = filled(draft.approvalReason, 1000) ? null : 'Motif requis.';
  const valid = !category && !count && !reason && competency.every(item => Object.values(item).every(value => value === null));
  return { category, count, reason, competency, valid };
}

export function CurriculaSection() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setDraft(null); setSelected(null); });
  const loaded = useLoad(() => readAll(schoolId, 'curricula', curriculumSchema), [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<CurriculumDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const items = useMemo(() => [...(loaded.data?.items ?? [])].sort(byCategory(item => item.revision)), [loaded.data]);
  const current = items.find(item => item.id === selected) ?? null;
  const problems = draft ? curriculumProblems(draft) : null;
  const canWrite = !runner.pending && !runner.busy;

  function edit(from: Curriculum | null, approve = false) {
    runner.clearOutcome(); setShowErrors(false);
    setDraft({ categoryCode: from?.categoryCode ?? '', approved: approve, approvalReason: '', basedOn: from,
      competencies: from ? from.competencies.map(item => ({ uid: uid(), key: item.key, label: item.label, description: item.description, sortOrder: String(item.sortOrder) }))
        : [{ uid: uid(), key: '', label: '', description: '', sortOrder: '10' }] });
  }
  const update = (change: Partial<CurriculumDraft>) => setDraft(value => value ? { ...value, ...change } : value);
  const updateCompetency = (key: string, change: Partial<CompetencyDraft>) =>
    setDraft(value => value ? { ...value, competencies: value.competencies.map(item => item.uid === key ? { ...item, ...change } : item) } : value);
  const nextRevision = draft ? Math.max(0, ...items.filter(item => item.categoryCode === draft.categoryCode.trim()).map(item => item.revision)) + 1 : 1;

  async function confirm() {
    if (!draft || !problems?.valid) return;
    const command = createCommand({ schoolId, kind: 'createCurriculum', path: 'curricula', resourceVersion: 0, body: {
      categoryCode: draft.categoryCode.trim(), approved: draft.approved, approvalReason: draft.approvalReason.trim(),
      competencies: draft.competencies.map(item => ({ key: item.key.trim(), label: item.label.trim(), description: item.description.trim(), sortOrder: Number(item.sortOrder) })) } });
    const result = await runner.run(command, draft.approved ? 'Le référentiel approuvé est créé.' : 'Le brouillon de référentiel est enregistré.');
    setReviewing(false);
    if (result.status === 'confirmed') { setDraft(null); setSelected(null); }
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Catalogue" title="Référentiels" description="Compétences travaillées pour chaque catégorie. Chaque modification crée une nouvelle révision ; l’approbation est toujours explicite."
        actions={<button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { setSelected(null); edit(null); }}><Symbol kind="plus" bare />Nouveau référentiel</button>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des référentiels…">{data => <SplitView
        list={items.length === 0 ? <EmptyState symbol="book" title="Aucun référentiel" message="Préparez un premier référentiel pour une catégorie, puis approuvez-le pour ouvrir une offre." />
          : <table className="data-table">
            <caption className="visually-hidden">Référentiels de l’école{data.truncated ? ' (liste partielle)' : ''}</caption>
            <thead><tr><th scope="col">Catégorie</th><th scope="col" className="numeric">Révision</th><th scope="col" className="numeric">Compétences</th><th scope="col">Statut</th></tr></thead>
            <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>Catégorie {item.categoryCode}</RowButton></th>
              <td className="numeric">{item.revision}</td><td className="numeric">{item.competencies.length}</td><td>{approvalBadge(item.approved)}</td>
            </tr>)}</tbody>
          </table>}
        detail={draft && problems ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title={draft.basedOn ? `Nouvelle révision · catégorie ${draft.basedOn.categoryCode}` : 'Nouveau référentiel'}
            meta={draft.basedOn ? `À partir de la révision ${draft.basedOn.revision}, qui reste inchangée.` : 'La révision est numérotée par l’école.'}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (problems.valid) { setAcknowledged(false); setReviewing(true); } }}>Relire avant d’enregistrer</button>
              <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <TextField label="Catégorie" value={draft.categoryCode} maxLength={30} placeholder="Par exemple B" disabled={!canWrite || !!draft.basedOn}
                onChange={categoryCode => update({ categoryCode })} error={showErrors ? problems.category : null}
                hint={draft.basedOn ? 'Une nouvelle révision garde la catégorie.' : undefined} />
              <fieldset className="fieldset">
                <legend>Compétences</legend>
                {problems.count && showErrors && <p className="field-error"><Symbol kind="alert" bare />{problems.count}</p>}
                {draft.competencies.map((item, index) => <div className="repeat-row" key={item.uid}>
                  <p className="repeat-title">Compétence {index + 1}</p>
                  <div className="form-row">
                    <TextField label="Clé stable" value={item.key} maxLength={80} disabled={!canWrite} onChange={key => updateCompetency(item.uid, { key })} error={showErrors ? problems.competency[index]?.key : null} />
                    <TextField label="Ordre" value={item.sortOrder} inputMode="numeric" disabled={!canWrite} onChange={sortOrder => updateCompetency(item.uid, { sortOrder })} error={showErrors ? problems.competency[index]?.sortOrder : null} />
                  </div>
                  <TextField label="Libellé" value={item.label} maxLength={200} disabled={!canWrite} onChange={label => updateCompetency(item.uid, { label })} error={showErrors ? problems.competency[index]?.label : null} />
                  <TextArea label="Description" rows={2} maxLength={4000} value={item.description} disabled={!canWrite} onChange={description => updateCompetency(item.uid, { description })} error={showErrors ? problems.competency[index]?.description : null} />
                  {draft.competencies.length > 1 && <button type="button" className="button quiet danger" disabled={!canWrite}
                    onClick={() => update({ competencies: draft.competencies.filter(other => other.uid !== item.uid) })}>Retirer la compétence {index + 1}</button>}
                </div>)}
                <button type="button" className="button secondary" disabled={!canWrite || draft.competencies.length >= 200}
                  onClick={() => update({ competencies: [...draft.competencies, { uid: uid(), key: '', label: '', description: '', sortOrder: String((draft.competencies.length + 1) * 10) }] })}>
                  <Symbol kind="plus" bare />Ajouter une compétence</button>
              </fieldset>
              <ApprovalFields approved={draft.approved} reason={draft.approvalReason} onApproved={approved => update({ approved })} onReason={approvalReason => update({ approvalReason })}
                disabled={!canWrite} subject="ce référentiel" showErrors={showErrors} />
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={`Catégorie ${current.categoryCode} · révision ${current.revision}`} badge={approvalBadge(current.approved)}
            actions={<>
              {!current.approved && <button type="button" className="button primary" disabled={!canWrite} onClick={() => edit(current, true)}>Approuver…</button>}
              <button type="button" className={current.approved ? 'button primary' : 'button secondary'} disabled={!canWrite} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle révision</button>
            </>}>
            {!current.approved && <p className="caption">Approuver crée une nouvelle révision identique, approuvée : cette révision reste un brouillon.</p>}
            <ol className="competency-list">{[...current.competencies].sort((a, b) => a.sortOrder - b.sortOrder).map(item => <li key={item.id}>
              <h3 className="row-title">{item.label}</h3><p className="row-meta"><code>{item.key}</code> · ordre {item.sortOrder}</p><p className="policy-copy">{item.description}</p>
            </li>)}</ol>
          </DetailPanel>
          : <Placeholder>Choisissez un référentiel pour consulter ses compétences, ou créez-en un nouveau.</Placeholder>} />}
      </LoadState>
      {draft && problems && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title={draft.approved ? 'Approuver ce référentiel' : 'Enregistrer ce brouillon'} confirmLabel={draft.approved ? 'Créer le référentiel approuvé' : 'Enregistrer le brouillon'}
        acknowledgement={draft.approved ? 'J’ai relu les compétences et je confirme leur approbation.' : 'Je confirme l’enregistrement de ce brouillon.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
        <p className="dialog-lead">Catégorie {draft.categoryCode.trim()} · révision {nextRevision} prévue</p>
        <ol className="competency-list compact">{draft.competencies.map(item => <li key={item.uid}><strong>{item.label.trim()}</strong> <span className="row-meta">({item.key.trim()})</span></li>)}</ol>
        <Facts items={[['Motif', draft.approvalReason.trim()], ['École', school.name]]} />
        <p className="caption">{draft.approved ? 'Le référentiel sera approuvé pour cette catégorie.' : 'Le référentiel restera un brouillon : aucune offre activée ne pourra l’utiliser.'}</p>
      </ConfirmDialog>}
    </div>
  );
}

/* ---------------------------------------------------------------- Procédures */

type ProcedureDraft = { categoryCode: string; procedureText: string; cancellationPolicyText: string; sources: string; approved: boolean; approvalReason: string; basedOn: CatalogPolicy | null };
const sourceList = (text: string) => text.split('\n').map(line => line.trim()).filter(Boolean);
function procedureProblems(draft: ProcedureDraft) {
  const sources = sourceList(draft.sources);
  const result = {
    category: filled(draft.categoryCode, 30) ? null : 'Indiquez la catégorie (par exemple B).',
    procedure: filled(draft.procedureText, 4000) ? null : 'Décrivez le déroulement (4 000 caractères au plus).',
    cancellation: filled(draft.cancellationPolicyText, 4000) ? null : 'Décrivez les conditions d’annulation (4 000 caractères au plus).',
    sources: sources.length > 30 ? '30 adresses au plus.' : sources.some(value => !isHttpURL(value)) ? 'Chaque ligne doit être une adresse web complète (https://…).' : null,
    reason: filled(draft.approvalReason, 1000) ? null : 'Motif requis.',
  };
  return { ...result, valid: Object.values(result).every(value => value === null) };
}

export function ProceduresSection() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setDraft(null); setSelected(null); });
  const loaded = useLoad(() => readAll(schoolId, 'policy-versions', catalogPolicySchema), [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<ProcedureDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const items = useMemo(() => [...(loaded.data?.items ?? [])].sort(byCategory(item => item.version)), [loaded.data]);
  const current = items.find(item => item.id === selected) ?? null;
  const problems = draft ? procedureProblems(draft) : null;
  const canWrite = !runner.pending && !runner.busy;
  const update = (change: Partial<ProcedureDraft>) => setDraft(value => value ? { ...value, ...change } : value);
  function edit(from: CatalogPolicy | null, approve = false) {
    runner.clearOutcome(); setShowErrors(false);
    setDraft({ categoryCode: from?.categoryCode ?? '', procedureText: from?.procedureText ?? '', cancellationPolicyText: from?.cancellationPolicyText ?? '',
      sources: from?.sourceUrls.join('\n') ?? '', approved: approve, approvalReason: '', basedOn: from });
  }
  async function confirm() {
    if (!draft || !problems?.valid) return;
    const command = createCommand({ schoolId, kind: 'createCatalogPolicy', path: 'policy-versions', resourceVersion: 0, body: {
      categoryCode: draft.categoryCode.trim(), procedureText: draft.procedureText.trim(), cancellationPolicyText: draft.cancellationPolicyText.trim(),
      sourceUrls: sourceList(draft.sources), approved: draft.approved, approvalReason: draft.approvalReason.trim() } });
    const result = await runner.run(command, draft.approved ? 'La procédure approuvée est créée.' : 'Le brouillon de procédure est enregistré.');
    setReviewing(false);
    if (result.status === 'confirmed') { setDraft(null); setSelected(null); }
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Catalogue" title="Procédures" description="Déroulement de la formation et conditions d’annulation, par catégorie. Distinct de la notice de données et des champs du profil."
        actions={<button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { setSelected(null); edit(null); }}><Symbol kind="plus" bare />Nouvelle procédure</button>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des procédures…">{() => <SplitView
        list={items.length === 0 ? <EmptyState symbol="file" title="Aucune procédure" message="Rédigez la procédure d’une catégorie, puis approuvez-la pour ouvrir une offre." />
          : <table className="data-table">
            <caption className="visually-hidden">Procédures de l’école</caption>
            <thead><tr><th scope="col">Catégorie</th><th scope="col" className="numeric">Version</th><th scope="col">Approuvée le</th><th scope="col">Statut</th></tr></thead>
            <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>Catégorie {item.categoryCode}</RowButton></th>
              <td className="numeric">{item.version}</td><td>{item.approvedAt ? formatDateTime(item.approvedAt, school.timeZone) : '—'}</td><td>{approvalBadge(item.approved, true)}</td>
            </tr>)}</tbody>
          </table>}
        detail={draft && problems ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title={draft.basedOn ? `Nouvelle version · catégorie ${draft.basedOn.categoryCode}` : 'Nouvelle procédure'}
            meta={draft.basedOn ? `À partir de la version ${draft.basedOn.version}, qui reste inchangée.` : undefined}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (problems.valid) { setAcknowledged(false); setReviewing(true); } }}>Relire avant d’enregistrer</button>
              <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <TextField label="Catégorie" value={draft.categoryCode} maxLength={30} placeholder="Par exemple B" disabled={!canWrite || !!draft.basedOn}
                onChange={categoryCode => update({ categoryCode })} error={showErrors ? problems.category : null} />
              <TextArea label="Déroulement de la formation" rows={6} maxLength={4000} value={draft.procedureText} disabled={!canWrite}
                onChange={procedureText => update({ procedureText })} error={showErrors ? problems.procedure : null} />
              <TextArea label="Conditions d’annulation" rows={4} maxLength={4000} value={draft.cancellationPolicyText} disabled={!canWrite}
                onChange={cancellationPolicyText => update({ cancellationPolicyText })} error={showErrors ? problems.cancellation : null} />
              <TextArea label="Sources" required={false} rows={3} value={draft.sources} disabled={!canWrite} hint="Une adresse web par ligne, 30 au plus."
                onChange={sources => update({ sources })} error={problems.sources} />
              <ApprovalFields approved={draft.approved} reason={draft.approvalReason} onApproved={approved => update({ approved })} onReason={approvalReason => update({ approvalReason })}
                disabled={!canWrite} subject="ces textes" showErrors={showErrors} />
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={`Catégorie ${current.categoryCode} · version ${current.version}`} badge={approvalBadge(current.approved, true)}
            actions={<>
              {!current.approved && <button type="button" className="button primary" disabled={!canWrite} onClick={() => edit(current, true)}>Approuver…</button>}
              <button type="button" className={current.approved ? 'button primary' : 'button secondary'} disabled={!canWrite} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle version</button>
            </>}>
            {!current.approved && <p className="caption">Approuver crée une nouvelle version identique, approuvée : cette version reste un brouillon.</p>}
            <h3>Déroulement de la formation</h3><p className="policy-copy">{current.procedureText}</p>
            <h3>Conditions d’annulation</h3><p className="policy-copy">{current.cancellationPolicyText}</p>
            {current.sourceUrls.length > 0 && <><h3>Sources</h3><ul className="plain-list">{current.sourceUrls.map(url => <li key={url}><a href={url} rel="noopener noreferrer" target="_blank">{url}</a></li>)}</ul></>}
          </DetailPanel>
          : <Placeholder>Choisissez une procédure pour la relire, ou créez-en une nouvelle.</Placeholder>} />}
      </LoadState>
      {draft && problems && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title={draft.approved ? 'Approuver cette procédure' : 'Enregistrer ce brouillon'} confirmLabel={draft.approved ? 'Créer la procédure approuvée' : 'Enregistrer le brouillon'}
        acknowledgement={draft.approved ? 'J’ai relu ces textes et je confirme leur approbation.' : 'Je confirme l’enregistrement de ce brouillon.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
        <p className="dialog-lead">Catégorie {draft.categoryCode.trim()}</p>
        <h3>Déroulement de la formation</h3><p className="policy-copy review-copy">{draft.procedureText.trim()}</p>
        <h3>Conditions d’annulation</h3><p className="policy-copy review-copy">{draft.cancellationPolicyText.trim()}</p>
        <Facts items={[['Sources', sourceList(draft.sources).length ? `${sourceList(draft.sources).length} adresse(s)` : 'Aucune'], ['Motif', draft.approvalReason.trim()]]} />
        <p className="caption">{draft.approved ? 'Ces textes seront approuvés pour cette catégorie.' : 'Ces textes resteront un brouillon.'}</p>
      </ConfirmDialog>}
    </div>
  );
}

/* ---------------------------------------------------------------- Offres */

type OfferingDraft = { offeringKey: string; categoryCode: string; curriculumVersionId: string; policyVersionId: string; enabled: boolean; duration: string; price: string; basedOn: Offering | null };

export function OfferingsSection() {
  const { schoolId, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setDraft(null); setSelected(null); });
  const loaded = useLoad(async () => {
    const [offerings, curricula, policies] = await Promise.all([readAll(schoolId, 'offerings', offeringSchema),
      readAll(schoolId, 'curricula', curriculumSchema), readAll(schoolId, 'policy-versions', catalogPolicySchema)]);
    return { offerings: offerings.items, curricula: curricula.items, policies: policies.items };
  }, [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [history, setHistory] = useState(false);
  const [draft, setDraft] = useState<OfferingDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const data = loaded.data;
  const latest = useMemo(() => {
    const map = new Map<string, Offering>();
    for (const item of data?.offerings ?? []) if ((map.get(item.offeringKey)?.version ?? 0) < item.version) map.set(item.offeringKey, item);
    return map;
  }, [data]);
  const rows = useMemo(() => [...(data?.offerings ?? [])].filter(item => history || latest.get(item.offeringKey)?.id === item.id)
    .sort((a, b) => a.offeringKey.localeCompare(b.offeringKey, 'fr') || b.version - a.version), [data, history, latest]);
  const current = data?.offerings.find(item => item.id === selected) ?? null;
  const canWrite = !runner.pending && !runner.busy;
  const curriculum = (id: string) => data?.curricula.find(item => item.id === id);
  const policy = (id: string) => data?.policies.find(item => item.id === id);
  const update = (change: Partial<OfferingDraft>) => setDraft(value => value ? { ...value, ...change } : value);

  const category = draft?.categoryCode.trim() ?? '';
  const curriculumOptions = (data?.curricula ?? []).filter(item => item.categoryCode === category).sort((a, b) => b.revision - a.revision);
  const policyOptions = (data?.policies ?? []).filter(item => item.categoryCode === category).sort((a, b) => b.version - a.version);
  const refsApproved = !!draft && curriculum(draft.curriculumVersionId)?.approved === true && policy(draft.policyVersionId)?.approved === true;
  const problems = draft ? (() => {
    const duration = Number(draft.duration);
    const result = {
      key: filled(draft.offeringKey, 80) ? null : 'Indiquez la référence de l’offre (80 caractères au plus).',
      category: filled(draft.categoryCode, 30) ? null : 'Indiquez la catégorie.',
      curriculum: curriculumOptions.some(item => item.id === draft.curriculumVersionId) ? null : 'Choisissez un référentiel de cette catégorie.',
      policy: policyOptions.some(item => item.id === draft.policyVersionId) ? null : 'Choisissez une procédure de cette catégorie.',
      duration: /^\d{1,3}$/.test(draft.duration) && duration >= 1 && duration <= 480 ? null : 'Durée en minutes, de 1 à 480.',
      price: parseCents(draft.price) === null ? 'Indiquez un prix valide en CHF, par exemple 95 ou 95.50.' : null,
      enabled: draft.enabled && !refsApproved ? 'Une offre activée exige un référentiel et une procédure approuvés.' : null,
    };
    return { ...result, valid: Object.values(result).every(value => value === null) };
  })() : null;

  function edit(from: Offering | null) {
    runner.clearOutcome(); setShowErrors(false);
    setDraft({ offeringKey: from?.offeringKey ?? '', categoryCode: from?.categoryCode ?? '', curriculumVersionId: from?.curriculumVersionId ?? '',
      policyVersionId: from?.policyVersionId ?? '', enabled: false, duration: from ? String(from.defaultDurationMinutes) : '45',
      price: from ? centsToInput(from.defaultPriceCents) : '', basedOn: from });
  }
  async function confirm() {
    if (!draft || !problems?.valid) return;
    const command = createCommand({ schoolId, kind: 'createOffering', path: 'offerings', resourceVersion: 0, body: {
      offeringKey: draft.offeringKey.trim(), categoryCode: draft.categoryCode.trim(), curriculumVersionId: draft.curriculumVersionId,
      policyVersionId: draft.policyVersionId, enabled: draft.enabled, defaultDurationMinutes: Number(draft.duration), defaultPriceCents: parseCents(draft.price)! } });
    const result = await runner.run(command, draft.enabled ? 'La version de l’offre est créée et activée.' : 'La version de l’offre est créée, désactivée.');
    setReviewing(false);
    if (result.status === 'confirmed') { setDraft(null); setSelected(null); }
  }
  const offerState = (item: Offering) => item.enabled ? <StatusBadge tone="success" symbol="check">Activée</StatusBadge> : <StatusBadge tone="neutral" symbol="dot">Désactivée</StatusBadge>;

  return (
    <div className="section-stack">
      <SectionHeading context="Catalogue" title="Offres" description="Formations proposées par l’école. Une offre activée s’appuie sur un référentiel et une procédure approuvés ; ce choix ne les approuve pas."
        actions={<button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { setSelected(null); edit(null); }}><Symbol kind="plus" bare />Nouvelle offre</button>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des offres…">{value => <SplitView
        list={<>
          <div className="list-toolbar"><CheckField label="Afficher les versions précédentes" checked={history} onChange={setHistory} /></div>
          {rows.length === 0 ? <EmptyState symbol="layers" title="Aucune offre" message="Créez une offre à partir d’un référentiel et d’une procédure de la même catégorie." />
          : <table className="data-table">
            <caption className="visually-hidden">Offres de l’école</caption>
            <thead><tr><th scope="col">Offre</th><th scope="col">Cat.</th><th scope="col" className="numeric">Version</th><th scope="col" className="numeric">Durée</th><th scope="col" className="numeric">Prix</th><th scope="col">État</th></tr></thead>
            <tbody>{rows.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>{item.offeringKey}</RowButton>
                {latest.get(item.offeringKey)?.id !== item.id && <span className="caption"> · ancienne version</span>}</th>
              <td>{item.categoryCode}</td><td className="numeric">{item.version}</td>
              <td className="numeric">{formatDuration(item.defaultDurationMinutes)}</td><td className="numeric">{formatCents(item.defaultPriceCents)}</td><td>{offerState(item)}</td>
            </tr>)}</tbody>
          </table>}
        </>}
        detail={draft && problems ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title={draft.basedOn ? `Nouvelle version · ${draft.basedOn.offeringKey}` : 'Nouvelle offre'}
            meta={draft.basedOn ? `À partir de la version ${draft.basedOn.version}, qui reste inchangée.` : undefined}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (problems.valid) { setAcknowledged(false); setReviewing(true); } }}>Relire avant d’enregistrer</button>
              <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <div className="form-row">
                <TextField label="Référence de l’offre" value={draft.offeringKey} maxLength={80} disabled={!canWrite || !!draft.basedOn} placeholder="Par exemple b-standard"
                  onChange={offeringKey => update({ offeringKey })} error={showErrors ? problems.key : null} />
                <TextField label="Catégorie" value={draft.categoryCode} maxLength={30} disabled={!canWrite || !!draft.basedOn} placeholder="Par exemple B"
                  onChange={categoryCode => update({ categoryCode, curriculumVersionId: '', policyVersionId: '' })} error={showErrors ? problems.category : null}
                  hint={draft.basedOn ? 'Une offre garde sa référence et sa catégorie.' : undefined} />
              </div>
              {category && curriculumOptions.length === 0 && policyOptions.length === 0 && <Notice tone="info" title="Contenus à créer" live={false}
                actions={<><button type="button" className="button quiet" onClick={() => navigate('referentiels')}>Ouvrir les référentiels</button><button type="button" className="button quiet" onClick={() => navigate('procedures')}>Ouvrir les procédures</button></>}>
                <p>Créez d’abord le référentiel et la procédure de la catégorie {category}.</p></Notice>}
              <SelectField label="Référentiel" value={draft.curriculumVersionId} placeholder="Choisir un référentiel" disabled={!canWrite || !category}
                options={curriculumOptions.map(item => ({ value: item.id, label: `Révision ${item.revision} · ${item.approved ? 'approuvée' : 'brouillon'}` }))}
                onChange={curriculumVersionId => update({ curriculumVersionId })} error={showErrors ? problems.curriculum : null} />
              <SelectField label="Procédure" value={draft.policyVersionId} placeholder="Choisir une procédure" disabled={!canWrite || !category}
                options={policyOptions.map(item => ({ value: item.id, label: `Version ${item.version} · ${item.approved ? 'approuvée' : 'brouillon'}` }))}
                onChange={policyVersionId => update({ policyVersionId })} error={showErrors ? problems.policy : null} />
              <div className="form-row">
                <TextField label="Durée par défaut (minutes)" value={draft.duration} inputMode="numeric" disabled={!canWrite} onChange={duration => update({ duration })} error={showErrors ? problems.duration : null} />
                <TextField label="Prix par défaut (CHF)" value={draft.price} inputMode="decimal" disabled={!canWrite} onChange={price => update({ price })} error={showErrors ? problems.price : null} />
              </div>
              <CheckField label="Activer cette version de l’offre" checked={draft.enabled} onChange={enabled => update({ enabled })} disabled={!canWrite}
                description="Une offre activée permet d’ouvrir de nouvelles formations. Elle exige un référentiel et une procédure approuvés." />
              {problems.enabled && <p className="field-error"><Symbol kind="alert" bare />{problems.enabled}</p>}
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={current.offeringKey} meta={`Catégorie ${current.categoryCode} · version ${current.version}`} badge={offerState(current)}
            actions={<button type="button" className="button primary" disabled={!canWrite} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle version</button>}>
            <Facts items={[
              ['Référentiel', curriculum(current.curriculumVersionId) ? <>Révision {curriculum(current.curriculumVersionId)!.revision} {approvalBadge(curriculum(current.curriculumVersionId)!.approved)}</> : 'Non disponible'],
              ['Procédure', policy(current.policyVersionId) ? <>Version {policy(current.policyVersionId)!.version} {approvalBadge(policy(current.policyVersionId)!.approved, true)}</> : 'Non disponible'],
              ['Durée par défaut', formatDuration(current.defaultDurationMinutes)],
              ['Prix par défaut', formatCents(current.defaultPriceCents)],
            ]} />
            {latest.get(current.offeringKey)?.id !== current.id && <p className="caption">Une version plus récente de cette offre existe.</p>}
            <p className="caption">Une nouvelle version ne modifie pas les formations déjà ouvertes. Elle est créée désactivée tant que vous ne cochez pas l’activation.</p>
          </DetailPanel>
          : <Placeholder>{value.offerings.length ? 'Choisissez une offre pour la consulter.' : 'Créez une première offre.'}</Placeholder>} />}
      </LoadState>
      {draft && problems && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title="Relire l’offre" confirmLabel={draft.enabled ? 'Créer et activer l’offre' : 'Créer l’offre désactivée'}
        acknowledgement={draft.enabled ? 'J’ai relu cette offre et je confirme son activation.' : 'Je confirme la création de cette version désactivée.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
        <p className="dialog-lead">{draft.offeringKey.trim()} · catégorie {draft.categoryCode.trim()}</p>
        <Facts items={[
          ['Référentiel', `Révision ${curriculum(draft.curriculumVersionId)?.revision ?? '?'} · ${curriculum(draft.curriculumVersionId)?.approved ? 'approuvée' : 'brouillon'}`],
          ['Procédure', `Version ${policy(draft.policyVersionId)?.version ?? '?'} · ${policy(draft.policyVersionId)?.approved ? 'approuvée' : 'brouillon'}`],
          ['Durée par défaut', formatDuration(Number(draft.duration))],
          ['Prix par défaut', parseCents(draft.price) !== null ? formatCents(parseCents(draft.price)!) : '—'],
          ['État', draft.enabled ? 'Activée' : 'Désactivée'],
        ]} />
      </ConfirmDialog>}
    </div>
  );
}
