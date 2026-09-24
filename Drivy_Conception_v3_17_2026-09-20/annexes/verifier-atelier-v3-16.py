#!/usr/bin/env python3
"""HTML checks only. Requires requirements-browser.txt and an installed Chromium.
Unavailable imports/browser or a failing assertion produce a non-zero exit.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
import json,time,platform,argparse,sys,shutil,datetime,os
R=Path(__file__).resolve().parents[1];out=R/'annexes/verification-atelier-v3-16.json'
ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--write-report',action='store_true');args=ap.parse_args()
checks=[];errors=[];matrix=[]
def ck(name,value,details=None):
 checks.append({'check':name,'passed':bool(value),'details':details})
 if os.environ.get('DRIVY_PROGRESS'):print('CHECK',name,bool(value),file=sys.stderr,flush=True)
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
 # Focused refinements: same dialog/map nodes, no false navigation, no time reset.
 load();cl('[data-action=signal]');page.wait_for_timeout(230)
 page.evaluate("window.__panel=document.querySelector('.sheet');window.__map=document.querySelector('#mapLayer');window.__head=document.querySelector('.head')")
 before=state()['pending'];cl('[data-category]:first-child')
 ck('Status actions have no navigation chevron',page.locator('#device .status-option>.icon').count()==0)
 ck('One concise instruction preserves commit semantics',page.locator('#device .commit-hint').inner_text()=='Le choix enregistre.')
 ck('Status options explicitly name their private save action',all('enregistrer' in label for label in page.locator('#device .status-option').evaluate_all('(xs)=>xs.map(x=>x.getAttribute("aria-label"))')))
 ck('Category to status keeps dialog, map and header nodes',page.evaluate("window.__panel===document.querySelector('.sheet')&&window.__map===document.querySelector('#mapLayer')&&window.__head===document.querySelector('.head')"))
 cl('[data-action=sheetBack]');ck('Back keeps timestamp and anchor',state()['pending']['second']==before['second'] and state()['pending']['anchor']==before['anchor'])
 ck('Back returns focus to previously selected category',page.evaluate('document.activeElement.dataset.category')==state()['events'][1]['theme'])
 ck('Back keeps the same dialog node',page.evaluate("window.__panel===document.querySelector('.sheet')"))
 page.evaluate("document.querySelector('.category').click();document.querySelector('[data-action=sheetBack]').click();document.querySelector('.category').click();document.querySelector('[data-action=closeSheet]').click()")
 ck('Rapid transitions can be interrupted with no write',state()['sheet'] is None and state()['pending'] is None and len(state()['events'])==3)
 load();page.evaluate('window.drivy.set({reduced:true})');cl('[data-action=signal]');cl('[data-category]:first-child')
 ck('Reduced-motion keeps action without animated morph',page.evaluate("document.querySelector('#device').getAnimations({subtree:true}).filter(x=>x.playState==='running').length")==0)
 cl('[data-status=POSITIVE]');ck('Reduced-motion still saves explicit choice',len(state()['events'])==4 and state()['events'][-1]['status']=='POSITIVE')
 load();page.emulate_media(reduced_motion='reduce');cl('[data-action=signal]');cl('[data-category]:first-child')
 ck('OS reduced-motion also disables panel motion',page.evaluate("document.querySelector('#device').getAnimations({subtree:true}).filter(x=>x.playState==='running').length")==0);page.emulate_media(reduced_motion='no-preference')
 load();page.evaluate("window.drivy.view('replay')")
 ck('Selected point uses its pedagogical theme',page.locator('#device .map-hit.selected .pin-glyph').get_attribute('data-glyph')=='priority')
 ck('Selected point still carries a non-color status symbol',page.locator('#device .map-hit.selected .pin-status').count()==1)
 ck('Theme and written status retained in replay panel','Priorité à droite' in page.locator('#selectedObservation').inner_text() and 'Attention' in page.locator('#selectedObservation').inner_text())
 ck('Unselected points remain concise',page.locator('#device .map-hit:not(.selected) .pin-status').count()==0 and page.locator('#device .map-hit.selected').count()==1)
 page.evaluate("window.drivy.set({pan:{x:15,y:10},zoom:1.1,follow:false})")
 cl('[data-event=demo-03]');ck('Selecting another point preserves free camera',state()['pan']=={'x':15,'y':10} and state()['zoom']==1.1 and not state()['follow'])
 ck('Point and replay time update together',state()['second']==1130 and page.locator('#device .map-hit.selected .pin-glyph').get_attribute('data-glyph')=='parking')
 cl('[data-action=detail]');cl('[data-action=changeQualification]');cl('[data-category]:first-child');cl('[data-status=ATTENTION]');cl('[data-action=undo]')
 ck('Undo qualification restores event instead of deleting it',len(state()['events'])==3 and state()['events'][2]['status']=='POSITIVE' and state()['events'][2]['theme']=='00000000-0000-4000-8000-000000000111')
 load();page.select_option('#mapDetailSelect','dense');ck('Dense map is a separate fictional layer',page.locator('#dense-context').count()==1 and state()['mapDetail']=='dense')
 ck('Dense review is outside the simulated application',page.locator('#device #mapDetailSelect').count()==0 and 'fictive' in page.locator('#mapDetailSelect').inner_text())
 original=state()['events'];page.check('#denseFixtures');ck('Dense fixture adds four separate events',len(state()['events'])==7 and state()['events'][:3]==original)
 cl('[data-action=list]');ck('Every dense event has a list entry',page.locator('#device [data-list-event]').count()==7)
 cl('[data-list-event=demo-02]');visited=[]
 for _ in range(5):
  cl('[data-action=next]');visited.append(state()['selected'])
 ck('Next traverses same-time observations individually',visited==['dense-01','dense-02','dense-03','dense-04','demo-03'],visited)
 cl('[data-action=previous]');cl('[data-action=previous]');ck('Previous reaches same-time distinct observation',state()['selected']=='dense-03')
 cl('[data-action=list]');cl('[data-list-event=dense-02]');ck('List independently opens a collocated observation',state()['selected']=='dense-02' and 'Observation' in page.locator('#selectedObservation').inner_text())
 page.uncheck('#denseFixtures');ck('Removing review fiction keeps original data',state()['events']==original)
 load();page.select_option('#stateSelect','save-error');cl('[data-action=mark]');ck('Simple marker failure remains visibly explicit',len(state()['events'])==3 and state()['toast'] is None and 'Repère non enregistré' in page.locator('#device').inner_text())
 cl('[data-action=signal]');cl('[data-action=markPending]');ck('Marker failure in panel keeps pending context',state()['pending'] is not None and page.locator('#device .sheet [role=alert]').count()==1 and len(state()['events'])==3)
 load();page.evaluate("window.drivy.view('replay');window.drivy.set({second:200,selected:null})");cl('[data-action=play]');time.sleep(.2);ck('Replay does not show a distant stale observation',state()['selected'] is None)
 # Width and readability checks use CSS pixels, not claims of native Dynamic Type.
 for mapDetail in ['calm','dense']:
  for size in ['phone','small','tablet-compact','tablet']:
   for scale in ['normal','large']:
    for theme in ['light','dark']:
     for view in ['capture','categories','status','replay']:
      page.evaluate('p=>{window.drivy.set(p);window.drivy.view(p.v)}',{'size':size,'scale':scale,'theme':theme,'v':view,'reduced':True,'environment':'normal','toast':None,'mapDetail':mapDetail})
      page.wait_for_timeout(60)
      metrics=page.evaluate('''()=>{const d=document.querySelector('#device'),r=d.getBoundingClientRect(),sheet=d.querySelector('.sheet');const visible=(x)=>{const q=x.getBoundingClientRect();return q.width>0&&q.height>0&&!x.closest('[inert]')};const buttons=[...d.querySelectorAll('button')].filter(visible);const undersized=buttons.filter(x=>{const q=x.getBoundingClientRect();return q.width<43.5||q.height<43.5}).map(x=>[x.innerText||x.getAttribute('aria-label'),x.offsetWidth,x.offsetHeight]);const critical=d.querySelector(sheet?'button[data-action=closeSheet]':'[data-action=signal]')||d.querySelector('[data-action=play]');const c=critical?.getBoundingClientRect();const onScreen=!!c&&c.top>=r.top&&c.bottom<=r.bottom&&c.left>=r.left&&c.right<=r.right;let clipped=[];for(const x of d.querySelectorAll('.cat-label,.label,.heading,.identity,.count,.selected-text')){if(!visible(x))continue;if(x.scrollWidth>x.clientWidth+1)clipped.push(x.innerText)}return{undersized,onScreen,clipped,sheetHorizontal:sheet?sheet.scrollWidth>sheet.clientWidth+1:false,deviceHorizontal:d.scrollWidth>d.clientWidth+1}}''')
      matrix.append({'mapDetail':mapDetail,'size':size,'scale':scale,'theme':theme,'view':view,**metrics})
 bad=[x for x in matrix if x['undersized'] or not x['onScreen'] or x['clipped'] or x['sheetHorizontal']]
 ck('128 layouts: visible primary/close, 44px targets, no horizontal text clipping',not bad,bad)
 load();ck('Reload resets volatile demo state',len(state()['events'])==3)
 ck('No script error in executed suite',not errors,errors)
 result={'version':'3.16','executedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'passed':all(x['passed'] for x in checks),'errorCount':sum(not x['passed'] for x in checks),'status':'PASSED' if all(x['passed'] for x in checks) else 'FAILED','scope':'HTML_DOCUMENTARY_PROTOTYPE_NOT_NATIVE_APP','environment':{'platform':platform.platform(),'python':platform.python_version(),'browser':b.version,'navigation':'page.set_content; separate file:// smoke blocked by browser policy, not qualified'},'checks':checks,'layouts':matrix,'nativeTests':'NOT_EXECUTED','roadSafety':'NOT_QUALIFIED'}
 if args.write_report:out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2));b.close()
raise SystemExit(0 if result['passed'] else 1)
