#!/usr/bin/env python3
"""Sync aligned SVG sources into the native document; optionally render via Apple."""
from pathlib import Path
import argparse, shutil, subprocess
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--render', action='store_true')
args = parser.parse_args()
for name in ('Road', 'Circuit', 'Markings'):
    shutil.copyfile(root/'source'/f'{name}.svg', root/'DriveLine.icon/Assets'/f'{name}.svg')
if args.render:
    developer = Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
    tool = developer.parent/'Applications/Icon Composer.app/Contents/Executables/ictool'
    # This is Icon Composer's renderer, not Developer/usr/bin/ictool (compiler).
    for rendition, size, filename in [(r,256,r) for r in ('Default','Dark','TintedLight','TintedDark','ClearLight','ClearDark')] + [('Default',s,f'Default-{s}') for s in (32,48,60,120)]:
        subprocess.run([str(tool),str(root/'DriveLine.icon'),'--export-image','--output-file',str(root/'previews'/f'{filename}.png'),'--platform','iOS','--rendition',rendition,'--width',str(size),'--height',str(size),'--scale','1'],check=True)
