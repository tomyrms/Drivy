import { z } from 'zod';

export type WebConfig = {
  origin: string; apiBaseURL: string; issuer: string; clientId: string;
  clientSecret: string; development: boolean; host: string; port: number;
};

export function secureURL(value: string, development: boolean): URL {
  const url = new URL(value);
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !(development && loopback && url.protocol === 'http:')) ||
      url.username || url.password || url.search || url.hash) throw new Error('URL web non autorisée.');
  return url;
}

export function readConfig(env: NodeJS.ProcessEnv): WebConfig {
  const parsed = z.object({
    WEB_ORIGIN: z.url(), API_BASE_URL: z.url(), OIDC_ISSUER: z.url(),
    OIDC_WEB_CLIENT_ID: z.string().min(1), OIDC_WEB_CLIENT_SECRET: z.string().min(24),
    WEB_DEVELOPMENT: z.enum(['true','false']).default('false'),
    WEB_HOST: z.string().default('127.0.0.1'), WEB_PORT: z.coerce.number().int().min(1).max(65535).default(3002)
  }).parse(env);
  const development = parsed.WEB_DEVELOPMENT === 'true';
  if (development && env.NODE_ENV === 'production') throw new Error('Développement interdit en production.');
  const origin = secureURL(parsed.WEB_ORIGIN, development);
  if (origin.pathname !== '/') throw new Error('WEB_ORIGIN doit être une origine.');
  if (development && [parsed.WEB_ORIGIN,parsed.API_BASE_URL,parsed.OIDC_ISSUER].some(value =>
    !['127.0.0.1','localhost','[::1]'].includes(new URL(value).hostname))) throw new Error('Développement limité au loopback.');
  return { origin: origin.origin, apiBaseURL: secureURL(parsed.API_BASE_URL, development).href.replace(/\/$/, ''),
    issuer: secureURL(parsed.OIDC_ISSUER, development).href.replace(/\/$/, ''),
    clientId: parsed.OIDC_WEB_CLIENT_ID, clientSecret: parsed.OIDC_WEB_CLIENT_SECRET, development,
    host: parsed.WEB_HOST, port: parsed.WEB_PORT };
}
