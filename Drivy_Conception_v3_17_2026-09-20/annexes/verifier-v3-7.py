#!/usr/bin/env python3
"""V3.7: contract comparison and documentary reference models.
No Drivy application, database, identity provider or native code is executed.
Requires PyYAML, jsonschema and referencing. Run from any directory.
"""
from pathlib import Path
from copy import deepcopy
import argparse, hashlib, json, re
import yaml
from jsonschema import Draft202012Validator, FormatChecker
ROOT=Path(__file__).resolve().parents[1]
MAX=9007199254740991

def price_model(base, declared, components, prices, selected, override=None, admin=False):
    """Executable interpretation of R108, NOT the future production implementation."""
    def money(x, signed=False):
        if type(x) is not int or not (-MAX if signed else 0) <= x <= MAX:
            raise ValueError('AMOUNT_INVALID')
    for amount in base: money(amount, True)
    money(declared)
    if sum(base) != declared: raise ValueError('BASE_SUM_MISMATCH')
    keys=[p['optionKey'] for p in prices]
    if len(keys)!=len(set(keys)): raise ValueError('DUPLICATE_OPTION_PRICE')
    required={c['optionKey'] for c in components if c['optionKey'] is not None}
    if set(keys)!=required: raise ValueError('OPTION_PRICE_SET_MISMATCH')
    for p in prices: money(p['additionalCents'])
    if len(selected)!=len(set(selected)): raise ValueError('DUPLICATE_SELECTION')
    if not set(selected)<=required: raise ValueError('UNKNOWN_OPTION')
    by_key={p['optionKey']:p['additionalCents'] for p in prices}
    catalog=declared+sum(by_key[k] for k in selected)
    money(catalog)
    agreed=catalog
    if override is not None:
        if not admin: raise ValueError('OVERRIDE_FORBIDDEN')
        if not isinstance(override.get('reason'),str) or not override['reason'].strip():
            raise ValueError('REASON_REQUIRED')
        agreed=override['agreedTotalCents'];money(agreed)
    return {'catalogTotalCents':catalog,'totalCents':agreed}

def check(write=False):
    api=yaml.safe_load((ROOT/'04-technique/openapi.yaml').read_text(encoding="utf-8"))
    S=api['components']['schemas'];checks=[];errors=[]
    def expect(name,ok,detail=None):
        item={'check':name,'passed':bool(ok),'detail':detail};checks.append(item)
        if not ok: errors.append(item)
    ops={op['operationId']:(p,m,op) for p,item in api['paths'].items() for m,op in item.items() if m.lower() in {'get','post','put','patch','delete','head','options'} and isinstance(op,dict)}
    expect('Current_contract_version',api['info']['version']=='3.7.0',api['info']['version'])
    expect('Public_text_selection_explicit','textObservationSelection' in S['PublishCommand']['required'])
    expect('Published_text_has_no_geographic_identifier',not set(S['PublishedTextObservation']['properties']) & {'captureId','draftId','anchor','point','coordinate','latitude','longitude','geometrySnapshotId'})
    expect('Final_report_carries_text_snapshot','textObservations' in S['ReportRevision']['required'])
    expect('Direct_delivery_is_not_a_lesson',S['ServiceDeliveryEvidence']['properties']['productType']['enum']==['EXTERNAL_SERVICE','EXAM_SUPPORT'])
    expect('Delivery_command_owns_no_actor_or_learner',not set(S['RecordServiceDeliveryCommand']['properties']) & {'personId','learnerId','schoolId','recordedBy'})
    close=ops['closeCourseSession'][2]['requestBody']['content']['application/json']['schema']['$ref']
    expect('Course_close_contract_matches_decision',close=='#/components/schemas/CloseCourseCommand')
    for key in ['PackOfferCommand','PackOfferVersion']:
        expect('Explicit_pack_pricing_'+key,{'basePriceLines','optionPrices'}<=set(S[key]['required']))
    expect('Purchase_snapshots_preserved',{'basePriceLinesSnapshot','selectedOptionPricesSnapshot','catalogTotalCents','priceOverride'}<=set(S['Purchase']['required']))
    expect('No_customer_price_in_purchase_command','totalCents' not in S['PurchaseCommand']['properties'])
    preview=ops['listAccountDeletionPreviewMemberships']
    expect('Preview_pagination_global_owner_scope','schoolId' not in preview[0] and '/v1/me/' in preview[0])
    expect('Preview_first_page_bounded',S['AccountDeletionPreview']['properties']['memberships']['maxItems']==100)
    expect('Preview_total_not_artificially_capped','maximum' not in S['AccountDeletionPreview']['properties']['totalMemberships'])
    expect('Deletion_receipt_does_not_restore_session',api['paths']['/v1/account-deletion-status']['get']['security']==[{'deletionReceipt':[]}])
    trace=json.loads((ROOT/'annexes/traceabilite.json').read_text(encoding="utf-8"))
    expect('Trace_contract_version_matches',trace['apiContractVersion']==api['info']['version'])
    expect('Trace_current_document_version',trace['documentVersion']=='3.7')
    expect('Feature_ids_preserved',[f['feature'] for f in trace['features']]==[f'F{x:02d}' for x in range(1,24)])
    expect('New_test_ids_contiguous',[t['id'] for t in trace['tests'][350:]]==[f'T{x:03d}' for x in range(351,383)])
    expect('No_product_test_promoted_to_executed',all(t['status']=='NOT_EXECUTED' for t in trace['tests']))
    catalogue=(ROOT/'01-fonctionnalites-prevues.md').read_text(encoding="utf-8")
    expect('Catalogue_covers_all_features',all(f'[{f["feature"]} ·' in catalogue for f in trace['features']))
    mobile_text=(ROOT/'04-technique/integration-mobile-transverse.md').read_text(encoding="utf-8")
    global_ops={x for x in ops if 'AccountDeletion' in x}
    expect('No_active_claim_global_contract_absent',bool(global_ops) and 'Aucune nouvelle route n’est inventée dans l’OpenAPI de cette passe ; son absence' not in mobile_text)
    expect('Single_global_deletion_mobile_section',len(re.findall(r'^## 8\.',mobile_text,re.M))==1)

    # Same payloads against the original and current contracts; new schema != previous acceptance.
    old=json.loads((ROOT/'annexes/schemas-base-v3-6.json').read_text(encoding="utf-8"))
    cases=json.loads((ROOT/'annexes/cas-contrats-v3-7.json').read_text(encoding="utf-8"))['cases'];results=[]
    def valid(components, schema, value):
        wrapper={'$schema':'https://json-schema.org/draft/2020-12/schema','allOf':[components['schemas'][schema]],'components':components}
        return Draft202012Validator(wrapper,format_checker=FormatChecker()).is_valid(value)
    for c in cases:
        new=valid(api['components'],c['schema'],c['value']);before=c.get('beforeSchema',c['schema'])
        was=valid(old['components'],before,c['value']) if before in old['components']['schemas'] else None
        results.append({'id':c['id'],'schema':c['schema'],'beforeSchema':before,'beforeValid':was,'afterValid':new,'expectedAfterValid':c['expectedValid'],'newSchema':was is None,'comparisonMeaning':c.get('comparisonMeaning','SCHEMA_SHAPE'),'previouslyAcceptedNowRejected':was is True and new is False and not c['expectedValid']})
        expect('Schema_case_'+c['id'],new==c['expectedValid'],c['title'])
    comparison={'version':'3.7','baseVersion':'3.6','scope':'SAME_FICTITIOUS_PAYLOADS_JSON_SCHEMA_ONLY','productTestsExecuted':False,'caseCount':len(results),'previouslyAcceptedNowRejected':sum(x['previouslyAcceptedNowRejected'] for x in results),'results':results}
    # Independently stated amounts and refusals, not production code or school prices.
    default={'base':[100000,-10000,0],'declared':90000,'components':[{'optionKey':None},{'optionKey':'firstAid'},{'optionKey':'firstAid'}],'prices':[{'optionKey':'firstAid','additionalCents':15000}],'selected':[]}
    models=[
      ('PM01','Base avec remise et frais offerts',{}, {'catalogTotalCents':90000,'totalCents':90000}),
      ('PM02','Deux composants, un seul supplément',{'selected':['firstAid']},{'catalogTotalCents':105000,'totalCents':105000}),
      ('PM03','Prix convenu, catalogue conservé',{'selected':['firstAid'],'override':{'agreedTotalCents':100000,'reason':'Accord fictif explicite'},'admin':True},{'catalogTotalCents':105000,'totalCents':100000}),
      ('PM04','Option inconnue',{'selected':['unknown']},'UNKNOWN_OPTION'),
      ('PM05','Option choisie deux fois',{'selected':['firstAid','firstAid']},'DUPLICATE_SELECTION'),
      ('PM06','Clé de prix répétée avec autre montant',{'prices':[{'optionKey':'firstAid','additionalCents':15000},{'optionKey':'firstAid','additionalCents':16000}]},'DUPLICATE_OPTION_PRICE'),
      ('PM07','Prix d’option manquant',{'prices':[]},'OPTION_PRICE_SET_MISMATCH'),
      ('PM08','Prix de base non égal aux lignes',{'declared':89000},'BASE_SUM_MISMATCH'),
      ('PM09','Dérogation sans droit',{'override':{'agreedTotalCents':80000,'reason':'Accord'}},'OVERRIDE_FORBIDDEN'),
      ('PM10','Dérogation sans justification',{'override':{'agreedTotalCents':80000,'reason':'  '},'admin':True},'REASON_REQUIRED'),
      ('PM11','Supplément zéro explicite',{'prices':[{'optionKey':'firstAid','additionalCents':0}],'selected':['firstAid']},{'catalogTotalCents':90000,'totalCents':90000}),
      ('PM12','Dépassement de la borne monétaire',{'base':[MAX],'declared':MAX,'selected':['firstAid']},'AMOUNT_INVALID'),
      ('PM13','Booleen n’est pas un montant',{'base':[True],'declared':1},'AMOUNT_INVALID'),
      ('PM14','Une ligne tarifaire ne crée pas de droit',{'components':[{'optionKey':None}],'prices':[]},{'catalogTotalCents':90000,'totalCents':90000}),
    ]
    mresults=[]
    for ident,title,changes,expected in models:
        args=deepcopy(default);args.update(changes)
        try:actual=price_model(**args)
        except ValueError as exc:actual=str(exc)
        ok=actual==expected;mresults.append({'id':ident,'title':title,'input':args,'expected':expected,'actual':actual,'passed':ok})
        expect('Pricing_reference_model_'+ident,ok,title)
    reference={'version':'3.7','scope':'DOCUMENTARY_REFERENCE_MODEL_ONLY','rule':'R108','productCodeExercised':False,'cases':mresults,'passed':all(x['passed'] for x in mresults),'limitation':'Modèle isolé du dossier : aucune transaction, aucun droit réel, aucun prix d’école ni code serveur ne sont exécutés.'}
    if write:
        (ROOT/'annexes/comparaison-contrats-v3-6-v3-7.json').write_text(json.dumps(comparison,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
        (ROOT/'annexes/verification-modele-prix-v3-7.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    return {'version':'3.7','scope':'DOCUMENTARY_CHECKS_ONLY','productTestsExecuted':False,'checks':checks,'schemaComparisonSummary':{k:v for k,v in comparison.items() if k!='results'},'referenceModelCases':len(mresults),'passed':not errors,'errorCount':len(errors),'errors':errors,'limitations':['No Swift build, PostgreSQL transaction, permission, provider or actual deletion was executed.','JSON shape and reference calculation do not demonstrate all semantic correctness.','Retentions, school commercial policy, last-admin procedure and device qualification remain decisions or future tests.']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args();report=check(args.write_report)
    if args.write_report:(ROOT/'annexes/verification-v3-7.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(0 if report['passed'] else 1)
