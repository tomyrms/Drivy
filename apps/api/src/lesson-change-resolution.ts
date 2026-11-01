import type {PoolClient} from 'pg';
import {ApiError,notFound} from './errors.js';

/**
 * Réponse du personnel à une demande de l'élève (#52). Accepter n'a pas de commande propre : le moniteur ou l'administration déplace ou
 * annule la leçon par les commandes existantes, qui relisent tous leurs contrôles, et désignent la demande par changeRequestId.
 * Ce module reste sans dépendance vers lessons.ts pour que celui-ci puisse l'appeler.
 */
export type ChangeOutcome='MOVED'|'CANCELLED';
const kindFor:Record<ChangeOutcome,'RESCHEDULE'|'CANCEL'>={MOVED:'RESCHEDULE',CANCELLED:'CANCEL'};

/** À appeler avant d'écrire : la demande désignée doit exister pour cette leçon, être en attente et porter sur la même action. */
export async function requireChangeRequest(db:PoolClient,schoolId:string,lessonId:string,requestId:string,outcome:ChangeOutcome){
 const row=(await db.query<{status:string;kind:string}>('SELECT status,kind FROM drivy.lesson_change_request WHERE school_id=$1 AND lesson_id=$2 AND id=$3',[schoolId,lessonId,requestId])).rows[0];
 if(!row)throw notFound();
 if(row.status!=='PENDING')throw new ApiError(409,'LESSON_CHANGE_REQUEST_CLOSED','Cette demande est déjà traitée.');
 if(row.kind!==kindFor[outcome])throw new ApiError(422,'LESSON_CHANGE_REQUEST_KIND','Cette demande ne porte pas sur cette action.');
}

/**
 * À appeler après l'écriture de la leçon. La demande désignée devient ACCEPTED ; une autre demande en attente que le changement rend
 * caduque devient SUPERSEDED (toute demande si la leçon est annulée, les demandes de déplacement si elle est déplacée). Une demande
 * d'annulation survit à un déplacement du personnel : l'élève veut toujours annuler.
 */
export async function settleChangeRequests(db:PoolClient,value:{schoolId:string;lessonId:string;membershipId:string;outcome:ChangeOutcome;acceptedId?:string|null}){
 await db.query(`UPDATE drivy.lesson_change_request SET status=CASE WHEN id=$3::uuid THEN 'ACCEPTED' ELSE 'SUPERSEDED' END,version=version+1,
   resolved_by_membership_id=$4,resolved_at=statement_timestamp(),updated_at=statement_timestamp()
  WHERE school_id=$1 AND lesson_id=$2 AND status='PENDING' AND ($5::text='CANCELLED' OR kind='RESCHEDULE' OR id=$3::uuid)`,
  [value.schoolId,value.lessonId,value.acceptedId??null,value.membershipId,value.outcome]);
}
