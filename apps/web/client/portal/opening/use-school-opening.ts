import { useEffect, useRef, useState } from 'react';
import { z } from 'zod';
import { endSession, okSchema, request, RequestFailure, sessionSchema, type Session } from '../../protocol';
import {
  createdOpeningLink, openingFailure, openingFieldErrors, openingLinks, openingLinkSchema, openingPreview, openingReceipt, openingState,
  schoolOpeningDestination, type OpeningFields, type OpeningFieldErrors, type OpeningLink, type OpeningReceipt,
} from '../../school-opening-model';

type OperatorLink = z.infer<typeof openingLinkSchema>;
const emptyFields = (): OpeningFields => ({ schoolName: '', displayName: '', contactEmail: '', contactPhone: null, timeZone: 'Europe/Zurich', instructs: false });

/** Opening remains a BFF-held intention. Neither the link, the form nor a receipt enters browser storage. */
export function useSchoolOpening(link: OpeningLink, operator: boolean, destination = schoolOpeningDestination) {
  const [session, setSession] = useState<Session | null>(null);
  const [loaded, setLoaded] = useState(false), [busy, setBusy] = useState(false), [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null), [uncertain, setUncertain] = useState(false);
  const [result, setResult] = useState<OpeningReceipt | null>(null);
  const [fields, setFields] = useState<OpeningFields>(emptyFields), [fieldErrors, setFieldErrors] = useState<OpeningFieldErrors>({});
  const [invalidField, setInvalidField] = useState<keyof OpeningFields | null>(null);
  const [items, setItems] = useState<OperatorLink[]>([]), [generated, setGenerated] = useState<z.infer<typeof createdOpeningLink> | null>(null);
  const [revoking, setRevoking] = useState<OperatorLink | null>(null), [copied, setCopied] = useState<'code' | 'link' | null>(null);
  const operation = useRef<string | null>(null), revocation = useRef<{ id: string; operationId: string } | null>(null);
  const running = useRef(false), started = useRef(false), linkStored = useRef(false);

  async function list() {
    const response = await request('operator/school-opening-links', openingLinks);
    setItems(response.data.items); operation.current = response.pendingOperationId ?? null; setReady(true);
  }
  async function inspect(current: Session) {
    const state = await request('opening', openingState);
    setUncertain(state.uncertain);
    if (state.draft) setFields(state.draft);
    if (state.result) { setResult(state.result); return; }
    if (state.uncertain) { setReady(true); return; }
    const response = await request('opening/preview', openingPreview, { csrf: current.csrfToken, body: {} });
    if (response.data.status === 'USED') setResult(response.data.school); else setReady(true);
  }
  async function boot() {
    setLoaded(false); setReady(false); setError(null); setResult(null); setCopied(null);
    // Purge the previous account before any asynchronous session read.
    setSession(null); setItems([]); setGenerated(null); setFields(emptyFields()); setFieldErrors({});
    operation.current = null; revocation.current = null; setRevoking(null);
    try {
      let current = await request('session', sessionSchema); setSession(current);
      if (link.error) throw new RequestFailure('OPENING_LINK_INVALID');
      if (!operator && link.token && !linkStored.current) {
        await request('opening', okSchema, { csrf: current.csrfToken, body: { token: link.token } });
        linkStored.current = true;
        current = await request('session', sessionSchema); setSession(current);
      }
      if (current.authenticated) {
        setFields(previous => ({ ...previous, displayName: current.user?.displayName ?? '', contactEmail: current.user?.email ?? '' }));
        if (operator) await list(); else await inspect(current);
      }
    } catch (reason) { setError(openingFailure(reason)); } finally { setLoaded(true); }
  }
  useEffect(() => { if (started.current) return; started.current = true; void boot(); }, []);
  useEffect(() => { if (result && !operator) window.location.replace(destination(result)); }, [result, operator, destination]);

  async function perform(action: () => Promise<void>) {
    if (running.current) return;
    running.current = true; setBusy(true); setError(null);
    try { await action(); } catch (reason) { setError(openingFailure(reason)); }
    finally { running.current = false; setBusy(false); }
  }
  const changeAccount = () => perform(async () => {
    await endSession(); linkStored.current = false; setUncertain(false); await boot();
  });
  const createSchool = () => perform(async () => {
    if (!session || !ready) return;
    if (!uncertain) {
      const errors = openingFieldErrors(fields); setFieldErrors(errors);
      const first = (['schoolName', 'contactEmail', 'contactPhone', 'displayName', 'timeZone'] as const).find(field => errors[field]);
      if (first) { setInvalidField(first); return; }
    }
    // A lost response followed by a failed read must never reopen editable fields.
    setUncertain(true);
    try {
      const response = await request('opening/create', z.object({ data: openingReceipt }), { csrf: session.csrfToken, body: fields });
      setResult(response.data); setUncertain(false);
    } catch (reason) {
      setError(openingFailure(reason));
      try {
        const state = await request('opening', openingState); setUncertain(state.uncertain);
        if (state.draft) setFields(state.draft);
        if (state.result) { setResult(state.result); setError(null); }
      } catch { /* Keep the same intention frozen until a verified state can be read. */ }
    }
  });
  const verify = () => perform(async () => {
    try {
      const response = await request('opening/result', z.object({ data: openingReceipt }));
      setResult(response.data); setUncertain(false);
    } catch (reason) {
      setError(reason instanceof RequestFailure && reason.status === 404
        ? 'Le résultat n’est pas encore confirmé. Vous pouvez renvoyer la même demande.' : openingFailure(reason));
    }
  });
  const createLink = () => perform(async () => {
    if (!session || !ready) return;
    setCopied(null);
    if (generated) {
      await request('operator/school-opening-links/clear', okSchema, { csrf: session.csrfToken, body: {} });
      operation.current = null; setGenerated(null);
    }
    operation.current ??= crypto.randomUUID();
    const response = await request('operator/school-opening-links', createdOpeningLink, { csrf: session.csrfToken, body: { operationId: operation.current } });
    setGenerated(response); await list();
  });
  const revoke = () => perform(async () => {
    if (!session || !revoking || !ready) return;
    if (revocation.current?.id !== revoking.id) revocation.current = { id: revoking.id, operationId: crypto.randomUUID() };
    const response = await request(`operator/school-opening-links/${revoking.id}/revoke`, z.object({ data: openingLinkSchema }), {
      csrf: session.csrfToken, body: { operationId: revocation.current.operationId },
    });
    setItems(previous => previous.map(item => item.id === response.data.id ? response.data : item));
    if (generated?.data.id === response.data.id) { setGenerated({ ...generated, data: response.data }); setCopied(null); }
    setRevoking(null); revocation.current = null;
    await list();
  });
  async function copy(kind: 'code' | 'link') {
    if (!generated) return;
    setCopied(null);
    try { await navigator.clipboard.writeText(generated[kind]); setCopied(kind); }
    catch { setError('La copie a échoué. Sélectionnez et copiez le texte affiché.'); }
  }
  function update<K extends keyof OpeningFields>(key: K, value: OpeningFields[K]) {
    if (busy || uncertain) return;
    setFields(previous => ({ ...previous, [key]: value })); setFieldErrors(previous => ({ ...previous, [key]: undefined }));
  }
  return { session, loaded, busy, ready, error, uncertain, result, fields, fieldErrors, invalidField, setInvalidField,
    items, generated, copied, revoking, setRevoking, recoverLink: !!operation.current && !generated,
    boot, changeAccount, createSchool, verify, createLink, revoke, copy, update };
}
export type SchoolOpeningState = ReturnType<typeof useSchoolOpening>;
