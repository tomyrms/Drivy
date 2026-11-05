import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Building2, Pencil } from 'lucide-react';
import { characters, createCommand, filled, isEmail } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { readSchool, readinessSchema, schoolSchema, type School } from '../../school-api';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { useCommandRunner, useConsole, useDraft, useLoad } from '../../console/context';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import './settings.css';

type Identity = { name: string; contactEmail: string; contactPhone: string };

/** School coordinates (#330): read first, a focused editor, versioned save; time zone shown as the reference of every date. */
export function SchoolSettingsPilot() {
  const { me, schoolId, membership } = useConsole();
  return <SchoolIdentityEditor key={`${me.personId}/${schoolId}/${membership.membershipId}/${membership.accessEpoch}`} />;
}

function SchoolIdentityEditor() {
  const { schoolId, school, navigate, reloadSchool, routeQuery } = useConsole();
  const { revision, confirmations } = useCommandSnapshot();
  const runner = useCommandRunner();
  const [confirmedSchool, setConfirmedSchool] = useState<School | null>(null);
  const baseline = confirmedSchool && confirmedSchool.version >= school.version ? confirmedSchool : school;
  const request = useRef<{ operationId: string; sent: Identity; version: number } | null>(null);
  const active = useRef(true);
  useEffect(() => () => { active.current = false; }, []);
  const [readMissing, setReadMissing] = useState(false);
  const [reading, setReading] = useState(false);
  const loaded = useLoad(async () => ({ readiness: await readSchool(schoolId, 'readiness', readinessSchema) }), [schoolId, revision, school.version]);
  const identity = useDraft<Identity>({ name: baseline.name, contactEmail: baseline.contactEmail, contactPhone: baseline.contactPhone ?? '' });
  const [attempted, setAttempted] = useState(false);
  const [editing, setEditing] = useState(() => !!routeQuery?.focus?.startsWith('school-'));
  useEffect(() => { if (routeQuery?.focus?.startsWith('school-')) setEditing(true); }, [routeQuery?.focus]);
  const editButton = useRef<HTMLButtonElement>(null);
  const form = useRef<HTMLFormElement>(null);
  const focusOnEdit = useRef(false);
  useLayoutEffect(() => {
    if (!editing || !focusOnEdit.current) return;
    focusOnEdit.current = false;
    form.current?.querySelector<HTMLInputElement>('input')?.focus();
  }, [editing]);
  const mayEdit = loaded.data !== undefined && !runner.pending && !runner.busy && !readMissing && !reading;
  // Typing continues while sending; only a request still to verify closes the fields.
  const fieldsOpen = loaded.data !== undefined && (!runner.pending || runner.pending.phase === 'sending');
  const value = identity.draft;
  const latestValue = useRef(value);
  latestValue.current = value;
  const errors = value ? {
    name: filled(value.name, 150) ? null : 'Indiquez le nom de l’école (150 caractères au plus).',
    contactEmail: isEmail(value.contactEmail.trim()) ? null : 'Indiquez une adresse e-mail valide.',
    contactPhone: characters(value.contactPhone) <= 32 ? null : '32 caractères au plus.',
  } : null;
  const valid = !!errors && Object.values(errors).every(error => error === null);

  function adopt(confirmed: School, sent: Identity) {
    if (!active.current) return;
    setConfirmedSchool(confirmed);
    identity.markSaved({ name: confirmed.name, contactEmail: confirmed.contactEmail, contactPhone: confirmed.contactPhone ?? '' }, sent);
    request.current = null; setReadMissing(false); setAttempted(false);
    if (JSON.stringify(latestValue.current) === JSON.stringify(sent)) {
      setEditing(false); requestAnimationFrame(() => editButton.current?.focus());
    }
  }
  async function reread() {
    const pending = request.current;
    if (!pending || reading) return;
    setReading(true); setReadMissing(true);
    try {
      const confirmed = await readSchool(schoolId, '', schoolSchema);
      if (confirmed.schoolId !== schoolId || confirmed.id !== schoolId || confirmed.version <= pending.version) throw new Error('Invalid school');
      adopt(confirmed, pending.sent);
    } catch { /* The receipt proves the write, never the missing resource body. */ }
    finally { if (active.current) setReading(false); }
  }
  useEffect(() => {
    if (!runner.busy && request.current && confirmations.some(item => item.operationId === request.current?.operationId) && !readMissing && !reading) void reread();
  }, [confirmations, runner.busy]);

  async function save() {
    setAttempted(true);
    if (!valid || !value) { requestAnimationFrame(() => form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()); return; }
    if (!mayEdit || !identity.edited) return;
    const normalized = { name: value.name.trim(), contactEmail: value.contactEmail.trim(), contactPhone: value.contactPhone.trim() };
    const sent = value;
    const command = createCommand({ schoolId, kind: 'updateSchool', path: '', ifMatch: baseline.version, resourceVersion: baseline.version,
      body: { ...normalized, contactPhone: normalized.contactPhone || null, timeZone: baseline.timeZone, impactConfirmed: true } });
    request.current = { operationId: command.operationId, sent, version: baseline.version };
    const result = await runner.run(command, 'Les coordonnées de l’école sont enregistrées.');
    if (!active.current) return;
    if (result.status === 'confirmed') {
      const parsed = schoolSchema.safeParse((result.body as { data?: unknown } | null)?.data);
      if (parsed.success && parsed.data.schoolId === schoolId && parsed.data.id === schoolId && parsed.data.version > baseline.version) adopt(parsed.data, sent);
      else await reread();
    } else if (result.status === 'rejected') request.current = null;
  }
  const close = () => { identity.reset(); setAttempted(false); setEditing(false); requestAnimationFrame(() => editButton.current?.focus()); };
  const error = (key: keyof Identity) => attempted ? errors?.[key] ?? null : null;

  return <section className="settings-page">
    <header className="settings-heading"><h1>École</h1>
      {school.status !== 'ACTIVE' && <Badge variant="outline">{school.status === 'DRAFT' ? 'En préparation' : 'École inactive'}</Badge>}</header>
    <CommandFeedback runner={runner} showSuccess={!identity.edited && !identity.conflicts.length && !readMissing && !reading} />
    {readMissing && <Alert><AlertTitle>Envoi confirmé, coordonnées à relire</AlertTitle><AlertDescription>Votre saisie est conservée. Relisez les coordonnées avant un nouvel enregistrement.</AlertDescription>
      <Button variant="outline" disabled={reading} onClick={() => void reread()}>{reading ? 'Relecture…' : 'Relire les coordonnées'}</Button></Alert>}
    {!!identity.conflicts.length && <Alert><AlertTitle>Modifications à concilier</AlertTitle><AlertDescription>La réponse de l’école diffère de votre saisie : {identity.conflicts.map(path => ({ name: 'nom', contactEmail: 'e-mail', contactPhone: 'téléphone' })[path] ?? path).join(', ')}. Votre saisie est conservée. Vérifiez-la puis enregistrez, ou reprenez les coordonnées confirmées.</AlertDescription>
      <Button variant="outline" disabled={!mayEdit} onClick={() => { identity.reset(); requestAnimationFrame(() => form.current?.querySelector<HTMLInputElement>('input')?.focus()); }}>Reprendre les coordonnées confirmées</Button></Alert>}
    {runner.outcome?.code === 'VERSION_CONFLICT' && <Button variant="outline" className="justify-self-start" onClick={() => { loaded.reload(); void reloadSchool(); }}>Recharger les informations</Button>}
    <ReadFeedback loaded={loaded} label="Vérification de l’école" />
    {loaded.data && <section className="settings-card" aria-labelledby="school-identity-title">
      <header className="settings-card-heading"><h2 id="school-identity-title">Coordonnées</h2>
        {!editing && <Button variant="outline" ref={editButton} disabled={!mayEdit} onClick={() => { focusOnEdit.current = true; setEditing(true); }}><Pencil aria-hidden="true" />Modifier</Button>}</header>
      {!editing && <dl className="settings-values">
        <div><dt>Nom de l’école</dt><dd className="settings-school-name"><Building2 aria-hidden="true" />{value?.name ?? school.name}</dd></div>
        <div><dt>E-mail de l’école</dt><dd>{value?.contactEmail ?? school.contactEmail}</dd></div>
        <div><dt>Téléphone</dt><dd>{(value?.contactPhone ?? school.contactPhone) || <span className="settings-muted">Non renseigné</span>}</dd></div>
        <div><dt>Fuseau horaire</dt><dd>{school.timeZone}</dd></div>
      </dl>}
      {editing && value && <form ref={form} noValidate onSubmit={event => { event.preventDefault(); void save(); }} className="settings-form">
        <FieldGroup>
          <Field data-invalid={!!error('name') || undefined}><FieldLabel htmlFor="school-name">Nom de l’école</FieldLabel>
            <Input id="school-name" value={value.name} onChange={event => identity.setDraft({ ...value, name: event.target.value })} disabled={!fieldsOpen} autoComplete="organization" maxLength={150} aria-invalid={!!error('name')} />
            {error('name') && <FieldError>{error('name')}</FieldError>}</Field>
          <Field data-invalid={!!error('contactEmail') || undefined}><FieldLabel htmlFor="school-email">E-mail de l’école</FieldLabel>
            <Input id="school-email" type="email" value={value.contactEmail} onChange={event => identity.setDraft({ ...value, contactEmail: event.target.value })} disabled={!fieldsOpen} autoComplete="email" aria-invalid={!!error('contactEmail')} />
            {error('contactEmail') && <FieldError>{error('contactEmail')}</FieldError>}</Field>
          <Field data-invalid={!!error('contactPhone') || undefined}><FieldLabel htmlFor="school-phone">Téléphone <span className="settings-muted">(facultatif)</span></FieldLabel>
            <Input id="school-phone" type="tel" value={value.contactPhone} onChange={event => identity.setDraft({ ...value, contactPhone: event.target.value })} disabled={!fieldsOpen} autoComplete="tel" maxLength={32} aria-invalid={!!error('contactPhone')} />
            {error('contactPhone') && <FieldError>{error('contactPhone')}</FieldError>}</Field>
        </FieldGroup>
        <p className="settings-readonly"><span>Fuseau horaire</span><strong>{school.timeZone}</strong></p>
        <div className="settings-form-actions">
          <Button type="button" variant="outline" disabled={runner.busy} onClick={close}>Annuler</Button>
          <Button type="submit" disabled={!mayEdit || !identity.edited} aria-busy={runner.busy}>{runner.busy ? 'Enregistrement…' : 'Enregistrer'}</Button>
        </div>
      </form>}
    </section>}
    {school.status === 'DRAFT' && <section className="settings-card" aria-labelledby="school-preparation-title">
      <header className="settings-card-heading"><h2 id="school-preparation-title">Préparation</h2><Button variant="outline" onClick={() => navigate('apercu')}>Continuer la préparation</Button></header>
    </section>}
  </section>;
}
