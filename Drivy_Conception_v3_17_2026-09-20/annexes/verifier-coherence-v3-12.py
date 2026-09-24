#!/usr/bin/env python3
"""Fail-closed consistency checks introduced by Drivy V3.12.
Documentary checks only: no app, API, database, device or user test is executed.
"""
from pathlib import Path
import argparse, json, re
import yaml
R=Path(__file__).resolve().parents[1]

def run():
    checks=[]; errors=[]
    def check(name, ok, detail=None):
        row={'name':name,'passed':bool(ok),'detail':detail}; checks.append(row)
        if not ok: errors.append(row)

    read=lambda rel:(R/rel).read_text(encoding='utf-8')
    readme=read('README.md'); start=read('COMMENCER_ICI.md'); summary=read('00-synthese.md')
    glossary=read('06-gouvernance/glossaire-decisions-questions.md')
    roadmap=read('05-realisation/roadmap-backlog.md')
    tests=read('05-realisation/tests-recette.md')
    design=read('DESIGN/04-ecrans-reference.md')
    research=read('01-recherche/vision-perimetre.md')
    api=yaml.safe_load(read('04-technique/openapi.yaml'))

    md_count=len(list(R.rglob('*.md')))
    check('markdown_count_matches_release', md_count==79 and '79 documents Markdown' in readme, md_count)
    check('active_release_branding', readme.startswith('# Drivy · Dossier de conception V3.12') and '**Drivy**' in summary and 'Référence active 3.12' in start)
    check('contract_brand_and_independent_version', api['info']['title'].startswith('Drivy ·') and api['info']['version']=='3.11.0', api['info'])

    decisions=re.findall(r'^### D(\d{2}) ·',glossary,re.M)
    expected_d=[f'{i:02}' for i in range(1,34)]
    check('D01_D33_exactly_once_in_order', decisions==expected_d, decisions)
    dsections=re.split(r'(?=^### D\d{2} ·)',glossary,flags=re.M)[1:]
    missing_status=[sec.splitlines()[0] for sec in dsections if '**Statut :**' not in sec.split('\n### ',1)[0].split('\n## ',1)[0]]
    check('all_decisions_have_explicit_status', not missing_status, missing_status)

    questions=re.findall(r'^### Q(\d{2}) ·',glossary,re.M)
    expected_q=[f'{i:02}' for i in range(1,15)]
    check('Q01_Q14_exactly_once_in_order', questions==expected_q, questions)
    dash=glossary.split('### Tableau de pilotage des questions ouvertes',1)[1].split('### Q01',1)[0] if '### Tableau de pilotage des questions ouvertes' in glossary else ''
    missing_dashboard=[x for x in [*(f'Q{i:02}' for i in range(1,15)),'DM06','DM07'] if x not in dash]
    check('open_questions_have_gate_dashboard', not missing_dashboard, missing_dashboard)

    check('DM07_fail_closed_quality_rule', '## DM07 · Budgets non fonctionnels et preuves de qualité' in roadmap and '`NOT_QUALIFIED`' in roadmap)
    check('generic_acceptance_action_removed', "Réaliser l'action décrite" not in tests and 'Réaliser l’action décrite' not in tests)
    check('design_risk_priority_present', '## Priorité de couverture avant implémentation' in design and all(x in design for x in ['E05','E17','E19','E21','E42','E44','E49']))
    check('research_evidence_template_present', '### Fiche de preuve pour chaque session de recherche' in research and 'observation' in research.lower() and 'interprétation' in research.lower())
    check('current_audit_linked_from_entrypoints', all('audit-corrections-v3-12.md' in x for x in [readme,start,read('01-fonctionnalites-prevues.md')]))
    check('historical_brand_exception_explained', ('preuves historiques' in start.lower() or 'anciennes preuves' in start.lower()) and 'identifiants techniques' in start.lower())

    return {
        'version':'3.12','scope':'DOCUMENTARY_COHERENCE_ONLY','checks':checks,
        'passed':not errors,'errorCount':len(errors),'errors':errors,
        'productTestsExecuted':False,'nativeBuildExecuted':False,
        'limits':['Checks establish internal documentary invariants only.','They do not validate product usability, safety, performance, legal compliance or implementation.']
    }

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-coherence-v3-12.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
