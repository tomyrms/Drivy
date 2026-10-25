import { z } from 'zod';

/** Opt-in scolaire uniquement. Ne fournit aucune identité ni aucun droit métier. */
export interface MessagingQualification { mode: 'disabled' | 'qualification'; schoolIds: readonly string[] }
export interface MessagingAccessOptions { mode?: 'disabled' | 'test-synthetic'; qualification?: MessagingQualification }

export function messagingSchoolGate(options: MessagingAccessOptions): (schoolId: string) => boolean {
  const qualification = options.qualification;
  const parsed = z.array(z.uuid()).min(1).max(100).safeParse(qualification?.schoolIds);
  const schools = new Set(qualification?.mode === 'qualification' && parsed.success
    ? parsed.data.map(id => id.toLowerCase()) : []);
  const synthetic = options.mode === 'test-synthetic' && process.env.NODE_ENV === 'test';
  return schoolId => schools.has(schoolId.toLowerCase()) || synthetic;
}
