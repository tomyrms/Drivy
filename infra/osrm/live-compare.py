"""Read-only live replay. No captured rows or raw remote errors leave the homelab.

Run from the repository after API/iOS algorithms are ready:
  python infra/osrm/live-compare.py --run CAPTURE_1 CAPTURE_2
Without --run, only compile/validate calculation code locally, without SSH or DB access.
The two capture UUIDs are arguments only. Never commit command transcripts containing them.
The default SSH host/CTs are the existing homelab, not a deployment destination.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def query(capture_ids: list[str]) -> str:
    if len(capture_ids) != 2 or len(set(capture_ids)) != 2 or any(not UUID.fullmatch(i) for i in capture_ids):
        raise ValueError("Exactly two distinct canonical capture UUIDs required")
    values = ",".join(f"('{value}'::uuid,{i})" for i, value in enumerate(capture_ids))
    return f"""BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH requested(id, ordinal) AS (VALUES {values})
SELECT json_build_object('captures',coalesce(json_agg(json_build_object(
'id',c.id,'school_id',c.school_id,
'chunks',(SELECT json_agg(json_build_object('segment_id',k.segment_id,'segment_index',k.segment_index,
'chunk_index',k.chunk_index,'content_hash',k.content_hash,'enc',encode(k.encrypted_points,'hex'))
ORDER BY k.segment_index,k.first_sequence)
FROM drivy.capture_chunk k WHERE k.capture_id=c.id AND k.encrypted_points IS NOT NULL))
ORDER BY requested.ordinal),'[]'::json))
FROM requested JOIN drivy.capture_session c ON c.id=requested.id;
ROLLBACK;"""


def numeric_only(value, key=None):
    # Second barrier on the homelab host, before stdout can cross SSH.
    # The JS barrier also applies a fixed allow-list to every field name.
    if key == "sourceHashes":
        if not isinstance(value, dict) or set(value) != {"api", "ios", "replay"}:
            raise ValueError("unsafe digest")
        if any(not isinstance(v, str) or not re.fullmatch(r"[0-9a-f]{64}", v) for v in value.values()):
            raise ValueError("unsafe digest")
    elif value is None or isinstance(value, bool):
        return
    elif isinstance(value, (int, float)):
        import math
        if not math.isfinite(value):
            raise ValueError("unsafe number")
    elif isinstance(value, list):
        for child in value:
            numeric_only(child)
    elif isinstance(value, dict):
        for field, child in value.items():
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", field) or field.lower() in {"latitude", "longitude", "id", "name", "coordinates", "schoolid", "captureid", "segmentid", "sequence"}:
                raise ValueError("unsafe field")
            numeric_only(child, field)
    else:
        raise ValueError("unsafe leaf")


def bundle_api():
    # esbuild is already installed by the repository lockfile. No package downloads.
    program = """const esbuild=require('esbuild');
const r=esbuild.buildSync({entryPoints:['apps/api/src/live-matching.ts'],bundle:true,write:false,
platform:'node',target:'node24',format:'esm',logLevel:'silent'});
process.stdout.write(r.outputFiles[0].text);"""
    result = subprocess.run(["node", "-e", program], cwd=ROOT, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError("API calculation bundle not ready")
    return result.stdout.decode("utf8")


def remote_program(sql, envelope):
    import inspect
    validation = inspect.getsource(numeric_only)
    bootstrap = """const fs=require('node:fs');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
for(const k of ['log','info','warn','error','debug','trace']) console[k]=()=>{};
const mod={exports:{}};
try { new Function('require','module','exports',input.code)(require,mod,mod.exports);
Promise.resolve(mod.exports.run(input)).then(r=>process.stdout.write(JSON.stringify(r))).catch(()=>{process.exitCode=1});
} catch {process.exitCode=1;}"""
    return f"""import json,re,subprocess,sys
{validation}
try:
    envelope={envelope!r}
    db=subprocess.run(['pct','exec','113','--','runuser','-u','postgres','--','psql','-X','-q','-At','-v','ON_ERROR_STOP=1','-d','drivy_refonte'],input={sql!r}.encode(),capture_output=True,timeout=45)
    if db.returncode: raise RuntimeError()
    rows=b''.join(line for line in db.stdout.splitlines(True) if line.strip() and line.strip() not in (b'BEGIN',b'ROLLBACK',b'SET'))
    envelope['data']=json.loads(rows)
    calc=subprocess.run(['pct','exec','114','--','node','-e',{bootstrap!r}],input=json.dumps(envelope).encode(),capture_output=True,timeout=1200)
    if calc.returncode: raise RuntimeError()
    report=json.loads(calc.stdout)
    numeric_only(report)
    sys.stdout.write(json.dumps(report,allow_nan=False))
except Exception:
    sys.stderr.write('Read-only replay failed; remote diagnostic data suppressed.\\n')
    sys.exit(1)
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_ids", nargs="*")
    parser.add_argument("--run", action="store_true", help="Algorithms reviewed and ready: allow read-only replay")
    parser.add_argument("--diagnostic", action="store_true", help="Also call OSRM without admission gates, separately from the product replay")
    parser.add_argument("--network-ms", type=float, default=0, help="Assumed extra client/network RTT, not measured")
    args = parser.parse_args(argv)
    try:
        if not 0 <= args.network_ms <= 10000:
            raise ValueError("Invalid hypothetical network latency")
        sql = query(args.capture_ids) if args.run else None
        code = (HERE / "live-compare.js").read_text(encoding="utf8")
        api = bundle_api()
        ios = b"\n".join((ROOT / path).read_bytes() for path in [
            "apps/ios/Drivy/SchoolCaptureCore/SchoolMapMotion.swift",
            "apps/ios/Drivy/SchoolCaptureCore/SchoolLiveMatchCoordinator.swift",
            "apps/ios/Drivy/SchoolCaptureAPI/SchoolLiveMatchModels.swift",
            "apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureLiveMap.swift"])
        envelope = {"code": code, "apiBundle": api, "networkMs": args.network_ms, "diagnosticOnly": args.diagnostic,
            "sourceHashes": {"api": hashlib.sha256(api.encode()).hexdigest(), "ios": hashlib.sha256(ios).hexdigest(), "replay": hashlib.sha256(code.encode()).hexdigest()}}
        if not args.run:
            print("Calculation bundle prepared locally. No SSH connection, no database access.")
            return 0
        remote = remote_program(sql, envelope)
        result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=yes", "root@192.168.1.106", "python3 -"], input=remote.encode(), capture_output=True, timeout=1260)
        if result.returncode:
            raise RuntimeError("Remote replay failed")
        report = json.loads(result.stdout)
        numeric_only(report)
        print(json.dumps(report, indent=2, allow_nan=False))
        return 0
    except Exception:
        # Never pass through a DB, SSH, Node, HTTP or compilation exception.
        print("Replay unavailable: preparation or read-only calculation failed; details suppressed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
