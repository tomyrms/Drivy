import { EventEmitter } from 'node:events';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const transport = vi.hoisted(() => ({ connect: vi.fn() }));
vi.mock('node:http2', async importOriginal => ({
  ...await importOriginal<typeof import('node:http2')>(),
  connect: transport.connect,
}));
vi.mock('jose', () => ({
  importPKCS8: async () => ({}),
  SignJWT: class {
    setProtectedHeader() { return this; }
    setIssuer() { return this; }
    setIssuedAt() { return this; }
    async sign() { return 'synthetic-provider-token'; }
  },
}));

import { apnsSender, type PushConfig, type PushSender } from '../src/course-push.js';

// Only the HTTP/2 and signing boundaries are replaced. The production sender receives
// the same response/data/end/error/close events as a ClientHttp2Stream, without a socket.
class ResponseStream extends EventEmitter {
  rstCode = 0;
  timeout: (() => void) | undefined;
  end = vi.fn();
  resume = vi.fn();
  close = vi.fn(() => { this.emit('close'); });
  setTimeout(_milliseconds: number, callback: () => void) { this.timeout = callback; return this; }
  headers(status: number) { this.emit('response', { ':status': status }); }
  data(body: string | Buffer) { this.emit('data', Buffer.isBuffer(body) ? body : Buffer.from(body)); }
  complete() { this.emit('end'); this.emit('close'); }
}

const config: PushConfig = {
  teamId: 'SYNTHETIC1', keyId: 'SYNTHETIC2', privateKey: 'synthetic-key-not-used',
  topic: 'test.drivy', environment: 'SANDBOX',
};
let stream: ResponseStream;
let sender: PushSender;
let request: ReturnType<typeof vi.fn>;

beforeEach(() => {
  stream = new ResponseStream();
  request = vi.fn(() => stream);
  transport.connect.mockReset();
  transport.connect.mockImplementation(() => Object.assign(new EventEmitter(), {
    request, close: vi.fn(), closed: false, destroyed: false,
  }));
  sender = apnsSender(config);
});
afterEach(() => { sender.close(); });

async function sending() {
  const result = sender.send('ab'.repeat(32), 'SANDBOX', { aps: { alert: 'Synthétique' } }, null, 'test');
  // Signing crosses two Promise continuations. Flush microtasks, never wait for wall time.
  for (let i = 0; i < 8; i++) await Promise.resolve();
  expect(request).toHaveBeenCalledOnce();
  return { result };
}

describe('APNs transport: exact status/reason classification', () => {
  it.each(['BadTopic', 'BadPriority', 'MissingTopic', 'TopicDisallowed', 'DeviceTokenNotForTopic', 'PayloadEmpty'])
    ('does not invalidate a device for 400 %s', async reason => {
      const { result } = await sending();
      stream.headers(400); stream.data(JSON.stringify({ reason })); stream.complete();
      expect(await result).toBe('RETRY');
    });

  it.each([[400, 'BadDeviceToken'], [410, 'Unregistered'], [410, 'ExpiredToken']] as const)
    ('invalidates only the completed known pair %i/%s', async (status, reason) => {
      const { result } = await sending();
      stream.headers(status); stream.data(JSON.stringify({ reason })); stream.complete();
      expect(await result).toBe('INVALID_TOKEN');
    });

  it.each([[410, 'BadDeviceToken'], [400, 'Unregistered'], [403, 'Unregistered'], [503, 'BadDeviceToken'], [410, 'Unknown']])
    ('does not invalidate for mismatched or unknown pair %i/%s', async (status, reason) => {
      const { result } = await sending();
      stream.headers(Number(status)); stream.data(JSON.stringify({ reason })); stream.complete();
      expect(await result).toBe('RETRY');
    });

  it.each(['', '{', 'null', '[]', '{"reason":4}', '{"reason":"badDeviceToken"}'])
    ('does not invalidate on missing or invalid JSON reason: %s', async body => {
      const { result } = await sending();
      stream.headers(400); stream.data(body); stream.complete();
      expect(await result).toBe('RETRY');
    });

  it('accepts an empty completed 200 response', async () => {
    const { result } = await sending();
    stream.headers(200); stream.complete();
    expect(await result).toBe('SENT');
  });

  it('waits for the entire fragmented body and end before classifying', async () => {
    const { result } = await sending();
    let settled = false;
    void result.then(() => { settled = true; });
    stream.headers(400); stream.data('{"reason":"Bad');
    await Promise.resolve(); expect(settled).toBe(false);
    stream.data('DeviceToken"}');
    await Promise.resolve(); expect(settled).toBe(false);
    stream.complete();
    expect(await result).toBe('INVALID_TOKEN');
  });
});

describe('APNs transport: incomplete and bounded responses', () => {
  it.each(['connect', 'request'])('retries a synchronous %s interruption', async boundary => {
    const failure = () => { throw new Error('synthetic unavailable transport'); };
    if (boundary === 'connect') transport.connect.mockImplementation(failure);
    else request.mockImplementation(failure);
    await expect(sender.send('ab'.repeat(32), 'SANDBOX', {}, null, 'test')).resolves.toBe('RETRY');
  });

  it('retries a response that ends without headers', async () => {
    const { result } = await sending();
    stream.data('{"reason":"BadDeviceToken"}'); stream.complete();
    expect(await result).toBe('RETRY');
  });
  it.each([200, 400, 410])('retries a close before end after status %i', async status => {
    const { result } = await sending();
    stream.headers(status); stream.data('{"reason":"Unregistered"}'); stream.emit('close');
    expect(await result).toBe('RETRY');
  });

  it.each(['error', 'aborted', 'timeout', 'reset'])('retries interruption: %s', async interruption => {
    const { result } = await sending();
    stream.headers(400); stream.data('{"reason":"BadDeviceToken"}');
    if (interruption === 'error') stream.emit('error', new Error('synthetic transport failure'));
    if (interruption === 'aborted') stream.emit('aborted');
    if (interruption === 'timeout') stream.timeout?.();
    if (interruption === 'reset') stream.rstCode = 8;
    stream.complete();
    expect(await result).toBe('RETRY');
  });

  it('limits accumulated bytes to 4096 and closes without invalidation', async () => {
    const { result } = await sending();
    stream.headers(400);
    stream.data('{"reason":"BadDeviceToken","padding":"');
    stream.data(Buffer.alloc(4096, 0x61));
    stream.data('"}'); stream.complete();
    expect(await result).toBe('RETRY');
    expect(stream.close).toHaveBeenCalled();
  });

  it('accepts exactly 4096 response bytes', async () => {
    const { result } = await sending();
    const body = JSON.stringify({ reason: 'BadDeviceToken' });
    stream.headers(400); stream.data(body + ' '.repeat(4096 - Buffer.byteLength(body))); stream.complete();
    expect(await result).toBe('INVALID_TOKEN');
  });
});
