/** A field's last local choice is separate from the last confirmed object. Never restore a whole old snapshot. */
export type FieldIntention<T> = { readonly value: T; readonly revision: number };

export function projectFields<T extends object>(confirmed: T, intentions: Partial<{ [K in keyof T]: FieldIntention<T[K]> }>): T {
  const projected = { ...confirmed };
  for (const key of Object.keys(intentions) as (keyof T)[]) {
    const intention = intentions[key];
    if (intention) projected[key] = intention.value;
  }
  return projected;
}

/** Confirmation of an older choice must not remove a newer choice for the same field. */
export function acknowledgeFields<T extends object>(
  intentions: Partial<{ [K in keyof T]: FieldIntention<T[K]> }>,
  sent: Partial<{ [K in keyof T]: FieldIntention<T[K]> }>,
): Partial<{ [K in keyof T]: FieldIntention<T[K]> }> {
  const next = { ...intentions };
  for (const key of Object.keys(sent) as (keyof T)[]) if (next[key]?.revision === sent[key]?.revision) delete next[key];
  return next;
}
