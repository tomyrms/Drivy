#!/usr/bin/env python3
"""Browser checks for the self-contained documentary prototype, not the app.
Requires playwright and Chromium. Uses set_content, since local file URLs can
be blocked by the execution environment. Native widgets/system permissions,
VoiceOver, Dynamic Type and real backend operations are not exercised.
"""
from pathlib import Path
import argparse,json,shutil
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
def run(chromium=None,screens=False):
    checks=[];errors=[];layouts=[]
    def check(name,ok,detail=None):
        checks.append({'name':name,'passed':bool(ok),'detail':detail})
        if not ok:errors.append(checks[-1])
    scenes=json.loads((R/'DESIGN/scenes.json').read_text(encoding="utf-8"))['scenes']
    with sync_playwright() as pw:
        exe=chromium or shutil.which('chromium') or shutil.which('google-chrome')
        browser=pw.chromium.launch(headless=True,**({'executable_path':exe} if exe else {}),args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1440,'height':1100},device_scale_factor=1)
        js_errors=[];requests=[]
        page.on('pageerror',lambda e:js_errors.append(str(e)))
        page.on('request',lambda r:requests.append(r.url))
        page.set_content((R/'DESIGN/MAQUETTES.html').read_text(encoding="utf-8"),wait_until='load')
        check('14_scenes_plus_overview',page.locator('#viewSelect option').count()==15)
        for width in [390,834,1440]:
            page.set_viewport_size({'width':width,'height':1100})
            for theme in ['light','dark']:
                page.evaluate('(theme)=>{document.documentElement.dataset.theme=theme;document.body.classList.remove("large-text");}',theme)
                for key in ['overview']+[s['key'] for s in scenes]:
                    page.evaluate('(key)=>{capture="recording";captureHasPoints=true;enrollment="available";replayVariant="shared";rescheduled=false;scene=key;render();}',key)
                    result=page.evaluate('''()=>({body:document.documentElement.scrollWidth<=innerWidth+1,stage:!!document.querySelector('#stage .phone,#stage .tablet,#stage .desktop'),badButtons:[...document.querySelectorAll('#stage .btn')].filter(x=>x.getBoundingClientRect().width>0&&x.scrollWidth>x.clientWidth+2).map(x=>x.textContent.trim())})''')
                    layouts.append({'scene':key,'width':width,'theme':theme,**result})
        check('all_layouts_have_content_and_no_body_horizontal_overflow',all(x['body'] and x['stage'] for x in layouts),[x for x in layouts if not x['body'] or not x['stage']])
        check('visible_primary_buttons_do_not_clip_text_horizontally',all(not x['badButtons'] for x in layouts),[x for x in layouts if x['badButtons']])
        large=[]
        page.set_viewport_size({'width':390,'height':1000})
        page.evaluate('document.body.classList.add("large-text")')
        for key in [s['key'] for s in scenes]:
            page.evaluate('(key)=>{scene=key;render();}',key)
            large.append({'scene':key,'noBodyOverflow':page.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),'noClippedButtons':page.evaluate('[...document.querySelectorAll("#stage .btn")].every(x=>x.scrollWidth<=x.clientWidth+2)')})
        check('large_text_layout',all(x['noBodyOverflow'] and x['noClippedButtons'] for x in large),[x for x in large if not x['noBodyOverflow'] or not x['noClippedButtons']])
        page.evaluate('document.body.classList.remove("large-text");document.documentElement.dataset.theme="light";')
        page.set_viewport_size({'width':1440,'height':1100})
        def scene(key):page.evaluate('(key)=>{scene=key;render();}',key)
        # No GPS and empty capture must show no false geometry.
        scene('sans-gps');check('no_gps_view_has_no_map',page.locator('#stage .map').count()==0)
        scene('capture');page.select_option('#scenarioSelect','waiting')
        check('first_fix_waiting_has_no_measured_geometry',page.locator('#stage .measured-geometry').count()==0 and 'Aucune mesure sauvegardée' in page.inner_text('#stage'))
        page.click('[data-action="pause"]');page.click('[data-action="resume"]')
        check('pause_resume_without_points_does_not_invent_route',page.locator('#stage .measured-geometry').count()==0)
        page.click('[data-action="stop"]')
        check('stop_empty_does_not_invent_route',page.locator('#stage .measured-geometry').count()==0)
        page.click('[data-action="toBilan"]')
        check('stop_is_not_automatically_lesson_completion',page.locator('dialog[open]').count()==1 and 'Constater la séance' in page.inner_text('dialog'))
        page.click('[data-action="demoCompleted"]')
        check('no_assessment_level_preselected',page.locator('input[name="level"]:checked').count()==0)
        # Pending and confirmed enrolment are different, including calendar presentation.
        page.evaluate('enrollment="available";rescheduled=false;');scene('cours')
        page.click('[data-action="enroll"]');check('explicit_registration_dialog',page.locator('dialog[open]').count()==1)
        check('dialog_has_accessible_label',page.locator('#modal').get_attribute('aria-labelledby')=='modalTitle')
        page.click('[data-action="submitEnrollment"]')
        check('pending_not_confirmed',page.locator('[data-action="confirmResult"]').count()==1 and 'Aucune place n’est encore confirmée.' in page.inner_text('#stage'))
        page.click('[data-action="confirmResult"]');page.click('[data-action="toAgenda"]');page.wait_for_selector('[data-calendar-course="commitment"]')
        check('confirmed_course_moves_to_commitments',page.locator('[data-calendar-course="commitment"]').count()==1 and page.locator('[data-calendar-course="offer"]').count()==0)
        page.click('[data-day="23"]');check('unsimulated_day_does_not_change_visible_selection',page.locator('.daybutton.selected').get_attribute('data-day')=='21')
        scene('cours');page.select_option('#scenarioSelect','full');check('full_course_cannot_register',page.locator('button:disabled').filter(has_text='Complet').count()==1)
        page.select_option('#scenarioSelect','reconfirm');page.click('[data-action="reconfirm"]');page.click('[data-action="demoReconfirm"]')
        check('accepted_new_times_visible','18:30–20:30' in page.inner_text('#stage'))
        scene('pack');check('confirmed_course_right_is_reserved','1 réservé' in page.inner_text('#stage'))
        # Published trace withdrawal does not fall back to private geometries.
        scene('replay');page.select_option('#scenarioSelect','withdrawn');check('withdrawn_trace_has_no_geometry',page.locator('#stage .map').count()==0 and 'Le bilan reste lisible' in page.inner_text('#stage'))
        page.select_option('#scenarioSelect','shared');page.click('[data-action="nextObs"]');check('next_observation_changes_time_and_text','24:50 · Insertion' in page.inner_text('#stage') and page.locator('[data-obs-number]').inner_text()=='2')
        # Browser list operations are local examples only.
        scene('web-eleves');page.fill('#studentSearch','Noé');check('student_search_finds_one','1 dossier fictif' in page.inner_text('#studentCount'))
        page.click('[data-student="1"]');page.click('[data-action="archivePreview"]');check('archive_preview_before_action',page.locator('dialog[open]').count()==1 and 'Archiver ne supprime pas le compte.' in page.inner_text('dialog'))
        page.click('[data-action="demoArchive"]');check('archive_changes_only_demo_state','Dossier archivé' in page.inner_text('#studentDetail'))
        page.click('[data-student="0"]');page.click('[data-action="archivePreview"]');check('future_commitments_block_archive','Archivage bloqué' in page.inner_text('dialog') and page.locator('dialog [data-action="demoArchive"]').count()==0)
        page.keyboard.press('Escape');check('modal_closes_with_escape',page.locator('dialog[open]').count()==0)
        if screens:
            assets=R/'DESIGN/assets';assets.mkdir(exist_ok=True)
            page.evaluate('capture="recording";captureHasPoints=true;enrollment="available";rescheduled=false;replayVariant="shared";replaySecond=674;selectedStudent=0;students[1].status="Actif";')
            for key,name,selector,theme in [('overview','planche-iphone-clair.png','#stage','light'),('overview','planche-iphone-sombre.png','#stage','dark'),('ipad-capture','ipad-capture-clair.png','#stage','light'),('web-eleves','web-eleves-clair.png','#stage','light'),('sans-gps','sans-gps-clair.png','#stage .phone','light'),('cours','cours-clair.png','#stage .phone','light')]:
                page.evaluate('(theme)=>document.documentElement.dataset.theme=theme',theme);scene(key)
                page.locator(selector).screenshot(path=str(assets/name))
            # A mobile viewport of the gallery verifies its own responsive wrapper.
            page.set_viewport_size({'width':390,'height':900});scene('overview')
            page.screenshot(path=str(assets/'galerie-mobile-390.png'),full_page=True)
        check('no_javascript_exceptions',not js_errors,js_errors)
        check('no_external_requests_from_prototype',not requests,requests)
        browser.close()
    report={'version':'3.8','scope':'DOCUMENTARY_HTML_PROTOTYPE_ONLY','loadingMethod':'Playwright set_content; file URLs blocked by environment; relative document links checked separately','nativeTestsExecuted':False,'browserLayoutCases':len(layouts),'largeTextCases':len(large),'checks':checks,'layoutCases':layouts,'largeTextLayouts':large,'passed':not errors,'errors':errors,'limits':['No Swift build, native device or real API.','150% prototype text does not emulate all Dynamic Type categories.','No VoiceOver/TalkBack or user tests.','Body overflow and button bounds are not an exhaustive accessibility audit.']}
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--chromium');p.add_argument('--screens',action='store_true');p.add_argument('--write-report',action='store_true');a=p.parse_args()
    r=run(a.chromium,a.screens)
    if a.write_report:(R/'annexes/verification-prototype-v3-8.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps({k:v for k,v in r.items() if k not in ['layoutCases','largeTextLayouts']},ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
