import {performance} from 'node:perf_hooks';
import {rankThemes,rankingParameters,type ThemeUsage} from '../src/observation-ranking-engine.js';
import {bestShare,dayName,firstDayAtRank,flips,movesPerDay,position,seeded,shuffled,simulate,strategies,themeKeys,visibleShare,zipf,type Strategy} from '../test/support/ranking-simulator.js';

/**
 * Compare les stratégies de classement des signalements sur des moniteurs simulés. Sortie : tableaux Markdown, repris dans
 * docs/implementation/classement-intelligent-20261013.md. Usage : npx tsx scripts/simulate-observation-ranking.ts
 */
const seeds=[11,23,37,41,59,67,73,89];
const mean=(values:number[])=>values.reduce((total,value)=>total+value,0)/values.length;
const fixed=(value:number,digits=2)=>value.toFixed(digits);
const table=(title:string,head:string[],rows:string[][])=>{
 console.log(`\n### ${title}\n`);console.log(`| ${head.join(' | ')} |`);console.log(`|${head.map(()=>'---').join('|')}|`);
 for(const row of rows)console.log(`| ${row.join(' | ')} |`);
};
const each=<T>(work:(seed:number)=>T)=>seeds.map(work);
/** Jours travaillés entre deux jours de calendrier. */
const worked=(from:number,to:number)=>to<0?'jamais':String(Array.from({length:Math.max(0,to-from)},(_,index)=>from+index).filter(day=>day%7<5).length);

// 1. Régime établi : 9, 18 et 30 thèmes, préférences fixes sans rapport avec l'ordre manuel.
for(const themes of [9,18,30]){
 const rows=strategies.map(strategy=>{
  const runs=each(seed=>{
   const weights=zipf(shuffled(themes,seeded(seed*7)));
   const run=simulate({themes,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights},strategy);
   return {share:visibleShare(run,84)/bestShare(weights),early:visibleShare(run,0,28)/bestShare(weights),moves:movesPerDay(run,84),still:Array.from({length:56},(_,index)=>84+index).filter(day=>day%7<5&&run.moved[day]===0).length/40};
  });
  return [strategy,fixed(mean(runs.map(run=>run.early))*100,1)+' %',fixed(mean(runs.map(run=>run.share))*100,1)+' %',fixed(mean(runs.map(run=>run.moves))),fixed(mean(runs.map(run=>run.still))*100,0)+' %'];
 });
 table(`Régime établi, ${themes} thèmes (6 leçons/jour, 4 signalements/leçon, 20 semaines)`,['Stratégie','Fenêtre utile, sem. 1-4','Fenêtre utile, sem. 13-20','Tuiles déplacées / jour (sem. 13-20)','Jours sans aucun mouvement'],rows);
}

// 2. Un thème en 25e place devient le plus utilisé ; un thème en 2e place cesse de l'être.
const shift=(strategy:Strategy,seed:number)=>{
 const themes=30,keys=themeKeys(themes),base=zipf(Array.from({length:themes},(_,index)=>index));
 const preference=(day:number)=>{
  const weights=[...base],progress=Math.min(1,Math.max(0,(day-56)/42));
  weights[24]=base[24]!+(1.2-base[24]!)*progress;weights[1]=base[1]!*(1-progress)+0.01*progress;return weights;
 };
 const run=simulate({themes,days:196,lessonsPerDay:6,signalsPerLesson:4,seed,preference},strategy);
 let jump=0;for(let day=57;day<196;day++)jump=Math.max(jump,position(run,day-1,keys[24]!)-position(run,day,keys[24]!));
 return {run,keys,jump};
};
table('Montée de la 25e place et déclin de la 2e (30 thèmes ; le changement s’étale sur six semaines à partir du jour 56)',
 ['Stratégie','Jours travaillés pour entrer dans les 9','… dans les 3','Plus grand saut en un jour','Place finale du thème monté','Jours travaillés pour que l’ancien 2e quitte les 9','Place finale de l’ancien 2e'],
 strategies.map(strategy=>{
  const runs=each(seed=>shift(strategy,seed));
  const days=(rank:number)=>runs.map(({run,keys})=>firstDayAtRank(run,keys[24]!,rank,56));
  const leave=runs.map(({run,keys})=>{for(let day=56;day<196;day++)if(position(run,day,keys[1]!)>9)return day;return -1;});
  const median=(values:number[])=>[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)]!;
  return [strategy,worked(56,median(days(9))),worked(56,median(days(3))),String(Math.max(...runs.map(run=>run.jump))),
   fixed(mean(runs.map(({run,keys})=>position(run,195,keys[24]!))),1),worked(56,median(leave)),fixed(mean(runs.map(({run,keys})=>position(run,195,keys[1]!))),1)];
 }));

// 3. Deux thèmes aux préférences égales : combien de fois échangent-ils leur place ?
table('Deux thèmes à égalité (18 thèmes, 20 semaines) : échanges de place entre eux',['Stratégie','Échanges (moyenne)','Échanges (maximum)'],
 strategies.map(strategy=>{
  const counts=each(seed=>{
   const weights=zipf(Array.from({length:18},(_,index)=>index));weights[3]=weights[2]!;
   const run=simulate({themes:18,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights},strategy);
   return flips(run,run.keys[2]!,run.keys[3]!,14);
  });
  return [strategy,fixed(mean(counts),1),String(Math.max(...counts))];
 }));

// 4. Changement brutal : au jour 70, les préférences sont redistribuées au hasard.
table('Changement brutal des habitudes au jour 70 (18 thèmes)',['Stratégie','Fenêtre utile, 2 semaines après','… 4 semaines après','… 8 semaines après','Tuiles déplacées / jour (4 semaines après)'],
 strategies.map(strategy=>{
  const runs=each(seed=>{
   const before=zipf(shuffled(18,seeded(seed))),after=zipf(shuffled(18,seeded(seed+1000)));
   const run=simulate({themes:18,days:140,lessonsPerDay:6,signalsPerLesson:4,seed,preference:day=>day<70?before:after},strategy);
   const best=bestShare(after);
   return [visibleShare(run,77,84)/best,visibleShare(run,91,98)/best,visibleShare(run,119,126)/best,movesPerDay(run,70,98)];
  });
  return [strategy,...[0,1,2].map(index=>fixed(mean(runs.map(run=>run[index]!))*100,1)+' %'),fixed(mean(runs.map(run=>run[3]!)))];
 }));

// 5. Quatre semaines sans leçon, puis reprise : l'ordre a-t-il bougé pendant l'absence et à la reprise ?
table('Quatre semaines sans utilisation (jours 70 à 97), 18 thèmes',['Stratégie','Tuiles déplacées pendant l’absence','Tuiles déplacées le jour de la reprise'],
 strategies.map(strategy=>{
  const runs=each(seed=>{
   const weights=zipf(shuffled(18,seeded(seed)));
   const active=(day:number)=>day%7<5&&(day<70||day>=98);
   const run=simulate({themes:18,days:126,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights,active},strategy);
   return [run.orders[97]!.filter((key,index)=>run.orders[69]![index]!==key).length,run.orders[98]!.filter((key,index)=>run.orders[97]![index]!==key).length];
  });
  return [strategy,fixed(mean(runs.map(run=>run[0]!)),1),fixed(mean(runs.map(run=>run[1]!)),1)];
 }));

// 6. Une leçon avec quarante répétitions du dernier thème.
table('Une leçon avec 40 répétitions du dernier thème (18 thèmes, jour 70)',['Stratégie','Place avant','Place le lendemain','Place une semaine après'],
 strategies.map(strategy=>{
  const runs=each(seed=>{
   const weights=zipf(Array.from({length:18},(_,index)=>index));
   const run=simulate({themes:18,days:98,lessonsPerDay:6,signalsPerLesson:4,seed,preference:()=>weights,burst:{day:70,theme:17,uses:40}},strategy);
   return [position(run,70,run.keys[17]!),position(run,71,run.keys[17]!),position(run,77,run.keys[17]!)];
  });
  return [strategy,...[0,1,2].map(index=>fixed(mean(runs.map(run=>run[index]!)),1))];
 }));

// 7. Moniteur très actif et moniteur occasionnel : même changement d'habitudes.
table('Moniteur très actif (8 leçons/jour, 5 j/7) et occasionnel (2 leçons/jour, 2 j/7) : montée d’un thème de la 16e place (18 thèmes, moteur retenu)',['Moniteur','Jours de calendrier pour entrer dans les 9','Jours travaillés','Tuiles déplacées / jour travaillé'],
 [['très actif',8,(day:number)=>day%7<5] as const,['occasionnel',2,(day:number)=>day%7===1||day%7===3] as const].map(([name,lessons,active])=>{
  const runs=each(seed=>{
   const base=zipf(Array.from({length:18},(_,index)=>index));
   const preference=(day:number)=>{const weights=[...base];if(day>=84)weights[15]=1.2;return weights;};
   const run=simulate({themes:18,days:280,lessonsPerDay:lessons,signalsPerLesson:4,seed,preference,active},'engine');
   const day=firstDayAtRank(run,run.keys[15]!,9,84);
   return [day<0?NaN:day-84,day<0?NaN:Array.from({length:day-84},(_,index)=>84+index).filter(active).length,movesPerDay(run,0,280,active)];
  });
  return [name,...[0,1,2].map(index=>fixed(mean(runs.map(run=>run[index]!)),1))];
 }));

// 8. Coût : classement de 30 thèmes sur plusieurs milliers de signalements.
{
 const keys=themeKeys(30),next=seeded(5),usage:ThemeUsage[]=[];let signals=0;
 for(let day=0;day<300;day++)for(let lesson=0;lesson<7;lesson++)for(const key of keys)if(next()<0.2){const uses=1+Math.floor(next()*4);signals+=uses;usage.push({themeKey:key,lessonId:`l${day}-${lesson}`,day:dayName(day),uses,position:1+Math.floor(next()*30)});}
 const previous=rankThemes({manual:keys,usage}).order,start=performance.now();
 for(let index=0;index<200;index++)rankThemes({manual:keys,previous,usage,elapsedDays:1});
 console.log(`\n### Coût\n\n${signals} signalements, ${usage.length} lignes d'usage, 30 thèmes : ${fixed((performance.now()-start)/200,2)} ms par classement.`);
}
console.log(`\nParamètres : ${JSON.stringify(rankingParameters)}`);
