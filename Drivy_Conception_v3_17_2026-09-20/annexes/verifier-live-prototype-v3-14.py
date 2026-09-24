#!/usr/bin/env python3
"""Exercise E23/E24 in-memory signal prototype and negative controls.
This does not exercise native code, persistent outbox, GPS, SQL, publication or road safety.
"""
from pathlib import Path
from copy import deepcopy
from datetime import datetime, timezone
import argparse, importlib.metadata, json, platform, shutil, sys
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]

def run(chromium=None):
    html=(R/'DESIGN/MAQUETTES.html').read_text(encoding='utf-8')
    api=yaml.safe_load((R/'04-technique/openapi.yaml').read_text(encoding='utf-8'))
    schema={'allOf':[api['components']['schemas']['GeoObservationCommand']],'components':api['components']}
    validator=Draft202012Validator(schema,format_checker=FormatChecker())
    checks=[];errors=[];requests=[];js_errors=[];dto_cases=[];layouts=[]
    def check(name,ok,detail=None):
        c={'name':name,'passed':bool(ok),'detail':detail};checks.append(c)
        print(name+': '+str(bool(ok)),file=sys.stderr,flush=True)
        if not ok:errors.append(c)
    def accepted(value):return not list(validator.iter_errors(value))
    with sync_playwright() as pw:
        exe=chromium or shutil.which('chromium') or shutil.which('google-chrome')
        browser=pw.chromium.launch(headless=True,**({'executable_path':exe} if exe else {}),args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1200,'height':1120})
        page.on('request',lambda r:requests.append(r.url));page.on('pageerror',lambda e:js_errors.append(str(e)))
        page.set_content(html,wait_until='load')
        def scene(key):page.evaluate('(s)=>{scene=s;render()}',key)
        def click(action):page.locator(f'#stage [data-action="{action}"],dialog[open] [data-action="{action}"]').first.click()
        def dto(index):
            d=page.evaluate('(i)=>buildDemoLiveCommand(liveEvents[i])',index);errs=[x.message for x in validator.iter_errors(d)]
            dto_cases.append({'value':d,'passed':not errs,'errors':errs});return d,not errs
        scene('capture');click('openSignal')
        frozen=page.evaluate('JSON.parse(JSON.stringify(pendingSignal))')
        check('opening_does_not_create_event',page.evaluate('liveEvents.length===0 && pendingSignal!==null'))
        check('six_named_stable_categories',page.locator('[data-signal-theme]').count()==6 and page.locator('[data-status]').count()==0)
        check('open_context_points_to_already_recorded_fixture',frozen['second']==1490 and frozen['anchor']['pointSecond']<=frozen['second'])
        click('cancelSignal');check('cancel_leaves_no_event_or_command',page.evaluate('liveEvents.length===0 && pendingSignal===null'))
        click('openSignal');page.locator('[data-signal-theme]').first.click()
        check('no_default_status_no_event_after_theme',page.evaluate('liveEvents.length===0') and page.locator('[data-status]').count()==3)
        page.evaluate('liveDemoSecond=1800')
        pending_before=page.evaluate('JSON.stringify(pendingSignal)')
        page.set_viewport_size({'width':700,'height':1100})
        check('resize_keeps_pending_timestamp_and_selection',page.evaluate('JSON.stringify(pendingSignal)')==pending_before)
        page.locator('[data-status=ATTENTION]').click()
        check('explicit_commit_creates_one_private_qualified_event',page.evaluate('liveEvents.length===1 && liveEvents[0].kind==="QUALIFIED" && !liveEvents[0].selected && capture==="recording"'))
        event=page.evaluate('JSON.parse(JSON.stringify(liveEvents[0]))')
        check('commit_keeps_open_time_not_validation_time',event['observedAt']==frozen['observedAt'] and event['anchor']==frozen['anchor'])
        d,ok=dto(0);check('anchored_signal_matches_unchanged_api_shape',ok)
        check('canvas_coords_not_transmitted_as_gps',not any(k in d for k in ['x','y','latitude','longitude']))
        page.evaluate('commitSignal("ATTENTION")');check('duplicate_commit_without_pending_is_ignored',page.evaluate('liveEvents.length===1'))
        check('live_map_contains_private_pin',page.locator('.cockpit .live-pin').count()==1)
        # A partly absent triplet, malformed time and missing explicit status fail the actual schema.
        for name,mutate in [('half_anchor',lambda x:x.update(segmentId=None)),('invalid_time',lambda x:x.update(observedAt='demain')),('missing_status',lambda x:x.pop('eventStatus')),('unqualified_as_qualified',lambda x:x.update(competencyId=None))]:
            bad=deepcopy(d);mutate(bad);check('negative_schema_'+name,not accepted(bad))
        click('reviewLive');page.locator('dialog [data-live-replay="live-1"]').click()
        check('private_replay_opens_same_moment',page.evaluate('scene==="replay" && replayVariant==="private" && replaySecond===1490'))
        check('private_replay_exposes_named_event', 'Priorité à droite' in page.locator('.private-timeline').inner_text())
        # Camera exploration stays independent of replay and recenter does not reset time.
        page.evaluate('mapOffset={x:50,y:20};mapExploring=true;applyMapOffset();replaySecond=1600;updateReplay()')
        check('replay_does_not_steal_manual_camera',page.evaluate('mapOffset.x===50 && mapOffset.y===20 && mapExploring'))
        click('recenter');check('recenter_keeps_replay_time',page.evaluate('mapOffset.x===0 && mapOffset.y===0 && replaySecond===1600'))
        scene('mes-lecons');page.locator('#stage [data-scene=replay]').click();page.wait_for_timeout(80)
        check('student_navigation_forces_published_context',page.evaluate('scene==="replay" && replayVariant==="shared"'))
        check('student_replay_has_no_private_timeline_or_controls',page.locator('#stage .private-timeline,#stage .live-event,#stage [data-live-selected]').count()==0)
        # Alternative marker and subsequent qualification keep one identity and original time.
        scene('capture');click('markLive');marker=page.evaluate('JSON.parse(JSON.stringify(liveEvents[1]))')
        check('marker_private_and_not_qualified',marker['kind']=='MARKER' and marker['theme'] is None and not marker['selected'])
        check('marker_dto_valid',dto(1)[1])
        click('reviewLive');page.locator('[data-live-edit="live-2"]').click();click('saveLive')
        check('detail_form_requires_theme_and_status',page.locator('#liveError').is_visible() and page.evaluate('liveEvents.length===2'))
        page.select_option('#liveTheme','00000000-0000-4000-8000-000000000111');page.select_option('#liveStatus','TO_REWORK')
        page.fill('#liveNote','Stationnement <script>aucun_script()</script>');click('saveLive')
        e=page.evaluate('JSON.parse(JSON.stringify(liveEvents[1]))')
        check('qualifying_marker_preserves_identity_time_anchor',e['id']==marker['id'] and e['observedAt']==marker['observedAt'] and e['anchor']==marker['anchor'])
        check('qualified_marker_dto_valid',dto(1)[1]);scene('bilan')
        check('no_automatic_selection_or_grade',page.locator('[data-live-selected]:checked,input[name=level]:checked').count()==0)
        page.check('[data-live-selected="live-2"]');click('previewBilan')
        check('preview_escapes_entered_text','Stationnement <script>aucun_script()</script>' in page.locator('dialog').inner_text() and page.locator('dialog script').count()==0)
        check('selection_does_not_assign_grade',page.evaluate('buildDemoDraft().observations.length===0'));page.keyboard.press('Escape')
        # Opening pending signal never hides stop, and stop itself does not commit it.
        scene('capture');click('openSignal');before=page.evaluate('liveEvents.length');click('stop')
        check('stop_accessible_while_signal_open',page.evaluate('capture==="stopped" && scene==="capture"') and page.evaluate('liveEvents.length')==before)
        check('stopping_keeps_pending_signal_explicit',page.evaluate('pendingSignal!==null'));click('cancelSignal')
        # No GPS, same category path, no fabricated anchor or permission.
        scene('sans-gps');click('openSignal');page.locator('[data-signal-theme]').nth(2).click();page.locator('[data-status=POSITIVE]').click()
        e=page.evaluate('liveEvents.at(-1)');check('without_gps_same_signal_path_no_anchor',e['anchor'] is None and e['status']=='POSITIVE' and page.locator('.map-wrap').count()==0)
        check('without_gps_dto_valid',dto(2)[1])
        # Restore baseline for viewport geometry. Measured HTML units, not native device qualification.
        page.evaluate('pendingSignal=null;capture="recording";lastLiveId=null;liveDemoSecond=1490');scene('capture')
        geom=r'''()=>{const p=document.querySelector('.phone'),r=p.getBoundingClientRect();const targets=['openSignal','markLive','stop'].map(a=>{const e=p.querySelector(`[data-action="${a}"]`),b=e.getBoundingClientRect();return {action:a,width:b.width,height:b.height,inside:b.top>=r.top-1&&b.bottom<=r.bottom+1&&b.left>=r.left-1&&b.right<=r.right+1}});return {phoneWidth:r.width,phoneHeight:r.height,targets,passed:targets.every(x=>x.inside&&x.width>=44&&x.height>=44)}}'''
        for width,height in [(320,568),(375,667),(390,844),(440,956)]:
            for large in [False,True]:
                page.evaluate('([w,h,l])=>{document.body.classList.toggle("large-text",l);const p=document.querySelector(".phone");p.style.maxWidth="none";p.style.width=w+"px";p.style.setProperty("--demo-phone-height",h+"px")}',[width,height,large])
                page.wait_for_timeout(20);g=page.evaluate(geom);g['largeText']=large;g['requestedWidth']=width;g['requestedHeight']=height;layouts.append(g)
        check('critical_targets_visible_at_all_eight_sizes',all(x['passed'] for x in layouts),layouts)
        # Same detector must reject an intentionally out-of-frame trigger.
        page.evaluate('const e=document.querySelector("[data-action=openSignal]");e.style.transition="none";e.style.transform="translateY(2000px)"')
        check('negative_geometry_detects_hidden_trigger',not page.evaluate(geom)['passed'])
        page.evaluate('document.body.classList.remove("large-text");render()');scene('ipad-capture');click('openSignal');page.locator('[data-signal-theme]').first.click()
        tablet_pending=page.evaluate('JSON.stringify(pendingSignal)')
        for width in [1440,700,390,1440]:page.set_viewport_size({'width':width,'height':1100});page.wait_for_timeout(20)
        check('ipad_resize_retains_pending_and_events',page.evaluate('JSON.stringify(pendingSignal)')==tablet_pending and page.evaluate('liveEvents.length===3'))
        click('cancelSignal');scene('capture');page.check('#reducedMotion');page.check('#highContrast');click('openSignal')
        check('reduced_motion_removes_panel_animation',page.locator('.signal-sheet').evaluate('(e)=>getComputedStyle(e).animationName')=='none')
        check('contrast_option_keeps_all_category_actions',page.locator('[data-signal-theme]').count()==6)
        click('cancelSignal');page.uncheck('#reducedMotion');page.uncheck('#highContrast')
        # Mutation tests run the SAME opening/frozen-context invariants on corrupted documents.
        corrupt=html.replace('function openSignal(){','function openSignal(){liveEvents.push(newLive("MARKER"));',1)
        badpage=browser.new_page();badpage.set_content(corrupt);badpage.evaluate('scene="capture";render();openSignal()')
        check('negative_open_side_effect_is_detected',not badpage.evaluate('liveEvents.length===0 && pendingSignal!==null'));badpage.close()
        corrupt=html.replace("const e=newLive('QUALIFIED',c);","const e=newLive('QUALIFIED');",1)
        badpage=browser.new_page();badpage.set_content(corrupt);badpage.evaluate('scene="capture";render();openSignal();pendingSignal.theme=SIGNAL.themes[0].id;liveDemoSecond=1800;commitSignal("ATTENTION")')
        check('negative_validation_timestamp_is_detected',not badpage.evaluate('liveEvents[0].second===1490'));badpage.close()
        fresh=browser.new_page();fresh.set_content(html);check('fresh_document_clears_memory',fresh.evaluate('liveEvents.length===0 && pendingSignal===null'));fresh.close()
        check('no_network_requests',not requests,requests);check('no_javascript_errors',not js_errors,js_errors)
        browser.close()
    return {'version':'3.14','scope':'DOCUMENTARY_HTML_MEMORY_AND_DTO_ONLY','executedAtUTC':datetime.now(timezone.utc).isoformat(),'environment':{'python':platform.python_version(),'system':platform.system(),'playwright':importlib.metadata.version('playwright'),'chromium':exe},'checks':checks,'dtoCases':dto_cases,'layouts':layouts,'passed':not errors,'errorCount':len(errors),'errors':errors,'nativeTestsExecuted':False,'limits':['No persistent storage, real GPS, backend, transaction or publication executed.','Canvas anchors are fictitious references; shape validation does not enforce authorization or freshness.','CSS measurements do not establish native Dynamic Type, VoiceOver, safety in motion or actual smallest supported device.','T423–T434 and all other product scenarios remain NOT_EXECUTED.']}
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--write-report',action='store_true');args=ap.parse_args()
    result=run(args.chromium)
    if args.write_report:(R/'annexes/verification-live-prototype-v3-14.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(0 if result['passed'] else 1)
