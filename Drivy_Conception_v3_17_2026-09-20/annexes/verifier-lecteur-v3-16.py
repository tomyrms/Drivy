#!/usr/bin/env python3
"""Focused reader and complementary-gallery smoke tests, not a native test suite."""
from pathlib import Path
from urllib.parse import urlsplit,unquote
from collections import Counter
import json,argparse,platform
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
def main(args):
    checks=[];errors=[]
    def ck(name,ok,details=None):checks.append(dict(check=name,passed=bool(ok),details=details))
    text=(R/'LIRE_DOSSIER.html').read_text(encoding='utf-8');soup=BeautifulSoup(text,'html.parser');counts=Counter(x['id'] for x in soup.select('[id]'))
    ck('Reader title V3.16','V3.16' in soup.title.text)
    ck('Every Markdown file is a reader section',len(soup.select('section.document'))==len(list(R.rglob('*.md'))))
    ck('Unique reader ids',all(n==1 for n in counts.values()))
    broken=[]
    for tag in soup.select('a[href],img[src]'):
        ref=tag.get('href',tag.get('src'));url=urlsplit(ref)
        if url.scheme or ref.startswith('//'):continue
        if not url.path:
            if url.fragment and unquote(url.fragment) not in counts:broken.append(ref)
        elif not (R/unquote(url.path)).exists():broken.append(ref)
    ck('Reader internal links and images resolve',not broken,broken)
    current=soup.select_one('#doc-06-gouvernance-audit-corrections-v3-16');old=soup.select_one('#doc-06-gouvernance-audit-corrections-v3-15')
    ck('Current audit distinguished from historical audit',current is not None and old is not None and not current.find('blockquote',string=lambda x:x and x.startswith('Historique :')) and bool(old.find('blockquote',string=lambda x:x and x.startswith('Historique :'))))
    with sync_playwright() as p:
        b=p.chromium.launch(**({'executable_path':args.chromium} if args.chromium else {}),args=['--no-sandbox']);page=b.new_page(viewport={'width':1440,'height':1000});page.on('pageerror',lambda e:errors.append(str(e)));page.set_default_timeout(5000)
        page.set_content(text);page.wait_for_timeout(200)
        ck('Reader starts with one document',page.locator('.document:visible').count()==1)
        page.evaluate('location.hash="#doc-design-readme"');page.wait_for_timeout(120)
        ck('Route resolves to design entry',page.locator('#doc-design-readme').is_visible())
        page.locator('#search').fill('zzzznonexistent315');ck('Search filters navigation',page.locator('.navlink:visible').count()==0)
        page.locator('#search').fill('');ck('Clear restores navigation',page.locator('.navlink:visible').count()>0)
        page.set_viewport_size({'width':390,'height':844});page.locator('#menu').click();ck('Mobile contents opens',page.locator('#menu').get_attribute('aria-expanded')=='true');page.keyboard.press('Escape');ck('Escape closes contents',page.locator('#menu').get_attribute('aria-expanded')=='false')
        page.goto('about:blank');page.set_content((R/'DESIGN/MAQUETTES.html').read_text(encoding='utf-8'));page.wait_for_timeout(160)
        ck('Complementary gallery advertises current reference',page.locator('a[href="LECON.html"]').count()>0)
        ck('Complementary gallery loads without JS error',not errors,errors)
        version=b.version;b.close()
    return {'version':'3.16','scope':'READER_AND_COMPLEMENTARY_GALLERY_SMOKE_ONLY','passed':all(x['passed'] for x in checks),'errorCount':sum(not x['passed'] for x in checks),'checks':checks,'environment':{'python':platform.python_version(),'browser':version},'previousFullGalleryInteractions':'NOT_RERUN','nativeTestsExecuted':False}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--chromium');p.add_argument('--write-report',action='store_true');a=p.parse_args();r=main(a)
    if a.write_report:(R/'annexes/verification-lecteur-v3-16.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
