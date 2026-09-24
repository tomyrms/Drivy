#!/usr/bin/env python3
"""Retained mobile/Swift documentary checks with explicit current registries and counts."""
from pathlib import Path
import json,argparse
R=Path(__file__).resolve().parents[1]
def run():
    reports={}
    for key,file in [('mobile','verifier-mobile-v3-7.py'),('swift','verifier-swift-v3-7.py')]:
        s=(R/'annexes'/file).read_text(encoding="utf-8").replace('qualification-mobile-v3-7.json','qualification-mobile-v3-13.json').replace('provenance-v3-7.json','provenance-v3-13.json')
        if key=='mobile':
            for old,new in [('range(1,61)','range(1,69)'),("len(trace['tests'])==382","len(trace['tests'])==422"),("trace['tests'][350:])","trace['tests'][350:382])")]:
                assert old in s,old;s=s.replace(old,new)
            marker="ensure(all(t['status']=='NOT_EXECUTED' for t in trace['tests']),'BUSINESS_TEST_CLAIM')"
            extra="ensure(all(t['introducedIn']=='3.10' for t in trace['tests'][382:406]),'PREVIOUS_TEST_PROVENANCE'); ensure(all(t['introducedIn']=='3.11' for t in trace['tests'][406:]),'CURRENT_TEST_PROVENANCE')"
            assert marker in s;s=s.replace(marker,marker+'; '+extra)
        else:
            assert s.count('len(paths)==65')==1;s=s.replace('len(paths)==65','len(paths)==80')
            # V3.13 uses a normalized decision status instead of the legacy wording.
            assert s.count("'ACCEPTÉ PAR LE PORTEUR'")==1;s=s.replace("'ACCEPTÉ PAR LE PORTEUR'", "'### D11 · Swift natif confirmé pour Apple'")
            # Historical journal list remains explicit; V3.9 did not use the abandoned stack.
        ns={'__file__':str(R/'annexes'/file),'__name__':'inherited_mobile_checks'}
        exec(compile(s,str(R/'annexes'/file),'exec'),ns);reports[key]=ns['check']();reports[key]['sourceCheckerVersion']='3.7';reports[key]['version']='3.13'
    return {'version':'3.13','scope':'MOBILE_SWIFT_DOCUMENTATION_ONLY','nativeTestsExecuted':False,'reports':reports,'passed':all(r['passed'] for r in reports.values()),'adaptation':'Current registry/provenance, exact T/MOB and document counts; previous assertions retained.'}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-mobile-swift-v3-13.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
