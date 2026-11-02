import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import { matchSchoolRoute } from '../server/school-routes.js';

/**
 * La passerelle web ne relaie que des routes nommées. Les examens (#54) et les demandes de l'élève (#52) sont arrivés avec leur API
 * mais sans leur entrée ici : l'onglet Examens répondait 404 en production alors que l'aperçu synthétique, qui court-circuite la passerelle,
 * fonctionnait. Ce test garde l'écart : toute route utilisée par le web doit être relayée, toute route réservée à l'app native ne doit pas l'être.
 */
const school = randomUUID(), other = randomUUID();
const at = (suffix: string) => `/schools/${school}/${suffix}`;

describe('Examens : routes relayées par la passerelle', () => {
  test('lecture d’une formation, prévision, modification, report, résultat et historique', () => {
    expect(matchSchoolRoute('GET', at(`trainings/${other}/exams`), '')?.path).toBe(`/v1/schools/${school}/trainings/${other}/exams`);
    expect(matchSchoolRoute('POST', at(`trainings/${other}/exams`), '')?.route.bodyLimit).toBe(4_096);
    for (const action of ['update', 'postpone', 'result']) {
      const match = matchSchoolRoute('POST', at(`exams/${other}/${action}`), '');
      expect(match?.route.ifMatch, action).toBe(true);
      expect(match?.path).toBe(`/v1/schools/${school}/exams/${other}/${action}`);
    }
    expect(matchSchoolRoute('GET', at(`exams/${other}/revisions`), '')).toBeDefined();
  });

  test('la liste transversale n’accepte que ses deux filtres', () => {
    expect(matchSchoolRoute('GET', at('exams'), '?filter=PENDING_RESULT')?.query).toBe('?filter=PENDING_RESULT');
    expect(matchSchoolRoute('GET', at('exams'), '?filter=UPCOMING')).toBeDefined();
    expect(matchSchoolRoute('GET', at('exams'), '?filter=ALL')).toBeUndefined();
    expect(matchSchoolRoute('GET', at('exams'), '?filter=UPCOMING&filter=PENDING_RESULT')).toBeUndefined();
    expect(matchSchoolRoute('GET', at('exams'), '?learnerId=' + other)).toBeUndefined();
  });

  test('rien d’autre n’est ouvert : ni méthode inconnue, ni identifiant qui n’est pas un UUID', () => {
    expect(matchSchoolRoute('PUT', at(`exams/${other}/result`), '')).toBeUndefined();
    expect(matchSchoolRoute('DELETE', at(`exams/${other}`), '')).toBeUndefined();
    expect(matchSchoolRoute('GET', at('trainings/not-a-uuid/exams'), '')).toBeUndefined();
    expect(matchSchoolRoute('POST', at(`exams/${other}/delete`), '')).toBeUndefined();
  });
});

describe('Demandes de l’élève : routes relayées par la passerelle', () => {
  test('le personnel lit les demandes d’une leçon, la boîte, et refuse avec la version', () => {
    expect(matchSchoolRoute('GET', at(`lessons/${other}/change-requests`), '')?.path).toBe(`/v1/schools/${school}/lessons/${other}/change-requests`);
    expect(matchSchoolRoute('GET', at('lesson-change-requests'), '')).toBeDefined();
    const refuse = matchSchoolRoute('POST', at(`lesson-change-requests/${other}/refuse`), '');
    expect(refuse?.route.ifMatch).toBe(true);
    expect(refuse?.route.bodyLimit).toBe(2_048);
  });

  test('créer et retirer une demande restent réservés à l’app native, jamais relayés par le web', () => {
    expect(matchSchoolRoute('POST', at(`lessons/${other}/change-requests`), '')).toBeUndefined();
    expect(matchSchoolRoute('POST', at(`lesson-change-requests/${other}/withdraw`), '')).toBeUndefined();
  });

  test('accepter reste un déplacement ou une annulation existants', () => {
    expect(matchSchoolRoute('POST', at(`lessons/${other}/move`), '')?.route.ifMatch).toBe(true);
    expect(matchSchoolRoute('POST', at(`lessons/${other}/cancel`), '')?.route.ifMatch).toBe(true);
  });
});
