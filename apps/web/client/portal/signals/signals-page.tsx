import { useId, useMemo, useState } from 'react';
import { Check, ChevronDown, RotateCcw } from 'lucide-react';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { readObservationThemes, type ObservationThemes } from '../../school-api';
import { useCommandRunner, useConsole, useLoad, useSectionDraft } from '../../console/context';
import {
  counterLabel, draftProblem, isDefaultConfiguration, isDefaultOrder, isDirty, previewTiles, resetAll, resetOrder, saveBody, settingsOf, type ThemeRow,
} from '../../console/observation-themes-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '../../components/ui/dropdown-menu';
import { Label } from '../../components/ui/label';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import { previewStartsOpen, SignalsPreview, SortableThemes } from './signals-parts';
import './signals.css';

/** Le brouillon porte la politique avec la liste : les deux s'enregistrent ensemble, au nom de l'école. */
type Draft = { version: number; rows: ThemeRow[]; personalizationAllowed: boolean };
const toRow = (theme: ObservationThemes['themes'][number]): ThemeRow => ({
  key: theme.key, title: theme.title, visible: theme.visible, defaultVisible: theme.defaultVisible, defaultPosition: theme.defaultPosition,
});

/**
 * Signalements DE L'ÉCOLE (administration) : ordre et affichage de référence, et politique de personnalisation des moniteurs.
 * Ce que chaque personne règle pour elle-même vit dans Mon compte, Préférences, Signalements.
 */
export function SignalsPilot() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readObservationThemes(schoolId), [schoolId, revision]);
  return <section className="signals-page">
    {loaded.status === 'ready' && loaded.data ? <SignalsEditor data={loaded.data} reload={loaded.reload} /> : <>
      <header className="signals-heading"><h1>Signalements de l’école</h1></header>
      <ReadFeedback loaded={loaded} label="Lecture des signalements" />
    </>}
  </section>;
}

export function SignalsEditor({ data, reload }: { data: ObservationThemes; reload: () => void }) {
  const { schoolId } = useConsole();
  const uid = useId();
  const [saved, setSaved] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(previewStartsOpen);
  const runner = useCommandRunner(() => setSaved(true));
  const baseline = useMemo(() => data.themes.map(toRow), [data]);
  const changed = (candidate: Draft) => isDirty(settingsOf(candidate.rows), settingsOf(baseline)) || candidate.personalizationAllowed !== data.personalizationAllowed;
  const [draft, setDraft] = useSectionDraft<Draft>('observation-themes', candidate => !saved && candidate.version === data.version && changed(candidate));
  const [notice, setNotice] = useState<'conflict' | 'forbidden' | null>(null);
  const [announcement, setAnnouncement] = useState('');

  // A draft from an older version is never replayed over a newer configuration.
  const current = draft && draft.version === data.version ? draft : null;
  const rows = current?.rows ?? baseline;
  const personalizationAllowed = current?.personalizationAllowed ?? data.personalizationAllowed;
  const dirty = changed({ version: data.version, rows, personalizationAllowed });
  const canManage = data.canManage && notice !== 'forbidden';
  const editable = canManage && !runner.pending && !runner.busy;
  const problem = draftProblem(rows);

  function edit(next: Draft, message: string) {
    setSaved(false); setNotice(null); runner.clearOutcome();
    setDraft(next);
    if (message) setAnnouncement(message);
  }
  const editRows = (next: ThemeRow[], message: string) => edit({ version: data.version, rows: next, personalizationAllowed }, message);

  async function save() {
    if (!editable || !dirty || saved || problem) return;
    runner.clearOutcome(); setNotice(null); setSaved(false);
    const command = createCommand({ schoolId, kind: 'saveObservationThemes', path: 'observation-themes',
      ifMatch: data.version, resourceVersion: data.version, body: saveBody(rows, personalizationAllowed) });
    const result = await runner.run(command, 'Les signalements de l’école sont enregistrés.');
    if (result.status === 'confirmed') { setSaved(true); return; }
    if (result.status !== 'rejected') return;
    if (result.code === 'VERSION_CONFLICT' || result.code === 'PRECONDITION_REQUIRED') {
      // Someone saved meanwhile: start again from their version, overwrite nothing.
      runner.clearOutcome(); setNotice('conflict'); setDraft(null); reload();
    } else if (['OBSERVATION_THEMES_ACCESS_REQUIRED', 'FORBIDDEN', 'ACCESS_DENIED'].includes(result.code)) {
      runner.clearOutcome(); setNotice('forbidden'); setDraft(null); reload();
    }
  }

  const status = runner.busy ? 'Enregistrement…' : runner.pending ? 'Résultat à vérifier' : saved ? 'Enregistré pour l’école' : dirty ? 'Modifications non enregistrées' : null;

  return <>
    <header className="signals-heading">
      <div><h1>Signalements de l’école</h1><p className="signals-counter">{counterLabel(rows)}</p></div>
      {canManage && <DropdownMenu>
        <DropdownMenuTrigger render={<Button variant="outline" disabled={!editable || isDefaultConfiguration(rows)} />}><RotateCcw aria-hidden="true" />Valeurs Drivy<ChevronDown aria-hidden="true" /></DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-64">
          <DropdownMenuItem disabled={isDefaultOrder(rows)} onClick={() => editRows(resetOrder(rows), 'Ordre Drivy rétabli, à enregistrer.')}>Rétablir l’ordre Drivy</DropdownMenuItem>
          <DropdownMenuItem onClick={() => editRows(resetAll(rows), 'Configuration Drivy rétablie, à enregistrer.')}>Rétablir la configuration Drivy</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>}
    </header>
    <p className="sr-only" role="status" aria-live="polite">{announcement}</p>
    {!canManage && <Alert><AlertTitle>Lecture seule</AlertTitle><AlertDescription>Vos accès ne permettent pas de modifier les signalements de l’école.</AlertDescription></Alert>}
    {notice === 'conflict' && <Alert><AlertTitle>Configuration rechargée</AlertTitle><AlertDescription>Les signalements ont changé entre-temps ; vos modifications n’ont pas été enregistrées.</AlertDescription></Alert>}
    <CommandFeedback runner={runner} showSuccess={false} />

    {canManage && <div className="signals-policy">
      <Checkbox id={`${uid}-policy`} checked={personalizationAllowed} disabled={!editable}
        onCheckedChange={value => edit({ version: data.version, rows, personalizationAllowed: value === true },
          value === true ? 'Les moniteurs peuvent personnaliser les signalements.' : 'Les moniteurs ne peuvent plus personnaliser l’affichage.')} />
      <Label htmlFor={`${uid}-policy`}>Autoriser les moniteurs à personnaliser les signalements</Label>
    </div>}

    <div className="signals-layout">
      <SortableThemes rows={rows} onChange={editRows} orderable={canManage} togglable={canManage} disabled={!editable} label="Signalements de l’école, dans l’ordre d’affichage" />
      <SignalsPreview tiles={previewTiles(rows)} open={previewOpen} onOpenChange={setPreviewOpen} />
    </div>

    {canManage && (dirty || status) && <div className="signals-savebar">
      <p role="status" aria-live="polite" className="signals-status">{saved && <Check aria-hidden="true" />}{status}</p>
      <div className="signals-actions">
        <Button variant="outline" disabled={!editable || !dirty || saved} onClick={() => { setDraft(null); setSaved(false); setAnnouncement('Modifications annulées.'); }}>Annuler</Button>
        <Button disabled={!editable || !dirty || saved || problem !== null} aria-busy={runner.busy} onClick={() => void save()}>Enregistrer pour l’école</Button>
      </div>
    </div>}
  </>;
}
