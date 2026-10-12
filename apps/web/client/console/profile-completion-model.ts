/** Règles pures du bloc « Profil à compléter » du dossier web : libellés, décompte, corps de la commande. */
/** Champs que la readiness PLAN_LESSON nomme, dans l’ordre de la politique de l’école. */
export type MissingField = 'firstName' | 'lastName' | 'birthDate' | 'postalAddress' | 'contactEmail' | 'contactPhone';
export const labels: Record<MissingField, string> = {
  firstName: 'Prénom', lastName: 'Nom', birthDate: 'Date de naissance', postalAddress: 'Adresse postale',
  contactEmail: 'E-mail', contactPhone: 'Téléphone',
};
export const countries = [
  { value: 'CH', label: 'Suisse' }, { value: 'FR', label: 'France' }, { value: 'DE', label: 'Allemagne' },
  { value: 'IT', label: 'Italie' }, { value: 'AT', label: 'Autriche' }, { value: 'LI', label: 'Liechtenstein' },
] as const;
type Address = { line1: string; postalCode: string; locality: string; countryCode: string };
export type Draft = Partial<Record<Exclude<MissingField, 'postalAddress'>, string>> & { postalAddress?: Address };

export const missingCount = (count: number) => count === 1 ? '1 information manquante' : `${count} informations manquantes`;

/** Ce que la saisie envoie : seuls les champs renseignés, une adresse seulement complète. `null` tant que rien n’est prêt. */
export function profileBody(fields: readonly MissingField[], draft: Draft): Record<string, unknown> | null {
  const body: Record<string, unknown> = {};
  for (const field of fields) {
    if (field === 'postalAddress') {
      const address = draft.postalAddress;
      if (address && [address.line1, address.postalCode, address.locality, address.countryCode].every(value => value.trim()))
        body.postalAddress = { line1: address.line1.trim(), line2: null, postalCode: address.postalCode.trim(), locality: address.locality.trim(), countryCode: address.countryCode };
    } else {
      const value = draft[field]?.trim();
      if (value) body[field] = value;
    }
  }
  return Object.keys(body).length ? body : null;
}
