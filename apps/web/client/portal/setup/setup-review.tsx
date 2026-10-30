import type { ReactNode } from 'react';
import { Pencil, TriangleAlert } from 'lucide-react';
import { formatCents } from '../../command-core';
import { issueStep, resolvedSetupFormation, type SetupPreview, type SetupStep } from '../../setup-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Disclosure } from './setup-fields';
import { ProfilePreview } from './setup-steps';

const civilDate = (value: string) => {
  const [year, month, day] = value.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(Date.UTC(year!, month! - 1, day!)));
};

function Values({ items }: { items: readonly (readonly [string, ReactNode])[] }) {
  return <dl className="setup-values">{items.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>;
}

function Part({ title, onEdit, editLabel, children }: { title: string; onEdit: () => void; editLabel: string; children: ReactNode }) {
  return <section className="setup-summary-part">
    <header><h3>{title}</h3><Button type="button" variant="ghost" size="sm" aria-label={editLabel} onClick={onEdit}><Pencil aria-hidden="true" />Modifier</Button></header>
    {children}
  </section>;
}

/** Server review of the saved draft: consequences, targeted issues, then what will be adopted, each part editable. */
export function SetupSummary({ preview, onEdit }: { preview: SetupPreview; onEdit: (step: SetupStep, field?: string) => void }) {
  const { content } = preview;
  return <div className="setup-summary">
    {preview.effects.map(effect => <Alert key={effect}><TriangleAlert aria-hidden="true" /><AlertTitle>Conséquence de la modification</AlertTitle><AlertDescription>{effect}</AlertDescription></Alert>)}
    {preview.issues.length > 0 && <Alert variant="destructive"><AlertTitle>À compléter</AlertTitle><AlertDescription>
      <ul className="setup-issues">{preview.issues.map((issue, index) => <li key={`${issue.field}-${index}`}>
        <Button type="button" variant="link" className="setup-issue" onClick={() => onEdit(issueStep(issue.field), issue.field)}>{issue.message}</Button></li>)}</ul>
    </AlertDescription></Alert>}
    {content.selectedSections.includes('IDENTITY') && <Part title="École" editLabel="Modifier l’école" onEdit={() => onEdit('IDENTITY')}>
      <Values items={[['Nom', content.identity.name], ['E-mail', content.identity.contactEmail], ['Téléphone', content.identity.contactPhone ?? 'Non renseigné'], ['Fuseau', content.identity.timeZone]]} />
    </Part>}
    {content.selectedSections.includes('PRIVACY') && <Part title="Confidentialité" editLabel="Modifier les textes de confidentialité" onEdit={() => onEdit('PRIVACY')}>
      <Values items={[['Contact pour les données', content.privacy.contactEmail]]} />
      <Disclosure title="Relire les textes"><div className="setup-texts">
        <h4>Information des personnes</h4><p className="setup-copy">{content.privacy.noticeText}</p>
        <h4>Conservation</h4><p className="setup-copy">{content.privacy.retentionText}</p>
      </div></Disclosure>
    </Part>}
    {(preview.activate || content.selectedSections.includes('PROFILE')) && <Part title="Informations des élèves" editLabel="Modifier les informations des élèves" onEdit={() => onEdit('PROFILE')}>
      {content.selectedSections.includes('PROFILE')
        ? <Disclosure title="Relire le formulaire et les explications"><ProfilePreview fields={content.profile.fields} /></Disclosure>
        : <p className="setup-muted">Reportées à plus tard.</p>}
    </Part>}
    {preview.activate && !content.selectedSections.includes('CATALOGUE') && content.formations.length === 0 && <Part title="Formations et tarifs" editLabel="Modifier les formations" onEdit={() => onEdit('FORMATIONS')}>
      <p className="setup-muted">Reportées à plus tard.</p>
    </Part>}
    {content.formations.map(item => {
      const formation = resolvedSetupFormation(content, item);
      const title = formation.label || `Permis ${formation.categoryCode}`;
      const kept = !formation.apply || !content.selectedSections.includes('CATALOGUE');
      return <Part key={formation.id} title={title} editLabel={`Modifier · ${title}`} onEdit={() => onEdit('PRICING')}>
        {kept ? <p className="setup-muted">Conservée en brouillon · à terminer plus tard</p> : <>
          <Values items={[['Permis', formation.categoryCode], ['Durée', formation.durationMinutes === null ? 'À compléter' : `${formation.durationMinutes} min`],
            ['Prix', formation.priceCents === null ? 'À compléter' : formatCents(formation.priceCents)], ['Disponible dès le', formation.validFrom ? civilDate(formation.validFrom) : 'À compléter']]} />
          {!formation.existingOfferingId && <Disclosure title="Programme et déroulement"><div className="setup-texts">
            <ol className="setup-summary-competencies">{formation.competencies.map(competence => <li key={competence.key}><strong>{competence.label}</strong>{competence.description && <span className="setup-muted">{competence.description}</span>}</li>)}</ol>
            <p className="setup-copy">{formation.procedureText}</p>
          </div></Disclosure>}
          <Disclosure title="Annulation et conditions du tarif"><div className="setup-texts">
            <h4>Annulation</h4><p className="setup-copy">{formation.existingOfferingId ? 'Le déroulement et les conditions d’annulation de la formation sont conservés.' : formation.cancellationPolicyText}</p>
            <h4>Conditions du tarif</h4><p className="setup-copy">{formation.termsText}</p>
          </div></Disclosure>
        </>}
      </Part>;
    })}
  </div>;
}
