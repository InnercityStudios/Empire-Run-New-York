#!/usr/bin/env python3
"""Capture the actual running Godot Mobile game. Requires graphical access.
Never fabricates images. Capture runs are save-isolated by GameSession.
"""
import argparse
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
VIEWS=[
    ('01_new_york_close', '-80,-30,110,-32'),
    ('02_new_york_medium', '400,-1700,1050,-32'),
    ('03_city_suburbs', '350,5650,2400,-15'),
    ('04_open_countryside', '-5200,-6800,1450,-20'),
    ('05_natural_banks', '-2650,5720,800,-12'),
    ('06_mansion_fields', '12500,-11500,1100,-32'),
    ('07_world_strategic', '4800,-2500,45000,0'),
]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot')
    ap.add_argument('--out',type=Path,default=ROOT/'docs/geography/phase1_captures')
    args=ap.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    manifest=[]
    for name,view in VIEWS:
        output=args.out/(name+'.png')
        log=args.out/(name+'.log')
        cmd=[args.godot,'--path',str(ROOT),'--log-file',str(log),'--windowed','--resolution','1600x900','--',
             '--new-game','--no-save','--capture='+str(output),'--capture-delay=14','--view='+view,'--stats']
        if name.startswith('07_'):cmd.append('--whole-world')
        result=subprocess.run(cmd,cwd=ROOT,timeout=120)
        if result.returncode or not output.exists():
            raise SystemExit('Godot capture failed: '+name+'; inspect '+str(log))
        manifest.append({'image':output.name,'view':view,'source':'Godot Mobile viewport'})
    (args.out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Captured',len(manifest),'actual Godot views in',args.out)
if __name__=='__main__':main()
