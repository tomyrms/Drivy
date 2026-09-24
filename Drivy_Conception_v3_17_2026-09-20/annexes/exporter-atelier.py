#!/usr/bin/env python3
"""Export actual browser views to PNG and SVG. No Figma API or native app.
Install requirements-export.txt; use --output outside the source tree.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image,ImageDraw,ImageFont
import json,argparse
R=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--chromium');ap.add_argument('--output',type=Path,required=True);ap.add_argument('--font',type=Path);ap.add_argument('--font-bold',type=Path);args=ap.parse_args()
O=args.output;O.mkdir(parents=True,exist_ok=True);V=R/'DESIGN/vecteurs';V.mkdir(exist_ok=True)
export=(R/'DESIGN/atelier/export-svg.js').read_text(encoding='utf-8')
with sync_playwright() as p:
 b=p.chromium.launch(**({'executable_path':args.chromium} if args.chromium else {}),args=['--no-sandbox'])
 page=b.new_page(viewport={'width':1550,'height':1120},device_scale_factor=2)
 page.set_content((R/'DESIGN/LECON.html').read_text(encoding='utf-8'))
 for theme in ['light','dark']:
  for i,view in enumerate(['capture','categories','status','replay'],1):
   page.evaluate('v=>{window.drivy.set({theme:v.theme,scale:"normal",size:"phone",reduced:true});window.drivy.view(v.view)}',{'theme':theme,'view':view})
   page.wait_for_timeout(250);page.mouse.move(0,0);page.evaluate('document.activeElement?.blur()');
   page.locator('#device').screenshot(path=str(O/f'{i:02d}_{view}_{theme}.png'))
   svg=page.evaluate(export);(V/f'{i:02d}_{view}_{theme}.svg').write_text(svg,encoding='utf-8')
 for key,patch,view in [('05_sans_gps',{'environment':'no-gps'},'capture'),('06_hors_ligne',{'environment':'offline'},'capture'),('07_grand_texte',{'environment':'normal','scale':'large','size':'small'},'categories'),('08_ipad',{'environment':'normal','scale':'normal','size':'tablet'},'capture')]:
  page.evaluate('p=>window.drivy.set({theme:"light",size:"phone",scale:"normal",...p})',patch);page.evaluate('v=>window.drivy.view(v)',view);page.wait_for_timeout(180);page.evaluate('document.activeElement?.blur()');page.locator('#device').screenshot(path=str(O/f'{key}.png'))
 for theme in ['light','dark']:
  page.evaluate('p=>{window.drivy.set({theme:p,scale:"normal",size:"phone",environment:"normal",mapDetail:"dense"});window.drivy.density(true);window.drivy.view("replay")}',theme)
  page.wait_for_timeout(250);page.mouse.move(0,0);page.evaluate('document.activeElement?.blur()');page.locator('#device').screenshot(path=str(O/f'10_dense_replay_{theme}.png'))
  page.locator('#device [data-action=list]').click();page.wait_for_timeout(250);page.mouse.move(0,0);page.evaluate('document.activeElement?.blur()');page.locator('#device').screenshot(path=str(O/f'11_dense_liste_{theme}.png'))
 page.evaluate('window.drivy.density(false);window.drivy.set({mapDetail:"calm"})')
 page.evaluate('window.drivy.set({size:"phone",scale:"normal",environment:"normal",theme:"light"});window.drivy.view("capture")');page.wait_for_timeout(150);page.evaluate('document.activeElement?.blur()');page.screenshot(path=str(O/'09_atelier.png'),full_page=True)
 b.close()
# Contact sheets are composites of actual browser screenshots, not independent generated mockups.
def font_at(size,bold=False):
 path=args.font_bold if bold and args.font_bold else args.font
 return ImageFont.truetype(str(path),size) if path else ImageFont.load_default(size=size)
for theme in ['light','dark']:
 W=1768;H=1084;bg='#F7F8FA' if theme=='light' else '#10151C';fg='#18212B' if theme=='light' else '#F2F5FA';mut='#536174' if theme=='light' else '#B0BCCC'
 sheet=Image.new('RGB',(W,H),bg);draw=ImageDraw.Draw(sheet)
 draw.text((56, thirty:=30),'Drivy',font=font_at(36,True),fill=fg)
 draw.text((200,45),'La carte d’abord.',font=font_at(21),fill=mut)
 labels=['01  La leçon','02  Signaler','03  Qualifier','04  Revoir']
 for i,(view,label) in enumerate(zip(['capture','categories','status','replay'],labels)):
  x=56+i*420
  draw.text((x,100),label,font=font_at(16,True),fill=fg)
  im=Image.open(O/f'{i+1:02d}_{view}_{theme}.png').convert('RGBA').resize((390,844),Image.Resampling.LANCZOS)
  # Screenshots have transparent outer corners. Preserve the surrounding background.
  mask=Image.new('L',im.size,0);ImageDraw.Draw(mask).rounded_rectangle((0,0,389,843),radius=44,fill=255);sheet.paste(im,(x,138),mask)
 draw.text((56,1012),'V3.16 · Quatre vues du prototype interactif · Données fictives · Aucun GPS ni service réel',font=font_at(16),fill=mut)
 draw.text((56,1042),'Direction retenue : composition cartographique, signalement rapide, hiérarchie claire et peu de texte.',font=font_at(14),fill=mut)
 sheet.save(O/f'00_parcours_{theme}.png')
print('Rendered PNGs and vector views')
