/** Aide de lecture uniquement. Les faits internes de cours ne valent ni justificatif officiel ni dispense. */
export const prerequisiteRuleVersion='2026-10-28.2';
export type PrerequisiteMoment='APPLICATION'|'THEORY'|'PRACTICAL';
export type PrerequisiteEvidence={state:'DECLARED'|'DOCUMENT_REVIEWED'|'EXEMPTION_REVIEWED'|'MISSING'|'READ_ERROR'|'ACCESS_DENIED'|'NOT_FOUND'|'UNKNOWN'|'INTERNAL_VALIDATION'|'ATTENDANCE_ONLY'|'ENROLLED';completedOn?:string;reviewedOn?:string;validatedAt?:string};
export type PrerequisiteContext={categoryCode:string;today:string;moment:PrerequisiteMoment;applicationSubmittedOn?:string;canton?:string;
  heldCategories?:readonly string[];evidence?:Readonly<Record<string,PrerequisiteEvidence>>};
export interface PrerequisiteHint {id:string;label:string;conclusion:string;detail:string;sourceUrl:string;version:string;checkedOn:string;blocking:false}
const categorySource=(code:string)=>code==='A35'?'https://www.vd.ch/mobilite/automobile-et-navigation/permis/motocycles-a1-et-a':`https://lepermisdeconduire.ch/categories-de-permis/categorie-${code.toLowerCase()}/`;
const transitionSource='https://www.vd.ch/actualites/actualite/news/26530-modernisation-de-la-formation-a-la-conduite';
const isDate=(value:string|undefined):value is string=>!!value&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(`${value}T12:00:00Z`))&&new Date(`${value}T12:00:00Z`).toISOString().slice(0,10)===value;
function conclusion(evidence:PrerequisiteEvidence|undefined,today:string,firstAid=false) {
  if(!evidence)return 'Preuve non renseignée';
  if(evidence.state==='READ_ERROR')return 'Preuve non consultable';
  if(evidence.state==='ACCESS_DENIED')return 'Faits de cours non consultables avec vos droits';
  if(evidence.state==='NOT_FOUND')return 'Dossier indisponible pour cette lecture';
  if(evidence.state==='UNKNOWN')return 'Aucun fait de cours enregistré';
  if(evidence.state==='INTERNAL_VALIDATION')return 'Accomplissement enregistré dans Drivy';
  if(evidence.state==='ATTENDANCE_ONLY')return 'Présences enregistrées · accomplissement non validé';
  if(evidence.state==='ENROLLED')return 'Inscription enregistrée · accomplissement non validé';
  if(evidence.state==='MISSING')return 'Prérequis déclaré manquant';
  if(evidence.state==='EXEMPTION_REVIEWED')return 'Dispense contrôlée par l’école';
  const state=evidence.state==='DOCUMENT_REVIEWED'?'Justificatif contrôlé par l’école':'Cours déclaré suivi';
  // On n'attribue jamais de durée universelle aux cours. Les 6 ans ne concernent ici que les premiers secours.
  if(firstAid&&isDate(evidence.completedOn)&&isDate(today)) {
    const year=Number(today.slice(0,4))-6;
    const threshold=`${year}${today.slice(4)}`;
    if(evidence.completedOn<threshold)return `${state} · ancienneté de plus de 6 ans à vérifier`;
  }
  return state;
}
export function prerequisiteHints(context:PrerequisiteContext):PrerequisiteHint[] {
  const {categoryCode:category,today,moment}=context;
  if(!isDate(today))return [];
  const hints:PrerequisiteHint[]=[];
  const add=(id:string,label:string,detail:string,sourceUrl=categorySource(category),override?:string)=>hints.push({id,label,detail,sourceUrl,
    conclusion:override??conclusion(context.evidence?.[id],today,id==='first-aid'),version:prerequisiteRuleVersion,checkedOn:'2026-10-28',blocking:false});
  const light=['A','A35','A1','B','B1'].includes(category);
  const exemptions:Record<string,readonly string[]>={B:['A','A35','A1','B1'],B1:['A1'],A1:['B','B1'],A35:['B','B1','A1'],A:['B','B1','A35','A1']};
  const declaredExemption=(exemptions[category]??[]).some(code=>context.heldCategories?.includes(code));
  const exemptionConclusion=declaredExemption?'Dispense possible selon le permis détenu':undefined;
  if(moment==='APPLICATION'&&light)add('first-aid','Premiers secours',
    'Vérifier une attestation ne remontant pas à plus de six ans au dépôt de la demande, ou une dispense reconnue. Un permis détenu peut ouvrir une dispense ; le contrôle du permis d’élève ne suffit pas à l’établir.',undefined,exemptionConclusion);
  if(light&&(moment==='PRACTICAL'||moment==='THEORY'&&today>='2027-01-01')) {
    if(moment==='THEORY') {
      const submitted=context.applicationSubmittedOn;
      if(context.canton==='VD'&&isDate(submitted)&&submitted<'2027-01-01')add('awareness','Sensibilisation / CTC',
        'Le canton de Vaud annonce une transition pour les demandes déposées avant le 1er janvier 2027. Faire confirmer sa portée sur le dossier et les connaissances de CTC interrogées en 2027 auprès du service cantonal.',transitionSource,'Transition possible — à vérifier auprès du canton');
      else add('awareness','Sensibilisation / CTC',
        'Dès le 1er janvier 2027, le CTC précède la théorie. Vérifier la date de dépôt de la demande et les dispositions transitoires auprès du canton ; la date d’ouverture de la formation Drivy ne les remplace pas.',transitionSource,
        !isDate(submitted)?'Date de demande inconnue — transition à vérifier':exemptionConclusion);
    } else add('awareness','Sensibilisation / CTC',
      'Vérifier le cours suivi ou la dispense applicable avant la démarche d’examen. Aucun délai de validité n’est calculé depuis une présence ou une validation interne de cours.',undefined,exemptionConclusion);
  }
  if(['A1','A35','A'].includes(category)&&moment==='PRACTICAL')add('motorcycle-basic','Formation pratique moto',
    category==='A'?'Vérifier le parcours A limitée → A et les anciens droits. L’IPB déjà reconnue ne doit pas être réexigée automatiquement.':
      'Le parcours initial prévoit une instruction pratique de base de 12 heures. Vérifier l’IPB déjà reconnue, les anciens droits et la validité réelle du permis d’élève ; une présence dans Drivy ne vaut pas attestation officielle.');
  if(['C','C1','D','D1'].includes(category)&&moment==='PRACTICAL')add('additional-theory','Théorie complémentaire',
    'Vérifier la théorie complémentaire et les éventuelles dispenses selon les catégories déjà détenues. La qualification OACP pour le transport professionnel est une démarche distincte.');
  if(category==='D'&&moment==='PRACTICAL')add('passenger-practice','Pratique préalable et formation minimale',
    'La pratique préalable et le volume minimal de formation dépendent du permis détenu et du parcours d’accès. Faire confirmer le cas par le service cantonal ; aucun total de leçons Drivy ne vaut preuve automatique.');
  return hints;
}
