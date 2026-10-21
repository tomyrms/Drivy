"""Read-only replay-route diagnostic (#89). Same barriers as live-compare.py: READ ONLY transaction on CT113,
decryption only in CT114 memory, real track-matching.ts bundled, only numeric aggregates leave the homelab.

  python -B infra/osrm/replay-diagnose.py CAPTURE_1 CAPTURE_2

Never commit transcripts containing the capture UUIDs.
"""
from __future__ import annotations
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
lc = __import__("live-compare")

ALLOWED = {"minimumConfidence", "captures", "points", "segments", "pathMetersRaw", "accuracyM", "intervalS", "pairSpeedMs",
    "storedSpeedSamples", "storedSpeedMs", "accuracyOver30", "selectedPoints", "runs", "runLengths", "matcherPoints",
    "matcherPointsPerRun", "runsBelow2MatcherPoints", "batches", "codes", "Ok", "NoMatch", "NoSegment", "NoTrips", "InvalidQuery",
    "TooBig", "batchConfidence", "placedShare", "spans", "spanConfidence", "coveredPoints", "coverageShare", "count", "p50", "p90", "max"}


def check(value):
    if value is None or isinstance(value, bool) or (isinstance(value, (int, float)) and value == value and abs(value) != float("inf")):
        return
    if isinstance(value, list):
        for child in value: check(child)
        return
    if isinstance(value, dict):
        for key, child in value.items():
            if key not in ALLOWED: raise ValueError("unsafe field")
            check(child)
        return
    raise ValueError("unsafe leaf")


def bundle():
    program = """const esbuild=require('esbuild');
const r=esbuild.buildSync({entryPoints:['apps/api/src/track-matching.ts'],bundle:true,write:false,platform:'node',target:'node22',format:'cjs',logLevel:'silent'});
process.stdout.write(r.outputFiles[0].text);"""
    result = subprocess.run(["node", "-e", program], cwd=ROOT, capture_output=True, timeout=60)
    if result.returncode: raise RuntimeError("bundle")
    return result.stdout.decode("utf8")


def main(argv):
    try:
        sql = lc.query(argv)
        envelope = {"code": (HERE / "replay-diagnose.js").read_text(encoding="utf8"), "apiBundle": bundle()}
        remote = lc.remote_program(sql, envelope)
        # Barrière distante équivalente à celle de live-compare, avec la liste de champs de ce diagnostic.
        import inspect
        remote = remote.replace("numeric_only(report)", "check(report)").replace(
            "try:\n    envelope=", f"ALLOWED={ALLOWED!r}\n{inspect.getsource(check)}\ntry:\n    envelope=", 1)
        result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "root@192.168.1.106", "python3 -"],
            input=remote.encode(), capture_output=True, timeout=1260)
        if result.returncode: raise RuntimeError("remote")
        report = json.loads(result.stdout)
        check(report)
        print(json.dumps(report, indent=2, allow_nan=False))
        return 0
    except Exception:
        print("Replay diagnostic unavailable; details suppressed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
