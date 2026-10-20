import {createHash} from 'node:crypto';
import type {FastifyInstance} from 'fastify';
import type {Pool} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {ApiError,notFound} from './errors.js';
import {liveMatchRequest,LiveMatchLimiter,matchLive,type LiveMatcher} from './live-matching.js';

/** Extension hors canon. Deux transactions READ ONLY distinctes: pas de snapshot conservé pendant OSRM. */
export function registerLiveMatchRoutes(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;liveMatcher?:LiveMatcher}) {
 const limiter=new LiveMatchLimiter();
 app.post('/v1/schools/:schoolId/captures/:captureId/live-match',{bodyLimit:16_384},async(request,reply)=>{
  const identity=await options.verifyToken(request.headers.authorization);
  const {schoolId,captureId}=z.object({schoolId:z.uuid(),captureId:z.uuid()}).strict().parse(request.params);
  z.object({}).strict().parse(request.query);
  const input=liveMatchRequest.parse(request.body);
  // Une même identité ne contourne pas la cadence en changeant d'école, de capture ou de segment.
  const key=createHash('sha256').update(JSON.stringify([identity.issuer,identity.subject])).digest('hex');
  const release=limiter.acquire(key);
  if(!release){reply.header('Retry-After','2');throw new ApiError(429,'LIVE_MATCH_RATE_LIMITED','Recalage temporairement indisponible.');}
  try {
   const authorize=()=>withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
    if(!member?.roles.includes('INSTRUCTOR'))throw notFound();
    const row=(await db.query<{authorized_at:Date;expires_at:Date}>(`
     SELECT c.authorized_at,c.expires_at FROM drivy.capture_session c
     WHERE c.school_id=$1 AND c.id=$2 AND c.person_id=$3 AND c.instructor_membership_id=$4
      AND c.capture_state='AUTHORIZED' AND c.expires_at>clock_timestamp()
      AND c.cutoff_at IS NULL AND c.stopped_at IS NULL AND c.finalized_at IS NULL AND c.publication_state='PRIVATE'
      AND drivy.report_lesson_author(c.lesson_id)
      AND EXISTS(SELECT 1 FROM drivy.recording_choice r WHERE r.id=drivy.capture_effective_choice(c.school_id,c.learner_id,c.lesson_id) AND r.status='ALLOWED')
    `,[schoolId,captureId,actor.personId,member.id])).rows[0];
    if(!row)throw notFound();
    if(input.points.some(p=>Date.parse(p.capturedAt)<row.authorized_at.getTime()||Date.parse(p.capturedAt)>=row.expires_at.getTime()))throw new ApiError(400,'INVALID_REQUEST','Fenêtre de mesures invalide.');
   });
   await authorize();
   const result=await matchLive(input,options.liveMatcher);
   // Relire aussi après timeout, indisponibilité ou refus du moteur. Aucun résultat sortant après perte de droit.
   await authorize();
   return {data:result,requestId:request.id,serverTime:new Date().toISOString()};
  } finally {release();}
 });
}
