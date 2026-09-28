import {realpathSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {Pool,type PoolClient} from 'pg';
import {z} from 'zod';
import {decodeRow,encryptPayload,keyringSchema,loadCommandKeyring,type CommandKeyring,type CommandRow} from './command-crypto.js';
async function transaction<T>(pool:Pool,work:(db:PoolClient)=>Promise<T>){
  const db=await pool.connect();try{await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_web_maintenance');
    await db.query("SET LOCAL lock_timeout='3s'");await db.query("SET LOCAL statement_timeout='10s'");
    const value=await work(db);await db.query('COMMIT');return value;
  }catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
}
/** One bounded batch, including uncertain commands; never changes payload or state. */
export async function rekeyCommands(pool:Pool,keyring:CommandKeyring){
  const ring=keyringSchema.parse(keyring);
  return transaction(pool,async db=>{
    const rows=(await db.query<CommandRow>(`SELECT * FROM drivy_web.profile_command WHERE key_id<>$1
      AND (lease_until IS NULL OR lease_until<clock_timestamp()) ORDER BY operation_id LIMIT 100 FOR UPDATE SKIP LOCKED`,[ring.activeKeyId])).rows;
    for(const row of rows){const value=decodeRow(row,ring);const sealed=encryptPayload({...row,key_id:ring.activeKeyId},{request:value.request,
      ...(value.reviewPolicy?{reviewPolicy:value.reviewPolicy}:{}),...(value.reviewNotice?{reviewNotice:value.reviewNotice}:{})},ring);
      const updated=await db.query(`UPDATE drivy_web.profile_command SET key_id=$3,sealed=$4,revision=revision+1,updated_at=clock_timestamp()
        WHERE operation_id=$1 AND revision=$2`,[row.operation_id,row.revision,ring.activeKeyId,sealed]);
      if(updated.rowCount!==1)throw new Error('COMMAND_REKEY_CONFLICT');
    }
    const remaining=Number((await db.query<{count:string}>('SELECT count(*) FROM drivy_web.profile_command WHERE key_id<>$1',[ring.activeKeyId])).rows[0]!.count);
    return {changed:rows.length,remaining};
  });
}
/** SQL restrictive RLS additionally forbids deleting any unresolved command. */
export async function purgeCommands(pool:Pool,retentionDays:number){
  z.number().int().min(1).max(3650).parse(retentionDays);
  return transaction(pool,async db=>{
    const removed=await db.query(`DELETE FROM drivy_web.profile_command WHERE state IN('COMMITTED','REJECTED','CANCELLED')
      AND lease_id IS NULL AND finished_at<clock_timestamp()-make_interval(days=>$1)`,[retentionDays]);return {removed:removed.rowCount??0};
  });
}
async function main(){
  const command=process.argv[2];if(!['rekey','purge'].includes(command??''))throw new Error('Action maintenance requise');
  const connectionString=process.env.WEB_COMMAND_MIGRATION_DATABASE_URL;if(!connectionString)throw new Error('Connexion opérateur requise');
  const pool=new Pool({connectionString,max:1,connectionTimeoutMillis:5000});
  try{
    if(command==='purge')process.stdout.write(JSON.stringify(await purgeCommands(pool,Number(process.env.WEB_COMMAND_RETENTION_DAYS??'30')))+'\n');
    else {const path=process.env.WEB_COMMAND_KEYRING_FILE;if(!path)throw new Error('Keyring requis');const ring=await loadCommandKeyring(path);
      let total=0,remaining=0;do{const result=await rekeyCommands(pool,ring);total+=result.changed;remaining=result.remaining;if(!result.changed)break;}while(remaining);
      process.stdout.write(JSON.stringify({changed:total,remaining})+'\n');}
  }finally{await pool.end();}
}
if(process.argv[1]&&realpathSync(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>{process.stderr.write('Maintenance du journal interrompue. Aucun contenu ni clé affiché.\n');process.exitCode=1;});
