#!/usr/bin/env python3
"""Re-run inherited semantic checks on new contract without rewriting historical reports.
Only current version and contiguous test-tail expectations are adapted. Schema rules unchanged.
"""
from pathlib import Path
import argparse,json
R=Path(__file__).resolve().parents[1]
s=(R/'annexes/verifier-v3-7.py').read_text(encoding="utf-8")
for old,new in [("api['info']['version']=='3.7.0'","api['info']['version']=='3.10.0'"),("trace['documentVersion']=='3.7'","trace['documentVersion']=='3.10'"),("range(351,383)","range(351,407)")]:
    assert s.count(old)==1,(old,s.count(old));s=s.replace(old,new)
ns={'__file__':str(R/'annexes/verifier-v3-7.py'),'__name__':'inherited_checks'}
exec(compile(s,str(R/'annexes/verifier-v3-7.py'),'exec'),ns)
r=ns['check'](False);r['version']='3.10';r['currentContractVersion']='3.10.0';r['adaptation']='Current versions and new contiguous T IDs only; substantive inherited checks retained. New file-specific checks run separately.'
p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args()
if args.write_report:(R/'annexes/verification-reference-v3-10.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
