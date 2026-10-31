import { createHash, randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Pool, type PoolClient } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { migrate, migrationFilePattern } from '../scripts/migrations.js';
import { canRead, eligibleContacts, findOrCreatePrivate, sendEnvelope } from '../src/messaging.js';
import { freshDatabase, id, prepareSchool } from './support/harness.js';

const coursePattern = /^04[2-6]_|^20261025_messaging_mention_push|^20261031_messaging_message_push/;
const migrationDirectory = new URL('../migrations/', import.meta.url);
const actor = { schoolId: id.schoolA, personId: id.instructor, membershipId: id.instructorMember };

describe('course upgrade after the dated production messaging migrations', () => {
  let pool: Pool;
  let migrationPool: Pool;
  beforeAll(async () => {
    pool = await freshDatabase({ deferCourseMigrations: true });
    migrationPool = new Pool({ connectionString: process.env.TEST_DATABASE_URL, options: '-c role=drivy_harness_migrator' });
  });
  afterAll(async () => { await migrationPool?.end(); await pool?.end(); });

  async function asApp<T>(personId: string, membershipId: string, work: (db: PoolClient) => Promise<T>, commit = false) {
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",
        [id.schoolA, personId, membershipId]);
      const result = await work(db);
      await db.query(commit ? 'COMMIT' : 'ROLLBACK');
      return result;
    } catch (error) { await db.query('ROLLBACK'); throw error; }
    finally { db.release(); }
  }

  async function registry() {
    return (await pool.query('SELECT name,sha256,applied_at::text FROM public.drivy_migrations ORDER BY name')).rows;
  }

  async function existingData() {
    const tables = ['person', 'school', 'membership', 'learner_profile', 'training', 'instructor_assignment',
      'school_policy_version', 'lesson', 'messaging_conversation', 'messaging_member_link', 'messaging_message'];
    const rows = await Promise.all(tables.map(async table => [table,
      (await pool.query(`SELECT to_jsonb(t) AS row FROM drivy.${table} t ORDER BY to_jsonb(t)::text`)).rows] as const));
    // Compare only columns present before 042. Its new nullable course columns are checked separately.
    const reservations = (await pool.query(`SELECT id,school_id,lesson_id,resource_id,resource_role,during::text,active
      FROM drivy.reservation ORDER BY id`)).rows;
    return { tables: Object.fromEntries(rows), reservations };
  }

  async function messagingDefinitions() {
    const functions = (await pool.query(`SELECT p.oid::regprocedure::text AS signature,pg_get_functiondef(p.oid) AS definition,
      p.proacl::text AS acl,p.proowner::regrole::text AS owner,p.prosecdef,p.proconfig
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='drivy' AND p.proname LIKE 'messaging_%' AND p.proname<>'messaging_mention_enqueue' ORDER BY signature`)).rows;
    const tables = (await pool.query(`SELECT c.relname,c.relacl::text AS acl,c.relowner::regrole::text AS owner,
      c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='drivy' AND c.relname LIKE 'messaging_%' AND c.relkind='r' ORDER BY c.relname`)).rows;
    const policies = (await pool.query(`SELECT * FROM pg_policies WHERE schemaname='drivy'
      AND (tablename LIKE 'messaging_%' OR policyname LIKE 'messaging_%') ORDER BY tablename,policyname`)).rows;
    return { functions, tables, policies };
  }

  async function assertMessagingRights(conversationId: string) {
    await asApp(id.instructor, id.instructorMember, async db => {
      expect((await eligibleContacts(db, actor)).contacts.map(contact => contact.personId)).toEqual([id.alice]);
      expect(await findOrCreatePrivate(db, actor, id.alice)).toBe(conversationId);
      await canRead(db, actor, conversationId);
      const sent = await sendEnvelope(db, actor, conversationId, randomUUID(),
        { scheme: 'synthetic', keyId: 'upgrade-fixture', payload: 'AQ==' }, [], null, null, 0);
      expect(sent.sequence).toBe(2);
    });
    await asApp(id.admin, id.adminMember, async db => {
      await expect(canRead(db, { schoolId: id.schoolA, personId: id.admin, membershipId: id.adminMember }, conversationId))
        .rejects.toMatchObject({ status: 404 });
      expect((await db.query('SELECT id FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows).toEqual([]);
    });
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_harness_migrator');
      expect((await db.query('SELECT id FROM drivy.membership WHERE id=$1 FOR SHARE', [id.instructorMember])).rowCount).toBe(1);
      await expect(db.query('UPDATE drivy.membership SET status=status WHERE id=$1', [id.instructorMember]))
        .rejects.toMatchObject({ code: '42501' });
    } finally { await db.query('ROLLBACK'); db.release(); }
  }

  it('applies 042..046 after messaging without losing existing data, rights or migration hashes, then is a no-op', async () => {
    const names = (await readdir(migrationDirectory)).filter(name => migrationFilePattern.test(name)).sort();
    const courses = names.filter(name => coursePattern.test(name));
    expect(courses).toEqual(['042_collective_courses.sql', '043_course_enrollment_waitlist_cancellation.sql',
      '044_course_attendance_payment_completion.sql', '045_course_notifications.sql', '046_course_push_revalidation.sql', '20261025_messaging_mention_push.sql', '20261031_messaging_message_push.sql']);
    const beforeRegistry = await registry();
    expect(beforeRegistry.map(row => row.name)).toEqual(names.filter(name => !coursePattern.test(name)));
    expect(beforeRegistry.filter(row => /^0\d{2}_/.test(row.name))).toHaveLength(41);
    expect(beforeRegistry.filter(row => /^20261023[a-z]?_messaging_/.test(row.name))).toHaveLength(7);
    expect((await pool.query("SELECT to_regclass('drivy.course_series') AS courses")).rows).toEqual([{ courses: null }]);
    expect((await pool.query(`SELECT column_name FROM information_schema.columns WHERE table_schema='drivy'
      AND table_name='reservation' AND column_name LIKE 'course_%'`)).rows).toEqual([]);
    const owner = await migrationPool.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user');
    expect(owner.rows).toEqual([{ rolsuper: false, rolbypassrls: false }]);

    const { policy } = await prepareSchool(pool);
    const lessonId = randomUUID();
    await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,
      planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
      VALUES($1,$2,$3,$4,$5,$6,'2030-01-10T08:00:00Z','2030-01-10T08:50:00Z','Europe/Zurich','Lieu synthétique',9000,10,$7,'{}')`,
      [lessonId, id.schoolA, id.aliceTraining, id.aliceLearner, id.alice, id.instructorMember, policy]);
    await pool.query(`INSERT INTO drivy.reservation(school_id,lesson_id,resource_id,resource_role,during,active) VALUES
      ($1,$2,$3,'INSTRUCTOR',tstzrange('2030-01-10T08:00:00Z','2030-01-10T09:00:00Z','[)'),true),
      ($1,$2,$4,'LEARNER',tstzrange('2030-01-10T08:00:00Z','2030-01-10T08:50:00Z','[)'),true),
      ($1,$2,$4,'LEARNER',tstzrange('2030-01-09T08:00:00Z','2030-01-09T08:50:00Z','[)'),false)`,
      [id.schoolA, lessonId, id.instructor, id.alice]);
    const conversationId = await asApp(id.instructor, id.instructorMember, async db => {
      const conversation = await findOrCreatePrivate(db, actor, id.alice);
      const sent = await sendEnvelope(db, actor, conversation, randomUUID(),
        { scheme: 'synthetic', keyId: 'upgrade-fixture', payload: 'AA==' }, [], null, null, 0);
      expect(sent.sequence).toBe(1);
      return conversation;
    }, true);
    await assertMessagingRights(conversationId);
    const beforeData = await existingData();
    expect(beforeData.reservations).toHaveLength(3);
    for (const rows of Object.values(beforeData.tables)) expect(rows.length).toBeGreaterThan(0);
    const beforeMessaging = await messagingDefinitions();
    expect(beforeMessaging.functions.length).toBeGreaterThan(0);
    expect(beforeMessaging.tables.length).toBeGreaterThan(0);
    expect(beforeMessaging.policies.length).toBeGreaterThan(0);

    await migrate(migrationPool);
    const afterRegistry = await registry();
    expect(afterRegistry.map(row => row.name)).toEqual(names);
    expect(afterRegistry.filter(row => !coursePattern.test(row.name))).toEqual(beforeRegistry);
    for (const row of afterRegistry) {
      const sql = await readFile(new URL(row.name, migrationDirectory), 'utf8');
      expect(row.sha256, row.name).toBe(createHash('sha256').update(sql).digest('hex'));
    }
    expect(await existingData()).toEqual(beforeData);
    expect(await messagingDefinitions()).toEqual(beforeMessaging);
    expect((await pool.query(`SELECT course_occurrence_id,course_enrollment_id FROM drivy.reservation ORDER BY id`)).rows)
      .toEqual(Array.from({ length: 3 }, () => ({ course_occurrence_id: null, course_enrollment_id: null })));
    const courseTables = (await pool.query(`SELECT tablename FROM pg_tables WHERE schemaname='drivy' AND tablename LIKE 'course_%' ORDER BY tablename`)).rows;
    expect(courseTables.map(row => row.tablename)).toEqual(expect.arrayContaining([
      'course_series', 'course_enrollment', 'course_attendance', 'course_payment_record', 'course_completion', 'course_reminder_sent'
    ]));
    for (const { tablename } of courseTables) {
      const count = (await pool.query(`SELECT count(*)::int AS count FROM drivy.${tablename}`)).rows[0].count;
      expect(count, tablename).toBe(tablename === 'course_type' ? 2 : 0);
    }
    await assertMessagingRights(conversationId);

    await migrate(migrationPool);
    expect(await registry()).toEqual(afterRegistry);
    expect(await existingData()).toEqual(beforeData);
    expect(await messagingDefinitions()).toEqual(beforeMessaging);
    await assertMessagingRights(conversationId);
  });
});
