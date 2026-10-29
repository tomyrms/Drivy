import type { SchoolCommand } from '../../command-core';
import type { FixtureRecord } from './fixtures';
import type { PreviewScenario } from './transport';

/** One synthetic request below /app/bff/schools/{school}/ ; segments are the path parts after the school. */
export interface PreviewRequest {
  method: string;
  path: string;
  segments: readonly string[];
  collection: string | undefined;
  resourceId: string | undefined;
  action: string | undefined;
  query: URLSearchParams;
  headers: Headers;
  /** Parsed JSON body for writes, empty object for reads. */
  body: FixtureRecord;
  scenario: PreviewScenario;
}

export interface PreviewTools {
  reply(status: number, body: unknown): Response;
  envelope(data: unknown): unknown;
  list(items: unknown[]): unknown;
  /** Store the idempotent result and receipt of a write, then answer (or lose the answer in the lost-reply scenario). */
  commit(kind: SchoolCommand['kind'], record: FixtureRecord): Response;
  versionMatches(record: FixtureRecord | undefined): boolean;
  nextId(): string;
}

/** A synthetic request to a route outside the school: session, accounts, invitations, opening links. Path after /app/bff/. */
export interface PreviewBffRequest {
  method: string;
  path: string;
  query: URLSearchParams;
  headers: Headers;
  body: FixtureRecord;
  scenario: PreviewScenario;
}

/**
 * Synthetic behaviour of one rebuilt family. Seed adds records to the shared fixture store at load.
 * Read and write return undefined to let the next family or the generic store answer.
 * Writes reach a family only after idempotency, the slow/refused/conflict scenarios and JSON parsing.
 */
export interface PreviewFamily {
  name: string;
  /**
   * Routes outside the school (`/app/bff/<path>`), tried before the built-in session and identity answers.
   * Apply the scenario yourself (slow, refused, conflict, lost-reply); nothing is stored by the transport.
   */
  bff?(request: PreviewBffRequest, tools: Pick<PreviewTools, 'reply' | 'nextId'>): Response | undefined | Promise<Response | undefined>;
  seed?(db: Record<string, FixtureRecord[]>): void;
  read?(request: PreviewRequest, tools: PreviewTools): Response | undefined;
  write?(request: PreviewRequest, tools: PreviewTools): Response | undefined;
  /** Domain code returned by the « refus » scenario for this family's writes. */
  refusalCode?(request: PreviewRequest): string | undefined;
}
