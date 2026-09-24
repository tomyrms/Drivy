import { Pool } from 'pg';
import { setTimeout } from 'node:timers/promises';
import { deliverOneInvitation,invitationMailConfig } from './invitation-mail.js';
async function run() {
  const config=invitationMailConfig();
  if(!config || !process.env.MAIL_DATABASE_URL) throw new Error('Configuration absente.');
  const pool=new Pool({connectionString:process.env.MAIL_DATABASE_URL,max:2,connectionTimeoutMillis:5000});
  try {
    const privileges=await pool.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user OR rolname='drivy_invitation_mailer'");
    if(privileges.rows.length!==2 || privileges.rows.some(row=>row.rolsuper || row.rolbypassrls)) throw new Error('Rôle non autorisé.');
    let stopping=false;process.on('SIGTERM',()=>{stopping=true;});process.on('SIGINT',()=>{stopping=true;});
    while(!stopping) {try {const processed=await deliverOneInvitation(pool,config);if(!processed) await setTimeout(1000);}
      catch {process.stderr.write('Worker invitations : traitement temporairement indisponible.\n');await setTimeout(5000);}}
  } finally {await pool.end();}
}
try {await run();} catch {process.stderr.write('Worker invitations : démarrage impossible, vérifier configuration et droits.\n');process.exitCode=1;}
