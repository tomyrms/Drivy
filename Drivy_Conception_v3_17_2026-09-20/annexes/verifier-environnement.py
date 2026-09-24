#!/usr/bin/env python3
"""Preflight for required documentary checks. A missing format is an explicit failure."""
from __future__ import annotations
import argparse, importlib.metadata, json, platform, sys
from pathlib import Path
R=Path(__file__).resolve().parents[1]
SENTINELS={
 'date-time':('2026-09-19T10:00:00Z','demain'),
 'date':('2026-09-19','demain'),
 'uuid':('00000000-0000-4000-8000-000000000001','pas-un-uuid'),
 'email':('test@example.invalid','sans-arobase'),
 'uri':('https://drivy.invalid/document','pas une URI'),
}
def check_formats(checker):
 checks=[]
 for fmt,(good,bad) in SENTINELS.items():
  exists=fmt in checker.checkers
  checks.append({'format':fmt,'registered':exists,'positiveAccepted':checker.conforms(good,fmt) if exists else False,'negativeRejected':not checker.conforms(bad,fmt) if exists else False})
 return checks

def run():
 checks=[];errors=[];versions={}
 for line in (R/'requirements.txt').read_text(encoding='utf-8').splitlines():
  line=line.strip()
  if not line or line.startswith('#'):continue
  name,expected=line.split('==',1)
  try:actual=importlib.metadata.version(name)
  except importlib.metadata.PackageNotFoundError:actual=None
  versions[name]={'installed':actual,'locked':expected};ok=actual==expected
  if not ok:errors.append({'dependency':name,'installed':actual,'expected':expected})
 try:
  from jsonschema import FormatChecker
  checks=check_formats(FormatChecker())
  errors.extend(x for x in checks if not(x['registered'] and x['positiveAccepted'] and x['negativeRejected']))
  broken=FormatChecker();broken.checkers.pop('date-time',None)
  self_test=not all(x['registered'] and x['positiveAccepted'] and x['negativeRejected'] for x in check_formats(broken))
  if not self_test:errors.append({'preflightSelfTest':'FAILED'})
 except ImportError as exc:
  errors.append({'import':str(exc)});self_test=False
 if sys.version_info<(3,11):errors.append({'python':'3.11 or newer required'})
 return {'version':'3.16','scope':'DOCUMENTARY_ENVIRONMENT_ONLY','python':sys.version.split()[0],'platform':platform.platform(),'dependencies':versions,'formats':checks,'missingFormatDetectedBySelfTest':self_test,'passed':not errors,'errorCount':len(errors),'errors':errors,'limits':['Only the reported runtime was executed. Explicit UTF-8 does not constitute a Windows qualification.','Binary format is a transport annotation, not a JSON string content validator.']}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args();result=run()
 if args.write_report:(R/'annexes/verification-environnement-v3-16.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(0 if result['passed'] else 1)
