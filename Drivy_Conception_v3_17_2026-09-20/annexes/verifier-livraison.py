#!/usr/bin/env python3
"""Fail-closed documentary suite. Temporary output files avoid inherited-pipe deadlocks.
No product tests are executed. Browser or process timeouts are failures, not successes.
"""
from __future__ import annotations
import argparse, datetime, json, os, signal, subprocess, sys, tempfile, time
from pathlib import Path
R=Path(__file__).resolve().parents[1]
CORE=['verifier-environnement.py','verifier-documentation.py','verifier-visuel-v3-16.py']
BROWSER=['verifier-atelier-v3-16.py','verifier-lecteur-v3-16.py']
def execute(cmd,timeout,env):
    # Grandchildren can keep inherited pipes open after the Python checker is killed.
    # Regular temporary files and whole-process-group termination make timeout bounded.
    with tempfile.TemporaryFile() as out,tempfile.TemporaryFile() as err:
        kwargs={'cwd':R,'stdout':out,'stderr':err,'env':env}
        if os.name=='posix':kwargs['start_new_session']=True
        elif os.name=='nt':kwargs['creationflags']=subprocess.CREATE_NEW_PROCESS_GROUP
        proc=subprocess.Popen(cmd,**kwargs);timed_out=False
        try:proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out=True
            if os.name=='posix':
                try:os.killpg(proc.pid,signal.SIGKILL)
                except ProcessLookupError:pass
            elif os.name=='nt':
                subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=10)
            else:proc.kill()
            proc.wait(timeout=10)
        out.seek(0);err.seek(0)
        return proc.returncode,out.read().decode('utf-8','replace'),err.read().decode('utf-8','replace'),timed_out

def main():
    p=argparse.ArgumentParser();p.add_argument('--browser',action='store_true');p.add_argument('--chromium');p.add_argument('--write-report',action='store_true');p.add_argument('--screens',action='store_true');p.add_argument('--timeout',type=int,default=120);a=p.parse_args()
    if a.timeout<=0:p.error('--timeout must be positive')
    reports=[];env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'};preflight_ok=True
    def output(running=False):
        return {'version':'3.16','scope':'DOCUMENTARY_AND_FOCUSED_VISUAL_RELEASE','previousSpecializedSuite':'NOT_RERUN_ON_V3_16','coverageNote':'The current suite rechecks generic contracts/links and the four-view atelier/reader. Version-specific V3.14 file/mobile/gallery suites remain historical and are not represented as passing V3.16.','executedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'requestedBrowserChecks':a.browser,'running':running,'passed':not running and all(x.get('passed') is True for x in reports if x['status']!='NOT_RUN'),'allChecksExecuted':not running and len(reports)==len(CORE+BROWSER) and all(x['status']!='NOT_RUN' for x in reports),'reports':reports,'productTestsExecuted':False,'nativeBuildExecuted':False,'limits':['A passing documentary suite does not establish product correctness, safety or legal compliance.','NOT_RUN is not passed. Timeout, missing browser and unavailable checks fail explicitly.','Reports and manifests must be regenerated after content changes.']}
    def save(running):
        if a.write_report:(R/'annexes/verification-livraison-v3-16.json').write_text(json.dumps(output(running),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    save(True)
    for script in CORE+BROWSER:
        if not preflight_ok:reports.append({'script':script,'status':'BLOCKED_BY_ENVIRONMENT','passed':False});continue
        if script in BROWSER and not a.browser:reports.append({'script':script,'status':'NOT_RUN','passed':None,'reason':'Use --browser after installing browser dependencies.'});continue
        cmd=[sys.executable,str(R/'annexes'/script)]
        if a.write_report:cmd.append('--write-report')
        if script in BROWSER and a.chromium:cmd+=['--chromium',a.chromium]
        # Exports are generated separately with exporter-atelier.py; --screens is retained for CLI compatibility.
        start=time.monotonic()
        try:
            code,stdout,stderr,timed_out=execute(cmd,a.timeout,env)
            try:payload=json.loads(stdout)
            except json.JSONDecodeError:payload={'passed':False,'errors':[{'type':'NON_JSON_OUTPUT','stdoutTail':stdout[-3000:]}]}
            ok=code==0 and payload.get('passed') is True and not timed_out
            record={'script':script,'status':'PASSED' if ok else 'FAILED','exitCode':code,'passed':ok,'timedOut':timed_out,'elapsedSeconds':round(time.monotonic()-start,3),'scope':payload.get('scope',payload.get('status')),'errorCount':payload.get('errorCount',len(payload.get('errors',[]))),'errors':payload.get('errors',[]),'stderr':stderr[-7000:]}
        except (OSError,subprocess.SubprocessError) as exc:record={'script':script,'status':'FAILED','passed':False,'error':str(exc)}
        reports.append(record);save(True);print(f"{script}: {record['status']}",file=sys.stderr,flush=True)
        if script==CORE[0] and not record['passed']:preflight_ok=False
    save(False);result=output();print(json.dumps(result,ensure_ascii=False,indent=2));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
