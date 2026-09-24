import { spawn } from 'node:child_process';
import { apiEnvironment,loadRuntime,root } from './shared.js';

try {
  const runtime=await loadRuntime();
  const child=spawn(process.execPath,['--import','tsx','apps/api/src/main.ts'],{ cwd:root,env:apiEnvironment(runtime),stdio:'inherit',windowsHide:true });
  process.once('SIGINT',()=>child.kill('SIGINT'));
  process.once('SIGTERM',()=>child.kill('SIGTERM'));
  child.once('error',()=>{ console.error('Démarrage API locale impossible.');process.exitCode=1; });
  child.once('exit',code=>{ process.exitCode=code ?? 1; });
} catch { console.error('Exécuter le provisionnement local avant de lancer cette API.');process.exitCode=1; }
