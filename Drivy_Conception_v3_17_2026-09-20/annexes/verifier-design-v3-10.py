#!/usr/bin/env python3
"""Design documentation checks: values, generated assets and visual coverage.
No application, geolocation service, native accessibility or user test.
"""
from pathlib import Path
import argparse,hashlib,json,re
from bs4 import BeautifulSoup
R=Path(__file__).resolve().parents[1]
def run():
    checks=[];errors=[]
    def check(name,ok,detail=None):
        c={'name':name,'passed':bool(ok),'detail':detail};checks.append(c)
        if not ok:errors.append(c)
    tokens=json.loads((R/'annexes/tokens-proposition.json').read_text(encoding="utf-8"));scenes=json.loads((R/'DESIGN/scenes.json').read_text(encoding="utf-8"))['scenes'];coverage=json.loads((R/'DESIGN/couverture-ecrans.json').read_text(encoding="utf-8"));ratios=json.loads((R/'DESIGN/contrastes.json').read_text(encoding="utf-8"));provenance=json.loads((R/'annexes/provenance-v3-10.json').read_text(encoding="utf-8"))
    text=(R/'02-experience/design-system.md').read_text(encoding="utf-8");html=(R/'DESIGN/MAQUETTES.html').read_text(encoding="utf-8")
    check('selected_option_A_status','direction_A_selected' in tokens['status'])
    check('base_palette_matches_selected_direction',all(tokens['colors']['light'][k]==v for k,v in {'canvas':'#F7F8FA','surface':'#FFFFFF','text':'#18212B','accent':'#245BD6'}.items()))
    def luminance(h):
        c=[int(h[i:i+2],16)/255 for i in (1,3,5)];c=[v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in c]
        return sum(a*b for a,b in zip(c,[.2126,.7152,.0722]))
    actual=[]
    for c in ratios['checks']:
        mode=tokens['colors'][c['mode']];a=luminance(mode[c['foreground']]);b=luminance(mode[c['background']]);r=(max(a,b)+.05)/(min(a,b)+.05)
        actual.append({**c,'recalculated':r,'matches':abs(r-c['ratio'])<1e-10,'actualPass':r>=c['threshold']})
    check('36_contrast_pairs_recomputed',len(actual)==36 and all(c['matches'] and c['actualPass'] for c in actual))
    check('canonical_palette_in_document_and_prototype',all(v in text and f'--{k}:{v};' in html for mode in tokens['colors'].values() for k,v in mode.items()))
    css=':root{color-scheme:light;'+''.join(f'--{k}:{v};' for k,v in tokens['colors']['light'].items())+'}\n:root[data-theme="dark"]{color-scheme:dark;'+''.join(f'--{k}:{v};' for k,v in tokens['colors']['dark'].items())+'}'
    expected=(R/'DESIGN/assets/maquettes.template.html').read_text(encoding="utf-8").replace('__TOKENS__',css).replace('__JSON_TOKENS__',json.dumps(tokens,ensure_ascii=False)).replace('__JSON_SCENES__',json.dumps(scenes,ensure_ascii=False)).replace('__JSON_REPLAY__',json.dumps(json.loads((R/'DESIGN/replay-fictif.json').read_text(encoding="utf-8")),ensure_ascii=False))
    check('prototype_exactly_generated_from_canonical_sources',expected==html)
    ids=[s['id'] for s in scenes];keys=[s['key'] for s in scenes]
    check('15_unique_scenes',len(scenes)==15 and len(set(ids))==15 and len(set(keys))==15)
    eids={f'E{i:02}' for i in range(1,50)};check('49_screen_coverage_no_duplicates',len(coverage['coverage'])==49 and {e['screen'] for e in coverage['coverage']}==eids)
    links={(e['screen'],v) for e in coverage['coverage'] for v in e['visuals']};actual_links={(e,s['id']) for s in scenes for e in s['screens']}
    check('coverage_matches_actual_scene_declarations',links==actual_links,{'listed':len(links),'scenes':len(actual_links)})
    check('16_illustrated_33_not_drawn',coverage['illustratedScreens']==16 and sum(bool(e['visuals']) for e in coverage['coverage'])==16)
    ds=(R/'DESIGN/02-composants.md').read_text(encoding="utf-8")+'\n'+text
    component_ids={f'DS{i:02}' for i in range(1,25)}
    check('scene_components_have_specifications',all(c in component_ids and c in ds for s in scenes for c in s['components']))
    check('no_font_binaries',not any(p.suffix.lower() in {'.ttf','.otf','.woff','.woff2'} for p in R.rglob('*')))
    soup=BeautifulSoup(html,'html.parser')
    check('no_external_runtime_resources',not soup.select('script[src],link[rel="stylesheet"],iframe') and not any(str(e.get('src','')).startswith(('http:','https:','//')) for e in soup.select('[src]')))
    check('no_runtime_geolocation_or_network_calls',not re.search(r'navigator\.geolocation|\bfetch\s*\(|new\s+XMLHttpRequest|new\s+WebSocket',html))
    check('api_matches_current_provenance',hashlib.sha256((R/'04-technique/openapi.yaml').read_bytes()).hexdigest()==provenance['apiSHA256'])
    paths=['planche-iphone-clair.png','planche-iphone-sombre.png','ipad-capture-clair.png','web-eleves-clair.png','sans-gps-clair.png','cours-clair.png']
    check('six_visual_exports_exist',all((R/'DESIGN/assets'/p).is_file() for p in paths))
    # Old palette is legal in explicitly historical comparison, not canonical definition.
    check('old_palette_absent_from_active_system',not re.search(r'#F6F4EF|#145B63',text,re.I))
    check('direction_not_open_in_decision_register','D05 · Cartographie native, option A' in (R/'06-gouvernance/glossaire-decisions-questions.md').read_text(encoding="utf-8"))
    bindings=json.loads((R/'DESIGN/contrat-interactions.json').read_text(encoding="utf-8"))
    check('interaction_bindings_match_screen_and_visual_catalog',all(set(e['screens'])<=eids and set(e['visuals'])<=set(ids) and e['appStatus']=='NOT_EXECUTED' for e in bindings['entries']))
    check('UX21_to_UX32_documented_not_executed',all('UX'+str(i) in (R/'DESIGN/06-livraison-validation.md').read_text(encoding="utf-8") for i in range(21,33)))
    summary=(R/'00-synthese.md').read_text(encoding="utf-8");catalog=(R/'01-fonctionnalites-prevues.md').read_text(encoding="utf-8")
    check('entrypoints_use_current_review', 'La V3.10 remplace la V3.9' in summary and 'La V3.7 remplace la V3.6' not in summary and '[Rapport de revue](06-gouvernance/audit-corrections-v3-10.md)' in catalog)
    return {'version':'3.10','scope':'DESIGN_DOCUMENTATION_ONLY','nativeTestsExecuted':False,'checks':checks,'contrastPairs':actual,'scenes':len(scenes),'illustratedScreenReferences':16,'notDrawnScreenReferences':33,'passed':not errors,'errors':errors,'limits':['Opaque sRGB contrast only; no global WCAG certification.','Screenshots are browser compositions, not SwiftUI, MapKit or device tests.','Business rules and native behaviour are not exercised by these checks.']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-design-v3-10.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps({k:v for k,v in r.items() if k!='contrastPairs'},ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
