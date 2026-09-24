import type { PoolClient, QueryResultRow } from 'pg';
import type { Actor, Membership } from './database.js';
import type { Position } from './cursor.js';
import { notFound } from './errors.js';

export interface LearnerFilters {
  q?: string | undefined; trainingStatus?: string | undefined; status: 'ACTIVE' | 'ARCHIVED' | 'ALL';
  instructorMembershipId?: string | undefined; categoryCode?: string | undefined; requiresAction?: boolean | undefined;
}
type PageRow = QueryResultRow & { id: string; _createdAt: string };
// Conserver les microsecondes PostgreSQL : Date JavaScript les tronquerait et répéterait la dernière ligne.
const cursorTimestamp = (alias: string) => `to_char(${alias}.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
const learnerColumns = `l.id, l.school_id AS "schoolId", l.version, l.person_id AS "personId",
  l.display_name AS "displayName", l.contact_email AS "contactEmail", l.contact_phone AS "contactPhone",
  l.archived_at AS "archivedAt", l.profile_readiness AS "profileReadiness"`;
const trainingColumns = `t.id, t.school_id AS "schoolId", t.version, t.learner_id AS "learnerId",
  t.offering_id AS "offeringId", o.category_code AS "categoryCode", t.status,
  to_char(t.started_on,'YYYY-MM-DD') AS "startedOn", to_char(t.closed_on,'YYYY-MM-DD') AS "closedOn"`;
// $1 école, $2 personne authentifiée, $3 appartenance courante, $4 rôles relus en base.
const assigned = (alias: string) => `EXISTS (SELECT 1 FROM drivy.instructor_assignment a
  WHERE a.school_id=$1 AND a.training_id=${alias}.id AND a.instructor_membership_id=$3
    AND a.valid_from <= statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until > statement_timestamp()))`;
const visibleTraining = (alias: string) => `('ADMIN'=ANY($4::text[])
  OR ('LEARNER'=ANY($4::text[]) AND l.person_id=$2)
  OR ('INSTRUCTOR'=ANY($4::text[]) AND ${assigned(alias)}))`;
const visibleLearner = `('ADMIN'=ANY($4::text[]) OR ('LEARNER'=ANY($4::text[]) AND l.person_id=$2)
  OR ('INSTRUCTOR'=ANY($4::text[]) AND EXISTS (SELECT 1 FROM drivy.training visible_t
    WHERE visible_t.school_id=$1 AND visible_t.learner_id=l.id AND ${assigned('visible_t')})))`;
const params = (schoolId: string, actor: Actor, membership: Membership) => [schoolId, actor.personId, membership.id, membership.roles];
export async function getLearner(db: PoolClient, schoolId: string, actor: Actor, member: Membership, id: string) {
  const result = await db.query(`SELECT ${learnerColumns} FROM drivy.learner_profile l WHERE l.school_id=$1 AND ${visibleLearner} AND l.id=$5`, [...params(schoolId, actor, member), id]);
  if (!result.rows[0]) throw notFound();
  return result.rows[0];
}
export async function getTraining(db: PoolClient, schoolId: string, actor: Actor, member: Membership, id: string) {
  const result = await db.query(`SELECT ${trainingColumns} FROM drivy.training t
    JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
    JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
    WHERE t.school_id=$1 AND ${visibleTraining('t')} AND t.id=$5`, [...params(schoolId, actor, member), id]);
  if (!result.rows[0]) throw notFound();
  return result.rows[0];
}
export async function listLearners(db: PoolClient, schoolId: string, actor: Actor, member: Membership,
  filters: LearnerFilters, limit: number, position: Position | undefined): Promise<PageRow[]> {
  const values: unknown[] = params(schoolId, actor, member);
  const bind = (value: unknown) => { values.push(value); return `$${values.length}`; };
  const conditions = ['l.school_id=$1', visibleLearner];
  if (filters.status !== 'ALL') conditions.push(`l.archived_at IS ${filters.status === 'ACTIVE' ? '' : 'NOT '}NULL`);
  if (filters.q) conditions.push(`strpos(lower(l.display_name), lower(${bind(filters.q)})) > 0`);
  if (filters.requiresAction !== undefined) conditions.push(`(l.profile_readiness='ACTION_REQUIRED')=${bind(filters.requiresAction)}`);
  const trainingConditions = ['ft.school_id=$1', 'ft.learner_id=l.id', visibleTraining('ft')];
  if (filters.trainingStatus) trainingConditions.push(`ft.status=${bind(filters.trainingStatus)}`);
  if (filters.categoryCode) trainingConditions.push(`fo.category_code=${bind(filters.categoryCode)}`);
  if (filters.instructorMembershipId) trainingConditions.push(`EXISTS (SELECT 1 FROM drivy.instructor_assignment fa
    WHERE fa.school_id=$1 AND fa.training_id=ft.id AND fa.instructor_membership_id=${bind(filters.instructorMembershipId)}
    AND fa.valid_from<=statement_timestamp() AND (fa.valid_until IS NULL OR fa.valid_until>statement_timestamp()))`);
  if (filters.trainingStatus || filters.categoryCode || filters.instructorMembershipId) conditions.push(`EXISTS (
    SELECT 1 FROM drivy.training ft JOIN drivy.offering_version fo ON fo.school_id=ft.school_id AND fo.id=ft.offering_id
    WHERE ${trainingConditions.join(' AND ')})`);
  if (position) conditions.push(`(l.created_at,l.id)>(${bind(position.createdAt)}::timestamptz,${bind(position.id)}::uuid)`);
  return (await db.query<PageRow>(`SELECT ${learnerColumns},${cursorTimestamp('l')} AS "_createdAt" FROM drivy.learner_profile l
    WHERE ${conditions.join(' AND ')} ORDER BY l.created_at,l.id LIMIT ${bind(limit + 1)}`, values)).rows;
}
export async function listTrainings(db: PoolClient, schoolId: string, actor: Actor, member: Membership,
  learnerId: string | undefined, limit: number, position: Position | undefined): Promise<PageRow[]> {
  const values: unknown[] = params(schoolId, actor, member);
  const conditions = ['t.school_id=$1', visibleTraining('t')];
  const bind = (value: unknown) => { values.push(value); return `$${values.length}`; };
  if (learnerId) conditions.push(`t.learner_id=${bind(learnerId)}`);
  if (position) conditions.push(`(t.created_at,t.id)>(${bind(position.createdAt)}::timestamptz,${bind(position.id)}::uuid)`);
  return (await db.query<PageRow>(`SELECT ${trainingColumns},${cursorTimestamp('t')} AS "_createdAt" FROM drivy.training t
    JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
    JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
    WHERE ${conditions.join(' AND ')} ORDER BY t.created_at,t.id LIMIT ${bind(limit + 1)}`, values)).rows;
}
