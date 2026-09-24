#!/usr/bin/env python3
"""HTML checks only. Requires requirements-browser.txt and an installed Chromium.
Unavailable imports/browser or a failing assertion produce a non-zero exit.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
import json,time,platform,argparse,sys,shutil,datetime
R=Path(__file__).resolve().parents[1];out=R/'annexes/verification-atelier-v3-15.json'
ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--write-report',action='store_true');args=ap.parse_args()
checks=[];errors=[];matrix=[]
def ck(name,value,details=None):
 checks.append({'check':name,'passed':bool(value),'details':details})
 if not value:print('FAIL',name,details,file=sys.stderr)
with sync_playwright() as p:
 b=p.chromium.launch(**({'executable_path':args.chromium} if args.chromium else {}),args=['--no-sandbox'])
 page=b.new_page(viewport={'width':1500,'height':1100});page.set_default_timeout(4000);page.on('pageerror',lambda e:errors.append(str(e)))
 def load():
  page.goto('about:blank');page.set_content((R/'DESIGN/LECON.html').read_text(encoding='utf-8'));page.wait_for_timeout(80)
 def state():return page.evaluate('window.drivy.state()')
 def cl(sel):page.locator('#device '+('.sheet ' if sel.startswith('[data-status=') else '')+'button'+sel).first.click()
 load();ck('Three clearly identified fixture observations',len(state()['events'])==3)
 cl('[data-action=signal]');a=state();ck('Opening does not add an event',len(a['events'])==3);ck('No default category or status',a['pending']['theme'] is None and a['sheet']=='categories')
 saved=a['pending'];page.evaluate('window.drivy.set({elapsed:1500})');cl('[data-category]:first-child');ck('Theme selection does not save',len(state()['events'])==3)
 cl('[data-status=ATTENTION]');a=state();last=a['events'][-1];ck('Theme plus explicit status adds one event',len(a['events'])==4 and last['status']=='ATTENTION');ck('Frozen moment and position preserved',last['second']==saved['second'] and last['anchor']==saved['anchor']);ck('Private no publication fields',last['visibility']=='PRIVATE' and 'published' not in last and 'score' not in last)
 cl('[data-action=undo]');ck('Undo removes only last addition',len(state()['events'])==3)
 cl('[data-action=signal]');cl('[data-action=closeSheet]');ck('Cancellation does not save',len(state()['events'])==3 and state()['pending'] is None)
 cl('[data-action=signal]');page.keyboard.press('Escape');ck('Escape cancels and focus restored',state()['sheet'] is None and page.evaluate('document.activeElement.dataset.action')=='signal')
 cl('[data-action=mark]');a=state();ck('Marker has no default qualification',a['events'][-1]['kind']=='MARKER' and a['events'][-1]['theme'] is None and a['events'][-1]['status'] is None)
 load();page.select_option('#stateSelect','no-gps');ck('No GPS is not a disabled map',page.locator('#device .map-viewport').count()==0)
 cl('[data-action=signal]');cl('[data-category]:first-child');cl('[data-status=POSITIVE]');ck('Observation without GPS has no anchor',state()['events'][-1]['anchor'] is None)
 load();page.select_option('#stateSelect','offline');cl('[data-action=signal]');cl('[data-category]:first-child');cl('[data-status=ATTENTION]');ck('Offline still saves private observation',len(state()['events'])==4 and state()['events'][-1]['visibility']=='PRIVATE');ck('Offline banner does not claim synced','Hors ligne' in page.locator('#device').inner_text() and 'Synchronisé' not in page.locator('#device').inner_text())
 load();page.select_option('#stateSelect','save-error');cl('[data-action=signal]');cl('[data-category]:first-child');cl('[data-status=ATTENTION]');ck('Save error does not produce success',len(state()['events'])==3 and state()['sheet']=='status' and state()['toast'] is None and state()['pending'] is not None);ck('Save error visibly reported',page.locator('#device [role=alert]').count()==1)
 load();cl('[data-action=more]');cl('[data-action=pauseCapture]');ck('Pause changes state without ending lesson',state()['capture']=='paused' and not state()['lessonEnded']);cl('[data-action=signal]');cl('[data-category]:first-child');cl('[data-status=ATTENTION]');ck('Pause cannot invent a fresh position',state()['events'][-1]['anchor'] is None)
 cl('[data-action=more]');cl('[data-action=askStop]');ck('Stop confirmation is explicit','Arrêter le GPS ?' in page.locator('#device').inner_text());cl('[data-action=stopCapture]');ck('Stop GPS keeps lesson and observations',state()['capture']=='stopped' and not state()['lessonEnded'] and len(state()['events'])==4)
 cl('[data-action=signal]');cl('[data-category]:first-child');cl('[data-status=TO_REWORK]');ck('Observation allowed after GPS stops',len(state()['events'])==5 and state()['events'][-1]['anchor'] is None)
 cl('[data-action=more]');cl('[data-action=askFinish]');cl('[data-action=finishLesson]');ck('Lesson end does not publish or erase observations',state()['lessonEnded'] and all(x['visibility']=='PRIVATE' for x in state()['events']))
 load();page.evaluate("window.drivy.view('replay')");cl('[data-action=play]');t=state()['second'];time.sleep(.65);delta=state()['second']-t;ck('Replay x1 runs on elapsed time',.4<delta<1.1,delta)
 box=page.locator('#device').bounding_box();page.mouse.move(box['x']+140,box['y']+320);page.mouse.down();page.mouse.move(box['x']+180,box['y']+340,steps=6);page.mouse.up();ck('Manual map pan does not pause playback',state()['playing'] and not state()['follow']);pan=state()['pan'];time.sleep(.25);ck('No forced recenter during manual exploration',state()['pan']==pan)
 cl('[data-action=recenter]');ck('Recenter does not reset replay time',state()['follow'] and state()['second']>t)
 cl('[data-action=play]');cl('[data-action=next]');ck('Next observation aligns the time',state()['selected']=='demo-03' and state()['second']==1130)
 cl('[data-action=detail]');page.fill('#noteInput','Texte <test> & précision.');cl('[data-action=saveNote]');ck('Edit text retained safely',state()['events'][2]['note']=='Texte <test> & précision.')
 cl('[data-action=detail]');cl('[data-action=changeQualification]');cl('[data-category]:first-child');cl('[data-status=TO_REWORK]');ck('Qualification updates existing observation, not duplicate',len(state()['events'])==3 and state()['events'][2]['status']=='TO_REWORK')
 ck('Replay focus restored after editing',page.evaluate('document.activeElement.dataset.action')=='play')
 load();page.evaluate("window.drivy.view('categories')");page.wait_for_timeout(220);focusables=page.locator('#device .sheet button');focusables.last.focus();page.keyboard.press('Tab');ck('Dialog focus trapped',page.evaluate("document.activeElement===document.querySelector('.sheet button')"));ck('Background inert in dialog',page.locator('#device .app-base[inert]').count()==1)
 # Width and readability checks use CSS pixels, not claims of native Dynamic Type.
 for size in ['phone','small','tablet-compact','tablet']:
  for scale in ['normal','large']:
   for theme in ['light','dark']:
    for view in ['capture','categories','status','replay']:
     page.evaluate('p=>{window.drivy.set(p);window.drivy.view(p.v)}',{'size':size,'scale':scale,'theme':theme,'v':view,'reduced':True,'environment':'normal','toast':None})
     page.wait_for_timeout(60)
     metrics=page.evaluate('''()=>{const d=document.querySelector('#device'),r=d.getBoundingClientRect(),sheet=d.querySelector('.sheet');const visible=(x)=>{const q=x.getBoundingClientRect();return q.width>0&&q.height>0&&!x.closest('[inert]')};const buttons=[...d.querySelectorAll('button')].filter(visible);const undersized=buttons.filter(x=>{const q=x.getBoundingClientRect();return q.width<43.5||q.height<43.5}).map(x=>[x.innerText||x.getAttribute('aria-label'),x.offsetWidth,x.offsetHeight]);const critical=d.querySelector(sheet?'button[data-action=closeSheet]':'[data-action=signal]')||d.querySelector('[data-action=play]');const c=critical?.getBoundingClientRect();const onScreen=!!c&&c.top>=r.top&&c.bottom<=r.bottom&&c.left>=r.left&&c.right<=r.right;let clipped=[];for(const x of d.querySelectorAll('.cat-label,.label,.heading,.identity,.count,.selected-text')){if(!visible(x))continue;if(x.scrollWidth>x.clientWidth+1)clipped.push(x.innerText)}return{undersized,onScreen,clipped,sheetHorizontal:sheet?sheet.scrollWidth>sheet.clientWidth+1:false,deviceHorizontal:d.scrollWidth>d.clientWidth+1}}''')
     matrix.append({'size':size,'scale':scale,'theme':theme,'view':view,**metrics})
 bad=[x for x in matrix if x['undersized'] or not x['onScreen'] or x['clipped'] or x['sheetHorizontal']]
 ck('64 layouts: visible primary/close, 44px targets, no horizontal text clipping',not bad,bad)
 load();ck('Reload resets volatile demo state',len(state()['events'])==3)
 ck('No script error in executed suite',not errors,errors)
 result={'version':'3.15','executedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'passed':all(x['passed'] for x in checks),'errorCount':sum(not x['passed'] for x in checks),'status':'PASSED' if all(x['passed'] for x in checks) else 'FAILED','scope':'HTML_DOCUMENTARY_PROTOTYPE_NOT_NATIVE_APP','environment':{'platform':platform.platform(),'python':platform.python_version(),'browser':b.version,'navigation':'page.set_content; no real file URL on managed Chromium'},'checks':checks,'layouts':matrix,'nativeTests':'NOT_EXECUTED','roadSafety':'NOT_QUALIFIED'}
 if args.write_report:out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2));b.close()
raise SystemExit(0 if result['passed'] else 1)
