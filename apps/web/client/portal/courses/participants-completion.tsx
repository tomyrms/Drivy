import { useState } from 'react';
import { BadgeCheck } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Input } from '../../components/ui/input';
import { activeCompletion, requirementLabel, type CourseSeries, type CourseSheetRow } from '../../console/course-model';
import { useConsole } from '../../console/context';
import { ReadFeedback } from '../agenda/presentation';
import { instantDateTime } from './course-presentation';
import { eligibility, filterByName } from './participants-model';
import { ActionDialog } from './participants-dialogs';
import { FeedbackText } from './participants-parts';
import { feedbackKey, type CourseParticipants } from './use-course-participants';

const missingLabel = (count: number) => `${count} ${count === 1 ? 'séance obligatoire reste' : 'séances obligatoires restent'} à marquer présente${count === 1 ? '' : 's'}`;

/**
 * Internal validation of the course, apart from presence and payment. It becomes possible once every required session is marked
 * present, it is an act of the school, and a withdrawal needs a motive; the school keeps the history of the validation.
 */
export function CompletionTab({ state, series }: { state: CourseParticipants; series: CourseSeries }) {
  const { school } = useConsole();
  const [search, setSearch] = useState('');
  const [validating, setValidating] = useState<CourseSheetRow | null>(null);
  const [revoking, setRevoking] = useState<{ row: CourseSheetRow; completionId: string } | null>(null);
  const sheet = state.sheet;
  if (!sheet) return <ReadFeedback loaded={state.sheetRead} label="Lecture des validations" />;
  const rows = filterByName(sheet.rows, search);
  return <div className="participants-tab">
    <ReadFeedback loaded={state.sheetRead} label="Lecture des validations" />
    <div className="participants-head"><h2>Validation interne</h2></div>
    {sheet.rows.length > 8 && <Input type="search" aria-label="Rechercher un participant" placeholder="Rechercher un participant" value={search} onChange={event => setSearch(event.target.value)} />}
    {sheet.rows.length === 0 ? <Empty className="participants-empty"><EmptyHeader><EmptyMedia variant="icon"><BadgeCheck /></EmptyMedia><EmptyTitle>Aucun inscrit</EmptyTitle></EmptyHeader></Empty>
      : rows.length === 0 ? <p className="course-muted" role="status">Aucun participant trouvé.</p>
        : <ul className="participants-list">{rows.map(row => {
          const kind = eligibility(row, series.id);
          const completion = activeCompletion(row);
          return <li key={row.enrollmentId} data-muted={kind === 'cancelled'}>
            <div className="participants-main"><strong>{row.learnerDisplayName || 'Élève'}</strong>
              <span className="course-muted">{requirementLabel(row.requirements)}</span>
              {completion && <span className="participants-state" data-state="validated">Validé le {instantDateTime(completion.validatedAt, school.timeZone)}{kind === 'validated-elsewhere' ? ' · autre session' : ''}</span>}
              {kind === 'missing' && <span className="course-muted">{missingLabel(row.requirements.missing)}</span>}
              <FeedbackText feedback={state.feedback[feedbackKey('completion', row.enrollmentId)]} /></div>
            {kind === 'eligible' && <Button disabled={state.locked} aria-label={`Valider le cours pour ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setValidating(row)}>Valider</Button>}
            {kind === 'validated' && completion && <Button variant="ghost" disabled={state.locked} aria-label={`Retirer la validation de ${row.learnerDisplayName || 'cet élève'}`} onClick={() => setRevoking({ row, completionId: completion.id })}>Retirer</Button>}
            {kind === 'cancelled' && <Badge variant="outline">Annulée</Badge>}
          </li>;
        })}</ul>}
    <ActionDialog open={validating !== null} title="Valider le cours" subject={validating?.learnerDisplayName || 'Élève'} withReason={false} confirmLabel="Valider le cours" state={state}
      facts={validating ? [['Cours', series.title], ['Présences', requirementLabel(validating.requirements)]] : []}
      onClose={() => setValidating(null)} onConfirm={() => validating ? state.validate(validating) : Promise.resolve({ status: 'rejected' as const, message: 'Participant introuvable.' })} />
    <ActionDialog open={revoking !== null} title="Retirer la validation" subject={revoking?.row.learnerDisplayName || 'Élève'} withReason destructive confirmLabel="Retirer la validation" state={state}
      facts={revoking ? [['Cours', series.title]] : []} consequence="L’historique de la validation est conservé par l’école."
      onClose={() => setRevoking(null)} onConfirm={reason => revoking ? state.revoke(revoking.row, revoking.completionId, reason) : Promise.resolve({ status: 'rejected' as const, message: 'Validation introuvable.' })} />
  </div>;
}
