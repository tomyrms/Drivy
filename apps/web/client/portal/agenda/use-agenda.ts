import { useEffect, useMemo, useRef, useState } from 'react';
import { addDays, civilDateIn, lessonsOfLearners, weekStart, weekWindow } from '../../agenda-model';
import { useCommandSnapshot } from '../../command-store';
import { activeInstructors } from '../../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll, readSchool } from '../../school-api';
import { agendaSearchQuery } from '../../console-filter-model';
import { agendaDays, agendaReadStatus } from '../../console/agenda-projection';
import { courseSeriesListSchema } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { useListState } from '../../console/list-state';
import { distinctLabel, homonymReferences } from '../../person-reference';

/** One read projection shared by both layouts. Selection contains identifiers only. */
export function useAgenda() {
  const context = useConsole();
  const { schoolId, school, routeQuery, setRouteQuery, confirmNavigation } = context;
  const { revision } = useCommandSnapshot();
  const [now, setNow] = useState(Date.now);
  const [period, setPeriod] = useListState('portal/agenda/period', () => civilDateIn(school.timeZone));
  const [search, setSearch] = useListState('portal/agenda/search', '');
  const [instructorLocal, setInstructorLocal] = useListState('portal/agenda/instructor', '');
  const [presentation, setPresentation] = useListState<'day' | 'week'>('portal/agenda/presentation', () => window.matchMedia('(max-width: 767px)').matches ? 'day' : 'week');
  const [compact, setCompact] = useState(() => window.matchMedia('(max-width: 767px)').matches);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [localSelection, setLocalSelection] = useState<{ lesson?: string | null; course?: string; occurrence?: string } | null>(null);
  const [returnPosition, setReturnPosition] = useListState('portal/agenda/return', { top: 0, grid: 0, focus: 'portal-agenda-title' });
  const rememberPosition = (focus: string) => setReturnPosition({ top: window.scrollY, grid: document.getElementById('agenda-grid-scroll')?.scrollTop ?? 0, focus });
  const monday = weekStart(routeQuery?.week ?? routeQuery?.day ?? period);
  const selectedDay = routeQuery?.day ?? period;
  const day = weekStart(selectedDay) === monday ? selectedDay : monday;
  const instructor = routeQuery ? routeQuery.instructor ?? '' : instructorLocal;
  const bounds = weekWindow(monday, school.timeZone);
  const directory = useLoad(async () => {
    const [members, learners] = await Promise.all([readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' })]);
    return { members: members.items, learners: learners.items, truncated: members.truncated || learners.truncated };
  }, [schoolId, revision]);
  const lessons = useLoad(async () => {
    if (!bounds) throw new Error('Période invalide.');
    return readAll(schoolId, 'lessons', lessonSchema, { from: bounds.from, to: bounds.to, ...(instructor ? { instructorMembershipId: instructor } : {}) });
  }, [schoolId, revision, bounds?.from, bounds?.to, instructor], `${schoolId}/${monday}/${instructor}`);
  const courses = useLoad(async () => {
    if (!bounds) throw new Error('Période invalide.');
    return (await readSchool(schoolId, 'course-series', courseSeriesListSchema, bounds)).items;
  }, [schoolId, revision, bounds?.from, bounds?.to], `${schoolId}/${monday}`);
  const searchQuery = agendaSearchQuery(directory, search).trim();
  const searching = Boolean(search.trim());
  const events = useMemo(() => bounds ? agendaDays(lessonsOfLearners(lessons.data?.items ?? [], directory.data?.learners ?? [], searchQuery), courses.data ?? [], {
    ...bounds, timeZone: school.timeZone, instructor, includeCourses: !searching,
  }) : [], [lessons.data, directory.data, courses.data, searchQuery, searching, bounds?.from, bounds?.to, school.timeZone, instructor]);
  const days = Array.from({ length: 7 }, (_, index) => {
    const date = addDays(monday, index);
    return { day: date, items: events.find(item => item.day === date)?.items ?? [] };
  });
  const partial = lessons.data?.truncated === true || directory.data?.truncated === true || (courses.data?.length ?? 0) >= 200;
  const freshness = agendaReadStatus([lessons, directory, courses], partial);
  const emptyConfirmed = lessons.status === 'ready' && (!searching || directory.status === 'ready') && (searching || courses.status === 'ready') && !partial;
  const instructors = activeInstructors(directory.data?.members ?? []);
  const references = homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName })));
  const instructorOptions = instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
  const learnerName = (id: string) => directory.data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => directory.data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
  const refreshAt = useRef(Date.now());
  const refresh = () => {
    refreshAt.current = Date.now();
    (lessons.refresh ?? lessons.reload)(); (directory.refresh ?? directory.reload)(); (courses.refresh ?? courses.reload)();
  };
  useEffect(() => {
    const media = window.matchMedia('(max-width: 767px)');
    const change = () => setCompact(media.matches);
    media.addEventListener('change', change);
    return () => media.removeEventListener('change', change);
  }, []);
  useEffect(() => {
    const tick = () => {
      setNow(Date.now());
      if (document.visibilityState === 'visible' && Date.now() - refreshAt.current >= 60_000) refresh();
    };
    const timer = window.setInterval(tick, 30_000);
    document.addEventListener('visibilitychange', tick);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', tick); };
  }, [lessons.refresh, directory.refresh, courses.refresh]);
  const chooseDay = (date: string) => { setPeriod(date); setRouteQuery?.({ ...routeQuery, week: weekStart(date), day: date }); };
  const chooseInstructor = (value: string) => { setInstructorLocal(value); setRouteQuery?.({ ...routeQuery, instructor: value || undefined }); };
  const go = (action: () => void) => confirmNavigation ? confirmNavigation(action) : action();
  const openLesson = (id: string | null) => go(() => {
    rememberPosition(id ? `portal-lesson-${id}` : 'portal-agenda-title');
    setLocalSelection({ lesson: id });
    setRouteQuery?.({ ...routeQuery, week: monday, day, lesson: id ?? undefined, course: undefined, occurrence: undefined, view: id ? undefined : 'nouvelle' }, false, true);
  });
  const openCourse = (id: string, occurrence: string) => go(() => {
    rememberPosition(`portal-course-${id}-${occurrence}`);
    setLocalSelection({ course: id, occurrence });
    setRouteQuery?.({ ...routeQuery, week: monday, day, lesson: undefined, course: id, occurrence, view: undefined }, false, true);
  });
  const selection = routeQuery ? routeQuery.lesson ? { lesson: routeQuery.lesson } : routeQuery.view === 'nouvelle' ? { lesson: null }
    : routeQuery.course ? { course: routeQuery.course, occurrence: routeQuery.occurrence } : null : localSelection;
  const close = () => {
    setLocalSelection(null); setRouteQuery?.({ ...routeQuery, lesson: undefined, course: undefined, occurrence: undefined, view: undefined }, false, true);
    window.requestAnimationFrame(() => {
      const grid = document.getElementById('agenda-grid-scroll'); if (grid) grid.scrollTop = returnPosition.grid;
      (document.getElementById(returnPosition.focus) ?? document.getElementById('portal-agenda-title'))?.focus({ preventScroll: true }); window.scrollTo({ top: returnPosition.top });
    });
  };
  return { context, now, monday, day, days, search, setSearch, instructor, chooseInstructor, instructorOptions, presentation, setPresentation,
    compact, filtersOpen, setFiltersOpen, directory, lessons, courses, partial, freshness, emptyConfirmed, searching, learnerName, memberName,
    refresh, chooseDay, openLesson, openCourse, close, selection };
}
