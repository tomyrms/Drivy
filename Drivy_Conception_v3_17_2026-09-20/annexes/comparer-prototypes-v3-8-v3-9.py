#!/usr/bin/env python3
"""Compare identical user intents on two HTML prototypes. Source path is explicit.
Read-only comparison; not a server or native security test.
"""
from pathlib import Path
import argparse,json,shutil
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
def inspect(root,exe=None):
 results={}
 with sync_playwright() as pw:
  b=pw.chromium.launch(executable_path=exe or shutil.which('chromium'),headless=True,args=['--no-sandbox']);p=b.new_page(viewport={'width':1440,'height':1100});p.set_default_timeout(5000)
  def reset(k):p.goto('about:blank');p.set_content((root/'DESIGN/MAQUETTES.html').read_text(encoding="utf-8"));p.evaluate('(k)=>{scene=k;render()}',k)
  reset('agenda');p.get_by_role('button',name='Consulter la leçon').click();p.wait_for_function('scene!=="agenda"')
  results['student_has_no_staff_commands']={'passed':p.locator('[data-action=start],[data-action=stop],[data-action=toBilan]').count()==0,'destination':p.evaluate('scene')}
  reset('capture');p.locator('#stage .topbar [data-scene="seance"]').click();p.wait_for_function('scene==="seance"')
  if p.locator('[data-action=openCapture]').count():p.locator('[data-action=openCapture]').first.click()
  else:p.locator('[data-action=start]').click();p.locator('[data-action=demoStart]').click()
  p.wait_for_function('scene==="capture"');results['capture_survives_return']={'passed':p.evaluate('capture==="recording"&&captureHasPoints'),'state':p.evaluate('capture'),'hasPoints':p.evaluate('captureHasPoints')}
  reset('bilan');results['constat_field_exists']={'passed':p.locator('#observationText').count()==1,'labels':p.locator('.formfield span').all_text_contents()}
  p.locator('textarea').first.fill('Vérification UNIQUE de la saisie.');p.locator('[data-action=previewBilan]').click()
  results['preview_uses_current_text']={'passed':'Vérification UNIQUE' in p.locator('dialog').inner_text()};p.keyboard.press('Escape')
  # Same view navigation, no page reload: draft must not disappear.
  p.evaluate('scene="agenda";render();scene="bilan";render()');results['draft_survives_view_change']={'passed':p.locator('textarea').first.input_value()=='Vérification UNIQUE de la saisie.'}
  reset('replay');p.locator('[data-action=nextObs]').click();xy=p.locator('.replay-dot').evaluate('(e)=>[+e.getAttribute("cx"),+e.getAttribute("cy")]')
  results['observation_matches_position']={'passed':abs(xy[0]-575)<.001 and abs(xy[1]-230)<.001,'position':xy,'expected':[575,230]}
  p.select_option('#scenarioSelect','partial');p.evaluate('replaySecond=550;updateReplay()')
  results['no_position_inside_gap']={'passed':not p.locator('.replay-dot').is_visible()}
  results['no_continuous_path_across_gap']={'passed':p.locator('path[id^=route]').count()==2,'paths':p.locator('path[id^=route]').count()}
  reset('web-eleves');p.fill('#studentSearch','Noé');p.select_option('#studentFilter','active');p.click('[data-student="1"]');p.click('[data-action=archivePreview]');p.click('[data-action=demoArchive]')
  results['archive_keeps_filter']={'passed':p.input_value('#studentSearch')=='Noé' and p.input_value('#studentFilter')=='active','query':p.input_value('#studentSearch'),'filter':p.input_value('#studentFilter')}
  results['archive_has_useful_focus']={'passed':p.evaluate('document.activeElement.id==="studentSearch"'),'focus':p.evaluate('document.activeElement.id||document.activeElement.tagName')}
  reset('web-eleves');p.fill('#studentSearch','nobody');results['empty_filter_has_no_stale_actions']={'passed':p.locator('[data-action=archivePreview]').count()==0,'detail':p.locator('#studentDetail').inner_text()[:150]}
  reset('profil');inp=p.locator('.formfield input').first;n=inp.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');p.check('#largeText');v=inp.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');results['tested_text_reaches_200_percent']={'passed':abs(v/n-2)<.01,'factor':v/n,'classification':'coverage extension; 150% was explicit in V3.8'}
  b.close()
 return results
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--source',required=True,type=Path);a.add_argument('--chromium');a.add_argument('--write-report',action='store_true');opt=a.parse_args()
 before=inspect(opt.source,opt.chromium);after=inspect(R,opt.chromium);pairs=[{'name':k,'before':before[k],'after':after[k]} for k in before]
 report={'version':'3.9','sourceVersion':'3.8','scope':'SAME_USER_INTENTS_IN_DOCUMENTARY_PROTOTYPES_ONLY','cases':pairs,'improved':sum(not p['before']['passed'] and p['after']['passed'] for p in pairs),'regressions':[p['name'] for p in pairs if p['before']['passed'] and not p['after']['passed']],'passed':all(p['after']['passed'] for p in pairs),'notABackendOrNativeTest':True}
 if opt.write_report:(R/'annexes/comparaison-prototype-v3-8-v3-9.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
 print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(0 if report['passed'] else 1)
