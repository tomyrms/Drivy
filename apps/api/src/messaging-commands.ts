import type { PoolClient } from 'pg';
import { z } from 'zod';
import { commandHash, recordCommand } from './commands.js';
import { ApiError, notFound } from './errors.js';
import { canRead, type MessagingActor } from './messaging.js';

export const messagingMutationTypes = ['MESSAGING_REACTION','MESSAGING_PIN','MESSAGING_VOTE','MESSAGING_HIDE','MESSAGING_DELETE'] as const;
type MutationType = typeof messagingMutationTypes[number];
export type MessagingMutation = { operationId:string; commandType:MutationType; conversationId:string; messageId:string; hash:string };

/** Optional for older clients. A supplied key is bound to actor, school, route and the exact accepted intention. */
export function messagingMutation(header:string|string[]|undefined, commandType:MutationType, schoolId:string,
  conversationId:string, messageId:string, body:unknown): MessagingMutation | undefined {
  if (header === undefined) return undefined;
  const operationId = z.uuid().parse(header).toLowerCase();
  return { operationId,commandType,conversationId,messageId,
    hash:commandHash({schoolId:schoolId.toLowerCase(),conversationId:conversationId.toLowerCase(),messageId:messageId.toLowerCase(),body},null) };
}

/** Existing operation/audit machinery, in the same transaction as the effect; the caller holds the shared operation lock. */
export async function executeMessagingMutation<T>(db:PoolClient,actor:MessagingActor,mutation:MessagingMutation,work:()=>Promise<T>):Promise<T> {
  const previous = await db.query<{school_id:string;command_type:string;payload_hash:string;response_data:T}>(
    'SELECT school_id,command_type,payload_hash,response_data FROM drivy.operation WHERE actor_person_id=$1 AND operation_id=$2',
    [actor.personId,mutation.operationId]);
  const known = previous.rows[0];
  if (known) {
    if (known.school_id !== actor.schoolId || known.command_type !== mutation.commandType || known.payload_hash !== mutation.hash)
      throw new ApiError(409,'IDEMPOTENCY_MISMATCH','Cette opération a déjà été utilisée avec un autre contenu ou contexte.');
    // Retained history can prove an old outcome, but a revoked account/membership or unreadable conversation cannot.
    await canRead(db,actor,mutation.conversationId);
    return known.response_data;
  }
  const result = await work();
  await recordCommand(db,{...actor,roles:[]},actor.schoolId,mutation.commandType,mutation.operationId,mutation.hash,
    {data:result,action:'MessagingMutationCommitted',resourceType:'MessagingMessage',resourceId:mutation.messageId,
      resourceVersion:1,changedFields:[]});
  return result;
}

/** AP72 returns the author's receipt only while the related conversation remains readable. */
export async function authorizeMessagingOperation(db:PoolClient,actor:MessagingActor,commandType:string,messageId:string):Promise<boolean> {
  if (!(messagingMutationTypes as readonly string[]).includes(commandType)) return false;
  const message = await db.query<{conversation_id:string}>('SELECT conversation_id FROM drivy.messaging_message WHERE school_id=$1 AND id=$2',[actor.schoolId,messageId]);
  if (!message.rows[0]) throw notFound();
  await canRead(db,actor,message.rows[0].conversation_id);
  return true;
}
