import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

/**
 * Lancement du VRAI point d'entrée `src/course-worker.ts` dans un processus Node distinct (C37).
 * Aucune copie de `run()` : le module exécute son propre `try{await run()}catch{…}` au chargement.
 * L'environnement du sous-processus est construit explicitement, sans aucune variable `APNS_*` et sans copier
 * l'environnement du poste. `tsx` (dépendance du lock existant) ne sert que de transformateur TypeScript ; le
 * processus reste un processus Node ordinaire.
 */
export const posix = process.platform !== 'win32';
const apiRoot = fileURLToPath(new URL('../../../', import.meta.url));
const execFileAsync = promisify(execFile);

/** Variables d'hôte strictement nécessaires au lancement de Node, plus l'URL de la base de recette. */
export function workerEnvironment(databaseUrl: string | undefined): Record<string, string> {
  const environment: Record<string, string> = {};
  for (const name of ['PATH', 'SystemRoot', 'TEMP', 'TMP']) {
    const value = process.env[name];
    if (value) environment[name] = value;
  }
  if (databaseUrl) environment.COURSE_WORKER_DATABASE_URL = databaseUrl;
  const forbidden = Object.keys(environment).filter(name => name.startsWith('APNS_'));
  if (forbidden.length) throw new Error(`clés APNs interdites dans le processus de recette : ${forbidden.join(', ')}`);
  return environment;
}

export interface WorkerExit { code: number | null; signal: NodeJS.Signals | null }
export interface WorkerHandle {
  pid: number;
  stdout(): string;
  stderr(): string;
  alive(): boolean;
  exit(): Promise<WorkerExit>;
  stop(timeoutMs?: number): Promise<WorkerExit & { forced: boolean }>;
}

const sleep = (milliseconds: number) => new Promise<void>(resolve => setTimeout(resolve, milliseconds));

/** Démarre le service réel. stdin est fermé : le processus ne dépend d'aucun terminal. */
export function startWorker(environment: Record<string, string>): WorkerHandle {
  const child = spawn(process.execPath, ['--import', 'tsx', 'src/course-worker.ts'], {
    cwd: apiRoot, env: environment, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  let out = '', err = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk: string) => { out += chunk; });
  child.stderr.on('data', (chunk: string) => { err += chunk; });
  let settled: WorkerExit | undefined;
  const exited = new Promise<WorkerExit>(resolve => {
    child.once('exit', (code, signal) => { settled = { code, signal }; resolve(settled); });
  });
  const handle: WorkerHandle = {
    pid: child.pid ?? -1,
    stdout: () => out,
    stderr: () => err,
    alive: () => settled === undefined,
    exit: () => exited,
    async stop(timeoutMs = 15_000) {
      if (settled !== undefined) return { ...settled, forced: false };
      // Windows ne livre pas SIGTERM : ce kill est une terminaison forcée, jamais un arrêt gracieux.
      child.kill();
      const bounded = await Promise.race([exited.then(result => result), sleep(timeoutMs).then(() => undefined)]);
      if (bounded !== undefined) return { ...bounded, forced: false };
      if (process.platform === 'win32' && child.pid !== undefined) {
        await execFileAsync('taskkill', ['/PID', String(child.pid), '/T', '/F']).catch(() => undefined);
      } else child.kill('SIGKILL');
      const forcedExit = await Promise.race([exited, sleep(10_000).then(() => undefined)]);
      if (forcedExit === undefined) throw new Error('processus cours non terminé après terminaison forcée');
      return { ...forcedExit, forced: true };
    },
  };
  return handle;
}

/** Attend une observation réelle (base ou sortie), jamais un délai fixe présenté comme preuve. */
export async function waitFor<T>(label: string, timeoutMs: number, probe: () => Promise<T | null | undefined | false>): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      const value = await probe();
      if (value) return value;
    } catch (error) { lastError = error; }
    await sleep(100);
  }
  const suffix = lastError instanceof Error ? ` (dernière erreur : ${lastError.message})` : '';
  throw new Error(`${label} : condition non observée en ${timeoutMs} ms${suffix}`);
}

export async function waitForExit(handle: WorkerHandle, timeoutMs: number): Promise<WorkerExit> {
  const result = await Promise.race([handle.exit(), sleep(timeoutMs).then(() => undefined)]);
  if (result === undefined) throw new Error(`sortie du processus non observée en ${timeoutMs} ms`);
  return result;
}
