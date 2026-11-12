import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Check, RotateCcw } from 'lucide-react';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { ConsoleContext, useCommandRunner, useConsole, useLoad, useSectionDraft } from '../../console/context';
import {
  applyCandidate, baselineOf, canResetPresentation, isPreferenceDirty, learningResetCopy, preferenceBody, preferenceProblem, preferenceRefusal,
  presentationResetCopy, previewKeys, refusalNotice, schoolOfReturn, usableDraft, type PreferenceDraft, type PreferenceRefusal,
} from '../../console/observation-preferences-model';
import { readObservationPreferences, type ObservationPreferences } from '../../school-api';
import { BrandSymbol } from '../../BrandSymbol';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Label } from '../../components/ui/label';
import { RadioGroup, RadioGroupItem } from '../../components/ui/radio-group';
import { Skeleton } from '../../components/ui/skeleton';
import { Switch } from '../../components/ui/switch';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import { PortalPendingRequests } from '../runtime/pending-requests';
import { previewStartsOpen, SignalsPreview, SortableThemes } from '../signals/signals-parts';
import { preferencesReturn } from './preferences-page';
import { usePersonalScope } from './personal-scope';
import '../portal.css';
import './account.css';
import '../signals/signals.css';

type Action = 'save' | 'presentation' | 'learning';

/**
 * Mon compte, Préférences, Signalements (R08) : l'ordre, l'affichage et le classement des signalements DE MON COMPTE, dans le cadre
 * d'une école. Moniteurs et administrateurs ; absent pour un compte d'élève seul. La référence de l'école, elle, se règle dans la gestion.
 */
export function PortalSignalsPreferencesPage() {
  const search = window.location.search;
  const back = preferencesReturn(search);
  const requestedSchool = new URLSearchParams(search).get('school') ?? schoolOfReturn(back);
  const scope = usePersonalScope(requestedSchool);
  const { state, context } = scope;
  const uid = useId();
  useEffect(() => { document.title = 'Signalements · Préférences personnelles · Drivy'; }, []);
  // The address always names the school on screen, so a reload or a shared link opens the same one.
  const shown = state.status === 'ready' ? state.membership.schoolId : null;
  useEffect(() => {
    if (!shown) return;
    const params = new URLSearchParams(window.location.search);
    if (params.get('school') === shown) return;
    params.set('school', shown);
    window.history.replaceState(window.history.state, '', `${window.location.pathname}?${params.toString()}`);
  }, [shown]);

  const preferences = `/app/preferences${back === '/app/' ? '' : `?returnTo=${encodeURIComponent(back)}`}`;
  return <div className="portal-app">
    <a className="portal-skip-link" href="#portal-content">Aller au contenu</a>
    <header className="portal-topbar"><a className="portal-brand" href="/app/" aria-label="Drivy, mon compte"><BrandSymbol /><span>Drivy</span></a></header>
    <main id="portal-content" tabIndex={-1} className="account-page">
      <Button variant="ghost" size="sm" className="account-back" onClick={() => scope.proceed(() => window.location.assign(preferences))}>
        <ArrowLeft aria-hidden="true" />Préférences personnelles
      </Button>

      {state.status === 'loading' && <div className="grid gap-3" role="status" aria-label="Ouverture de vos préférences"><Skeleton className="h-10 w-56" /><Skeleton className="h-64 w-full" /></div>}
      {state.status === 'signin' && <section className="account-section">
        <h1>Connexion requise</h1>
        <Button onClick={() => window.location.assign('/app/')}>Se connecter</Button>
      </section>}
      {state.status === 'error' && <Alert variant="destructive"><AlertTitle>Vos préférences ne peuvent pas s’ouvrir</AlertTitle><AlertDescription>{state.message}</AlertDescription>
        <div className="mt-3"><Button variant="outline" onClick={() => void scope.load(requestedSchool)}>Réessayer</Button></div></Alert>}
      {state.status === 'none' && <section className="account-section">
        <h1>Signalements</h1>
        <p className="account-muted">Aucun signalement à régler avec ce compte.</p>
      </section>}

      {state.status === 'ready' && context && <ConsoleContext.Provider value={context}>
        {state.eligible.length > 1 && <div className="account-section">
          <Label htmlFor={`${uid}-school`}>École</Label>
          <select id={`${uid}-school`} className="signals-school-select" value={state.membership.schoolId} onChange={event => scope.select(event.target.value)}>
            {state.eligible.map(member => <option key={member.schoolId} value={member.schoolId}>{member.schoolName}</option>)}
          </select>
        </div>}
        <PortalPendingRequests />
        <PersonalSignals key={`${state.me.personId}/${state.membership.schoolId}/${state.membership.membershipId}/${state.membership.accessEpoch}`} />
      </ConsoleContext.Provider>}

      {scope.departure && <Dialog open onOpenChange={open => { if (!open) scope.setDeparture(null); }}><DialogContent>
        <DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Vos modifications ne sont pas enregistrées.</DialogDescription></DialogHeader>
        <DialogFooter><Button variant="outline" onClick={() => scope.setDeparture(null)}>Continuer la saisie</Button>
          <Button onClick={() => { const next = scope.departure; scope.setDeparture(null); scope.unsaved.current.clear(); next?.proceed(); }}>Quitter la page</Button></DialogFooter>
      </DialogContent></Dialog>}
    </main>
  </div>;
}

function PersonalSignals() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readObservationPreferences(schoolId), [schoolId, revision]);
  return <section className="signals-page">
    {loaded.status === 'ready' && loaded.data ? <PersonalEditor data={loaded.data} reload={loaded.reload} /> : <>
      <header className="signals-heading"><h1>Signalements</h1></header>
      <ReadFeedback loaded={loaded} label="Lecture de vos signalements" />
    </>}
  </section>;
}

export function PersonalEditor({ data, reload }: { data: ObservationPreferences; reload: () => void }) {
  const { schoolId, me, membership, school } = useConsole();
  const uid = useId();
  const lastAction = useRef<Action>('save');
  const [done, setDone] = useState<Action | null>(null);
  const runner = useCommandRunner(() => setDone(lastAction.current));
  const [previewOpen, setPreviewOpen] = useState(previewStartsOpen);
  const [notice, setNotice] = useState<Exclude<PreferenceRefusal, null> | null>(null);
  const [announcement, setAnnouncement] = useState('');
  const [confirm, setConfirm] = useState<'presentation' | 'learning' | null>(null);
  const [adopted, setAdopted] = useState('own');

  const baseline = useMemo(() => baselineOf(data), [data]);
  const [draft, setDraft] = useSectionDraft<PreferenceDraft>('observation-preferences', candidate =>
    done === null && usableDraft(candidate, data) !== null && isPreferenceDirty(candidate, baseline));
  const usable = usableDraft(draft, data);
  const current = usable ?? baseline;
  const dirty = isPreferenceDirty(current, baseline);
  const administrator = membership.roles.includes('ADMIN');
  const visibilityEditable = baseline.visibilityEditable;
  const editable = notice !== 'access' && !runner.pending && !runner.busy;
  const problem = preferenceProblem(current, baseline);

  // A draft made for another version of the account, or under another school policy, is never replayed over the current state.
  useEffect(() => {
    if (draft === null || usable !== null) return;
    if (done === null) setNotice(draft.visibilityEditable !== data.personalizationAllowed ? 'policy' : 'conflict');
    setDraft(null);
  }, [draft, usable, data.personalizationAllowed]);

  function edit(next: PreferenceDraft, message: string) {
    setDone(null); setNotice(null); runner.clearOutcome();
    setDraft(next);
    if (message) setAnnouncement(message);
  }
  const editRows = (rows: PreferenceDraft['rows'], message: string) => edit({ ...current, rows }, message);

  /** What the server said when it refused: reread its state, drop the draft, never claim anything was saved. */
  function refused(code: string): boolean {
    const refusal = preferenceRefusal(code);
    if (!refusal) return false;
    runner.clearOutcome(); setNotice(refusal); setDraft(null); setAdopted('own'); reload();
    return true;
  }

  async function submit(action: Action, command: ReturnType<typeof createCommand>, success: string) {
    lastAction.current = action;
    setDone(null); setNotice(null); runner.clearOutcome();
    const result = await runner.run(command, success);
    if (result.status === 'confirmed') { setDone(action); return; }
    if (result.status === 'rejected') refused(result.code);
  }
  const command = (kind: 'saveObservationPreferences' | 'resetObservationPresentation' | 'resetObservationLearning', path: string, body: Record<string, unknown>) =>
    createCommand({ schoolId, kind, path, ifMatch: data.version, resourceVersion: data.version, resourceId: me.personId, body });

  async function save() {
    if (!editable || !dirty || done === 'save' || problem) return;
    await submit('save', command('saveObservationPreferences', 'observation-preferences', preferenceBody(current, baseline)), 'Vos signalements sont enregistrés.');
  }
  async function confirmed(kind: 'presentation' | 'learning') {
    setConfirm(null);
    if (!editable) return;
    // The reset starts again from the server's state: whatever was being edited is given up, as announced.
    setDraft(null); setAdopted('own');
    await submit(kind, kind === 'presentation'
      ? command('resetObservationPresentation', 'observation-preferences/presentation-reset', {})
      : command('resetObservationLearning', 'observation-preferences/learning-reset', {}),
    kind === 'presentation' ? `Votre ordre et votre affichage reprennent la référence de ${school.name}.` : 'Le classement intelligent repart de zéro.');
  }

  function adopt(key: string) {
    setAdopted(key);
    const candidate = data.adoption?.candidates.find(item => item.schoolId === key);
    if (!candidate) { setDone(null); setDraft(null); return; }
    edit(applyCandidate(baseline, candidate), `Configuration de ${candidate.schoolName} reprise, à enregistrer.`);
  }

  const tiles = previewKeys(current, baseline, data.palette).flatMap(key => {
    const row = current.rows.find(item => item.key === key);
    return row ? [{ key: row.key, title: row.title }] : [];
  });
  const status = runner.busy ? 'Enregistrement…' : runner.pending ? 'Résultat à vérifier' : done === 'save' ? 'Enregistré' : dirty ? 'Modifications non enregistrées' : null;
  const resetAllowed = canResetPresentation({ administrator, personalizationAllowed: data.personalizationAllowed });
  const copy = confirm === 'learning' ? learningResetCopy(dirty) : presentationResetCopy(school.name, { personalizationAllowed: data.personalizationAllowed, dirty });

  return <>
    <header className="signals-heading">
      <div>
        <h1>Signalements</h1>
        <p className="signals-counter">{school.name}</p>
      </div>
      {!visibilityEditable && <span className="signals-badge">Géré par l’école</span>}
    </header>
    <p className="sr-only" role="status" aria-live="polite">{announcement}</p>
    {notice && <Alert><AlertTitle>{refusalNotice[notice].title}</AlertTitle><AlertDescription>{refusalNotice[notice].message}</AlertDescription></Alert>}
    <CommandFeedback runner={runner} showSuccess={done !== null && done !== 'save'} />

    {data.adoption && <RadioGroup value={adopted} onValueChange={adopt} className="signals-choice" aria-label="Configuration de départ">
      <Label htmlFor={`${uid}-adopt-own`}><RadioGroupItem id={`${uid}-adopt-own`} value="own" />Celle de {school.name}</Label>
      {data.adoption.candidates.map(candidate => <Label key={candidate.schoolId} htmlFor={`${uid}-adopt-${candidate.schoolId}`}>
        <RadioGroupItem id={`${uid}-adopt-${candidate.schoolId}`} value={candidate.schoolId} />Reprendre celle de {candidate.schoolName}
      </Label>)}
    </RadioGroup>}

    <div className="signals-switchline">
      <Label htmlFor={`${uid}-smart`}>Classement intelligent</Label>
      <Switch id={`${uid}-smart`} checked={current.mode === 'SMART'} disabled={!editable}
        onCheckedChange={checked => edit({ ...current, mode: checked ? 'SMART' : 'MANUAL' }, checked ? 'Classement intelligent activé, à enregistrer.' : 'Ordre manuel, à enregistrer.')} />
    </div>

    <div className="signals-layout">
      <SortableThemes rows={current.rows} onChange={editRows} orderable togglable={visibilityEditable} disabled={!editable} label="Vos signalements, dans l’ordre manuel" />
      <SignalsPreview tiles={tiles} open={previewOpen} onOpenChange={setPreviewOpen} title="Ordre appliqué dans Signaler" />
    </div>

    <div className="signals-tools">
      {resetAllowed && <Button variant="outline" disabled={!editable} onClick={() => setConfirm('presentation')}><RotateCcw aria-hidden="true" />Rétablir l’ordre et la visibilité</Button>}
      <Button variant="ghost" size="sm" disabled={!editable} onClick={() => setConfirm('learning')}>Recommencer l’apprentissage du classement intelligent</Button>
    </div>

    {(dirty || status) && <div className="signals-savebar">
      <p role="status" aria-live="polite" className="signals-status">{done === 'save' && <Check aria-hidden="true" />}{status}</p>
      <div className="signals-actions">
        <Button variant="outline" disabled={!editable || !dirty || done === 'save'} onClick={() => { setDraft(null); setAdopted('own'); setDone(null); setAnnouncement('Modifications annulées.'); }}>Annuler</Button>
        <Button disabled={!editable || !dirty || done === 'save' || problem !== null} aria-busy={runner.busy} onClick={() => void save()}>Enregistrer</Button>
      </div>
    </div>}

    <Dialog open={confirm !== null} onOpenChange={open => { if (!open) setConfirm(null); }}><DialogContent>
      <DialogHeader><DialogTitle>{copy.title}</DialogTitle><DialogDescription>{copy.message}</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={() => setConfirm(null)}>Annuler</Button>
        <Button onClick={() => confirm && void confirmed(confirm)}>Confirmer</Button></DialogFooter>
    </DialogContent></Dialog>
  </>;
}
