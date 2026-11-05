export function summarize(values: number[]) {
  if (values.some(value => !Number.isFinite(value) || value < 0)) throw new Error('Invalid observed duration');
  if (!values.length) return { status: 'NON_MESURÉ', reason: 'Aucun échantillon observé' };
  const sorted = [...values].sort((a, b) => a - b), middle = Math.floor(sorted.length / 2);
  return { n: sorted.length, min: sorted[0]!, median: sorted.length % 2 ? sorted[middle]! : (sorted[middle - 1]! + sorted[middle]!) / 2, max: sorted.at(-1)! };
}
