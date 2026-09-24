import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_URL: z.url(),
  OIDC_ISSUER: z.url(),
  OIDC_AUDIENCE: z.string().min(1),
  OIDC_JWKS_URL: z.url(),
  CURSOR_SECRET: z.string().min(32),
  PORT: z.coerce.number().int().min(1).max(65535).default(3001),
  HOST: z.string().default('127.0.0.1')
});
export type Config = z.infer<typeof schema>;
export function readConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    throw new Error(`Configuration API manquante/invalide : ${parsed.error.issues.map(issue => issue.path.join('.')).join(', ')}`);
  }
  const config = parsed.data;
  for (const name of ['OIDC_ISSUER', 'OIDC_JWKS_URL'] as const) {
    const url = new URL(config[name]);
    if (url.username || url.password || (url.protocol !== 'https:' &&
      !(config.NODE_ENV !== 'production' && url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) {
      throw new Error(`${name} doit utiliser HTTPS (HTTP local uniquement en développement).`);
    }
  }
  return config;
}
