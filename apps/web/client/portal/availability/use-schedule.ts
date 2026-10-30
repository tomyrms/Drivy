import { useEffect, useMemo, useState } from 'react';
import { civilDateIn } from '../../agenda-model';
import { useCommandSnapshot } from '../../command-store';
import { activeInstructors } from '../../invitation-model';
import { availabilitySchema, closureSchema, memberSchema, readAll } from '../../school-api';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { useConsole, useLoad } from '../../console/context';
import { useListState } from '../../console/list-state';
import { ruleGroups, upcomingAbsences } from './schedule-model';

/** Which composition is open on the page: the reading view, one hours editor (new or existing), or the absence editor. */
export type ScheduleView = null | { kind: 'rule'; ruleId: string | null } | { kind: 'absence' };

/**
 * One read projection for hours and absences, and the instructor they are shown for.
 * The chosen instructor survives a change of tab (hours ↔ absences) through the school's list memory and the URL.
 */
export function useSchedule() {
  const context = useConsole();
  const { schoolId, school, membership, routeQuery, setRouteQuery, confirmNavigation } = context;
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [members, rules, closures] = await Promise.all([readAll(schoolId, 'members', memberSchema),
      readAll(schoolId, 'availability-rules', availabilitySchema), readAll(schoolId, 'closures', closureSchema)]);
    return { members: members.items, rules: rules.items, closures: closures.items, truncated: members.truncated || rules.truncated || closures.truncated };
  }, [schoolId, revision]);
  const [remembered, setRemembered] = useListState('portal/planning/instructor', '');
  const [now, setNow] = useState(Date.now);
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 60_000); return () => window.clearInterval(timer); }, []);
  const instructors = useMemo(() => activeInstructors(loaded.data?.members ?? []), [loaded.data]);
  const references = useMemo(() => homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName }))), [instructors]);
  const options = instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
  const requested = routeQuery?.instructor ?? remembered;
  const instructor = instructors.some(item => item.id === requested) ? requested
    : instructors.some(item => item.id === membership.membershipId) ? membership.membershipId : instructors[0]?.id ?? '';
  const instructorName = options.find(item => item.value === instructor)?.label ?? '';
  const today = civilDateIn(school.timeZone, now);
  const rules = useMemo(() => (loaded.data?.rules ?? []).filter(rule => rule.instructorMembershipId === instructor), [loaded.data, instructor]);
  const groups = useMemo(() => ruleGroups(rules, today), [rules, today]);
  const absences = useMemo(() => upcomingAbsences((loaded.data?.closures ?? []).filter(item => item.instructorMembershipId === instructor), now), [loaded.data, instructor, now]);
  const [view, setView] = useState<ScheduleView>(null);
  // A different target never inherits an open composition (back/forward, school switch).
  useEffect(() => { setView(null); }, [instructor, schoolId]);
  const chooseInstructor = (id: string | null) => {
    if (!id || id === instructor) return;
    const proceed = () => { setView(null); setRemembered(id); setRouteQuery?.({ ...routeQuery, instructor: id }, false, true); };
    if (confirmNavigation) confirmNavigation(proceed); else proceed();
  };
  const partial = loaded.data?.truncated === true;
  return { context, loaded, instructors, options, instructor, instructorName, today, now, rules, groups, absences, view, setView, chooseInstructor, partial,
    /** Writes wait for a complete read: a hidden overlap or a hidden absence would make the review misleading. */
    writable: school.status === 'ACTIVE' && loaded.status === 'ready' && !partial && instructors.some(item => item.id === instructor),
    refresh: loaded.refresh ?? loaded.reload };
}
export type ScheduleState = ReturnType<typeof useSchedule>;
