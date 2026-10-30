import { describe, expect, it } from 'vitest';
import { createEntryPreviewTransport } from './entry-transport';

const origin = 'https://preview.example.test';
const command = (body: object = {}, version = 1): RequestInit => ({ method: 'POST', headers: { 'X-CSRF-Token': `synthetic-entry-${version}` }, body: JSON.stringify(body) });

describe('aperçu fictif des entrées', () => {
  it('refuse toute route non prévue, même sur un autre hôte', async () => {
    const fetch = createEntryPreviewTransport('login', origin);
    expect((await fetch('https://real.example.test/app/bff/session')).status).toBe(403);
    expect((await fetch(`${origin}/app/bff/unknown`)).status).toBe(404);
    expect((await fetch(`${origin}/app/bff/password-login`, { method: 'POST' })).status).toBe(403);
  });

  it('un code valide nomme le parcours avant la connexion et une écriture sans CSRF courant est refusée', async () => {
    const fetch = createEntryPreviewTransport('login', origin);
    expect((await fetch(`${origin}/app/bff/access-code`, command({ code: 'incorrect' }))).status).toBe(404);
    expect(await (await fetch(`${origin}/app/bff/access-code`, command({ code: 'DEMO-DEMO' }))).json()).toMatchObject({ kind: 'LEARNER_INVITATION' });
    expect((await fetch(`${origin}/app/bff/password-login`, command({ email: 'alex@example.test', password: 'synthetic-password' }))).status).toBe(200);
    expect(await (await fetch(`${origin}/app/bff/session`)).json()).toMatchObject({ authenticated: true, invitationPending: true, csrfToken: 'synthetic-entry-2' });
    expect((await fetch(`${origin}/app/bff/invitation/accept`, command())).status).toBe(403);
  });

  it('la réponse perdue conserve le reçu et la même confirmation jusqu’à la reprise', async () => {
    const fetch = createEntryPreviewTransport('lost-reply', origin);
    const preview = await (await fetch(`${origin}/app/bff/invitation/preview`, command())).json();
    const body = { invitationId: preview.data.invitationId, confirmation: preview.confirmation };
    await expect(fetch(`${origin}/app/bff/invitation/accept`, command(body))).rejects.toThrow('Synthetic response lost');
    expect(await (await fetch(`${origin}/app/bff/session`)).json()).toMatchObject({ invitationPending: true });
    expect((await fetch(`${origin}/app/bff/invitation/clear`, command())).status).toBe(409);
    expect(await (await fetch(`${origin}/app/bff/invitation/preview`, command())).json()).toMatchObject({ confirmation: preview.confirmation, uncertain: true });
    expect((await fetch(`${origin}/app/bff/invitation/accept`, command(body))).status).toBe(201);
    expect(await (await fetch(`${origin}/app/bff/session`)).json()).toMatchObject({ invitationPending: false });
    expect((await (await fetch(`${origin}/app/bff/me`)).json()).data.memberships).toHaveLength(1);
  });

  it('une invitation expirée ne fournit ni aperçu ni acceptation implicite', async () => {
    const fetch = createEntryPreviewTransport('expired', origin);
    expect((await fetch(`${origin}/app/bff/invitation/preview`, command())).status).toBe(410);
    expect((await (await fetch(`${origin}/app/bff/me`)).json()).data.memberships).toHaveLength(0);
  });
});
