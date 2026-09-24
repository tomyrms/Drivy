#!/usr/bin/env python3
"""Verify or explicitly regenerate a SHA-256 delivery manifest, excluding the manifest itself."""
from pathlib import Path
import argparse,hashlib,json
R=Path(__file__).resolve().parents[1];M=R/'SHA256SUMS.txt'
def files():return sorted(p for p in R.rglob('*') if p.is_file() and p!=M and '__pycache__' not in p.parts and p.suffix!='.pyc')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--regenerate',action='store_true');a=ap.parse_args()
 actual={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files()}
 if a.regenerate:M.write_text(''.join(f'{sha}  {path}\n' for path,sha in actual.items()),encoding='utf-8')
 expected={}
 try:
  for line in M.read_text(encoding='utf-8').splitlines():
   sha,path=line.split('  ',1)
   if path in expected:raise ValueError('Duplicate manifest path: '+path)
   expected[path]=sha
 except (OSError,ValueError) as exc:print(json.dumps({'passed':False,'error':str(exc)}));return 1
 missing=sorted(set(expected)-set(actual));extra=sorted(set(actual)-set(expected));changed=sorted(x for x in expected.keys()&actual.keys() if expected[x]!=actual[x]);ok=not(missing or extra or changed)
 print(json.dumps({'scope':'FILE_INTEGRITY_ONLY','passed':ok,'listedFiles':len(expected),'missing':missing,'unlisted':extra,'changed':changed,'manifestRegenerated':a.regenerate},ensure_ascii=False,indent=2));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
