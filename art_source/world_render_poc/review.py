#!/usr/bin/env python3
"""Run native Godot geometry checks or six real Mobile-renderer captures.
Does not export a web approximation or fabricate a preview when GPU access fails.
"""
import argparse
import json
import subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--capture',action='store_true')
    args=parser.parse_args()
    results=HERE/'results';results.mkdir(exist_ok=True)
    name='capture' if args.capture else 'check'
    log=results/(name+'.log')
    cmd=[args.godot,'--path',str(HERE),'--log-file',str(results/(name+'_engine.log'))]
    if args.capture:cmd+=['--windowed','--resolution','1600x1000','--','--capture-all','--output='+str(results/'captures')]
    else:cmd+=['--headless','--','--check']
    run=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
    log.write_text(run.stdout)
    if run.returncode or any(message in run.stdout for message in ['SCRIPT ERROR:','SHADER ERROR:','Shader compilation failed']):
        failure={'status':'blocked' if args.capture else 'failed','exit_code':run.returncode,
                 'requested':'Native Godot Mobile viewport captures' if args.capture else 'geometry checks',
                 'screenshots_created':False,'log':str(log.relative_to(HERE))}
        (results/(name+'_status.json')).write_text(json.dumps(failure,indent=2)+'\n')
        raise SystemExit(f'{name}: {failure["status"]}; exit {run.returncode}; see {log}')
    report=results/'captures/capture_report.json' if args.capture else results/'geometry_check.json'
    if not report.exists():raise SystemExit('Godot produced no verification report')
    data=json.loads(report.read_text())
    if data.get('errors'):raise SystemExit(str(data['errors']))
    if args.capture:
        if not data.get('gpu_measurements_available') or len(data.get('captures',[]))!=6:
            raise SystemExit('Six graphical viewport captures were not produced')
        for shot in data['captures']:
            if not Path(shot['file']).exists():raise SystemExit('Missing '+shot['file'])
        print('Six actual Godot captures ready for visual review. Approval remains pending.')
    else:print('Geometry checks pass. Visual review and GPU measurements remain pending.')

if __name__=='__main__':main()
