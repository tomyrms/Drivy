#!/usr/bin/env python3
"""Structural checks and negative tests. Not a Swift, security or usability certification."""
from pathlib import Path
import argparse,copy,datetime,hashlib,json,re,subprocess,sys
R=Path(__file__).resolve().parents[1]
def errors_for(c):
 errors=[];rows=c.get('coverage',[]);ids=[x.get('screen') for x in rows]
 if sorted(ids)!=[f'E{i:02}' for i in range(1,50)]:errors.append('49 unique canonical screens required')
 for x in rows:
  if not x.get('components') or any(not re.fullmatch(r'DS(?:0[1-9]|1[0-9]|2[0-5])',v) for v in x['components']):errors.append('Unknown or missing component '+str(x.get('screen')))
  if x.get('nativeStatus')!='NOT_EXECUTED':errors.append('False native qualification')
 if c.get('currentScreens')!=sum(bool(x.get('currentVisuals')) for x in rows):errors.append('Current screen count mismatch')
 if c.get('currentCompositions')!=sum(len(x.get('currentVisuals',[])) for x in rows):errors.append('Composition count mismatch')
 if c.get('illustratedScreens')!=sum(bool(x.get('visuals')) for x in rows):errors.append('Illustration count mismatch')
 return errors

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--write-report',action='store_true');args=ap.parse_args();checks=[]
 def ck(name,value,detail=None):checks.append({'name':name,'passed':bool(value),'detail':detail})
 c=json.loads((R/'DESIGN/couverture-ecrans.json').read_text(encoding='utf-8'));u=json.loads((R/'DESIGN/composants-usage.json').read_text(encoding='utf-8'))
 ck('49 screens with explicit rendering status and canonical components',not errors_for(c),errors_for(c))
 ck('17 current screens, 20 compositions and 23 any-illustrated', (c['currentScreens'],c['currentCompositions'],c['illustratedScreens'])==(17,20,23))
 usage=u['screenUsage'];usage_ids=set(usage) if isinstance(usage,dict) else {x['screen'] for x in usage}
 ck('All 49 screens appear in component usage',usage_ids=={f'E{i:02}' for i in range(1,50)})
 ui=(R/'DESIGN/atelier/ui.js').read_text(encoding='utf-8');app=(R/'DESIGN/atelier/app.js').read_text(encoding='utf-8');work=(R/'DESIGN/atelier/workspace.js').read_text(encoding='utf-8');gen=(R/'annexes/generer-atelier.py').read_text(encoding='utf-8')
 ck('Single component-library definition',len(re.findall(r'const UI\s*=',ui+app+work))==1)
 for factory in ['observationRow','field','sheetHeader','dialog']:
  ck('Map delegates '+factory,'UI.'+factory+'(' in app)
 ck('Workspace uses shared observation, field and modal',all('UI.'+k+'(' in work for k in ['observationRow','field','modal']))
 ck('Both entries include same source files',all("'"+f+"'" in gen for f in ['ui.js','app.js','workspace.js']))
 baseline=json.loads((R/'annexes/invariants-source-v3-16.json').read_text(encoding='utf-8'))
 diffs=[rel for rel,sha in baseline.items() if hashlib.sha256((R/rel).read_bytes()).hexdigest()!=sha];ck('API, tokens and business registry unchanged',not diffs,diffs)
 before={f:(R/'DESIGN'/f).read_bytes() for f in ['APPLICATION.html','LECON.html']}
 subprocess.run([sys.executable,str(R/'annexes/generer-atelier.py')],check=True,capture_output=True)
 ck('Current compiled files regenerate identically',all((R/'DESIGN'/f).read_bytes()==b for f,b in before.items()))
 ck('No external runtime scripts or fonts',not re.search(r'<script[^>]+src\s*=|@import|https?://[^\s"\']+\.(woff|ttf)',before['APPLICATION.html'].decode()))
 # Negative tests are in-memory mutations, never edits to released files.
 bad=copy.deepcopy(c);bad['coverage'].append(copy.deepcopy(bad['coverage'][0]));ck('Negative: duplicate screen rejected',bool(errors_for(bad)))
 bad=copy.deepcopy(c);bad['coverage'][0]['components']=['DS99'];ck('Negative: unknown component rejected',bool(errors_for(bad)))
 bad=copy.deepcopy(c);bad['coverage'][0]['nativeStatus']='PASSED';ck('Negative: unexecuted native status enforced',bool(errors_for(bad)))
 bad=copy.deepcopy(c);bad['currentScreens']=49;ck('Negative: inflated coverage rejected',bool(errors_for(bad)))
 ck('Negative: a modified baseline would be rejected',hashlib.sha256((R/'annexes/tokens-proposition.json').read_bytes()+b' ').hexdigest()!=baseline['annexes/tokens-proposition.json'])
 result={'version':'3.17','executedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'DOCUMENTARY_SOURCE_INVARIANTS_NOT_PRODUCT_TESTS','passed':all(x['passed'] for x in checks),'checks':checks,'errorCount':sum(not x['passed'] for x in checks)}
 if args.write_report:(R/'annexes/verification-composants-v3-17.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
