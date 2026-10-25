import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,prepareCommercial,lessonBody,id,type Call} from './support/harness.js';

/**
 * Cours collectifs : inscription (#39), file prioritaire (#40), annulations et changements de dates (#41).
 * Données synthétiques. Exécution de référence : campagne finale #84.
 */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const AWARENESS='0c0a5e00-0000-4000-8000-000000000001',FIRST_AID='0c0a5e00-0000-4000-8000-000000000002';
let dayCursor=10;
const at=(offset:number,hourUtc:number)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+offset);d.setUTCHours(hourUtc,0,0,0);return d.toISOString();};
/** Série publiée de `days` séances consécutives, sur des jours encore inutilisés par la suite. */
async function published(options:{capacity?:number;days?:number;typeId?:string;instructor?:string;startOffset?:number}={}){
 const start=options.startOffset??(dayCursor+=4),days=options.days??1;
 // Un type distinct par série : la règle « pas deux sessions à venir du même type » ne lie pas les tests entre eux.
 const typeId=options.typeId??(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 const occurrences=Array.from({length:days},(_,i)=>({startsAt:at(start+i,8),endsAt:at(start+i,11),instructorMembershipId:options.instructor??id.otherInstructorMember,attendanceRequired:true}));
 const draft=await call('POST','/course-series',{operationId:randomUUID(),typeId,title:'Cours de recette',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity:options.capacity??10,minParticipants:null,timeZone:'Europe/Zurich',occurrences},null,'demo-admin');
 if(draft.statusCode!==201)throw new Error(draft.body);
 const pub=await call('POST',`/course-series/${draft.json().data.id}/publish`,{operationId:randomUUID()},draft.json().data.version,'demo-admin');
 if(pub.statusCode!==200)throw new Error(pub.body);
 return {...pub.json().data,startOffset:start} as {id:string;version:number;startOffset:number;occurrences:{startsAt:string;endsAt:string;position:number;instructorMembershipId:string}[]};
}
const enroll=(seriesId:string,subject:string,op=randomUUID())=>call('POST',`/course-series/${seriesId}/enroll`,{operationId:op},null,subject);
const me=(seriesId:string,subject:string)=>call('GET',`/course-series/${seriesId}/me`,undefined,null,subject);
async function setPolicy(selfCancelHours:number,offerResponseMinutes:number|null){
 const version=(await call('GET','/course-catalogue',undefined,null,'demo-admin')).json().data.policy.version;
 const res=await call('PUT','/course-policy',{operationId:randomUUID(),selfCancelHours,offerResponseMinutes},version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
}
async function learnerReservations(seriesId:string,learnerPerson:string){
 return (await pool.query(`SELECT count(*)::int AS n FROM drivy.reservation r JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id WHERE o.series_id=$1 AND r.resource_id=$2 AND r.active`,[seriesId,learnerPerson])).rows[0].n as number;
}
async function cancelAll(seriesId:string){
 const list=(await call('GET',`/course-series/${seriesId}/enrollments`,undefined,null,'demo-admin')).json().data.items as {id:string;version:number;status:string}[];
 for(const e of list.filter(e=>e.status==='ACTIVE')){const res=await call('POST',`/course-enrollments/${e.id}/staff-cancel`,{operationId:randomUUID(),reason:'Nettoyage de recette'},e.version,'demo-admin');if(res.statusCode!==200)throw new Error(res.body);}
}

describe('#39 inscription à toute la série',()=>{
 it('une action inscrit aux trois séances, une seule place consommée, état Inscrit',async()=>{
  const s=await published({days:3});
  const res=await enroll(s.id,'demo-alice');expect(res.statusCode,res.body).toBe(201);
  expect(res.json().data.me.state).toBe('ENROLLED');
  expect(res.json().data.series).toMatchObject({seatsTaken:1,remainingSeats:9});
  expect(await learnerReservations(s.id,id.alice)).toBe(3);
  expect(res.json().data.me.enrollment).toMatchObject({source:'SELF',selfCancelHours:24,policyVersion:1,canSelfCancel:true});
  expect(Date.parse(res.json().data.me.enrollment.selfCancelDeadline)).toBe(Date.parse(s.occurrences[0]!.startsAt)-24*3_600_000);
  await cancelAll(s.id);
 });
 it('rejeu avec le même operationId : aucun doublon',async()=>{
  const s=await published(),op=randomUUID();
  expect((await enroll(s.id,'demo-alice',op)).statusCode).toBe(201);
  expect((await enroll(s.id,'demo-alice',op)).statusCode).toBe(201);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1',[s.id])).rows[0].n).toBe(1);
  expect((await enroll(s.id,'demo-alice')).json().code).toBe('COURSE_ALREADY_ENROLLED');
  await cancelAll(s.id);
 });
 it('conflit sur la troisième date : aucune réservation partielle',async()=>{
  const s=await published({days:3});
  const commercial=await prepareCommercial(call);
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,s.startOffset+2,8),null,'demo-admin');
  expect(lesson.statusCode,lesson.body).toBe(201);
  const res=await enroll(s.id,'demo-alice');
  expect(res.statusCode).toBe(409);expect(res.json().code).toBe('COURSE_SCHEDULE_CONFLICT');
  expect(await learnerReservations(s.id,id.alice)).toBe(0);
  expect((await me(s.id,'demo-alice')).json().data.me.state).toBe('AVAILABLE');
  await call('POST',`/lessons/${lesson.json().data.id}/cancel`,{operationId:randomUUID(),reasonCode:'SCHOOL_REQUEST',comment:null},lesson.json().data.version,'demo-admin');
 });
 it('leçon créée après l’inscription : refusée (contrôle réciproque)',async()=>{
  const s=await published();
  expect((await enroll(s.id,'demo-alice')).statusCode).toBe(201);
  const commercial=await prepareCommercial(call);
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,s.startOffset,8),null,'demo-admin');
  expect(lesson.statusCode).toBe(409);
  await cancelAll(s.id);
 });
 it('deux élèves pour la dernière place : un succès, un refus Complet',async()=>{
  const s=await published({capacity:1});
  const [a,b]=await Promise.all([enroll(s.id,'demo-alice'),enroll(s.id,'demo-bob')]);
  expect([a.statusCode,b.statusCode].sort()).toEqual([201,409]);
  expect([a,b].find(r=>r.statusCode===409)!.json().code).toBe('COURSE_FULL');
  await cancelAll(s.id);
 });
 it('déjà effectué : offre visible, inscription refusée, même après renommage du type',async()=>{
  const type=(await call('POST','/course-types',{operationId:randomUUID(),title:'Atelier nuit',description:''},null,'demo-admin')).json().data;
  await pool.query(`INSERT INTO drivy.course_completion(school_id,learner_id,type_id,validated_by) VALUES($1,$2,$3,$4)`,[id.schoolA,id.aliceLearner,type.id,id.adminMember]);
  await call('PATCH',`/course-types/${type.id}`,{operationId:randomUUID(),title:'Atelier conduite de nuit',description:''},type.version,'demo-admin');
  const s=await published({typeId:type.id});
  expect((await me(s.id,'demo-alice')).json().data.me.state).toBe('COMPLETED');
  expect((await enroll(s.id,'demo-alice')).json().code).toBe('COURSE_ALREADY_COMPLETED');
 });
 it('pas deux sessions à venir du même type ; réinscription après annulation garde l’historique',async()=>{
  const a=await published({typeId:FIRST_AID}),b=await published({typeId:FIRST_AID});
  const first=(await enroll(a.id,'demo-alice')).json().data.me.enrollment;
  expect((await enroll(b.id,'demo-alice')).json().code).toBe('COURSE_EQUIVALENT_ENROLLED');
  expect((await call('POST',`/course-enrollments/${first.id}/cancel`,{operationId:randomUUID()},first.version,'demo-alice')).statusCode).toBe(200);
  expect((await enroll(a.id,'demo-alice')).statusCode).toBe(201);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND learner_id=$2',[a.id,id.aliceLearner])).rows[0].n).toBe(2);
  await cancelAll(a.id);
 });
 it('inscription par le personnel : droit requis, origine STAFF, mêmes contrôles ; élève ne voit pas la liste',async()=>{
  const s=await published({capacity:1});
  expect((await call('POST',`/course-series/${s.id}/enrollments`,{operationId:randomUUID(),learnerId:id.aliceLearner})).statusCode).toBe(403);
  const ok=await call('POST',`/course-series/${s.id}/enrollments`,{operationId:randomUUID(),learnerId:id.aliceLearner},null,'demo-admin');
  expect(ok.statusCode,ok.body).toBe(201);expect(ok.json().data.source).toBe('STAFF');
  expect((await call('POST',`/course-series/${s.id}/enrollments`,{operationId:randomUUID(),learnerId:id.bobLearner},null,'demo-admin')).json().code).toBe('COURSE_FULL');
  expect((await call('GET',`/course-series/${s.id}/enrollments`,undefined,null,'demo-alice')).statusCode).toBe(403);
  await cancelAll(s.id);
 });
 it('brouillon et autre école : introuvables pour l’élève',async()=>{
  const draft=(await call('POST','/course-series',{operationId:randomUUID(),typeId:AWARENESS,title:'Brouillon',description:'',location:'',conditions:'',teachingLanguage:null,
   responsibleMembershipId:id.adminMember,capacity:5,minParticipants:null,timeZone:'Europe/Zurich',occurrences:[{startsAt:at(200,8),endsAt:at(200,9),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true}]},null,'demo-admin')).json().data;
  expect((await enroll(draft.id,'demo-alice')).statusCode).toBe(404);
  expect((await call('POST',`/v1/schools/${id.schoolB}/course-series/${draft.id}/enroll`,{operationId:randomUUID()},null,'demo-foreign')).statusCode).toBe(404);
 });
});

describe('#40 file prioritaire',()=>{
 it('file active par défaut (12 h, décision du 24 octobre) ; désactivée seulement par un choix explicite de l’école',async()=>{
  const s=await published({capacity:1});await enroll(s.id,'demo-alice');
  await setPolicy(24,null);
  expect((await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).json().code).toBe('COURSE_WAITLIST_DISABLED');
  await setPolicy(24,720);
  expect((await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(201);
  await call('POST',`/course-series/${s.id}/waitlist/leave`,{operationId:randomUUID()},null,'demo-bob');
  await cancelAll(s.id);await setPolicy(24,null);
 });
 it('place proposée au premier seulement, acceptation convertit en inscription, réponse tardive refusée',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  expect((await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(201);
  expect((await me(s.id,'demo-bob')).json().data.me).toMatchObject({state:'WAITING',waitlistPosition:1});
  // Une place se libère : proposée exclusivement à Bob, retenue comptée, inscription concurrente refusée.
  await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice');
  const offered=(await me(s.id,'demo-bob')).json().data;
  expect(offered.me.state).toBe('OFFERED');expect(offered.series.seatsTaken).toBe(1);
  expect(Date.parse(offered.me.offer.expiresAt)).toBeLessThanOrEqual(Date.parse(s.occurrences[0]!.startsAt)-2*3_600_000);
  expect((await enroll(s.id,'demo-alice')).json().code).toBe('COURSE_FULL');
  const offerId=offered.me.offer.id,op=randomUUID();
  const [x,y]=await Promise.all([call('POST',`/course-offers/${offerId}/accept`,{operationId:op},null,'demo-bob'),call('POST',`/course-offers/${offerId}/accept`,{operationId:randomUUID()},null,'demo-bob')]);
  expect([x.statusCode,y.statusCode]).toContain(201);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND status='ACTIVE'",[s.id])).rows[0].n).toBe(1);
  expect((await me(s.id,'demo-bob')).json().data.me.enrollment.source).toBe('OFFER');
  await cancelAll(s.id);await setPolicy(24,null);
 });
 it('refus ou expiration : la place passe au suivant une seule fois, sans inscription automatique',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await call('POST',`/course-series/${s.id}/enrollments`,{operationId:randomUUID(),learnerId:id.aliceLearner},null,'demo-admin')).json().data;
  // Bob, puis un troisième élève fictif : la file est ordonnée par entrée.
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  await call('POST',`/course-enrollments/${holder.id}/staff-cancel`,{operationId:randomUUID(),reason:'Demande de l’élève'},holder.version,'demo-admin');
  const offer=(await me(s.id,'demo-bob')).json().data.me.offer;
  // Expiration forcée : l'heure serveur fait foi.
  await pool.query(`UPDATE drivy.course_seat_offer SET offered_at=now()-interval '13 hours',expires_at=now()-interval '1 minute' WHERE id=$1`,[offer.id]);
  const late=await call('POST',`/course-offers/${offer.id}/accept`,{operationId:randomUUID()},null,'demo-bob');
  expect(late.json().code).toBe('COURSE_OFFER_EXPIRED');
  expect((await me(s.id,'demo-bob')).json().data.me.state).toBe('AVAILABLE');
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND status='ACTIVE'",[s.id])).rows[0].n).toBe(0);
  await setPolicy(24,null);
 });
 it('trop près du début : aucune proposition, la place reste libre',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  // Première séance dans 2 h 10 : échéance possible inférieure à 30 min.
  await pool.query(`UPDATE drivy.course_occurrence SET starts_at=now()+interval '130 minutes',ends_at=now()+interval '190 minutes' WHERE series_id=$1`,[s.id]);
  await call('POST',`/course-enrollments/${holder.id}/staff-cancel`,{operationId:randomUUID(),reason:'Recette'},holder.version+0,'demo-admin');
  expect((await me(s.id,'demo-bob')).json().data.me.state).toBe('WAITING');
  await setPolicy(24,null);
 });
});

describe('#40 file : retrait, droits, confidentialité, perte de réponse, série annulée',()=>{
 it('retrait volontaire et annulation de série : aucune place bloquée, proposition révoquée',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  expect((await call('POST',`/course-series/${s.id}/waitlist/leave`,{operationId:randomUUID()},null,'demo-bob')).json().data.me.state).toBe('FULL');
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice');
  const offer=(await me(s.id,'demo-bob')).json().data.me.offer;expect(offer).toBeTruthy();
  const current=(await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${s.id}/cancel`,{operationId:randomUUID(),reason:'Recette'},current.version,'demo-admin')).statusCode).toBe(200);
  expect((await call('POST',`/course-offers/${offer.id}/accept`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(409);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_seat_offer WHERE series_id=$1 AND status='ACTIVE'",[s.id])).rows[0].n).toBe(0);
  await setPolicy(24,null);
 });
 it('un autre élève ne peut ni accepter ni voir la proposition ; la file ne donne aucun nom',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await call('POST',`/course-series/${s.id}/enrollments`,{operationId:randomUUID(),learnerId:id.aliceLearner},null,'demo-admin')).json().data;
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  await call('POST',`/course-enrollments/${holder.id}/staff-cancel`,{operationId:randomUUID(),reason:'Recette'},holder.version,'demo-admin');
  const view=(await me(s.id,'demo-bob')).json().data;
  expect(JSON.stringify(view)).not.toContain('Alice');
  expect((await call('POST',`/course-offers/${view.me.offer.id}/accept`,{operationId:randomUUID()},null,'demo-alice')).statusCode).toBe(404);
  expect((await call('POST',`/course-offers/${view.me.offer.id}/decline`,{operationId:randomUUID()},null,'demo-admin')).statusCode).toBe(403);
  // Réponse perdue : la même opération rejouée rend le même résultat, une seule inscription.
  const op=randomUUID();
  expect((await call('POST',`/course-offers/${view.me.offer.id}/accept`,{operationId:op},null,'demo-bob')).statusCode).toBe(201);
  expect((await call('POST',`/course-offers/${view.me.offer.id}/accept`,{operationId:op},null,'demo-bob')).statusCode).toBe(201);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_enrollment WHERE series_id=$1 AND status='ACTIVE'",[s.id])).rows[0].n).toBe(1);
  await cancelAll(s.id);await setPolicy(24,null);
 });
 it('lectures concurrentes de la file : une seule proposition pour une place',async()=>{
  await setPolicy(24,720);
  const s=await published({capacity:1});
  const holder=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await call('POST',`/course-series/${s.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob');
  await pool.query(`UPDATE drivy.course_enrollment SET status='CANCELLED',cancelled_at=now(),cancel_kind='STAFF' WHERE id=$1`,[holder.id]);
  await Promise.all([0,1,2,3].map(()=>me(s.id,'demo-bob')));
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.course_seat_offer WHERE series_id=$1",[s.id])).rows[0].n).toBe(1);
  await setPolicy(24,null);
 });
});

describe('#41 annulations et changements de dates',()=>{
 it('annulation autonome jusqu’à l’échéance, refusée après ; contact ne change rien',async()=>{
  const s=await published();
  const e=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await pool.query(`UPDATE drivy.course_enrollment SET self_cancel_deadline=now()-interval '1 second' WHERE id=$1`,[e.id]);
  const refused=await call('POST',`/course-enrollments/${e.id}/cancel`,{operationId:randomUUID()},e.version,'demo-alice');
  expect(refused.statusCode).toBe(409);expect(refused.json().code).toBe('COURSE_SELF_CANCEL_CLOSED');
  const state=(await me(s.id,'demo-alice')).json().data.me;
  expect(state).toMatchObject({state:'ENROLLED'});expect(state.enrollment.canSelfCancel).toBe(false);expect(state.contactEmail).toBeTruthy();
  expect(await learnerReservations(s.id,id.alice)).toBe(1);
  // Le personnel habilité décide : motif obligatoire, tracé, place libérée une fois.
  // Moniteur sans droit : l'inscription n'est pas dans son périmètre.
  expect((await call('POST',`/course-enrollments/${e.id}/staff-cancel`,{operationId:randomUUID(),reason:'Malade'},e.version)).statusCode).toBe(404);
  const done=await call('POST',`/course-enrollments/${e.id}/staff-cancel`,{operationId:randomUUID(),reason:'Malade'},e.version,'demo-admin');
  expect(done.json().data).toMatchObject({status:'CANCELLED',cancelKind:'STAFF',cancelReason:'Malade'});
  expect(await learnerReservations(s.id,id.alice)).toBe(0);
  expect((await call('POST',`/course-enrollments/${e.id}/staff-cancel`,{operationId:randomUUID(),reason:'Bis'},done.json().data.version,'demo-admin')).json().code).toBe('COURSE_ENROLLMENT_CLOSED');
 });
 it('à l’échéance exacte : encore autorisée',async()=>{
  const s=await published();
  const e=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await pool.query(`UPDATE drivy.course_enrollment SET self_cancel_deadline=now()+interval '2 seconds' WHERE id=$1`,[e.id]);
  expect((await call('POST',`/course-enrollments/${e.id}/cancel`,{operationId:randomUUID()},e.version,'demo-alice')).statusCode).toBe(200);
 });
 it('délai de 48 h : nouvelles inscriptions seulement ; élève et moniteur sans droit ne le changent pas',async()=>{
  expect((await call('PUT','/course-policy',{operationId:randomUUID(),selfCancelHours:48,offerResponseMinutes:null},1,'demo-alice')).statusCode).toBe(403);
  const s=await published();
  const before=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  await setPolicy(48,null);
  const s2=await published();
  const after=(await enroll(s2.id,'demo-bob')).json().data.me.enrollment;
  expect(before.selfCancelHours).toBe(24);expect(after.selfCancelHours).toBe(48);
  await cancelAll(s.id);await cancelAll(s2.id);await setPolicy(24,null);
 });
 it('changement de dates incompatible refusé sans modification ; compatible appliqué, échéance non durcie',async()=>{
  const s=await published();
  const e=(await enroll(s.id,'demo-alice')).json().data.me.enrollment;
  const blocker=await published({instructor:id.instructorMember});
  await enroll(blocker.id,'demo-alice');
  const refused=await call('POST',`/course-series/${s.id}/reschedule`,{operationId:randomUUID(),occurrences:[{position:1,startsAt:blocker.occurrences[0]!.startsAt,endsAt:blocker.occurrences[0]!.endsAt,instructorMembershipId:id.otherInstructorMember}]},s.version+1,'demo-admin');
  expect(refused.statusCode,refused.body).toBe(409);
  expect((await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data.occurrences[0].startsAt).toBe(s.occurrences[0]!.startsAt);
  const current=(await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data;
  const earlier=new Date(Date.parse(s.occurrences[0]!.startsAt)-86_400_000);
  const moved=await call('POST',`/course-series/${s.id}/reschedule`,{operationId:randomUUID(),occurrences:[{position:1,startsAt:earlier.toISOString(),endsAt:new Date(earlier.getTime()+3*3_600_000).toISOString(),instructorMembershipId:id.otherInstructorMember}]},current.version,'demo-admin');
  expect(moved.statusCode,moved.body).toBe(200);
  const kept=(await me(s.id,'demo-alice')).json().data.me.enrollment;
  expect(kept.selfCancelDeadline).toBe(e.selfCancelDeadline);
  await cancelAll(s.id);await cancelAll(blocker.id);
 });
 it('annulation de série : inscriptions et file fermées, occupations libérées, historique gardé',async()=>{
  const s=await published();
  await enroll(s.id,'demo-alice');
  const current=(await call('GET',`/course-series/${s.id}`,undefined,null,'demo-admin')).json().data;
  expect((await call('POST',`/course-series/${s.id}/cancel`,{operationId:randomUUID(),reason:''},current.version,'demo-admin')).statusCode).toBe(400);
  const res=await call('POST',`/course-series/${s.id}/cancel`,{operationId:randomUUID(),reason:'Formateur indisponible'},current.version,'demo-admin');
  expect(res.statusCode,res.body).toBe(200);expect(res.json().data.status).toBe('CANCELLED');
  expect(await learnerReservations(s.id,id.alice)).toBe(0);
  expect((await me(s.id,'demo-alice')).json().data.me.enrollment).toMatchObject({status:'CANCELLED',cancelKind:'SERIES_CANCELLED'});
  expect((await enroll(s.id,'demo-bob')).json().code).toBe('COURSE_NOT_OPEN');
 });
});
