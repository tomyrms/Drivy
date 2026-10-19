import { useCommandSnapshot } from '../command-store';
import { readSchool, recordingChoiceSchema } from '../school-api';
import { gpsConsentLabel } from './privacy-model';
import { Loading, Notice, StatusBadge } from '../ui';
import { RequestFailure } from '../protocol';
import { ReadRetry } from './layout';
import { useConsole, useLoad } from './context';
import { z } from 'zod';

const listSchema = z.object({ items: z.array(recordingChoiceSchema).max(5000) });

/** Accord GPS de l'élève, lu une fois pour toute l'école (réservé à l'administration ; rien si la lecture est refusée). */
export function GpsConsentLine({ learnerId }: { learnerId: string }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    try { return await readSchool(schoolId, 'recording-choices', listSchema); }
    catch (error) {
      // A denied read stays hidden, but an outage must not look like a missing feature.
      if (error instanceof RequestFailure && error.status === 403) return null;
      throw error;
    }
  }, [schoolId, revision]);
  if (loaded.status === 'loading') return <Loading label="Lecture de l’accord GPS…" />;
  if (loaded.status === 'error') return <Notice tone="error" title="Accord GPS indisponible" actions={<ReadRetry loaded={loaded} />}><p>{loaded.error}</p></Notice>;
  if (!loaded.data) return null;
  const label = gpsConsentLabel(loaded.data.items.find(item => item.learnerId === learnerId));
  return <p className="row-meta with-badge">Accord GPS : {label.renew ? <StatusBadge tone="warning" symbol="alert">{label.text}</StatusBadge> : label.text}</p>;
}
