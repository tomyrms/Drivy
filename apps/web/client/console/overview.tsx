import { useCommandSnapshot } from '../command-store';
import {
  catalogPolicySchema, curriculumSchema, dataPolicySchema, offeringSchema, productSchema, profilePolicySchema, readAll, readSchool,
  readinessSchema, termsSchema,
} from '../school-api';
import { Facts, Notice, StatusBadge, Symbol, type Tone } from '../ui';
import { readError, useConsole, useLoad, type SectionKey } from './context';
import { SectionHeading } from './layout';

type StepState = 'done' | 'todo' | 'blocked' | 'unknown';
interface Step { title: string; detail: string; state: StepState; section: SectionKey; action: string }

export const schoolStatus = (status: string): { label: string; tone: Tone } =>
  status === 'ACTIVE' ? { label: 'École active', tone: 'success' } : status === 'DRAFT' ? { label: 'En préparation', tone: 'warning' } : { label: 'École inactive', tone: 'neutral' };

export const capabilityTitle = (capability: string) => ({
  CAN_USE_WORKSPACE: 'Espace de l’école', CAN_PLAN_LESSON: 'Planification des leçons',
  CAN_CAPTURE: 'Enregistrement des trajets', CAN_PUBLISH_COURSE: 'Publication des cours',
} as Record<string, string>)[capability] ?? 'Autre fonction';

async function settle<T>(work: Promise<T>): Promise<{ ok: true; value: T } | { ok: false; error: string }> {
  try { return { ok: true, value: await work }; } catch (error) { return { ok: false, error: readError(error) }; }
}

export function OverviewSection() {
  const { schoolId, school, canConfigureCatalog, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  // Each read is independent: one unavailable list does not hide the others.
  const loaded = useLoad(async () => {
    const [readiness, policy, curricula, procedures, offerings, profile, terms, products] = await Promise.all([
      settle(readSchool(schoolId, 'readiness', readinessSchema)),
      settle(readSchool(schoolId, 'data-policy', dataPolicySchema)),
      settle(readAll(schoolId, 'curricula', curriculumSchema)),
      settle(readAll(schoolId, 'policy-versions', catalogPolicySchema)),
      settle(readAll(schoolId, 'offerings', offeringSchema)),
      settle(readAll(schoolId, 'profile-field-policies', profilePolicySchema)),
      settle(readAll(schoolId, 'commercial-terms', termsSchema)),
      settle(readAll(schoolId, 'service-products', productSchema)),
    ]);
    return { readiness, policy, curricula, procedures, offerings, profile, terms, products };
  }, [schoolId, revision, school.version]);

  const data = loaded.data;
  const state = <T,>(result: { ok: true; value: T } | { ok: false; error: string } | undefined, done: (value: T) => boolean): StepState =>
    !result ? 'unknown' : !result.ok ? 'unknown' : done(result.value) ? 'done' : 'todo';
  const identityCodes = ['SCHOOL_IDENTITY_REQUIRED', 'INVALID_TIME_ZONE', 'SCHOOL_CONTACT_REQUIRED'];
  const steps: Step[] = [
    { title: 'Coordonnées de l’école', detail: 'Nom, e-mail et téléphone affichés aux membres.', section: 'configuration', action: 'Vérifier les coordonnées',
      state: state(data?.readiness, value => !value.activationBlockers.some(item => identityCodes.includes(item.code))) },
    { title: 'Textes d’information et de conservation', detail: 'Adoptés explicitement avant toute invitation.', section: 'configuration', action: 'Adopter les textes',
      state: state(data?.policy, value => value.status === 'APPROVED') },
    { title: 'Activation de l’école', detail: 'Ouvre l’espace de l’école à ses membres.', section: 'configuration', action: 'Relire et activer',
      state: school.status === 'ACTIVE' ? 'done' : data?.readiness?.ok && !data.readiness.value.activationReady ? 'blocked' : state(data?.readiness, () => false) },
    { title: 'Champs du profil', detail: 'Informations demandées aux élèves, avec leur utilité.', section: 'champs-profil', action: 'Définir les champs',
      state: state(data?.profile, value => value.items.some(item => item.status === 'PUBLISHED')) },
    { title: 'Référentiel approuvé', detail: 'Compétences travaillées pour une catégorie.', section: 'referentiels', action: 'Préparer un référentiel',
      state: state(data?.curricula, value => value.items.some(item => item.approved)) },
    { title: 'Procédure approuvée', detail: 'Déroulement de la formation et conditions d’annulation.', section: 'procedures', action: 'Préparer une procédure',
      state: state(data?.procedures, value => value.items.some(item => item.approved)) },
    { title: 'Offre activée', detail: 'Permet d’ouvrir de nouvelles formations.', section: 'offres', action: 'Créer une offre',
      state: state(data?.offerings, value => value.items.some(item => item.enabled)) },
    { title: 'Conditions commerciales et prestations', detail: canConfigureCatalog ? 'Tarifs proposés, liés à des conditions approuvées.' : 'Demande l’autorisation « Configurer les prestations et tarifs ».',
      section: 'prestations', action: 'Configurer les prestations',
      state: !canConfigureCatalog ? 'blocked' : state(data?.products, value => value.items.some(item => item.enabled)) === 'done'
        && state(data?.terms, value => value.items.some(item => item.approved)) === 'done' ? 'done' : data ? 'todo' : 'unknown' },
  ];
  const next = steps.find(step => step.state === 'todo' || (step.state === 'blocked' && step.section === 'configuration'));
  const status = schoolStatus(school.status);
  const failures = data ? Object.values(data).filter(result => !result.ok).length : 0;
  const remaining = steps.filter(step => step.state !== 'done');
  const completed = steps.filter(step => step.state === 'done');
  const destinations = [
    { section: 'agenda' as const, title: 'Ouvrir l’agenda', symbol: 'calendar' as const },
    { section: 'eleves' as const, title: 'Consulter les élèves', symbol: 'users' as const },
    { section: 'trajets' as const, title: 'Revoir les trajets', symbol: 'route' as const },
  ];

  return (
    <div className="section-stack">
      <SectionHeading title="Vue d’ensemble" actions={school.status !== 'ACTIVE' && <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge>} />
      <nav className="workspace-links" aria-label="Travail quotidien">
        {destinations.map(item => <a key={item.section} className="workspace-link" href={`/app/gestion/${schoolId}/${item.section}`}
          onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(item.section); }}>
          <Symbol kind={item.symbol} /><strong>{item.title}</strong><Symbol kind="back" bare />
        </a>)}
      </nav>
      <div className="overview-grid">
        <section className="panel" aria-labelledby="steps-title">
          <div className="panel-head">
            <h2 id="steps-title" className="section-title">Préparation de l’école</h2>
            <button type="button" className="button quiet" onClick={loaded.reload} disabled={loaded.status === 'loading'}><Symbol kind="refresh" bare />Actualiser</button>
          </div>
          {loaded.status === 'loading' && !data && <p className="loading" role="status"><span className="spinner" aria-hidden="true" />Vérification de la préparation de l’école…</p>}
          {failures > 0 && <Notice tone="warning" title="Certaines informations sont indisponibles" live={false}>
            <p>{failures === 1 ? 'Une lecture' : `${failures} lectures`} n’a pas abouti : l’état correspondant est marqué « À vérifier ».</p></Notice>}
          <ol className="step-list">
            {remaining.map(step => <li key={step.title} className={`step ${step.state}`}>
              <StepBadge state={step.state} />
              <div className="row-text">
                <h3 className="row-title">{step.title}</h3>
                {step.state === 'blocked' && <p className="row-meta">{step.detail}</p>}
              </div>
              <button type="button" className={next === step ? 'button primary' : 'button quiet'} onClick={() => navigate(step.section)}>{step.action}</button>
            </li>)}
          </ol>
          {completed.length > 0 && <details className="completed-steps">
            <summary>{completed.length} {completed.length === 1 ? 'étape terminée' : 'étapes terminées'}</summary>
            <ul>{completed.map(step => <li key={step.title}><Symbol kind="check" bare /><span>{step.title}</span></li>)}</ul>
          </details>}
        </section>
        <div className="section-stack">
          <section className="panel" aria-labelledby="school-facts">
            <h2 id="school-facts" className="section-title">Coordonnées</h2>
            <Facts items={[
              ['E-mail', school.contactEmail || 'Non renseigné'],
              ['Téléphone', school.contactPhone || 'Non renseigné'],
              ['Fuseau horaire', school.timeZone],
            ]} />
            <button type="button" className="button quiet" onClick={() => navigate('configuration')}><Symbol kind="edit" bare />Modifier les coordonnées</button>
          </section>
          {data?.readiness?.ok && <section className="panel" aria-labelledby="capabilities-title">
            <h2 id="capabilities-title" className="section-title">Fonctions de l’école</h2>
            <ul className="plain-list capability-list">{data.readiness.value.capabilities.map(capability => <li key={capability.capability}>
              <span className={`step-state${capability.ready ? '' : ' warning'}`}><Symbol kind={capability.ready ? 'check' : 'alert'} bare /><span className="visually-hidden">{capability.ready ? 'Disponible' : 'À configurer'}</span></span>
              <div className="row-text"><span className="row-title">{capabilityTitle(capability.capability)}</span>
              {!capability.ready && capability.blockers[0] && <span className="row-meta">{capability.blockers[capability.blockers.length - 1]!.message}</span>}</div>
            </li>)}</ul>
          </section>}
        </div>
      </div>
    </div>
  );
}

function StepBadge({ state }: { state: StepState }) {
  const label = { done: 'Terminé', todo: 'À faire', blocked: 'Prérequis', unknown: 'À vérifier' }[state];
  return <span className={`step-state${state === 'blocked' ? ' warning' : ''}`}>
    <Symbol kind={state === 'done' ? 'check' : state === 'blocked' ? 'alert' : state === 'unknown' ? 'info' : 'dot'} bare />
    <span className="visually-hidden">{label}</span>
  </span>;
}
