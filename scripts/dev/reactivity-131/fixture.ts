// Compiled in production mode; only composition, transport faults and observation hooks live here.
export const fixtureSource = `
import React from 'react';
import { createRoot } from 'react-dom/client';
import { z } from '/apps/web/node_modules/zod/index.js';
import { ConsoleContext } from '/apps/web/client/console/context';
import { AccessPilot } from '/apps/web/client/portal/access/access-page';
import { PortalPendingRequests } from '/apps/web/client/portal/runtime/pending-requests';
import { PortalPreferencesPage } from '/apps/web/client/portal/account/preferences-page';
import { commandStore } from '/apps/web/client/command-store';
import { installPreviewTransport, setPreviewScenario } from '/apps/web/client/portal/preview/transport';
import { ids, previewMe, previewMembership, previewSchool } from '/apps/web/client/portal/preview/fixtures';
import '/apps/web/client/portal/portal.css';
z.config({ jitless: true });
const params = new URLSearchParams(location.search), delay = Number(params.get('delay') || 0), fault = params.get('fault') || '';
const q = window.q = { events: [], writes: 0, reads: 0, confirmed: false, metadata: null, changed: false };
const event = name => q.events.push({ name, at: performance.now() });
const originalSetItem = Storage.prototype.setItem; Storage.prototype.setItem = function(key, value) { if(key !== 'drivy-gestion-demandes-v1') return originalSetItem.call(this,key,value); if(fault === 'storage') { event('metadata-refused'); throw new Error('Synthetic metadata refusal'); } const result=originalSetItem.call(this,key,value); event('metadata-saved'); return result; };
installPreviewTransport();
if (fault === 'lost' || fault === 'refused') setPreviewScenario(fault === 'lost' ? 'lost-reply' : 'refused');
const transport = window.fetch;
window.fetch = async (input, init) => {
  const method = init?.method || 'GET', url = String(input), write = method !== 'GET';
  if(write) { q.writes++; event('write-start'); await new Promise(done => setTimeout(done, delay)); }
  else { q.reads++; if(q.writes) event('reread-start'); }
  if(fault === 'reread' && q.writes && !write && url.includes('/members')) return new Response(JSON.stringify({code:'API_UNAVAILABLE'}), {status:503});
  try { const result = await transport(input, init); if(write) event('write-response'); else if(q.writes) event('reread-response'); return result; }
  catch(error) { event('response-lost'); throw error; }
};
commandStore.scopeToPerson(ids.person); commandStore.scopeToAccess(ids.school, ids.admin, 1);
commandStore.subscribe(() => { const s = commandStore.getSnapshot(); q.metadata = s.metadata; q.phases = [...s.entries.values()].map(e => ({ phase:e.phase, bodyInMemory:!!e.command })); q.confirmed = !!s.confirmed; event(s.confirmed ? 'store-confirmed' : 'store-update'); });
q.switchAccount = () => { commandStore.scopeToPerson('31100000-0000-4000-8000-000000000099'); q.changed = true; event('account-changed'); };
const context = { schoolId:ids.school, school:previewSchool, me:previewMe, membership:previewMembership, canConfigureCatalog:true, csrf:()=> 'synthetic', refreshCsrf:async()=> 'synthetic', reloadSchool:async()=>{}, navigate:()=>{}, routeQuery:{selection:ids.instructor}, login:()=>{}, confirmIdentity:async()=>true };
createRoot(document.getElementById('root')).render(params.get('surface') === 'preferences' ? <PortalPreferencesPage /> : <ConsoleContext.Provider value={context}><main className="portal-app p-6"><PortalPendingRequests/><AccessPilot initialEdit/></main></ConsoleContext.Provider>);
`;
