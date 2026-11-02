#!/usr/bin/env python3
"""Additive countryside blueprint, never rewrites the owner's city/slice data.
Run with Python 3 (stdlib only). Plot/terrain validation runs in Godot against
actual rendered height samples and the final connected road graph.
"""
import json
import math
import random
from pathlib import Path
from slice_data import chaikin, blob, pip, path_dist, poly_dist

ROOT = Path(__file__).resolve().parents[2]
EXTENT = [-8500, -14500, 18500, 9500]
# Broad fields in three strategic distance bands, outside the authored city.
REGIONS = [
    ('bergen', 'Bergen Meadows', 'outer', [(-8000,-10800),(-3800,-11200),(-2300,-9400),(-3300,-1000),(-8000,-1000)]),
    ('palisades', 'Palisades Pastures', 'suburban', [(-2200,-14100),(2200,-14100),(2350,-9500),(-2200,-9500)]),
    ('westchester', 'Westchester Fields', 'suburban', [(3800,-14200),(17700,-14200),(17700,-9200),(3800,-9200)]),
    ('gold_coast', 'Gold Coast Meadows', 'suburban', [(10100,-4900),(17700,-5400),(17700,-1600),(10100,-1600)]),
    ('south_shore', 'South Shore Fields', 'outer', [(10100,-1200),(17700,-1200),(17700,5200),(10100,5200)]),
    ('staten_meadows', 'Richmond Pastures', 'prime', [(-7200,5900),(-4800,5700),(-4700,7800),(-1600,8100),(-2900,9000),(-6800,9000)]),
]

def rounded(points):
    return [[round(x,2),round(z,2)] for x,z in points]

def main():
    rng=random.Random(19771101)
    overlay={'extent':EXTENT,'settings':{'version':1,'plot_size':140,'spacing':230,'exclusion_radius':115,
              'target_capacity':2017}, 'landmasses':[], 'networks':[], 'estate_regions':[], 'bridges':[{'id':'george_washington_bridge','name':'George Washington Bridge',
              'kind':'suspension','width':26,'speed':1600,'path':[[2728,-6900],[1300,-7300]]}] }
    for ident, join, poly in [
        ('staten_fields','staten_island',[(-7600,5600),(-4200,5200),(-4000,7600),(-1000,8000),(-3000,9500),(-7000,9500)]),
        ('new_jersey_fields','new_jersey',[(-8500,-14500),(2400,-14500),(2400,-9400),(-800,-5000),(-1700,-1200),(-8500,1200)]),
        ('north_fields','bronx',[(3400,-14500),(18500,-14500),(18500,-8500),(7600,-8200),(3500,-8500)]),
        ('east_fields','long_island',[(7400,-4500),(10000,-5400),(12800,-5750),(15500,-6100),(18500,-5800),(18500,6500),
                                     (14500,6100),(11200,5700),(7400,5300)])]:
        overlay['landmasses'].append({'id':ident,'join':join,'kind':'scenery','polygon':rounded(chaikin(poly,2,closed=True))})
    # These connect exactly to existing arterial endpoints. Sparse local roads
    # intersect these collectors; no second independent navigation skeleton.
    collectors=[
        ('Palisades Parkway',[(1300,-7300),(200,-9000),(0,-12000),(400,-14200)]),
        ('Bergen Road',[(0,-10500),(-2500,-10500),(-5200,-9500),(-7600,-8500)]),
        ('Hudson Meadows Road',[(-5200,-9500),(-5300,-6500),(-6000,-3800)]),
        ('Saw Mill Parkway',[(3850,-8850),(4500,-10200),(6500,-12000),(17500,-12000)]),
        ('Westchester Lane',[(10500,-12000),(11000,-10500),(11500,-9300)]),
        ('Northern State Parkway',[(7600,-2800),(10500,-3000),(14000,-3100),(18000,-3000)]),
        ('Southern State Parkway',[(7500,1800),(10200,2000),(13700,2200),(18000,2400)]),
        ('Nassau Road',[(10500,-3000),(10500,2000),(10800,5000)]),
        ('Richmond Meadows Road',[(-4450,5600),(-5700,6100),(-6000,8000),(-2600,8400)]),
    ]
    overlay['networks'].append({'id':'outer_collectors','blocks':False,'roads':[
        {'name':name,'width':14,'speed':1300,'path':rounded(path)} for name,path in collectors]})
    for ri,(ident,name,tier,poly) in enumerate(REGIONS):
        xs,zs=zip(*poly); xmin,xmax=min(xs),max(xs); zmin,zmax=min(zs),max(zs)
        lakes=[]
        # One modest lake per large estate region. Most land remains buildable.
        cx,cz=xmin+(xmax-xmin)*.4,zmin+(zmax-zmin)*.48
        lakes=[{'id':ident+'_pond','name':name+' Lake','polygon':rounded(blob(cx,cz,170,110,ri+90))}]
        roads=[]
        # Gentle curving parallel lanes with a shared collector. 620 m pitch
        # leaves two broad fields per lane, rather than a suburban street grid.
        row=0
        z=zmin+230
        while z<zmax-140:
            run=[]
            for i in range(int((xmax-xmin)/100)+1):
                x=xmin+i*100
                q=(x,z+48*math.sin((x-xmin)/800+ri+row*.65))
                good=pip(*q,poly) and poly_dist(*q,poly)>45
                if good:
                    run.append(q)
                if (not good or i==int((xmax-xmin)/100)) and run:
                    if len(run)>2: roads.append({'name':name+' Lane %d'%row,'width':7,'speed':900,'path':rounded(run)})
                    run=[]
            z+=620;row+=1
        spine_x=xmin+(xmax-xmin)*.70
        spine=[]
        for i in range(int((zmax-zmin)/80)+1):
            z=zmin+80*i
            p=(spine_x+28*math.sin(z/900),z)
            if pip(*p,poly) and poly_dist(*p,poly)>30:spine.append(p)
        roads.append({'name':name+' Road','width':9,'speed':1100,'path':rounded(spine)})
        # Tie every lane to the collector via a regional spine and an explicit
        # approach; these are data roads, consumed by the same planar network.
        target=collectors[[1,0,3,5,6,8][ri]][1][1]
        if spine: roads.append({'name':name+' Approach','width':9,'speed':1000,'path':rounded([spine[len(spine)//2],target])})
        # Lakes are placed clear of roads (move within the same field if needed).
        for lake in lakes:
            if any(path_dist(cx,cz,r['path'])[0]<220 for r in roads):
                for off in [260,-260,380,-380]:
                    if pip(cx,cz+off,poly) and all(path_dist(cx,cz+off,r['path'])[0]>220 for r in roads):
                        lake['polygon']=rounded(blob(cx,cz+off,150,95,ri+90));break
                else: lakes=[];break
        region={'id':ident,'name':name,'tier':tier,'polygon':poly,'plot_size':140,'plot_spacing':230,
                'lakes':lakes,'streams':[],'woods':[],'plots':[]}
        overlay['networks'].append({'id':'fields_'+ident,'blocks':False,'roads':roads})
        overlay['estate_regions'].append(region)
    out=ROOT/'data/world/landscape.json'
    out.write_text(json.dumps(overlay,indent=1)+'\n')
    print('Wrote',out,'regions',len(REGIONS),'roads',sum(len(n['roads']) for n in overlay['networks']))

if __name__=='__main__':main()
