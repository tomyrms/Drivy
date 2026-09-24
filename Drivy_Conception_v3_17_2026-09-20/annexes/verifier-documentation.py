#!/usr/bin/env python3
"""Documentary checks only; no Drivy service or device is exercised.
Requirements: Python 3.11+, PyYAML, jsonschema, markdown-it-py.
Run from any directory: python annexes/verifier-documentation.py
Add --write-report to replace the documentary JSON report (then regenerate hashes).
"""
from __future__ import annotations
import argparse, json, re, unicodedata, hashlib, importlib.util
from pathlib import Path
from urllib.parse import unquote, urlsplit
from collections import Counter
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from markdown_it import MarkdownIt

ROOT=Path(__file__).resolve().parents[1]

def slug(s:str)->str:
    s=s.lower().strip()
    s=re.sub(r'<[^>]+>','',s)
    s=re.sub(r'[^\w\s-]','',s,flags=re.UNICODE)
    return re.sub(r'\s+','-',s)

def main()->dict:
    report={'version':'3.12','status':'DOCUMENTARY_CHECKS_ONLY','productTestsExecuted':False,'errors':[], 'checks':{}}
    errors=report['errors'];checks=report['checks'];files=sorted(ROOT.rglob('*.md'))
    env_spec=importlib.util.spec_from_file_location('documentary_environment',ROOT/'annexes/verifier-environnement.py')
    env_module=importlib.util.module_from_spec(env_spec);env_spec.loader.exec_module(env_module)
    environment=env_module.run();checks['environment']=environment
    if not environment['passed']:
        errors.append({'type':'ENVIRONMENT_NOT_READY','details':environment['errors']})
        report.update({'passed':False,'errorCount':len(errors)});return report
    anchors={};links=[];md=MarkdownIt('commonmark',{'html':True}).enable('table')
    for f in files:
        text=f.read_text(encoding='utf-8'); aset=set(re.findall(r'<a\s+[^>]*id=[\"\']([^\"\']+)[\"\']',text))
        explicit=re.findall(r'<a\s+[^>]*id=[\"\']([^\"\']+)[\"\']',text)
        for key,n in Counter(explicit).items():
            if n>1:errors.append({'type':'DUPLICATE_EXPLICIT_ANCHOR','file':str(f.relative_to(ROOT)),'anchor':key})
        seen=Counter();tokens=md.parse(text)
        for i,t in enumerate(tokens):
            if t.type=='heading_open':
                raw=tokens[i+1].content;b=slug(raw);n=seen[b];seen[b]+=1;aset.add(b+(f'-{n}' if n else ''))
            if t.children:
                for c in t.children:
                    if c.type in ('link_open','image'):
                        href=c.attrGet('href') or c.attrGet('src')
                        if href:links.append((f,href))
        anchors[f.resolve()]=aset
    internal=external=0
    for f,href in links:
        u=urlsplit(href)
        if u.scheme or href.startswith('//'):external+=1;continue
        target=(f.parent/unquote(u.path)).resolve() if u.path else f.resolve();internal+=1
        if not target.is_relative_to(ROOT):errors.append({'type':'LINK_OUTSIDE_DOSSIER','file':str(f.relative_to(ROOT)),'link':href});continue
        if not target.exists():errors.append({'type':'MISSING_LINK_TARGET','file':str(f.relative_to(ROOT)),'link':href});continue
        if u.fragment and target.suffix=='.md' and unquote(u.fragment) not in anchors.get(target,set()):errors.append({'type':'MISSING_ANCHOR','file':str(f.relative_to(ROOT)),'link':href})
    checks['markdown']={'files':len(files),'internalLinks':internal,'externalLinksNotRevalidated':external}
    api=yaml.safe_load((ROOT/'04-technique/openapi.yaml').read_text(encoding='utf-8'))
    operations=[];refs=[]
    def walk(x,path='$'):
        if isinstance(x,dict):
            if '$ref' in x:refs.append((path,x['$ref']))
            for k,v in x.items():walk(v,path+'.'+k)
        elif isinstance(x,list):
            for i,v in enumerate(x):walk(v,path+f'[{i}]')
    walk(api)
    for at,ref in refs:
        if not ref.startswith('#/'):errors.append({'type':'EXTERNAL_SCHEMA_REF','at':at,'ref':ref});continue
        node=api
        try:
            for key in ref[2:].split('/'):node=node[key.replace('~1','/').replace('~0','~')]
        except (KeyError,TypeError):errors.append({'type':'UNRESOLVED_REF','at':at,'ref':ref})
    methodset={'get','post','put','patch','delete','head','options','trace'}
    for p,methods in api['paths'].items():
        for method,o in methods.items():
            if method not in methodset:continue
            operations.append(o['operationId']);names=re.findall(r'{(\w+)}',p)
            params=[*methods.get('parameters',[]),*o.get('parameters',[])]
            pathnames=[x['name'] for x in params if x.get('in')=='path']
            if set(names)!=set(pathnames):errors.append({'type':'PATH_PARAMETERS','path':p,'method':method,'names':names,'params':pathnames})
            if any(not x.get('required',False) for x in params if x.get('in')=='path'):errors.append({'type':'OPTIONAL_PATH_PARAM','path':p})
            if len({(x['in'],x['name']) for x in params})!=len(params):errors.append({'type':'DUPLICATE_PARAMETERS','path':p,'method':method})
    for key,n in Counter(operations).items():
        if n>1:errors.append({'type':'DUPLICATE_OPERATION','id':key})
    example_count=0
    def check_example(schema,value,label):
        nonlocal example_count
        example_count+=1
        v=Draft202012Validator({'$schema':'https://json-schema.org/draft/2020-12/schema','allOf':[schema],'components':api['components']},format_checker=FormatChecker())
        for e in v.iter_errors(value):errors.append({'type':'EXAMPLE_INVALID','label':label,'path':'/'.join(map(str,e.path)),'message':e.message})
    for name,sch in api['components']['schemas'].items():
        try:Draft202012Validator.check_schema(sch)
        except Exception as e:errors.append({'type':'SCHEMA_INVALID','schema':name,'message':str(e)[:700]})
        for i,v in enumerate(sch.get('examples',[])):check_example(sch,v,f'schema:{name}[{i}]')
    ex=json.loads((ROOT/'annexes/exemples-v3.json').read_text(encoding="utf-8"))
    for i,v in enumerate(ex['examples']):check_example(api['components']['schemas'][v['schema']],v['value'],f'annex:{i}:{v["schema"]}')
    schema_annex_count=example_count
    def media_examples(node,path='api'):
        if isinstance(node,dict):
            if isinstance(node.get('schema'),dict):
                if 'example' in node:check_example(node['schema'],node['example'],path+'/example')
                examples=node.get('examples',{})
                if isinstance(examples,dict):
                    for key,ex in examples.items():
                        if isinstance(ex,dict) and 'value' in ex:check_example(node['schema'],ex['value'],path+'/examples/'+key)
            for key,value in node.items():media_examples(value,path+'/'+str(key))
        elif isinstance(node,list):
            for index,value in enumerate(node):media_examples(value,path+'/'+str(index))
    media_examples(api)
    media_count=example_count-schema_annex_count
    case_data={'cases': []}
    for case_file in ['cas-contrats-v3-1-adaptes-v3-6.json','cas-contrats-v3-2-adaptes-v3-7.json','cas-contrats-v3-5-adaptes-v3-6.json','cas-contrats-v3-6.json','cas-contrats-v3-7.json','cas-contrats-v3-10.json','cas-contrats-v3-11.json']:
        case_data['cases'].extend(json.loads((ROOT/'annexes'/case_file).read_text(encoding="utf-8"))['cases'])
    if len({x['id'] for x in case_data['cases']})!=len(case_data['cases']):errors.append({'type':'DUPLICATE_SCHEMA_CASE_ID'})
    case_results=[]
    for case in case_data['cases']:
        schema=api['components']['schemas'].get(case['schema'])
        if schema is None:
            errors.append({'type':'UNKNOWN_CASE_SCHEMA','id':case['id']});continue
        validator=Draft202012Validator({'$schema':'https://json-schema.org/draft/2020-12/schema','allOf':[schema],'components':api['components']},format_checker=FormatChecker())
        validation_errors=list(validator.iter_errors(case['value']))
        actual=not validation_errors;matches=actual==case['expectedValid']
        case_results.append({'id':case['id'],'expectedValid':case['expectedValid'],'actualValid':actual,'passed':matches})
        if not matches:errors.append({'type':'SCHEMA_CASE_EXPECTATION','id':case['id'],'expectedValid':case['expectedValid'],'errors':[e.message for e in validation_errors]})
    checks['schemaRegressions']={'total':len(case_results),'positive':sum(x['expectedValid'] for x in case_results),'negative':sum(not x['expectedValid'] for x in case_results),'passed':all(x['passed'] for x in case_results),'productCodeExercised':False,'results':case_results}
    checks['api']={'operations':len(operations),'schemas':len(api['components']['schemas']),'internalRefsResolved':len(refs),'schemaAndAnnexExamplesChecked':schema_annex_count,'mediaTypeExamplesChecked':media_count,'totalPositiveExamplesChecked':example_count,'openapiVersion':api['openapi'],'fullOpenApiMetaSchemaValidation':False,'note':'YAML, refs, paramètres de routes, schémas JSON2020-12 et exemples seulement ; pas validation OpenAPI complète ou serveur.'}
    trace=json.loads((ROOT/'annexes/traceabilite.json').read_text(encoding="utf-8"))
    definitions={}
    combined='\n'.join(f.read_text(encoding="utf-8") for f in files)
    for prefix,maximum,file in [('R',112,'03-fonctionnel/regles-etats.md'),('J',29,'02-experience/parcours.md'),('E',49,'02-experience/ecrans.md'),('T',434,'05-realisation/tests-recette.md'),('C',72,'01-recherche/inventaire-decisions.md')]:
        text=(ROOT/file).read_text(encoding="utf-8");width=3 if prefix=='T' else 2
        wanted={f'{prefix}{i:0{width}}' for i in range(1,maximum+1)}
        actual={x.upper() for x in re.findall(r'<a id="('+prefix.lower()+r'\d+)"></a>',text)}
        definitions[prefix]=actual
        if actual!=wanted:errors.append({'type':'ID_DEFINITIONS','prefix':prefix,'missing':sorted(wanted-actual),'extra':sorted(actual-wanted)})
    definitions['F']={f'F{i:02}' for i in range(1,24)}
    for f in trace['features']:
        if f'<a id="{f["feature"].lower()}"></a>' not in (ROOT/f['document']).read_text(encoding="utf-8"):errors.append({'type':'FEATURE_ANCHOR','feature':f['feature']})
        for field,prefix in [('capabilities','C'),('journeys','J'),('screens','E'),('rules','R'),('tests','T')]:
            for ident in f.get(field,[]):
                if ident not in definitions[prefix]:errors.append({'type':'TRACE_MISSING_DEFINITION','feature':f['feature'],'field':field,'id':ident})
    # Validate the structured operation catalogue against the actual YAML and prose.
    yaml_ops={o['operationId']:(method,path,o) for path,methods in api['paths'].items() for method,o in methods.items() if method in methodset}
    registry_ops={op['id']:op for op in trace['apiOperations']}
    if len(registry_ops)!=len(trace['apiOperations']):errors.append({'type':'DUPLICATE_API_REGISTRY_ID'})
    if {x['op'] for x in registry_ops.values()}!=set(yaml_ops):errors.append({'type':'API_REGISTRY_SET'})
    prose=(ROOT/'04-technique/api.md').read_text(encoding="utf-8")
    prose_rows={m.group(1):(m.group(2).lower(),m.group(3)) for m in re.finditer(r'^\| (AP\d+) \| `(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) ([^`]+)`',prose,re.M)}
    for ident,entry in registry_ops.items():
        actual=yaml_ops.get(entry['op'])
        if actual and (entry['method'],entry['path'])!=actual[:2]:errors.append({'type':'API_REGISTRY_ROUTE','id':ident})
        if prose_rows.get(ident)!=(entry['method'],entry['path']):errors.append({'type':'API_PROSE_ROUTE','id':ident})
    if set(prose_rows)!=set(registry_ops):errors.append({'type':'API_PROSE_SET'})
    for feature in trace['features']:
        for api_id in feature.get('api',[]):
            if api_id not in registry_ops:errors.append({'type':'FEATURE_API_UNKNOWN','feature':feature['feature'],'id':api_id})
    tests_by_id={x['id']:x for x in trace['tests']}
    if len(tests_by_id)!=len(trace['tests']) or set(tests_by_id)!=definitions['T']:errors.append({'type':'TEST_REGISTRY_IDS'})
    for test in trace['tests']:
        for prefix,field in [('F','features'),('R','rules')]:
            for ident in test[field]:
                if ident not in definitions[prefix]:errors.append({'type':'TEST_UNKNOWN_REFERENCE','test':test['id'],'reference':ident})
        for feature_id in test['features']:
            feature=next((f for f in trace['features'] if f['feature']==feature_id),None)
            if feature and test['id'] not in feature['tests']:errors.append({'type':'MISSING_REVERSE_TEST_LINK','test':test['id'],'feature':feature_id})
    checks['catalogueConsistency']={'apiRegistryEntries':len(registry_ops),'proseApiRows':len(prose_rows),'testRegistryEntries':len(tests_by_id),'methodPathsAndIdentifiersChecked':True,'featureTestReverseLinksChecked':True,'meaning':'Relations documentaires, pas autorisation ni transaction exécutée.'}
    expected={**trace['counts']};measured={'features':len(trace['features']),'capabilities':len(definitions['C']),'rules':len(definitions['R']),'journeys':len(definitions['J']),'screens':len(definitions['E']),'apiOperations':len(operations),'testSpecifications':len(definitions['T'])}
    if expected!=measured:errors.append({'type':'COUNTS','expected':expected,'measured':measured})
    if len(trace['tests'])!=trace['counts']['testSpecifications'] or any(x.get('status')!='NOT_EXECUTED' for x in trace['tests']):errors.append({'type':'TEST_STATUS','message':'Counts/status differ from NOT_EXECUTED design registry.'})
    checks['traceability']=measured
    # Numeric controls are pure checks on fictitious values, not product tests.
    fixture=json.loads((ROOT/'annexes/fixtures-statistiques-v3.json').read_text(encoding="utf-8"));calc={'lessonCount':len(fixture['lessonMinutes']),'durationSeconds':60*sum(fixture['lessonMinutes']),'distinctLearners':len(set(fixture['lessonLearnerKeys'])),'courseFillRatio':sum(fixture['occupiedSeats'])/sum(fixture['courseCapacities']),'netRecordedCents':sum(fixture['receiptsCents'])-sum(fixture['refundsCents']),'netAfterReversalCents':sum(fixture['receiptsCents'])-sum(fixture['refundsCents'])-fixture['reversedReceiptCents']}
    if calc!=fixture['expected']:errors.append({'type':'FIXTURE_ARITHMETIC','actual':calc})
    checks['fictitiousArithmetic']={'calculated':calc,'matches':calc==fixture['expected'],'productCodeExercised':False}
    checks['limitations']=['Aucun build ni test métier exécuté','Aucune qualification réelle GPS/tablette','Aucun entretien utilisateur ou mesure marché','Pas audit juridique, de sécurité ni charge réel','Liens externes historiques non tous revalidés en V3.12','Pas validateur intégral méta-schéma OpenAPI installé']
    module_spec=importlib.util.spec_from_file_location('drivy_contract_lint',ROOT/'annexes/verifier-contrats-transversaux.py')
    module=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(module)
    cross=module.check(ROOT);checks['crossContract']=cross
    errors.extend(cross['errors'])
    report['errorCount']=len(errors);report['passed']=not errors
    return report

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--write-report',action='store_true');args=ap.parse_args()
    result=main()
    if args.write_report:(ROOT/'annexes/verification-documentaire.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if result['passed'] else 1)
