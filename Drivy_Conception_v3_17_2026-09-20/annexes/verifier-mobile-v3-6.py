#!/usr/bin/env python3
"""Check mobile documentation structure. Does NOT exercise the app or assess visual quality.
Python 3.11+, standard library. Run --write-report to save the result.
"""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(__file__).resolve().parents[1]
def check(root:Path=ROOT)->dict:
    errors=[];checks={}
    def load(path):return json.loads((root/path).read_text(encoding='utf-8'))
    mobile=load('annexes/qualification-mobile-v3-4.json')
    source=load('annexes/sources-mobile-v3-4.json')
    build=load('annexes/matrice-build-mobile-v3-4.json')
    trace=load('annexes/traceabilite.json')
    prov=load('annexes/provenance-v3-6.json')
    tokens=load('annexes/tokens-proposition.json')
    spec=(root/'05-realisation/qualification-mobile-ui-ux.md').read_text(encoding="utf-8")
    allmd='\n'.join(p.read_text(encoding="utf-8") for p in root.rglob('*.md'))
    req_ids=[x['id'] for x in mobile['requirements']];case_ids=[x['id'] for x in mobile['cases']]
    src_ids=[x['id'] for x in source['entries']]
    valid_f={x['feature'] for x in trace['features']}
    valid_e={e for x in trace['features'] for e in x['screens']}
    def ensure(cond,kind,detail=None):
        if not cond:errors.append({'type':kind,'detail':detail})
    ensure(req_ids==[f'MX{i:02d}' for i in range(1,17)],'REQUIREMENT_IDS')
    ensure(case_ids==[f'MOB{i:03d}' for i in range(1,53)],'CASE_IDS')
    ensure(src_ids==[f'S{i}' for i in range(62,106)],'SOURCE_IDS')
    source_md=(root/'06-gouvernance/sources.md').read_text(encoding="utf-8")
    for src in source['entries']:
        u=urlparse(src['url']);ensure(u.scheme=='https' and bool(u.netloc),'SOURCE_URL',src['id'])
        ensure(src['consultedAt']=='2026-09-19','SOURCE_DATE',src['id'])
        ensure(f'id="{src["id"].lower()}"' in source_md,'SOURCE_ANCHOR',src['id'])
        ensure(src['url'] in source_md,'SOURCE_PROSE_LINK',src['id'])
    referenced=set()
    for case in mobile['cases']:
        ident=case['id'];ensure(case['status']=='NOT_EXECUTED' and case['evidence'] is None,'UNSUPPORTED_TEST_CLAIM',ident)
        ensure(f'id="{ident.lower()}"' in spec,'CASE_ANCHOR',ident)
        for field in ['title','precondition','procedure','expected']:
            ensure(bool(case[field].strip()) and case[field] in spec,'CASE_PROSE_PARITY',f'{ident}:{field}')
        ensure(bool(case['requirements']) and set(case['requirements'])<=set(req_ids),'CASE_REQUIREMENTS',ident)
        ensure(set(case['features'])<=valid_f and bool(case['features']),'FEATURE_REFERENCE',ident)
        ensure(set(case['screens'])<=valid_e and bool(case['screens']),'SCREEN_REFERENCE',ident)
        ensure(bool(case['platforms']) and set(case['platforms'])<= {'IOS','IPADOS','ANDROID','WEB'},'PLATFORM_REFERENCE',ident)
        referenced.update(case['requirements'])
    ensure(referenced==set(req_ids),'REQUIREMENT_COVERAGE')
    for req in mobile['requirements']:
        ident=req['id'];ensure(f'id="{ident.lower()}"' in spec,'REQUIREMENT_ANCHOR',ident)
        path,_,anchor=req['reference'].partition('#')
        ensure((root/path).is_file(),'REQUIREMENT_FILE',ident)
        if anchor:ensure(f'id="{anchor}"' in (root/path).read_text(encoding="utf-8"),'REQUIREMENT_FILE_ANCHOR',ident)
        ensure(set(req['sources'])<=set(src_ids),'REQUIREMENT_SOURCES',ident)
    ensure(build['status']=='TEMPLATE_NOT_QUALIFIED','BUILD_TEMPLATE_STATUS')
    ensure(len(build['builds'])==6,'BUILD_MATRIX_COUNT')
    for row in build['builds']:
        ensure(row['status']=='NOT_QUALIFIED' and not row['evidence'],'UNSUPPORTED_BUILD_CLAIM',row['platform'])
        ensure(row['artifactSHA256'] is None and row['exactOSVersion'] is None,'BUILD_FACTS_IN_TEMPLATE',row['platform'])
    ensure('minimumTouchTargetLogicalUnits' not in tokens,'AMBIGUOUS_TOUCH_TOKEN')
    ensure(tokens['minimumTouchTargetsByPlatform']=={'webCSS':44,'iOSPoints':44,'AndroidDp':48},'TOUCH_MINIMA')
    ensure(tokens['primaryAndCriticalTouchTargetsByPlatform']=={'webCSS':48,'iOSPoints':48,'AndroidDp':48},'TOUCH_CRITICAL')
    api_hash=hashlib.sha256((root/'04-technique/openapi.yaml').read_bytes()).hexdigest()
    ensure(api_hash==prov['openapiSHA256'],'API_CHANGED')
    ensure(mobile['businessTestsUnchanged']==284 and len(trace['tests'])==350,'BUSINESS_COUNT_EVOLUTION'); ensure(all(t['introducedIn']=='3.5' for t in trace['tests'][284:310]) and all(t['introducedIn']=='3.6' for t in trace['tests'][310:]),'NEW_TEST_PROVENANCE')
    ensure(all(t['status']=='NOT_EXECUTED' for t in trace['tests']),'BUSINESS_TEST_CLAIM')
    anti=(root/'02-experience/qualite-ui-ux-anti-slop.md').read_text(encoding="utf-8")
    ensure(all(f'id="as{i:02d}"' in anti for i in range(1,11)),'ANTI_SLOP_CRITERIA')
    patterns=(root/'02-experience/patterns-mobile-parcours.md').read_text(encoding="utf-8")
    ensure(all(f'id="px{i:02d}"' in patterns for i in range(1,7)),'PATTERNS')
    ensure('DM06' in (root/'README.md').read_text(encoding="utf-8") and 'blocage de publication' in (root/'04-technique/integration-mobile-transverse.md').read_text(encoding="utf-8"),'GLOBAL_DELETION_LIMIT_DISCLOSURE')
    for number in {int(x) for x in re.findall(r'\[S(\d+)\]',allmd)}:
        ensure(f'id="s{number:02d}"' in source_md or f'id="s{number}"' in source_md,'UNDEFINED_SOURCE',number)
    checks.update({'mobileRequirements':len(req_ids),'mobileCasesNotExecuted':len(case_ids),'sourceEntriesTracked':len(src_ids),'newSourceEntriesV34':9,'unqualifiedBuildRows':len(build['builds']),'qualityCriteria':10,'appliedPatterns':6,'apiMatchesCurrentProvenance':api_hash==prov['openapiSHA256'],'apiSHA256':api_hash,'businessScenariosCurrent':310,'businessScenariosInherited':284,'caseProseAndRegistryChecked':True,'touchTokensConsistent':True,'globalDeletionOperationalGateDisclosed':True})
    return {'version':'3.6','status':'DOCUMENTARY_CHECKS_ONLY','productTestsExecuted':False,'checkedAt':'2026-09-19','checks':checks,'errorCount':len(errors),'errors':errors,'passed':not errors,'limitations':['Contrôles de structure/relations, pas exécution des scénarios MOB ou T.','Présence d’une clause ne démontre pas que son implémentation est correcte.','Aucun verdict automatisé sur esthétique, AI slop, conformité juridique ou compatibilité physique.','URLs sources vérifiées syntaxiquement ici ; consultations web séparées dans le registre.']}
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--write-report',action='store_true');args=ap.parse_args()
    report=check()
    if args.write_report:(ROOT/'annexes/verification-mobile-v3-6.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(0 if report['passed'] else 1)
