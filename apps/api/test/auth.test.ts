import { beforeAll, describe, expect, it } from 'vitest';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { createTokenVerifier, type TokenVerifier } from '../src/auth.js';
import { readConfig } from '../src/config.js';

const config = { OIDC_ISSUER: 'https://identity.example.invalid', OIDC_AUDIENCE: 'drivy-api', OIDC_JWKS_URL: 'https://identity.example.invalid/jwks' };
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let verify: TokenVerifier;
beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  const publicKey = await exportJWK(keys.publicKey);
  verify = createTokenVerifier(config, createLocalJWKSet({ keys: [{ ...publicKey, kid: 'test-key', alg: 'RS256' }] }));
});
const token = async (options: { issuer?: string; audience?: string; expiration?: number; sub?: string } = {}) =>
  new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer(options.issuer ?? config.OIDC_ISSUER)
    .setAudience(options.audience ?? config.OIDC_AUDIENCE).setSubject(options.sub ?? 'test-person')
    .setIssuedAt().setExpirationTime(options.expiration ?? Math.floor(Date.now()/1000)+300).sign(keys.privateKey);
describe('Vérification OIDC cryptographique', () => {
  it('vérifie la signature, issuer et audience puis ne conserve que issuer/subject', async () => {
    await expect(verify(`Bearer ${await token()}`)).resolves.toEqual({ issuer: config.OIDC_ISSUER, subject: 'test-person' });
  });
  it.each(['issuer','audience'] as const)('refuse un %s différent', async claim => {
    await expect(verify(`Bearer ${await token({ [claim]: 'https://other.example.invalid' })}`)).rejects.toMatchObject({ status: 401 });
  });
  it('refuse un jeton expiré', async () => {
    await expect(verify(`Bearer ${await token({ expiration: 1 })}`)).rejects.toMatchObject({ status: 401 });
  });
  it('refuse une signature altérée', async () => {
    const valid = await token(); const chunks = valid.split('.'); chunks[1] = Buffer.from('{"sub":"admin"}').toString('base64url');
    await expect(verify(`Bearer ${chunks.join('.')}`)).rejects.toMatchObject({ status: 401 });
  });
  it.each([undefined,'','Bearer unsigned','Basic xyz'])('refuse une session absente ou invalide %s', async header => {
    await expect(verify(header)).rejects.toMatchObject({ status: 401 });
  });
});
describe('Configuration fermée', () => {
  it('ne démarre pas avec des paramètres OIDC manquants', () => { expect(() => readConfig({})).toThrow('Configuration API'); });
  it('refuse un fournisseur HTTP en production', () => {
    expect(() => readConfig({ ...config, NODE_ENV:'production', DATABASE_URL:'postgresql://localhost/drivy', CURSOR_SECRET:'x'.repeat(32), OIDC_ISSUER:'http://localhost:9000' })).toThrow('HTTPS');
  });
});
