export const accessReason = 'Mesure synthétique Q131';
const keys = ['operationId', 'schoolId', 'kind', 'resourceId', 'resourceVersion', 'createdAt'];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Independent, narrow oracle for this campaign's updateMember metadata, never a substring test. */
export function verifyMetadataOnly(raw: string | null): number {
  if(raw === null) return 0;
  const entries: unknown = JSON.parse(raw);
  if(!Array.isArray(entries)) throw new Error('Invalid metadata array');
  for(const entry of entries) {
    if(!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('Invalid metadata object');
    if(Object.keys(entry).length !== keys.length || Object.keys(entry).some(key=>!keys.includes(key))) throw new Error('Unexpected metadata fields');
    for(const key of ['operationId','schoolId','resourceId']) if(typeof entry[key] !== 'string' || !uuid.test(entry[key])) throw new Error('Invalid metadata identifier');
    if(entry.kind !== 'updateMember' || !Number.isSafeInteger(entry.resourceVersion) || entry.resourceVersion < 1 || !Number.isSafeInteger(entry.createdAt) || entry.createdAt <= 0) throw new Error('Invalid metadata values');
  }
  return entries.length;
}
export type AccessVerdict = 'confirmed' | 'lost' | 'refused' | 'account';
export interface StoreObservation { confirmed:boolean; phases:{phase:string}[]; changed:boolean }
export function accessVerdictMatches(state:StoreObservation, expected:AccessVerdict): boolean {
  if(expected === 'confirmed') return state.confirmed === true && state.phases.length === 0;
  if(state.confirmed !== false) return false;
  if(expected === 'lost') return state.phases.length === 1 && state.phases[0]?.phase === 'uncertain';
  if(expected === 'account') return state.changed === true && state.phases.length === 0;
  return state.phases.length === 0;
}
