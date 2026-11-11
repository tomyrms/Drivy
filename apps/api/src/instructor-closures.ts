import type {PoolClient} from 'pg';

/**
 * Fermetures (congés) d'un moniteur : une indisponibilité confirmée vaut pour toute occupation de son agenda, pas seulement
 * pour les leçons (#423). Les fermetures ne sont pas des lignes de drivy.reservation : l'exclusion commune ne les voit pas, d'où
 * ces contrôles explicites, rejoués dans la transaction de chaque commande.
 * La concurrence est tranchée par le verrou d'école que prend toute commande (commands.ts) : deux commandes d'une même école
 * ne s'exécutent jamais en même temps, la seconde relit donc l'état validé par la première.
 * Intervalles semi-ouverts [début, fin) : un engagement qui commence quand le congé finit reste possible.
 */
export async function overlapsClosure(db:PoolClient,schoolId:string,instructorMembershipId:string,startsAt:string,endsAt:string):Promise<boolean>{
 // Fonction autorisée (oui/non) : la table des congés reste illisible pour un moniteur qui n'est pas ce collègue (RLS schedule_read).
 return (await db.query<{unavailable:boolean}>('SELECT drivy.instructor_unavailable($1,$2,$3::timestamptz,$4::timestamptz) AS unavailable',[schoolId,instructorMembershipId,startsAt,endsAt])).rows[0]!.unavailable;
}
export interface ClosureBookings {lessons:number;courses:number;exams:number}
/** Engagements existants du moniteur recouvrant une fermeture à créer (fonction SQL réservée à qui gère ce moniteur). */
export async function bookingsUnderClosure(db:PoolClient,schoolId:string,instructorMembershipId:string,startsAt:string,endsAt:string):Promise<ClosureBookings>{
 return (await db.query<ClosureBookings>('SELECT lessons,courses,exams FROM drivy.closure_bookings($1,$2,$3::timestamptz,$4::timestamptz)',[schoolId,instructorMembershipId,startsAt,endsAt])).rows[0]!;
}
export function describeBookings(value:ClosureBookings):string{
 const parts=[[value.lessons,'leçon','leçons'],[value.courses,'séance de cours','séances de cours'],[value.exams,'accompagnement d’examen','accompagnements d’examen']] as const;
 return parts.filter(([count])=>count>0).map(([count,one,many])=>`${count} ${count===1?one:many}`).join(', ');
}
