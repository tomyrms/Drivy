import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider } from '../../apps/web/server/oidc.js';
import { apiOrigin,issuer,stateDirectory } from './shared.js';

try {
  const saved=z.object({clientSecret:z.string()}).parse(JSON.parse(await readFile(new URL('web-runtime.json',stateDirectory),'utf8')));
  const config={origin:'http://127.0.0.1:3002',apiBaseURL:apiOrigin,issuer,clientId:'drivy-web',clientSecret:saved.clientSecret,
    development:true,host:'127.0.0.1',port:3002};
  const identity=await createIdentityProvider(config);
  const app=await buildWebApp({config,identity,staticRoot:fileURLToPath(new URL('../../apps/web/dist/client/',import.meta.url))});
  const stop=async()=>{await app.close();process.exit(0);};
  process.once('SIGINT',stop);process.once('SIGTERM',stop);
  await app.listen({host:config.host,port:config.port});
  console.log('Web local : http://127.0.0.1:3002/app ; démarrer run-api.ts séparément pour les données scolaires.');
} catch { console.error('Web local indisponible. Exécuter setup-web.ts et compiler apps/web au préalable. Aucun secret affiché.');process.exitCode=1; }
