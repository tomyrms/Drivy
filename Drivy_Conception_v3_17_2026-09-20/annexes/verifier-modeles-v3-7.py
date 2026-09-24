#!/usr/bin/env python3
"""Executable, isolated interpretations of R109/R111. NOT production code or app tests."""
from pathlib import Path
import argparse,json,math
ROOT=Path(__file__).resolve().parents[1]

def correct_presence(*,present:bool,released:bool,active_consumption:bool,pending:bool):
    if present and released and not active_consumption:
        return {'present':True,'settlement':'REVIEW_REQUIRED','consumedDelta':0,'moneyDelta':0}
    return {'present':present,'settlement':'NOT_REQUIRED' if pending and not present else 'NONE','consumedDelta':0,'moneyDelta':0}

def resolve(*,present:bool,pending:bool,available:int,quantity:int,mode:str,admin:bool):
    if not admin:raise ValueError('FORBIDDEN')
    if not present or not pending:raise ValueError('RIGHT_SETTLEMENT_CHANGED')
    if type(available) is not int or type(quantity) is not int or available<0 or quantity<1:raise ValueError('INVALID_QUANTITY')
    if mode=='WAIVE_CONSUMPTION':return {'settlement':'SETTLED','available':available,'consumedDelta':0,'moneyDelta':0}
    if mode!='CONSUME_FROM_ORIGINAL_LOT':raise ValueError('INVALID_RESOLUTION')
    if available<quantity:raise ValueError('INSUFFICIENT_ENTITLEMENT')
    return {'settlement':'SETTLED','available':available-quantity,'consumedDelta':quantity,'moneyDelta':0}

def admissible(*,measured:float,start:float,stop:float,callback:float,sealed:bool,accuracy,latitude:float=47.,longitude:float=7.):
    # Normalised same-clock toy interval. No hardware, lease, timestamp mapping or signature is validated.
    if accuracy=='NAN':accuracy=float('nan')
    values=(measured,start,stop,callback,accuracy,latitude,longitude)
    if not all(isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x) for x in values):return False
    return not sealed and start<=measured<stop and callback>=measured and accuracy>=0 and -90<=latitude<=90 and -180<=longitude<=180

def check():
    checks=[]
    def run(id,fn,data,expected,title):
        try:actual=fn(**data)
        except ValueError as e:actual=str(e)
        checks.append({'id':id,'title':title,'input':data,'expected':expected,'actual':actual,'passed':actual==expected})
    p={'present':True,'released':True,'active_consumption':False,'pending':False}
    run('RM01',correct_presence,p,{'present':True,'settlement':'REVIEW_REQUIRED','consumedDelta':0,'moneyDelta':0},'Présence exacte sans consommation forcée')
    run('RM02',correct_presence,{**p,'present':False,'pending':True},{'present':False,'settlement':'NOT_REQUIRED','consumedDelta':0,'moneyDelta':0},'Rétraction ferme le suivi sans crédit fictif')
    run('RM03',correct_presence,{**p,'active_consumption':True},{'present':True,'settlement':'NONE','consumedDelta':0,'moneyDelta':0},'Une consommation effective n’est pas redébitée par le fait')
    d={'present':True,'pending':True,'available':1,'quantity':1,'mode':'CONSUME_FROM_ORIGINAL_LOT','admin':True}
    run('RM04',resolve,d,{'settlement':'SETTLED','available':0,'consumedDelta':1,'moneyDelta':0},'Consommation exacte sans argent')
    run('RM05',resolve,{**d,'available':0},'INSUFFICIENT_ENTITLEMENT','Reliquat insuffisant')
    run('RM06',resolve,{**d,'available':0,'mode':'WAIVE_CONSUMPTION'},{'settlement':'SETTLED','available':0,'consumedDelta':0,'moneyDelta':0},'Renonciation sans nouveau droit')
    run('RM07',resolve,{**d,'admin':False},'FORBIDDEN','Habilitation requise')
    run('RM08',resolve,{**d,'present':False},'RIGHT_SETTLEMENT_CHANGED','Fait rétracté')
    run('RM09',resolve,{**d,'pending':False},'RIGHT_SETTLEMENT_CHANGED','Suivi déjà clos')
    run('RM10',resolve,{**d,'quantity':True},'INVALID_QUANTITY','Booléen interdit comme quantité')
    g={'measured':110,'start':100,'stop':200,'callback':120,'sealed':False,'accuracy':4}
    for ident,title,changes,expected in [
      ('GM01','Mesure dans intervalle',{},True),
      ('GM02','Cache avant nouvelle leçon',{'measured':99},False),
      ('GM03','Point postérieur à arrêt',{'measured':201,'callback':202},False),
      ('GM04','Borne d’arrêt exclue',{'measured':200,'callback':202},False),
      ('GM05','Batch tardif non scellé',{'callback':1000},True),
      ('GM06','Callback après scellement',{'sealed':True},False),
      ('GM07','Précision négative',{'accuracy':-1},False),
      ('GM08','Précision non finie',{'accuracy':'NAN'},False),
      ('GM09','Origine géographique possible',{'latitude':0,'longitude':0},True),
      ('GM10','Latitude impossible',{'latitude':91},False),
      ('GM11','Instant de réception impossible',{'callback':109},False),
      ('GM12','Précision zéro conservée si réellement fournie',{'accuracy':0},True)]:
        run(ident,admissible,{**g,**changes},expected,title)
    return {'version':'3.7','scope':'ISOLATED_DOCUMENTARY_MODELS','productCodeExercised':False,'checks':checks,'passed':all(c['passed'] for c in checks),'caseCount':len(checks),'limitations':['No application, sensor, PostgreSQL or APNs was executed.','No OIDC, grant implementation, operation deduplication or concurrent transaction is validated by these pure functions.','GPS times are normalised synthetic values, not proof of mapping between CLLocation timestamps and a monotone clock.','R109 is a proposed policy, not a commercial or legal rule validated with a school.']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args();report=check()
    if args.write_report:(ROOT/'annexes/verification-modeles-v3-7.json').write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n', encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False));raise SystemExit(0 if report['passed'] else 1)
