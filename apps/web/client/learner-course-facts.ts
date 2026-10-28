import {z} from 'zod';
import type {PrerequisiteEvidence} from './swiss-prerequisites.js';

const typeKey=z.enum(['FIRST_AID','AWARENESS']),id=z.uuid();
export const learnerCourseFactsSchema=z.object({
  schoolId:id,learnerId:id,
  completions:z.array(z.object({id,typeKey,validatedAt:z.iso.datetime({offset:true}),seriesId:id.nullable()})),
  enrollments:z.array(z.object({enrollmentId:id,seriesId:id,typeKey,
    requirements:z.object({required:z.number().int().nonnegative(),present:z.number().int().nonnegative(),missing:z.number().int().nonnegative()}),
    attendance:z.array(z.object({occurrenceId:id,status:z.enum(['PRESENT','ABSENT','EXCUSED'])})),
  })),
});
export type LearnerCourseFacts=z.infer<typeof learnerCourseFactsSchema>;
export type CourseFactsRead={status:'READY';data:LearnerCourseFacts}|{status:'ACCESS_DENIED'|'NOT_FOUND'|'READ_ERROR'};
export const prerequisiteCourseTypes={'first-aid':'FIRST_AID',awareness:'AWARENESS'} as const;

/** Aucune conversion de validatedAt en completedOn, ni de présences en accomplissement. */
export function coursePrerequisiteEvidence(read:CourseFactsRead):Record<string,PrerequisiteEvidence>{
  return Object.fromEntries(Object.entries(prerequisiteCourseTypes).map(([key,type])=>{
    if(read.status!=='READY')return [key,{state:read.status} satisfies PrerequisiteEvidence];
    const completion=read.data.completions.find(item=>item.typeKey===type);
    if(completion)return [key,{state:'INTERNAL_VALIDATION',validatedAt:completion.validatedAt} satisfies PrerequisiteEvidence];
    const enrollments=read.data.enrollments.filter(item=>item.typeKey===type);
    const state=enrollments.some(item=>item.attendance.some(mark=>mark.status==='PRESENT'))?'ATTENDANCE_ONLY':enrollments.length?'ENROLLED':'UNKNOWN';
    return [key,{state} satisfies PrerequisiteEvidence];
  }));
}
