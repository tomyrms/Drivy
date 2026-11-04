import type { CommandKind, SchoolCommand } from './command-core.js';

/**
 * Règles pures de reprise d'une demande suivie (#106), partagées par le magasin de commandes et par ce que le bureau montre.
 * Aucune ne décide d'un droit : elles disent seulement ce qu'un renvoi peut encore signifier.
 *
 * Pur : ni DOM, ni réseau, ni stockage. Le magasin applique ces règles avant le transport ; les écrans les lisent pour
 * retirer une action, jamais pour l'autoriser à la place du serveur.
 */

/** Le créneau voulu d'une création ou d'un déplacement, en millisecondes, quand le corps de la demande le porte. */
export function desiredSlotOf(command: SchoolCommand | null): number | null {
  if (!command || (command.kind !== 'createLesson' && command.kind !== 'moveLesson')) return null;
  const start = command.body.plannedStart;
  return typeof start === 'string' && Number.isFinite(Date.parse(start)) ? Date.parse(start) : null;
}

/**
 * Renvoyer la même demande n'a de sens que tant que le créneau voulu est encore devant : une création ou un déplacement
 * dont l'horaire est passé n'est plus renvoyé, il reste à vérifier le résultat ou à abandonner le suivi.
 * Une commande restaurée sans corps ne prouve pas que son créneau est encore devant : pas de renvoi non plus.
 * Tout autre type de commande garde le comportement existant (`true` ici, le magasin décide du reste).
 */
export function lessonResendAllowed(entry: { readonly kind: CommandKind; readonly command: SchoolCommand | null }, now = Date.now()): boolean {
  if (entry.kind !== 'createLesson' && entry.kind !== 'moveLesson') return true;
  const slot = desiredSlotOf(entry.command);
  return slot !== null && slot > now;
}

/** Raison courte affichée à côté d'un renvoi retiré, ou `null` quand le renvoi reste possible. */
export function lessonResendReason(entry: { readonly kind: CommandKind; readonly command: SchoolCommand | null }, now = Date.now()): string | null {
  return lessonResendAllowed(entry, now) ? null : 'L’horaire demandé est passé : vérifiez le résultat ou arrêtez le suivi.';
}
