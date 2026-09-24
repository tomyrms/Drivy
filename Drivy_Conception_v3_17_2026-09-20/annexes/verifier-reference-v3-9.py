#!/usr/bin/env python3
"""Run inherited 3.7 contract checks with the document registry at 3.9.
Only the documentary-version assertion is adapted. The API remains 3.7.0.
Does not rewrite historical comparison reports or exercise the application.
"""
from pathlib import Path
import argparse,json
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args()
s=(R/'annexes/verifier-v3-7.py').read_text(encoding="utf-8")
old="trace['documentVersion']=='3.7'";new="trace['documentVersion']=='3.9'"
assert s.count(old)==1,'Expected a single documented version assertion'
ns={'__file__':str(R/'annexes/verifier-v3-7.py'),'__name__':'inherited_contract_checks'}
exec(compile(s.replace(old,new),str(R/'annexes/verifier-v3-7.py'),'exec'),ns)
report=ns['check'](False);report['version']='3.9';report['inheritedContractVersion']='3.7.0';report['adaptation']='Only trace.documentVersion assertion, 3.7 to 3.9. No application tests.'
if a.write_report:(R/'annexes/verification-reference-v3-9.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(0 if report['passed'] else 1)
