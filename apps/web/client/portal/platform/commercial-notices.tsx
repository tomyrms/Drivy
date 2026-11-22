import { useCallback, useEffect, useRef, useState } from 'react';
import { request } from '../../protocol';
import { noticeEventLabel, platformCommercialNoticesReadResult, platformCommercialNoticesResult, platformFailure, requestKindLabel, type PlatformCommercialNotice } from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import type { PlatformConsoleState } from './use-platform-console';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

/**
 * Avis aux opérateurs (R01-T08) : une demande d'école à traiter. Une relecture ne duplique rien ; marquer lu rejoue la même opération
 * tant que la réponse n'a pas été reçue, et un échec laisse les avis visibles.
 */
export function CommercialNotices({ state }: { state: PlatformConsoleState }) {
  const [items, setItems] = useState<readonly PlatformCommercialNotice[]>([]);
  const [problem, setProblem] = useState<string | null>(null), [marking, setMarking] = useState(false);
  const operation = useRef<{ key: string; id: string } | null>(null);
  const csrf = state.session?.csrfToken;

  const load = useCallback(async () => {
    try { const result = await request('platform/commercial-notices', platformCommercialNoticesResult); setItems(result.data.items); setProblem(null); }
    catch (reason) { setProblem(platformFailure(reason)); }
  }, []);
  useEffect(() => { if (csrf) void load(); }, [csrf, load]);

  async function markRead() {
    if (!csrf || marking || items.length === 0) return;
    const ids = items.map(item => item.id), key = ids.join(',');
    const id = operation.current?.key === key ? operation.current.id : crypto.randomUUID();
    operation.current = { key, id };
    setMarking(true); setProblem(null);
    try {
      await request('platform/commercial-notices/read', platformCommercialNoticesReadResult, { csrf, body: { operationId: id, ids } });
      operation.current = null;
      await load();
    } catch (reason) { setProblem(platformFailure(reason)); }
    finally { setMarking(false); }
  }

  if (items.length === 0 && !problem) return null;
  return <div className="platform-group" role="group" aria-label="Demandes des écoles">
    <div className="platform-fiche-head">
      <h3 className="platform-subtitle">Demandes des écoles</h3>
      {items.length > 0 && <div className="platform-actions"><Button variant="ghost" disabled={marking} aria-busy={marking} onClick={() => void markRead()}>Marquer comme lu</Button></div>}
    </div>
    {problem && <Alert variant="destructive"><AlertTitle>Avis non actualisés</AlertTitle><AlertDescription>{problem}</AlertDescription>
      <div className="mt-3"><Button variant="outline" onClick={() => void load()}>Réessayer</Button></div></Alert>}
    {items.length > 0 && <ul className="platform-list">{items.map(item => <li key={item.id}>
      <div className="platform-summary"><strong>{item.clientName}</strong>
        <span>{requestKindLabel(item.kind)} · {noticeEventLabel(item.event)} · {dateTime(item.createdAt)}</span></div>
      <Button variant="ghost" disabled={state.busy} aria-label={`Ouvrir la fiche de ${item.clientName}`} onClick={() => void state.clients.openClient(item.clientId)}>Ouvrir</Button>
    </li>)}</ul>}
  </div>;
}
