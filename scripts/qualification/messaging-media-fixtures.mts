import type { Pool } from 'pg';
import { fixtureIds } from '../../apps/api/scripts/fixtures.js';

/**
 * Identités et école strictement dédiées au scénario média réel (#97, Q97).
 *
 * Ces valeurs sont **syntétiques** et figées : le test Swift les rejoue à l'identique pour
 * prouver la readiness du relais jetable. Aucune identité canonique du harnais texte n'est
 * réutilisée : le test historique exige que son élève (`fixtureIds.alice`) soit sans clés au
 * début, donc nos deux comptes média vivent dans une école distincte, avec leurs propres
 * relations (formation + affectation) qui autorisent la conversation privée.
 *
 * Ce module n'est importé que par le bootstrap de qualification (NODE_ENV=test, opt-in de
 * reset, base `drivy_test` loopback, TLS éphémère) : il n'est jamais chargé par la
 * composition déployée.
 */
export const mediaFixtureIds = {
  school: '1a000000-0000-4000-8000-000000000097',
  foreignSchool: '1a000000-0000-4000-8000-000000000098',
  instructor: '2a000000-0000-4000-8000-000000000097',
  learner: '2a000000-0000-4000-8000-000000000098',
  foreign: '2a000000-0000-4000-8000-000000000099',
  instructorMember: '3a000000-0000-4000-8000-000000000097',
  learnerMember: '3a000000-0000-4000-8000-000000000098',
  foreignMember: '3a000000-0000-4000-8000-000000000099',
  learnerProfile: '4a000000-0000-4000-8000-000000000097',
  offering: '5a000000-0000-4000-8000-000000000097',
  foreignOffering: '5a000000-0000-4000-8000-000000000098',
  training: '6a000000-0000-4000-8000-000000000097',
  assignment: '7a000000-0000-4000-8000-000000000097'
} as const;

/** Sujets Bearer propres à la fixture média : jamais ajoutés à l'authentification de production. */
export const mediaFixtureSubjects = {
  instructor: 'media-fixture-instructor',
  learner: 'media-fixture-learner',
  foreign: 'media-fixture-foreign'
} as const;

/** Nom de fixture publié par `/qualification/ready` pour la partie média. */
export const mediaReadinessFixture = 'drivy-messaging-media-v1';

/**
 * Colisions entre l'école média et le harnais canonique : doit toujours être vide.
 * Pure, donc testable sans base ni réseau.
 */
export function mediaFixtureCollisions(): string[] {
  const canonical = new Map<string, string>(Object.entries(fixtureIds).map(([key, value]) => [value, key]));
  return Object.entries(mediaFixtureIds)
    .filter(([, value]) => canonical.has(value))
    .map(([key, value]) => `${key}=${canonical.get(value)}`);
}

/**
 * Sème l'école média et ses deux comptes. Idempotent (`ON CONFLICT DO NOTHING`), sans
 * `DELETE`, `TRUNCATE`, mise à jour de masse ni effacement d'un autre scénario.
 *
 * L'émetteur doit être l'origine synthétique `.invalid` du relais : un domaine réel est
 * refusé avant toute écriture, sans répéter la valeur fournie.
 */
export async function seedMessagingMediaFixtures(pool: Pool, issuer: string): Promise<void> {
  if (!/^https:\/\/[a-z0-9.-]+\.invalid$/.test(issuer)) throw new Error('MEDIA_FIXTURE_ISSUER_REQUIRED');
  if (mediaFixtureCollisions().length > 0) throw new Error('MEDIA_FIXTURE_ID_COLLISION');
  const id = mediaFixtureIds;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [personId, subject, name] of [
      [id.instructor, mediaFixtureSubjects.instructor, 'Moniteur Média · Synthétique'],
      [id.learner, mediaFixtureSubjects.learner, 'Élève Média · Synthétique'],
      [id.foreign, mediaFixtureSubjects.foreign, 'Compte Étranger · Synthétique']
    ]) {
      await client.query('INSERT INTO drivy.person(id,display_name) VALUES ($1,$2) ON CONFLICT DO NOTHING', [personId, name]);
      await client.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',
        [issuer, subject, personId]);
    }
    for (const [schoolId, name] of [
      [id.school, 'Auto-école Média · Qualification'],
      [id.foreignSchool, 'Auto-école Étrangère · Qualification']
    ]) {
      await client.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES ($1,$2,'ACTIVE','media@example.invalid') ON CONFLICT DO NOTHING",
        [schoolId, name]);
    }
    for (const [memberId, schoolId, personId, roles] of [
      [id.instructorMember, id.school, id.instructor, ['INSTRUCTOR']],
      [id.learnerMember, id.school, id.learner, ['LEARNER']],
      [id.foreignMember, id.foreignSchool, id.foreign, ['LEARNER']]
    ]) {
      await client.query('INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING',
        [memberId, schoolId, personId, roles]);
    }
    // Le dossier de l'élève suit la forme courante (identité sur `drivy.person`) ou l'ancienne,
    // exactement comme les fixtures canoniques : aucune migration n'est supposée.
    const legacyDossier = (await client.query(
      "SELECT 1 FROM information_schema.columns WHERE table_schema='drivy' AND table_name='learner_profile' AND column_name='display_name'"
    )).rowCount !== 0;
    if (legacyDossier) {
      await client.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name,contact_email,created_at) VALUES ($1,$2,$3,'Élève Média · Synthétique','media@example.invalid','2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING",
        [id.learnerProfile, id.school, id.learner]);
    } else {
      await client.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,created_at) VALUES ($1,$2,$3,'2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING",
        [id.learnerProfile, id.school, id.learner]);
      await client.query("UPDATE drivy.person SET contact_email='media@example.invalid' WHERE id=$1 AND contact_email IS NULL", [id.learner]);
    }
    for (const [offeringId, schoolId] of [[id.offering, id.school], [id.foreignOffering, id.foreignSchool]]) {
      await client.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES ($1,$2,'category-b','B',1) ON CONFLICT DO NOTHING",
        [offeringId, schoolId]);
    }
    await client.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on,created_at) VALUES ($1,$2,$3,$4,'category-b','ACTIVE','2026-01-01','2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING",
      [id.training, id.school, id.learnerProfile, id.offering]);
    await client.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES ($1,$2,$3,$4,'2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING",
      [id.assignment, id.school, id.training, id.instructorMember]);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
