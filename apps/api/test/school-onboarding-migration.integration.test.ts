import {createHash,randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {Pool} from 'pg';
import {expect,it} from 'vitest';
import {migrate} from '../scripts/migrations.js';
import {seedFixtures} from '../scripts/fixtures.js';
import {defaultProfileFields,setupDraftSchema} from '../src/school-onboarding-model.js';
import {harness,id,issuer,prepareSchool,prepareCommercial} from './support/harness.js';
import {captureHarness} from './support/capture-harness.js';

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
        result[table]=(await pool.query(`SELECT to_jsonb(t)-$1::text[] AS value FROM drivy.${table} t ORDER BY (to_jsonb(t)-$1::text[])::text`,[table==='school_setup'?newColumns:table==='offering_version'?['label']:[]])).rows.map(row=>row.value);
      }
      return result;
    };
    const before=await snapshot();expect(before.operation!.length).toBeGreaterThan(0);expect(before.service_product_version!.length).toBeGreaterThan(0);
    // Le migrateur de production reprend les checksums déjà enregistrés et applique seulement les nouveautés.
    await migrate(migration);
    expect(await snapshot()).toEqual(before);
    expect((await pool.query('SELECT name,sha256,applied_at FROM public.drivy_migrations WHERE name=ANY($1::text[]) ORDER BY name',[oldNames])).rows).toEqual(history);
    expect((await pool.query('SELECT name FROM public.drivy_migrations WHERE NOT(name=ANY($1::text[])) ORDER BY name',[oldNames])).rows.map(row=>row.name)).toEqual(['031_school_opening.sql','032_school_setup_draft.sql','033_formation_programme_label.sql','034_withdrawal_reason_staff_only.sql','035_osrm_matched_route.sql','036_autonomous_signals.sql','037_self_profile.sql']);
    // 033 ajoute seulement le nom facultatif d'un parcours : aucune ligne existante ne reçoit de nom déduit.
    expect((await pool.query('SELECT count(*)::int AS named FROM drivy.offering_version WHERE label IS NOT NULL')).rows[0].named).toBe(0);
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

it('035 purge Mapbox et tous les anciens calculs en cours sans toucher aux chunks ni aux notices adoptées',async()=>{
  const pool=new Pool({connectionString:url}),owner='drivy_onboarding_migration_owner';
  const migration=new Pool({connectionString:url,options:`-c role=${owner}`});
  let capture:Awaited<ReturnType<typeof captureHarness>>|undefined;
  try {
    // Les mêmes privilèges limités que le migrateur de production, sur une base uniquement synthétique.
    for(const role of [owner,'drivy_app','drivy_invitation_mailer'])await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
    await pool.query(`GRANT CREATE ON DATABASE drivy_test TO ${owner}`);await pool.query(`GRANT drivy_app,drivy_invitation_mailer TO ${owner} WITH ADMIN OPTION`);
    await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');
    await pool.query(`GRANT USAGE,CREATE ON SCHEMA public TO ${owner}`);
    await migration.query('CREATE TABLE public.drivy_migrations(name text PRIMARY KEY,sha256 text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())');
    const directory=new URL('../migrations/',import.meta.url);
    const oldNames=(await readdir(directory)).filter(name=>/^\d{3}_.*\.sql$/.test(name)&&Number(name.slice(0,3))<=34).sort();
    for(const name of oldNames){
      const sql=await readFile(new URL(name,directory),'utf8'),db=await migration.connect();
      try {await db.query('BEGIN');await db.query(sql);await db.query('INSERT INTO public.drivy_migrations(name,sha256) VALUES($1,$2)',[name,createHash('sha256').update(sql).digest('hex')]);await db.query('COMMIT');}
      catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
      if(name.startsWith('001_'))await seedFixtures(pool,issuer);
    }
    capture=await captureHarness(pool);
    const trip=await capture.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
    await capture.uploadStopFinalize(trip);
    const fixtures=[
      ['mapbox','READY'],['mapbox','EMPTY'],['mapbox','FAILED'],['mapbox','PROCESSING'],
      [null,'PROCESSING'],['osrm','PROCESSING'],['osrm','READY'],['osrm','EMPTY'],['osrm','FAILED'],
    ] as const;
    const leases:{id:string;lease:string;provider:string|null}[]=[];
    for(const [provider,status] of fixtures){
      const target=randomUUID(),lease=randomUUID();
      await pool.query(`INSERT INTO drivy.capture_session SELECT (jsonb_populate_record(NULL::drivy.capture_session,to_jsonb(c)||jsonb_build_object('id',$2::uuid))).* FROM drivy.capture_session c WHERE id=$1`,[trip.capture.id,target]);
      await pool.query(`INSERT INTO drivy.capture_matched_route(capture_id,school_id,reconstruction_version,algorithm_version,status,provider,lease_id,lease_until,encrypted_route,key_id)
        SELECT id,school_id,reconstruction_version,1,$2,$3,CASE WHEN $2='PROCESSING' THEN $4::uuid END,CASE WHEN $2='PROCESSING' THEN now()+interval '10 minutes' END,
        CASE WHEN $2='READY' THEN $5::bytea END,CASE WHEN $2='READY' THEN 'synthetic-only' END FROM drivy.capture_session WHERE id=$1`,[target,status,provider,lease,Buffer.alloc(29,42)]);
      if(status==='PROCESSING')leases.push({id:target,lease,provider});
    }
    const snapshot=async(table:string)=>(await pool.query(`SELECT to_jsonb(t) AS value FROM drivy.${table} t ORDER BY to_jsonb(t)::text`)).rows;
    const chunks=await snapshot('capture_chunk'),sessions=await snapshot('capture_session'),notices=await snapshot('school_data_policy');
    expect(chunks.length).toBeGreaterThan(0);
    const retained=(await pool.query("SELECT * FROM drivy.capture_matched_route WHERE provider='osrm' AND status<>'PROCESSING' ORDER BY capture_id")).rows;
    await migrate(migration);
    expect((await pool.query('SELECT * FROM drivy.capture_matched_route ORDER BY capture_id')).rows).toEqual(retained);
    expect(await snapshot('capture_chunk')).toEqual(chunks);expect(await snapshot('capture_session')).toEqual(sessions);expect(await snapshot('school_data_policy')).toEqual(notices);
    expect((await pool.query("SELECT to_regprocedure('drivy.claim_matched_route(uuid,integer,integer,integer)') AS old_claim")).rows[0].old_claim).toBeNull();
    const query=async(sql:string,values:unknown[])=>{
      const db=await pool.connect();try {await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');const result=await db.query(sql,values);await db.query('COMMIT');return result;}
      catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
    };
    for(const old of leases){
      expect((await query("SELECT drivy.complete_matched_route($1,$2,'EMPTY',NULL,NULL,0,$3,NULL,NULL) AS accepted",[old.id,old.lease,old.provider??'mapbox'])).rows[0].accepted).toBe(false);
    }
    const target=leases[0]!.id;
    const version=(await pool.query('SELECT reconstruction_version FROM drivy.capture_session WHERE id=$1',[target])).rows[0].reconstruction_version;
    const claim=async(engine:string,algorithm=2)=>(await query('SELECT drivy.claim_matched_route($1,$2,$3,180,$4) AS lease',[target,version,algorithm,engine])).rows[0].lease as string|null;
    expect(await claim('mapbox')).toBeNull();expect(await claim('osrm',1)).toBeNull();
    const lease=await claim('osrm');expect(lease).not.toBeNull();
    expect((await pool.query('SELECT provider,algorithm_version,status FROM drivy.capture_matched_route WHERE capture_id=$1',[target])).rows[0]).toEqual({provider:'osrm',algorithm_version:2,status:'PROCESSING'});
    // Même en annonçant OSRM, le callback ancien ne peut terminer le nouveau bail.
    expect((await query("SELECT drivy.complete_matched_route($1,$2,'EMPTY',NULL,NULL,0,'osrm',NULL,NULL) AS accepted",[target,leases[0]!.lease])).rows[0].accepted).toBe(false);
    expect((await query("SELECT drivy.complete_matched_route($1,$2,'EMPTY',NULL,NULL,0,'mapbox',NULL,NULL) AS accepted",[target,lease])).rows[0].accepted).toBe(false);
    expect((await query("SELECT drivy.complete_matched_route($1,$2,'EMPTY',NULL,NULL,0,'osrm',NULL,NULL) AS accepted",[target,lease])).rows[0].accepted).toBe(true);
    // Une réexécution du migrateur ne repurge pas un nouveau résultat OSRM.
    const after=await snapshot('capture_matched_route');await migrate(migration);expect(await snapshot('capture_matched_route')).toEqual(after);
    expect(await snapshot('capture_chunk')).toEqual(chunks);expect(await snapshot('school_data_policy')).toEqual(notices);
  } finally {await capture?.app.close();await migration.end();await pool.end();}
},60_000);
