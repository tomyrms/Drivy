import { useCommandSnapshot } from '../../command-store';
import { RequestFailure } from '../../protocol';
import { readSchool, readinessSchema } from '../../school-api';
import { useConsole, useLoad } from '../../console/context';
import type { SectionKey } from '../../console/sections';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { ReadFeedback } from '../components/feedback';

/** Destinations announced by the server; an unknown destination never creates an arbitrary route. */
const destinations: Readonly<Record<string, SectionKey>> = {
  OFFERINGS: 'formations', TEAM: 'equipe', AVAILABILITY: 'disponibilites', COMMERCIAL: 'prestations',
  PROFILE_POLICY: 'champs-profil', SCHOOL_SETUP: 'apercu',
};

/** Same school readiness as the existing planner, read again after a command or an explicit agenda refresh. */
export function PlanningReadinessBanner({ refreshKey = 0 }: { refreshKey?: number }) {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const value = await readSchool(schoolId, 'readiness', readinessSchema);
    if (value.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return value;
  }, [schoolId, revision, school.version, refreshKey]);
  if (school.status !== 'ACTIVE') return null;
  if (loaded.status === 'error') return <ReadFeedback loaded={loaded} label="Vérification des conditions de planification" />;
  const planning = loaded.data?.capabilities.find(item => item.capability === 'CAN_PLAN_LESSON');
  if (!planning || planning.ready) return null;
  const blockers = planning.blockers.filter((item, index, all) => all.findIndex(other => other.code === item.code
    && other.message === item.message && other.destinationKey === item.destinationKey) === index);
  return <Alert><AlertTitle>Pour planifier une leçon</AlertTitle><AlertDescription>
    <ul className="flex w-full flex-col gap-2">{blockers.map((item, index) => {
      const section = item.destinationKey ? destinations[item.destinationKey] : undefined;
      return <li key={`${item.code}-${index}`} className="flex flex-wrap items-center justify-between gap-2">
        <span className="min-w-0 flex-1 break-words">{item.message}</span>
        {section && <Button variant="outline" size="sm" aria-label={`Ouvrir le réglage : ${item.message}`}
          onClick={() => navigate(section, section === 'apercu' ? { from: 'configuration' } : {})}>Ouvrir</Button>}
      </li>;
    })}</ul>
  </AlertDescription></Alert>;
}
