import { useCommandSnapshot } from '../command-store';
import { dataPolicySchema, profilePolicySchema, readAll, readSchool, readinessSchema } from '../school-api';
import { Notice, StatusBadge, Symbol, type Tone } from '../ui';
import { readError, useConsole, useLoad, type SectionKey } from './context';
import { SectionHeading } from './layout';
import { consolePath } from './route';

export const schoolStatus = (status: string): { label: string; tone: Tone } =>
  status === 'ACTIVE' ? { label: 'École active', tone: 'success' } : status === 'DRAFT' ? { label: 'En préparation', tone: 'warning' } : { label: 'École inactive', tone: 'neutral' };

export const capabilityTitle = (capability: string) => ({
  CAN_USE_WORKSPACE: 'Espace de l’école', CAN_PLAN_LESSON: 'Planification des leçons',
  CAN_CAPTURE: 'Enregistrement des trajets', CAN_PUBLISH_COURSE: 'Publication des cours',
} as Record<string, string>)[capability] ?? 'Autre fonction';

async function settle<T>(work: Promise<T>): Promise<{ ok: true; value: T } | { ok: false; error: string }> {
  try { return { ok: true, value: await work }; } catch (error) { return { ok: false, error: readError(error) }; }
}

/** First-run preparation lives in Settings, never as the working homepage of an active school. */
export function OverviewSection() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [readiness, policy, profile] = await Promise.all([
      settle(readSchool(schoolId, 'readiness', readinessSchema)),
      settle(readSchool(schoolId, 'data-policy', dataPolicySchema)),
      settle(readAll(schoolId, 'profile-field-policies', profilePolicySchema)),
    ]);
    return { readiness, policy, profile };
  }, [schoolId, revision, school.version]);
  const data = loaded.data, status = schoolStatus(school.status);
  const identityCodes = ['SCHOOL_IDENTITY_REQUIRED', 'INVALID_TIME_ZONE', 'SCHOOL_CONTACT_REQUIRED'];
  const identityReady = data?.readiness.ok && !data.readiness.value.activationBlockers.some(item => identityCodes.includes(item.code));
  const rows: { title: string; section: SectionKey; done: boolean | undefined }[] = [
    { title: 'École et confidentialité', section: 'configuration', done: data?.policy.ok && identityReady && data.policy.value.status === 'APPROVED' },
    { title: 'Informations demandées aux élèves', section: 'champs-profil', done: data?.profile.ok && data.profile.value.items.some(item => item.status === 'PUBLISHED') },
    { title: 'Formations et tarifs', section: 'formations', done: data?.readiness.ok && data.readiness.value.capabilities.some(item => item.capability === 'CAN_PLAN_LESSON' && item.ready) },
  ];
  const failures = data ? Object.values(data).filter(result => !result.ok).length : 0;
  return <div className="section-stack">
    <SectionHeading title="Préparation de l’école" actions={school.status !== 'ACTIVE' ? <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge> : undefined} />
    {loaded.status === 'loading' && !data && <p className="loading" role="status"><span className="spinner" aria-hidden="true" />Vérification de l’école…</p>}
    {failures > 0 && <Notice tone="warning" title="Préparation à vérifier" actions={<button type="button" className="button retry" onClick={loaded.reload}>Réessayer</button>}>
      <p>Certaines informations n’ont pas pu être lues.</p>
    </Notice>}
    <ul className="preparation-list">{rows.map((row, index) => <li key={row.section}>
      <a className="preparation-link" href={consolePath(schoolId, row.section)} onClick={event => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
        event.preventDefault(); navigate(row.section);
      }}>
        <span className={row.done ? 'preparation-marker done' : 'preparation-marker'} aria-hidden="true">{row.done ? <Symbol kind="check" bare /> : String(index + 1).padStart(2, '0')}</span>
        <div className="row-text"><h2 className="row-title">{row.title}</h2>{row.done && <span className="row-meta">Prêt</span>}</div>
        <span className="flip"><Symbol kind="back" bare /></span>
      </a>
    </li>)}</ul>
    {school.status === 'DRAFT' && <div className="preparation-next">
      <button type="button" className="button primary" onClick={() => navigate('configuration')}>Relire et activer l’école</button>
    </div>}
    {school.status === 'ACTIVE' && <div className="preparation-next">
      <button type="button" className="button primary" onClick={() => navigate('agenda')}>Ouvrir le planning</button>
    </div>}
  </div>;
}
