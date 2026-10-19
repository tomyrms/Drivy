import { RequestFailure } from './protocol.js';

export function identityConfirmationMessage(error: unknown): string {
  if (!(error instanceof RequestFailure)) return 'Connexion impossible. Réessayez dans un instant.';
  switch (error.code) {
    case 'INVALID_CREDENTIALS': return 'E-mail ou mot de passe incorrect.';
    case 'REAUTH_ACCOUNT_MISMATCH': return 'Utilisez le compte déjà connecté pour confirmer votre identité.';
    case 'REAUTH_PROOF_UNAVAILABLE': return 'La confirmation d’identité est indisponible. Votre connexion et votre saisie sont conservées.';
    case 'RATE_LIMITED': return 'Trop de tentatives. Patientez quelques minutes.';
    case 'SESSION_EXPIRED': return 'Votre connexion a expiré. Fermez cette fenêtre puis reconnectez-vous.';
    default: return 'Connexion impossible. Réessayez dans un instant.';
  }
}
