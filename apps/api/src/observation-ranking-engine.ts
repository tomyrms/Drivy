/**
 * Moteur du classement intelligent des signalements. Pur : ni base, ni horloge, ni interface. Il classe toutes les clés reçues,
 * quel que soit leur nombre ; la fenêtre de neuf tuiles de « Signaler » n'y apparaît que comme une donnée du biais de position.
 * Méthode, paramètres et simulations : docs/implementation/classement-intelligent-20261013.md.
 */

/** Usage d'un thème dans une leçon, un jour donné (date locale de l'école). `position` : rang de la tuile au moment du geste. */
export interface ThemeUsage {themeKey:string;lessonId:string;day:string;uses:number;position:number|null}

export interface RankingParameters {
 /** Demi-vie de la preuve, en jours d'activité (jours où le moniteur a signalé), pas en jours de calendrier. */
 halfLifeActiveDays:number;
 /** Jours d'activité pris en compte ; au-delà, le poids est négligeable. */
 windowActiveDays:number;
 /** Plafond de la preuve d'une leçon pour un thème : log2(1+usages), borné. */
 lessonCap:number;
 /** Tuiles visibles sans défiler, et colonnes de la grille : seules données d'affichage, pour corriger le biais de position. */
 foldSize:number;columns:number;
 /** Surpoids d'un usage fait sous la fenêtre, par rangée à défiler, et son plafond. */
 rowBoost:number;maxPositionWeight:number;
 /** Leçons distinctes exigées avant qu'un thème compte, et constante du lissage (en leçons). */
 minimumLessons:number;confidenceLessons:number;
 /** Poids de l'ordre manuel : le premier thème reçoit `priorSpan`, le dernier presque rien. */
 priorSpan:number;
 /**
  * Hystérésis : un thème n'en dépasse un autre que si l'écart de leurs scores excède `significance` écarts-types du bruit de leur
  * preuve (une somme décroissante d'usages a une variance proche de sa moitié), plus `absoluteMargin`.
  */
 significance:number;absoluteMargin:number;
 /** Places gagnées au plus par jour écoulé depuis le dernier classement ; 0 : sans limite. */
 climbPerDay:number;
}

export const rankingParameters:RankingParameters={
 halfLifeActiveDays:12,windowActiveDays:120,lessonCap:3,foldSize:9,columns:3,rowBoost:0.25,maxPositionWeight:2,
 minimumLessons:2,confidenceLessons:2,priorSpan:1,significance:1.5,absoluteMargin:0.3,climbPerDay:6
};

export interface ThemeScore {key:string;score:number;evidence:number;lessons:number;prior:number}

/** Un usage fait en défilant vaut davantage : la tuile était moins accessible, le geste dit plus. Borné, pour ne rien amplifier. */
export function positionWeight(position:number|null,p:RankingParameters=rankingParameters):number{
 if(position===null||position<=p.foldSize)return 1;
 return Math.min(p.maxPositionWeight,1+p.rowBoost*Math.ceil((position-p.foldSize)/p.columns));
}

/**
 * Score de chaque thème de `manual` (l'ordre manuel des thèmes affichés). Preuve : somme, sur les leçons, d'un terme saturé par
 * leçon, corrigé de la position et décroissant avec les jours d'activité écoulés (moyenne mobile exponentielle). Elle est lissée
 * par la taille de l'échantillon, puis ajoutée à un a priori tiré de l'ordre manuel.
 */
export function scoreThemes(manual:readonly string[],usage:readonly ThemeUsage[],p:RankingParameters=rankingParameters):Map<string,ThemeScore>{
 // Les jours d'activité se comptent sur tous les usages, y compris ceux de thèmes masqués depuis : le temps du moniteur est le même.
 const days=[...new Set(usage.map(row=>row.day))].sort().reverse().slice(0,p.windowActiveDays),age=new Map(days.map((day,index)=>[day,index]));
 const sums=new Map<string,{evidence:number;decayed:number;lessons:Set<string>}>();
 for(const row of usage){
  const elapsed=age.get(row.day);if(elapsed===undefined||row.uses<=0)continue;
  const weight=2**(-elapsed/p.halfLifeActiveDays);
  let sum=sums.get(row.themeKey);if(!sum){sum={evidence:0,decayed:0,lessons:new Set()};sums.set(row.themeKey,sum);}
  sum.evidence+=Math.min(Math.log2(1+row.uses),p.lessonCap)*positionWeight(row.position,p)*weight;
  if(!sum.lessons.has(row.lessonId)){sum.lessons.add(row.lessonId);sum.decayed+=weight;}
 }
 const scores=new Map<string,ThemeScore>();
 manual.forEach((key,index)=>{
  const sum=sums.get(key),prior=p.priorSpan*(1-index/manual.length);
  // Sous le seuil de leçons, la preuve ne compte pas : un usage isolé ne déplace rien.
  const evidence=sum&&sum.lessons.size>=p.minimumLessons?sum.evidence*sum.decayed/(sum.decayed+p.confidenceLessons):0;
  scores.set(key,{key,score:prior+evidence,evidence,lessons:sum?.lessons.size??0,prior});
 });
 return scores;
}

/** Un ordre enregistré, ramené aux thèmes affichés : une clé disparue est retirée, une clé nouvelle part en fin, dans l'ordre manuel. */
export function reconcileOrder(order:readonly string[],manual:readonly string[]):string[]{
 const allowed=new Set(manual),seen=new Set<string>(),kept=order.filter(key=>allowed.has(key)&&!seen.has(key)&&seen.add(key));
 return [...kept,...manual.filter(key=>!seen.has(key))];
}

export interface RankingInput {
 /** Thèmes affichés, dans l'ordre manuel. */
 manual:readonly string[];
 /** Classement précédent ; absent ou vide à l'activation : le classement repart alors des scores seuls. */
 previous?:readonly string[]|undefined;
 usage:readonly ThemeUsage[];
 /** Jours de calendrier depuis le classement précédent (au moins 1). */
 elapsedDays?:number;
 parameters?:RankingParameters;
}

/**
 * Classement complet. À partir du classement précédent, chaque thème monte juste au-dessus du plus haut thème qu'il domine
 * nettement (hystérésis), sans gagner plus de `climbPerDay` places par jour écoulé ; il ne descend que parce qu'un autre le dépasse.
 * Deux thèmes aux scores proches gardent donc leur ordre. Un thème qui vient d'être affiché se place d'après son score, sans limite.
 */
export function rankThemes(input:RankingInput):{order:string[];scores:Map<string,ThemeScore>}{
 const p=input.parameters??rankingParameters,manual=[...new Set(input.manual)],scores=scoreThemes(manual,input.usage,p);
 const score=(key:string)=>scores.get(key)!.score;
 if(!input.previous?.length){
  const place=new Map(manual.map((key,index)=>[key,index]));
  return {order:[...manual].sort((a,b)=>score(b)-score(a)||place.get(a)!-place.get(b)!),scores};
 }
 const known=new Set(input.previous),limit=p.climbPerDay>0?p.climbPerDay*Math.max(1,Math.floor(input.elapsedDays??1)):Infinity;
 const evidence=(key:string)=>scores.get(key)!.evidence;
 const dominates=(a:string,b:string)=>score(a)-score(b)>p.significance*Math.sqrt((evidence(a)+evidence(b))/2)+p.absoluteMargin;
 const order:string[]=[];
 for(const key of reconcileOrder(input.previous,manual)){
  let target=order.length;
  if(known.has(key)){
   const top=order.findIndex(other=>dominates(key,other));
   if(top>=0)target=Math.max(top,order.length-limit);
  }else{
   const lower=order.findIndex(other=>score(other)<score(key));
   if(lower>=0)target=lower;
  }
  order.splice(target,0,key);
 }
 return {order,scores};
}
