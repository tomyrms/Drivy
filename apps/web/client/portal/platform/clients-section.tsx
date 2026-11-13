import { useState, type ChangeEvent, type ComponentProps } from 'react';
import { ArrowLeft, ChevronRight, Copy, Link2, Plus, School, Search } from 'lucide-react';
import {
  clientTitle, codeStateLabel, ficheChanges, ficheDraftOf, ficheProblem, linkSourceLabel, openingCodeValidities, preparationLabel, schoolStatusLabel, setupProgress,
  type FicheDraft, type FicheField, type PlatformClient, type PlatformClientCode, type PlatformClientDetail,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { PortalSelect } from '../components/portal-select';
import type { ClientFilter } from './use-platform-clients';
import type { PlatformConsoleState } from './use-platform-console';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
const day = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium' }).format(new Date(value));
const validityOptions = openingCodeValidities.map(days => ({ value: String(days), label: days === 1 ? '1 jour' : `${days} jours` }));
const filters: readonly { value: ClientFilter; label: string }[] = [
  { value: 'ALL', label: 'Toutes' }, { value: 'AWAITING_SCHOOL', label: 'En attente' }, { value: 'IN_PREPARATION', label: 'En préparation' },
  { value: 'ACTIVE', label: 'Actives' }, { value: 'ARCHIVED', label: 'Archivées' },
];

/** Écoles clientes : l'annuaire, puis la fiche d'une école. Le code d'ouverture se crée d'ici, sans autre saisie que le nom. */
export function ClientsSection({ state }: { state: PlatformConsoleState }) {
  const selected = state.clients.selected;
  return <section className="platform-section" aria-labelledby="platform-clients-title">
    <h2 id="platform-clients-title">Écoles</h2>
    {selected ? <ClientFiche state={state} client={selected} /> : <ClientDirectory state={state} />}
  </section>;
}

/** Ce que l'opérateur lit d'un coup d'œil : l'état de préparation et, au besoin, ce qui bloque (un code expiré ou révoqué). */
function clientLine(client: PlatformClient): string {
  const parts: string[] = [preparationLabel(client.preparation)];
  if (client.school && client.preparation === 'IN_PREPARATION') parts.push(setupProgress(client.school.setup));
  if (!client.schoolId && client.latestCode?.state === 'AVAILABLE') parts.push(`code valable jusqu’au ${day(client.latestCode.expiresAt)}`);
  return parts.join(' · ');
}
const contactLine = (client: PlatformClient) => [client.contactName, client.contactEmail ?? client.school?.contactEmail].filter(Boolean).join(' · ');
function unusualCode(client: PlatformClient): string | null {
  const state = client.latestCode?.state;
  if (client.schoolId || (state !== 'EXPIRED' && state !== 'REVOKED')) return null;
  return state === 'EXPIRED' ? 'Code expiré' : 'Code révoqué';
}

function ClientDirectory({ state }: { state: PlatformConsoleState }) {
  const { clients } = state;
  const [text, setText] = useState(clients.search);
  const searching = clients.search !== '' || clients.preparation !== 'ALL';
  const items = clients.page.items;
  return <>
    <div className="platform-toolbar">
      <form className="platform-search" role="search" onSubmit={event => { event.preventDefault(); void clients.searchClients(text); }}>
        <Input type="search" name="q" aria-label="Rechercher une école" placeholder="Rechercher une école" autoComplete="off" maxLength={100} value={text} onChange={event => setText(event.target.value)} />
        <Button type="submit" variant="outline" disabled={state.busy}><Search aria-hidden="true" data-icon="inline-start" />Rechercher</Button>
      </form>
      <div className="platform-actions">
        <Button disabled={state.busy} onClick={() => clients.startCode({ clientId: null, clientName: null })}><Plus aria-hidden="true" data-icon="inline-start" />Créer un code</Button>
        <Button variant="outline" disabled={state.busy} onClick={() => void clients.startAttach(null)}>Rattacher une école</Button>
      </div>
    </div>
    <div className="platform-filter" role="group" aria-label="Filtrer par état">
      {filters.map(filter => <Button key={filter.value} variant={clients.preparation === filter.value ? 'secondary' : 'ghost'} aria-pressed={clients.preparation === filter.value}
        disabled={state.busy} onClick={() => void clients.searchClients(text, filter.value)}>{filter.label}</Button>)}
    </div>
    {clients.pending && <div className="platform-pending" role="group" aria-labelledby="platform-code-pending-title">
      <div className="platform-summary"><strong id="platform-code-pending-title">Code non transmis</strong>
        <span>{clients.pending.displayName ?? items.find(item => item.id === clients.pending?.clientId)?.displayName ?? ''}</span></div>
      <div className="platform-actions"><Button variant="outline" disabled={state.busy} onClick={() => void clients.resumeCode()}>Afficher le code</Button>
        <Button variant="ghost" disabled={state.busy} onClick={() => void clients.closeCode()}>Fermer</Button></div>
    </div>}
    {items.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><School aria-hidden="true" /></EmptyMedia><EmptyTitle>{searching ? 'Aucune école trouvée' : 'Aucune école cliente'}</EmptyTitle></EmptyHeader></Empty>
      : <ul className="platform-list" aria-label="Écoles clientes">{items.map(client => {
        const unusual = unusualCode(client), contact = contactLine(client);
        return <li key={client.id}>
          <button type="button" className="platform-client" disabled={state.busy} onClick={() => void clients.openClient(client.id)}>
            <span className="platform-summary">
              <strong>{clientTitle(client)}{unusual && <Badge variant="outline">{unusual}</Badge>}</strong>
              <span>{clientLine(client)}</span>
              {contact && <span>{contact}</span>}
            </span>
            <ChevronRight aria-hidden="true" />
          </button>
        </li>;
      })}</ul>}
    {clients.page.total !== null && items.length > 0 && <p className="platform-count" role="status">{items.length} sur {clients.page.total} {clients.page.total > 1 ? 'écoles' : 'école'}</p>}
    {clients.page.nextCursor && <Button variant="outline" disabled={state.busy} onClick={() => void clients.moreClients()}>Afficher plus</Button>}
  </>;
}

function ClientFiche({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const { clients } = state;
  const hasAvailableCode = client.codes.some(code => code.state === 'AVAILABLE');
  const open = !client.schoolId && !hasAvailableCode;
  return <div className="platform-fiche">
    <Button variant="ghost" className="platform-back" disabled={state.busy} onClick={clients.closeClient}><ArrowLeft aria-hidden="true" data-icon="inline-start" />Écoles</Button>
    <header className="platform-fiche-head">
      <div className="platform-summary"><h3>{clientTitle(client)}</h3><span>{preparationLabel(client.preparation)}</span></div>
      {open && <div className="platform-actions">
        <Button disabled={state.busy} onClick={() => clients.startCode({ clientId: client.id, clientName: clientTitle(client) })}><Plus aria-hidden="true" data-icon="inline-start" />Créer un code</Button>
        <Button variant="outline" disabled={state.busy} onClick={() => void clients.startAttach(client)}>Rattacher une école</Button>
      </div>}
    </header>
    <ClientFacts client={client} />
    <FicheForm key={`${client.id}:${client.version}`} state={state} client={client} />
    {client.codes.length > 0 && <div className="platform-group">
      <h4 className="platform-subtitle">Codes d’ouverture</h4>
      <ul className="platform-list">{client.codes.map(code => <CodeRow key={code.id} state={state} code={code} />)}</ul>
    </div>}
  </div>;
}

/** L'école, son contact et sa progression : ce que l'opérateur a le droit de lire, et rien du contenu pédagogique. */
function ClientFacts({ client }: { client: PlatformClientDetail }) {
  const school = client.school;
  const rows: [string, string][] = [];
  if (school) {
    rows.push(['École', `${school.name} · ${schoolStatusLabel(school.status)}`]);
    const contact = [school.contactEmail, school.contactPhone].filter(Boolean).join(' · ');
    if (contact) rows.push(['Contact de l’école', contact]);
    rows.push(['Préparation', `${setupProgress(school.setup)}${school.setup.savedAt ? ` · enregistrée le ${day(school.setup.savedAt)}` : ''}`]);
  }
  if (client.link) rows.push(['Ouverture', `${linkSourceLabel(client.link.source)} le ${day(client.link.linkedAt)}${client.link.issuedByName ? ` · code de ${client.link.issuedByName}` : ''}`]);
  // Emplacements réservés aux offres et aux échéances : rien n'y est inventé tant qu'aucun lot ne les renseigne.
  rows.push(['Offre', client.commercial.offer == null ? 'Non configurée' : 'Configurée']);
  rows.push(['Échéances', client.commercial.dueDates.length === 0 ? 'Aucune' : String(client.commercial.dueDates.length)]);
  return <dl className="platform-facts">{rows.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>;
}

function codeLine(code: PlatformClientCode): string {
  const by = code.issuedByName ? ` · par ${code.issuedByName}` : '';
  switch (code.state) {
    case 'AVAILABLE': return `Créé le ${day(code.createdAt)} · expire le ${dateTime(code.expiresAt)}${by}`;
    case 'USED': return `${code.usedAt ? `Utilisé le ${day(code.usedAt)}` : 'Utilisé'}${code.school ? ` · ${code.school.name}` : ''}${by}`;
    case 'EXPIRED': return `Expiré le ${day(code.expiresAt)}${by}`;
    default: return `${code.revokedAt ? `Révoqué le ${day(code.revokedAt)}` : 'Révoqué'}${by}`;
  }
}
function CodeRow({ state, code }: { state: PlatformConsoleState; code: PlatformClientCode }) {
  return <li>
    <div className="platform-summary"><strong>{codeStateLabel(code.state)}</strong><span>{codeLine(code)}</span></div>
    {code.state === 'AVAILABLE' && <Button variant="ghost" disabled={state.busy} aria-label={`Révoquer le code créé le ${day(code.createdAt)}`} onClick={() => void state.clients.revokeCode(code)}>Révoquer</Button>}
  </li>;
}

type TextFieldProps = { id: string; label: string; value: string; error?: string | undefined; onValue: (value: string) => void } & Omit<ComponentProps<typeof Input>, 'id' | 'value' | 'onChange'>;
function TextField({ id, label, value, error, onValue, ...input }: TextFieldProps) {
  return <Field data-invalid={!!error}>
    <FieldLabel htmlFor={id}>{label}</FieldLabel>
    <Input id={id} value={value} aria-invalid={!!error} aria-describedby={error ? `${id}-error` : undefined} onChange={(event: ChangeEvent<HTMLInputElement>) => onValue(event.target.value)} {...input} />
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}

/** La fiche se modifie d'un bloc : seules les zones changées partent, sous la version lue. Aucune saisie n'est obligatoire. */
function FicheForm({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail }) {
  const [draft, setDraft] = useState<FicheDraft>(() => ficheDraftOf(client));
  const [invalid, setInvalid] = useState<{ field: FicheField; message: string } | null>(null);
  const dirty = Object.keys(ficheChanges(client, draft)).length > 0;
  const bind = (field: FicheField) => ({ value: draft[field], error: invalid?.field === field ? invalid.message : undefined,
    onValue: (value: string) => { setDraft(previous => ({ ...previous, [field]: value })); setInvalid(null); } });
  const submit = () => {
    const problem = ficheProblem(draft);
    if (problem) { setInvalid(problem); return; }
    void state.clients.saveFiche(client, draft);
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <FieldGroup>
      <TextField id="client-name" label="Nom de l’école cliente" name="displayName" maxLength={150} autoComplete="off" {...bind('displayName')} />
      <div className="platform-grid">
        <TextField id="client-contact" label="Contact commercial" name="contactName" maxLength={200} autoComplete="off" {...bind('contactName')} />
        <TextField id="client-email" label="E-mail du contact" name="contactEmail" type="email" maxLength={254} autoComplete="off" {...bind('contactEmail')} />
        <TextField id="client-phone" label="Téléphone du contact" name="contactPhone" type="tel" maxLength={32} autoComplete="off" {...bind('contactPhone')} />
      </div>
      <fieldset className="platform-address"><legend>Adresse de facturation</legend>
        <TextField id="client-street" label="Rue" name="billingStreet" maxLength={200} autoComplete="off" {...bind('billingStreet')} />
        <div className="platform-grid">
          <TextField id="client-postal" label="Code postal" name="billingPostalCode" maxLength={20} autoComplete="off" {...bind('billingPostalCode')} />
          <TextField id="client-city" label="Localité" name="billingCity" maxLength={100} autoComplete="off" {...bind('billingCity')} />
          <TextField id="client-country" label="Pays" name="billingCountry" maxLength={100} autoComplete="off" {...bind('billingCountry')} />
        </div>
      </fieldset>
      <Field data-invalid={invalid?.field === 'internalNotes'}>
        <FieldLabel htmlFor="client-notes">Notes internes</FieldLabel>
        <Textarea id="client-notes" name="internalNotes" rows={3} maxLength={4000} value={draft.internalNotes} aria-invalid={invalid?.field === 'internalNotes'}
          onChange={event => { setDraft(previous => ({ ...previous, internalNotes: event.target.value })); setInvalid(null); }} />
        {invalid?.field === 'internalNotes' && <FieldError>{invalid.message}</FieldError>}
      </Field>
    </FieldGroup>
    <div className="platform-actions"><Button type="submit" disabled={!dirty || state.busy} aria-busy={state.busy}>{state.busy ? 'Enregistrement…' : 'Enregistrer'}</Button></div>
  </form>;
}

/** « Créer un code » : le nom de l'école cliente et une validité suffisent ; le code est montré une fois, avec son lien. */
export function CodeDialog({ state }: { state: PlatformConsoleState }) {
  const { clients } = state, target = clients.codeTarget;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) clients.stopCode(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {target && (clients.issued ? <IssuedCode state={state} /> : <CodeForm state={state} clientId={target.clientId} clientName={target.clientName} />)}
    </DialogContent>
  </Dialog>;
}

function CodeForm({ state, clientId, clientName }: { state: PlatformConsoleState; clientId: string | null; clientName: string | null }) {
  const { clients } = state;
  const [name, setName] = useState(''), [validity, setValidity] = useState<string | null>('7'), [invalid, setInvalid] = useState<string | null>(null);
  const locked = state.busy || clients.uncertain;
  const submit = () => {
    const value = name.trim();
    if (!clients.uncertain && !clientId && !value) { setInvalid('Saisissez le nom de l’école.'); return; }
    setInvalid(null);
    void clients.issueCode({ ...(clientId ? { clientId } : { displayName: value }), validityDays: Number(validity ?? '7') });
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>Créer un code</DialogTitle>{clientName && <DialogDescription>{clientName}</DialogDescription>}</DialogHeader>
    <FieldGroup>
      {!clientId && <TextField id="code-school-name" label="Nom de l’école" name="displayName" maxLength={150} autoComplete="off" required value={name} disabled={locked}
        error={invalid ?? undefined} onValue={value => { setName(value); setInvalid(null); }} />}
      <PortalSelect id="code-validity" label="Validité" options={validityOptions} value={validity} disabled={locked} onValueChange={setValidity} />
    </FieldGroup>
    {clients.uncertain && <Alert><AlertTitle>Code non confirmé</AlertTitle><AlertDescription>Les informations envoyées sont conservées pour renvoyer cette même demande.</AlertDescription></Alert>}
    {state.error && !clients.uncertain && <Alert variant="destructive"><AlertTitle>Code non créé</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={clients.stopCode}>Annuler</Button>
      <Button type="submit" disabled={state.busy} aria-busy={state.busy}>{state.busy ? 'Création…' : clients.uncertain ? 'Renvoyer la même demande' : 'Créer le code'}</Button></DialogFooter>
  </form>;
}

function IssuedCode({ state }: { state: PlatformConsoleState }) {
  const { clients } = state, issued = clients.issued;
  if (!issued) return null;
  const code = issued.data.client.codes.find(item => item.id === issued.data.codeId);
  return <div className="platform-issued-dialog">
    <DialogHeader><DialogTitle>Code à transmettre</DialogTitle>
      <DialogDescription>{clientTitle(issued.data.client)}{code ? ` · expire le ${dateTime(code.expiresAt)}` : ''}</DialogDescription></DialogHeader>
    <Field><FieldLabel htmlFor="opening-code">Code d’ouverture</FieldLabel>
      <div className="platform-copy"><Input id="opening-code" className="platform-code" value={issued.code} readOnly autoComplete="off" spellCheck={false} onFocus={event => event.target.select()} />
        <Button variant="outline" onClick={() => void clients.copy('code')}><Copy aria-hidden="true" data-icon="inline-start" />Copier le code</Button></div></Field>
    {issued.link && <Field><FieldLabel htmlFor="opening-link">Lien d’ouverture</FieldLabel>
      <div className="platform-copy"><Input id="opening-link" value={issued.link} readOnly autoComplete="off" spellCheck={false} onFocus={event => event.target.select()} />
        <Button variant="outline" onClick={() => void clients.copy('link')}><Link2 aria-hidden="true" data-icon="inline-start" />Copier le lien</Button></div></Field>}
    <p className="platform-copied" role="status">{clients.copied === 'code' ? 'Code copié.' : clients.copied === 'link' ? 'Lien copié.' : ''}</p>
    {clients.copyFailed && <Alert variant="destructive"><AlertTitle>Copie impossible</AlertTitle><AlertDescription>Sélectionnez et copiez le texte affiché.</AlertDescription></Alert>}
    {state.error && <Alert variant="destructive"><AlertTitle>Action impossible</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button disabled={state.busy} onClick={() => void clients.closeCode()}>J’ai transmis le code</Button></DialogFooter>
  </div>;
}

/** Rattacher une école déjà ouverte (pilote) à une fiche : elle garde ses accès et ses données, rien n'est recréé ni facturé. */
export function AttachDialog({ state }: { state: PlatformConsoleState }) {
  const { clients } = state, target = clients.attach;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) clients.stopAttach(); }}>
    <DialogContent showCloseButton={!state.busy}>{target && <AttachBody state={state} client={target.client} />}</DialogContent>
  </Dialog>;
}

function AttachBody({ state, client }: { state: PlatformConsoleState; client: PlatformClientDetail | null }) {
  const { clients } = state;
  const [text, setText] = useState('');
  return <>
    <DialogHeader><DialogTitle>Rattacher une école existante</DialogTitle>{client && <DialogDescription>{clientTitle(client)}</DialogDescription>}</DialogHeader>
    <form className="platform-search" role="search" onSubmit={event => { event.preventDefault(); void clients.searchUnattached(text); }}>
      <Input type="search" name="q" aria-label="Rechercher une école existante" placeholder="Rechercher une école" autoComplete="off" maxLength={100} value={text} onChange={event => setText(event.target.value)} />
      <Button type="submit" variant="outline" disabled={state.busy}><Search aria-hidden="true" data-icon="inline-start" />Rechercher</Button>
    </form>
    {state.error && <Alert variant="destructive"><AlertTitle>Rattachement non confirmé</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    {clients.unattached.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><School aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucune école à rattacher</EmptyTitle></EmptyHeader></Empty>
      : <ul className="platform-list platform-dialog-list">{clients.unattached.map(school => <li key={school.id}>
        <div className="platform-summary"><strong>{school.name}</strong>
          <span>{[schoolStatusLabel(school.status), setupProgress(school.setup), school.contactEmail].filter(Boolean).join(' · ')}</span></div>
        <Button variant="outline" disabled={state.busy} aria-label={`Rattacher ${school.name}`} onClick={() => void clients.attachSchool(school)}>Rattacher</Button>
      </li>)}</ul>}
  </>;
}
