import type { Tariff, TariffStatus } from '../../formation-api';

/** Un tarif non proposé ou terminé reste consultable dans les archives ; il n'est ni supprimé ni masqué par le serveur. */
const archivedStatuses: ReadonlySet<TariffStatus> = new Set(['DISABLED', 'ENDED']);
export function tariffGroups(tariffs: readonly Tariff[]): { current: Tariff[]; archived: Tariff[] } {
  return { current: tariffs.filter(item => !archivedStatuses.has(item.status)), archived: tariffs.filter(item => archivedStatuses.has(item.status)) };
}

/** État effectif d'un tarif, lisible sans ouvrir son détail : seuls les états inhabituels reçoivent un badge. */
export const statusExplanations: Partial<Record<TariffStatus, string>> = {
  TERMS_NOT_APPROVED: 'Ses conditions ne sont pas approuvées : il ne peut pas être réservé.',
  TERMS_EXPIRED: 'Ses conditions ont expiré : il ne peut pas être réservé.',
  TERMS_NOT_YET: 'Ses conditions ne sont pas encore en vigueur.',
};
