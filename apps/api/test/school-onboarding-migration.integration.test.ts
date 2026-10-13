import {createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {Pool} from 'pg';
import {expect,it} from 'vitest';
import {migrate} from '../scripts/migrations.js';
import {seedFixtures} from '../scripts/fixtures.js';
import {defaultProfileFields,setupDraftSchema} from '../src/school-onboarding-model.js';
import {harness,id,issuer,prepareSchool,prepareCommercial} from './support/harness.js';

const url=process.env.TEST_DATABASE_URL;
if(!url||new URL(url).pathname!=='/drivy_test')throw new Error('Base synthétique isolée drivy_test obligatoire.');

it('031/032 préservent une copie synthétique peuplée à030 et ne relancent pas une école ACTIVE',async()=>{
  const pool=new Pool({connectionString:url}),owner='drivy_onboarding_migration_owner';
  const migration=new Pool({connectionString:url,options:`-c role=${owner}`});
  let app:Awaited<ReturnType<typeof harness>>['app']|undefined;
  try {
    expect((await pool.query('SELECT current_database() AS name')).rows[0].name).toBe('drivy_test');
    for(const role of [owner,'drivy_app','drivy_invitation_mailer'])await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
    await pool.query(`GRANT CREATE ON DATABASE drivy_test TO ${owner}`);await pool.query(`GRANT drivy_app,drivy_invitation_mailer TO ${owner} WITH ADMIN OPTION`);
    await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');
    await pool.query(`GRANT USAGE,CREATE ON SCHEMA public TO ${owner}`);
    expect((await migration.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0]).toEqual({rolsuper:false,rolbypassrls:false});
    await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
    const directory=new URL('../migrations/',import.meta.url);
    const oldNames=(await readdir(directory)).filter(name=>/^\d{3}_.*\.sql$/.test(name)&&Number(name.slice(0,3))<=30).sort();
    expect(oldNames.at(-1)).toBe('030_admin_recording_choices.sql');
    // Copie synthétique de l'état antérieur : aucune base d'exploitation n'est lue.
    for(const name of oldNames) {
      const sql=await readFile(new URL(name,directory),'utf8'),db=await migration.connect();
      try {await db.query('BEGIN');await db.query(sql);await db.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',[name,createHash('sha256').update(sql).digest('hex')]);await db.query('COMMIT');}
      catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
      if(name.startsWith('001_')) {
        await seedFixtures(pool,issuer);
        await pool.query("UPDATE drivy.school SET status='DRAFT',name='École en préparation synthétique' WHERE id=$1",[id.schoolB]);
      }
    }
    await prepareSchool(pool);
    await pool.query('UPDATE drivy.profile_field_policy SET fields=$1 WHERE school_id=$2',[JSON.stringify(defaultProfileFields),id.schoolA]);
    await pool.query("UPDATE drivy.school_setup SET version=8,current_step='REVIEW',completed_steps=ARRAY['IDENTITY','DATA','REVIEW'],completed_at=now(),last_saved_at=now() WHERE school_id=$1",[id.schoolA]);
    await pool.query("UPDATE drivy.school_setup SET version=3,current_step='DATA',completed_steps=ARRAY['IDENTITY'],last_saved_at=now() WHERE school_id=$1",[id.schoolB]);
    await pool.query(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at)
      VALUES($1,2,'Ancienne notice synthétique conservée exactement.','Ancienne conservation synthétique conservée exactement.','draft@example.invalid',$2,now())`,[id.schoolB,id.instructorMemberB]);
    const env=await harness(pool);app=env.app;
    const commercial=await prepareCommercial(env.call);
    expect(commercial.product.unitPriceCents).toBe(9000);
    await pool.query(`INSERT INTO drivy.recording_choice(school_id,version,learner_id,status,notice_version_id,recorded_by,source)
      SELECT $1,1,$2,'ALLOWED',notice_version_id,$3,'RECORDED_VERBAL' FROM drivy.school_data_policy WHERE school_id=$1 ORDER BY version DESC LIMIT 1`,[id.schoolA,id.aliceLearner,id.instructorMember]);
    const privacyViews=async()=>Promise.all(['data-policy/impact','recording-choices'].map(async route=>{
      const response=await env.call('GET',`/v1/schools/${id.schoolA}/${route}`,undefined,undefined,'demo-admin');expect(response.statusCode,response.body).toBe(200);return response.json().data;
    }));
    const beforePrivacy=await privacyViews();expect(beforePrivacy[0]).toEqual({gpsAgreements:1,activeCaptures:0});
    expect(beforePrivacy[1].items[0]).toMatchObject({learnerId:id.aliceLearner,currentNotice:true,status:'ALLOWED'});
    const beforeEntry=(await env.call('GET','/v1/me',undefined,undefined,'demo-admin')).json().data;
    const history=(await pool.query('SELECT name,sha256,applied_at FROM public.drivy_migrations ORDER BY name')).rows;
    const tables=(await pool.query<{name:string}>("SELECT c.relname AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relkind='r' ORDER BY c.relname")).rows.map(row=>row.name);
    const newColumns=['draft_version','draft_step','draft_content','draft_updated_at','draft_updated_by','draft_applied_at'];
    const snapshot=async()=>{
      const result:Record<string,unknown[]>={};
      for(const table of tables) {
        if(!/^[a-z_]+$/.test(table))throw new Error('Nom de table de recette inattendu.');
        result[table]=(await pool.query(`SELECT to_jsonb(t)-$1::text[] AS value FROM drivy.${table} t ORDER BY (to_jsonb(t)-$1::text[])::text`,[table==='school_setup'?newColumns:[]])).rows.map(row=>row.value);
      }
      return result;
    };
    const before=await snapshot();expect(before.operation!.length).toBeGreaterThan(0);expect(before.service_product_version!.length).toBeGreaterThan(0);
    // Le migrateur de production reprend les checksums déjà enregistrés et applique seulement les nouveautés.
    await migrate(migration);
    expect(await snapshot()).toEqual(before);
    expect((await pool.query('SELECT name,sha256,applied_at FROM public.drivy_migrations WHERE name=ANY($1::text[]) ORDER BY name',[oldNames])).rows).toEqual(history);
    expect((await pool.query('SELECT name FROM public.drivy_migrations WHERE NOT(name=ANY($1::text[])) ORDER BY name',[oldNames])).rows.map(row=>row.name)).toEqual(['031_school_opening.sql','032_school_setup_draft.sql']);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.school_opening_link')).rows[0].n).toBe(0);
    expect((await env.call('GET','/v1/me',undefined,undefined,'demo-admin')).json().data).toEqual(beforeEntry);
    expect(await privacyViews()).toEqual(beforePrivacy);
    for(const [schoolId,subject,status] of [[id.schoolA,'demo-admin','ACTIVE'],[id.schoolB,'demo-instructor','DRAFT']] as const) {
      const response=await env.call('GET',`/v1/schools/${schoolId}/setup-draft`,undefined,undefined,subject);expect(response.statusCode,response.body).toBe(200);
      const draft=setupDraftSchema.parse(response.json().data);
      expect(draft).toMatchObject({version:1,status:'DRAFT',currentStep:'IDENTITY',updatedAt:null,appliedAt:null});
      expect(draft.content.selectedSections).toEqual(status==='ACTIVE'?[]:['IDENTITY','PRIVACY','PROFILE']);
      expect(draft.content.formations).toEqual([]);
      const policy=(await pool.query('SELECT notice_text,retention_text FROM drivy.school_data_policy WHERE school_id=$1 ORDER BY version DESC LIMIT 1',[schoolId])).rows[0];
      expect(draft.content.privacy.noticeText).toBe(policy.notice_text);expect(draft.content.privacy.retentionText).toBe(policy.retention_text);
      expect((await pool.query('SELECT draft_content,draft_version,status FROM drivy.school_setup p JOIN drivy.school s ON s.id=p.school_id WHERE school_id=$1',[schoolId])).rows[0]).toEqual({draft_content:null,draft_version:1,status});
    }
    expect(await snapshot()).toEqual(before); // Les lectures n'ont ni adopté, ni sauvegardé, ni activé.
    const migrated=(await pool.query('SELECT name,sha256,applied_at FROM public.drivy_migrations ORDER BY name')).rows;
    await migrate(migration);
    expect((await pool.query('SELECT name,sha256,applied_at FROM public.drivy_migrations ORDER BY name')).rows).toEqual(migrated);
    expect(await snapshot()).toEqual(before);
  } finally {await app?.close();await migration.end();await pool.end();}
},30_000);
