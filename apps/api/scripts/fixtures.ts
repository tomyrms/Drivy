import type { Pool } from 'pg';

export const fixtureIds = {
  schoolA: '10000000-0000-4000-8000-000000000001', schoolB: '10000000-0000-4000-8000-000000000002',
  admin: '20000000-0000-4000-8000-000000000001', instructor: '20000000-0000-4000-8000-000000000002',
  alice: '20000000-0000-4000-8000-000000000003', bob: '20000000-0000-4000-8000-000000000004',
  otherInstructor: '20000000-0000-4000-8000-000000000005', foreign: '20000000-0000-4000-8000-000000000006',
  adminMember: '30000000-0000-4000-8000-000000000001', instructorMember: '30000000-0000-4000-8000-000000000002',
  aliceMember: '30000000-0000-4000-8000-000000000003', bobMember: '30000000-0000-4000-8000-000000000004',
  otherInstructorMember: '30000000-0000-4000-8000-000000000005', foreignMember: '30000000-0000-4000-8000-000000000006',
  instructorMemberB: '30000000-0000-4000-8000-000000000007',
  aliceLearner: '40000000-0000-4000-8000-000000000001', bobLearner: '40000000-0000-4000-8000-000000000002',
  foreignLearner: '40000000-0000-4000-8000-000000000003',
  offeringA: '50000000-0000-4000-8000-000000000001', offeringB: '50000000-0000-4000-8000-000000000002',
  aliceTraining: '60000000-0000-4000-8000-000000000001', bobTraining: '60000000-0000-4000-8000-000000000002',
  foreignTraining: '60000000-0000-4000-8000-000000000003', assignment: '70000000-0000-4000-8000-000000000001'
} as const;

/** Données entièrement fictives. Cette fonction ne crée aucun jeton ni fournisseur d'identité. */
export async function seedFixtures(pool: Pool, issuer: string): Promise<void> {
  const id = fixtureIds;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [personId, subject, name] of [
      [id.admin,'demo-admin','Camille Administration'], [id.instructor,'demo-instructor','Alex Moniteur'],
      [id.alice,'demo-alice','Alice Exemple'], [id.bob,'demo-bob','Noé Exemple'],
      [id.otherInstructor,'demo-other-instructor','Lou Monitrice'], [id.foreign,'demo-foreign','Sacha Autre-école']
    ]) {
      await client.query('INSERT INTO drivy.person(id,display_name) VALUES ($1,$2) ON CONFLICT DO NOTHING', [personId,name]);
      await client.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [issuer,subject,personId]);
    }
    for (const [schoolId, name] of [[id.schoolA,'Auto-école Horizon · Démonstration'],[id.schoolB,'Auto-école Rivage · Démonstration']]) {
      await client.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES ($1,$2,'ACTIVE','contact@example.invalid') ON CONFLICT DO NOTHING", [schoolId,name]);
    }
    for (const [memberId, schoolId, personId, roles] of [
      [id.adminMember,id.schoolA,id.admin,['ADMIN']], [id.instructorMember,id.schoolA,id.instructor,['INSTRUCTOR']],
      [id.aliceMember,id.schoolA,id.alice,['LEARNER']], [id.bobMember,id.schoolA,id.bob,['LEARNER']],
      [id.otherInstructorMember,id.schoolA,id.otherInstructor,['INSTRUCTOR']],
      [id.foreignMember,id.schoolB,id.foreign,['LEARNER']], [id.instructorMemberB,id.schoolB,id.instructor,['ADMIN']]
    ]) await client.query('INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING', [memberId,schoolId,personId,roles]);
    for (const [learnerId,schoolId,personId,name] of [
      [id.aliceLearner,id.schoolA,id.alice,'Alice Exemple'], [id.bobLearner,id.schoolA,id.bob,'Noé Exemple'],
      [id.foreignLearner,id.schoolB,id.foreign,'Sacha Autre-école']
    ]) await client.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name,contact_email,created_at) VALUES ($1,$2,$3,$4,'eleve@example.invalid','2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING", [learnerId,schoolId,personId,name]);
    for (const [offeringId,schoolId] of [[id.offeringA,id.schoolA],[id.offeringB,id.schoolB]]) {
      await client.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES ($1,$2,'category-b','B',1) ON CONFLICT DO NOTHING", [offeringId,schoolId]);
    }
    for (const [trainingId,schoolId,learnerId,offeringId] of [
      [id.aliceTraining,id.schoolA,id.aliceLearner,id.offeringA], [id.bobTraining,id.schoolA,id.bobLearner,id.offeringA],
      [id.foreignTraining,id.schoolB,id.foreignLearner,id.offeringB]
    ]) await client.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on,created_at) VALUES ($1,$2,$3,$4,'category-b','ACTIVE','2026-01-01','2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING", [trainingId,schoolId,learnerId,offeringId]);
    await client.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES ($1,$2,$3,$4,'2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING", [id.assignment,id.schoolA,id.aliceTraining,id.instructorMember]);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}
