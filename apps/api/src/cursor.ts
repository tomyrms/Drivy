import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { z } from 'zod';
import { ApiError } from './errors.js';

const payloadSchema = z.object({ scope: z.string(), createdAt: z.iso.datetime({ offset: true }), id: z.uuid(), expiresAt: z.number() }).strict();
export type Position = Pick<z.infer<typeof payloadSchema>, 'createdAt' | 'id'>;
export class Cursors {
  private readonly key: Buffer;
  constructor(secret: string) { this.key = createHash('sha256').update(secret).digest(); }
  encode(scope: string, position: Position): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const data = Buffer.from(JSON.stringify({ scope, ...position, expiresAt: Date.now() + 3_600_000 }));
    const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString('base64url');
  }
  decode(token: string | undefined, scope: string): Position | undefined {
    if (!token) return undefined;
    try {
      if (token.length > 6000 || !/^[A-Za-z0-9_-]+$/.test(token)) throw new Error();
      const bytes = Buffer.from(token, 'base64url');
      const decipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(0, 12));
      decipher.setAuthTag(bytes.subarray(12, 28));
      const payload = payloadSchema.parse(JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]).toString('utf8')));
      if (payload.scope !== scope || payload.expiresAt < Date.now()) throw new Error();
      return { createdAt: payload.createdAt, id: payload.id };
    } catch { throw new ApiError(400, 'INVALID_CURSOR', 'Rechargez la liste : ce curseur n’est plus valide pour ces filtres et cet accès.'); }
  }
}
