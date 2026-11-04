/** Real Keycloak/Mailpit qualification of access recovery on disposable synthetic accounts.
 *  Three real roles are recovered on their own existing person, school and objects; nothing here persists a mail
 *  link, a password, a token or a request trace. */
import { randomBytes, randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import type { Browser, Page } from '../../infra/dev/browser.js';

/** The Drivy login theme answers the same conditional sentence for a known address, an unknown one and a failing relay. */
export const RECOVERY_CONDITIONAL_MESSAGE = 'Si cette adresse correspond à un compte, vous pourrez recevoir un lien de récupération. Si aucun message n’arrive, réessayez plus tard.';
/** State shown by `/app/recover` when the entry cannot be opened: an honest failure, never a claimed delivery. */
export const RECOVERY_UNAVAILABLE_MESSAGE = 'La récupération est momentanément indisponible.';

export type RecoveryRole = 'ADMIN' | 'INSTRUCTOR' | 'LEARNER';
export type RecoveryAccount = { role:RecoveryRole; email:string; password?:string; revokeOtherSessions:boolean };
export type MembershipState = { schoolId:string; roles:string[]; grants:string[]; status:string; accessEpoch:number; version:number };
export type AssignmentState = { id:string; trainingId:string; instructorMembershipId:string; validFrom:string; validUntil:string|null };
/** Champs métier explicitement comparés : un identifiant seul ne prouve pas qu’une ligne n’a pas changé de contenu. */
export type LessonState = { id:string; trainingId:string; learnerId:string; learnerPersonId:string; instructorMembershipId:string;
  status:string; plannedStart:string; plannedEnd:string; timeZone:string; meetingPoint:string; priceCents:number;
  bufferMinutes:number; policyVersionId:string; publicationVersion:number; version:number };
export type TrainingState = { id:string; learnerId:string; offeringId:string; offeringKey:string; status:string;
  startedOn:string|null; closedOn:string|null; version:number };
export type ProfileState = { id:string; profileId:string|null; administrativePolicyId:string|null; profileUpdatedAt:string|null;
  enteredByMembershipId:string|null; entrySource:string|null; archived:boolean; version:number };
export type AvailabilityState = { id:string; instructorMembershipId:string; weekdays:number[]; localStart:string;
  localEnd:string; validFrom:string; validUntil:string|null; removed:boolean; version:number };
/** Projection durable d’un compte : identité, rattachements et contenu métier, jamais un simple ensemble d’identifiants. */
export type IdentitySnapshot = {
  person: { id:string; status:string; displayName:string; firstName:string|null; lastName:string|null;
    contactEmail:string|null; locale:string; version:number } | null;
  links: string[];
  memberships: MembershipState[];
  assignments: AssignmentState[];
  learnerLessons: LessonState[];
  instructorLessons: LessonState[];
  trainings: TrainingState[];
  profiles: ProfileState[];
  availability: AvailabilityState[];
  totals: { persons:number; links:number; memberships:number; assignments:number; lessons:number; trainings:number;
    profiles:number; availability:number };
};

const roleLabel: Record<RecoveryRole,string> = { ADMIN:'administrateur', INSTRUCTOR:'moniteur', LEARNER:'élève' };
const stable = (value:unknown) => JSON.stringify(value);
/** Reading order is not identity: the same rows in another order are not a difference. */
const byId = <T extends {id:string}>(items:T[]):T[] => [...items].sort((left,right) => left.id.localeCompare(right.id));
const ordered = (snapshot:IdentitySnapshot):IdentitySnapshot => ({
  ...snapshot,
  links: [...snapshot.links].sort(),
  memberships: [...snapshot.memberships].map(item => ({...item, roles:[...item.roles].sort(), grants:[...item.grants].sort()}))
    .sort((left,right) => left.schoolId.localeCompare(right.schoolId)),
  assignments: byId(snapshot.assignments),
  learnerLessons: byId(snapshot.learnerLessons),
  instructorLessons: byId(snapshot.instructorLessons),
  trainings: byId(snapshot.trainings),
  profiles: byId(snapshot.profiles),
  availability: byId(snapshot.availability).map(item => ({...item, weekdays:[...item.weekdays].sort((left,right) => left-right)}))
});

/** Named differences only: no identifier and no business value ever reaches a check label or an artifact. */
export function snapshotDifferences(before:IdentitySnapshot, after:IdentitySnapshot):string[] {
  const left = ordered(before), right = ordered(after);
  const sections:[string,unknown,unknown][] = [
    ['liens d’identité', left.links, right.links],
    ['identité de personne', left.person, right.person],
    ['rattachements, rôles et droits', left.memberships, right.memberships],
    ['affectations de moniteur', left.assignments, right.assignments],
    ['leçons suivies', left.learnerLessons, right.learnerLessons],
    ['leçons données', left.instructorLessons, right.instructorLessons],
    ['formations', left.trainings, right.trainings],
    ['dossiers élève', left.profiles, right.profiles],
    ['disponibilités', left.availability, right.availability],
    ['totaux en base', left.totals, right.totals]
  ];
  return sections.filter(([,left,right]) => stable(left) !== stable(right)).map(([label]) => label);
}

/** A role is only qualified by its own real objects; three labels on one empty account would not qualify anything. */
export function requirementGaps(snapshot:IdentitySnapshot, role:RecoveryRole):string[] {
  if (!snapshot.person) return ['aucune personne liée'];
  const roles = snapshot.memberships.flatMap(item => item.roles);
  const gaps:string[] = [];
  if (!roles.includes(role)) gaps.push(`rôle ${role.toLowerCase()}`);
  if (role === 'ADMIN' && snapshot.instructorLessons.length === 0) gaps.push('au moins une leçon donnée');
  if (role === 'INSTRUCTOR') {
    if (snapshot.memberships.some(item => item.roles.includes('ADMIN'))) gaps.push('rôle moniteur distinct');
    if (snapshot.availability.length === 0) gaps.push('au moins une disponibilité');
    if (snapshot.instructorLessons.length === 0) gaps.push('au moins une leçon donnée');
  }
  if (role === 'LEARNER') {
    if (snapshot.profiles.length === 0) gaps.push('au moins un dossier élève');
    if (snapshot.trainings.length === 0) gaps.push('au moins une formation');
    if (snapshot.learnerLessons.length === 0) gaps.push('au moins une leçon suivie');
  }
  return gaps;
}

type LessonRow = { id:string; training_id:string; learner_id:string; learner_person_id:string; instructor_membership_id:string;
  status:string; planned_start:Date; planned_end:Date; time_zone:string; meeting_point:string; price_cents_snapshot:string;
  buffer_minutes_snapshot:number; policy_version_id:string; publication_version:number; version:number };
const lessonState = (row:LessonRow):LessonState => ({ id:row.id, trainingId:row.training_id, learnerId:row.learner_id,
  learnerPersonId:row.learner_person_id, instructorMembershipId:row.instructor_membership_id, status:row.status,
  plannedStart:row.planned_start.toISOString(), plannedEnd:row.planned_end.toISOString(), timeZone:row.time_zone,
  meetingPoint:row.meeting_point, priceCents:Number(row.price_cents_snapshot), bufferMinutes:row.buffer_minutes_snapshot,
  policyVersionId:row.policy_version_id, publicationVersion:row.publication_version, version:row.version });

/** Durable state read through the application schema, with the business fields the recovery must preserve. */
export async function readIdentitySnapshot(database:Pool, issuer:string, subject:string):Promise<IdentitySnapshot> {
  const links = (await database.query<{issuer:string;subject:string;person_id:string}>(
    'SELECT issuer,subject,person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2 ORDER BY issuer,subject',[issuer,subject])).rows;
  const personId = links[0]?.person_id;
  const person = personId
    ? (await database.query<{id:string;status:string;display_name:string;first_name:string|null;last_name:string|null;
      contact_email:string|null;locale:string;version:number}>(
      'SELECT id,status,display_name,first_name,last_name,contact_email,locale,version FROM drivy.person WHERE id=$1',[personId])).rows[0] ?? null
    : null;
  const memberships = personId
    ? (await database.query<{school_id:string;roles:string[];grants:string[];status:string;access_epoch:number;version:number}>(
      'SELECT school_id,roles,grants,status,access_epoch,version FROM drivy.membership WHERE person_id=$1 ORDER BY school_id',[personId])).rows
      .map(row => ({ schoolId:row.school_id, roles:row.roles, grants:row.grants, status:row.status,
        accessEpoch:row.access_epoch, version:row.version }))
    : [];
  const assignments = personId
    ? (await database.query<{id:string;training_id:string;instructor_membership_id:string;valid_from:Date;valid_until:Date|null}>(
      `SELECT a.id,a.training_id,a.instructor_membership_id,a.valid_from,a.valid_until FROM drivy.instructor_assignment a
       JOIN drivy.membership m ON m.id=a.instructor_membership_id AND m.school_id=a.school_id WHERE m.person_id=$1`,[personId])).rows
      .map(row => ({ id:row.id, trainingId:row.training_id, instructorMembershipId:row.instructor_membership_id,
        validFrom:row.valid_from.toISOString(), validUntil:row.valid_until?.toISOString() ?? null }))
    : [];
  const lessonColumns = `l.id,l.training_id,l.learner_id,l.learner_person_id,l.instructor_membership_id,l.status,
    l.planned_start,l.planned_end,l.time_zone,l.meeting_point,l.price_cents_snapshot,l.buffer_minutes_snapshot,
    l.policy_version_id,l.publication_version,l.version`;
  const learnerLessons = personId
    ? (await database.query<LessonRow>(`SELECT ${lessonColumns} FROM drivy.lesson l WHERE l.learner_person_id=$1`,[personId])).rows.map(lessonState)
    : [];
  const instructorLessons = personId
    ? (await database.query<LessonRow>(`SELECT ${lessonColumns} FROM drivy.lesson l
       JOIN drivy.membership m ON m.id=l.instructor_membership_id AND m.school_id=l.school_id WHERE m.person_id=$1`,[personId])).rows.map(lessonState)
    : [];
  const trainings = personId
    ? (await database.query<{id:string;learner_id:string;offering_id:string;offering_key:string;status:string;started_on:string|null;
      closed_on:string|null;version:number}>(`SELECT t.id,t.learner_id,t.offering_id,t.offering_key,t.status,
      to_char(t.started_on,'YYYY-MM-DD') AS started_on,to_char(t.closed_on,'YYYY-MM-DD') AS closed_on,t.version
      FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id WHERE l.person_id=$1`,[personId])).rows
      .map(row => ({ id:row.id, learnerId:row.learner_id, offeringId:row.offering_id, offeringKey:row.offering_key,
        status:row.status, startedOn:row.started_on, closedOn:row.closed_on, version:row.version }))
    : [];
  const profiles = personId
    ? (await database.query<{id:string;profile_id:string|null;administrative_policy_id:string|null;
      profile_updated_at:Date|null;entered_by_membership_id:string|null;entry_source:string|null;
      archived:boolean;version:number}>(`SELECT id,profile_id,administrative_policy_id,profile_updated_at,
      entered_by_membership_id,entry_source,archived_at IS NOT NULL AS archived,version
      FROM drivy.learner_profile WHERE person_id=$1`,[personId])).rows
      .map(row => ({ id:row.id, profileId:row.profile_id, administrativePolicyId:row.administrative_policy_id,
        profileUpdatedAt:row.profile_updated_at?.toISOString() ?? null, enteredByMembershipId:row.entered_by_membership_id,
        entrySource:row.entry_source, archived:row.archived, version:row.version }))
    : [];
  const availability = personId
    ? (await database.query<{id:string;instructor_membership_id:string;weekdays:number[];local_start:string;local_end:string;
      valid_from:string;valid_until:string|null;removed:boolean;version:number}>(`SELECT a.id,a.instructor_membership_id,a.weekdays,
      to_char(a.local_start,'HH24:MI') AS local_start,to_char(a.local_end,'HH24:MI') AS local_end,
      to_char(a.valid_from,'YYYY-MM-DD') AS valid_from,to_char(a.valid_until,'YYYY-MM-DD') AS valid_until,
      a.removed_at IS NOT NULL AS removed,a.version FROM drivy.availability_rule a
      JOIN drivy.membership m ON m.id=a.instructor_membership_id AND m.school_id=a.school_id WHERE m.person_id=$1`,[personId])).rows
      .map(row => ({ id:row.id, instructorMembershipId:row.instructor_membership_id, weekdays:row.weekdays,
        localStart:row.local_start, localEnd:row.local_end, validFrom:row.valid_from, validUntil:row.valid_until,
        removed:row.removed, version:row.version }))
    : [];
  const totals = (await database.query<IdentitySnapshot['totals']>(`SELECT
    (SELECT count(*)::int FROM drivy.person) AS persons,(SELECT count(*)::int FROM drivy.identity_link) AS links,
    (SELECT count(*)::int FROM drivy.membership) AS memberships,(SELECT count(*)::int FROM drivy.instructor_assignment) AS assignments,
    (SELECT count(*)::int FROM drivy.lesson) AS lessons,(SELECT count(*)::int FROM drivy.training) AS trainings,
    (SELECT count(*)::int FROM drivy.learner_profile) AS profiles,(SELECT count(*)::int FROM drivy.availability_rule) AS availability`)).rows[0]!;
  return {
    person: person ? { id:person.id, status:person.status, displayName:person.display_name, firstName:person.first_name,
      lastName:person.last_name, contactEmail:person.contact_email, locale:person.locale, version:person.version } : null,
    links: links.map(row => `${row.issuer}|${row.subject}|${row.person_id}`),
    memberships, assignments, learnerLessons, instructorLessons, trainings, profiles, availability, totals
  };
}

type Inputs = { browser:Browser; origin:string; apiOrigin:string; issuer:string; keycloakOrigin:string; realmName:string;
  adminPassword:string; clientId:string; clientSecret:string; administration:Pool; accounts:RecoveryAccount[];
  ownMail:(email:string)=>Promise<string>; mailLink:(text:string,origin:string,path:string)=>string;
  assert:(value:unknown,label:string)=>void; setStage:(value:string)=>void };

/** Synthetic precondition: the distinct instructor really gives a lesson of the existing training.
 *  The lesson is booked through the school API with the commercial selection of the existing one, so the
 *  administrator's and the learner's lesson keep their own row; no lesson is fabricated in SQL. */
async function ensureInstructorLesson(input:{database:Pool; apiOrigin:string; issuer:string; adminSubject:string;
  instructorSubject:string; learnerSubject:string; accessToken:string}):Promise<{instructorLessons:number;administratorLessons:number}> {
  const {database,apiOrigin,issuer} = input;
  const source=(await database.query<{school_id:string;training_id:string;policy_version_id:string;time_zone:string;
    price_cents_snapshot:string;commercial_selection:{serviceProductVersionId:string;acceptedTermsVersionId:string};minutes:string}>(
    `SELECT l.school_id,l.training_id,l.policy_version_id,l.time_zone,l.price_cents_snapshot,l.commercial_selection,
     extract(epoch FROM (l.planned_end-l.planned_start))/60 AS minutes FROM drivy.lesson l
     JOIN drivy.learner_profile p ON p.school_id=l.school_id AND p.id=l.learner_id
     JOIN drivy.identity_link i ON i.person_id=p.person_id AND i.issuer=$1 AND i.subject=$2
     WHERE l.status='PLANNED' ORDER BY l.created_at LIMIT 1`,[issuer,input.learnerSubject])).rows[0];
  if(!source) throw new Error('RECOVERY_FIXTURE_SOURCE_LESSON_MISSING');
  const instructor=(await database.query<{id:string}>(`SELECT m.id FROM drivy.membership m
    JOIN drivy.identity_link i ON i.person_id=m.person_id AND i.issuer=$1 AND i.subject=$2
    WHERE m.school_id=$3 AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) LIMIT 1`,
    [issuer,input.instructorSubject,source.school_id])).rows[0];
  if(!instructor) throw new Error('RECOVERY_FIXTURE_INSTRUCTOR_MEMBERSHIP_MISSING');
  const counts=async()=>(await database.query<{instructor_lessons:number;administrator_lessons:number}>(`SELECT
    (SELECT count(*)::int FROM drivy.lesson WHERE instructor_membership_id=$1) AS instructor_lessons,
    (SELECT count(*)::int FROM drivy.lesson l JOIN drivy.membership m ON m.id=l.instructor_membership_id
      JOIN drivy.identity_link i ON i.person_id=m.person_id AND i.issuer=$2 AND i.subject=$3) AS administrator_lessons`,
    [instructor.id,issuer,input.adminSubject])).rows[0]!;
  const existing=await counts();
  if(existing.instructor_lessons>0) return { instructorLessons:existing.instructor_lessons, administratorLessons:existing.administrator_lessons };
  const operator={Authorization:`Bearer ${input.accessToken}`};
  const assignmentOperation=randomUUID();
  const assignment=await fetch(`${apiOrigin}/v1/schools/${source.school_id}/trainings/${source.training_id}/assignments`,{
    method:'POST',redirect:'error',signal:AbortSignal.timeout(15_000),
    headers:{...operator,'Content-Type':'application/json','Idempotency-Key':assignmentOperation},
    body:JSON.stringify({operationId:assignmentOperation,instructorMembershipId:instructor.id,
      validFrom:new Date(Date.now()-120_000).toISOString()})});
  if(assignment.status!==201) {
    // An assignment that already covers this training is the only tolerable refusal: it leaves the same business state.
    if(!(await assignment.text()).includes('ASSIGNMENT_CONFLICT')) throw new Error('RECOVERY_FIXTURE_ASSIGNMENT_FAILED');
  }
  const search=new URLSearchParams({trainingId:source.training_id,instructorMembershipId:instructor.id,
    durationMinutes:String(Number(source.minutes)),bufferMinutes:'0',timeZone:source.time_zone,days:'14'});
  const slots=await fetch(`${apiOrigin}/v1/schools/${source.school_id}/lessons/next-slot?${search}`,{redirect:'error',
    signal:AbortSignal.timeout(15_000),headers:operator});
  if(!slots.ok) throw new Error('RECOVERY_FIXTURE_SLOT_FAILED');
  const slot=(await slots.json() as {data:{slot:{plannedStart:string;plannedEnd:string}|null}}).data.slot;
  if(!slot) throw new Error('RECOVERY_FIXTURE_SLOT_MISSING');
  const lessonOperation=randomUUID();
  const created=await fetch(`${apiOrigin}/v1/schools/${source.school_id}/lessons`,{method:'POST',redirect:'error',
    signal:AbortSignal.timeout(15_000),headers:{...operator,'Content-Type':'application/json','Idempotency-Key':lessonOperation},
    body:JSON.stringify({operationId:lessonOperation,trainingId:source.training_id,instructorMembershipId:instructor.id,
      plannedStart:slot.plannedStart,plannedEnd:slot.plannedEnd,timeZone:source.time_zone,
      meetingPoint:'Point de rencontre synthétique du moniteur',agreedPriceCents:Number(source.price_cents_snapshot),bufferMinutes:0,
      policyVersionId:source.policy_version_id,commercialSelection:{mode:'UNIT_PRICE',
        serviceProductVersionId:source.commercial_selection.serviceProductVersionId,quantity:1,entitlementLotId:null,
        acceptedTermsVersionId:source.commercial_selection.acceptedTermsVersionId}})});
  if(created.status!==201) throw new Error('RECOVERY_FIXTURE_LESSON_FAILED');
  const booked=await counts();
  return { instructorLessons:booked.instructor_lessons, administratorLessons:booked.administrator_lessons };
}
type KeycloakUser = { id:string; username:string; email?:string; emailVerified:boolean; createdTimestamp:number; enabled:boolean };

export async function verifyAccountRecovery(input:Inputs) {
  const { browser,origin,apiOrigin,issuer,keycloakOrigin,realmName,clientId,clientSecret,administration,assert,setStage } = input;
  const adminResponse = await fetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`, {method:'POST',
    body:new URLSearchParams({client_id:'admin-cli',grant_type:'password',username:'drivy-e2e-admin',password:input.adminPassword})});
  if (!adminResponse.ok) throw new Error('RECOVERY_ADMIN_UNAVAILABLE');
  const admin = await adminResponse.json() as {access_token:string};
  const headers = {Authorization:`Bearer ${admin.access_token}`,'Content-Type':'application/json'};
  const realmURL = `${keycloakOrigin}/admin/realms/${realmName}`;
  const realmResponse = await fetch(realmURL,{headers});
  if (!realmResponse.ok) throw new Error('RECOVERY_REALM_UNAVAILABLE');
  const initial = await realmResponse.json() as {smtpServer:Record<string,string>;actionTokenGeneratedByUserLifespan:number;attributes?:Record<string,string>};
  const tokenURL = `${issuer}/protocol/openid-connect/token`;
  const grant = (email:string,password:string) => fetch(tokenURL,{method:'POST',body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,
    grant_type:'password',scope:'openid profile email',username:email,password})});
  const renewal = (refresh_token:string) => fetch(tokenURL,{method:'POST',body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,
    grant_type:'refresh_token',refresh_token})});
  const userByEmail = async (email:string) => {
    const response = await fetch(`${realmURL}/users?email=${encodeURIComponent(email)}&exact=true`,{headers});
    if (!response.ok) throw new Error('RECOVERY_IDENTITY_UNAVAILABLE');
    const users = await response.json() as KeycloakUser[];
    if (users.length !== 1) throw new Error('RECOVERY_IDENTITY_INVALID');
    return users[0]!;
  };
  /** Disposable-realm fixture: an account whose password was never stored gets a synthetic one, never a real secret. */
  const setPassword = async (user:KeycloakUser,value:string) => {
    const response = await fetch(`${realmURL}/users/${user.id}/reset-password`,{method:'PUT',headers,
      body:JSON.stringify({type:'password',value,temporary:false})});
    if (response.status !== 204) throw new Error('RECOVERY_IDENTITY_UPDATE_FAILED');
  };
  const apiIdentity = async (accessToken:string) => {
    const response = await fetch(`${apiOrigin}/v1/me`,{headers:{Authorization:`Bearer ${accessToken}`}});
    if (!response.ok) throw new Error('RECOVERY_IDENTITY_READ_FAILED');
    return (await response.json() as {data:{personId?:string;subject?:string;memberships:unknown[]}}).data;
  };
  const contexts: Awaited<ReturnType<Browser['newContext']>>[] = [];
  async function page() {
    const context = await browser.newContext({locale:'fr-CH'}); contexts.push(context);
    await context.route('**/*', route => [origin,keycloakOrigin].includes(new URL(route.request().url()).origin) ? route.continue() : route.abort());
    const result = await context.newPage(); result.setDefaultTimeout(15_000); return result;
  }
  /** Same entry as a person without a password: the portal opens the provider's autonomous reset page. */
  async function requestLink(target:Page,address:string) {
    await target.goto(`${origin}/app/recover`);
    await target.getByRole('button',{name:'Récupérer mon accès',exact:true}).click();
    await target.locator('input[name="username"]').fill(address);
    await target.locator('input[type="submit"],button[type="submit"]').click();
    await target.getByText(RECOVERY_CONDITIONAL_MESSAGE,{exact:true}).waitFor();
    return target.getByText(RECOVERY_CONDITIONAL_MESSAGE,{exact:true}).innerText();
  }
  const nextLink = async (address:string) => input.mailLink(await input.ownMail(address),keycloakOrigin,
    `/realms/${realmName}/login-actions/action-token`);
  async function updateRealm(body:unknown) {
    const response = await fetch(realmURL,{method:'PUT',headers,body:JSON.stringify(body)});
    if (!response.ok) throw new Error('RECOVERY_REALM_UPDATE_FAILED');
  }
  try {
    setStage('récupération : disponibilité anonyme et SMTP réel');
    const availability = await fetch(`${apiOrigin}/v1/account-recovery/options`);
    const options = await availability.json() as {data:{available:boolean;recoveryUrl:string|null}};
    assert(availability.ok && options.data.available && options.data.recoveryUrl === `${origin}/app/recover`,
      'La récupération expose uniquement une entrée contrôlée, sans adresse ni jeton');

    setStage('récupération : leçon réelle donnée par le moniteur distinct');
    const adminAccount = input.accounts.find(account => account.role === 'ADMIN');
    const instructorAccount = input.accounts.find(account => account.role === 'INSTRUCTOR');
    const learnerAccount = input.accounts.find(account => account.role === 'LEARNER');
    if (!adminAccount || !instructorAccount || !learnerAccount) throw new Error('RECOVERY_ROLES_INCOMPLETE');
    const adminUser = await userByEmail(adminAccount.email), instructorUser = await userByEmail(instructorAccount.email),
      learnerUser = await userByEmail(learnerAccount.email);
    const fixturePassword = adminAccount.password ?? randomBytes(24).toString('base64url');
    if (adminAccount.password === undefined) await setPassword(adminUser,fixturePassword);
    const fixtureSession = await grant(adminAccount.email,fixturePassword);
    if (!fixtureSession.ok) throw new Error('RECOVERY_SESSION_UNAVAILABLE');
    const fixtureTokens = await fixtureSession.json() as {access_token:string};
    const fixture = await ensureInstructorLesson({database:administration,apiOrigin,issuer,adminSubject:adminUser.id,
      instructorSubject:instructorUser.id,learnerSubject:learnerUser.id,accessToken:fixtureTokens.access_token});
    assert(fixture.instructorLessons >= 1 && fixture.administratorLessons >= 1,
      'Le moniteur distinct donne sa propre leçon, en plus de celle de l’administrateur, sans la remplacer');

    for (const account of input.accounts) {
      const label = roleLabel[account.role];
      setStage(`récupération · ${label} : identité, écoles, droits et leçons avant`);
      const user = await userByEmail(account.email);
      const previousPassword = account.password ?? randomBytes(24).toString('base64url');
      if (account.password === undefined) await setPassword(user,previousPassword);
      const previousSession = await grant(account.email,previousPassword);
      if (!previousSession.ok) throw new Error('RECOVERY_SESSION_UNAVAILABLE');
      const previousTokens = await previousSession.json() as {access_token:string;refresh_token:string};
      const previousIdentity = await apiIdentity(previousTokens.access_token);
      const before = await readIdentitySnapshot(administration,issuer,user.id);
      const gaps = requirementGaps(before,account.role);
      assert(gaps.length === 0,`Le compte ${label} possède avant la récupération ses rattachements et ses objets métier réels${gaps.length ? ` (${gaps.join(', ')})` : ''}`);

      setStage(`récupération · ${label} : demande de lien depuis l’entrée contrôlée`);
      const target = await page();
      const message = await requestLink(target,account.email);
      if (account.role === 'ADMIN') {
        const unknownMessage = await requestLink(await page(),`unknown-${randomBytes(8).toString('hex')}@example.invalid`);
        assert(message === unknownMessage && message === RECOVERY_CONDITIONAL_MESSAGE,
          'Une adresse connue et une adresse inconnue reçoivent la même réponse conditionnelle, mot pour mot');
      }
      const link = await nextLink(account.email);

      setStage(`récupération · ${label} : lien réel, nouveau mot de passe et politique de sessions`);
      const nextPassword = randomBytes(24).toString('base64url');
      await target.goto(link);
      await target.locator('input[name="password-new"]').fill(nextPassword);
      await target.locator('input[name="password-confirm"]').fill(nextPassword);
      if (account.revokeOtherSessions) await target.locator('input[name="logout-sessions"]').check();
      await target.locator('input[type="submit"],button[type="submit"]').click();
      await target.locator('input[name="password-new"]').waitFor({state:'detached'});
      const refusedOld = await grant(account.email,previousPassword);
      const acceptedNew = await grant(account.email,nextPassword);
      if (!acceptedNew.ok) throw new Error('RECOVERY_NEW_PASSWORD_REFUSED');
      const nextTokens = await acceptedNew.json() as {access_token:string;refresh_token:string};
      assert(refusedOld.status === 400,`${label} : l’ancien mot de passe est refusé après la récupération`);
      const previousRenewal = await renewal(previousTokens.refresh_token);
      if (account.revokeOtherSessions) {
        assert(previousRenewal.status === 400,`${label} : « Se déconnecter des autres appareils » révoque le renouvellement antérieur`);
      } else {
        assert(previousRenewal.ok,`${label} : sans la case cochée, le renouvellement antérieur reste valide et rien n’est présenté comme révoqué`);
      }
      const stillValid = await apiIdentity(previousTokens.access_token);
      assert(stable(stillValid.memberships) === stable(previousIdentity.memberships),
        `${label} : un jeton d’accès déjà émis reste valide jusqu’à son expiration, la révocation porte sur le renouvellement`);

      setStage(`récupération · ${label} : même personne, mêmes écoles, mêmes droits et mêmes leçons après`);
      const after = await readIdentitySnapshot(administration,issuer,user.id);
      const differences = snapshotDifferences(before,after);
      assert(differences.length === 0,`${label} : la récupération conserve personne, écoles, rôles et leçons${differences.length ? ` (${differences.join(', ')})` : ''}`);
      const afterUser = await userByEmail(account.email);
      assert(afterUser.id === user.id && afterUser.createdTimestamp === user.createdTimestamp
        && afterUser.username === user.username && afterUser.emailVerified === user.emailVerified,
        `${label} : l’identité OIDC reste la même, adresse toujours vérifiée, sans nouvelle personne`);
      const afterIdentity = await apiIdentity(nextTokens.access_token);
      assert(stable(afterIdentity) === stable(previousIdentity), `${label} : les droits lus par l’API restent identiques, sans élévation`);
      const session = await target.context().request.get(`${origin}/app/bff/session`);
      assert((await session.json()).authenticated === false,`${label} : la récupération ne crée aucune session applicative`);
      assert(!(await target.context().request.get(`${origin}/app/bff/me`)).ok(),`${label} : la récupération ne donne accès à aucune identité Drivy`);

      setStage(`récupération · ${label} : lien consommé`);
      const replay = await page(); await replay.goto(link);
      assert(await replay.locator('input[name="password-new"]').count() === 0,`${label} : le lien consommé ne permet pas une seconde réinitialisation`);
    }

    setStage('récupération : lien expiré');
    await updateRealm({actionTokenGeneratedByUserLifespan:1,attributes:{...initial.attributes,'actionTokenGeneratedByUserLifespan.reset-credentials':'1'}});
    const expiryPage = await page(); await requestLink(expiryPage,input.accounts[0]!.email);
    const expiredLink = await nextLink(input.accounts[0]!.email);
    await new Promise(done => setTimeout(done,2100));
    await expiryPage.goto(expiredLink);
    assert(await expiryPage.locator('input[name="password-new"]').count() === 0,'Un lien expiré ne permet pas de changer le mot de passe');

    setStage('récupération : panne SMTP sans annonce de livraison');
    await updateRealm({smtpServer:{...initial.smtpServer,host:'127.0.0.1',port:'1'}});
    const failedMailPage = await page();
    assert(await requestLink(failedMailPage,input.accounts[0]!.email) === RECOVERY_CONDITIONAL_MESSAGE,
      'Une panne SMTP garde la réponse conditionnelle et ne révèle pas l’existence du compte');

    setStage('récupération : perte de connexion, résultat honnête');
    const offlinePage = await page();
    await offlinePage.route('**/app/bff/account-recovery/start',route => route.abort('failed'));
    await offlinePage.goto(`${origin}/app/recover`);
    await offlinePage.getByRole('button',{name:'Récupérer mon accès',exact:true}).click();
    await offlinePage.getByText(RECOVERY_UNAVAILABLE_MESSAGE,{exact:true}).waitFor();
    assert(await offlinePage.getByRole('button',{name:'Réessayer',exact:true}).isVisible()
      && await offlinePage.getByText(RECOVERY_CONDITIONAL_MESSAGE,{exact:true}).count() === 0,
      'Une perte de connexion affiche un échec honnête et ne prétend pas qu’un message est parti');
  } finally {
    await updateRealm({smtpServer:initial.smtpServer,actionTokenGeneratedByUserLifespan:initial.actionTokenGeneratedByUserLifespan,
      attributes:{...initial.attributes,'actionTokenGeneratedByUserLifespan.reset-credentials':''}});
    await Promise.all(contexts.map(context => context.close()));
  }
}
