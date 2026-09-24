#!/usr/bin/env python3
"""Checks selected cross-contract conventions; does not run a Drivy service.
Usage: python annexes/verifier-contrats-transversaux.py [--root path]
"""
from pathlib import Path
import argparse,json,yaml
METHODS={'get','post','put','patch','delete','head','options'}
def check(root):
 a=yaml.safe_load((Path(root)/'04-technique/openapi.yaml').read_text(encoding="utf-8"));s=a['components']['schemas'];errors=[];counts={'operations':0,'successBranches':0,'ordinaryLimitParameters':0,'ordinaryPageSchemas':0,'pendingContracts':0}
 def err(kind,**kw):errors.append({'type':kind,**kw})
 def branches(sc):return sc.get('oneOf',sc.get('anyOf',[sc]))
 for name,sc in s.items():
  if 'Page' in name and 'items' in sc.get('properties',{}):
   counts['ordinaryPageSchemas']+=1
   if sc['properties']['items'].get('maxItems')!=100:err('PAGE_ITEMS_LIMIT',schema=name)
 for path,ms in a['paths'].items():
  for m,o in ms.items():
   if m not in METHODS:continue
   counts['operations']+=1;ident=o['operationId']
   for p in o.get('parameters',[]):
    if p.get('name')=='limit' and p.get('in')=='query' and ident!='getCaptureReplay':
     counts['ordinaryLimitParameters']+=1
     if not all(p['schema'].get(k)==v for k,v in {'minimum':1,'maximum':100,'default':50}.items()):err('QUERY_LIMIT',operation=ident)
   for code,r in o.get('responses',{}).items():
    if not str(code).startswith('2'):continue
    sc=r.get('content',{}).get('application/json',{}).get('schema')
    if sc:
     for b in branches(sc):
      counts['successBranches']+=1;name=b.get('$ref','').split('/')[-1];shape=s.get(name,{})
      if not all(k in shape.get('required',[]) for k in ['data','requestId','serverTime']):err('SUCCESS_ENVELOPE',operation=ident,status=code,schema=name)
   requires_pending=ident=='getOperationResult' or ('{schoolId}' in path and any(p.get('name')=='Idempotency-Key' for p in o.get('parameters',[])))
   if requires_pending:
    counts['pendingContracts']+=1
    response=o['responses'].get('202',{}).get('content',{}).get('application/json',{}).get('schema',{})
    if not any(b.get('$ref')=='#/components/schemas/PendingOperationEnvelope' for b in branches(response)):err('PENDING_RESPONSE_UNDECLARED',operation=ident)
   if ident=='recordCourseAttendance':
    if not path.endswith('/cycles/{enrollmentCycle}'):err('ATTENDANCE_CYCLE_PATH')
    pars={p['name']:p for p in o['parameters']}
    if pars.get('If-Match',{}).get('required',True) or 'If-None-Match' not in pars:err('ATTENDANCE_CREATE_PRECONDITION')
 if s['PurchaseCommand']['properties']['selectedOptionKeys'].get('uniqueItems') is not True:err('DUPLICATE_PACK_OPTIONS')
 if s['SegmentManifest']['properties']['expectedChunkIndices'].get('uniqueItems') is not True:err('DUPLICATE_CHUNK_INDICES')
 for k in ['enrollmentDeadline','selfCancellationDeadline']:
  if k not in s['RescheduleCourseCommand']['required']:err('MISSING_RESCHEDULE_DEADLINE',field=k)
 domains={'COURSE_SESSION','COURSE_ENROLLMENT','REQUIREMENT','PURCHASE','ENTITLEMENT','CAPTURE','RECORDING_CHOICE','ADMINISTRATIVE_PROFILE','PROFILE_POLICY'}
 absent=domains-set(s['SyncChange']['properties']['resourceType']['enum'])
 if absent:err('SYNC_DOMAIN_MISSING',domains=sorted(absent))
 if 'INVALIDATE' not in s['SyncChange']['properties']['action']['enum']:err('INVALIDATION_ACTION_MISSING')
 for name,required in [('CourseSession',['requirementTypeSnapshot']),('CourseEnrollment',['acceptedCommercialSnapshot','acceptedSelfCancellationDeadline']),('AttendanceRecord',['enrollmentCycle']),('EntitlementLot',['usableQuantity']),('CapturePublication',['availability']),('Lesson',['commercialRevisionVersion'])]:
  for k in required:
   if k not in s[name]['required']:err('REQUIRED_PROJECTION_FIELD',schema=name,field=k)
 return {'status':'CROSS_CONTRACT_DOCUMENTARY_ONLY','productCodeExercised':False,'version':a['info']['version'],'checks':counts,'errorCount':len(errors),'errors':errors,'passed':not errors,'limitations':['Enveloppes, bornes et présence de clauses seulement ; les règles de service et transactions ne sont pas exécutées.','Pas de validation intégrale du méta-schéma OpenAPI.']}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);args=p.parse_args();r=check(args.root);print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
