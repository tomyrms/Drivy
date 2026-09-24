#!/usr/bin/env python3
"""Generate the documentary UI prototype, not a Drivy app or client."""
from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
t=json.loads((R/'annexes/tokens-proposition.json').read_text(encoding="utf-8"))
replay=json.loads((R/'DESIGN/replay-fictif.json').read_text(encoding="utf-8"))
scenes=json.loads((R/'DESIGN/scenes.json').read_text(encoding="utf-8"))['scenes']
css=':root{color-scheme:light;'+''.join(f'--{k}:{v};' for k,v in t['colors']['light'].items())+'}\n:root[data-theme="dark"]{color-scheme:dark;'+''.join(f'--{k}:{v};' for k,v in t['colors']['dark'].items())+'}'
s=(R/'DESIGN/assets/maquettes.template.html').read_text(encoding="utf-8").replace('__TOKENS__',css).replace('__JSON_TOKENS__',json.dumps(t,ensure_ascii=False)).replace('__JSON_SCENES__',json.dumps(scenes,ensure_ascii=False))
s=s.replace('__JSON_REPLAY__',json.dumps(replay,ensure_ascii=False)).replace('__JSON_SIGNAL__',json.dumps(json.loads((R/'DESIGN/signalement-fictif.json').read_text(encoding='utf-8')),ensure_ascii=False))
(R/'DESIGN/MAQUETTES.html').write_text(s,encoding='utf-8')
print(json.dumps({'file':'DESIGN/MAQUETTES.html','scenes':len(scenes),'bytes':len(s.encode())}))
