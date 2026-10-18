import { randomUUID } from 'node:crypto';
import { expect, test } from 'vitest';
import { createKeycloakProvisioner, readAccountProvisioningConfig } from '../src/account-provisioning.js';
import { ApiError } from '../src/errors.js';

const config = { baseURL: 'http://127.0.0.1:8081/identity', realm: 'drivy', clientId: 'drivy-accounts', clientSecret: 'synthetic-client-secret-value' };
const chosenSecret = `Aa1!${randomUUID()}`;
const account = { email: 'camille@example.invalid', firstName: 'Camille', lastName: 'Recette', password: chosenSecret };

function fakeFetch(userStatus: number, userBody: unknown = {}) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (url.endsWith('/token')) return new Response(JSON.stringify({ access_token: 'service-token' }), { status: 200 });
    return new Response(userStatus === 201 ? null : JSON.stringify(userBody), { status: userStatus });
  }) as unknown as typeof fetch;
  return { calls, fetcher };
}

test('la configuration est facultative, complète et locale ou chiffrée', () => {
  expect(readAccountProvisioningConfig({})).toBeUndefined();
  expect(readAccountProvisioningConfig({ ACCOUNT_ADMIN_URL: config.baseURL + '/', ACCOUNT_ADMIN_REALM: 'drivy', ACCOUNT_ADMIN_CLIENT_ID: 'drivy-accounts',
    ACCOUNT_ADMIN_CLIENT_SECRET: config.clientSecret })).toEqual(config);
  expect(() => readAccountProvisioningConfig({ ACCOUNT_ADMIN_URL: config.baseURL })).toThrow();
  expect(() => readAccountProvisioningConfig({ ACCOUNT_ADMIN_URL: 'http://identity.example.invalid', ACCOUNT_ADMIN_REALM: 'drivy',
    ACCOUNT_ADMIN_CLIENT_ID: 'drivy-accounts', ACCOUNT_ADMIN_CLIENT_SECRET: config.clientSecret })).toThrow();
});

test('crée l’utilisateur par le client de service, adresse comme identifiant, sans vérification présumée', async () => {
  const { calls, fetcher } = fakeFetch(201);
  await createKeycloakProvisioner(config, fetcher)(account);
  expect(calls.map(call => call.url)).toEqual([`${config.baseURL}/realms/drivy/protocol/openid-connect/token`, `${config.baseURL}/admin/realms/drivy/users`]);
  expect(String(calls[0]!.init.body)).toContain('grant_type=client_credentials');
  expect(JSON.parse(String(calls[1]!.init.body))).toEqual({ username: account.email, email: account.email, firstName: 'Camille', lastName: 'Recette',
    enabled: true, emailVerified: false, credentials: [{ type: 'password', value: chosenSecret, temporary: false }] });
});

test('traduit les refus du fournisseur sans relayer son détail', async () => {
  const run = (status: number, body?: unknown) => createKeycloakProvisioner(config, fakeFetch(status, body).fetcher)(account);
  await expect(run(409)).rejects.toMatchObject({ status: 409, code: 'ACCOUNT_EXISTS' });
  await expect(run(400, { error: 'invalidPasswordMinLengthMessage' })).rejects.toMatchObject({ status: 400, code: 'ACCOUNT_PASSWORD_REJECTED' });
  await expect(run(500)).rejects.toMatchObject({ status: 503, code: 'ACCOUNT_CREATION_UNAVAILABLE' });
  const offline = (async () => { throw new TypeError('fetch failed'); }) as unknown as typeof fetch;
  await expect(createKeycloakProvisioner(config, offline)(account)).rejects.toBeInstanceOf(ApiError);
});
