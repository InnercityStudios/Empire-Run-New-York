#!/usr/bin/env python3
"""Bake a 2048px shoreline proximity mask from authored vector geography.
Pillow only; this is a material mask, never used to define terrain geometry.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parents[2]

def main():
    base=json.loads((ROOT/'data/world/nyc_1977.json').read_text())
    extra=json.loads((ROOT/'data/world/landscape.json').read_text())
    x0,z0,x1,z1=extra['extent'];width=2048;height=round(width*(z1-z0)/(x1-x0))
    px=lambda p:((p[0]-x0)/(x1-x0)*width,(p[1]-z0)/(z1-z0)*height)
    im=Image.new('L',(width,height));d=ImageDraw.Draw(im)
    for c in base['landmasses']+extra['landmasses']:d.polygon([px(p) for p in c['polygon']],fill=255)
    for r in base.get('estate_regions',[])+extra['estate_regions']:
        for lake in r.get('lakes',[]):d.polygon([px(p) for p in lake['polygon']],fill=0)
        for stream in r.get('streams',[]):
            d.line([px(p) for p in stream['path']],fill=0,width=max(1,round(stream['width']/(x1-x0)*width)))
    im=im.filter(ImageFilter.GaussianBlur(2.4))
    im.save(ROOT/'assets/textures/world_water_mask.png')
    print('Shoreline mask',im.size)
if __name__=='__main__':main()
