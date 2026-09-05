#!/usr/bin/env python3
import json
from pathlib import Path
from datetime import datetime
p = Path.home()/'.config/cordial/flags.json'
p.parent.mkdir(parents=True, exist_ok=True)
try:
    data = json.loads(p.read_text()) if p.exists() else {}
except Exception:
    backup = p.with_suffix(f'.broken-{datetime.now():%Y%m%d-%H%M%S}.json')
    p.rename(backup); data = {}
if p.exists():
    backup = p.with_suffix(f'.bak-{datetime.now():%Y%m%d-%H%M%S}.json')
    backup.write_text(p.read_text())
data.update({
    'DFIntTaskSchedulerTargetFps': 5,
    'FIntRenderShadowIntensity': 0,
    'FFlagDisablePostFx': True,
    'FIntDebugForceQualityLevel': 1,
})
p.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')
p.chmod(0o600)
print(p)
