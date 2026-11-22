import { renderToStaticMarkup } from 'react-dom/server';
import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { ConsoleContext, type ConsoleContextValue } from '../client/console/context';
import type { Member } from '../client/protocol';
import type { ObservationPreferences, ObservationThemes } from '../client/school-api';
import { PersonalEditor } from '../client/portal/account/signals-preferences-page';
import { SignalsEditor } from '../client/portal/signals/signals-page';

/**
 * Premier affichage des deux destinations, pour chaque rôle et chaque politique d'école : ce que la personne voit et ce qu'elle peut déclencher.
 * Le serveur reste seul juge ; ces rendus prouvent que l'écran ne propose rien que la matrice des droits exclut.
 */
const schoolId = randomUUID();
const personId = randomUUID();
const keys = ['observation', 'speed', 'give-way', 'placement'];
const membership = (roles: Member['roles']): Member => ({ membershipId: randomUUID(), schoolId, schoolName: 'École du Léman', roles, grants: [], accessEpoch: 1 });
const context = (roles: Member['roles']): ConsoleContextValue => {
  const member = membership(roles);
  return { schoolId, me: { personId, displayName: 'Luc Martin', version: 1, memberships: [member] }, membership: member,
    school: { id: schoolId, schoolId, version: 1, name: 'École du Léman', timeZone: 'Europe/Zurich', status: 'ACTIVE', contactEmail: 'ecole@example.test', contactPhone: null,
      configurationVersion: 1, modules: { gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false } } as ConsoleContextValue['school'],
    canConfigureCatalog: false, drafts: new Map(), reloadSchool: async () => undefined, csrf: () => 'csrf', refreshCsrf: async () => 'csrf', navigate: () => undefined, login: () => undefined };
};
const preferences = (overrides: Partial<ObservationPreferences> = {}): ObservationPreferences => ({
  id: personId, schoolId, version: 1, personalizationAllowed: true, orderCustomized: false, visibilityCustomized: false, mode: 'MANUAL',
  themes: keys.map((key, index) => ({ key, title: `Thème ${key}`, visible: true, defaultVisible: true, defaultPosition: index, schoolVisible: true, visibilityEditable: overrides.personalizationAllowed ?? true })),
  palette: keys, rankedOn: null, learning: { generation: 0, since: null }, adoption: null, ...overrides,
});
const personal = (roles: Member['roles'], data: ObservationPreferences) =>
  renderToStaticMarkup(<ConsoleContext.Provider value={context(roles)}><PersonalEditor data={data} reload={() => undefined} /></ConsoleContext.Provider>);

describe('Mon compte › Préférences › Signalements : matrice des rôles et de la politique', () => {
  const reset = 'Rétablir l’ordre et la visibilité';
  const learning = 'Recommencer l’apprentissage du classement intelligent';

  it('moniteur, école libre : ordre et affichage modifiables, retour à la référence proposé', () => {
    const html = personal(['INSTRUCTOR'], preferences());
    expect(html).toContain('role="switch"');
    expect(html).toContain('Déplacer Thème observation');
    expect(html).toContain(reset);
    expect(html).toContain(learning);
    expect(html).not.toContain('Géré par l’école');
  });

  it('moniteur, affichage imposé : ordre modifiable, affichage en lecture seule « Géré par l’école », pas de retour à la référence', () => {
    const html = personal(['INSTRUCTOR'], preferences({ personalizationAllowed: false }));
    expect(html).toContain('Géré par l’école');
    expect(html).toContain('Déplacer Thème observation');
    expect(html).toContain('Monter Thème speed');
    // Un seul interrupteur reste : le classement intelligent. Aucun interrupteur d'affichage par thème.
    expect(html.match(/role="switch"/g)).toHaveLength(1);
    expect(html).not.toContain(reset);
    // L'apprentissage se recommence même quand l'affichage est imposé.
    expect(html).toContain(learning);
  });

  it('administrateur, affichage imposé : le retour à la référence reste proposé', () => {
    const html = personal(['ADMIN'], preferences({ personalizationAllowed: false }));
    expect(html).toContain(reset);
    expect(html).toContain('Géré par l’école');
    expect(html).toContain(learning);
  });

  it('administrateur et moniteur, école libre : tout est proposé', () => {
    const html = personal(['ADMIN', 'INSTRUCTOR'], preferences());
    expect(html).toContain(reset);
    expect(html.match(/role="switch"/g)?.length).toBe(keys.length + 1);
  });

  it('un thème masqué par l’école est dit « Masqué » quand l’affichage est imposé', () => {
    const data = preferences({ personalizationAllowed: false });
    const html = personal(['INSTRUCTOR'], { ...data, themes: data.themes.map(theme => theme.key === 'speed' ? { ...theme, visible: false, schoolVisible: false } : theme) });
    expect(html).toContain('Masqué');
  });

  it('le nom de l’école ouverte est affiché, pas d’autre texte explicatif', () => {
    const html = personal(['INSTRUCTOR'], preferences());
    expect(html).toContain('École du Léman');
    expect(html).toContain('Signalements');
  });

  it('plusieurs écoles et rien d’enregistré : le choix de départ est proposé une fois', () => {
    const candidate = (name: string) => ({ schoolId: randomUUID(), schoolName: name, mode: 'MANUAL' as const, themes: keys.map(key => ({ key, visible: true })) });
    const html = personal(['INSTRUCTOR'], preferences({ adoption: { candidates: [candidate('École A'), candidate('École B')] } }));
    expect(html).toContain('Configuration de départ');
    expect(html).toContain('Reprendre celle de École A');
    expect(html).toContain('Reprendre celle de École B');
    expect(personal(['INSTRUCTOR'], preferences())).not.toContain('Configuration de départ');
  });

  it('rien à enregistrer au premier affichage : pas de barre d’enregistrement', () => {
    expect(personal(['INSTRUCTOR'], preferences())).not.toContain('signals-savebar');
  });
});

describe('Signalements de l’école (administration)', () => {
  const settings = (overrides: Partial<ObservationThemes> = {}): ObservationThemes => ({
    id: schoolId, schoolId, version: 1, canManage: true, personalizationAllowed: false,
    themes: keys.map((key, index) => ({ key, title: `Thème ${key}`, visible: true, defaultVisible: true, defaultPosition: index })), ...overrides,
  });
  const school = (data: ObservationThemes) =>
    renderToStaticMarkup(<ConsoleContext.Provider value={context(['ADMIN'])}><SignalsEditor data={data} reload={() => undefined} /></ConsoleContext.Provider>);

  it('l’administrateur voit la case d’autorisation, décochée par défaut, et le titre de l’école', () => {
    const html = school(settings());
    expect(html).toContain('Signalements de l’école');
    expect(html).toContain('Autoriser les moniteurs à personnaliser les signalements');
    expect(html).toMatch(/role="checkbox"[^>]*aria-checked="false"/);
    expect(html).toContain('Valeurs Drivy');
  });

  it('la case reflète la politique enregistrée', () => {
    expect(school(settings({ personalizationAllowed: true }))).toMatch(/role="checkbox"[^>]*aria-checked="true"/);
  });

  it('sans droit de gestion : lecture seule, ni case ni enregistrement', () => {
    const html = school(settings({ canManage: false }));
    expect(html).toContain('Lecture seule');
    expect(html).not.toContain('Autoriser les moniteurs');
    expect(html).not.toContain('Enregistrer pour l’école');
  });
});
