import { useId, useState } from 'react';
import { CircleCheck, Plus, X } from 'lucide-react';
import { commonLessonTexts, type CommonLessonRules } from '../../common-lesson-rules';
import type { Offering } from '../../school-api';
import {
  resolvedSetupFormation, selectSetupSection, setupFormation, setupPrice, setupProfileRequirement, templateAlreadyAdded,
  type SetupContent, type SetupFormation, type SetupTemplates,
} from '../../setup-model';
import { priceAmountProblem } from '../../console/formation-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Input } from '../../components/ui/input';
import { Label } from '../../components/ui/label';
import { RadioGroup, RadioGroupItem } from '../../components/ui/radio-group';
import { Textarea } from '../../components/ui/textarea';
import { PortalSelect } from '../components/portal-select';
import { CheckRow, Disclosure, TextAreaField, TextField } from './setup-fields';
import { applyProfileChoice, minutesValue, priceInput, profileChoiceOf, profileChoices, profileFieldDefaults, profileFieldLabels, templatePrivacy, type ProfileFieldRule } from './setup-guide-model';

export type StepProps = { content: SetupContent; onChange: (value: SetupContent) => void; errorFor: (path: string) => string | null };
const formationTitle = (formation: SetupFormation, index: number) => formation.label || (formation.categoryCode ? `Permis ${formation.categoryCode}` : `Formation ${index + 1}`);
const hasError = (errorFor: StepProps['errorFor'], paths: readonly string[]) => paths.some(path => !!errorFor(path));

function PermitCode({ code }: { code: string }) {
  return <span className="setup-code" aria-hidden="true">{code.trim().slice(0, 3) || '·'}</span>;
}

function NoCatalogueAccess() {
  return <Alert><AlertTitle>Accès aux tarifs requis</AlertTitle><AlertDescription>Un administrateur doit vous donner l’autorisation de configurer le catalogue.</AlertDescription></Alert>;
}

/* ------------------------------------------------------------ Permis */

export function FormationsStep({ content, templates, offerings, initialOfferingId, today, onChange, canWrite, errorFor }: StepProps & {
  templates: SetupTemplates; offerings: Offering[]; initialOfferingId?: string | undefined; today: string; canWrite: boolean;
}) {
  const add = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: [...content.formations, value] }, 'CATALOGUE', true));
  const update = (value: SetupFormation) => onChange({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) });
  const [chosen, setChosen] = useState(offerings.some(item => item.id === initialOfferingId) ? initialOfferingId! : '');
  const full = content.formations.length >= 20;
  if (!canWrite) return <NoCatalogueAccess />;
  const available = templates.formations.filter(template => !offerings.some(offer => offer.categoryCode === template.categoryCode));
  return <div className="setup-step-body">
    <div className="setup-templates" role="group" aria-label="Permis proposés">
      {available.map(template => {
        const added = templateAlreadyAdded(content.formations, template.categoryCode);
        return <Button key={template.id} type="button" variant="outline" className="setup-template" disabled={full || added} aria-pressed={added}
          onClick={() => add(setupFormation(template, today))}>
          <PermitCode code={template.categoryCode} /><span>{template.label}</span>{added ? <CircleCheck aria-hidden="true" /> : <Plus aria-hidden="true" />}
        </Button>;
      })}
      <Button type="button" variant="ghost" className="setup-template setup-template-other" disabled={full} onClick={() => add(setupFormation(null, today))}><Plus aria-hidden="true" />Autre formation</Button>
    </div>
    {offerings.length > 0 && <Disclosure title="Ajouter un tarif à une formation existante" open={!!initialOfferingId}>
      <div className="setup-inline-form">
        <PortalSelect id="setup-existing-offering" label="Formation" searchable value={chosen || null} onValueChange={value => setChosen(value ?? '')} placeholder="Choisir une formation"
          options={offerings.map(offer => ({ value: offer.id, label: `${offer.label ? `${offer.label} · ` : ''}Permis ${offer.categoryCode} · ${offer.defaultDurationMinutes} min` }))} />
        <Button type="button" variant="outline" disabled={!chosen || full} onClick={() => {
          const offer = offerings.find(item => item.id === chosen); if (!offer) return;
          add({ ...setupFormation(null, today), existingOfferingId: offer.id, useCommonTerms: false, categoryCode: offer.categoryCode, label: `Leçon ${offer.categoryCode}`, durationMinutes: offer.defaultDurationMinutes, competencies: [] });
          setChosen('');
        }}>Préparer ce tarif</Button>
      </div>
    </Disclosure>}
    {content.formations.length > 0 && <ul className="setup-items" aria-label="Formations du brouillon">{content.formations.map((formation, index) => {
      const prefix = `formations.${index}`;
      const title = formationTitle(formation, index);
      const template = templates.formations.find(item => item.id === formation.templateId);
      return <li key={formation.id} className="setup-item">
        <div className="setup-item-head">
          <PermitCode code={formation.categoryCode} />
          <div className="setup-item-title"><h3>{title}</h3>
            <span className="setup-muted">{formation.existingOfferingId ? 'Nouveau tarif d’une formation existante' : formation.templateId ? 'Programme proposé par Drivy' : 'Formation à décrire'}</span></div>
          <Button type="button" variant="ghost" size="icon" aria-label={`Retirer du brouillon · ${title}`} onClick={() => onChange({ ...content, formations: content.formations.filter(item => item.id !== formation.id) })}><X aria-hidden="true" /></Button>
        </div>
        <Disclosure title="Nom et permis" open={!formation.templateId && !formation.existingOfferingId || hasError(errorFor, [`${prefix}.categoryCode`, `${prefix}.label`])}>
          <div className="setup-grid">
            <TextField name={`${prefix}.categoryCode`} label="Permis" value={formation.categoryCode} maxLength={30} disabled={!!formation.existingOfferingId} error={errorFor(`${prefix}.categoryCode`)}
              onChange={categoryCode => update({ ...formation, categoryCode, templateId: null, templateVersion: null })} />
            <TextField name={`${prefix}.label`} label="Nom de la formation ou du tarif" value={formation.label} maxLength={200} error={errorFor(`${prefix}.label`)} onChange={label => update({ ...formation, label })} />
          </div>
        </Disclosure>
        {!formation.existingOfferingId && <>
          {formation.templateId && <Disclosure title="Référence du programme" open={!!errorFor(`${prefix}.templateVersion`)}>
            <div className="setup-reference">
              <p>Proposition Drivy · {formation.templateVersion}</p>
              {template?.coverageNote && <p className="setup-muted">{template.coverageNote}</p>}
              <p className="setup-muted">À relire par l’école ; ce programme ne certifie pas les prérequis de l’élève.</p>
              {formation.sourceUrls.length > 0 && <ul>{formation.sourceUrls.map(url => <li key={url}><a href={url} target="_blank" rel="noreferrer">{hostname(url)}<span className="sr-only"> (nouvel onglet)</span></a></li>)}</ul>}
              {errorFor(`${prefix}.templateVersion`) && <p className="setup-error" role="alert">{errorFor(`${prefix}.templateVersion`)}</p>}
            </div>
          </Disclosure>}
          <Disclosure title={`Programme · ${formation.competencies.length} compétence${formation.competencies.length > 1 ? 's' : ''}`}
            open={formation.competencies.some((_, position) => hasError(errorFor, [`${prefix}.competencies.${position}.label`, `${prefix}.competencies.${position}.description`])) || !!errorFor(`${prefix}.competencies`)}>
            <ol className="setup-competencies">{formation.competencies.map((competence, position) => <li key={competence.key}>
              <TextField name={`${prefix}.competencies.${position}.label`} label={`Compétence ${position + 1}`} value={competence.label} error={errorFor(`${prefix}.competencies.${position}.label`)}
                onChange={label => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, label } : item) })} />
              <TextAreaField name={`${prefix}.competencies.${position}.description`} label="Description" rows={2} value={competence.description} error={errorFor(`${prefix}.competencies.${position}.description`)}
                onChange={description => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, description } : item) })} />
              <Button type="button" variant="ghost" size="sm" className="setup-start" aria-label={`Retirer cette compétence · ${competence.label || `Compétence ${position + 1}`}`}
                onClick={() => update({ ...formation, competencies: formation.competencies.filter((_, i) => i !== position).map((item, sortOrder) => ({ ...item, sortOrder })) })}>Retirer</Button>
            </li>)}</ol>
            {errorFor(`${prefix}.competencies`) && <p className="setup-error" role="alert">{errorFor(`${prefix}.competencies`)}</p>}
            <Button type="button" variant="outline" className="setup-start" disabled={formation.competencies.length >= 200}
              onClick={() => update({ ...formation, competencies: [...formation.competencies, { key: crypto.randomUUID(), label: '', description: '', sortOrder: formation.competencies.length }] })}><Plus aria-hidden="true" />Ajouter une compétence</Button>
          </Disclosure>
          <Disclosure title="Déroulement de la formation" open={!!errorFor(`${prefix}.procedureText`)}>
            <TextAreaField name={`${prefix}.procedureText`} label="Déroulement" rows={5} maxLength={4000} value={formation.procedureText} error={errorFor(`${prefix}.procedureText`)} onChange={procedureText => update({ ...formation, procedureText })} />
          </Disclosure>
        </>}
      </li>;
    })}</ul>}
  </div>;
}

function hostname(url: string) {
  try { return new URL(url).hostname; } catch { return url; }
}

/* ------------------------------------------------------------ Prix et règles */

function PriceField({ formation, onChange, name, error }: { formation: SetupFormation; onChange: (value: SetupFormation) => void; name: string; error: string | null }) {
  const [raw, setRaw] = useState(priceInput(formation.priceCents));
  return <TextField name={name} label="Prix de la leçon" suffix="CHF" value={raw} inputMode="decimal" autoComplete="off" error={raw && setupPrice(raw) === null ? priceAmountProblem : error}
    onChange={value => { setRaw(value); onChange({ ...formation, priceCents: setupPrice(value) }); }} />;
}

export function PricingStep({ content, onChange, canWrite, errorFor }: StepProps & { canWrite: boolean }) {
  const update = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) }, 'CATALOGUE', true));
  if (!canWrite) return <NoCatalogueAccess />;
  if (!content.formations.length) return <p className="setup-muted">Aucune formation à tarifer dans ce brouillon.</p>;
  return <div className="setup-step-body">
    <ul className="setup-items" aria-label="Prix des formations">{content.formations.map((formation, index) => {
      const prefix = `formations.${index}`;
      const particular = [`${prefix}.validFrom`, `${prefix}.cancellationPolicyText`, `${prefix}.termsText`, `${prefix}.useCommonTerms`];
      return <li key={formation.id} className="setup-item" data-set-aside={!formation.apply || undefined}>
        <div className="setup-item-head"><PermitCode code={formation.categoryCode} />
          <div className="setup-item-title"><h3>{formationTitle(formation, index)}</h3>{!formation.apply && <span className="setup-muted">Mise de côté</span>}</div></div>
        <div className="setup-grid">
          <TextField name={`${prefix}.durationMinutes`} label="Durée" suffix="min" inputMode="numeric" autoComplete="off" maxLength={4} error={errorFor(`${prefix}.durationMinutes`)}
            value={formation.durationMinutes === null ? '' : String(formation.durationMinutes)} onChange={value => update({ ...formation, durationMinutes: minutesValue(value) })} />
          <PriceField name={`${prefix}.priceCents`} error={errorFor(`${prefix}.priceCents`)} formation={formation} onChange={update} />
        </div>
        <Disclosure title="Date et conditions particulières" open={hasError(errorFor, particular)}>
          <div className="setup-stack">
            <TextField name={`${prefix}.validFrom`} label="Disponible dès le" type="date" className="setup-date" value={formation.validFrom ?? ''} error={errorFor(`${prefix}.validFrom`)} onChange={validFrom => update({ ...formation, validFrom: validFrom || null })} />
            {!formation.existingOfferingId && <CheckRow label="Utiliser les règles communes des leçons" checked={formation.useCommonTerms ?? false} onChange={useCommonTerms => update({ ...resolvedSetupFormation(content, formation), useCommonTerms })} />}
            {errorFor(`${prefix}.useCommonTerms`) && <p className="setup-error" role="alert">{errorFor(`${prefix}.useCommonTerms`)}</p>}
            {!formation.useCommonTerms && <>
              {!formation.existingOfferingId && <TextAreaField name={`${prefix}.cancellationPolicyText`} label="Conditions d’annulation particulières" rows={3} maxLength={4000} value={formation.cancellationPolicyText} error={errorFor(`${prefix}.cancellationPolicyText`)} onChange={cancellationPolicyText => update({ ...formation, cancellationPolicyText })} />}
              <TextAreaField name={`${prefix}.termsText`} label="Conditions particulières du tarif" rows={4} maxLength={20000} value={formation.termsText} error={errorFor(`${prefix}.termsText`)} onChange={termsText => update({ ...formation, termsText })} />
            </>}
            {formation.existingOfferingId && formation.cancellationPolicyText.trim() && <Alert><AlertTitle>Annulation déjà définie</AlertTitle>
              <AlertDescription>Le tarif conserve les règles de sa formation.</AlertDescription>
              <Button type="button" variant="outline" className="setup-start mt-3" onClick={() => update({ ...formation, cancellationPolicyText: '' })}>Conserver l’annulation de la formation</Button></Alert>}
            <CheckRow label="Inclure ce tarif dans la confirmation" checked={formation.apply} onChange={apply => update({ ...formation, apply })} />
          </div>
        </Disclosure>
      </li>;
    })}</ul>
    {content.formations.some(item => item.useCommonTerms) && <CommonLessonRulesSection content={content} onChange={onChange} errorFor={errorFor} />}
  </div>;
}

/** Questions answered once for the school; the pupil's text is generated by the API's own rules (`commonLessonTexts`). */
function CommonLessonRulesSection({ content, onChange, errorFor }: StepProps) {
  const rules: CommonLessonRules = content.commonLessonRules ?? { cancellationHours: null, lateAction: null, paymentText: '', exceptionsText: '' };
  const update = (value: Partial<CommonLessonRules>) => onChange({ ...content, commonLessonRules: { ...rules, ...value } });
  const text = commonLessonTexts(rules, content.identity.contactEmail);
  return <section className="setup-rules" aria-labelledby="setup-rules-title">
    <h3 id="setup-rules-title">Règles communes des leçons</h3>
    <PortalSelect id="setup-late-action" name="commonLessonRules.lateAction" label="En cas d’annulation" value={rules.lateAction} placeholder="Choisir la règle de l’école"
      {...(errorFor('commonLessonRules.lateAction') ? { error: errorFor('commonLessonRules.lateAction')! } : {})} onValueChange={value => update({ lateAction: value === 'CONTACT' || value === 'NO_FEE' ? value : null })}
      options={[{ value: 'CONTACT', label: 'Un délai, puis contact avec l’école' }, { value: 'NO_FEE', label: 'Annulation sans frais, sur demande à l’école' }]} />
    {rules.lateAction === 'CONTACT' && <TextField name="commonLessonRules.cancellationHours" label="Prévenir combien d’heures avant la leçon ?" suffix="h" inputMode="numeric" autoComplete="off" maxLength={4} className="setup-short"
      value={rules.cancellationHours === null ? '' : String(rules.cancellationHours)} error={errorFor('commonLessonRules.cancellationHours')}
      onChange={value => update({ cancellationHours: /^\d+$/.test(value) ? Number(value) : null })} />}
    <TextField name="commonLessonRules.paymentText" label="Quand et comment se règle la leçon ?" value={rules.paymentText} maxLength={2000} error={errorFor('commonLessonRules.paymentText')} onChange={paymentText => update({ paymentText })} />
    <Disclosure title="Exceptions de l’école" open={!!rules.exceptionsText.trim()}>
      <TextAreaField name="commonLessonRules.exceptionsText" label="Exceptions à ces règles" optional rows={3} maxLength={2000} value={rules.exceptionsText} onChange={exceptionsText => update({ exceptionsText })} />
    </Disclosure>
    <Disclosure title="Texte préparé pour l’élève"><p className="setup-copy">{text.termsText}</p></Disclosure>
  </section>;
}

/* ------------------------------------------------------------ Éditeurs ouverts depuis le résumé */

export function IdentityEditor({ content, onChange, errorFor }: StepProps) {
  const update = (value: Partial<SetupContent['identity']>) => onChange(selectSetupSection({ ...content, identity: { ...content.identity, ...value } }, 'IDENTITY', true));
  return <div className="setup-grid">
    <TextField name="identity.name" label="Nom de l’école" value={content.identity.name} maxLength={150} autoComplete="organization" error={errorFor('identity.name')} onChange={name => update({ name })} />
    <TextField name="identity.contactEmail" label="E-mail de l’école" type="email" value={content.identity.contactEmail} autoComplete="email" inputMode="email" error={errorFor('identity.contactEmail')} onChange={contactEmail => update({ contactEmail })} />
    <TextField name="identity.contactPhone" label="Téléphone" optional type="tel" value={content.identity.contactPhone ?? ''} autoComplete="tel" error={errorFor('identity.contactPhone')} onChange={contactPhone => update({ contactPhone: contactPhone || null })} />
    <TextField name="identity.timeZone" label="Fuseau horaire" value={content.identity.timeZone} autoComplete="off" spellCheck={false} error={errorFor('identity.timeZone')} onChange={timeZone => update({ timeZone })} />
  </div>;
}

export function PrivacyEditor({ content, templates, onChange, errorFor }: StepProps & { templates: SetupTemplates }) {
  const update = (value: Partial<SetupContent['privacy']>) => onChange(selectSetupSection({ ...content, privacy: { ...content.privacy, ...value } }, 'PRIVACY', true));
  const [replace, setReplace] = useState(false);
  return <div className="setup-stack">
    <TextField name="privacy.contactEmail" label="Contact pour les données" type="email" inputMode="email" value={content.privacy.contactEmail} error={errorFor('privacy.contactEmail')} onChange={contactEmail => update({ contactEmail })} />
    <TextAreaField name="privacy.noticeText" label="Information des personnes" rows={10} maxLength={20_000} value={content.privacy.noticeText} error={errorFor('privacy.noticeText')} onChange={noticeText => update({ noticeText })} />
    <TextAreaField name="privacy.retentionText" label="Conservation des données" rows={6} maxLength={20_000} value={content.privacy.retentionText} error={errorFor('privacy.retentionText')} onChange={retentionText => update({ retentionText })} />
    {errorFor('privacy.templateVersion') && <p className="setup-error" role="alert">{errorFor('privacy.templateVersion')}</p>}
    <Button type="button" variant="outline" className="setup-start" onClick={() => setReplace(true)}>Repartir de l’exemple Drivy</Button>
    <Dialog open={replace} onOpenChange={setReplace}><DialogContent>
      <DialogHeader><DialogTitle>Reprendre l’exemple ?</DialogTitle><DialogDescription>Les textes de ce brouillon seront remplacés. Les textes déjà adoptés restent inchangés.</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={() => setReplace(false)}>Garder mes textes</Button>
        <Button onClick={() => { update(templatePrivacy(templates, content)); setReplace(false); }}>Utiliser l’exemple</Button></DialogFooter>
    </DialogContent></Dialog>
  </div>;
}

/** Empty, read-only controls: the pupil's form with its exact explanations, without collecting anything. */
export function ProfilePreview({ fields }: { fields: readonly ProfileFieldRule[] }) {
  const types: Record<string, string> = { contactPhone: 'tel', contactEmail: 'email', birthDate: 'date' };
  return <div className="setup-profile-preview" aria-label="Aperçu du formulaire élève">{fields.map(field => <div key={field.field} className="setup-profile-preview-field">
    <p><strong>{profileFieldLabels[field.field] ?? field.field}</strong><span className="setup-muted">{setupProfileRequirement(field)}</span></p>
    {field.field === 'profilePhotoDocumentId' ? <div className="setup-profile-photo" role="img" aria-label="Emplacement de la photo de profil" />
      : field.field === 'postalAddress' ? <Textarea aria-label={profileFieldLabels[field.field]} rows={2} readOnly tabIndex={-1} value="" />
      : <Input aria-label={profileFieldLabels[field.field]} type={types[field.field] ?? 'text'} readOnly tabIndex={-1} value="" />}
    <p className="setup-muted">{field.explanation}</p>
  </div>)}</div>;
}

export function ProfileEditor({ content, onChange, errorFor }: StepProps) {
  const uid = useId();
  const update = (fields: SetupContent['profile']['fields']) => onChange(selectSetupSection({ ...content, profile: { ...content.profile, fields, effectiveFrom: null } }, 'PROFILE', true));
  const fieldError = content.profile.fields.some((_, index) => !!errorFor(`profile.fields.${index}.explanation`)) || !!errorFor('profile.fields');
  return <div className="setup-stack">
    {content.profile.effectiveFrom !== null && <Alert><AlertTitle>Date d’effet à actualiser</AlertTitle>
      <AlertDescription>Les informations demandées prennent désormais effet dès leur confirmation. Ce brouillon conserve encore une ancienne date.</AlertDescription>
      <Button type="button" variant="outline" className="setup-start mt-3" onClick={() => update(content.profile.fields)}>Appliquer dès la confirmation</Button></Alert>}
    <ProfilePreview fields={content.profile.fields} />
    {errorFor('profile.fields') && <p className="setup-error" role="alert">{errorFor('profile.fields')}</p>}
    <Disclosure title="Adapter les informations demandées" open={fieldError}>
      <div className="setup-profile-fields">{profileFieldDefaults.map(base => {
        const current = content.profile.fields.find(item => item.field === base.field);
        const index = current ? content.profile.fields.indexOf(current) : -1;
        const label = profileFieldLabels[base.field]!;
        if (base.field === 'firstName' || base.field === 'lastName') return <div key={base.field} className="setup-profile-fixed"><strong>{label}</strong><span className="setup-muted">À l’inscription</span></div>;
        return <fieldset key={base.field} className="setup-profile-field">
          <legend>{label}</legend>
          <RadioGroup value={profileChoiceOf(current)} onValueChange={value => update(applyProfileChoice(content.profile.fields, base, value as typeof profileChoices[number]['value']))}
            className="setup-choices" aria-label={`Demander · ${label}`}>
            {profileChoices.map(choice => <Label key={choice.value} htmlFor={`${uid}-${base.field}-${choice.value}`} className="setup-choice">
              <RadioGroupItem id={`${uid}-${base.field}-${choice.value}`} value={choice.value} />{choice.label}</Label>)}
          </RadioGroup>
          {current && <Disclosure title="Pourquoi cette information ?" open={!!errorFor(`profile.fields.${index}.explanation`)}>
            <TextAreaField name={`profile.fields.${index}.explanation`} label={`Explication · ${label}`} rows={2} maxLength={1000} value={current.explanation} error={errorFor(`profile.fields.${index}.explanation`)}
              onChange={explanation => update(content.profile.fields.map(item => item.field === base.field ? { ...item, explanation } : item))} />
          </Disclosure>}
        </fieldset>;
      })}</div>
    </Disclosure>
  </div>;
}
