import { useState } from 'react';
import { ArrowLeft, Download, FileSearch } from 'lucide-react';
import { civilDateIn, weekStart } from '../../agenda-model';
import { readError, useConsole, useLoad } from '../../console/context';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Tabs, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { ReadFeedback } from '../components/feedback';
import { coverageBadge, PilotageSection } from './components';
import { expectedFromCard, exportErrorMessage, lineStatus, lineTitle, measureDomain, measureParts, shownAmount, totalText } from './detail-model';
import { exportMeasure, readDetails, type DetailLineRecord, type DetailRequest } from './details-api';
import { describeReason, formatMeasure } from './measure-format';
import { MetricsView, ScopeLine } from './metrics-view';
import type { MetricDefinition, MetricFilters, MetricMeasure, MetricsAnswer } from './metrics-api';
import { periodLabel, type ResolvedPeriod } from './period-model';

/**
 * Lignes d'une mesure (#380) pour la période, la portée et les filtres de la carte d'origine. Le chiffre de la carte, le total du détail et le
 * fichier exporté sont trois lectures du même périmètre ; un écart entre la carte et le détail est signalé par le serveur, jamais masqué.
 */
export function MeasureDetail({ measure, part, period, filters, scopeLabel, canExport, onBack, onPart }: {
  measure: string; part: 'a' | 'b' | undefined; period: ResolvedPeriod; filters: MetricFilters; scopeLabel: string; canExport: boolean; onBack: () => void; onPart: (part: 'a' | 'b') => void;
}) {
  // Relire remonte les deux lectures : la carte et ses lignes repartent d'un même instant.
  const [reread, setReread] = useState(0);
  return <div className="pilotage-detail">
    <Button variant="ghost" size="sm" className="pilotage-back" onClick={onBack} autoFocus><ArrowLeft data-icon="inline-start" aria-hidden="true" />Retour aux chiffres</Button>
    <MetricsView key={reread} label="Lecture du détail" request={{ domain: measureDomain(measure), from: period.from, toExclusive: period.toExclusive, ...filters }}>
      {(answer, definitions) => {
        const card = answer.measures[measure], definition = definitions.get(measure);
        if (!card || !definition) return <Alert><AlertTitle>Cette mesure n’est pas disponible</AlertTitle><AlertDescription>Elle n’existe pas pour cette portée ou vos accès ne la montrent pas.</AlertDescription></Alert>;
        return <DetailBody measure={measure} part={part} onPart={onPart} card={card} definition={definition} answer={answer} period={period} filters={filters} scopeLabel={scopeLabel}
          canExport={canExport} onReread={() => setReread(value => value + 1)} />;
      }}
    </MetricsView>
  </div>;
}

function DetailBody({ measure, part, onPart, card, definition, answer, period, filters, scopeLabel, canExport, onReread }: {
  measure: string; part: 'a' | 'b' | undefined; onPart: (part: 'a' | 'b') => void; card: MetricMeasure; definition: MetricDefinition; answer: MetricsAnswer; period: ResolvedPeriod; filters: MetricFilters;
  scopeLabel: string; canExport: boolean; onReread: () => void;
}) {
  const { schoolId, school, csrf, refreshCsrf, login, navigate } = useConsole();
  // Une mesure en deux listes se lit par partie (F06) ; le chiffre de la carte les additionne, il ne peut donc pas servir de valeur attendue pour une seule.
  const parts = measureParts[measure], shownPart = parts ? part ?? parts[0]?.part : undefined;
  const request: DetailRequest = { measure, part: shownPart, from: period.from, toExclusive: period.toExclusive, ...filters };
  const expected = parts ? {} : expectedFromCard(card);
  const scope = [schoolId, measure, shownPart ?? '', period.from, period.toExclusive, filters.instructor ?? '', filters.category ?? '', filters.product ?? ''].join('/');
  const first = useLoad(() => readDetails(schoolId, request, null, expected), [schoolId, scope], scope);
  const [more, setMore] = useState<{ lines: DetailLineRecord[]; cursor: string | null | undefined; busy: boolean; error: string | null }>({ lines: [], cursor: undefined, busy: false, error: null });
  const [file, setFile] = useState<{ status: 'idle' | 'busy' | 'done' | 'failed'; message: string; login: boolean }>({ status: 'idle', message: '', login: false });

  const detail = first.status === 'ready' ? first.data : undefined;
  const lines = detail ? [...detail.lines, ...more.lines] : [];
  const nextCursor = more.cursor === undefined ? detail?.page.nextCursor ?? null : more.cursor;
  const loadMore = async () => {
    if (!nextCursor) return;
    setMore(previous => ({ ...previous, busy: true, error: null }));
    try {
      const page = await readDetails(schoolId, request, nextCursor, {});
      setMore(previous => ({ lines: [...previous.lines, ...page.lines], cursor: page.page.nextCursor, busy: false, error: null }));
    } catch (error) { setMore(previous => ({ ...previous, busy: false, error: readError(error) })); }
  };
  const download = async () => {
    setFile({ status: 'busy', message: '', login: false });
    let outcome = await exportMeasure(schoolId, csrf(), request, expected);
    if (!outcome.ok && (outcome.code === 'CSRF_INVALID' || outcome.code === 'CSRF_REQUIRED' || outcome.code === 'CSRF_REJECTED')) outcome = await exportMeasure(schoolId, await refreshCsrf(), request, expected);
    if (outcome.ok) setFile({ status: 'done', login: false, message: outcome.drift ? `${outcome.fileName} téléchargé. Les données ont changé depuis l’affichage : le fichier le signale.` : `${outcome.fileName} téléchargé.` });
    else setFile({ status: 'failed', message: exportErrorMessage(outcome.code), login: outcome.code === 'REAUTH_REQUIRED' || outcome.code === 'SESSION_EXPIRED' });
  };
  const open = (line: DetailLineRecord) => {
    const day = civilDateIn(school.timeZone, Date.parse(line.eventAt)), base = { week: weekStart(day), day, ...(filters.instructor ? { instructor: filters.instructor } : {}) };
    if (line.kind === 'LESSON') navigate('agenda', { ...base, lesson: line.id });
    else if (line.seriesId) navigate('agenda', { ...base, course: line.seriesId, ...(line.kind === 'COURSE_OCCURRENCE' ? { occurrence: line.id } : {}) });
  };
  const time = new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short', timeZone: school.timeZone });
  const shown = shownAmount(lines);
  const complete = detail !== undefined && lines.length >= detail.total.lineCount;

  return <PilotageSection title={definition.label} action={canExport
    ? <Button variant="outline" size="sm" disabled={file.status === 'busy'} onClick={() => void download()}><Download data-icon="inline-start" aria-hidden="true" />{file.status === 'busy' ? 'Export en cours…' : 'Exporter en CSV'}</Button>
    : undefined}>
    <div className="pilotage-detail-value">
      <p className="pilotage-value">{formatMeasure(card.value, card.unit)}</p>
      {card.coverage.status !== 'COMPLETE' && <Badge variant="outline">{coverageBadge[card.coverage.status]}</Badge>}
    </div>
    {card.coverage.reasons.length > 0 && <ul className="pilotage-reasons">{card.coverage.reasons.map(reason => <li key={reason.code}>{describeReason(reason.code, reason.count)}</li>)}</ul>}
    <ScopeLine period={periodLabel(period)} scope={scopeLabel} answer={answer} />
    {parts && <Tabs value={shownPart} onValueChange={value => onPart(value as 'a' | 'b')}>
      <TabsList aria-label="Liste affichée">{parts.map(item => <TabsTrigger key={item.part} value={item.part}>{item.label}</TabsTrigger>)}</TabsList>
    </Tabs>}
    <div role="status" aria-live="polite">
      {file.status === 'done' && <Alert><AlertTitle>Export terminé</AlertTitle><AlertDescription>{file.message}</AlertDescription></Alert>}
      {file.status === 'failed' && <Alert variant="destructive"><AlertTitle>Export impossible</AlertTitle><AlertDescription>{file.message}</AlertDescription>
        {file.login && <div className="mt-3"><Button variant="outline" onClick={() => login()}>Se reconnecter</Button></div>}</Alert>}
    </div>
    <ReadFeedback loaded={first} label="Lecture des lignes" />
    {detail && <>
      {detail.drift && <Alert><AlertTitle>Les données ont changé</AlertTitle><AlertDescription>Le total des lignes ne correspond plus au chiffre affiché. Relisez pour repartir d’un même instant.</AlertDescription>
        <div className="mt-3"><Button variant="outline" onClick={onReread}>Relire</Button></div></Alert>}
      <p className="pilotage-scope">Total : {totalText(detail.total)} · Affichées : {lines.length} sur {detail.total.lineCount}{!complete && shown !== null ? ` · somme des lignes affichées : ${formatMeasure(shown, 'cents')}` : ''}</p>
      {lines.length === 0
        ? <Empty><EmptyHeader><EmptyMedia variant="icon"><FileSearch aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucune ligne sur cette période</EmptyTitle></EmptyHeader></Empty>
        : <ul className="pilotage-list pilotage-lines">{lines.map(line => <li key={`${line.kind}:${line.id}`}>
          <div className="pilotage-line-what">
            <strong>{lineTitle(line)}</strong>
            <span>{[time.format(new Date(line.eventAt)), line.instructorLabel?.trim() || null, lineStatus(line),
              line.durationSeconds === null || line.durationSeconds === undefined ? null : formatMeasure(line.durationSeconds, 'seconds')].filter(Boolean).join(' · ')}</span>
          </div>
          {line.amountCents !== null && line.amountCents !== undefined && <span className="pilotage-line-amount">{formatMeasure(line.amountCents, 'cents')}</span>}
          {(line.kind === 'LESSON' || line.seriesId) && <Button variant="ghost" size="sm" onClick={() => open(line)} aria-label={`Ouvrir : ${lineTitle(line)}, ${time.format(new Date(line.eventAt))}`}>Ouvrir</Button>}
        </li>)}</ul>}
      {more.error && <Alert variant="destructive"><AlertTitle>La suite n’a pas pu être lue</AlertTitle><AlertDescription>{more.error}</AlertDescription>
        <div className="mt-3 flex flex-wrap gap-2"><Button variant="outline" onClick={() => void loadMore()}>Réessayer</Button><Button variant="outline" onClick={onReread}>Relire depuis le début</Button></div></Alert>}
      {nextCursor && !more.error && <div><Button variant="outline" disabled={more.busy} onClick={() => void loadMore()}>{more.busy ? 'Lecture…' : 'Afficher la suite'}</Button></div>}
    </>}
  </PilotageSection>;
}
