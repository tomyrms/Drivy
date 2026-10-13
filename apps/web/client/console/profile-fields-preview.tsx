import type { ProfilePolicy } from '../school-api';
import { setupProfileRequirement } from '../setup-model';
import './profile-fields-preview.css';

const labels: Record<string, string> = { firstName: 'Prénom', lastName: 'Nom', contactPhone: 'Téléphone', contactEmail: 'E-mail',
  birthDate: 'Date de naissance', postalAddress: 'Adresse postale', profilePhotoDocumentId: 'Photo de profil' };
const types: Record<string, string> = { contactPhone: 'tel', contactEmail: 'email', birthDate: 'date' };

/** Empty, read-only controls show the selected fields and their exact explanation without collecting a pupil's data. */
export function ProfileFieldsPreview({ fields }: { fields: readonly ProfilePolicy['fields'][number][] }) {
  return <div className="profile-fields-preview" aria-label="Aperçu du formulaire élève">{fields.map(field => <div className="profile-preview-field" key={field.field}>
    <div className="profile-preview-label"><strong>{labels[field.field]}</strong><span className="row-meta">{setupProfileRequirement(field)}</span></div>
    {field.field === 'profilePhotoDocumentId' ? <div className="profile-preview-photo" role="img" aria-label="Emplacement de la photo de profil" />
      : field.field === 'postalAddress' ? <textarea aria-label={labels[field.field]} rows={2} readOnly tabIndex={-1} value="" />
      : <input aria-label={labels[field.field]} type={types[field.field] ?? 'text'} readOnly tabIndex={-1} value="" />}
    <p className="caption policy-copy">{field.explanation}</p>
  </div>)}</div>;
}
