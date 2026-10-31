import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareSchool,id,type Call} from './support/harness.js';

/**
 * Cours collectifs : fuseau Europe/Zurich et changement d'heure (#83 : #38, #39, #40, #41). Données synthétiques.
 *
 * Le serveur compte les échéances en heures ÉCOULÉES (début moins 24 h = 86 400 s), jamais « à la même heure la veille » :
 * même convention que la réservation individuelle (apps/web/test/individual-cancellation.test.ts). Ces tests figent ce choix
 * et vérifient que les instants des séances, leurs occupations d'agenda et leurs durées suivent l'heure locale de l'école.
 *
 * L'horloge n'est pas simulée : le prochain changement d'heure réel (dernier dimanche de mars ou d'octobre, 01:00 UTC) est
 * calculé au lancement, au moins six jours à venir. Le test s'adapte au sens de la bascule (heure d'été ou d'hiver) ;
 * chaque assertion dit ce qui est attendu dans les deux sens. La borne « début moins 2 h » de la fenêtre de proposition
 * ne peut être exercée à la bascule qu'avec une horloge injectable : elle est couverte ailleurs par déplacement de dates.
 */
const ZONE='Europe/Zurich',HOUR=3_600_000,DAY=24*HOUR;
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});

const parts=(ms:number)=>Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:ZONE,hourCycle:'h23',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'})
 .formatToParts(new Date(ms)).filter(p=>p.type!=='literal').map(p=>[p.type,Number(p.value)])) as Record<'year'|'month'|'day'|'hour'|'minute'|'second',number>;
const offsetMinutes=(ms:number)=>{const p=parts(ms);return Math.round((Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second)-Math.floor(ms/1000)*1000)/60_000);};
/** Heure murale de l'école (jour AAAA-MM-JJ, heure HH:mm) vers l'instant, pour une heure qui existe et n'est pas doublée. */
function localInstant(day:string,time:string){
 const [y,m,d]=day.split('-').map(Number) as [number,number,number],[hh,mm]=time.split(':').map(Number) as [number,number];
 const wall=Date.UTC(y,m-1,d,hh,mm);let instant=wall-offsetMinutes(wall)*60_000;instant=wall-offsetMinutes(instant)*60_000;
 return new Date(instant);
}
/** Lecture inverse : AAAA-MM-JJTHH:mm dans le fuseau de l'école. */
function local(value:Date|string|number){
 const p=parts(new Date(value).getTime()),two=(n:number)=>String(n).padStart(2,'0');
 return `${p.year}-${two(p.month)}-${two(p.day)}T${two(p.hour)}:${two(p.minute)}`;
}
const addDays=(day:string,delta:number)=>new Date(Date.parse(`${day}T12:00:00Z`)+delta*DAY).toISOString().slice(0,10);
/** Dernier dimanche du mois (0 = janvier), 01:00 UTC : règle européenne du changement d'heure. */
function lastSunday(year:number,month:number){
 const date=new Date(Date.UTC(year,month+1,0,1,0,0));date.setUTCDate(date.getUTCDate()-date.getUTCDay());return date;
}
function nextTransition(after:number){
 const year=new Date(after).getUTCFullYear();
 const all=[year,year+1,year+2].flatMap(y=>[{kind:'SPRING' as const,at:lastSunday(y,2)},{kind:'AUTUMN' as const,at:lastSunday(y,9)}]).sort((a,b)=>a.at.getTime()-b.at.getTime());
 return all.find(item=>item.at.getTime()>after)!;
}
const transition=nextTransition(Date.now()+6*DAY);
const sunday=transition.at.toISOString().slice(0,10),saturday=addDays(sunday,-1),monday=addDays(sunday,1),friday=addDays(sunday,-2);
/** Heures écoulées entre le samedi et le dimanche à la même heure murale : 23 h à l'heure d'été, 25 h à l'heure d'hiver. */
const shiftHours=transition.kind==='SPRING'?-1:1;

async function setPolicy(selfCancelHours:number){
 const version=(await call('GET','/course-catalogue',undefined,null,'demo-admin')).json().data.policy.version;
 // Le délai de réponse reste fixé à 720 min : null désactiverait la file prioritaire.
 const res=await call('PUT','/course-policy',{operationId:randomUUID(),selfCancelHours,offerResponseMinutes:720},version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
}
type Session={day:string;from:string;to:string};
const occurrenceBody=(s:Session)=>({startsAt:localInstant(s.day,s.from).toISOString(),endsAt:localInstant(s.day,s.to).toISOString(),instructorMembershipId:id.otherInstructorMember,attendanceRequired:true});
async function draft(sessions:Session[],capacity=10){
 const type=(await call('POST','/course-types',{operationId:randomUUID(),title:`Type ${randomUUID()}`,description:''},null,'demo-admin')).json().data.id;
 return call('POST','/course-series',{operationId:randomUUID(),typeId:type,title:'Cours à cheval sur le changement d’heure',description:'',location:'Salle',conditions:'',teachingLanguage:null,
  responsibleMembershipId:id.adminMember,capacity,minParticipants:null,timeZone:ZONE,occurrences:sessions.map(occurrenceBody)},null,'demo-admin');
}
type Published={id:string;version:number;totalMinutes:number;selfCancelHours:number;selfCancellationDeadline:string;occurrences:{startsAt:string;endsAt:string;position:number}[]};
async function published(sessions:Session[],capacity=10):Promise<Published>{
 const created=await draft(sessions,capacity);if(created.statusCode!==201)throw new Error(created.body);
 const res=await call('POST',`/course-series/${created.json().data.id}/publish`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
 if(res.statusCode!==200)throw new Error(res.body);
 return res.json().data;
}
const enroll=(seriesId:string,subject:string)=>call('POST',`/course-series/${seriesId}/enroll`,{operationId:randomUUID()},null,subject);
async function learnerRanges(seriesId:string,person:string){
 return (await pool.query<{starts:Date;ends:Date}>(`SELECT lower(r.during) AS starts,upper(r.during) AS ends FROM drivy.reservation r JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id
  WHERE o.series_id=$1 AND r.resource_id=$2 AND r.course_enrollment_id IS NOT NULL AND r.active ORDER BY o.position`,[seriesId,person])).rows;
}

describe('repères du test',()=>{
 it('le prochain changement d’heure est bien calculé et les heures murales choisies existent',()=>{
  // Garde-fou : une erreur de calcul fausserait toutes les autres assertions sans le dire.
  const before=transition.at.getTime()-HOUR,after=transition.at.getTime()+HOUR;
  expect(offsetMinutes(after)-offsetMinutes(before)).toBe(transition.kind==='SPRING'?60:-60);
  expect(local(transition.at)).toBe(`${sunday}T${transition.kind==='SPRING'?'03':'02'}:00`);
  for(const time of ['06:00','09:00','13:00','17:00','20:00'])for(const d of [saturday,sunday,monday])expect(local(localInstant(d,time))).toBe(`${d}T${time}`);
 });
});

describe('série à cheval sur le changement d’heure (Europe/Zurich)',()=>{
 it('même heure murale chaque jour, instants décalés d’une heure, occupations d’agenda fidèles, échéance en heures écoulées',async()=>{
  const sessions=[saturday,sunday,monday].map(day=>({day,from:'09:00',to:'12:00'}));
  const series=await published(sessions);
  expect(series.occurrences.map(o=>local(o.startsAt))).toEqual([saturday,sunday,monday].map(d=>`${d}T09:00`));
  expect(series.occurrences.map(o=>local(o.endsAt))).toEqual([saturday,sunday,monday].map(d=>`${d}T12:00`));
  const starts=series.occurrences.map(o=>Date.parse(o.startsAt));
  expect(starts[1]!-starts[0]!).toBe(DAY+shiftHours*HOUR);
  expect(starts[2]!-starts[1]!).toBe(DAY);
  expect(series.totalMinutes).toBe(540);
  const res=await enroll(series.id,'demo-alice');expect(res.statusCode,res.body).toBe(201);
  const enrollment=res.json().data.me.enrollment;
  // Une inscription occupe l'agenda de l'élève sur chaque séance, aux mêmes instants que le cours.
  const ranges=await learnerRanges(series.id,id.alice);
  expect(ranges.map(r=>r.starts.toISOString())).toEqual(series.occurrences.map(o=>o.startsAt));
  expect(ranges.map(r=>r.ends.toISOString())).toEqual(series.occurrences.map(o=>o.endsAt));
  // Échéance = première séance moins 24 h écoulées ; le samedi et le vendredi sont sous le même décalage horaire.
  expect(Date.parse(enrollment.selfCancelDeadline)).toBe(starts[0]!-24*HOUR);
  expect(local(enrollment.selfCancelDeadline)).toBe(`${friday}T09:00`);
  // Deuxième calcul de l'échéance (projection de la série) : même instant que celui figé dans l'inscription.
  expect(series.selfCancellationDeadline).toBe(enrollment.selfCancelDeadline);
 });

 it('première séance le jour du changement d’heure : 24 h et 48 h sont des heures écoulées, pas « même heure la veille »',async()=>{
  const first=await published([{day:sunday,from:'13:00',to:'16:00'}]);
  const learner=await enroll(first.id,'demo-alice');expect(learner.statusCode,learner.body).toBe(201);
  const start=Date.parse(first.occurrences[0]!.startsAt),deadline=Date.parse(learner.json().data.me.enrollment.selfCancelDeadline);
  expect(local(start)).toBe(`${sunday}T13:00`);
  expect(deadline).toBe(start-24*HOUR);
  // Le samedi, l'horloge murale diffère d'une heure du dimanche : l'échéance tombe à 14:00 (retour à l'heure d'hiver) ou 12:00 (heure d'été).
  expect(local(deadline)).toBe(`${saturday}T${transition.kind==='AUTUMN'?'14':'12'}:00`);
  // La lecture « même heure murale la veille » donnerait un autre instant : le contrat retenu n'est pas celui-là.
  expect(deadline).not.toBe(localInstant(saturday,'13:00').getTime());
  expect(Math.abs(deadline-localInstant(saturday,'13:00').getTime())).toBe(HOUR);

  await setPolicy(48);
  try{
   const second=await published([{day:sunday,from:'17:00',to:'20:00'}]);
   expect(second.selfCancelHours).toBe(48);
   const bob=await enroll(second.id,'demo-bob');expect(bob.statusCode,bob.body).toBe(201);
   const start48=Date.parse(second.occurrences[0]!.startsAt),deadline48=Date.parse(bob.json().data.me.enrollment.selfCancelDeadline);
   expect(deadline48).toBe(start48-48*HOUR);
   expect(local(deadline48)).toBe(`${friday}T${transition.kind==='AUTUMN'?'18':'16'}:00`);
   // La série déjà publiée garde sa règle de 24 h : une nouvelle politique ne la réécrit pas.
   expect((await call('GET',`/course-series/${first.id}`,undefined,null,'demo-admin')).json().data.selfCancelHours).toBe(24);
  }finally{await setPolicy(24);}
 });

 it('séance qui enjambe la bascule : durée en temps écoulé, limite de 12 h mesurée de la même façon',async()=>{
  // 01:30 → 03:30 murales : 1 h écoulée à l'heure d'été (02:00 n'existe pas), 3 h au retour à l'heure d'hiver (02:00 deux fois).
  const night=await draft([{day:sunday,from:'01:30',to:'03:30'}]);expect(night.statusCode,night.body).toBe(201);
  expect(night.json().data.totalMinutes).toBe(transition.kind==='SPRING'?60:180);
  // Durée murale de 11 h 30 ou 12 h 30 selon le sens : seule la durée écoulée compte pour la limite de 12 h.
  const cases:{from:string;to:string}[]=transition.kind==='SPRING'
   ?[{from:'00:00',to:'13:00'},{from:'00:00',to:'13:30'}]   // 13 h et 13 h 30 murales = 12 h et 12 h 30 écoulées
   :[{from:'00:00',to:'11:00'},{from:'00:00',to:'12:00'}];  // 11 h et 12 h murales = 12 h et 13 h écoulées
  const outcomes:number[]=[];
  for(const c of cases){
   const elapsed=localInstant(sunday,c.to).getTime()-localInstant(sunday,c.from).getTime();
   const res=await draft([{day:sunday,from:c.from,to:c.to}]);
   outcomes.push(res.statusCode);
   expect(res.statusCode,`${c.from}-${c.to} (${elapsed/HOUR} h écoulées) : ${res.body}`).toBe(elapsed<=12*HOUR?201:422);
   if(elapsed>12*HOUR)expect(res.json().code).toBe('INVALID_INTERVAL');
  }
  expect(outcomes).toEqual([201,422]);
 });

 it('fenêtre de proposition de place : minutes écoulées, indépendantes du changement d’heure de la série',async()=>{
  const series=await published([saturday,sunday,monday].map(day=>({day,from:'06:00',to:'08:00'})),1);
  const holder=(await enroll(series.id,'demo-alice')).json().data.me.enrollment;
  expect((await call('POST',`/course-series/${series.id}/waitlist`,{operationId:randomUUID()},null,'demo-bob')).statusCode).toBe(201);
  expect((await call('POST',`/course-enrollments/${holder.id}/cancel`,{operationId:randomUUID()},holder.version,'demo-alice')).statusCode).toBe(200);
  const offer=(await call('GET',`/course-series/${series.id}/me`,undefined,null,'demo-bob')).json().data.me.offer;
  expect(offer).toBeTruthy();
  const row=(await pool.query<{window:string;expires_at:Date}>("SELECT extract(epoch FROM expires_at-offered_at)::text AS window,expires_at FROM drivy.course_seat_offer WHERE id=$1",[offer.id])).rows[0]!;
  // 720 min de réponse ; quelques millisecondes séparent le début de transaction (offered_at) de l'instant de calcul.
  expect(Number(row.window)).toBeGreaterThanOrEqual(720*60);
  expect(Number(row.window)).toBeLessThan(720*60+30);
  expect(row.expires_at.toISOString()).toBe(offer.expiresAt);
  // La séance est loin : la borne « début moins 2 h » ne s'applique pas, la réponse reste la durée de l'école.
  expect(Date.parse(offer.expiresAt)).toBeLessThan(Date.parse(series.occurrences[0]!.startsAt)-2*HOUR);
 });
});
