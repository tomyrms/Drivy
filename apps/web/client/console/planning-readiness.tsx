import { useCommandSnapshot } from '../command-store';
import { readSchool, readinessSchema } from '../school-api';
import { Notice, Symbol } from '../ui';
import { useConsole, useLoad, type SectionKey } from './context';
import { ReadRetry } from './layout';

/** Où se corrige chaque manque signalé par le serveur (destinationKey des blocages de CAN_PLAN_LESSON). */
export const destinationSection: Record<string, SectionKey> = {
  OFFERINGS: 'formations', TEAM: 'equipe', AVAILABILITY: 'disponibilites', COMMERCIAL: 'prestations',
  PROFILE_POLICY: 'champs-profil', SCHOOL_SETUP: 'apercu',
};

/** Ce qui manque encore pour planifier une leçon, en tête de l'Agenda : rien quand tout est prêt. */
export function PlanningReadinessBanner({ refreshKey = 0 }: { refreshKey?: number }) {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'readiness', readinessSchema), [schoolId, revision, school.version, refreshKey]);
  if (school.status === 'ACTIVE' && loaded.status === 'error') return <Notice tone="error" title="Lecture impossible" actions={<ReadRetry loaded={loaded} />}><p>{loaded.error}</p></Notice>;
  const planning = loaded.data?.capabilities.find(item => item.capability === 'CAN_PLAN_LESSON');
  if (school.status !== 'ACTIVE' || !planning || planning.ready) return null;
  const blockers = planning.blockers.filter((item, index, all) => all.findIndex(other => other.code === item.code) === index);
  return <Notice tone="info" title="Pour planifier une leçon" live={false}>
    <ul className="blocker-list">{blockers.map(item => {
      const section = item.destinationKey ? destinationSection[item.destinationKey] : undefined;
      return <li key={item.code}><Symbol kind="dot" bare />{item.message}
        {section && <button type="button" className="button quiet compact" onClick={() => navigate(section, section === 'apercu' ? { from: 'configuration' } : {})}>Ouvrir</button>}</li>;
    })}</ul>
  </Notice>;
}
