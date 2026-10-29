import { z } from 'zod';
import { useCommandSnapshot } from '../../command-store';
import { courseCatalogueSchema, courseSeriesSchema, courseTypeSchema, type CourseCatalogue } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { readSchool } from '../../school-api';

export const readCourseCatalogue = (schoolId: string): Promise<CourseCatalogue> => readSchool(schoolId, 'course-catalogue', courseCatalogueSchema);

/** Course types, delays and instructors of the school. A failure here never blocks the lessons of the agenda. */
export function useCourseCatalogue() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  return useLoad(() => readCourseCatalogue(schoolId), [schoolId, revision]);
}

/** Courses are offered only where the school enabled the module and the school grants the right to manage them. */
export const coursesManageable = (moduleEnabled: boolean, catalogue: Pick<CourseCatalogue, 'canManage'> | undefined): boolean => moduleEnabled && catalogue?.canManage === true;
export function useCanManageCourses(catalogue: { data: CourseCatalogue | undefined }): boolean {
  const { school } = useConsole();
  return coursesManageable(school.modules.collectiveCoursesEnabled, catalogue.data);
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
