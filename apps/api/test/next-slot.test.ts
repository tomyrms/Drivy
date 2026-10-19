import {describe,expect,it} from 'vitest';
import {dayCandidates,findNextSlot,fromWallClock,isoWeekday,nextCivilDay,wallClock,wallClockInstants,type Candidate,type Interval,type OpeningRule,type SlotSearch} from '../src/next-slot.js';

// Horaires synthétiques ; aucune personne, aucune position. Europe/Zurich : UTC+2 en octobre avant le 25, UTC+1 ensuite.
const zone='Europe/Zurich';
const at=(value:string)=>new Date(value);
const weekdays:OpeningRule={weekdays:[1,2,3,4,5],localStart:'09:00',localEnd:'18:00',validFrom:'2026-01-01',validUntil:null};
const assigned=[{validFrom:at('2026-01-01T00:00:00Z'),validUntil:null}];
function search(now:string,extra:Partial<SlotSearch>={}):SlotSearch{
 return {rules:[weekdays],closures:[],assignments:assigned,timeZone:zone,durationMinutes:50,stepMinutes:15,now:at(now),notBefore:at(now),...extra};
}
const local=(instant:Date)=>{const wall=wallClock(instant,zone);return `${wall.date} ${String(Math.floor(wall.minutes/60)).padStart(2,'0')}:${String(wall.minutes%60).padStart(2,'0')}`;};
const free=async()=>[] as boolean[];
const none=async(candidates:Candidate[])=>candidates.map(()=>false);
/** Occupations privées simulées : le moniteur porte son tampon après chaque leçon, l'élève non (comme lesson_slot_conflict). */
function occupied(instructor:Interval[],learner:Interval[]=[],bufferMinutes=10){
 const calls:Candidate[][]=[];
 const predicate=async(candidates:Candidate[])=>{
  calls.push(candidates);
  return candidates.map(c=>{
   const padded=new Date(c.end.getTime()+bufferMinutes*60_000);
   return instructor.some(b=>c.start<b.endsAt&&b.startsAt<padded)||learner.some(b=>c.start<b.endsAt&&b.startsAt<c.end);
  });
 };
 return {predicate,calls};
}

describe('calendrier civil',()=>{
 it('jour ISO, jour suivant et heure murale autour des fins de mois',()=>{
  expect(isoWeekday('2026-10-12')).toBe(1);
  expect(isoWeekday('2026-10-18')).toBe(7);
  expect(nextCivilDay('2026-10-31')).toBe('2026-11-01');
  expect(nextCivilDay('2026-12-31')).toBe('2027-01-01');
  expect(local(fromWallClock('2026-10-13',9*60,zone)!)).toBe('2026-10-13 09:00');
  expect(fromWallClock('2026-10-13',9*60,zone)!.toISOString()).toBe('2026-10-13T07:00:00.000Z');
 });
 it('l’heure sautée au passage à l’heure d’été n’existe pas',()=>{
  expect(fromWallClock('2026-03-29',2*60+30,zone)).toBeNull();
  expect(fromWallClock('2026-03-29',3*60,zone)!.toISOString()).toBe('2026-03-29T01:00:00.000Z');
 });
 it('l’heure répétée au retour à l’heure d’hiver a deux occurrences, la sautée aucune',()=>{
  expect(wallClockInstants('2026-10-25',2*60+30,zone).map(value=>value.toISOString())).toEqual(['2026-10-25T00:30:00.000Z','2026-10-25T01:30:00.000Z']);
  expect(wallClockInstants('2026-03-29',2*60+30,zone)).toEqual([]);
  expect(wallClockInstants('2026-10-13',9*60,zone).map(value=>value.toISOString())).toEqual(['2026-10-13T07:00:00.000Z']);
  expect(wallClockInstants('2026-10-25',3*60,zone).map(value=>value.toISOString())).toEqual(['2026-10-25T02:00:00.000Z']);
 });
 it('un créneau tombant dans l’heure répétée est proposé aux deux occurrences',()=>{
  const night:OpeningRule={weekdays:[7],localStart:'02:00',localEnd:'04:00',validFrom:'2026-01-01',validUntil:null};
  const starts=dayCandidates('2026-10-25',search('2026-10-24T00:00:00Z',{rules:[night],durationMinutes:30,stepMinutes:30})).map(value=>value.start.toISOString());
  expect(starts).toContain('2026-10-25T00:30:00.000Z');
  expect(starts).toContain('2026-10-25T01:30:00.000Z');
 });
});

describe('prochain créneau disponible',()=>{
 it('19 h 30, journée finie : demain 9 h 00',async()=>{
  const result=await findNextSlot(search('2026-10-13T17:30:00Z'),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-14 09:00');
  expect(result.slot!.end.getTime()-result.slot!.start.getTime()).toBe(50*60_000);
 });

 it('vendredi soir : les jours non travaillés sont sautés jusqu’au lundi',async()=>{
  const result=await findNextSlot(search('2026-10-16T17:00:00Z'),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-19 09:00');
 });

 it('jamais un début passé : la grille reprend au pas suivant, alignée sur l’ouverture',async()=>{
  const result=await findNextSlot(search('2026-10-13T07:07:00Z'),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-13 09:15');
  const exact=await findNextSlot(search('2026-10-13T07:15:00Z'),14,none);
  expect(local(exact.slot!.start)).toBe('2026-10-13 09:15');
 });

 it('la leçon tient entière dans l’ouverture : trop longue en fin de journée, elle passe au lendemain',async()=>{
  const result=await findNextSlot(search('2026-10-13T14:35:00Z',{durationMinutes:100}),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-14 09:00');
  const fits=await findNextSlot(search('2026-10-13T14:15:00Z',{durationMinutes:100}),14,none);
  expect(local(fits.slot!.start)).toBe('2026-10-13 16:15');
  expect(local(fits.slot!.end)).toBe('2026-10-13 17:55');
 });

 it('une pause entre deux plages : la leçon ne chevauche jamais la coupure',async()=>{
  const rules:OpeningRule[]=[{...weekdays,localStart:'08:00',localEnd:'12:00'},{...weekdays,localStart:'13:00',localEnd:'17:00'}];
  const result=await findNextSlot(search('2026-10-13T09:20:00Z',{rules}),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-13 13:00');
  const before=dayCandidates('2026-10-13',search('2026-10-13T05:00:00Z',{rules})).map(c=>local(c.start).slice(11));
  expect(before).toContain('11:00');
  expect(before).not.toContain('11:15');
  expect(before).not.toContain('12:15');
 });

 it('une indisponibilité (fermeture) écarte tout créneau qui la croise, bornes semi-ouvertes',async()=>{
  const closures=[{startsAt:at('2026-10-14T07:00:00Z'),endsAt:at('2026-10-14T08:30:00Z')}];
  const result=await findNextSlot(search('2026-10-13T17:30:00Z',{closures}),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-14 10:30');
 });

 it('une journée entière de fermeture ou une règle hors validité reporte au jour suivant',async()=>{
  const closures=[{startsAt:at('2026-10-13T22:00:00Z'),endsAt:at('2026-10-14T22:00:00Z')}];
  expect(local((await findNextSlot(search('2026-10-13T17:30:00Z',{closures}),14,none)).slot!.start)).toBe('2026-10-15 09:00');
  const rules=[{...weekdays,validFrom:'2026-10-20'}];
  expect(local((await findNextSlot(search('2026-10-13T17:30:00Z',{rules}),14,none)).slot!.start)).toBe('2026-10-20 09:00');
  const ended=[{...weekdays,validUntil:'2026-10-13'}];
  expect((await findNextSlot(search('2026-10-13T17:30:00Z',{rules:ended}),14,none)).slot).toBeNull();
 });

 it('les leçons déjà planifiées du moniteur, tampon compris, et celles de l’élève sont évitées',async()=>{
  const instructor=[{startsAt:at('2026-10-14T07:00:00Z'),endsAt:at('2026-10-14T08:00:00Z')}]; // 9:00–9:50 + tampon 10 min
  const learner=[{startsAt:at('2026-10-14T08:00:00Z'),endsAt:at('2026-10-14T08:45:00Z')}]; // autre formation, 10:00–10:45
  const {predicate}=occupied(instructor,learner,10);
  const result=await findNextSlot(search('2026-10-13T17:30:00Z'),14,predicate);
  expect(local(result.slot!.start)).toBe('2026-10-14 10:45');
 });

 it('le tampon du nouveau créneau ne doit pas mordre sur la leçon suivante du moniteur',async()=>{
  const instructor=[{startsAt:at('2026-10-14T07:55:00Z'),endsAt:at('2026-10-14T09:00:00Z')}]; // 9:55–11:00
  const {predicate}=occupied(instructor,[],10);
  const result=await findNextSlot(search('2026-10-13T17:30:00Z'),14,predicate);
  expect(local(result.slot!.start)).toBe('2026-10-14 11:00');
  const {predicate:noBuffer}=occupied(instructor,[],0);
  expect(local((await findNextSlot(search('2026-10-13T17:30:00Z'),14,noBuffer)).slot!.start)).toBe('2026-10-14 09:00');
 });

 it('l’affectation du moniteur doit couvrir toute la leçon',async()=>{
  const assignments=[{validFrom:at('2026-01-01T00:00:00Z'),validUntil:at('2026-10-14T08:00:00Z')}]; // jusqu’au 14 à 10:00
  const result=await findNextSlot(search('2026-10-13T17:30:00Z',{assignments}),14,none);
  expect(local(result.slot!.start)).toBe('2026-10-14 09:00');
  const late=await findNextSlot(search('2026-10-14T07:05:00Z',{assignments}),14,none);
  expect(late.slot).toBeNull();
  const future=[{validFrom:at('2026-10-20T00:00:00Z'),validUntil:null}];
  expect((await findNextSlot(search('2026-10-13T17:30:00Z',{assignments:future}),14,none)).slot).toBeNull();
 });

 it('rien dans la période : aucun créneau, la dernière date cherchée permet de reprendre plus loin',async()=>{
  const {predicate,calls}=occupied([{startsAt:at('2026-10-01T00:00:00Z'),endsAt:at('2026-11-30T00:00:00Z')}]);
  const result=await findNextSlot(search('2026-10-13T17:30:00Z'),7,predicate);
  expect(result).toEqual({slot:null,searchedThrough:'2026-10-19'});
  // Le 13 n'a plus de créneau, le week-end n'en a aucun : seuls les jours ouvrés restants sont interrogés.
  expect(calls.map(day=>local(day[0]!.start).slice(0,10))).toEqual(['2026-10-14','2026-10-15','2026-10-16','2026-10-19']);
  const resumed=await findNextSlot(search('2026-10-13T17:30:00Z',{notBefore:fromWallClock(nextCivilDay(result.searchedThrough),0,zone)!}),7,none);
  expect(local(resumed.slot!.start)).toBe('2026-10-20 09:00');
 });

 it('passage à l’heure d’été : aucune heure inexistante, la fin reste la durée réelle relue en heure murale',()=>{
  const rules=[{weekdays:[7],localStart:'00:00',localEnd:'05:00',validFrom:'2026-01-01',validUntil:null}];
  const starts=dayCandidates('2026-03-29',search('2026-03-28T00:00:00Z',{rules,durationMinutes:30,stepMinutes:30}));
  expect(starts.map(c=>wallClock(c.start,zone).minutes/60)).toEqual([0,0.5,1,1.5,3,3.5,4,4.5]);
  expect(starts.every(c=>c.end.getTime()-c.start.getTime()===30*60_000)).toBe(true);
  expect(local(starts[3]!.end)).toBe('2026-03-29 03:00');
 });

 it('retour à l’heure d’hiver : une heure répétée n’ajoute pas de doublon et la fin ne dépasse pas l’ouverture',()=>{
  const rules=[{weekdays:[7],localStart:'01:00',localEnd:'04:00',validFrom:'2026-01-01',validUntil:null}];
  const starts=dayCandidates('2026-10-25',search('2026-10-24T00:00:00Z',{rules,durationMinutes:60,stepMinutes:60}));
  const walls=starts.map(c=>local(c.start).slice(11)),ends=starts.map(c=>local(c.end).slice(11));
  expect(new Set(starts.map(c=>c.start.getTime())).size).toBe(starts.length);
  expect(walls).toContain('01:00');
  expect(walls).toContain('03:00');
  expect(ends.every(end=>end<='04:00')).toBe(true);
 });

 it('aucun candidat : le prédicat d’occupation n’est jamais appelé',async()=>{
  let called=false;
  const result=await findNextSlot(search('2026-10-13T17:30:00Z',{rules:[]}),3,async c=>{called=true;return free().then(()=>c.map(()=>false));});
  expect(result.slot).toBeNull();
  expect(called).toBe(false);
 });

 it('refuse une durée hors bornes et une réponse d’occupation incomplète',async()=>{
  await expect(findNextSlot(search('2026-10-13T17:30:00Z',{durationMinutes:0}),3,none)).rejects.toThrow(RangeError);
  await expect(findNextSlot(search('2026-10-13T17:30:00Z'),3,free)).rejects.toThrow();
 });
});
