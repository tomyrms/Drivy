#!/usr/bin/env python3
"""Verify the documentary reader only. Browser loading via set_content.
Requires BeautifulSoup4, Playwright and Chromium. No native app test.
"""
from pathlib import Path
import argparse,json,shutil
from urllib.parse import urlsplit,unquote
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
def run(chromium=None):
    html=(R/'LIRE_DOSSIER.html').read_text(encoding="utf-8");soup=BeautifulSoup(html,'html.parser');ids=[x['id'] for x in soup.select('[id]')];ids_set=set(ids)
    checks=[];errors=[]
    def check(name,ok,detail=None):
        x={'name':name,'passed':bool(ok),'detail':detail};checks.append(x)
        if not ok:errors.append(x)
    sections=soup.select('section.document');check('75_markdown_documents',len(sections)==75 and len(list(R.rglob('*.md')))==75)
    check('unique_reader_ids',len(ids)==len(ids_set))
    broken=[]
    for a in soup.select('a[href]'):
        u=urlsplit(a['href'])
        if u.scheme or a['href'].startswith('//'):continue
        if not u.path:
            if u.fragment and unquote(u.fragment) not in ids_set:broken.append(a['href'])
        elif not (R/unquote(u.path)).exists():broken.append(a['href'])
    check('reader_links_resolve',not broken,broken[:40])
    with sync_playwright() as p:
        exe=chromium or shutil.which('chromium') or shutil.which('google-chrome')
        browser=p.chromium.launch(headless=True,**({'executable_path':exe} if exe else {}),args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1440,'height':1100});js_errors=[]
        page.on('pageerror',lambda e:js_errors.append(str(e)))
        page.set_content(html,wait_until='load')
        visited=[]
        for section in sections:
            ident=section['id']
            page.evaluate('(id)=>document.querySelector(`a.navlink[data-doc="${id}"]`).click()',ident)
            page.wait_for_function('(id)=>document.getElementById(id).classList.contains("active")',arg=ident)
            visited.append(ident)
        check('all_documents_navigated',len(visited)==75)
        page.fill('#search','Cartographie native');page.wait_for_timeout(100)
        visible=page.locator('.navlink:visible').count();check('search_returns_relevant_subset',0<visible<75,visible)
        page.fill('#search','');page.wait_for_timeout(100)
        check('design_group_present','DESIGN · Direction A' in page.locator('#sidebar').text_content())
        layouts=[]
        for width in [1440,834,390]:
            page.set_viewport_size({'width':width,'height':1000})
            page.evaluate('document.querySelector("a.navlink[data-doc=doc-design-readme]").click()')
            page.wait_for_function('document.querySelector("#doc-design-readme").classList.contains("active")')
            page.wait_for_timeout(80)
            result=page.evaluate('''()=>({width:innerWidth,bodyFits:document.documentElement.scrollWidth<=innerWidth+1,titleTop:document.querySelector('#doc-design-readme h1').getBoundingClientRect().top,headerBottom:document.querySelector('header').getBoundingClientRect().bottom})''')
            layouts.append(result)
            page.screenshot(path=str(R/f'annexes/lecteur-v3-10-{width}.png'),full_page=False)
        check('reader_body_no_horizontal_overflow',all(x['bodyFits'] for x in layouts),layouts)
        check('titles_not_hidden_by_header',all(x['titleTop']>=x['headerBottom']-2 for x in layouts),layouts)
        check('no_reader_js_errors',not js_errors,js_errors)
        browser.close()
    return {'version':'3.10','scope':'DOCUMENTARY_READER_ONLY','loadingMethod':'Playwright set_content; links checked structurally; local file URLs blocked by environment','checks':checks,'passed':not errors,'errors':errors,'nativeTestsExecuted':False,'limits':['No native UI, screen reader or user tests.','Viewport dimensions do not demonstrate physical-device qualification.']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--chromium');p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run(a.chromium)
    if a.write_report:(R/'annexes/verification-lecteur-v3-10.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
