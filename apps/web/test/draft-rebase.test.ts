import { describe, expect, test } from 'vitest';
import { rebaseConfirmedDraft } from '../client/console/draft-model.js';

type Identity = { name: string; contactEmail: string; contactPhone: string };
type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };
type Content = { identity: Identity; privacy: PolicyText; selectedSections: string[] };

const content = (name = 'École A', email = 'ecole@example.invalid'): Content => ({
  identity: { name, contactEmail: email, contactPhone: '' },
  privacy: { noticeText: 'Information locale.', retentionText: 'Conservation locale.', contactEmail: 'donnees@example.invalid' },
  selectedSections: ['IDENTITY', 'PRIVACY'],
});

describe('Rebase d’un brouillon confirmé (#106, #123)', () => {
  test('adopte la normalisation serveur sur un champ non retouché et garde la saisie postérieure sur un autre', () => {
    const sent = content(' École A ', 'ecole@example.invalid');
    const confirmed = content('École A', 'ecole@example.invalid');
    const current = { ...sent, identity: { ...sent.identity, contactEmail: 'nouveau@example.invalid' } };

    const result = rebaseConfirmedDraft(sent, confirmed, current);

    expect(result.value).toEqual({ ...confirmed, identity: { ...confirmed.identity, contactEmail: 'nouveau@example.invalid' } });
    expect(result.conflicts).toEqual([]);
  });

  test('garde la saisie locale seule quand l’école n’a rien changé sur ce champ', () => {
    const sent = content('École A');
    const confirmed = content('École A');
    const current = { ...sent, privacy: { ...sent.privacy, noticeText: 'Texte encore en cours.' } };

    const result = rebaseConfirmedDraft(sent, confirmed, current);

    expect(result.value.privacy.noticeText).toBe('Texte encore en cours.');
    expect(result.value.identity).toEqual(confirmed.identity);
    expect(result.conflicts).toEqual([]);
  });

  test('signale le même champ changé des deux côtés et ne l’écrase pas', () => {
    const sent = content('École A', 'ecole@example.invalid');
    const confirmed = content('École A', 'normalise@example.invalid');
    const current = { ...sent, identity: { ...sent.identity, contactEmail: 'local@example.invalid' } };

    const result = rebaseConfirmedDraft(sent, confirmed, current);

    expect(result.value.identity.contactEmail).toBe('local@example.invalid');
    expect(result.conflicts).toEqual(['identity.contactEmail']);
  });

  test('fusionne les objets imbriqués sans perdre les champs disjoints ni les tableaux locaux modifiés', () => {
    const sent = content();
    const confirmed = { ...content(), identity: { ...sent.identity, name: 'École normalisée' } };
    const current = { ...sent, identity: { ...sent.identity, contactEmail: 'local@example.invalid' }, selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE'] };

    const result = rebaseConfirmedDraft(sent, confirmed, current);

    expect(result.value.identity).toEqual({ name: 'École normalisée', contactEmail: 'local@example.invalid', contactPhone: '' });
    expect(result.value.privacy).toEqual(confirmed.privacy);
    expect(result.value.selectedSections).toEqual(['IDENTITY', 'PRIVACY', 'PROFILE']);
    expect(result.conflicts).toEqual([]);
  });

  test('un tableau changé des deux côtés reste local et signalé au lieu d’être fusionné au hasard', () => {
    const sent = content();
    const confirmed = { ...content(), selectedSections: ['IDENTITY'] };
    const current = { ...sent, selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE'] };

    const result = rebaseConfirmedDraft(sent, confirmed, current);

    expect(result.value.selectedSections).toEqual(['IDENTITY', 'PRIVACY', 'PROFILE']);
    expect(result.conflicts).toEqual(['selectedSections']);
  });

  test('sans changement local, la valeur confirmée est adoptée telle quelle', () => {
    const sent = content('École A');
    const confirmed = content('École A', 'normalise@example.invalid');

    const result = rebaseConfirmedDraft(sent, confirmed, sent);

    expect(result.value).toEqual(confirmed);
    expect(result.conflicts).toEqual([]);
  });
});
