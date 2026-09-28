import {Pool} from 'pg';
import {loadCommandKeyring} from './command-crypto.js';
import {PostgresCommandStore,UnavailableCommandStore} from './command-store.js';
export async function configureCommands(env:NodeJS.ProcessEnv){
  const url=env.WEB_COMMAND_DATABASE_URL,path=env.WEB_COMMAND_KEYRING_FILE;
  if(!url&&!path)return {store:new UnavailableCommandStore(),close:async()=>{}};
  if(!url||!path)throw new Error('Configuration journal incomplète');
  const keyring=await loadCommandKeyring(path);
  const pool=new Pool({connectionString:url,max:5,connectionTimeoutMillis:5000});
  return {store:new PostgresCommandStore(pool,keyring),close:()=>pool.end()};
}
