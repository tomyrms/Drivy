import { describe, expect, test } from 'vitest';
import { rebaseConfirmedDraft } from '../client/console/draft-model.js';

/**
 * #106 critère « réconcilier au niveau des champs, conserver modifications concurrentes et intentions suivantes » :
 * l'enchaînement de deux envois sur un même brouillon, avec une modification externe d'un troisième champ et des réponses
 * qui arrivent dans l'ordre inverse. Chaque envoi rebase le brouillon courant sur ce que l'école a confirmé.
 */
type Draft = { name: string; email: string; phone: string; notes: { title: string; body: string } };
const base: Draft = { name: 'École A', email: 'a@example.invalid', phone: '', notes: { title: 'Titre', body: 'Texte' } };
const with_ = (draft: Draft, patch: Partial<Draft>): Draft => ({ ...draft, ...patch });

describe('Deux intentions successives sur un même brouillon', () => {
  test('A confirmé pendant la saisie de B : B est gardée, la modification externe est adoptée, aucun conflit', () => {
    const sentA = with_(base, { name: 'École A2' });
    const typedB = with_(sentA, { email: 'b@example.invalid' });
    const confirmedA = with_(sentA, { phone: '0102030405' }); // l'école a changé un troisième champ entre-temps

    const afterA = rebaseConfirmedDraft(sentA, confirmedA, typedB);
    expect(afterA.value).toEqual(with_(confirmedA, { email: 'b@example.invalid' }));
    expect(afterA.conflicts).toEqual([]);

    const sentB = afterA.value, confirmedB = afterA.value;
    const afterB = rebaseConfirmedDraft(sentB, confirmedB, afterA.value);
    expect(afterB.value).toEqual(confirmedB);
    expect(afterB.conflicts).toEqual([]);
  });

  test('la réponse de A arrive après celle de B : ni la saisie de B ni la modification externe ne sont perdues', () => {
    const sentA = with_(base, { name: 'École A2' });
    const sentB = with_(sentA, { email: 'b@example.invalid' });
    const external = { phone: '0102030405' };
    const confirmedB = with_(sentB, external); // l'école a appliqué A puis B, et la modification externe
    const confirmedA = with_(sentA, external); // la réponse de A reflète l'état après A seulement

    const afterB = rebaseConfirmedDraft(sentB, confirmedB, sentB);
    expect(afterB.value).toEqual(confirmedB);

    const afterLateA = rebaseConfirmedDraft(sentA, confirmedA, afterB.value);
    expect(afterLateA.value).toEqual(confirmedB);
    expect(afterLateA.conflicts).toEqual([]);
  });

  test('un même champ changé des deux côtés reste local, nommé, et seul ce chemin est signalé', () => {
    const sentA = with_(base, { notes: { title: 'Titre A', body: 'Texte' } });
    const typed = with_(sentA, { notes: { title: 'Titre local', body: 'Texte local' } });
    const confirmed = with_(sentA, { notes: { title: 'Titre école', body: 'Texte' } });

    const result = rebaseConfirmedDraft(sentA, confirmed, typed);
    expect(result.conflicts).toEqual(['notes.title']);
    expect(result.value.notes).toEqual({ title: 'Titre local', body: 'Texte local' });
  });

  test('l\'envoi suivant d\'un champ encore en conflit ne ressuscite pas la valeur de l\'école', () => {
    const sentA = with_(base, { name: 'Nom A' });
    const typed = with_(sentA, { name: 'Nom local' });
    const confirmed = with_(sentA, { name: 'Nom école' });
    const first = rebaseConfirmedDraft(sentA, confirmed, typed);
    expect(first.value.name).toBe('Nom local');

    // La personne renvoie son propre nom : la confirmation suivante le reprend, sans nouveau conflit.
    const resent = first.value, confirmedAgain = with_(resent, { name: 'Nom local' });
    const second = rebaseConfirmedDraft(resent, confirmedAgain, first.value);
    expect(second.value.name).toBe('Nom local');
    expect(second.conflicts).toEqual([]);
  });
});
