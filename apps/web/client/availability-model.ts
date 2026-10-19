export interface WeeklyHours {
  readonly weekdays: readonly number[];
  readonly localStart: string;
  readonly localEnd: string;
  readonly validFrom: string;
  readonly validUntil: string | null;
}

/** Same-day clocks (HH:MM) and civil dates (YYYY-MM-DD) compare as text. A missing end date is open. */
function periodsMeet(a: Pick<WeeklyHours, 'validFrom' | 'validUntil'>, b: Pick<WeeklyHours, 'validFrom' | 'validUntil'>): boolean {
  return (b.validUntil === null || a.validFrom <= b.validUntil) && (a.validUntil === null || b.validFrom <= a.validUntil);
}

/** The first existing weekly hours that the proposed ones would overlap, on a shared day, hour and period; null when none. */
export function overlappingHours(existing: readonly WeeklyHours[], proposed: WeeklyHours): WeeklyHours | null {
  return existing.find(rule => rule.weekdays.some(day => proposed.weekdays.includes(day))
    && rule.localStart < proposed.localEnd && proposed.localStart < rule.localEnd
    && periodsMeet(rule, proposed)) ?? null;
}
