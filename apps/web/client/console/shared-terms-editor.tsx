import { useRef, useState } from 'react';
import { createCommand } from '../command-core';
import type { CatalogueReference } from '../formation-api';
import { CheckField, TextArea } from '../ui';
import { useCommandRunner, useConsole, useUnsavedChanges } from './context';
import { OutcomeNotice } from './layout';

export function SharedTermsEditor({ reference }: { reference: Extract<CatalogueReference, { kind: 'TERMS' }> }) {
  const { schoolId, canConfigureCatalog } = useConsole();
  const [editing, setEditing] = useState(false);
  const form = useRef<HTMLFormElement>(null);
  const editButton = useRef<HTMLButtonElement>(null);
  const [text, setText] = useState(reference.terms.termsText);
  const [reviewed, setReviewed] = useState(false);
  const changed = text !== reference.terms.termsText;
  const release = useUnsavedChanges(editing && changed);
  const runner = useCommandRunner(() => { release(); setEditing(false); });
  const current = reference.usedBy.filter(item => item.current);
  const blocked = runner.busy || !!runner.pending;
  if (!canConfigureCatalog || !current.length) return null;
  return <div className="section-stack shared-terms-editor"><OutcomeNotice outcome={runner.outcome} />
    {!editing ? <button ref={editButton} className="button secondary" type="button" onClick={() => { setEditing(true); requestAnimationFrame(() => form.current?.querySelector('textarea')?.focus()); }}>Modifier les conditions communes</button>
      : <form ref={form} className="section-stack shared-terms-form" onSubmit={event => {
        event.preventDefault(); if (blocked || !changed || !reviewed || text.trim().length < 20) return;
        void runner.run(createCommand({ schoolId, kind: 'reviseSharedTerms', path: 'formations/terms/revise', resourceVersion: 0,
          body: { termsVersionId: reference.id, expectedProductVersionIds: current.map(item => item.id), termsText: text, reviewAcknowledged: true } }), 'Les nouvelles conditions sont enregistrées.');
      }}>
        <TextArea label="Conditions communes" value={text} rows={10} maxLength={20000} disabled={blocked} onChange={value => { setText(value); setReviewed(false); }} />
        <div className="shared-terms-impact"><h3>Tarifs concernés ({current.length})</h3><ul className="plain-list">{current.map(item => <li key={item.id}>{item.label}{item.categoryCode ? ` · permis ${item.categoryCode}` : ' · sans permis'}</li>)}</ul>
          <p>Les réservations existantes gardent leurs conditions. Les tarifs ci-dessus recevront une nouvelle version.</p></div>
        <CheckField label="J’ai relu le texte et les tarifs concernés." checked={reviewed} disabled={blocked} onChange={setReviewed} />
        <div className="button-row"><button type="button" className="button quiet" disabled={blocked} onClick={() => { setText(reference.terms.termsText); setReviewed(false); setEditing(false); requestAnimationFrame(() => editButton.current?.focus()); }}>Annuler</button>
          <button type="submit" className="button primary" disabled={blocked || !changed || !reviewed || text.trim().length < 20}>Adopter les nouvelles conditions</button></div>
      </form>}
  </div>;
}
