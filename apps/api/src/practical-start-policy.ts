/** Qualification only. Real-school activation remains blocked by #266 and a separate deployment decision. */
export interface PracticalStartOptions { gpsOnlyQualificationSchoolIds?: readonly string[] }
export function requiresGPS(options:PracticalStartOptions,schoolId:string):boolean {
  const canonicalSchoolId=schoolId.toLowerCase();
  return options.gpsOnlyQualificationSchoolIds?.some(id=>id.toLowerCase()===canonicalSchoolId)===true;
}
