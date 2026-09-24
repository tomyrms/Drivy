#!/usr/bin/env python3
"""Generate both entry points from the SAME component and route sources. No network."""
from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]; A=R/'DESIGN/atelier'
t=json.loads((R/'annexes/tokens-proposition.json').read_text(encoding='utf-8'))
app='\n'.join((A/f).read_text(encoding='utf-8') for f in ['ui.js','app.js','workspace.js'])
replacements=[('__FIXTURE__',json.loads((A/'fixture.json').read_text(encoding='utf-8'))),('__WORKSPACE_FIXTURE__',json.loads((A/'workspace-fixture.json').read_text(encoding='utf-8'))),('__TOKENS_JSON__',t),('__MAP_JSON__',(A/'map.svg').read_text(encoding='utf-8')),('__DENSE_MAP_JSON__',(A/'map-dense.svg').read_text(encoding='utf-8'))]
for tag,obj in replacements:app=app.replace(tag,json.dumps(obj,ensure_ascii=False).replace('</',r'<\/'))
css=':root{'+''.join(f'--{k}:{v};' for k,v in t['colors']['light'].items())+'}'
template=(A/'template.html').read_text(encoding='utf-8').replace('__COLORS__',css).replace('__STYLE__','\n'.join((A/f).read_text(encoding='utf-8') for f in ['style.css','workspace.css']))
for file,start in [('LECON.html','map'),('APPLICATION.html','home')]:
 s=template.replace('__APP__',app.replace('__START_SCREEN__',start))
 (R/'DESIGN'/file).write_text(s,encoding='utf-8')
 print(json.dumps({'file':'DESIGN/'+file,'bytes':len(s.encode()),'status':'GENERATED_NOT_TESTED'}))
