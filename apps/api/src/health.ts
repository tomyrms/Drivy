import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool} from 'pg';

/**
 * Sondes d'exploitation internes, hors contrat canonique : aucune donnée scolaire, aucune version ni message SQL.
 * Une requête relayée par le proxy public (en-têtes Forwarded/X-Forwarded-*) reçoit le même 404 qu'un chemin inconnu :
 * la sonde ne sert qu'en boucle locale ou depuis le superviseur de l'hôte.
 */
const forwarded=(r:FastifyRequest)=>['forwarded','x-forwarded-for','x-forwarded-host','x-forwarded-proto','x-real-ip'].some(name=>r.headers[name]!==undefined);
const notFound={type:'urn:drivy:problem:not_found',title:'Objet introuvable dans le périmètre autorisé.',status:404,code:'NOT_FOUND'};

export function registerHealth(app:FastifyInstance,options:{pool:Pool;readinessTimeoutMs?:number}){
 const timeout=options.readinessTimeoutMs??2000;
 app.get('/health/live',async(r,reply)=>{
  if(forwarded(r))return reply.status(404).type('application/problem+json').send({...notFound,requestId:r.id});
  return {status:'ok'};
 });
 app.get('/health/ready',async(r,reply)=>{
  if(forwarded(r))return reply.status(404).type('application/problem+json').send({...notFound,requestId:r.id});
  let timer:NodeJS.Timeout|undefined;
  try{
   // Une seule lecture constante : ni schéma, ni rôle, ni latence ne sont exposés.
   await Promise.race([options.pool.query('SELECT 1'),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('timeout')),timeout);})]);
   return {status:'ready'};
  }catch{
   return reply.status(503).send({status:'unavailable'});
  }finally{if(timer)clearTimeout(timer);}
 });
}
