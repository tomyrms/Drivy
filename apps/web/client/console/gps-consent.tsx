import { useCommandSnapshot } from '../command-store';
import { readSchool, recordingChoiceSchema } from '../school-api';
import { gpsConsentLabel } from './privacy-model';
import { StatusBadge } from '../ui';
import { useConsole, useLoad } from './context';
import { z } from 'zod';

const listSchema = z.object({ items: z.array(recordingChoiceSchema).max(5000) });

/** Accord GPS de l'élève, lu une fois pour toute l'école (réservé à l'administration ; rien si la lecture est refusée). */
export function GpsConsentLine({ learnerId }: { learnerId: string }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'recording-choices', listSchema), [schoolId, revision]);
  if (loaded.status !== 'ready' || !loaded.data) return null;
  const label = gpsConsentLabel(loaded.data.items.find(item => item.learnerId === learnerId));
  return <p className="row-meta with-badge">Accord GPS : {label.renew ? <StatusBadge tone="warning" symbol="alert">{label.text}</StatusBadge> : label.text}</p>;
}
