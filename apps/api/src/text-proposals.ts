/**
 * Textes proposés par Drivy à une école (décision du porteur du 13 octobre 2026) : l'administration les relit,
 * les modifie si besoin et les adopte d'un geste. Rien n'est adopté sans ce geste, et chaque texte reste modifiable.
 * Ils décrivent ce que Drivy fait réellement : aucune durée de conservation n'est promise tant qu'aucune suppression
 * automatique ne l'applique, et le recalage routier n'est cité que s'il est configuré. Relecture juridique à prévoir
 * avant l'accueil d'écoles réelles (analyse-textes-ecole-20261013.md).
 */
export interface ProposalContext { schoolName: string; contactEmail: string; mapMatchingProvider?: 'mapbox' | 'osrm' | undefined }
export interface ProposedFieldRule {
  field: 'firstName' | 'lastName' | 'contactPhone' | 'contactEmail';
  requirement: 'REQUIRED' | 'OPTIONAL'; stage: 'JOIN' | 'OPTIONAL';
  purposeCode: 'IDENTIFICATION' | 'LESSON_CONTACT'; explanation: string;
}

export function proposedDataPolicy(context: ProposalContext) {
  const routing = context.mapMatchingProvider === 'mapbox'
    ? ' Pour caler le trajet sur les routes, ses positions sont envoyées à Mapbox, un service établi aux États-Unis, qui ne reçoit ni votre nom ni vos coordonnées.'
    : context.mapMatchingProvider === 'osrm'
      ? ' Pour caler le trajet sur les routes, ses positions sont traitées dans l’hébergement de Drivy, sans envoyer vos positions à un service tiers.'
      : '';
  const noticeText = [
    `${context.schoolName} utilise Drivy pour organiser votre formation à la conduite : leçons, suivi de votre progression, bilans et, si vous l’acceptez, enregistrement du trajet pendant les leçons.`,
    'Les données traitées sont votre nom et vos coordonnées, vos leçons, les observations et bilans de vos moniteurs, et le trajet GPS des leçons pour lesquelles vous avez donné votre accord. Le GPS n’enregistre que pendant une leçon, depuis l’appareil du moniteur.',
    'Les accès dépendent des rôles dans l’école. Vous voyez vos leçons réalisées, leurs observations, bilans et objectifs partagés automatiquement. Les notes privées du moniteur ne vous sont pas montrées. Les messages utilisent leur propre chiffrement et leurs propres destinataires.',
    `Drivy héberge ces données pour le compte de l’école.${routing} Les fonds de carte sont affichés par Apple Plans.`,
    `Pour exercer vos droits ou demander une correction, un accès ou un effacement, écrivez à ${context.contactEmail}. Le retrait du choix GPS est accessible dans votre compte ; il ne supprime ni le compte ni les données déjà enregistrées. L’appareil du moniteur reçoit ce retrait à sa prochaine vérification ; hors réseau, son autorisation temporaire expire.`,
  ].join('\n\n');
  const retentionText = [
    'Drivy ne réalise pas encore de purge automatique à une échéance définie. [À compléter avec l’exploitant avant utilisation réelle : durées par type de données, traitement des sauvegardes et procédure d’effacement.]',
    `Adressez vos demandes à ${context.contactEmail}. Une demande ne signifie pas que l’effacement a déjà eu lieu ; l’école doit examiner sa portée et les obligations de conservation applicables, puis confirmer le traitement effectué.`,
  ].join('\n\n');
  return { noticeText, retentionText, contactEmail: context.contactEmail };
}

/** Le strict nécessaire : rien de ce qui est proposé ne bloque la planification d'une leçon. */
export const proposedProfileFields: readonly ProposedFieldRule[] = [
  { field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous reconnaître dans l’école et sur vos bilans.' },
  { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Pour vous reconnaître dans l’école et sur vos bilans.' },
  { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous prévenir d’un changement de leçon.' },
  { field: 'contactEmail', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous écrire au sujet de vos leçons.' },
];

export function proposedProcedure() {
  return {
    procedureText: 'Chaque leçon commence au lieu de rendez-vous convenu et dure le temps réservé. Le moniteur fait le point au départ, conduit la leçon avec vous, puis vous remet un bilan dans l’app.',
    cancellationPolicyText: '[À compléter : délai et marche à suivre choisis par l’école pour les leçons individuelles.]',
  };
}

export function proposedCommercialTerms(context: ProposalContext) {
  return {
    label: 'Conditions générales',
    termsText: [
      'Le prix d’une leçon est celui affiché au moment de sa réservation.',
      'Les leçons se règlent auprès de l’école, selon les moyens de paiement qu’elle accepte.',
      '[À compléter : conditions d’annulation de l’école pour cette prestation.]',
      `Pour toute question : ${context.contactEmail}.`,
    ].join('\n\n'),
  };
}
