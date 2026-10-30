import type { AgendaEvent } from '../../console/agenda-projection';

const wallMinute = (instant: string, timeZone: string) => {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(instant));
  return Number(parts.find(part => part.type === 'hour')?.value) * 60 + Number(parts.find(part => part.type === 'minute')?.value);
};
export function calendarInterval(event: AgendaEvent, timeZone: string) {
  const start = wallMinute(event.startsAt, timeZone);
  const end = wallMinute(event.kind === 'lesson' ? event.lesson.plannedEnd : event.occurrence.endsAt, timeZone);
  return { start, end: end > start ? end : 1440 };
}
/** Collision lanes include the minimum readable event height; no overlap hides another appointment. */
export function calendarLanes(events: readonly AgendaEvent[], timeZone: string) {
  const result: { event: AgendaEvent; start: number; end: number; lane: number; lanes: number }[] = [];
  let cluster: typeof result = [], ends: number[] = [], clusterEnd = -1;
  const finish = () => { for (const item of cluster) item.lanes = ends.length; cluster = []; ends = []; };
  for (const event of [...events].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt))) {
    const interval = calendarInterval(event, timeZone), end = Math.max(interval.end, interval.start + 72);
    if (interval.start >= clusterEnd) { finish(); clusterEnd = -1; }
    let lane = ends.findIndex(value => value <= interval.start);
    if (lane === -1) lane = ends.length;
    ends[lane] = end; clusterEnd = Math.max(clusterEnd, end);
    const item = { event, start: interval.start, end, lane, lanes: 1 }; result.push(item); cluster.push(item);
  }
  finish(); return result;
}
