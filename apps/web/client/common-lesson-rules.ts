// Généré par apps/api/scripts/generate-school-setup-contract.ts depuis school-commercial-rules.ts.
import {z} from 'zod';

/** School answers, not a billing engine. Existing textual policies are never converted implicitly. */
export const commonLessonRulesSchema=z.object({
  cancellationHours:z.number().int().min(0).max(8760).nullable(),
  lateAction:z.enum(['CONTACT','NO_FEE']).nullable(),
  paymentText:z.string().max(2000),
  exceptionsText:z.string().max(2000),
}).strict();
export type CommonLessonRules=z.infer<typeof commonLessonRulesSchema>;
export function commonLessonTexts(rules:CommonLessonRules,contact:string){
  const cancellationPolicyText=rules.lateAction==='NO_FEE'
    ? `Pour annuler ou déplacer une leçon, contactez l’école : ${contact}. L’école ne facture pas de frais d’annulation.`
    : rules.lateAction==='CONTACT'&&rules.cancellationHours!==null
      ? `Pour annuler ou déplacer une leçon sans frais, prévenez l’école au moins ${rules.cancellationHours} heure(s) avant son début : ${contact}. Passé ce délai ou en cas d’absence, contactez l’école pour examiner la situation. Contacter l’école ne confirme pas l’annulation. Aucun frais n’est calculé ou prélevé automatiquement par Drivy.` : '';
  return {cancellationPolicyText,termsText:[
    'Le prix et la durée sont ceux de la leçon réservée.',rules.paymentText.trim(),cancellationPolicyText,rules.exceptionsText.trim(),
  ].filter(Boolean).join('\n\n')};
}
