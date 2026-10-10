#!/usr/bin/env node
/** CT114, root uniquement. Prépare les clés dédiées ; aucun profil matériel qualifié ni redémarrage. */
import { createHash, generateKeyPairSync, randomBytes, randomUUID, createPublicKey } from 'node:crypto';
import { constants } from 'node:fs';
import { open, rename, unlink } from 'node:fs/promises';
import { parseEnv } from 'node:util';

const directory = '/etc/drivy-refonte';
const path = `${directory}/api.env`;
const issuer = 'https://drivy.shulker.ch/refonte';
const required = ['CAPTURE_ENCRYPTION_KEY_HEX', 'CAPTURE_ENCRYPTION_KEY_ID', 'CAPTURE_SIGNING_PRIVATE_JWK', 'CAPTURE_AUTHORITY_ISSUER'];
function demand(value) { if (!value) throw new Error('private_configuration'); }
async function readPrivate(target) {
  const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat();
    demand(info.isFile() && info.uid === 0 && (info.mode & 0o077) === 0 && info.size < 100_000);
    return await handle.readFile('utf8');
  } finally { await handle.close(); }
}
async function writeExclusive(target, text) {
  const handle = await open(target, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try { await handle.writeFile(text); await handle.sync(); } finally { await handle.close(); }
}
function validateExisting(environment) {
  demand(required.every(name => environment[name]) && environment.CAPTURE_AUTHORITY_ISSUER === issuer);
  demand(/^[a-fA-F0-9]{64}$/.test(environment.CAPTURE_ENCRYPTION_KEY_HEX));
  demand(/^[a-zA-Z0-9_-]{1,80}$/.test(environment.CAPTURE_ENCRYPTION_KEY_ID));
  const jwk = JSON.parse(environment.CAPTURE_SIGNING_PRIVATE_JWK);
  demand(jwk.kty === 'OKP' && jwk.crv === 'Ed25519' && typeof jwk.d === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(jwk.kid));
  const publicKey = createPublicKey({ key: jwk, format: 'jwk' }).export({ format: 'jwk' });
  demand(publicKey.x === jwk.x && publicKey.crv === 'Ed25519');
  demand(Array.isArray(JSON.parse(environment.CAPTURE_QUALIFICATION_PROFILES_JSON ?? '[]')));
  return jwk.kid;
}
async function main() {
  demand(process.getuid?.() === 0 && process.argv.length === 3 && process.argv[2] === '--apply');
  const dir = await open(directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  let locked = false;
  const lock = `${directory}/.capture-provision.lock`;
  try {
    const info = await dir.stat();
    demand(info.uid === 0 && (info.mode & 0o022) === 0);
    await writeExclusive(lock, `${process.pid}\n`); locked = true;
    const previous = await readPrivate(path);
    const environment = parseEnv(previous);
    if (required.some(name => environment[name])) {
      const keyId = validateExisting(environment);
      console.log(JSON.stringify({ status: 'EXISTING_KEYS_PRESERVED', signingKeyId: keyId, serviceRestarted: false }));
      return;
    }
    // L’ajout ne doit pas écraser une configuration partielle ou un profil qualifié existant.
    demand(!Object.keys(environment).some(name => name.startsWith('CAPTURE_')));
    const keyId = `capture-${randomUUID()}`;
    const { privateKey } = generateKeyPairSync('ed25519');
    const signingKey = { ...privateKey.export({ format: 'jwk' }), kid: keyId };
    const additions = {
      CAPTURE_ENCRYPTION_KEY_HEX: randomBytes(32).toString('hex'),
      CAPTURE_ENCRYPTION_KEY_ID: keyId,
      CAPTURE_SIGNING_PRIVATE_JWK: JSON.stringify(signingKey),
      CAPTURE_AUTHORITY_ISSUER: issuer,
      CAPTURE_QUALIFICATION_PROFILES_JSON: '[]',
      CAPTURE_UPLOAD_HOURS: '72',
    };
    const next = `${previous.replace(/\n?$/, '\n')}\n${Object.entries(additions).map(([name, value]) => `${name}=${value}`).join('\n')}\n`;
    validateExisting(parseEnv(next));
    const backup = `${directory}/api.before-capture-${randomUUID()}.env`;
    await writeExclusive(backup, previous);
    const temporary = `${directory}/.api-capture-${randomUUID()}.env`;
    await writeExclusive(temporary, next);
    // Une modification concurrente de la configuration fait échouer le remplacement.
    demand(createHash('sha256').update(await readPrivate(path)).digest('hex') === createHash('sha256').update(previous).digest('hex'));
    await rename(temporary, path);
    await dir.sync();
    console.log(JSON.stringify({ status: 'KEYS_PREPARED', signingKeyId: keyId, qualifiedProfiles: 0, serviceRestarted: false }));
  } finally {
    if (locked) await unlink(lock);
    await dir.close();
  }
}
try { await main(); }
catch { console.error('Préparation capture interrompue ; vérifier les fichiers privés sur CT114. Aucun secret affiché.'); process.exitCode = 1; }
