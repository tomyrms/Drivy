#!/usr/bin/env python3
"""Documentary schemas and isolated reference models. No application or storage service.
Python 3.11+, PyYAML, jsonschema. Current schemas plus unchanged before/after payloads.
"""
from pathlib import Path
from copy import deepcopy
from urllib.parse import urlsplit
import argparse,json,hashlib
import yaml
from jsonschema import Draft202012Validator,FormatChecker
R=Path(__file__).resolve().parents[1]
def acceptable_origin(url,allowed):
    """Illustrative policy for fixtures, NOT a production URL/security implementation."""
    try:
        if any(ord(c)<33 for c in url) or '#' in url or '\\' in url:return False
        p=urlsplit(url)
        if p.scheme!='https' or p.username is not None or p.password is not None or not p.hostname:return False
        return (p.scheme,p.hostname.lower(),p.port or 443) in allowed
    except (TypeError,ValueError):return False

def promote(state,expected_version,generation,scan_ok,rights):
    """Pure state transition over fictitious fields, not SQL/CAS against a live DB."""
    old=deepcopy(state)
    if state['status']!='QUARANTINED' or state['version']!=expected_version or state['generation']!=generation or not scan_ok or not rights:
        return old,False
    return {**old,'status':'READY','version':old['version']+1},True

def retry_action(status,object_present,ticket_valid,intent_retained,rights):
    if not rights:return 'REFUSE'
    if status=='DELETED' or not intent_retained:return 'EXPLICIT_NEW_INTENT'
    if status in ('QUARANTINED','READY'):return 'READ_CURRENT'
    if object_present:return 'FINALIZE_CURRENT'
    return 'PUT_SAME_BODY' if ticket_valid else 'EXPLICIT_NEW_INTENT'

def run():
    a=yaml.safe_load((R/'04-technique/openapi.yaml').read_text(encoding="utf-8"));old=json.loads((R/'annexes/schemas-base-v3-9.json').read_text(encoding="utf-8"))
    cases=json.loads((R/'annexes/cas-contrats-v3-10.json').read_text(encoding="utf-8"))['cases'];comparison=[];checks=[];models=[]
    def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
    def valid(components,k,value):
        if k not in components['schemas']:return None
        schema={'$schema':'https://json-schema.org/draft/2020-12/schema','allOf':[components['schemas'][k]],'components':components}
        return not list(Draft202012Validator(schema,format_checker=FormatChecker()).iter_errors(value))
    for c in cases:
        before=valid(old,c['schema'],c['value']);after=valid(a['components'],c['schema'],c['value'])
        comparison.append({'id':c['id'],'title':c['title'],'schema':c['schema'],'expectedValid':c['expectedValid'],'beforeValid':before,'afterValid':after,'passed':after==c['expectedValid'],'meaning':'Identical JSON payload, not an application execution'})
    check('All_current_schema_cases_match_expectation',all(c['passed'] for c in comparison))
    check('Same_invalid_payloads_now_rejected',any(c['expectedValid'] is False and c['beforeValid'] is True and c['afterValid'] is False for c in comparison))
    op={o['operationId']:o for item in a['paths'].values() for o in item.values() if isinstance(o,dict) and 'operationId'in o}
    types=op['readExportContent']['responses']['200']['content']
    check('Exports_expose_CSV_and_ZIP',set(types)=={'text/csv','application/zip'})
    for name in ['readDocumentContent','readAssetContent','readExportContent']:
        resp=op[name]['responses']['200']
        check(name+'_no_store',resp['headers']['Cache-Control']['schema']=={'type':'string','const':'private, no-store'})
        check(name+'_no_json_success','application/json' not in resp['content'])
    check('Methods_routes_not_artificially_added',len(op)==201)
    check('Contract_and_doc_registry_versions',a['info']['version']=='3.11.0' and json.loads((R/'annexes/traceabilite.json').read_text(encoding="utf-8"))['apiContractVersion']=='3.11.0')
    def model(name,actual,expected):models.append({'name':name,'actual':actual,'expected':expected,'passed':actual==expected})
    allowed={('https','staging.drivy.invalid',443)}
    for name,url,expected in [
        ('origin exact','https://staging.drivy.invalid/object?signature=fictif',True),
        ('port standard explicite','https://staging.drivy.invalid:443/object',True),
        ('suffixe trompeur','https://staging.drivy.invalid.attacker.invalid/object',False),
        ('userinfo','https://user@staging.drivy.invalid/object',False),
        ('http','http://staging.drivy.invalid/object',False),
        ('port inconnu','https://staging.drivy.invalid:444/object',False),
        ('fragment','https://staging.drivy.invalid/object#secret',False),
        ('fragment vide','https://staging.drivy.invalid/object#',False),
        ('controle CRLF','https://staging.drivy.invalid/\r\nobject',False),
        ('origine API non stockage','https://api.drivy.invalid/object',False)]:model(name,acceptable_origin(url,allowed),expected)
    original={'status':'QUARANTINED','version':2,'generation':'g1'}
    for name,state,version,gen,ok,rights,expected in [
        ('promotion courante',original,2,'g1',True,True,True),
        ('suppression avant résultat',{**original,'status':'DELETED','version':3},2,'g1',True,True,False),
        ('ancienne génération',{**original,'generation':'g2'},2,'g1',True,True,False),
        ('ancienne version',original,1,'g1',True,True,False),
        ('scanner indisponible',original,2,'g1',False,True,False),
        ('droit de traitement révoqué',original,2,'g1',True,False,False)]:
        result,applied=promote(state,version,gen,ok,rights);model(name,{'applied':applied,'unchanged':result==state},{'applied':expected,'unchanged':not expected})
    for name,args,expected in [
        ('octets reçus URL expirée',('PENDING_UPLOAD',True,False,True,True),'FINALIZE_CURRENT'),
        ('octets absents ticket valide',('PENDING_UPLOAD',False,True,True,True),'PUT_SAME_BODY'),
        ('octets absents URL expirée',('PENDING_UPLOAD',False,False,True,True),'EXPLICIT_NEW_INTENT'),
        ('déjà validé',('READY',True,False,True,True),'READ_CURRENT'),
        ('intention nettoyée',('DELETED',False,False,False,True),'EXPLICIT_NEW_INTENT'),
        ('droits perdus',('READY',True,True,True,False),'REFUSE')]:model(name,retry_action(*args),expected)
    check('Reference_models',all(m['passed'] for m in models))
    report={'version':'3.13','scope':'SCHEMAS_AND_ISOLATED_DOCUMENTARY_MODELS','productCodeExercised':False,'storageRequestsExecuted':False,'schemaCases':comparison,'sameInvalidNowRejected':sum(c['expectedValid'] is False and c['beforeValid'] is True and c['afterValid'] is False for c in comparison),'newCases':len(cases),'modelCases':models,'modelCount':len(models),'checks':checks,'passed':all(c['passed'] for c in checks),'limitations':['No real S3, HTTP cache, file parser, Swift build, network capture or database transaction executed.','Models illustrate a proposed policy; they do not prove the production code uses it.','JSON Schema shape does not enforce origin allowlists, compute SHA-256 or prevent concurrent writes.']}
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args();r=run()
    if args.write_report:(R/'annexes/verification-fichiers-v3-13.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
