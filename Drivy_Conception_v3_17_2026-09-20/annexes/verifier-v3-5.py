#!/usr/bin/env python3
"""Additional documentary constraints. Does not execute any Drivy app or service."""
from pathlib import Path
import argparse, json, yaml, re
from jsonschema import Draft202012Validator, FormatChecker
R=Path(__file__).resolve().parents[1]
def check():
 api=yaml.safe_load((R/'04-technique/openapi.yaml').read_text(encoding="utf-8"));S=api['components']['schemas'];errors=[];checks=[]
 def expect(name,ok,detail=None):
  checks.append({'check':name,'passed':bool(ok),'detail':detail})
  if not ok:errors.append({'check':name,'detail':detail})
 text=(R/'04-technique/api.md').read_text(encoding="utf-8")
 expect('No_stale_ETag0_creation_instruction',not bool(re.search(r'valeur de création explicite\s*[`"“]?0',text)))
 expect('Presence_creation_precondition_canonical','If-None-Match: *' in text)
 d=(R/'02-experience/design-system.md').read_text(encoding="utf-8");expect('No_free_school_accent_promise','logo, accent et coordonnées' not in d and 'non configurable au pilote' in d)
 expect('Native_stack_accepted','ACCEPTÉ PAR LE PORTEUR' in (R/'06-gouvernance/glossaire-decisions-questions.md').read_text(encoding="utf-8"))
 expect('Prepared_waypoints_are_contractual','plannedWaypoints' in S['Preparation']['required'] and 'plannedWaypoints' in S['PreparationCommand']['properties'])
 expect('Prepared_waypoints_bounded',S['Preparation']['properties']['plannedWaypoints']['maxItems']==20)
 expect('Course_language_contract',all('teachingLanguage' in S[k]['required'] for k in ['CourseSession','CourseSessionCommand','CalendarOffer']))
 expect('Calendar_language_filter_present',any(p['name']=='teachingLanguage' for p in api['paths']['/v1/schools/{schoolId}/calendar']['get']['parameters']))
 expect('No_inferred_language_audience',S['CourseAudience']['properties']['languages'].get('maxItems')==0)
 expect('Global_receipt_not_normal_session',api['paths']['/v1/account-deletion-status']['get']['security']==[{'deletionReceipt':[]}])
 expect('Global_request_no_client_personId','personId' not in S['AccountDeletionSubmitCommand']['properties'] and not S['AccountDeletionSubmitCommand']['additionalProperties'])
 expect('Receipt_data_minimal',set(S['AccountDeletionReceipt']['properties'])=={'status','updatedAt','messageCode','nextUpdateAt'})
 tr=json.loads((R/'annexes/traceabilite.json').read_text(encoding="utf-8"))
 expect('Stable_original_feature_ids',[f['feature'] for f in tr['features']]==[f'F{x:02d}' for x in range(1,24)])
 catalogue=(R/'01-fonctionnalites-prevues.md').read_text(encoding="utf-8")
 expect('All_features_listed',all(f'[{f["feature"]} ·' in catalogue for f in tr['features']))
 expect('Core_GPS_not_extension','U01 n’est plus une extension' in catalogue)
 expect('Phases_match_catalogue',all(f['phase'] in catalogue for f in tr['features']))
 expected_j=['AP193','AP194','AP195','AP196','AP197','AP198']
 expect('Global_paths_available_without_school',all('schoolId' not in x['path'] for x in tr['apiOperations'] if x['id'] in expected_j))
 old=json.loads((R/'annexes/schemas-base-v3-4.json').read_text(encoding="utf-8"));cases=json.loads((R/'annexes/cas-contrats-v3-5.json').read_text(encoding="utf-8"))['cases'];results=[]
 def valid(components,sch,value):
  wrap={'$schema':'https://json-schema.org/draft/2020-12/schema','allOf':[components['schemas'][sch]],'components':components}
  return Draft202012Validator(wrap,format_checker=FormatChecker()).is_valid(value)
 for c in cases:
  new=valid(api['components'],c['schema'],c['value']);was=valid(old['components'],c['schema'],c['value']) if c['schema'] in old['components']['schemas'] else None
  results.append({'id':c['id'],'schema':c['schema'],'beforeValid':was,'afterValid':new,'expectedAfterValid':c['expectedValid'],'newSchema':was is None,'previouslyAcceptedNowRejected':was is True and new is False and not c['expectedValid']})
  expect('Schema_case_'+c['id'],new==c['expectedValid'])
 comparison={'version':'3.5','scope':'SAME_FICTITIOUS_PAYLOADS_JSON_SCHEMA_ONLY','productTestsExecuted':False,'baseVersion':'3.4','caseCount':len(results),'previouslyAcceptedNowRejected':sum(x['previouslyAcceptedNowRejected'] for x in results),'results':results}
 (R/'annexes/comparaison-contrats-v3-4-v3-5.json').write_text(json.dumps(comparison,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
 return {'version':'3.5','status':'DOCUMENTARY_CHECKS_ONLY','productTestsExecuted':False,'checks':checks,'errorCount':len(errors),'errors':errors,'passed':not errors,'limitations':['Same-shape schema checks do not run server authorization, SQL, encryption or actual deletion.','Contract source and user requirements remain separate from proposed implementation choices.','Scope catalogue is not a list of features implemented or released.']}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');args=p.parse_args();r=check()
 if args.write_report:(R/'annexes/verification-v3-5.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n', encoding="utf-8")
 print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
