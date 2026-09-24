#!/usr/bin/env python3
"""V3.6 documentation consistency checks. Does not compile Swift or run Drivy."""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
HISTORICAL={
 '06-gouvernance/sources.md',
 '06-gouvernance/audit-corrections-v3-6.md','06-gouvernance/audit-corrections-v3-5.md',
 '06-gouvernance/changements-v2.md','06-gouvernance/changements-v3.md',
 '06-gouvernance/changements-v3-3.md','06-gouvernance/changements-v3-4.md',
 '06-gouvernance/audit-corrections-v3-1.md','06-gouvernance/audit-corrections-v3-2.md',
}
PATTERN=re.compile(r'\bExpo\b|\bRN\b|React Native|runtime JS|expo-location|expo-maps|expo-sqlite|\bEAS\b|\bSecureStore\b|\bAsyncStorage\b')
def check(root=ROOT):
 errors=[];tests=[]
 def expect(name,cond,details=None):
  tests.append({'check':name,'passed':bool(cond),'details':details})
  if not cond:errors.append({'check':name,'details':details})
 paths=sorted(root.rglob('*.md'));occ=[];active=0
 for p in paths:
  rel=p.relative_to(root).as_posix()
  if rel in HISTORICAL:continue
  active+=1
  for num,line in enumerate(p.read_text(encoding="utf-8").splitlines(),1):
   if PATTERN.search(line):occ.append({'file':rel,'line':num,'text':line})
 expect('Legacy_mobile_stack_absent_from_active_reference',not occ,{'activeDocuments':active,'matches':occ,'excludedFiles':sorted(HISTORICAL)})
 for name in ['annexes/qualification-mobile-v3-4.json','annexes/matrice-build-mobile-v3-4.json']:
  t=(root/name).read_text(encoding="utf-8");expect('Native_registry_no_legacy_stack:'+name,not PATTERN.search(t))
 architecture=(root/'04-technique/architecture-client-swift.md').read_text(encoding="utf-8")
 for text in ['Swift natif','SwiftUI','Core Location','MapKit','URLSession','Keychain','SQLCipher','MainActor','await','Swift Testing','XCTest','GA0']:
  expect('Native_architecture_clause:'+text,text in architecture)
 expect('Native_decision_accepted','ACCEPTÉ PAR LE PORTEUR' in (root/'06-gouvernance/glossaire-decisions-questions.md').read_text(encoding="utf-8"))
 matrix=json.loads((root/'annexes/matrice-build-mobile-v3-4.json').read_text(encoding="utf-8"))
 expect('Android_not_required_for_Apple_G0',matrix['policy']['androidBuildRequiredForAppleG0'] is False)
 apple=[r for r in matrix['builds'] if not r['platform'].startswith('Android')]
 android=[r for r in matrix['builds'] if r['platform'].startswith('Android')]
 expect('Four_Apple_rows_native_unqualified',len(apple)==4 and all(r['architectureDecision']=='SWIFT_NATIVE_ACCEPTED' and r['status']=='NOT_QUALIFIED' and r['swiftCompilerVersion'] is None and not r['evidence'] for r in apple))
 expect('Two_Android_rows_future_unqualified',len(android)==2 and all(r['implementationPhase']=='FUTURE_GA0' and r['status']=='NOT_QUALIFIED' and not r['evidence'] for r in android))
 expect('No_legacy_runtime_fields',all(not(set(r)&{'expoSDK','reactNativeVersion','nativeRuntimeVersion'}) for r in matrix['builds']))
 mobile=json.loads((root/'annexes/qualification-mobile-v3-4.json').read_text(encoding="utf-8"))
 expect('Twelve_added_Swift_cases', [c['id'] for c in mobile['cases'][40:]]==[f'MOB{x:03d}' for x in range(41,53)] and all(c['platforms']==['IOS','IPADOS'] and c['status']=='NOT_EXECUTED' and c['evidence'] is None for c in mobile['cases'][40:]))
 legacy_sources={'S70','S71','S72','S74','S75','S76','S80','S89','S96'}
 expect('Current_requirements_no_legacy_framework_sources',not any(legacy_sources & set(r['sources']) for r in mobile['requirements']))
 provenance=json.loads((root/'annexes/provenance-v3-6.json').read_text(encoding="utf-8"));sha=hashlib.sha256((root/'04-technique/openapi.yaml').read_bytes()).hexdigest()
 expect('OpenAPI_matches_current_provenance',sha==provenance['openapiSHA256'])
 expect('No_native_build_claimed',provenance['nativeBuildExecuted'] is False and provenance['applicationCodeModified'] is False)
 expect('Current_markdown_count',len(paths)==64,len(paths))
 expect('Global_deletion_operational_gate_explicit','blocage de publication' in (root/'04-technique/integration-mobile-transverse.md').read_text(encoding="utf-8") and 'DM06' in (root/'README.md').read_text(encoding="utf-8"))
 return {'version':'3.6','scope':'DOCUMENTATION_NOT_SWIFT_COMPILATION','productTestsExecuted':False,'checks':tests,'passed':not errors,'errorCount':len(errors),'errors':errors,'limitations':['Lexical and structural checks do not prove all semantic consistency.','No native code, permissions, OS behaviour or encryption was executed.','Historical journals and source register deliberately retain previous technology names.']}
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--write-report',action='store_true');args=parser.parse_args();result=check()
 if args.write_report:(ROOT/'annexes/verification-swift-v3-6.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
 print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(0 if result['passed'] else 1)
