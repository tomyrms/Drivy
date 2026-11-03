import { describe, expect, test } from 'vitest';
import { reviewGate, type ReviewGateInput } from './setup-review-gate';

const base: ReviewGateInput = {
  step: 'REVIEW', requested: false, synced: true, blocked: false, reviewing: false,
  preview: null, acknowledged: false, readFailure: false, phase: 'idle',
};

describe('Revue de la préparation (#123) : relecture explicite et activation', () => {
  test('un chargement qui retombe sur le résumé laisse « Vérifier la préparation » utilisable', () => {
    // Recette navigateur : reprise du brouillon confirmé, la page s'ouvre sur le résumé sans geste de navigation.
    const gate = reviewGate(base);
    expect(gate.read).toBe(false);
    expect(gate.verify).toBe(true);
    expect(gate.reason).toBeNull();
  });

  test('une navigation ou un enregistrement vers le résumé déclenche la lecture, une fois le brouillon synchronisé', () => {
    expect(reviewGate({ ...base, requested: true })).toMatchObject({ read: true, verify: false });
    // Envoi encore en vol : on attend la confirmation, le bouton reste indisponible avec sa raison.
    expect(reviewGate({ ...base, requested: true, synced: false, phase: 'saving' }))
      .toMatchObject({ read: false, verify: false, activate: false, reason: 'Enregistrement en cours.' });
    // Confirmation arrivée : la lecture part avec la version que l'école détient.
    expect(reviewGate({ ...base, requested: true, phase: 'idle' })).toMatchObject({ read: true });
  });

  test('la revue mesure le brouillon détenu par l’école, jamais l’interface seule', () => {
    expect(reviewGate({ ...base, synced: false, phase: 'idle' })).toMatchObject({ verify: false, reason: 'Modifications non enregistrées.' });
    expect(reviewGate({ ...base, synced: false, phase: 'saving' })).toMatchObject({ verify: false, reason: 'Enregistrement en cours.' });
    expect(reviewGate({ ...base, synced: false, phase: 'unknown' })).toMatchObject({ verify: false, reason: 'Enregistrement à vérifier.' });
    expect(reviewGate({ ...base, synced: false, phase: 'conflict' })).toMatchObject({ verify: false, reason: 'La préparation a changé à l’école : relisez l’étape.' });
    expect(reviewGate({ ...base, synced: false, phase: 'refused' })).toMatchObject({ verify: false, reason: 'Modifications non enregistrées.' });
  });

  test('rien ne se lit ni ne s’active pendant une lecture, une demande suivie ou une adoption', () => {
    expect(reviewGate({ ...base, requested: true, reviewing: true })).toMatchObject({ read: false, verify: false });
    expect(reviewGate({ ...base, requested: true, blocked: true })).toMatchObject({ read: false, verify: false });
    expect(reviewGate({ ...base, readFailure: true, requested: true })).toMatchObject({ read: false, verify: true });
    expect(reviewGate({ ...base, preview: { ready: true }, requested: true })).toMatchObject({ read: false, verify: false, activate: false });
    expect(reviewGate({ ...base, preview: { ready: true }, acknowledged: true })).toMatchObject({ activate: true });
    expect(reviewGate({ ...base, preview: { ready: false }, acknowledged: true })).toMatchObject({ activate: false });
  });

  test('hors du résumé, aucun contrôle de revue ne s’ouvre', () => {
    const gate = reviewGate({ ...base, step: 'PRICING', requested: true, preview: { ready: true }, acknowledged: true });
    expect(gate).toMatchObject({ read: false, verify: false, activate: false });
  });
});
