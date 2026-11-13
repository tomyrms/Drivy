import { useRef, useState } from 'react';
import { okSchema, request, RequestFailure, type Session } from '../../protocol';
import {
  ficheChanges, platformClientDetailResult, platformClientsResult, platformCodeResult, platformFailureKind, platformIssuedCodeResult, platformPendingCodeResult,
  platformUnattachedResult,
  type FicheDraft, type PlatformClient, type PlatformClientCode, type PlatformClientDetail, type PlatformClientPreparation, type PlatformIssuedCode,
  type PlatformPendingCode, type PlatformUnattachedSchool,
} from '../../platform-model';

export type ClientFilter = 'ALL' | PlatformClientPreparation;
export type ClientPage = { items: PlatformClient[]; total: number | null; nextCursor: string | null };
/** « Créer un code » : pour une fiche existante, ou pour une école cliente nouvelle dont seul le nom est saisi. */
export type CodeTarget = { clientId: string | null; clientName: string | null };
/** « Rattacher une école » : à une fiche existante, ou en créant la fiche avec l'école. */
export type AttachTarget = { client: PlatformClientDetail | null };
export type CopyKind = 'code' | 'link';
export type ClientSnapshot = { page: ClientPage; pending: PlatformPendingCode | null; selected: PlatformClientDetail | null };
type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>;
  /** Relecture à l'intérieur d'une commande en cours, et relecture qui prend sa propre place. */
  reload: () => Promise<void>; refresh: () => Promise<void>;
};

const PAGE_SIZE = 25;
const emptyPage: ClientPage = { items: [], total: null, nextCursor: null };

export function clientsPath(search: string, preparation: ClientFilter, cursor?: string | null) {
  const query = new URLSearchParams({ limit: String(PAGE_SIZE) });
  if (cursor) query.set('cursor', cursor);
  if (search) query.set('q', search);
  if (preparation !== 'ALL') query.set('preparation', preparation);
  return `platform/clients?${query}`;
}
const unattachedPath = (search: string) => `platform/unattached-schools?${new URLSearchParams({ limit: '50', ...(search ? { q: search } : {}) })}`;

/**
 * Écoles clientes : annuaire paginé, fiche, codes d'ouverture, rattachement d'une école existante. Comme le reste de la console,
 * le navigateur ne garde que des projections de lecture ; le code d'ouverture n'existe qu'entre la réponse de création et sa fermeture.
 * Chaque commande garde son identifiant d'opération tant que son résultat est inconnu : la même demande, rejouée, dit si elle a eu lieu.
 */
export function usePlatformClients({ session, perform, reload, refresh }: Kernel) {
  const [page, setPage] = useState<ClientPage>(emptyPage), [search, setSearch] = useState(''), [preparation, setPreparation] = useState<ClientFilter>('ALL');
  const [selected, setSelected] = useState<PlatformClientDetail | null>(null), [pending, setPending] = useState<PlatformPendingCode | null>(null);
  const [codeTarget, setCodeTarget] = useState<CodeTarget | null>(null), [issued, setIssued] = useState<PlatformIssuedCode | null>(null);
  const [copied, setCopied] = useState<CopyKind | null>(null), [copyFailed, setCopyFailed] = useState(false), [uncertain, setUncertain] = useState(false);
  const [attach, setAttach] = useState<AttachTarget | null>(null), [unattached, setUnattached] = useState<PlatformUnattachedSchool[]>([]);
  const filters = useRef({ search: '', preparation: 'ALL' as ClientFilter }), selectedId = useRef<string | null>(null);
  const operations = useRef(new Map<string, string>());
  const codeOperation = useRef<{ signature: string; operationId: string } | null>(null);

  const operationFor = (key: string) => {
    let operationId = operations.current.get(key);
    if (!operationId) { operationId = crypto.randomUUID(); operations.current.set(key, operationId); }
    return operationId;
  };
  /** Seule une réponse inconnue garde l'opération : le reste est tranché, la prochaine demande repart d'une opération neuve. */
  const settle = (key: string, reason?: unknown) => { if (reason === undefined || platformFailureKind(reason) !== 'unconfirmed') operations.current.delete(key); };

  function reset() {
    setPage(emptyPage); setSearch(''); setPreparation('ALL'); setSelected(null); setPending(null); setCodeTarget(null); setIssued(null); setCopied(null);
    setCopyFailed(false); setUncertain(false); setAttach(null); setUnattached([]);
    filters.current = { search: '', preparation: 'ALL' }; selectedId.current = null; operations.current.clear(); codeOperation.current = null;
  }

  /** Lecture groupée pour le chargement de la console : l'annuaire sous les filtres courants, le code en attente, la fiche ouverte. */
  async function snapshot(): Promise<ClientSnapshot> {
    const open = selectedId.current;
    const [list, waiting, detail] = await Promise.all([
      request(clientsPath(filters.current.search, filters.current.preparation), platformClientsResult),
      request('platform/school-codes/pending', platformPendingCodeResult),
      open ? request(`platform/clients/${open}`, platformClientDetailResult).then(result => result.data).catch(reason => {
        // Une fiche qui n'existe plus se referme sans bruit ; tout autre échec reste un échec.
        if (reason instanceof RequestFailure && reason.status === 404) return null;
        throw reason;
      }) : Promise.resolve(null),
    ]);
    return { page: list.data, pending: waiting.pending, selected: detail };
  }
  function apply(next: ClientSnapshot) {
    setPage(next.page); setPending(next.pending); setSelected(next.selected);
    if (!next.selected) selectedId.current = null;
  }

  // --- Annuaire ---
  const searchClients = (text: string, value: ClientFilter = filters.current.preparation) => perform(async () => {
    const next = { search: text.trim(), preparation: value };
    const result = await request(clientsPath(next.search, next.preparation), platformClientsResult);
    filters.current = next; setSearch(next.search); setPreparation(next.preparation); setPage(result.data);
  });
  const moreClients = () => perform(async () => {
    if (!page.nextCursor) return;
    const result = await request(clientsPath(filters.current.search, filters.current.preparation, page.nextCursor), platformClientsResult);
    setPage(previous => {
      const known = new Set(previous.items.map(item => item.id));
      return { items: [...previous.items, ...result.data.items.filter(item => !known.has(item.id))], total: result.data.total, nextCursor: result.data.nextCursor };
    });
  });

  // --- Fiche ---
  const openClient = (id: string) => perform(async () => {
    const result = await request(`platform/clients/${id}`, platformClientDetailResult);
    selectedId.current = result.data.id; setSelected(result.data);
  });
  const closeClient = () => { selectedId.current = null; setSelected(null); };
  const saveFiche = (client: PlatformClientDetail, draft: FicheDraft) => perform(async () => {
    if (!session) return;
    const changes = ficheChanges(client, draft);
    if (Object.keys(changes).length === 0) return;
    const key = `fiche:${client.id}:${client.version}:${JSON.stringify(changes)}`, operationId = operationFor(key);
    try {
      const result = await request(`platform/clients/${client.id}/update`, platformClientDetailResult,
        { csrf: session.csrfToken, body: { operationId, version: client.version, ...changes } });
      settle(key); selectedId.current = result.data.id; setSelected(result.data);
    } catch (reason) { settle(key, reason); throw reason; }
    await reload();
  });

  // --- Codes d'ouverture ---
  const startCode = (target: CodeTarget) => { setCopied(null); setCopyFailed(false); setUncertain(false); setCodeTarget(target); };
  /** Fermer la boîte ne perd rien : un code créé mais non confié reste proposé dans l'annuaire, et une demande inconnue y est reprise. */
  const stopCode = () => {
    const unfinished = issued !== null || uncertain;
    setCodeTarget(null); setIssued(null); setCopied(null); setCopyFailed(false);
    if (unfinished) void refresh();
  };
  const issueCode = (input: { clientId?: string; displayName?: string; validityDays: number }) => perform(async () => {
    if (!session) return;
    const signature = JSON.stringify(input);
    const operation = codeOperation.current?.signature === signature ? codeOperation.current : (codeOperation.current = { signature, operationId: crypto.randomUUID() });
    try {
      const result = await request('platform/school-codes', platformIssuedCodeResult, { csrf: session.csrfToken, body: { operationId: operation.operationId, ...input } });
      codeOperation.current = null; setUncertain(false); setIssued(result); setCopied(null); setCopyFailed(false);
    } catch (reason) {
      if (platformFailureKind(reason) === 'unconfirmed') setUncertain(true); else { codeOperation.current = null; setUncertain(false); }
      throw reason;
    }
    await reload();
  });
  /** Après une coupure ou une fermeture : le relais rend le même code pour la même opération, sans en créer un second. */
  const resumeCode = () => perform(async () => {
    if (!session || !pending) return;
    const result = await request('platform/school-codes', platformIssuedCodeResult, { csrf: session.csrfToken, body: {
      operationId: pending.operationId, ...(pending.clientId ? { clientId: pending.clientId } : {}),
      ...(pending.displayName ? { displayName: pending.displayName } : {}), ...(pending.validityDays !== undefined ? { validityDays: pending.validityDays } : {}),
    } });
    setCodeTarget({ clientId: pending.clientId ?? null, clientName: pending.displayName ?? null }); setIssued(result); setCopied(null); setCopyFailed(false);
  });
  const closeCode = () => perform(async () => {
    if (!session) return;
    await request('platform/school-codes/clear', okSchema, { csrf: session.csrfToken, body: {} });
    codeOperation.current = null; setIssued(null); setPending(null); setCodeTarget(null); setUncertain(false); setCopied(null);
    await reload();
  });
  const revokeCode = (code: PlatformClientCode) => perform(async () => {
    if (!session) return;
    const key = `revoke:${code.id}`, operationId = operationFor(key);
    try {
      await request(`platform/school-codes/${code.id}/revoke`, platformCodeResult, { csrf: session.csrfToken, body: { operationId } });
      settle(key);
    } catch (reason) { settle(key, reason); throw reason; }
    await reload();
  });
  async function copy(kind: CopyKind) {
    if (!issued) return;
    const value = kind === 'code' ? issued.code : issued.link;
    if (!value) return;
    setCopied(null); setCopyFailed(false);
    try { await navigator.clipboard.writeText(value); setCopied(kind); }
    catch { setCopyFailed(true); }
  }

  // --- Rattacher une école existante ---
  const startAttach = (client: PlatformClientDetail | null) => perform(async () => {
    const result = await request(unattachedPath(''), platformUnattachedResult);
    setUnattached(result.data.items); setAttach({ client });
  });
  const stopAttach = () => { setAttach(null); setUnattached([]); };
  const searchUnattached = (text: string) => perform(async () => {
    const result = await request(unattachedPath(text.trim()), platformUnattachedResult);
    setUnattached(result.data.items);
  });
  const attachSchool = (school: PlatformUnattachedSchool) => perform(async () => {
    if (!session || !attach) return;
    const client = attach.client;
    const key = `attach:${client?.id ?? 'new'}:${client?.version ?? 0}:${school.id}`, operationId = operationFor(key);
    try {
      const result = client
        ? await request(`platform/clients/${client.id}/attach-school`, platformClientDetailResult, { csrf: session.csrfToken, body: { operationId, version: client.version, schoolId: school.id } })
        : await request('platform/clients', platformClientDetailResult, { csrf: session.csrfToken, body: { operationId, schoolId: school.id } });
      settle(key); selectedId.current = result.data.id; setSelected(result.data); stopAttach();
    } catch (reason) { settle(key, reason); throw reason; }
    await reload();
  });

  return { page, search, preparation, selected, pending, codeTarget, issued, copied, copyFailed, uncertain, attach, unattached,
    reset, snapshot, apply, searchClients, moreClients, openClient, closeClient, saveFiche,
    startCode, stopCode, issueCode, resumeCode, closeCode, revokeCode, copy, startAttach, stopAttach, searchUnattached, attachSchool };
}
export type PlatformClientsState = ReturnType<typeof usePlatformClients>;
