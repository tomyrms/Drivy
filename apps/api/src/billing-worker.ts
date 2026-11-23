import { Pool } from 'pg';
import { setTimeout } from 'node:timers/promises';
import { guardPool } from './database.js';

/**
 * Service de facturation planifiée (R01-T05, #457) : une fois par heure, prépare puis émet les factures dues des fiches activées,
 * puis fait le passage des relances (R01-T09, #461) : rappels, avertissement, suspension automatique et levée après règlement.
 * Rôle PostgreSQL drivy_billing_worker (sans BYPASSRLS ni SUPERUSER) : il n'a que le droit d'exécuter drivy.platform_billing_run() et
 * drivy.platform_dunning_run(). La politique de relance est créée désactivée : sans opérateur, le second passage ne fait rien.
 * Les journaux ne reçoivent que des compteurs, jamais un nom, un montant ni un identifiant.
 */
const intervalMs = 60 * 60 * 1000;
async function run(){
 if(!process.env.BILLING_WORKER_DATABASE_URL)throw new Error('Configuration absente.');
 const pool=guardPool(new Pool({connectionString:process.env.BILLING_WORKER_DATABASE_URL,max:1,connectionTimeoutMillis:5000}));
 try{
  const roles=await pool.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user OR rolname='drivy_billing_worker'");
  if(roles.rows.length!==2||roles.rows.some(row=>row.rolsuper||row.rolbypassrls))throw new Error('Rôle non autorisé.');
  let stopping=false;const stop=()=>{stopping=true;};process.on('SIGTERM',stop);process.on('SIGINT',stop);
  while(!stopping){
   try{
    const result=(await pool.query<{result:{skipped:boolean;prepared?:number;issued?:number;waiting?:number;failed?:number}}>('SELECT drivy.platform_billing_run() AS result')).rows[0]!.result;
    if(!result.skipped)process.stdout.write(`Facturation planifiée : ${result.prepared??0} préparée(s), ${result.issued??0} émise(s), ${result.waiting??0} en attente, ${result.failed??0} en échec.\n`);
   }catch{process.stderr.write('Facturation planifiée : passage temporairement indisponible.\n');}
   // Après la facturation : une facture émise à l'instant est vue par les relances du même passage.
   try{
    const dunning=(await pool.query<{result:{skipped:boolean;reminders?:number;warnings?:number;suspended?:number;lifted?:number;failed?:number}}>('SELECT drivy.platform_dunning_run() AS result')).rows[0]!.result;
    if(!dunning.skipped)process.stdout.write(`Relances planifiées : ${dunning.reminders??0} rappel(s), ${dunning.warnings??0} avertissement(s), ${dunning.suspended??0} suspension(s), ${dunning.lifted??0} levée(s), ${dunning.failed??0} en échec.\n`);
   }catch{process.stderr.write('Relances planifiées : passage temporairement indisponible.\n');}
   for(let waited=0;waited<intervalMs&&!stopping;waited+=15_000)await setTimeout(15_000);
  }
 }finally{await pool.end();}
}
try{await run();}catch{process.stderr.write('Facturation planifiée : démarrage impossible, vérifier configuration et droits.\n');process.exitCode=1;}
