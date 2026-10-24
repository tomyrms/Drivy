import { Pool } from 'pg';
import { setTimeout } from 'node:timers/promises';
import { guardPool } from './database.js';
import { apnsSender, processPushBatch, pushConfig } from './course-push.js';

/**
 * Service des cours collectifs : expiration des propositions, rappels, alerte de minimum, notifications push.
 * Rôle PostgreSQL drivy_course_worker (sans BYPASSRLS). Sans clés APNs, il avance la file et prépare les notifications
 * sans rien envoyer (elles restent consultables dans l'app).
 */
async function run(){
 if(!process.env.COURSE_WORKER_DATABASE_URL)throw new Error('Configuration absente.');
 const pool=guardPool(new Pool({connectionString:process.env.COURSE_WORKER_DATABASE_URL,max:2,connectionTimeoutMillis:5000}));
 const config=pushConfig();const sender=config?apnsSender(config):undefined;
 try{
  const roles=await pool.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user OR rolname='drivy_course_worker'");
  if(roles.rows.length!==2||roles.rows.some(row=>row.rolsuper||row.rolbypassrls))throw new Error('Rôle non autorisé.');
  let stopping=false;process.on('SIGTERM',()=>{stopping=true;});process.on('SIGINT',()=>{stopping=true;});
  while(!stopping){
   try{const processed=await processPushBatch(pool,sender);if(!processed)await setTimeout(15_000);}
   catch{process.stderr.write('Service des cours : traitement temporairement indisponible.\n');await setTimeout(15_000);}
  }
 }finally{sender?.close();await pool.end();}
}
try{await run();}catch{process.stderr.write('Service des cours : démarrage impossible, vérifier configuration et droits.\n');process.exitCode=1;}
