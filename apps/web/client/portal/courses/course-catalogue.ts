import { useEffect } from 'react';
import { z } from 'zod';
import { useCommandSnapshot } from '../../command-store';
import { courseCatalogueSchema, courseSeriesSchema, courseTypeSchema, type CourseCatalogue } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { moduleEntitled, readSchool, readSchoolEntitlements } from '../../school-api';

export const readCourseCatalogue = (schoolId: string): Promise<CourseCatalogue> => readSchool(schoolId, 'course-catalogue', courseCatalogueSchema);

/** Course types, delays and instructors of the school. A failure here never blocks the lessons of the agenda. */
export function useCourseCatalogue() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  return useLoad(() => readCourseCatalogue(schoolId), [schoolId, revision]);
}

export const COLLECTIVE_COURSES_MODULE = 'COLLECTIVE_COURSES';

/**
 * Droits commerciaux de l'école, relus à l'ouverture, à chaque changement de commande et au retour sur l'onglet. Un affichage seulement :
 * le serveur refuse tout nouvel usage d'un module non accordé, quelle que soit la fraîcheur de cet écran.
 */
export function useSchoolEntitlements() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const entitlements = useLoad(() => readSchoolEntitlements(schoolId), [schoolId, revision]);
  const { refresh } = entitlements;
  useEffect(() => {
    const resume = () => { if (document.visibilityState === 'visible') refresh?.(); };
    document.addEventListener('visibilitychange', resume);
    window.addEventListener('focus', resume);
    return () => { document.removeEventListener('visibilitychange', resume); window.removeEventListener('focus', resume); };
  }, [refresh]);
  return entitlements;
}

/**
 * Courses are offered only where the school enabled the module, the commercial rights grant it, and the school grants the right to manage them.
 * `entitled` defaults to true: an unread right hides nothing, the server stays the guard.
 */
export const coursesManageable = (moduleEnabled: boolean, catalogue: Pick<CourseCatalogue, 'canManage'> | undefined, entitled = true): boolean =>
  moduleEnabled && entitled && catalogue?.canManage === true;
export function useCanManageCourses(catalogue: { data: CourseCatalogue | undefined }): boolean {
  const { school } = useConsole();
  const entitlements = useSchoolEntitlements();
  return coursesManageable(school.modules.collectiveCoursesEnabled, catalogue.data, moduleEntitled(entitlements.data, COLLECTIVE_COURSES_MODULE));
}

/** The confirmed resource of a write, when the response carried it; null after a receipt-only confirmation. */
export const confirmedSeries = (body: unknown) => {
  const parsed = z.object({ data: courseSeriesSchema }).safeParse(body);
  return parsed.success ? parsed.data.data : null;
};
export const confirmedType = (body: unknown) => {
  const parsed = z.object({ data: courseTypeSchema }).safeParse(body);
  return parsed.success ? parsed.data.data : null;
};
