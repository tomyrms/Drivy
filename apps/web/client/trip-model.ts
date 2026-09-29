import { z } from 'zod';

const timestamp = z.string().datetime({ offset: true });
export const tripSchema = z.object({
  id: z.string().uuid(), schoolId: z.string().uuid(), lessonId: z.string().uuid(), learnerId: z.string().uuid(),
  learnerName: z.string(), instructorName: z.string(), instructorMembershipId: z.string().uuid(),
  authorizedAt: timestamp, stoppedAt: timestamp.nullable(), cutoffAt: timestamp.nullable(),
  lessonPlannedStart: timestamp, lessonTimeZone: z.string(), captureState: z.string(), syncState: z.string(),
});
export type Trip = z.infer<typeof tripSchema>;

export function tripDuration(trip: Pick<Trip, 'authorizedAt' | 'stoppedAt' | 'cutoffAt' | 'captureState'>): string {
  const end = trip.cutoffAt ?? trip.stoppedAt;
  if (!end) return trip.captureState === 'AUTHORIZED' ? 'En cours' : '—';
  const minutes = Math.max(0, Math.round((Date.parse(end) - Date.parse(trip.authorizedAt)) / 60_000));
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}
