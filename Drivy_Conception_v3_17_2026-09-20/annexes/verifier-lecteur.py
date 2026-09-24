#!/usr/bin/env python3
"""Tests the offline documentation reader, not the Drivy app.
Requires Playwright and a Chromium installation. --chromium overrides its path.
"""
from pathlib import Path
import argparse,json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
def main(executable):
 results=[];errors=[];console=[]
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True,executable_path=executable,args=['--no-sandbox'])
  page=browser.new_page(viewport={'width':1440,'height':1000})
  page.on('pageerror',lambda err:console.append(str(err)))
  page.set_content((ROOT/'LIRE_DOSSIER.html').read_text(encoding="utf-8"),wait_until='load')
  links=page.locator('.navlink').evaluate_all('(xs)=>xs.map(x=>({id:x.dataset.doc,href:x.getAttribute("href")}))')
  for item in links:
   page.evaluate('(id)=>{location.hash=id}',item['id'])
   page.wait_for_function('(id)=>document.querySelector(".document.active")?.id===id',arg=item['id'],timeout=3000)
  results.append({'check':'allDocumentRoutes','count':len(links),'passed':True})
  anchors=page.evaluate('''()=>{const ids=[...document.querySelectorAll('[id]')].map(x=>x.id); const missing=[...document.querySelectorAll('a[href^="#"]')].map(x=>decodeURIComponent(x.getAttribute('href').slice(1))).filter(x=>x&&!document.getElementById(x));return {idCount:ids.length,duplicateIds:ids.filter((x,i)=>ids.indexOf(x)!==i),missingAnchors:missing};}''')
  if anchors['missingAnchors'] or anchors['duplicateIds']:errors.append({'type':'ANCHORS','detail':anchors})
  results.append({'check':'domAnchors','passed':not anchors['missingAnchors'] and not anchors['duplicateIds'],**anchors})
  page.locator('#search').fill('geometrySnapshotId');count=page.locator('.navlink:visible').count()
  if not count:errors.append({'type':'SEARCH_NO_MATCH'})
  page.locator('#search').fill('zzzz_impossible_search_12345');hidden=page.locator('.navlink:visible').count()
  if hidden:errors.append({'type':'SEARCH_FILTER_FAILURE'})
  page.locator('#search').fill('');label=page.locator('#searchcount').inner_text()
  if f'{len(links)} documents' not in label:errors.append({'type':'SEARCH_RESET_COUNT','label':label})
  results.append({'check':'searchAndReset','matchedDocuments':count,'noMatchVisible':hidden,'resetText':label,'passed':bool(count) and hidden==0 and f'{len(links)} documents' in label})
  for width,height in [(1440,1000),(834,1112),(390,844)]:
   page.set_viewport_size({'width':width,'height':height})
   page.evaluate("location.hash='doc-06-gouvernance-audit-corrections-v3-7'; route()")
   page.wait_for_timeout(120)
   overflow=page.evaluate('document.documentElement.scrollWidth>window.innerWidth+1')
   if overflow:errors.append({'type':'PAGE_OVERFLOW','width':width})
   if width<850:
    page.locator('#menu').click();opened=page.locator('#menu').get_attribute('aria-expanded')=='true';page.keyboard.press('Escape');closed=page.locator('#menu').get_attribute('aria-expanded')=='false'
    if not (opened and closed):errors.append({'type':'MENU','width':width})
   title_top=page.locator('.document.active h1').evaluate('(el)=>el.getBoundingClientRect().top');header_bottom=page.locator('header').evaluate('(el)=>el.getBoundingClientRect().bottom')
   if title_top<header_bottom:errors.append({'type':'HEADING_UNDER_FIXED_HEADER','width':width,'titleTop':title_top,'headerBottom':header_bottom})
   path=ROOT/'annexes'/f'lecteur-v3-7-{width}.png';page.screenshot(path=str(path),full_page=False)
   results.append({'check':'responsiveReader','width':width,'height':height,'horizontalPageOverflow':overflow,'titleBelowHeader':title_top>=header_bottom,'screenshot':str(path.relative_to(ROOT)),'passed':not overflow})
  # An actual deep-link navigation on the current document.
  page.evaluate("location.hash='doc-06-gouvernance-audit-corrections-v3-7--apports'")
  page.wait_for_timeout(100)
  results.append({'check':'deepLinkMobileChanges','passed':page.locator('.document.active').get_attribute('id')=='doc-06-gouvernance-audit-corrections-v3-7'})
  browser_version=browser.version;browser.close()
 if console:errors.append({'type':'JAVASCRIPT_ERRORS','errors':console})
 report={'version':'3.7','status':'DOCUMENT_READER_TESTS_ONLY','productTestsExecuted':False,'browser':browser_version,'loadMode':'set_content, car la politique Chromium de cet environnement bloque file:// ; liens internes testés, ouverture locale file:// non testée','chromiumExecutable':executable,'checks':results,'errors':errors,'passed':not errors,'limitations':['Fenêtres simulées dans Chromium, pas essais sur téléphone ou tablette physiques.','Ce lecteur présente les documents, pas des écrans implémentés de Drivy.','Le rendu final des documents a été observé via captures ; pas de maquettes haute fidélité créées.']}
 (ROOT/'annexes/verification-lecteur.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n', encoding="utf-8");print(json.dumps(report,ensure_ascii=False,indent=2));return not errors
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--chromium',default='/usr/bin/chromium');a=ap.parse_args();raise SystemExit(0 if main(a.chromium) else 1)
