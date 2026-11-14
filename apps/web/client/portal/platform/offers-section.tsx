import { useState } from 'react';
import { Layers, Plus } from 'lucide-react';
import { moduleLabel, modulesLabel, offerProblem, orderedModules, sameModules, type PlatformOffer } from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import type { PlatformConsoleState } from './use-platform-console';

type OfferFilter = 'ACTIVE' | 'ARCHIVED';
const filters: readonly { value: OfferFilter; label: string }[] = [{ value: 'ACTIVE', label: 'Actives' }, { value: 'ARCHIVED', label: 'Archivées' }];
const schoolsLabel = (count: number) => `${count} ${count > 1 ? 'écoles' : 'école'}`;

/** Offres : des ensembles nommés de modules du catalogue. Aucun montant ni essai ici (#456) ; archiver n'efface rien. */
export function OffersSection({ state }: { state: PlatformConsoleState }) {
  const { offers } = state;
  const [filter, setFilter] = useState<OfferFilter>('ACTIVE');
  const items = offers.offers.filter(offer => offer.status === filter);
  return <section className="platform-section" aria-labelledby="platform-offers-title">
    <h2 id="platform-offers-title">Offres</h2>
    <div className="platform-toolbar">
      <div className="platform-filter" role="group" aria-label="Filtrer les offres">
        {filters.map(item => <Button key={item.value} variant={filter === item.value ? 'secondary' : 'ghost'} aria-pressed={filter === item.value}
          disabled={state.busy} onClick={() => setFilter(item.value)}>{item.label}</Button>)}
      </div>
      <Button disabled={state.busy} onClick={() => offers.startOffer(null)}><Plus aria-hidden="true" data-icon="inline-start" />Créer une offre</Button>
    </div>
    {items.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><Layers aria-hidden="true" /></EmptyMedia><EmptyTitle>{filter === 'ACTIVE' ? 'Aucune offre active' : 'Aucune offre archivée'}</EmptyTitle></EmptyHeader></Empty>
      : <ul className="platform-list" aria-label="Offres">{items.map(offer => <OfferRow key={offer.id} state={state} offer={offer} />)}</ul>}
  </section>;
}

function OfferRow({ state, offer }: { state: PlatformConsoleState; offer: PlatformOffer }) {
  const { offers } = state, archived = offer.status === 'ARCHIVED';
  return <li>
    <div className="platform-summary"><strong>{offer.name}</strong>
      <span>{[modulesLabel(offer.modules), offer.schoolsInForce > 0 ? schoolsLabel(offer.schoolsInForce) : null].filter(Boolean).join(' · ')}</span></div>
    <div className="platform-actions">
      {archived
        ? <Button variant="ghost" disabled={state.busy} aria-label={`Rétablir l’offre ${offer.name}`} onClick={() => void offers.restoreOffer(offer)}>Rétablir</Button>
        : <>
          <Button variant="ghost" disabled={state.busy} aria-label={`Modifier l’offre ${offer.name}`} onClick={() => offers.startOffer(offer)}>Modifier</Button>
          <Button variant="ghost" disabled={state.busy} aria-label={`Archiver l’offre ${offer.name}`} onClick={() => void offers.archiveOffer(offer)}>Archiver</Button>
        </>}
    </div>
  </li>;
}

/** Création et modification d'une offre : un nom et les modules du catalogue. Seules les zones changées partent, sous la version lue. */
export function OfferDialog({ state }: { state: PlatformConsoleState }) {
  const { offers } = state, target = offers.editor;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) offers.stopOffer(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {target && <OfferForm key={target.offer ? `${target.offer.id}:${target.offer.version}` : 'new'} state={state} offer={target.offer} />}
    </DialogContent>
  </Dialog>;
}

function OfferForm({ state, offer }: { state: PlatformConsoleState; offer: PlatformOffer | null }) {
  const { offers } = state;
  const [name, setName] = useState(offer?.name ?? ''), [selected, setSelected] = useState<string[]>(offer?.modules ?? []);
  const [invalid, setInvalid] = useState<string | null>(null);
  const dirty = !offer || name.trim() !== offer.name || !sameModules(orderedModules(selected, offers.modules), offer.modules);
  const toggle = (code: string, checked: boolean) => { setSelected(previous => (checked ? [...previous.filter(item => item !== code), code] : previous.filter(item => item !== code))); setInvalid(null); };
  const submit = () => {
    const problem = offerProblem(name, selected);
    if (problem) { setInvalid(problem); return; }
    void offers.saveOffer({ name, modules: selected });
  };
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
    <DialogHeader><DialogTitle>{offer ? 'Modifier l’offre' : 'Créer une offre'}</DialogTitle></DialogHeader>
    <FieldGroup>
      <Field data-invalid={!!invalid}>
        <FieldLabel htmlFor="offer-name">Nom de l’offre</FieldLabel>
        <Input id="offer-name" name="name" maxLength={100} autoComplete="off" required value={name} disabled={state.busy} aria-invalid={!!invalid}
          aria-describedby={invalid ? 'offer-name-error' : undefined} onChange={event => { setName(event.target.value); setInvalid(null); }} />
        {invalid && <FieldError id="offer-name-error">{invalid}</FieldError>}
      </Field>
      <fieldset className="platform-modules"><legend>Modules</legend>
        {offers.modules.map(module => <Field key={module.code} orientation="horizontal">
          <Checkbox id={`offer-module-${module.code}`} checked={selected.includes(module.code)} disabled={state.busy} onCheckedChange={value => toggle(module.code, value === true)} />
          <FieldLabel htmlFor={`offer-module-${module.code}`}>{moduleLabel(module.code)}</FieldLabel>
        </Field>)}
      </fieldset>
    </FieldGroup>
    {state.error && <Alert variant="destructive"><AlertTitle>Offre non enregistrée</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
    <DialogFooter><Button type="button" variant="outline" disabled={state.busy} onClick={offers.stopOffer}>Annuler</Button>
      <Button type="submit" disabled={!dirty || state.busy} aria-busy={state.busy}>{state.busy ? 'Enregistrement…' : 'Enregistrer'}</Button></DialogFooter>
  </form>;
}
