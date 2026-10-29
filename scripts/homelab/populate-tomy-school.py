#!/usr/bin/env python3
"""Populate the explicitly designated Tomy School. Plan only unless --validate or --execute.

No identity credentials, invitations, messages, GPS points or delivery jobs are created.
The normal development fixtures remain forbidden on the homelab database.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

REMOTE = r'''
import datetime,hashlib,json,os,pathlib,subprocess
def sql(code):
 r=subprocess.run(['runuser','-u','postgres','--','psql','-XqAt','--set=ON_ERROR_STOP=1','--dbname=drivy_refonte'],input=code.encode(),capture_output=True,timeout=120)
 if r.returncode:
  lines=r.stderr.decode(errors='replace').splitlines()
  # Never echo row DETAIL, SQL source, or a private value from a failed statement.
  message=next((line.split('ERROR:',1)[1].strip() for line in lines if 'ERROR:' in line),'Database operation failed')
  raise RuntimeError(message[:250])
 return [json.loads(line) for line in r.stdout.decode().splitlines() if line.startswith('{')]
sid=REQUEST['schoolId']; aid=REQUEST['actorId']
lookup=sql("SELECT jsonb_build_object('id',s.id,'name',s.name,'status',s.status,'actorValid',EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=s.id AND m.id='"+aid+"' AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)),'learners',(SELECT count(*) FROM drivy.learner_profile l WHERE l.school_id=s.id),'members',(SELECT count(*) FROM drivy.membership m WHERE m.school_id=s.id)) FROM drivy.school s WHERE s.id='"+sid+"';")
if len(lookup)!=1 or lookup[0]['name'].strip().lower()!='tomy school' or lookup[0]['status']!='ACTIVE' or not lookup[0]['actorValid']: raise RuntimeError('Exact school and administrator guard failed')
if not REQUEST['validate'] and not REQUEST['execute']:
 print(json.dumps({'action':'plan','school':lookup[0],'scriptSha256':REQUEST['scriptSha256'],'backupRequired':True,'singleTransaction':True}));raise SystemExit(0)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
directory=pathlib.Path('/root/drivy-tomy-school-'+stamp);directory.mkdir(mode=0o700)
backup=directory/'before.dump'
fd=os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'wb') as stream:
 result=subprocess.run(['runuser','-u','postgres','--','pg_dump','--format=custom','--dbname=drivy_refonte'],stdout=stream,stderr=subprocess.PIPE,timeout=300)
 stream.flush();os.fsync(stream.fileno())
if result.returncode or backup.stat().st_size<1024: raise RuntimeError('Database backup failed')
for args in [['pg_restore','--list',str(backup)],['pg_restore','--file=/dev/null',str(backup)]]:
 if subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=300).returncode: raise RuntimeError('Backup verification failed')
code=REQUEST['sql'];(directory/'populate.sql').write_text(code);(directory/'populate.sql').chmod(0o600)
if hashlib.sha256(code.encode()).hexdigest()!=REQUEST['scriptSha256']:raise RuntimeError('SQL identity mismatch')
ending='COMMIT;' if REQUEST['execute'] else 'ROLLBACK;'
result=sql(code+'\n'+ending)
receipt={'action':'populated' if REQUEST['execute'] else 'validated-and-rolled-back','schoolId':sid,'scriptSha256':REQUEST['scriptSha256'],'backup':str(backup),'backupBytes':backup.stat().st_size,'archiveVerified':True,'restoreRehearsal':False,'results':result}
(directory/'receipt.json').write_text(json.dumps(receipt,indent=2));(directory/'receipt.json').chmod(0o600)
print(json.dumps(receipt))
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--school-id', required=True, type=uuid.UUID)
    parser.add_argument('--actor-membership-id', required=True, type=uuid.UUID)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--validate', action='store_true')
    mode.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    prefix = """BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
SET LOCAL TIME ZONE 'Europe/Zurich';
CREATE FUNCTION pg_temp.seed_uuid(value text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
 SELECT (substr(md5(value),1,8)||'-'||substr(md5(value),9,4)||'-4'||substr(md5(value),14,3)||'-8'||substr(md5(value),18,3)||'-'||substr(md5(value),21,12))::uuid
$$;
CREATE TEMP TABLE seed_context(school_id uuid,actor_id uuid,actor_person_id uuid);
INSERT INTO seed_context SELECT s.id,m.id,m.person_id FROM drivy.school s JOIN drivy.membership m ON m.school_id=s.id JOIN drivy.person p ON p.id=m.person_id
 WHERE s.id='%s' AND m.id='%s' AND lower(trim(s.name))='tomy school' AND s.status='ACTIVE' AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles);
DO $$ BEGIN
 IF (SELECT count(*) FROM seed_context)<>1 THEN RAISE EXCEPTION 'School guard failed'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('tomy311-population',0));
 PERFORM 1 FROM drivy.person WHERE id=(SELECT actor_person_id FROM seed_context) FOR UPDATE;
 PERFORM 1 FROM drivy.membership WHERE id=(SELECT actor_id FROM seed_context) FOR UPDATE;
 PERFORM 1 FROM drivy.school WHERE id=(SELECT school_id FROM seed_context) FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM seed_context c JOIN drivy.school s ON s.id=c.school_id
  JOIN drivy.membership m ON m.id=c.actor_id AND m.school_id=s.id JOIN drivy.person p ON p.id=m.person_id
  WHERE lower(trim(s.name))='tomy school' AND s.status='ACTIVE' AND m.status='ACTIVE' AND p.status='ACTIVE'
  AND 'ADMIN'=ANY(m.roles) AND p.id=c.actor_person_id) THEN RAISE EXCEPTION 'School or administrator changed while locking'; END IF;
 PERFORM set_config('app.person_id',(SELECT actor_person_id::text FROM seed_context),true);
 PERFORM set_config('app.membership_id',(SELECT actor_id::text FROM seed_context),true);
 PERFORM set_config('app.school_id',(SELECT school_id::text FROM seed_context),true);
END $$;
CREATE TEMP TABLE seed_original_people AS SELECT p.* FROM drivy.person p;
CREATE TEMP TABLE seed_original_schools AS SELECT s.* FROM drivy.school s;
CREATE TEMP TABLE seed_original_memberships AS SELECT m.* FROM drivy.membership m;
CREATE TEMP TABLE seed_original_content(table_name text,row_value jsonb);
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['learner_profile','onboarding_progress','training','training_wish','instructor_assignment','offering_version','curriculum_version','competency_definition','school_policy_version','service_product_version','commercial_terms_version','availability_rule','closure','lesson','reservation','lesson_preparation','report_draft','report_revision','course_type','course_policy_version','course_series','course_occurrence','course_enrollment','course_waitlist_entry','course_payment_record','course_attendance','course_completion'] LOOP
  IF to_regclass('drivy.'||name) IS NOT NULL THEN
   EXECUTE format('INSERT INTO seed_original_content SELECT %%L,to_jsonb(t) FROM drivy.%%I t',name,name);
  END IF;
 END LOOP;
END $$;
""" % (args.school_id, args.actor_membership_id)
    fragments = [root / 'scripts/dev' / ('tomy-school-' + part + '.sql') for part in ['catalogue', 'people', 'courses', 'lessons']]
    code = prefix + '\n'.join(path.read_text(encoding='utf-8') for path in fragments)
    code += """
-- The owner already has the INSTRUCTOR role; add a few dossiers to their teaching list without changing access.
INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from)
 SELECT pg_temp.seed_uuid('tomy311:owner-assignment:'||p.ordinal),c.school_id,p.training_id,c.actor_id,current_date-90
 FROM seed_people p CROSS JOIN seed_context c JOIN drivy.membership m ON m.id=c.actor_id
 WHERE p.role='LEARNER' AND p.ordinal<=8 AND 'INSTRUCTOR'=ANY(m.roles)
 AND NOT EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=c.school_id AND a.training_id=p.training_id AND a.instructor_membership_id=c.actor_id AND a.valid_until IS NULL)
 ON CONFLICT(id) DO NOTHING;
-- Preserve all pre-existing identities, memberships and every other school.
DO $$ BEGIN
 IF EXISTS(SELECT * FROM seed_original_people EXCEPT SELECT * FROM drivy.person) THEN RAISE EXCEPTION 'An existing identity changed'; END IF;
 IF EXISTS(SELECT * FROM seed_original_memberships EXCEPT SELECT * FROM drivy.membership) THEN RAISE EXCEPTION 'An existing membership changed'; END IF;
 IF EXISTS(SELECT * FROM seed_original_schools EXCEPT SELECT * FROM drivy.school) THEN RAISE EXCEPTION 'An existing school changed unexpectedly'; END IF;
END $$;
DO $$ DECLARE name text; changed boolean; BEGIN
 FOR name IN SELECT DISTINCT table_name FROM seed_original_content LOOP
  EXECUTE format('SELECT EXISTS(SELECT row_value FROM seed_original_content WHERE table_name=%L EXCEPT SELECT to_jsonb(t) FROM drivy.%I t)',name,name) INTO changed;
  IF changed THEN RAISE EXCEPTION 'An existing business record changed in %',name; END IF;
 END LOOP;
END $$;
-- Enable the requested course surface without touching GPS, identity or existing contact details.
WITH changed AS (
 UPDATE drivy.school SET modules=jsonb_set(modules,'{collectiveCoursesEnabled}','true'),version=version+1,configuration_version=configuration_version+1
 WHERE id=(SELECT school_id FROM seed_context) AND modules->>'collectiveCoursesEnabled' IS DISTINCT FROM 'true' RETURNING *
)
INSERT INTO drivy.school_settings_version(school_id,version,settings,created_by)
 SELECT s.id,s.configuration_version,coalesce((SELECT v.settings FROM drivy.school_settings_version v WHERE v.school_id=s.id ORDER BY v.version DESC LIMIT 1),'{}')||
 jsonb_build_object('name',s.name,'timeZone',s.time_zone,'contactEmail',s.contact_email,'contactPhone',s.contact_phone,'modules',s.modules),c.actor_id
 FROM changed s JOIN seed_context c ON c.school_id=s.id;
SELECT jsonb_build_object('learners',(SELECT count(*) FROM seed_people WHERE role='LEARNER'),'instructors',(SELECT count(*) FROM seed_people WHERE role='INSTRUCTOR'),
 'schoolMembers',(SELECT count(*) FROM drivy.membership WHERE school_id=c.school_id),
 'offerings',(SELECT count(*) FROM drivy.offering_version WHERE school_id=c.school_id),
 'products',(SELECT count(*) FROM drivy.service_product_version WHERE school_id=c.school_id),
 'lessons',(SELECT count(*) FROM drivy.lesson WHERE school_id=c.school_id),
 'lessonStates',(SELECT jsonb_object_agg(status,n) FROM (SELECT status,count(*) n FROM drivy.lesson WHERE school_id=c.school_id GROUP BY status) s),
 'courseSeries',(SELECT count(*) FROM drivy.course_series WHERE school_id=c.school_id),
 'courseOccurrences',(SELECT count(*) FROM drivy.course_occurrence WHERE school_id=c.school_id),
 'enrollments',(SELECT count(*) FROM drivy.course_enrollment WHERE school_id=c.school_id),
 'waitlist',(SELECT count(*) FROM drivy.course_waitlist_entry WHERE school_id=c.school_id),
 'payments',(SELECT count(*) FROM drivy.course_payment_record WHERE school_id=c.school_id),
 'availability',(SELECT count(*) FROM drivy.availability_rule WHERE school_id=c.school_id),
 'closures',(SELECT count(*) FROM drivy.closure WHERE school_id=c.school_id)) FROM seed_context c;
"""
    request = {'schoolId': str(args.school_id), 'actorId': str(args.actor_membership_id), 'validate': args.validate,
               'execute': args.execute, 'sql': code, 'scriptSha256': hashlib.sha256(code.encode()).hexdigest()}
    child = 'REQUEST=' + repr(request) + '\n' + REMOTE
    compile(child, '<population>', 'exec')
    host = "import subprocess,json\ncode=" + repr(child) + "\nr=subprocess.run(['pct','exec','113','--','python3','-'],input=code.encode(),capture_output=True,timeout=800)\n"
    host += "if r.returncode:\n lines=r.stderr.decode(errors='replace').splitlines()\n print(json.dumps({'error':next((x for x in reversed(lines) if x.startswith('RuntimeError:')),'Remote operation failed')}))\nelse: print(r.stdout.decode())\nraise SystemExit(r.returncode)\n"
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=8',
                             'root@192.168.1.106', 'python3 -'], input=host.encode(), capture_output=True, timeout=850)
    print(result.stdout.decode())
    if result.returncode:
        raise SystemExit('Population result not confirmed. Inspect the private receipt and school counts before retrying; SQL errors roll back, a lost post-commit reply does not. Private diagnostics stay on host.')

if __name__ == '__main__':
    main()
