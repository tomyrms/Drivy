import { describe, expect, it, vi } from 'vitest';
import { buildWebApp } from '../server/app.js';
import type { IdentityProvider } from '../server/oidc.js';
import { RateLimiter } from '../server/rate-limit.js';

const config = { origin:'https://drivy.example', apiBaseURL:'https://drivy.example', issuer:'https://identity.example/realms/drivy',
  clientId:'drivy-web', clientSecret:'synthetic-account-recovery-000000', development:false,host:'127.0.0.1',port:3002 };
describe('entrée récupération sans connexion applicative', () => {
  it('refuse les entrées anonymes excessives et reprend après la fenêtre', async () => {
    let now = 0;
    const app = await buildWebApp({config:{...config,accountRecoveryEnabled:true},identity:{} as IdentityProvider,
      entryLimiter:new RateLimiter(2,60_000,()=>now)});
    try {
      const csrf = (await app.inject('/app/bff/session')).json().csrfToken;
      const start = () => app.inject({method:'POST',url:'/app/bff/account-recovery/start',headers:{origin:config.origin,'x-csrf-token':csrf},payload:{}});
      expect((await start()).statusCode).toBe(200); expect((await start()).statusCode).toBe(200);
      expect((await start()).statusCode).toBe(429);
      now = 60_001;
      expect((await start()).statusCode).toBe(200);
    } finally { await app.close(); }
  });
  it.each([false,true])('applique activation explicite %s et ne crée pas de session', async enabled => {
    const begin = vi.fn(); const app = await buildWebApp({config:{...config,accountRecoveryEnabled:enabled},identity:{begin} as unknown as IdentityProvider});
    try {
      const options = await app.inject('/app/bff/account-recovery/options');
      expect(options.json().data).toEqual({available:enabled,recoveryUrl:enabled?'https://drivy.example/app/recover':null});
      const csrf = (await app.inject('/app/bff/session')).json().csrfToken;
      const response = await app.inject({method:'POST',url:'/app/bff/account-recovery/start',headers:{origin:config.origin,'x-csrf-token':csrf},payload:{}});
      expect(response.statusCode).toBe(enabled ? 200 : 503);
      if (enabled) {
        const url = new URL(response.json().url);
        expect(url.origin).toBe('https://identity.example'); expect(url.pathname).toBe('/realms/drivy/login-actions/reset-credentials');
        expect([...url.searchParams]).toEqual([['client_id','drivy-web'],['ui_locales','fr']]);
      }
      expect(response.headers['set-cookie']).toBeUndefined(); expect(begin).not.toHaveBeenCalled();
      expect((await app.inject({method:'POST',url:'/app/bff/account-recovery/start',headers:{origin:config.origin,'x-csrf-token':csrf},payload:{email:'synthetic@example.invalid'}})).statusCode).toBe(400);
      expect((await app.inject({method:'POST',url:'/app/bff/account-recovery/start',payload:{}})).statusCode).toBe(403);
    } finally { await app.close(); }
  });
});
