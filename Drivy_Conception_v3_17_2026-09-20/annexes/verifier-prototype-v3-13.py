#!/usr/bin/env python3
"""Test executable documentary HTML, never the Swift application or a real API.
Python 3.11+, PyYAML, jsonschema, referencing, Playwright and Chromium.
Tests include regression journeys and actual draft DTO shape against OpenAPI.
"""
from pathlib import Path
import argparse, json, shutil, traceback, sys, time
from playwright.sync_api import sync_playwright
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
R = Path(__file__).resolve().parents[1]

def run(chromium=None, screens=False):
    started=time.monotonic(); checks=[]; layouts=[]; large=[]; js_errors=[]; requests=[]; dto_cases=[]
    def check(name, ok, detail=None):
        checks.append({'name':name, 'passed':bool(ok), 'detail':detail}); print(f'{time.monotonic()-started:.1f}s {name}: {bool(ok)}',file=sys.stderr,flush=True)
    scenes=json.loads((R/'DESIGN/scenes.json').read_text(encoding="utf-8"))['scenes']
    html=(R/'DESIGN/MAQUETTES.html').read_text(encoding="utf-8")
    api=yaml.safe_load((R/'04-technique/openapi.yaml').read_text(encoding="utf-8"))
    resource=Resource.from_contents({'$schema':'https://json-schema.org/draft/2020-12/schema',**api})
    registry=Registry().with_resource('urn:drivy:openapi',resource)
    validator=Draft202012Validator({'$ref':'urn:drivy:openapi#/components/schemas/SaveDraftCommand'},registry=registry,format_checker=FormatChecker())
    with sync_playwright() as pw:
        exe=chromium or shutil.which('chromium') or shutil.which('google-chrome')
        b=pw.chromium.launch(headless=True,**({'executable_path':exe} if exe else {}),args=['--no-sandbox'])
        p=b.new_page(viewport={'width':1440,'height':1100},device_scale_factor=1)
        p.set_default_timeout(5000);p.set_default_navigation_timeout(5000)
        p.on('pageerror',lambda e:js_errors.append(str(e)));p.on('request',lambda r:requests.append(r.url))
        def reset(key):
            p.goto('about:blank');p.set_content(html,wait_until='load');p.evaluate('(k)=>{scene=k;render()}',key)
        def scene(key):p.evaluate('(k)=>{rememberFields();scene=k;render()}',key)
        def click(action):p.locator(f'#stage [data-action="{action}"],dialog[open] [data-action="{action}"]').first.click()
        def dto(label,expected=True):
            command=p.evaluate('buildDemoDraft()');errs=[e.message for e in validator.iter_errors(command)]
            dto_cases.append({'name':label,'expectedValid':expected,'valid':not errs,'errors':errs,'command':command})
            check(label,(not errs)==expected,errs)
        reset('overview');check('15_scenes_plus_overview',p.locator('#viewSelect option').count()==16)
        # Render check is narrow: whole-document overflow and actual visible button content bounds.
        for size in [1,2]:
            for width in [320,390,834,1440]:
                p.set_viewport_size({'width':width,'height':1100})
                for theme in ['light','dark']:
                    print(f'layout {size} {width} {theme}',file=sys.stderr,flush=True)
                    p.evaluate('([t,n])=>{document.documentElement.dataset.theme=t;document.body.classList.toggle("large-text",n===2)}',[theme,size])
                    for key in (['overview'] if size==1 else [])+[s['key'] for s in scenes]:
                        p.evaluate('(k)=>{capture="recording";captureHasPoints=true;enrollment="available";replayVariant="shared";replaySecond=674;rescheduled=false;scene=k;render()}',key)
                        result=p.evaluate('''()=>({body:document.documentElement.scrollWidth<=innerWidth+1,content:!!document.querySelector('#stage .phone,#stage .tablet,#stage .desktop'),badButtons:[...document.querySelectorAll('#stage button')].filter(x=>x.getBoundingClientRect().width>0&&x.scrollWidth>x.clientWidth+2).map(x=>({text:x.textContent.trim(),w:x.clientWidth,scroll:x.scrollWidth}))})''')
                        (layouts if size==1 else large).append({'scene':key,'width':width,'theme':theme,'textScale':size,**result})
        check('normal_layouts_no_document_overflow',all(x['body'] and x['content'] for x in layouts),[x for x in layouts if not x['body'] or not x['content']])
        check('normal_buttons_no_horizontal_clipping',all(not x['badButtons'] for x in layouts),[x for x in layouts if x['badButtons']])
        check('200_percent_layouts_no_document_overflow',all(x['body'] and x['content'] for x in large),[x for x in large if not x['body'] or not x['content']])
        check('200_percent_buttons_no_horizontal_clipping',all(not x['badButtons'] for x in large),[x for x in large if x['badButtons']])
        p.set_viewport_size({'width':1440,'height':1100})
        # Role isolation of prototypes: not proof of server authorisation.
        reset('agenda');p.get_by_role('button',name='Consulter la leçon').click();p.wait_for_function('scene==="mes-lecons"')
        check('student_lesson_is_read_only',p.locator('[data-action=start],[data-action=stop],[data-action=toBilan]').count()==0 and 'Mes leçons' in p.inner_text('#stage'))
        check('student_view_only_published_context','dernier bilan publié' in p.inner_text('#stage'))
        check('route_change_focus_not_lost',p.evaluate('document.activeElement!==document.body && !!document.activeElement.closest("#stage")'))
        reset('bilan');p.evaluate('window.scrollTo(0,document.body.scrollHeight);go("mes-lecons")');p.wait_for_function('scene==="mes-lecons"');rect=p.evaluate('(()=>{const r=document.activeElement.getBoundingClientRect();const h=document.querySelector(".top").getBoundingClientRect();return {top:r.top,bottom:r.bottom,headerBottom:h.bottom,height:innerHeight}})()');check('destination_focus_visible_after_long_page',rect['top']>=rect['headerBottom'] and rect['bottom']<=rect['height'],rect)
        reset('web-eleves');p.locator('.sidebar [data-reference]').first.click()
        check('unillustrated_staff_link_does_not_open_student_screen',p.locator('dialog[open]').count()==1 and p.evaluate('scene')=='web-eleves' and p.locator('[data-action=enroll]').count()==0)
        p.keyboard.press('Escape');check('modal_closes_with_escape',p.locator('dialog[open]').count()==0)
        # Capture navigation, stop semantics, empty trace.
        reset('capture');p.locator('#stage .topbar [data-scene="seance"]').click();p.wait_for_function('scene==="seance"')
        check('open_capture_hides_new_start',p.locator('[data-action=start]').count()==0)
        click('openCapture');p.wait_for_function('scene==="capture"')
        check('capture_retains_state_after_close_return',p.evaluate('capture==="recording" && captureHasPoints'))
        p.evaluate('go("sans-gps")');check('no_gps_transition_does_not_silently_drop_capture',p.locator('dialog[open]').count()==1 and p.evaluate('capture==="recording"'));p.keyboard.press('Escape')
        click('pause');check('pause_focus_moves_to_resume',p.evaluate('document.activeElement.dataset.action==="resume"'))
        click('resume');check('resume_focus_moves_to_pause',p.evaluate('document.activeElement.dataset.action==="pause"'))
        p.select_option('#scenarioSelect','waiting');check('waiting_has_no_measured_geometry',p.locator('#stage .measured-geometry').count()==0)
        click('pause');click('resume');check('empty_pause_resume_stays_empty',p.evaluate('capture==="waiting" && !captureHasPoints'))
        click('stop');check('empty_stop_stays_empty',p.locator('#stage .measured-geometry').count()==0)
        click('toBilan');check('stop_does_not_complete_lesson',p.locator('dialog[open]').count()==1 and 'Constater la séance' in p.inner_text('dialog'))
        click('demoCompleted');p.wait_for_function('scene==="bilan"');check('bilan_has_no_default_grade',p.locator('input[name=level]:checked').count()==0)
        reset('sans-gps');check('no_gps_composition_has_no_disabled_map',p.locator('#stage .map').count()==0)
        # Draft semantics: same fields as actual contract; memory only.
        reset('bilan');check('three_required_bilan_fields',all(p.locator('#'+k).count()==1 for k in ['workedOn','observationText','nextStep']))
        dto('draft_without_grade_contract')
        p.locator('#observationText').fill('');click('previewBilan');check('empty_constat_blocks_preview',not p.locator('dialog[open]').count() and p.locator('#observationText').get_attribute('aria-invalid')=='true')
        p.locator('#observationText').fill('Constat saisi <script>nePasExecuter()</script> & exact.');p.locator('#workedOn').fill('Travail UNIQUE à conserver.');click('previewBilan')
        check('preview_uses_edited_text_and_escapes_markup','Travail UNIQUE' in p.inner_text('dialog') and '<script>nePasExecuter()</script>' in p.inner_text('dialog') and p.locator('dialog script').count()==0)
        check('dialog_label_and_initial_focus',p.locator('#modal').get_attribute('aria-labelledby')=='modalTitle' and p.evaluate('document.activeElement.id==="modalTitle"'))
        # Tab cycle must stay in the open modal, excluding browser chrome.
        focused=[]
        for _ in range(6):p.keyboard.press('Tab');focused.append(p.evaluate('!!document.activeElement.closest("dialog")'))
        check('dialog_tab_keeps_focus_inside',all(focused),focused)
        p.keyboard.press('Escape');check('dialog_focus_returns_to_opener',p.evaluate('document.activeElement.dataset.action==="previewBilan"'))
        scene('agenda');scene('bilan');check('draft_fields_retained_across_views',p.locator('#workedOn').input_value()=='Travail UNIQUE à conserver.')
        p.locator('input[value=GUIDED]').check();click('previewBilan');check('observed_grade_requires_context',p.locator('#observationContext').get_attribute('aria-invalid')=='true' and not p.locator('dialog[open]').count())
        p.locator('#observationContext').fill('Après un rappel, à la seconde intersection.');dto('draft_with_grade_and_context_contract');click('previewBilan')
        check('grade_context_in_exact_preview','Après un rappel' in p.inner_text('dialog'));p.keyboard.press('Escape')
        click('clearLevel');check('removing_grade_encodes_absence_not_zero',p.evaluate('buildDemoDraft().observations.length===0') and p.locator('input[name=level]:checked').count()==0);dto('cleared_grade_contract')
        p.locator('#workedOn').fill('A'*4001);click('previewBilan');check('draft_preview_rejects_overlong_text',not p.locator('dialog[open]').count());dto('overlong_draft_rejected_by_contract',False)
        # Native string length must not be simulated by UTF16 truncation in HTML.
        p.locator('#workedOn').fill('😀'*4000);dto('unicode_draft_4000_codepoints_contract');click('previewBilan');check('unicode_draft_not_cut_at_2000_scalars',p.locator('dialog[open]').count()==1);p.keyboard.press('Escape')
        reset('bilan');check('reload_does_not_claim_persistent_draft','UNIQUE' not in p.locator('#workedOn').input_value() and 'localStorage.setItem' not in html and 'indexedDB.open' not in html)
        # Course: unknown outcome does not create another intent; full never reserves credit.
        reset('cours');click('enroll');check('all_course_dates_before_submission','21, 22, 23 et 24' in p.inner_text('dialog'));click('submitEnrollment')
        op=p.evaluate('enrollmentOperationId');check('pending_is_not_confirmation',p.evaluate('enrollment==="pending"'))
        p.select_option('#resultSelect','unknown');click('confirmResult');check('unknown_keeps_same_pending_intent',p.evaluate('enrollment==="pending" && confirmationIssue') and p.evaluate('enrollmentOperationId')==op and p.locator('[data-action=enroll]').count()==0)
        p.select_option('#resultSelect','full');click('confirmResult');check('pending_to_full_has_no_registration',p.evaluate('enrollment==="full"') and p.locator('[data-action=enroll]').count()==0)
        scene('pack');check('refused_course_does_not_reserve_right','1 réservé' not in p.inner_text('#stage'))
        reset('cours');click('enroll');click('submitEnrollment');click('confirmResult');click('toAgenda');p.wait_for_selector('[data-calendar-course="commitment"]')
        check('confirmed_course_moves_to_commitments',p.locator('[data-calendar-course="offer"]').count()==0)
        p.click('[data-day="23"]');check('unsimulated_day_stays_labelled_21',p.locator('.daybutton.selected').get_attribute('data-day')=='21')
        scene('pack');check('only_confirmed_right_is_reserved','1 réservé' in p.inner_text('#stage'))
        scene('cours');p.select_option('#scenarioSelect','reconfirm');click('reconfirm');click('demoReconfirm');check('reconfirmed_time_visible','18:30–20:30' in p.inner_text('#stage'))
        # Recorded timestamps and real breaks in the synthetic canvas data.
        reset('replay');click('nextObs');xy=p.locator('.replay-dot').evaluate('(e)=>[+e.getAttribute("cx"),+e.getAttribute("cy")]')
        check('second_observation_position_matches_timestamp',xy==[575,230],xy)
        check('second_observation_text_matches_time','24:50 · Insertion' in p.inner_text('#stage'))
        p.select_option('#scenarioSelect','partial');p.evaluate('replaySecond=550;updateReplay()')
        check('gap_has_no_moving_position',not p.locator('.replay-dot').is_visible() and p.locator('[data-replay-gap]').is_visible())
        check('gap_has_two_nonconnected_measured_paths',p.locator('path[data-route-segment]').count()==2,p.locator('path[data-route-segment]').count())
        check('gap_boundaries_remain_real_samples',p.evaluate('replayPosition(480,true)!==null && replayPosition(620,true)!==null && replayPosition(550,true)===null'))
        p.evaluate('replaySecond=0;updateReplay()');check('no_future_observation_shown','Aucune observation à cet instant' in p.inner_text('#stage'))
        click('nextObs');check('next_from_start_goes_first_annotation',p.evaluate('replaySecond===674'))
        p.select_option('#scenarioSelect','withdrawn');check('withdrawn_replay_contains_no_geometry',p.locator('#stage .map').count()==0 and 'Le bilan reste lisible' in p.inner_text('#stage'))
        # Keyboard and context in management actions.
        reset('web-eleves');p.fill('#studentSearch','Noé');p.select_option('#studentFilter','active');p.click('[data-student="1"]');click('archivePreview')
        check('archive_preview_explains_not_account_deletion','Archiver ne supprime pas le compte.' in p.inner_text('dialog'));click('demoArchive')
        check('archive_retains_query_filter',p.input_value('#studentSearch')=='Noé' and p.input_value('#studentFilter')=='active')
        check('hidden_archived_selection_removed',p.locator('[data-action=archivePreview]').count()==0 and 'Aucun dossier sélectionné' in p.inner_text('#studentDetail'))
        check('archive_focus_returns_to_search',p.evaluate('document.activeElement.id==="studentSearch"'))
        p.fill('#studentSearch','');p.select_option('#studentFilter','all');check('filter_can_be_cleared','5 dossiers' in p.inner_text('#studentCount'))
        p.click('[data-student="1"]');check('archive_is_visible_on_explicit_reselection','Dossier archivé' in p.inner_text('#studentDetail'))
        p.click('[data-student="0"]');click('archivePreview');check('future_commitments_still_block_archive','Archivage bloqué' in p.inner_text('dialog') and not p.locator('dialog [data-action=demoArchive]').count());p.keyboard.press('Escape')
        p.fill('#studentSearch','introuvable');check('empty_filter_has_no_stale_dossier',p.locator('[data-action=archivePreview]').count()==0 and 'Emma Laurent' not in p.inner_text('#studentDetail'))
        reset('profil');p.locator('#firstName').fill('Prénom de démo');scene('agenda');scene('profil');check('onboarding_memory_retained',p.locator('#firstName').input_value()=='Prénom de démo')
        input_=p.locator('#firstName');normal=input_.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');p.check('#largeText');big=input_.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');check('form_text_genuinely_doubles',abs(big/normal-2)<.01,{'normal':normal,'large':big})
        reset('bilan');sp=p.locator('.choice span').first;n=sp.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');p.check('#largeText');v=sp.evaluate('(e)=>parseFloat(getComputedStyle(e).fontSize)');check('grade_labels_genuinely_double',abs(v/n-2)<.01,{'normal':n,'large':v})
        reset('web-ecole');p.locator('input[name="category"][value="A1"]').uncheck();scene('web-eleves');scene('web-ecole');check('school_choices_remain_demo_memory',not p.locator('input[name="category"][value="A1"]').is_checked())
        p.evaluate('location.hash="%ZZ"');p.wait_for_function('scene==="overview"');check('malformed_hash_falls_back_safely',p.locator('#stage .phone').count()==3)
        if screens:
            assets=R/'DESIGN/assets'
            for key,name,selector,theme in [('overview','planche-iphone-clair.png','#stage','light'),('overview','planche-iphone-sombre.png','#stage','dark'),('ipad-capture','ipad-capture-clair.png','#stage','light'),('web-eleves','web-eleves-clair.png','#stage','light'),('sans-gps','sans-gps-clair.png','#stage .phone','light'),('cours','cours-clair.png','#stage .phone','light'),('mes-lecons','eleve-mes-lecons.png','#stage .phone','light'),('bilan','bilan-constat.png','#stage .phone','light')]:
                reset(key);p.evaluate('(t)=>document.documentElement.dataset.theme=t',theme);p.locator(selector).screenshot(path=str(assets/name))
            reset('replay');p.select_option('#scenarioSelect','partial');p.evaluate('replaySecond=550;updateReplay()');p.locator('#stage .phone').screenshot(path=str(assets/'replay-interruption.png'))
            p.set_viewport_size({'width':320,'height':900});reset('bilan');p.check('#largeText');p.screenshot(path=str(assets/'bilan-320-texte-200.png'),full_page=True)
            p.set_viewport_size({'width':390,'height':900});reset('overview');p.screenshot(path=str(assets/'galerie-mobile-390.png'),full_page=True)
        # about:blank is local and expected, unlike a provider call.
        check('no_javascript_exceptions',not js_errors,js_errors)
        external=[x for x in requests if x.startswith(('http:','https:'))];check('no_external_prototype_requests',not external,external)
        b.close()
    errors=[x for x in checks if not x['passed']]
    return {'version':'3.13','scope':'DOCUMENTARY_HTML_PROTOTYPE_ONLY','nativeTestsExecuted':False,'apiVersion':api['info']['version'],'browserLayoutCases':len(layouts),'largeTextCases':len(large),'largeTextFactor':2,'checks':checks,'layoutCases':layouts,'largeTextLayouts':large,'draftContractCases':dto_cases,'passed':not errors,'errors':errors,'limits':['No native Swift, real API, geolocation, APNs or school data.','200% CSS text is not native Dynamic Type or a complete WCAG audit.','Measured bounds do not exhaustively test all collisions; manual visual review remains necessary.','Edited demonstration values are in-memory only and reset on page reload.']}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--screens',action='store_true');ap.add_argument('--write-report',action='store_true');a=ap.parse_args()
    r=run(a.chromium,a.screens)
    if a.write_report:(R/'annexes/verification-prototype-v3-13.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps({k:v for k,v in r.items() if k not in ['layoutCases','largeTextLayouts','draftContractCases']},ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
