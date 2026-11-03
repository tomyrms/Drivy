import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useCommandSnapshot } from '../../command-store';
import { visibleIntentions, type LessonIntention } from '../../console/agenda-intentions';
import { useConsole } from '../../console/context';

/** Memory only, in the console's drafts: renewed with the account, school, membership and access epoch; never in browser storage. */
const INTENTIONS_KEY = 'agenda/intentions';

/**
 * Intentions de planification de cette école (#109) : celles que le magasin de commandes suit encore, et celles qu'il vient de
 * confirmer jusqu'à une lecture plus récente. La projection les montre ; elle n'en fait jamais un fait, un droit ni un total.
 */
export function useLessonIntentions(readAt: number | undefined) {
  const { schoolId, drafts } = useConsole();
  const { entries, confirmations } = useCommandSnapshot();
  const stored = useRef<LessonIntention[]>((drafts?.get(INTENTIONS_KEY) as LessonIntention[] | undefined) ?? []);
  const [list, setList] = useState<LessonIntention[]>(stored.current);
  const change = useCallback((next: (current: LessonIntention[]) => LessonIntention[]) => {
    stored.current = next(stored.current);
    drafts?.set(INTENTIONS_KEY, stored.current);
    setList(stored.current);
  }, [drafts]);

  // Une confirmation (réponse vérifiée ou reçu AP72) garde l'intention à l'écran, sans marque, jusqu'à la relecture suivante.
  useEffect(() => {
    const confirmed = new Set(confirmations.map(item => item.operationId));
    if (!stored.current.some(item => item.settledAt === undefined && confirmed.has(item.operationId))) return;
    change(current => current.map(item => item.settledAt === undefined && confirmed.has(item.operationId) ? { ...item, settledAt: Date.now() } : item));
  }, [confirmations, change]);

  const followed = useMemo(() => new Set([...entries.values()].filter(entry => entry.meta.schoolId === schoolId).map(entry => entry.meta.operationId)),
    [entries, schoolId]);
  const intentions = useMemo(() => visibleIntentions(list, followed, readAt), [list, followed, readAt]);
  const add = useCallback((intention: LessonIntention) => change(current => [...current.filter(item => item.tag !== intention.tag), intention]), [change]);
  return { intentions, add };
}
