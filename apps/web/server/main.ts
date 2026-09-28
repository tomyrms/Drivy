import { fileURLToPath } from 'node:url';
import { readConfig } from './config.js';
import { createIdentityProvider } from './oidc.js';
import { buildWebApp } from './app.js';
import {configureCommands} from './command-config.js';

try {
  const config = readConfig(process.env);
  const identity = await createIdentityProvider(config);
  const commands=await configureCommands(process.env);
  const app = await buildWebApp({config,identity,commandStore:commands.store,staticRoot:fileURLToPath(new URL('../client',import.meta.url))});
  app.addHook('onClose',commands.close);
  const stop = async () => { await app.close(); process.exit(0); };
  process.on('SIGINT',stop); process.on('SIGTERM',stop);
  await app.listen({host:config.host,port:config.port});
  process.stdout.write('Drivy web prêt.\n');
} catch {
  process.stderr.write('Démarrage web interrompu. Vérifier la configuration privée et la disponibilité des services.\n');
  process.exit(1);
}
