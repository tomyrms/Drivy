import { z } from 'zod';
import { ApiError } from './errors.js';

/**
 * Création d'un compte chez le fournisseur d'identité (Keycloak), par un client de service limité à la gestion des utilisateurs.
 * L'inscription libre du realm est fermée : seul ce chemin, ouvert par un code ou un lien valable, crée un compte.
 * Le mot de passe ne fait que traverser l'API : il n'est ni stocké, ni journalisé, ni renvoyé.
 */
export type NewAccount = { email: string; firstName: string; lastName: string; password: string; emailVerified?: boolean };
export type AccountProvisioner = (account: NewAccount) => Promise<void>;

export type AccountProvisioningConfig = { baseURL: string; realm: string; clientId: string; clientSecret: string };

export function readAccountProvisioningConfig(env: NodeJS.ProcessEnv = process.env): AccountProvisioningConfig | undefined {
  const values = { baseURL: env.ACCOUNT_ADMIN_URL, realm: env.ACCOUNT_ADMIN_REALM, clientId: env.ACCOUNT_ADMIN_CLIENT_ID, clientSecret: env.ACCOUNT_ADMIN_CLIENT_SECRET };
  if (Object.values(values).every(value => value === undefined || value === '')) return undefined;
  const parsed = z.object({ baseURL: z.url(), realm: z.string().regex(/^[A-Za-z0-9_-]{1,100}$/), clientId: z.string().min(1).max(200),
    clientSecret: z.string().min(16).max(500) }).safeParse(values);
  if (!parsed.success) throw new Error(`Configuration de création de comptes invalide : ${parsed.error.issues.map(issue => issue.path.join('.')).join(', ')}`);
  const url = new URL(parsed.data.baseURL);
  // Le client de service parle au fournisseur sur la machine ou en HTTPS : jamais un secret en clair sur le réseau.
  if (url.username || url.password || (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)))) {
    throw new Error('ACCOUNT_ADMIN_URL doit utiliser HTTPS (HTTP local uniquement).');
  }
  return { ...parsed.data, baseURL: parsed.data.baseURL.replace(/\/+$/, '') };
}

const unavailable = () => new ApiError(503, 'ACCOUNT_CREATION_UNAVAILABLE', 'La création de compte est momentanément indisponible. Réessayez plus tard.');

export function createKeycloakProvisioner(config: AccountProvisioningConfig, fetcher: typeof fetch = fetch): AccountProvisioner {
  const signal = () => AbortSignal.timeout(10_000);
  async function serviceToken(): Promise<string> {
    let response: Response;
    try {
      response = await fetcher(`${config.baseURL}/realms/${config.realm}/protocol/openid-connect/token`, { method: 'POST', signal: signal(),
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'client_credentials', client_id: config.clientId, client_secret: config.clientSecret }) });
    } catch { throw unavailable(); }
    if (!response.ok) throw unavailable();
    const token = z.object({ access_token: z.string().min(1) }).safeParse(await response.json().catch(() => null));
    if (!token.success) throw unavailable();
    return token.data.access_token;
  }
  return async account => {
    const token = await serviceToken();
    let response: Response;
    try {
      response = await fetcher(`${config.baseURL}/admin/realms/${config.realm}/users`, { method: 'POST', signal: signal(),
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ username: account.email, email: account.email, firstName: account.firstName, lastName: account.lastName,
          enabled: true, emailVerified: account.emailVerified === true, credentials: [{ type: 'password', value: account.password, temporary: false }] }) });
    } catch { throw unavailable(); }
    if (response.status === 201) return;
    if (response.status === 409) throw new ApiError(409, 'ACCOUNT_EXISTS', 'Un compte existe déjà avec cette adresse. Connectez-vous, puis saisissez votre code.');
    if (response.status === 400) {
      // Refus de la politique de mot de passe du realm : le détail du fournisseur n'est pas relayé tel quel.
      const body = z.object({ error: z.string().optional(), errorMessage: z.string().optional() }).safeParse(await response.json().catch(() => null));
      const reason = body.success ? `${body.data.error ?? ''} ${body.data.errorMessage ?? ''}` : '';
      if (/password/i.test(reason)) throw new ApiError(400, 'ACCOUNT_PASSWORD_REJECTED', 'Ce mot de passe n’est pas accepté. Choisissez-en un plus long ou moins courant.');
      throw new ApiError(400, 'INVALID_REQUEST', 'Requête invalide.');
    }
    throw unavailable();
  };
}
