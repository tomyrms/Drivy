/** Real Keycloak/Mailpit qualification of access recovery on disposable synthetic accounts.
 *  Three real roles are recovered on their own existing person, school and objects; nothing here persists a mail
 *  link, a password, a token or a request trace. */
import { randomBytes } from 'node:crypto';
import type { Pool } from 'pg';
import type { Browser, Page } from '../../infra/dev/browser.js';

/** The Drivy login theme answers the same conditional sentence for a known address, an unknown one and a failing relay. */
export const RECOVERY_CONDITIONAL_MESSAGE = 'Si cette adresse correspond à un compte, vous pourrez recevoir un lien de récupération. Si aucun message n’arrive, réessayez plus tard.';
/** State shown by `/app/recover` when the entry cannot be opened: an honest failure, never a claimed delivery. */
export const RECOVERY_UNAVAILABLE_MESSAGE = 'La récupération est momentanément indisponible.';

export type RecoveryRole = 'ADMIN' | 'INSTRUCTOR' | 'LEARNER';
export type RecoveryAccount = { role:RecoveryRole; email:string; password?:string; revokeOtherSessions:boolean };
export type MembershipState = { schoolId:string; roles:string[]; grants:string[]; status:string; accessEpoch:number };
/** Everything a recovery must leave exactly as it was: identity, attachments, rights and business objects. */
export type IdentitySnapshot = {
  person: { id:string; status:string; displayName:string } | null;
  links: string[];
  memberships: MembershipState[];
  learnerLessons: string[];
  instructorLessons: string[];
  trainings: string[];
  profiles: string[];
  availability: string[];
  totals: { persons:number; links:number; memberships:number; lessons:number };
};

const roleLabel: Record<RecoveryRole,string> = { ADMIN:'administrateur', INSTRUCTOR:'moniteur', LEARNER:'élève' };
const stable = (value:unknown) => JSON.stringify(value);
/** Reading order is not identity: the same rows in another order are not a difference. */
const ordered = (snapshot:IdentitySnapshot):IdentitySnapshot => ({
  ...snapshot,
  links: [...snapshot.links].sort(),
  memberships: [...snapshot.memberships].map(item => ({...item, roles:[...item.roles].sort(), grants:[...item.grants].sort()}))
    .sort((left,right) => left.schoolId.localeCompare(right.schoolId)),
  learnerLessons: [...snapshot.learnerLessons].sort(),
  instructorLessons: [...snapshot.instructorLessons].sort(),
  trainings: [...snapshot.trainings].sort(),
  profiles: [...snapshot.profiles].sort(),
  availability: [...snapshot.availability].sort()
});

/** Named differences only: no identifier ever reaches a check label or an artifact. */
export function snapshotDifferences(before:IdentitySnapshot, after:IdentitySnapshot):string[] {
  const left = ordered(before), right = ordered(after);
  const sections:[string,unknown,unknown][] = [
    ['liens d’identité', left.links, right.links],
    ['identité de personne', left.person, right.person],
    ['rattachements, rôles et droits', left.memberships, right.memberships],
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
  }
  if (role === 'LEARNER') {
    if (snapshot.profiles.length === 0) gaps.push('au moins un dossier élève');
    if (snapshot.trainings.length === 0) gaps.push('au moins une formation');
    if (snapshot.learnerLessons.length === 0) gaps.push('au moins une leçon suivie');
  }
  return gaps;
}

/** Durable state read through the application schema, not through the identity provider's claims. */
export async function readIdentitySnapshot(database:Pool, issuer:string, subject:string):Promise<IdentitySnapshot> {
  const links = (await database.query<{issuer:string;subject:string;person_id:string}>(
    'SELECT issuer,subject,person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2 ORDER BY issuer,subject',[issuer,subject])).rows;
  const personId = links[0]?.person_id;
  const person = personId
    ? (await database.query<{id:string;status:string;display_name:string}>('SELECT id,status,display_name FROM drivy.person WHERE id=$1',[personId])).rows[0] ?? null
    : null;
  const memberships = personId
    ? (await database.query<{school_id:string;roles:string[];grants:string[];status:string;access_epoch:number}>(
      'SELECT school_id,roles,grants,status,access_epoch FROM drivy.membership WHERE person_id=$1 ORDER BY school_id',[personId])).rows
      .map(row => ({ schoolId:row.school_id, roles:row.roles, grants:row.grants, status:row.status, accessEpoch:row.access_epoch }))
      .sort((left,right) => left.schoolId.localeCompare(right.schoolId))
    : [];
  const ids = async (sql:string) => personId
    ? (await database.query<{id:string}>(sql,[personId])).rows.map(row => row.id).sort() : [];
  const totals = (await database.query<{persons:number;links:number;memberships:number;lessons:number}>(`SELECT
    (SELECT count(*)::int FROM drivy.person) AS persons,(SELECT count(*)::int FROM drivy.identity_link) AS links,
    (SELECT count(*)::int FROM drivy.membership) AS memberships,(SELECT count(*)::int FROM drivy.lesson) AS lessons`)).rows[0]!;
  return {
    person: person ? { id:person.id, status:person.status, displayName:person.display_name } : null,
    links: links.map(row => `${row.issuer}|${row.subject}`),
    memberships,
    learnerLessons: await ids('SELECT id FROM drivy.lesson WHERE learner_person_id=$1'),
    instructorLessons: await ids(`SELECT l.id FROM drivy.lesson l
      JOIN drivy.membership m ON m.id=l.instructor_membership_id AND m.school_id=l.school_id WHERE m.person_id=$1`),
    trainings: await ids(`SELECT t.id FROM drivy.training t
      JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id WHERE l.person_id=$1`),
    profiles: await ids('SELECT id FROM drivy.learner_profile WHERE person_id=$1'),
    availability: await ids(`SELECT a.id FROM drivy.availability_rule a
      JOIN drivy.membership m ON m.id=a.instructor_membership_id AND m.school_id=a.school_id WHERE m.person_id=$1`),
    totals
  };
}

type Inputs = { browser:Browser; origin:string; apiOrigin:string; issuer:string; keycloakOrigin:string; realmName:string;
  adminPassword:string; clientId:string; clientSecret:string; administration:Pool; accounts:RecoveryAccount[];
  ownMail:(email:string)=>Promise<string>; mailLink:(text:string,origin:string,path:string)=>string;
  assert:(value:unknown,label:string)=>void; setStage:(value:string)=>void };
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
