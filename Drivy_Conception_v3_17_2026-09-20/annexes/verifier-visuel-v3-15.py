#!/usr/bin/env python3
"""Structural invariants of the focused visual revision, not product tests."""
from pathlib import Path
import argparse,json,re,hashlib,xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
R=Path(__file__).resolve().parents[1]
def run():
    checks=[]
    def ck(name,ok,details=None):checks.append(dict(check=name,passed=bool(ok),details=details))
    provenance=json.loads((R/'annexes/provenance-v3-15.json').read_text(encoding='utf-8'))
    for path,digest in provenance['unchangedArtifacts'].items():
        ck('Unchanged '+path,hashlib.sha256((R/path).read_bytes()).hexdigest()==digest)
    a=R/'DESIGN/atelier';tokens=json.loads((R/'annexes/tokens-proposition.json').read_text(encoding='utf-8'))
    app=(a/'app.js').read_text(encoding='utf-8')
    for tag,obj in [('__FIXTURE__',json.loads((a/'fixture.json').read_text(encoding='utf-8'))),('__TOKENS_JSON__',tokens),('__MAP_JSON__',(a/'map.svg').read_text(encoding='utf-8'))]:
        app=app.replace(tag,json.dumps(obj,ensure_ascii=False).replace('</',r'<\/'))
    css=':root{'+''.join(f'--{k}:{v};' for k,v in tokens['colors']['light'].items())+'}'
    expected=(a/'template.html').read_text(encoding='utf-8').replace('__COLORS__',css).replace('__STYLE__',(a/'style.css').read_text(encoding='utf-8')).replace('__APP__',app)
    rendered=(R/'DESIGN/LECON.html').read_text(encoding='utf-8')
    ck('Generated atelier equals its current sources',rendered==expected)
    soup=BeautifulSoup(rendered,'html.parser')
    ck('No remote scripts, fonts or styles required',not soup.select('script[src],link[rel=stylesheet],iframe'))
    ck('Four review views only',len(soup.select('[data-view]'))==4)
    ck('Prototype limitation outside application canvas',bool(soup.select_one('.sidebar .disclaimer')) and not soup.select_one('#device .disclaimer'))
    ck('No API calls or persistence are implemented',not re.search(r'fetch\s*\(|XMLHttpRequest|localStorage|sessionStorage|navigator\.geolocation',app))
    ck('Reduced motion is implemented','prefers-reduced-motion' in (a/'style.css').read_text(encoding='utf-8'))
    vectors=sorted((R/'DESIGN/vecteurs').glob('*.svg'));ck('Eight static vector exports',len(vectors)==8)
    for p in vectors:
        root=ET.parse(p).getroot();nodes=list(root.iter());tags=[e.tag.split('}')[-1] for e in nodes]
        ck(p.name+' is XML, with editable text and no bitmap/font payload','text' in tags and 'image' not in tags and not re.search(r'base64|font-face|<foreignObject',p.read_text(encoding='utf-8')))
    ck('Brand spelling in current prototype','Drivy' in rendered and not re.search('drivey',rendered,re.I))
    count=len(list(R.rglob('*.md')))
    ck('README current count',f'{count} documents Markdown' in (R/'README.md').read_text(encoding='utf-8'))
    ck('Current guide prioritises atelier','LECON.html' in (R/'COMMENCER_ICI.md').read_text(encoding='utf-8'))
    ck('Complementary gallery links to current atelier','LECON.html' in (R/'DESIGN/MAQUETTES.html').read_text(encoding='utf-8'))
    ck('Direction approval does not invent Figma delivery','non connecté' in (R/'DESIGN/PASSAGE_FIGMA.md').read_text(encoding='utf-8').lower() or 'pas connecté' in (R/'DESIGN/PASSAGE_FIGMA.md').read_text(encoding='utf-8').lower())
    return {'version':'3.15','scope':'STRUCTURAL_DOCUMENTARY_CHECKS_ONLY','passed':all(x['passed'] for x in checks),'errorCount':sum(not x['passed'] for x in checks),'checks':checks,'markdownDocuments':count,'figmaImportExecuted':False,'nativeTestsExecuted':False}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-visuel-v3-15.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
