import { RequestFailure, type Me, type Member } from '../protocol.js';
import type { School } from '../school-api.js';

export type AccessRead =
  | { status: 'ready'; me: Me; membership: Member; school: School }
  | { status: 'denied'; me: Me; membership: Member | null }
  | { status: 'signin' }
  | { status: 'unavailable'; error: RequestFailure };

/** Only the latest authority check can restore a console, including after an explicit denial. */
export class ConsoleAccessReader {
  private generation = 0;

  constructor(private readonly readMe: () => Promise<Me>, private readonly readSchool: (schoolId: string) => Promise<School>) {}

  invalidate(): void { this.generation++; }

  async read(schoolId: string): Promise<AccessRead | null> {
    const current = ++this.generation;
    try {
      const me = await this.readMe();
      if (current !== this.generation) return null;
      const membership = me.memberships.find(member => member.schoolId === schoolId);
      if (!membership?.roles.includes('ADMIN')) return { status: 'denied', me, membership: membership ?? null };
      const school = await this.readSchool(membership.schoolId);
      if (current !== this.generation) return null;
      if (school.id !== membership.schoolId) return { status: 'unavailable', error: new RequestFailure('INVALID_RESPONSE') };
      return { status: 'ready', me, membership, school };
    } catch (error) {
      if (current !== this.generation) return null;
      if (error instanceof RequestFailure) {
        if (error.status === 401) return { status: 'signin' };
        if ([403, 404].includes(error.status)) return { status: 'unavailable', error };
      }
      // A transient read failure cannot invent revoked rights; section reads expose their own failures.
      return null;
    }
  }
}
