/** Operator-only, additive fictional data for the owner's explicitly requested trials.
 * Accounts are created separately by the identity provider; no password is accepted here.
 * Existing school settings and existing people are never replaced.
 */
import pg from 'pg';
import {readFileSync} from 'node:fs';
import {randomUUID,createHash} from 'node:crypto';

const state=JSON.parse(readFileSync(0,'utf8'));
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
if(!uuid.test(state.operationId)||!uuid.test(state.schoolId)||state.issuer!=='https://drivy.shulker.ch/identity/realms/drivy'
  ||!Array.isArray(state.accounts)||state.accounts.length!==2||state.accounts.some(a=>!uuid.test(a.subject)||!['moniteur','eleve'].includes(a.username)))throw new Error('Invalid operator state');
const env=Object.fromEntries(readFileSync('/etc/drivy-refonte/migration.env','utf8').split('\n').filter(l=>l&&!l.startsWith('#')).map(l=>[l.slice(0,l.indexOf('=')),l.slice(l.indexOf('=')+1)]));
const pool=new pg.Pool({connectionString:env.MIGRATION_DATABASE_URL,max:1});
const db=await pool.connect();
const tables=['person','identity_link','school','membership','learner_profile','offering_version','training','instructor_assignment','profile_field_policy','school_data_policy','school_settings_version','operation','audit_event'];
try {
  const actual=(await db.query('SELECT current_database() AS db,current_user AS role')).rows[0];
  if(actual.db!=='drivy_refonte'||actual.role!=='drivy_refonte_owner')throw new Error('Wrong deployment database');
  await db.query('BEGIN');
  await db.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='20s'");
  await db.query('LOCK TABLE '+tables.map(t=>'drivy.'+t).join(',')+' IN ACCESS EXCLUSIVE MODE');
  const protections=(await db.query("SELECT relname,relrowsecurity,relforcerowsecurity,pg_get_userbyid(relowner) AS owner FROM pg_class WHERE relnamespace='drivy'::regnamespace AND relname=ANY($1)",[tables])).rows;
  if(protections.length!==tables.length||protections.some(t=>!t.relrowsecurity||!t.relforcerowsecurity||t.owner!==actual.role))throw new Error('Unexpected table protection');
  for(const t of tables)await db.query('ALTER TABLE drivy.'+t+' NO FORCE ROW LEVEL SECURITY');
  const school=(await db.query('SELECT * FROM drivy.school WHERE id=$1 FOR UPDATE',[state.schoolId])).rows[0];
  if(!school||school.name!=='Luc auto école'||school.status!=='ACTIVE')throw new Error('School must already be activated by its administrator');
  const admin=(await db.query("SELECT m.* FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=$1 AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles) AND p.display_name='luc'",[state.schoolId])).rows[0];
  if(!admin)throw new Error('Expected administrator missing');
  const done=(await db.query('SELECT command_type FROM drivy.operation WHERE actor_person_id=$1 AND operation_id=$2',[admin.person_id,state.operationId])).rows[0];
  if(done){if(done.command_type!=='PROVISION_EXAMPLE_DATA')throw new Error('Operation collision');}
  else {
    if((await db.query('SELECT 1 FROM drivy.learner_profile WHERE school_id=$1 LIMIT 1',[state.schoolId])).rowCount)throw new Error('School already has learners; additive seed requires operator review');
    const instructor=state.accounts.find(a=>a.username==='moniteur'),student=state.accounts.find(a=>a.username==='eleve');
    if(!instructor||!student)throw new Error('Both example roles required');
    for(const a of state.accounts)if((await db.query('SELECT 1 FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[state.issuer,a.subject])).rowCount)throw new Error('Identity already linked');
    const teacherPerson=randomUUID(),teacherMember=randomUUID();
    await db.query("INSERT INTO drivy.person(id,display_name) VALUES($1,'Alex Martin · exemple')",[teacherPerson]);
    await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)',[state.issuer,instructor.subject,teacherPerson]);
    await db.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,ARRAY['INSTRUCTOR'])",[teacherMember,state.schoolId,teacherPerson]);
    const offering=randomUUID();
    await db.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled) VALUES($1,$2,'example-category-b','B',1,false)",[offering,state.schoolId]);
    const examples=[['Léa','Morel'],['Noé','Favre'],['Emma','Rochat'],['Lucas','Perrin'],['Sofia','Blanc'],['Hugo','Girard']];
    for(const [index,[first,last]] of examples.entries()){
      const person=randomUUID(),member=randomUUID(),learner=randomUUID(),training=randomUUID(),display=first+' '+last+' · exemple';
      await db.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)',[person,display]);
      if(index===0)await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)',[state.issuer,student.subject,person]);
      await db.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,ARRAY['LEARNER'])",[member,state.schoolId,person]);
      await db.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name,first_name,last_name,contact_email,entered_by_membership_id,entry_source) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'STAFF_ASSISTED')",[learner,state.schoolId,person,display,first,last,'eleve'+(index+1)+'@example.invalid',admin.id]);
      await db.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,'example-category-b',$5,current_date-$6::int)",[training,state.schoolId,learner,offering,index===4?'PAUSED':'ACTIVE',index*7]);
      await db.query('INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now())',[randomUUID(),state.schoolId,training,teacherMember]);
    }
    const receipt={schoolId:state.schoolId,learners:6,trainings:6,instructorMembershipId:teacherMember,synthetic:true};
    const payloadHash=createHash('sha256').update(JSON.stringify({schoolId:state.schoolId,issuer:state.issuer,accounts:state.accounts})).digest('hex');
    await db.query("INSERT INTO drivy.operation(actor_person_id,operation_id,school_id,command_type,payload_hash,resource_id,response_data) VALUES($1,$2,$3,'PROVISION_EXAMPLE_DATA',$5,$3,$4)",[admin.person_id,state.operationId,state.schoolId,JSON.stringify(receipt),payloadHash]);
    await db.query("INSERT INTO drivy.audit_event(id,school_id,actor_person_id,actor_membership_id,operation_id,action,resource_type,resource_id,changed_fields) VALUES($1,$2,$3,$4,$5,'OperatorProvisionedFictionalExamples','School',$2,ARRAY['exampleLearners','exampleTrainings','exampleInstructor'])",[randomUUID(),state.schoolId,admin.person_id,admin.id,state.operationId]);
  }
  for(const t of tables)await db.query('ALTER TABLE drivy.'+t+' FORCE ROW LEVEL SECURITY');
  await db.query('COMMIT');
  process.stdout.write(JSON.stringify({schoolId:state.schoolId,exampleLearners:6,accounts:2,existingSettingsUnchanged:true})+'\n');
} catch(error) {await db.query('ROLLBACK');process.stderr.write('Example provisioning refused: '+(error instanceof Error&&/^[A-Za-z ;]+$/.test(error.message)?error.message:'private details withheld')+'\n');process.exitCode=1;}
finally{db.release();await pool.end();}
