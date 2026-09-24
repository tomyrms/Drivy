import { execFileSync, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, chmod } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

export const root = fileURLToPath(new URL('../../', import.meta.url));
export const stateDirectory = new URL('../../infra/dev/.state/', import.meta.url);
export const issuer = 'http://127.0.0.1:8081/realms/drivy-dev';
export const keycloakOrigin = 'http://127.0.0.1:8081';
export const apiOrigin = 'http://127.0.0.1:3001';
export const clientId = 'drivy-apple';
export const audience = 'drivy-api';
export const redirectUri = 'ch.drivy.qualification:/oauth/callback';
export const databaseUrl = 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_dev';
export const runtimeSchema = z.object({
  adminUsername: z.literal('drivy-local-bootstrap'), adminPassword: z.string().min(32),
  cursorSecret: z.string().min(32)
}).strict();
export type Runtime = z.infer<typeof runtimeSchema>;
export const accountSchema = z.object({
  username: z.string(), password: z.string().min(32), subject: z.uuid(), personId: z.uuid()
}).strict();
export type Account = z.infer<typeof accountSchema>;

export async function protectStateDirectory(): Promise<void> {
  const path = fileURLToPath(stateDirectory);
  await mkdir(path,{ recursive:true,mode:0o700 });
  if (process.platform === 'win32') {
    const identity = execFileSync('whoami',['/user','/fo','csv','/nh'],{ encoding:'utf8',windowsHide:true });
    const sid = identity.match(/S-1-[0-9-]+/)?.[0];
    if (!sid) throw new Error('Impossible de déterminer le compte local pour protéger les secrets.');
    execFileSync('icacls',[path,'/inheritance:r','/grant:r',`*${sid}:(OI)(CI)F`,'/grant:r','*S-1-5-18:(OI)(CI)F'],{ stdio:'ignore',windowsHide:true });
  } else { await chmod(path,0o700); }
}
export async function secretFile(name: string, data: unknown): Promise<void> {
  if (!/^[a-z-]+\.json$/.test(name)) throw new Error('Nom de fichier local invalide.');
  await writeFile(new URL(name,stateDirectory),JSON.stringify(data,null,2)+'\n',{ mode:0o600 });
}
export async function loadRuntime(): Promise<Runtime> {
  return runtimeSchema.parse(JSON.parse(await readFile(new URL('runtime.json',stateDirectory),'utf8')));
}
export async function loadAccounts(): Promise<Account[]> {
  return z.array(accountSchema).parse(JSON.parse(await readFile(new URL('accounts.json',stateDirectory),'utf8')));
}
export async function initializeRuntime(): Promise<Runtime> {
  await protectStateDirectory();
  try { return await loadRuntime(); }
  catch (error) {
    if (!(error instanceof Error) || !('code' in error) || error.code !== 'ENOENT') throw new Error('Configuration locale existante illisible ; aucune clé de remplacement créée.');
    const runtime: Runtime = { adminUsername:'drivy-local-bootstrap',adminPassword:randomBytes(32).toString('base64url'),cursorSecret:randomBytes(32).toString('base64url') };
    await secretFile('runtime.json',runtime);
    return runtime;
  }
}
export async function command(executable: string,args: string[]): Promise<void> {
  const child = spawn(executable,args,{ cwd:root,stdio:'inherit',windowsHide:true });
  await new Promise<void>((resolve,reject)=>{
    child.once('error',()=>reject(new Error('Commande locale indisponible.')));
    child.once('exit',code=>code===0 ? resolve() : reject(new Error(`Commande locale échouée (${String(code)}).`)));
  });
}
export async function localFetch(url: string | URL, init: RequestInit = {}): Promise<Response> {
  const target = new URL(url);
  if (![keycloakOrigin,apiOrigin].includes(target.origin)) throw new Error('Requête refusée hors des services loopback de cet environnement.');
  return fetch(target,{ ...init,redirect:'manual',signal:AbortSignal.timeout(15_000) });
}
export async function waitForIdentity(): Promise<void> {
  for (let attempt=0;attempt<120;attempt++) {
    try { if ((await localFetch(`${keycloakOrigin}/realms/master/.well-known/openid-configuration`)).ok) return; } catch { /* Démarrage en cours. */ }
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  throw new Error('Le fournisseur local ne répond pas après le délai de démarrage.');
}
export function apiEnvironment(runtime: Runtime): NodeJS.ProcessEnv {
  return { ...process.env,NODE_ENV:'development',DATABASE_URL:databaseUrl,
    OIDC_ISSUER:issuer,OIDC_AUDIENCE:audience,OIDC_JWKS_URL:`${issuer}/protocol/openid-connect/certs`,
    CURSOR_SECRET:runtime.cursorSecret,HOST:'127.0.0.1',PORT:'3001' };
}
