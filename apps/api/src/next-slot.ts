/**
 * Recherche du prochain créneau libre (extension hors contrat canonique : `GET …/lessons/next-slot`).
 *
 * Ce module est pur : aucune base, aucune horloge implicite. Il produit, jour civil par jour civil dans le fuseau de
 * l'école, les débuts qui respectent exactement ce que l'écriture contrôlera (`ensureOpen` et l'affectation de
 * `trainingContext`) : une ouverture du moniteur qui contient toute la leçon le même jour local, aucune fermeture
 * croisée, une affectation couvrant le rendez-vous, un début futur. Les occupations (leçons du moniteur, tampon
 * compris, et de l'élève dans toute l'école) restent privées : elles sont testées par un prédicat fourni par
 * l'appelant, qui interroge `drivy.lesson_slot_conflict` sans jamais lire les réservations elles-mêmes.
 */

export interface OpeningRule {weekdays:number[];localStart:string;localEnd:string;validFrom:string;validUntil:string|null}
export interface Interval {startsAt:Date;endsAt:Date}
export interface AssignmentWindow {validFrom:Date;validUntil:Date|null}
export interface SlotSearch {
 rules:OpeningRule[];closures:Interval[];assignments:AssignmentWindow[];
 timeZone:string;durationMinutes:number;stepMinutes:number;
 /** Instant de lecture : l'affectation doit être en cours maintenant, comme à l'écriture. */
 now:Date;
 /** Aucun début avant cet instant (inclus). L'appelant y ajoute sa marge : un début doit rester futur à l'écriture. */
 notBefore:Date;
}
export interface Candidate {start:Date;end:Date}

const formatters=new Map<string,Intl.DateTimeFormat>();
function formatter(timeZone:string){
 let value=formatters.get(timeZone);
 if(!value){
  value=new Intl.DateTimeFormat('en-CA',{timeZone,hourCycle:'h23',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'});
  formatters.set(timeZone,value);
 }
 return value;
}
/** Heure murale d'un instant dans un fuseau : jour civil « AAAA-MM-JJ » et minutes depuis minuit (secondes ignorées). */
export function wallClock(instant:Date,timeZone:string){
 const parts=Object.fromEntries(formatter(timeZone).formatToParts(instant).map(part=>[part.type,part.value]));
 const hour=Number(parts.hour)%24;
 return {date:`${parts.year}-${parts.month}-${parts.day}`,minutes:hour*60+Number(parts.minute),seconds:Number(parts.second)};
}
function offsetMs(instant:number,timeZone:string){
 const wall=wallClock(new Date(instant),timeZone),[y,m,d]=wall.date.split('-').map(Number) as [number,number,number];
 return Date.UTC(y,m-1,d,0,wall.minutes,wall.seconds)-Math.floor(instant/1000)*1000;
}
/** Instant d'une heure murale ; null si elle n'existe pas ce jour-là (heure sautée au passage à l'heure d'été).
 * Une heure répétée (retour à l'heure d'hiver) donne l'une de ses deux occurrences, toujours vérifiée ensuite. */
export function fromWallClock(date:string,minutes:number,timeZone:string):Date|null{
 const [y,m,d]=date.split('-').map(Number) as [number,number,number],guess=Date.UTC(y,m-1,d,0,minutes);
 const first=guess-offsetMs(guess,timeZone),second=guess-offsetMs(first,timeZone);
 for(const value of [first,second]){
  const wall=wallClock(new Date(value),timeZone);
  if(wall.date===date&&wall.minutes===minutes)return new Date(value);
 }
 return null;
}
/** Jour civil suivant « AAAA-MM-JJ », sans fuseau. */
export function nextCivilDay(date:string){
 const [y,m,d]=date.split('-').map(Number) as [number,number,number];
 return new Date(Date.UTC(y,m-1,d+1)).toISOString().slice(0,10);
}
/** Jour ISO de la semaine (1 = lundi … 7 = dimanche) d'un jour civil, comme `extract(isodow …)`. */
export function isoWeekday(date:string){
 const [y,m,d]=date.split('-').map(Number) as [number,number,number],day=new Date(Date.UTC(y,m-1,d)).getUTCDay();
 return day===0?7:day;
}
const clock=(value:string)=>{const [h,m]=value.split(':').map(Number) as [number,number];return h*60+m;};
const overlaps=(a:Interval|Candidate,b:Interval)=>{
 const start='start'in a?a.start:a.startsAt,end='end'in a?a.end:a.endsAt;
 return start.getTime()<b.endsAt.getTime()&&b.startsAt.getTime()<end.getTime();
};

/** Débuts possibles d'un jour civil, triés et sans doublon, avant tout contrôle d'occupation. */
export function dayCandidates(date:string,search:SlotSearch):Candidate[]{
 const duration=search.durationMinutes*60_000,weekday=isoWeekday(date),seen=new Map<number,Candidate>();
 for(const rule of search.rules){
  if(!rule.weekdays.includes(weekday)||rule.validFrom>date||(rule.validUntil!==null&&rule.validUntil<date))continue;
  const opens=clock(rule.localStart),closes=clock(rule.localEnd);
  // Grille alignée sur l'ouverture : 9:00, 9:15, … ; jamais au-delà de la fermeture.
  for(let minute=opens;minute+search.durationMinutes<=closes;minute+=search.stepMinutes){
   const start=fromWallClock(date,minute,search.timeZone);if(!start)continue;
   const end=new Date(start.getTime()+duration),endWall=wallClock(end,search.timeZone);
   // Un changement d'heure dans la leçon déplace sa fin murale : l'écriture relit l'heure murale, la recherche aussi.
   if(endWall.date!==date||endWall.minutes>closes||endWall.seconds!==0)continue;
   if(start.getTime()<search.notBefore.getTime())continue;
   if(search.closures.some(closure=>overlaps({start,end},closure)))continue;
   if(!search.assignments.some(a=>a.validFrom.getTime()<=search.now.getTime()&&a.validFrom.getTime()<=start.getTime()
    &&(a.validUntil===null||(a.validUntil.getTime()>search.now.getTime()&&a.validUntil.getTime()>=end.getTime()))))continue;
   seen.set(start.getTime(),{start,end});
  }
 }
 return [...seen.values()].sort((a,b)=>a.start.getTime()-b.start.getTime());
}

export interface SlotSearchResult {slot:Candidate|null;searchedThrough:string}
/**
 * Premier créneau libre à partir du jour civil de `notBefore`, sur `days` jours civils au plus.
 * `conflicts` reçoit les candidats d'un jour et répond, dans le même ordre, s'ils croisent une occupation.
 * Un jour sans candidat n'appelle pas `conflicts`.
 */
export async function findNextSlot(search:SlotSearch,days:number,conflicts:(candidates:Candidate[])=>Promise<boolean[]>):Promise<SlotSearchResult>{
 if(!Number.isInteger(search.durationMinutes)||search.durationMinutes<1||search.durationMinutes>480)throw new RangeError('durationMinutes');
 if(!Number.isInteger(search.stepMinutes)||search.stepMinutes<1)throw new RangeError('stepMinutes');
 let date=wallClock(search.notBefore,search.timeZone).date,last=date;
 for(let index=0;index<days;index++){
  last=date;
  const candidates=dayCandidates(date,search);
  if(candidates.length){
   const answers=await conflicts(candidates);
   if(answers.length!==candidates.length)throw new Error('Conflict answers do not match candidates');
   const free=candidates.findIndex((_,position)=>answers[position]===false);
   if(free>=0)return {slot:candidates[free]!,searchedThrough:date};
  }
  date=nextCivilDay(date);
 }
 return {slot:null,searchedThrough:last};
}
