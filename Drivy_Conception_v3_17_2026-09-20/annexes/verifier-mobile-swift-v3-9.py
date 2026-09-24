#!/usr/bin/env python3
"""Re-run retained mobile and Swift documentation assertions on dossier 3.9.
Only the expected Markdown inventory changes from 65 to 74 in Swift checks.
No native compilation, GPS or mobile product tests are performed.
"""
from pathlib import Path
import json,argparse
R=Path(__file__).resolve().parents[1]
def run():
    reports={}
    for key,file in [('mobile','verifier-mobile-v3-7.py'),('swift','verifier-swift-v3-7.py')]:
        s=(R/'annexes'/file).read_text(encoding="utf-8")
        if key=='swift':
            assert s.count('len(paths)==65')==1
            s=s.replace('len(paths)==65','len(paths)==74')
        ns={'__file__':str(R/'annexes'/file),'__name__':'inherited_mobile_checks'}
        exec(compile(s,str(R/'annexes'/file),'exec'),ns)
        reports[key]=ns['check']()
    return {'version':'3.9','scope':'MOBILE_SWIFT_DOCUMENTATION_ONLY','adaptation':'Only expected Markdown count 65 to 74; native decisions, API hashes and not-executed test statuses retained.','nativeTestsExecuted':False,'reports':reports,'passed':all(r['passed'] for r in reports.values())}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-mobile-swift-v3-9.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
