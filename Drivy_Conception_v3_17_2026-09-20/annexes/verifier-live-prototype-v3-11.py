#!/usr/bin/env python3
"""Check only the in-memory documentary live workflow and its JSON DTO shapes."""
from pathlib import Path
import argparse,json,shutil,sys,time
import yaml
from jsonschema import Draft202012Validator,FormatChecker
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
def run(chromium=None):
 html=(R/'DESIGN/MAQUETTES.html').read_text(encoding='utf-8');api=yaml.safe_load((R/'04-technique/openapi.yaml').read_text(encoding='utf-8'))
 schema={'allOf':[api['components']['schemas']['GeoObservationCommand']],'components':api['components']};v=Draft202012Validator(schema,format_checker=FormatChecker());checks=[];errors=[];requests=[];js_errors=[];dtos=[]
 def check(name,ok,detail=None):
  print(name+': '+str(bool(ok)),file=sys.stderr,flush=True)
  entry={'name':name,'passed':bool(ok),'detail':detail};checks.append(entry)
  if not ok:errors.append(entry)
 with sync_playwright() as pw:
  exe=chromium or shutil.which('chromium') or shutil.which('google-chrome');b=pw.chromium.launch(headless=True,**({'executable_path':exe} if exe else {}),args=['--no-sandbox']);p=b.new_page(viewport={'width':390,'height':1000});p.on('request',lambda r:requests.append(r.url));p.on('pageerror',lambda e:js_errors.append(str(e)));p.set_content(html,wait_until='load')
  def scene(key):p.evaluate('(k)=>{scene=k;render()}',key)
  def click(a):p.locator(f'#stage [data-action="{a}"],dialog[open] [data-action="{a}"]').first.click()
  def dto(index):
   value=p.evaluate('(i)=>buildDemoLiveCommand(liveEvents[i])',index);es=list(v.iter_errors(value));dtos.append({'value':value,'passed':not es,'errors':[e.message for e in es]});return not es
  scene('capture');click('markLive');check('marker_created_private',p.evaluate('liveEvents.length===1 && liveEvents[0].kind==="MARKER" && !liveEvents[0].selected'))
  check('marker_command_valid_without_fabricated_anchor',dto(0))
  click('editLive');check('theme_status_not_prefilled',p.input_value('#liveTheme')=='' and p.input_value('#liveStatus')=='');click('saveLive');check('missing_qualification_keeps_form_open',p.locator('dialog[open]').count()==1 and p.locator('#liveError').is_visible() and p.evaluate('liveEvents.length===1'))
  p.select_option('#liveTheme','00000000-0000-4000-8000-000000000108');p.select_option('#liveStatus','ATTENTION');p.fill('#liveNote','Priorité observée <script>interdit()</script>');p.set_viewport_size({'width':834,'height':1000});check('rotation_retains_form',p.input_value('#liveStatus')=='ATTENTION' and 'Priorité observée' in p.input_value('#liveNote'));click('saveLive')
  check('qualified_command_valid',dto(1));check('saving_observation_keeps_capture',p.evaluate('capture==="recording" && liveEvents.length===2'))
  scene('bilan');check('live_events_retrievable_in_bilan',p.locator('.live-event').count()==2);check('nothing_selected_or_graded',p.locator('[data-live-selected]:checked,input[name=level]:checked').count()==0)
  check('marker_not_selectable_for_publication',p.locator('[data-live-selected]').count()==1 and 'Non publiable avant qualification' in p.inner_text('#stage'))
  p.check('[data-live-selected]');check('selecting_event_does_not_grade',p.evaluate('buildDemoDraft().observations.length===0'));click('previewBilan');check('preview_contains_exact_escaped_selection','Priorité observée <script>interdit()</script>' in p.inner_text('dialog') and p.locator('dialog script').count()==0);p.keyboard.press('Escape')
  scene('capture');click('editLive');p.fill('#liveNote','Brouillon à conserver');click('liveStop');check('stop_available_without_saving_form',p.evaluate('capture==="stopped" && liveEvents.length===2 && liveForm.note==="Brouillon à conserver"'));check('stop_does_not_complete',p.evaluate('scene==="capture"'))
  scene('sans-gps');click('editLive');p.select_option('#liveTheme','00000000-0000-4000-8000-000000000109');p.select_option('#liveStatus','POSITIVE');p.fill('#liveNote','');click('saveLive');check('no_gps_observation_valid',dto(2));check('explicit_theme_used_when_optional_note_empty',p.evaluate('liveEvents[2].text==="Giratoire" && buildDemoLiveCommand(liveEvents[2]).captureId===null'))
  scene('bilan');p.locator('[data-live-edit="live-1"]').click();p.select_option('#liveTheme','00000000-0000-4000-8000-000000000110');p.select_option('#liveStatus','TO_REWORK');click('saveLive');check('marker_qualification_retains_event_time',p.evaluate('liveEvents[0].kind==="QUALIFIED" && liveEvents[0].observedAt==="2026-09-21T07:20:01.000Z"'));check('qualified_marker_command_valid',dto(0));check('qualification_does_not_auto_select',p.evaluate('!liveEvents[0].selected'))
  scene('replay');check('private_live_events_not_in_student_replay',p.locator('.live-event,[data-live-selected],[data-action=editLive]').count()==0)
  # Capture evidence at real CSS viewport widths, not physical-device claims.
  scene('capture');p.evaluate('capture="recording";render();clearTimeout(toastTimer);document.getElementById("toast").style.display="none"');p.set_viewport_size({'width':390,'height':1000});p.screenshot(path=str(R/'annexes/live-capture-v3-11.png'),full_page=True)
  click('editLive');p.screenshot(path=str(R/'annexes/live-form-v3-11.png'),full_page=True);p.keyboard.press('Escape')
  scene('bilan');p.screenshot(path=str(R/'annexes/live-bilan-v3-11.png'),full_page=True)
  fresh=b.new_page();fresh.set_content(html,wait_until='load');check('fresh_document_clears_demo_memory_explicitly',fresh.evaluate('liveEvents.length===0'));fresh.close();check('no_network_requests',not requests,requests);check('no_javascript_errors',not js_errors,js_errors);b.close()
 return {'version':'3.11','scope':'DOCUMENTARY_HTML_MEMORY_AND_DTO_ONLY','checks':checks,'dtoCases':dtos,'passed':not errors,'errors':errors,'nativeTestsExecuted':False,'limits':['No persistence, GPS, backend, SQL transaction or publication executed.','No user test, driving safety test or native Dynamic Type/accessibility validation.','Scenarios T407–T422 remain NOT_EXECUTED on a product.']}
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--write-report',action='store_true');a=ap.parse_args();r=run(a.chromium)
 if a.write_report:(R/'annexes/verification-live-prototype-v3-11.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
