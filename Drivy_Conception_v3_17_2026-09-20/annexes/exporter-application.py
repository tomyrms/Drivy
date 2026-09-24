#!/usr/bin/env python3
"""Render the unified HTML prototype. Screenshots, not a native-app validation."""
from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw, ImageFont
import argparse,json,datetime
R=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--chromium',default='/usr/bin/chromium');ap.add_argument('--output',type=Path,default=R/'DESIGN/assets/application-v3-17');args=ap.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
ROUTES=[('01_seance','home','Séance'),('02_agenda','agenda','Agenda'),('03_eleves','students','Élèves'),('04_dossier','student','Dossier élève'),('05_lecon','lesson','Leçon'),('06_planifier','planning','Planifier'),('07_rediger','report','Rédiger le bilan'),('08_apercu','preview','Aperçu élève'),('09_bilan_partage','shared','Bilan partagé'),('10_documents','documents','Documents'),('11_compte','account','Mon compte'),('12_notifications','notifications','Notifications'),('13_ecole','school','École'),('14_mes_lecons','learner','Mes leçons'),('15_agenda_eleve','learner-agenda','Agenda élève'),('16_parcours','progress','Mon parcours')]
html=(R/'DESIGN/APPLICATION.html').read_text(encoding='utf-8');items=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=args.chromium,args=['--no-sandbox']);page=b.new_page(viewport={'width':1600,'height':1120},device_scale_factor=1);page.on('pageerror',lambda e:errors.append(str(e)))
 for mode in ['light','dark']:
  for stem,route,label in ROUTES:
   page.goto('about:blank');page.set_content(html)
   if route in ['learner','learner-agenda','progress']:page.evaluate("window.drivy.app.role('learner')")
   elif route in ['student','documents']:page.evaluate("window.drivy.app.show('students')")
   page.evaluate('(p)=>{window.drivy.set({theme:p.theme,size:"phone",reduced:true});window.drivy.app.show(p.route)}',{'theme':mode,'route':route});page.wait_for_timeout(50)
   page.locator('.preview').evaluate('(el,color)=>el.style.background=color','#F1F3F5' if mode=='light' else '#0C1118')
   dest=out/f'{stem}_{mode}.png';page.locator('#device').screenshot(path=str(dest));items.append({'file':dest.name,'route':route,'theme':mode,'size':'390x844','scope':'HTML_FICTITIOUS_DATA'})
 # A wide and a large-text cell are explicit illustrations, not new screens.
 for stem,route,size,scale in [('17_ipad_dossier','student','tablet','normal'),('18_grand_texte','agenda','small','large')]:
  page.goto('about:blank');page.set_content(html);page.evaluate("window.drivy.app.show('students')");page.evaluate('(p)=>{window.drivy.set({theme:"light",size:p.size,scale:p.scale,reduced:true});window.drivy.app.show(p.route)}',dict(route=route,size=size,scale=scale));page.wait_for_timeout(50);page.locator('#device').screenshot(path=str(out/f'{stem}.png'));items.append({'file':stem+'.png','route':route,'theme':'light','size':size,'scale':scale})
 b.close()
font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';font=ImageFont.truetype(font_path,20);title=ImageFont.truetype(font_path,30)
def board(stems,labels,name,heading,mode='light'):
 ims=[Image.open(out/f'{s}_{mode}.png').convert('RGB') for s in stems];pad=26;gap=22;width=2*pad+sum(im.width for im in ims)+gap*(len(ims)-1);height=104+max(im.height for im in ims)+pad;canvas=Image.new('RGB',(width,height),'#F1F3F5' if mode=='light' else '#0C1118');d=ImageDraw.Draw(canvas);col='#18212B' if mode=='light' else '#F2F5FA';d.text((pad,20),heading,font=title,fill=col);x=pad
 for im,lab in zip(ims,labels):d.text((x,68),lab,font=font,fill=col);canvas.paste(im,(x,104));x+=im.width+gap
 canvas.save(out/name)
board(['01_seance','02_agenda','03_eleves','04_dossier'],['Séance','Agenda','Élèves','Dossier élève'],'00_parcours_moniteur_clair.png','Drivy · Un même langage visuel')
board(['01_seance','02_agenda','03_eleves','04_dossier'],['Séance','Agenda','Élèves','Dossier élève'],'00_parcours_moniteur_sombre.png','Drivy · Un même langage visuel','dark')
board(['08_apercu','10_documents','14_mes_lecons','16_parcours'],['Aperçu avant publication','Documents','Espace élève','Parcours pédagogique'],'00_bilans_et_eleve.png','Drivy · Du bilan au parcours élève')
(out/'captures.json').write_text(json.dumps({'generatedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':'3.17','method':'Chromium page.set_content / locator screenshot','screens':items,'errors':errors,'native':'NOT_EXECUTED'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'captures':len(items),'boards':3,'scriptErrors':errors}))
raise SystemExit(bool(errors))
