import {performance} from 'node:perf_hooks';
import {describe,expect,it} from 'vitest';
import {positionWeight,rankThemes,rankingParameters,reconcileOrder,scoreThemes,type ThemeUsage} from '../src/observation-ranking-engine.js';
import {bestShare,dayName,firstDayAtRank,flips,movesPerDay,position,seeded,shuffled,simulate,themeKeys,visibleShare,zipf} from './support/ranking-simulator.js';

/** Moteur du classement intelligent : règles, puis simulations de moniteurs (graines fixes, sans base). */
const seeds=[11,23,37,41,59,67,73,89];
const mean=(values:number[])=>values.reduce((total,value)=>total+value,0)/values.length;
/** `uses` usages d'un thème dans une leçon par jour, sur des jours consécutifs. */
const daily=(key:string,from:number,to:number,uses=2,rank:number|null=null):ThemeUsage[]=>Array.from({length:to-from},(_,index)=>({themeKey:key,lessonId:`${key}-${from+index}`,day:dayName(from+index),uses,position:rank}));

describe('score d’un thème',()=>{
 const keys=themeKeys(18);
 it('sans historique, l’ordre manuel fait foi, pour n’importe quel nombre de thèmes',()=>{
  for(const count of [1,5,9,12,18,30,64]){const manual=themeKeys(count);expect(rankThemes({manual,usage:[]}).order).toEqual(manual);}
  expect(rankThemes({manual:[],usage:[]}).order).toEqual([]);
 });
 it('un usage isolé ne compte pas : il faut deux leçons distinctes',()=>{
  const once:ThemeUsage[]=[{themeKey:'t18',lessonId:'a',day:dayName(1),uses:1,position:18}];
  expect(scoreThemes(keys,once).get('t18')!.evidence).toBe(0);
  expect(rankThemes({manual:keys,previous:keys,usage:once}).order).toEqual(keys);
  // Quarante répétitions dans la même leçon restent une seule leçon.
  expect(rankThemes({manual:keys,previous:keys,usage:[{...once[0]!,uses:40}]}).order).toEqual(keys);
  expect(scoreThemes(keys,[...once,{...once[0]!,lessonId:'b'}]).get('t18')!.evidence).toBeGreaterThan(0);
 });
 it('la preuve d’une leçon sature : quarante répétitions pèsent trois fois un usage, pas quarante',()=>{
  const evidence=(uses:number)=>scoreThemes(keys,[{themeKey:'t01',lessonId:'a',day:dayName(1),uses,position:1},{themeKey:'t01',lessonId:'b',day:dayName(1),uses,position:1}]).get('t01')!.evidence;
  expect(evidence(40)/evidence(1)).toBeCloseTo(3,5);expect(evidence(3)/evidence(1)).toBeCloseTo(2,5);
 });
 it('la récence l’emporte : un mois d’usage récent dépasse six mois d’usage ancien',()=>{
  // t02 : très utilisé pendant 120 jours d'activité, puis plus du tout ; t03 : régulier pendant les 30 derniers.
  const usage=[...daily('t02',0,120,4),...daily('t03',120,150,2)],scores=scoreThemes(keys,usage);
  expect(scores.get('t03')!.score).toBeGreaterThan(scores.get('t02')!.score);
  expect(rankThemes({manual:keys,usage}).order[0]).toBe('t03');
 });
 it('la demi-vie se compte en jours d’activité : une absence ne change aucun score',()=>{
  const worked=[...daily('t05',0,20),...daily('t09',5,20,1)];
  // Les mêmes usages, mais avec des dates espacées d'un mois de vacances au milieu.
  const paused=worked.map(row=>({...row,day:dayName(Number(row.day.slice(1))+(Number(row.day.slice(1))>=10?30:0))}));
  for(const key of ['t05','t09'])expect(scoreThemes(keys,paused).get(key)!.score).toBeCloseTo(scoreThemes(keys,worked).get(key)!.score,10);
 });
 it('un usage fait en défilant pèse davantage, sans jamais dépasser le double',()=>{
  expect([1,9,10,12,13,18,19,40,null].map(rank=>positionWeight(rank))).toEqual([1,1,1.25,1.25,1.5,1.75,2,2,1]);
  const at=(rank:number)=>scoreThemes(keys,daily('t10',0,5,1,rank)).get('t10')!.evidence;
  expect(at(16)/at(4)).toBeCloseTo(1.75,5);
 });
 it('à usage égal, l’ordre manuel départage',()=>{
  const usage=[...daily('t12',0,10),...daily('t04',0,10)];
  expect(rankThemes({manual:keys,usage}).order.slice(0,2)).toEqual(['t04','t12']);
 });
});

describe('stabilité',()=>{
 const keys=themeKeys(18);
 it('deux scores proches gardent leur ordre, dans un sens comme dans l’autre',()=>{
  const usage=[...daily('t01',0,30,2),...daily('t02',0,30,2),...daily('t02',30,31,3)];
  expect(scoreThemes(keys,usage).get('t02')!.score).toBeGreaterThan(scoreThemes(keys,usage).get('t01')!.score);
  expect(rankThemes({manual:keys,previous:keys,usage}).order.slice(0,2)).toEqual(['t01','t02']);
  const swapped=['t02','t01',...keys.slice(2)];
  expect(rankThemes({manual:keys,previous:swapped,usage}).order.slice(0,2)).toEqual(['t02','t01']);
 });
 it('un écart net fait dépasser, et la montée est limitée par jour écoulé',()=>{
  const usage=daily('t18',0,30,3);
  expect(rankThemes({manual:keys,previous:keys,usage,elapsedDays:1}).order.indexOf('t18')).toBe(17-rankingParameters.climbPerDay);
  expect(rankThemes({manual:keys,previous:keys,usage,elapsedDays:2}).order.indexOf('t18')).toBe(17-2*rankingParameters.climbPerDay);
  expect(rankThemes({manual:keys,previous:keys,usage,elapsedDays:30}).order[0]).toBe('t18');
  // Les autres thèmes ne changent pas d'ordre entre eux.
  expect(rankThemes({manual:keys,previous:keys,usage,elapsedDays:30}).order.slice(1)).toEqual(keys.slice(0,17));
 });
 it('un thème ne monte pas derrière un voisin qu’il ne domine pas, mais passe celui qu’il domine nettement plus haut',()=>{
  // t03 est presque à égalité avec t02 et nettement devant t01, qui est en tête.
  const usage=[...daily('t01',0,30,1),...daily('t02',0,30,4),...daily('t03',0,30,4),...daily('t03',29,30,1)];
  expect(rankThemes({manual:keys,previous:keys,usage}).order.slice(0,3)).toEqual(['t02','t03','t01']);
 });
 it('le même état donne le même classement : recalculer ne change rien',()=>{
  const usage=[...daily('t07',0,25,3),...daily('t15',10,25,2),...daily('t02',0,25,1)];
  let order=rankThemes({manual:keys,usage}).order;
  for(let round=0;round<5;round++){const next=rankThemes({manual:keys,previous:order,usage,elapsedDays:1}).order;expect(next).toEqual(order);order=next;}
 });
});

describe('thèmes affichés, masqués, ajoutés',()=>{
 const keys=themeKeys(12);
 it('ramène un ordre enregistré aux thèmes affichés',()=>{
  expect(reconcileOrder(['t03','gone','t01','t03'],['t01','t02','t03','t04'])).toEqual(['t03','t01','t02','t04']);
  expect(reconcileOrder([],['t01','t02'])).toEqual(['t01','t02']);
 });
 it('un thème masqué quitte le classement sans déranger les autres ; ses usages restent pour son retour',()=>{
  const usage=[...daily('t09',0,30,3),...daily('t11',0,30,2)],first=rankThemes({manual:keys,usage}).order;
  expect(first.slice(0,2)).toEqual(['t09','t11']);
  const without=keys.filter(key=>key!=='t09'),hidden=rankThemes({manual:without,previous:first,usage}).order;
  expect(hidden).toEqual(first.filter(key=>key!=='t09'));
  // Réaffiché : il reprend la place que son historique lui donne, sans attendre la limite de montée.
  expect(rankThemes({manual:keys,previous:hidden,usage}).order[0]).toBe('t09');
 });
 it('un thème nouvellement affiché et jamais utilisé se range d’après l’ordre manuel, sous les thèmes utilisés',()=>{
  const usage=daily('t10',0,30,3),before=rankThemes({manual:keys.slice(1),usage}).order;
  const after=rankThemes({manual:keys,previous:before,usage}).order;
  expect(after.slice(0,2)).toEqual(['t10','t01']);expect(after.slice(2)).toEqual(before.slice(1));
 });
 it('ignore les usages d’une clé inconnue et les doublons de l’ordre manuel',()=>{
  expect(rankThemes({manual:['t01','t02','t01'],usage:daily('retired',0,30,5)}).order).toEqual(['t01','t02']);
 });
});

describe('simulations',()=>{
 it('9, 18 et 30 thèmes : la fenêtre finit par porter presque tous les signalements voulus, et bouge peu',()=>{
  for(const [themes,share,moves] of [[9,0.999,0.5],[18,0.95,1.5],[30,0.95,4]] as const){
   const runs=seeds.map(seed=>{
    const weights=zipf(shuffled(themes,seeded(seed*7))),run=simulate({themes,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights},'engine');
    return {share:visibleShare(run,84)/bestShare(weights),moves:movesPerDay(run,84)};
   });
   expect(mean(runs.map(run=>run.share)),`${themes} thèmes`).toBeGreaterThan(share);
   expect(mean(runs.map(run=>run.moves)),`${themes} thèmes`).toBeLessThan(moves);
  }
 });
 it('bouge moins qu’un tri par fréquence ou par moyenne mobile, pour une fenêtre aussi utile',()=>{
  const measure=(strategy:'count'|'ewma'|'engine')=>mean(seeds.map(seed=>{
   const weights=zipf(shuffled(18,seeded(seed*7)));
   return movesPerDay(simulate({themes:18,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights},strategy),84);
  }));
  expect(measure('engine')).toBeLessThan(measure('count'));expect(measure('engine')).toBeLessThan(measure('ewma')/2);
 });
 it('un thème en 25e place sur 30 devient le plus utilisé : il monte par étapes jusqu’aux trois premières places',()=>{
  for(const seed of seeds){
   const keys=themeKeys(30),base=zipf(Array.from({length:30},(_,index)=>index));
   const preference=(day:number)=>{const weights=[...base],progress=Math.min(1,Math.max(0,(day-56)/42));weights[24]=base[24]!+(1.2-base[24]!)*progress;weights[1]=base[1]!*(1-progress)+0.01*progress;return weights;};
   const run=simulate({themes:30,days:196,lessonsPerDay:6,signalsPerLesson:4,seed,preference},'engine');
   expect(position(run,55,keys[24]!)).toBeGreaterThan(9);
   const nine=firstDayAtRank(run,keys[24]!,9,56),three=firstDayAtRank(run,keys[24]!,3,56);
   expect(nine).toBeGreaterThan(56);expect(three).toBeGreaterThan(nine);expect(three).toBeLessThan(140);
   // Aucun saut d'un jour au lendemain ne dépasse la limite ; après un week-end, trois jours se sont écoulés.
   for(let day=57;day<196;day++)expect(position(run,day-1,keys[24]!)-position(run,day,keys[24]!)).toBeLessThanOrEqual(rankingParameters.climbPerDay*3);
   // L'ancien deuxième, délaissé, finit hors de la fenêtre.
   expect(position(run,195,keys[1]!)).toBeGreaterThan(9);
  }
 });
 it('deux thèmes à égalité n’échangent presque jamais leur place',()=>{
  const counts=seeds.map(seed=>{
   const weights=zipf(Array.from({length:18},(_,index)=>index));weights[3]=weights[2]!;
   const run=simulate({themes:18,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights},'engine');
   return flips(run,run.keys[2]!,run.keys[3]!,14);
  });
  expect(Math.max(...counts)).toBeLessThanOrEqual(3);expect(mean(counts)).toBeLessThan(1.5);
 });
 it('quatre semaines sans leçon ne déplacent rien, ni pendant l’absence ni à la reprise',()=>{
  for(const seed of seeds){
   const weights=zipf(shuffled(18,seeded(seed))),active=(day:number)=>day%7<5&&(day<70||day>=98);
   const run=simulate({themes:18,days:126,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights,active},'engine');
   expect(run.orders[97]).toEqual(run.orders[69]);
   expect(run.orders[98]!.filter((key,index)=>run.orders[97]![index]!==key).length).toBeLessThanOrEqual(4);
  }
 });
 it('un changement brutal d’habitudes est suivi en quelques semaines',()=>{
  const shares=seeds.map(seed=>{
   const before=zipf(shuffled(18,seeded(seed))),after=zipf(shuffled(18,seeded(seed+1000)));
   const run=simulate({themes:18,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:day=>day<70?before:after},'engine');
   return [visibleShare(run,70,77),visibleShare(run,91,98),visibleShare(run,119,126)].map(value=>value/bestShare(after));
  });
  const week=(index:number)=>mean(shares.map(share=>share[index]!));
  expect(week(1)).toBeGreaterThan(week(0));expect(week(1)).toBeGreaterThan(0.85);expect(week(2)).toBeGreaterThan(0.9);
 });
 it('une leçon avec quarante répétitions du dernier thème ne bouleverse rien',()=>{
  for(const seed of seeds){
   const weights=zipf(Array.from({length:18},(_,index)=>index));
   const run=simulate({themes:18,days:98,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights,burst:{day:70,theme:17,uses:40}},'engine');
   const key=run.keys[17]!;
   expect(position(run,70,key)-position(run,71,key)).toBeLessThanOrEqual(3);expect(position(run,77,key)).toBeGreaterThan(9);
  }
 });
 it('moniteur très actif ou occasionnel : la même quantité de leçons produit la même adaptation',()=>{
  const worked=(lessons:number,active:(day:number)=>boolean)=>mean(seeds.map(seed=>{
   const base=zipf(Array.from({length:18},(_,index)=>index));
   const preference=(day:number)=>{const weights=[...base];if(day>=84)weights[15]=1.2;return weights;};
   const run=simulate({themes:18,days:280,lessonsPerDay:lessons,signalsPerLesson:4,seed,preference,active},'engine');
   const day=firstDayAtRank(run,run.keys[15]!,9,84);expect(day).toBeGreaterThan(84);
   return Array.from({length:day-84},(_,index)=>84+index).filter(active).length;
  }));
  const busy=worked(8,day=>day%7<5),occasional=worked(2,day=>day%7===1||day%7===3);
  expect(busy).toBeLessThan(8);expect(occasional).toBeLessThan(12);
 });
 it('historique accumulé en mode manuel : l’activation classe tout de suite d’après les habitudes',()=>{
  for(const seed of seeds){
   const weights=zipf(shuffled(30,seeded(seed*3)));
   const run=simulate({themes:30,days:120,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights,manualUntil:112},'engine');
   expect(run.orders[111]).toEqual(run.keys);
   expect(visibleShare(run,112,119)/bestShare(weights)).toBeGreaterThan(visibleShare(run,98,105)/bestShare(weights));
   expect(visibleShare(run,112,119)/bestShare(weights)).toBeGreaterThan(0.8);
  }
 });
 it('plusieurs milliers de signalements, trente thèmes : un classement coûte quelques millisecondes',()=>{
  const keys=themeKeys(30),next=seeded(5),usage:ThemeUsage[]=[];let signals=0;
  for(let day=0;day<300;day++)for(let lesson=0;lesson<7;lesson++)for(const key of keys)if(next()<0.2){const uses=1+Math.floor(next()*4);signals+=uses;usage.push({themeKey:key,lessonId:`l${day}-${lesson}`,day:dayName(day),uses,position:1+Math.floor(next()*30)});}
  expect(signals).toBeGreaterThan(20_000);
  const previous=rankThemes({manual:keys,usage}).order,start=performance.now();
  for(let round=0;round<20;round++)expect(rankThemes({manual:keys,previous,usage,elapsedDays:1}).order).toHaveLength(30);
  expect((performance.now()-start)/20).toBeLessThan(50);
 });
});
