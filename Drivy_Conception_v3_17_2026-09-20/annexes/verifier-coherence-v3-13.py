#!/usr/bin/env python3
"""Fail-closed documentary consistency checks for Drivy V3.13.
No app, API, database, device, road or user test is executed.
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
    perimeter=read('05-realisation/perimetre-premiere-livraison.md')
    tests=read('05-realisation/tests-recette.md')
    design=read('DESIGN/04-ecrans-reference.md')
    research=read('01-recherche/vision-perimetre.md')
    api=yaml.safe_load(read('04-technique/openapi.yaml'))

    md_count=len(list(R.rglob('*.md')))
    check('markdown_count_matches_release', md_count==80 and '80 documents Markdown' in readme, md_count)
    check('official_brand_is_drivy', readme.startswith('# Drivy · Dossier de conception V3.13') and '**Drivy**' in summary and 'Référence active 3.13' in start)
    wrong=[]
    for p in R.rglob('*'):
        if not p.is_file(): continue
        try: txt=p.read_text(encoding='utf-8')
        except UnicodeDecodeError: continue
        if ('dri'+'vey') in txt.lower(): wrong.append(str(p.relative_to(R)))
    check('wrong_brand_spelling_absent_from_text_artifacts', not wrong, wrong[:30])
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
    check('definition_of_ready_present', '## Définition d’une tranche prête à développer' in roadmap and 'NOT_READY' in roadmap and all(x in roadmap for x in ['Action et utilisateur','Source de vérité','Persistance minimale','Preuve attendue']))
    check('vertical_implementation_profile_present', '## Profil d’implémentation G1/G2' in perimeter and all(x in perimeter for x in ['G1A · Accès et école','G1B · Configuration minimale','G2A · Leçon sans GPS','G2B · Capture et observation live','G2C · Continuité']))
    check('physical_split_requires_reason', all(x in perimeter for x in ['cycle de vie ou autorisation indépendante','rétention, purge ou restauration indépendante','preuve de performance']))
    check('registry_not_physical_plan', 'Il n’est pas un plan de migrations.' in perimeter and 'ne reçoit pas une table par défaut' in perimeter)
    check('generic_acceptance_action_removed', "Réaliser l'action décrite" not in tests and 'Réaliser l’action décrite' not in tests)
    check('design_risk_priority_present', '## Priorité de couverture avant implémentation' in design and all(x in design for x in ['E05','E17','E19','E21','E42','E44','E49']))
    check('research_evidence_template_present', '### Fiche de preuve pour chaque session de recherche' in research and 'observation' in research.lower() and 'interprétation' in research.lower())
    check('current_audit_linked_from_entrypoints', all('audit-corrections-v3-13.md' in x for x in [readme,start,read('01-fonctionnalites-prevues.md')]))

    return {
        'version':'3.13','scope':'DOCUMENTARY_COHERENCE_ONLY','checks':checks,
        'passed':not errors,'errorCount':len(errors),'errors':errors,
        'productTestsExecuted':False,'nativeBuildExecuted':False,
        'limits':['Checks establish internal documentary invariants only.','They do not validate product usability, safety, performance, legal compliance or implementation.']
    }

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write-report',action='store_true');a=p.parse_args();r=run()
    if a.write_report:(R/'annexes/verification-coherence-v3-13.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(r,ensure_ascii=False,indent=2));raise SystemExit(0 if r['passed'] else 1)
