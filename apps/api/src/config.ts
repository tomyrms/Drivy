import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_URL: z.url(),
  OIDC_ISSUER: z.url(),
  OIDC_AUDIENCE: z.string().min(1),
  OIDC_JWKS_URL: z.url(),
  CURSOR_SECRET: z.string().min(32),
  MESSAGING_MODE: z.enum(['disabled', 'qualification']).default('disabled'),
  MESSAGING_QUALIFICATION_SCHOOL_IDS: z.string().default('').transform(value => value.trim() === '' ? [] : value.split(',').map(id => id.trim().toLowerCase()))
    .pipe(z.array(z.uuid()).max(100)).transform(ids => [...new Set(ids)]),
  // Facultatif : clé propre aux codes d'invitation. Sans elle, la clé se dérive de CURSOR_SECRET (HKDF, étiquette dédiée).
  INVITATION_CODE_SECRET: z.string().min(32).optional(),
  // Facultatif : adresses du proxy public (liste séparée par des virgules) dont l'en-tête X-Forwarded-For est cru.
  TRUST_PROXY: z.string().regex(/^[0-9a-fA-F.:/,]{1,500}$/).optional(),
  REAUTH_MAX_AGE_SECONDS:z.coerce.number().int().min(30).max(900).default(300),
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
  if (config.MESSAGING_MODE === 'qualification' && config.MESSAGING_QUALIFICATION_SCHOOL_IDS.length === 0) {
    throw new Error('MESSAGING_QUALIFICATION_SCHOOL_IDS doit contenir une école autorisée en mode qualification.');
  }
  for (const name of ['OIDC_ISSUER', 'OIDC_JWKS_URL'] as const) {
    const url = new URL(config[name]);
    if (url.username || url.password || (url.protocol !== 'https:' &&
      !(config.NODE_ENV !== 'production' && url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) {
      throw new Error(`${name} doit utiliser HTTPS (HTTP local uniquement en développement).`);
    }
  }
  return config;
}
