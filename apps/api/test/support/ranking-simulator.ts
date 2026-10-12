import {rankThemes,rankingParameters,type RankingParameters,type ThemeUsage} from '../../src/observation-ranking-engine.js';

/**
 * Moniteur simulé pour le classement intelligent : des préférences vraies, des leçons, et une gêne quand la tuile voulue demande
 * de défiler (il renonce parfois, ou se rabat sur une tuile visible). Générateur à graine : chaque exécution est identique.
 * Sert aux tests du moteur et à scripts/simulate-observation-ranking.ts.
 */
export function seeded(seed:number):()=>number{
 let state=seed>>>0;
 return ()=>{state=(state+0x6D2B79F5)>>>0;let t=state;t=Math.imul(t^(t>>>15),t|1);t^=t+Math.imul(t^(t>>>7),t|61);return ((t^(t>>>14))>>>0)/4294967296;};
}
export const themeKeys=(count:number)=>Array.from({length:count},(_,index)=>`t${String(index+1).padStart(2,'0')}`);
export const dayName=(day:number)=>`d${String(day).padStart(5,'0')}`;
/** Préférences de Zipf : le thème `order[0]` est le plus voulu. Résultat indexé comme l'ordre manuel. */
export function zipf(order:readonly number[],exponent=1):number[]{
 const weights=new Array<number>(order.length).fill(0);order.forEach((theme,rank)=>{weights[theme]=1/(rank+1)**exponent;});return weights;
}
export function shuffled(count:number,next:()=>number):number[]{
 const values=Array.from({length:count},(_,index)=>index);
 for(let index=count-1;index>0;index--){const other=Math.floor(next()*(index+1));[values[index],values[other]]=[values[other]!,values[index]!];}
 return values;
}

export type Strategy='count'|'ewma'|'engine'|'engine-no-hysteresis'|'engine-no-position'|'engine-no-cap';
export const strategies:Strategy[]=['count','ewma','engine-no-hysteresis','engine-no-position','engine-no-cap','engine'];
export interface Scenario {
 themes:number;days:number;lessonsPerDay:number;signalsPerLesson:number;seed:number;
 /** Poids de chaque thème (indexé comme l'ordre manuel) le jour donné. */
 preference:(day:number)=>number[];
 /** Jour travaillé ? Par défaut : cinq jours sur sept. */
 active?:(day:number)=>boolean;
 /** Une leçon où un seul thème est répété. */
 burst?:{day:number;theme:number;uses:number};
 /** Jours pendant lesquels l'ordre reste manuel (historique accumulé avant l'activation). */
 manualUntil?:number;
 parameters?:Partial<RankingParameters>;
}
export interface Run {
 keys:string[];
 /** Ordre affiché chaque jour. */
 orders:string[][];
 /** Par jour : thèmes dont la place a changé depuis la veille. */
 moved:number[];
 /** Par jour : signalements voulus, et parmi eux ceux dont la tuile était visible sans défiler. */
 wanted:number[];visible:number[];
 usage:ThemeUsage[];
}

function poisson(mean:number,next:()=>number):number{
 const limit=Math.exp(-mean);let count=0,product=next();
 while(product>limit){count++;product*=next();}
 return count;
}
function pick(weights:readonly number[],next:()=>number):number{
 let total=0;for(const weight of weights)total+=weight;
 let roll=next()*total;
 for(let index=0;index<weights.length;index++){roll-=weights[index]!;if(roll<=0)return index;}
 return weights.length-1;
}
function parametersFor(strategy:Strategy,overrides:Partial<RankingParameters>={}):RankingParameters{
 const base={...rankingParameters,...JSON.parse(process.env.RANKING_OVERRIDES??'{}') as Partial<RankingParameters>,...overrides};
 if(strategy==='engine-no-hysteresis')return {...base,significance:0,absoluteMargin:0,climbPerDay:0};
 if(strategy==='engine-no-position')return {...base,rowBoost:0};
 if(strategy==='engine-no-cap')return {...base,climbPerDay:0};
 return base;
}
/** Références naïves : tri par nombre d'usages, et tri par usages pondérés d'une demi-vie de trente jours de calendrier. */
function naive(strategy:'count'|'ewma',keys:readonly string[],usage:readonly ThemeUsage[],today:number):string[]{
 const totals=new Map<string,number>();
 for(const row of usage){
  const age=today-Number(row.day.slice(1)),weight=strategy==='count'?1:2**(-age/30);
  totals.set(row.themeKey,(totals.get(row.themeKey)??0)+row.uses*weight);
 }
 const place=new Map(keys.map((key,index)=>[key,index]));
 return [...keys].sort((a,b)=>(totals.get(b)??0)-(totals.get(a)??0)||place.get(a)!-place.get(b)!);
}

export function simulate(scenario:Scenario,strategy:Strategy):Run{
 const next=seeded(scenario.seed),keys=themeKeys(scenario.themes),parameters=parametersFor(strategy,scenario.parameters);
 const active=scenario.active??(day=>day%7<5),usage:ThemeUsage[]=[];
 const run:Run={keys,orders:[],moved:[],wanted:[],visible:[],usage};
 let order=[...keys],ranked:string[]|undefined,rankedDay=0,lesson=0;
 for(let day=0;day<scenario.days;day++){
  // Le classement se refait à la première ouverture d'un jour travaillé, sur les usages des jours précédents.
  if(active(day)&&day>=(scenario.manualUntil??0)){
   if(strategy==='count'||strategy==='ewma')order=naive(strategy,keys,usage,day);
   else{order=rankThemes({manual:keys,previous:ranked,usage,elapsedDays:day-rankedDay,parameters}).order;ranked=order;rankedDay=day;}
  }
  const previous=run.orders.at(-1);
  run.orders.push(order);run.moved.push(previous?order.filter((key,index)=>previous[index]!==key).length:0);
  let wanted=0,visible=0;
  if(active(day)){
   const weights=scenario.preference(day),place=new Map(order.map((key,index)=>[key,index+1]));
   for(let index=0;index<scenario.lessonsPerDay;index++){
    const lessonId=`l${lesson++}`,counts=new Map<number,number>();
    for(let signal=poisson(scenario.signalsPerLesson,next);signal>0;signal--){
     let theme=pick(weights,next);const position=place.get(keys[theme]!)!;
     wanted++;if(position<=parameters.foldSize)visible++;
     if(position>parameters.foldSize){
      // Sous la fenêtre : le moniteur renonce d'autant plus que la tuile est loin, et se rabat une fois sur deux sur une tuile visible.
      const rows=Math.ceil((position-parameters.foldSize)/parameters.columns);
      if(next()<Math.min(0.6,0.2*rows)){
       if(next()<0.5)continue;
       const shown=order.slice(0,parameters.foldSize).map(key=>keys.indexOf(key));
       theme=shown[pick(shown.map(item=>weights[item]!+1e-9),next)]!;
      }
     }
     counts.set(theme,(counts.get(theme)??0)+1);
    }
    if(scenario.burst&&scenario.burst.day===day&&index===0)counts.set(scenario.burst.theme,(counts.get(scenario.burst.theme)??0)+scenario.burst.uses);
    for(const [theme,uses] of counts)usage.push({themeKey:keys[theme]!,lessonId,day:dayName(day),uses,position:place.get(keys[theme]!)!});
   }
  }
  run.wanted.push(wanted);run.visible.push(visible);
 }
 return run;
}

const sum=(values:readonly number[])=>values.reduce((total,value)=>total+value,0);
/** Part des signalements voulus dont la tuile était visible sans défiler, du jour `from` (inclus) au jour `to` (exclu). */
export function visibleShare(run:Run,from:number,to=run.orders.length):number{
 const wanted=sum(run.wanted.slice(from,to));return wanted?sum(run.visible.slice(from,to))/wanted:1;
}
/** La même part si les neuf thèmes les plus voulus étaient toujours dans la fenêtre. */
export function bestShare(weights:readonly number[],fold=rankingParameters.foldSize):number{
 return sum([...weights].sort((a,b)=>b-a).slice(0,fold))/sum(weights);
}
/** Tuiles déplacées par jour travaillé, en moyenne, sur la période. */
export function movesPerDay(run:Run,from:number,to=run.orders.length,active:(day:number)=>boolean=day=>day%7<5):number{
 const days=Array.from({length:to-from},(_,index)=>from+index).filter(active);
 return days.length?sum(days.map(day=>run.moved[day]!))/days.length:0;
}
export function position(run:Run,day:number,key:string):number{return run.orders[day]!.indexOf(key)+1;}
/** Premier jour, à partir de `from`, où le thème est à `rank` ou mieux ; -1 s'il n'y arrive pas. */
export function firstDayAtRank(run:Run,key:string,rank:number,from=0):number{
 for(let day=from;day<run.orders.length;day++)if(position(run,day,key)<=rank)return day;
 return -1;
}
/** Nombre de fois où deux thèmes ont échangé leur ordre relatif. */
export function flips(run:Run,a:string,b:string,from=0):number{
 let count=0;
 for(let day=from+1;day<run.orders.length;day++){
  const before=position(run,day-1,a)<position(run,day-1,b),after=position(run,day,a)<position(run,day,b);
  if(before!==after)count++;
 }
 return count;
}
