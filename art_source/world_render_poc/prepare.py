#!/usr/bin/env python3
"""Author only the two approval samples and stage existing, attributed assets.
No province generator, screenshot blueprint, gameplay or save file is read as
geometry. Run with stdlib Python; all outputs stay inside this proof project.
"""
import hashlib
import json
import math
import shutil
import struct
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]

def curve(points, samples=16, closed=False):
    # Explicit cubic Bezier control points; immutable sampled coordinates are
    # written to source JSON. No image tracing or runtime random shorelines.
    result=[]
    for segment in points:
        for i in range(samples):
            t=i/samples;u=1-t
            result.append([round(u**3*segment[0][j]+3*u*u*t*segment[1][j]+3*u*t*t*segment[2][j]+t**3*segment[3][j],4) for j in (0,1)])
    if not closed:result.append(list(points[-1][-1]))
    return result

def place(ident, asset, frontage, outward, **kw):
    return dict(id=ident,asset=asset,frontage=frontage,outward=outward,**kw)

def main():
    reserved=json.loads((ROOT/'data/world/estate_reservations.json').read_text())
    selected=next(p for p in reserved['plots'] if p['id']=='estate:staten:-3430:6572:infill2')
    origin=[-4000,6300]
    plot={k:selected[k] for k in ['id','center','gate','road_point','size','exclusion_radius','elevation','yaw']}
    # Preserve the exact persistent coordinates; render-local coordinates are
    # obtained only by subtracting origin, never by rewriting this reservation.
    pond_controls=[[[870,475],[870,520],[825,550],[775,550]],[[775,550],[725,550],[668,530],[670,485]],
                   [[670,485],[670,440],[700,405],[750,410]],[[750,410],[800,395],[865,420],[870,475]]]
    country={
        'id':'richmond_pasture','origin':origin,'bounds':[0,0,960,704],
        'land':[[0,0],[960,0],[960,704],[0,704]],'shore_kind':'natural','water_level':-1.6,
        'waters':[{'id':'clove_pond_proof','controls':pond_controls,'polygon':curve(pond_controls,24,True)}],
        'terrain':{'datum':1.2,'hills':[[880,80,11,190],[55,660,7,170],[930,680,6,180]],
                   'fields':[[[335,200],[610,180],[665,270],[650,450],[580,505],[340,480],[300,350]]],
                   'field_height':.12,'bank_width':18},
        'nodes':{'north':[280,0],'junction':[195.4072265625,193.00244140625],'south':[85,704],'east':[960,180]},
        'roads':[{'id':'rockland_lane','width':7,'class':'country','from':'north','to':'junction','path':[[280,0],[240,95],[195.4072265625,193.00244140625]]},
                 {'id':'rockland_south','width':7,'class':'country','from':'junction','to':'south','path':[[195.4072265625,193.00244140625],[166,300],[128,445],[99,595],[85,704]]},
                 {'id':'pasture_lane','width':6,'class':'country','from':'junction','to':'east','path':[[195.4072265625,193.00244140625],[310,165],[470,132],[640,128],[810,148],[960,180]]}],
        'parks':[],'reservation':plot,
        'buildings':[place('farm_house','house_b',[382,139],[0,1]),place('lane_house','house_d',[310,124],[0,1])],
        'trees':[], 'rocks':[],
        'views':{'close':{'target':[705,0,420],'distance':370,'yaw':-35,'pitch':42},
                 'medium':{'target':[480,0,350],'distance':700,'yaw':-25,'pitch':58},
                 'strategic':{'target':[480,0,352],'size':580,'yaw':0,'pitch':90}}}
    # Deliberate stands on field margins. Explicit positions are published in
    # the geometry contract rather than generated differently by LOD tiers.
    for cx,cz,n in [(825,95,29),(76,580,22),(920,575,23),(618,605,14),(735,310,12)]:
        for i in range(n):
            a=i*2.3999632297;r=9+math.sqrt(i)*10.5
            x,z=cx+math.cos(a)*r,cz+math.sin(a)*r*.66
            if not 10<x<950 or not 10<z<694:continue
            if math.hypot(x-492,z-340)<145:continue
            country['trees'].append({'pos':[round(x,3),round(z,3)],'asset':['tree_oak','tree_birch','tree_maple'][i%3],
                                     'yaw':round((i*137.5)%360,2),'scale':round(.84+(i%7)*.06,2)})
    def distance_to_path(p, path):
        best=float('inf')
        for a,b in zip(path,path[1:]):
            dx,dz=b[0]-a[0],b[1]-a[1]
            t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz or 1)))
            best=min(best,math.hypot(p[0]-a[0]-dx*t,p[1]-a[1]-dz*t))
        return best
    country['trees']=[t for t in country['trees'] if all(distance_to_path(t['pos'],r['path'])>r['width']/2+7 for r in country['roads'])]
    for i,p in enumerate(country['waters'][0]['polygon'][::7]):
        country['rocks'].append({'pos':[p[0]+5,p[1]-3],'asset':'rock_a' if i%3==0 else 'reeds','yaw':i*43,'scale':.6+(i%3)*.16})
    coast=[[28,0],[29,40],[32,90],[36,135],[39,180],[43,225],[46,270],[46,320]]
    city={'id':'brooklyn_waterfront','origin':[1100,1850],'bounds':[0,0,320,320],
          'land':coast+[[320,320],[320,0]],'shore':coast,'shore_kind':'bulkhead','water_level':-1.6,
          'waters':[{'id':'east_river_proof','polygon':[[0,0]]+coast+[[0,320]]}],
          'terrain':{'datum':-.03,'hills':[],'fields':[],'field_height':-.03,'bank_width':0},
          'nodes':{'dock_n':[70,60],'front_n':[110,60],'rear_n':[260,60],
                   'dock_s':[82,220],'front_s':[110,220],'rear_s':[260,220],
                   'front_top':[110,0],'front_bottom':[110,320], 'rear_top':[260,0],'rear_bottom':[260,320],
                   'dock_top':[65,0],'dock_bottom':[85,320]},
          'roads':[],
          'parks':[[[87,85],[99,84],[101,105],[100,166],[95,190],[87,184]]],
          'buildings':[place('corner_store','lic_brooklyn_corner',[126,92],[-1,0]),
                       place('river_loft','loft_a',[126,132],[-1,0]),
                       place('dock_warehouse','warehouse_a',[126,184],[-1,0]),
                       place('rear_loft','warehouse_b',[244,111],[1,0]),
                       place('rear_tenement','tenement_g',[244,163],[1,0]),
                       place('north_row_a','rowhouse_a',[182,76],[0,-1]),
                       place('north_row_c','rowhouse_c',[205,76],[0,-1]),
                       place('south_tenement','tenement_c',[185,204],[0,1]),
                       place('south_row','rowhouse_c',[209,204],[0,1])],
          'trees':[{'pos':p,'asset':'tree_birch','yaw':i*83,'scale':.75+i*.04} for i,p in enumerate([[93,100],[94,132],[94,163],[66,250]])],
          'rocks':[],
          'views':{'close':{'target':[151,0,147],'distance':175,'yaw':-48,'pitch':43},
                   'medium':{'target':[158,0,155],'distance':250,'yaw':-40,'pitch':59},
                   'strategic':{'target':[160,0,160],'size':190,'yaw':0,'pitch':90}}}
    def road(name,a,b,width=12,path=None):
        city['roads'].append({'id':name,'from':a,'to':b,'width':width,'class':'city','path':path or [city['nodes'][a],city['nodes'][b]]})
    for a,b in [('front_top','front_n'),('front_n','front_s'),('front_s','front_bottom'),
                ('rear_top','rear_n'),('rear_n','rear_s'),('rear_s','rear_bottom'),
                ('dock_n','front_n'),('front_n','rear_n'),('dock_s','front_s'),('front_s','rear_s')]:road(a+'_'+b,a,b)
    road('dock_top','dock_top','dock_n',8)
    road('dock_middle','dock_n','dock_s',8,[[70,60],[76,140],[82,220]])
    road('dock_bottom','dock_s','dock_bottom',8)
    geo={'schema':'empire-visual-proof-v1','approved':False,'units':'metres','axes':'+X east, +Z south, +Y up',
         'quantization_m':.001,'revision':1,'regions':[country,city]}
    (HERE/'data/geography.json').write_text(json.dumps(geo,indent=2)+'\n')
    asset_ids={p['asset'] for r in geo['regions'] for key in ['buildings','trees','rocks'] for p in r[key]}
    asset_ids|={'street_lamp','fire_hydrant','trash_can'}
    defs=json.loads((ROOT/'data/materials.json').read_text())['materials']
    selected_defs={};manifest=[]
    for ident in sorted(asset_ids):
        folder='buildings' if (ROOT/'assets/models/buildings'/f'{ident}.glb').exists() else 'props'
        src=ROOT/'assets/models'/folder/f'{ident}.glb';dest=HERE/'assets/models'/f'{ident}.glb'
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest)
        with src.open('rb') as f:
            f.read(12);size,_=struct.unpack('<II',f.read(8));data=json.loads(f.read(size))
        for m in data.get('materials',[]):
            if m.get('name') in defs:selected_defs[m['name']]=defs[m['name']]
        manifest.append({'asset':str(src.relative_to(ROOT)),'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
    textures=set()
    for definition in selected_defs.values():
        for val in definition.values():
            if isinstance(val,str) and val.startswith('res://assets/textures/'):textures.add(val.removeprefix('res://'))
    for name in ['terrain_grass_albedo','terrain_dirt_albedo','terrain_sand_albedo','terrain_mud_albedo','terrain_rock_albedo','terrain_grass_normal','water_normal','sidewalk_albedo','stone_albedo']:
        textures.add(f'assets/textures/{name}.png')
    for name in ['albedo','normal','arm']:textures.add(f'assets/textures/pbr/asphalt_02_{name}.png')
    for rel in sorted(textures):
        dest=HERE/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/rel,dest)
    # Explicit import policy for this isolated project only. Root-project
    # assets and their .import files are never changed by staging.
    for rel in sorted(textures):
        palette='palette_' in rel
        normal='_normal.' in rel
        dest=HERE/rel
        imp=Path(str(dest)+'.import')
        if imp.exists():
            text=imp.read_text()
            for old,new in [('compress/mode=0','compress/mode=0' if palette else 'compress/mode=2'),
                            ('mipmaps/generate=false','mipmaps/generate=false' if palette else 'mipmaps/generate=true'),
                            ('compress/normal_map=0','compress/normal_map=1' if normal else 'compress/normal_map=0'),
                            ('process/size_limit=0','process/size_limit=0' if palette else 'process/size_limit=1024'),
                            ('detect_3d/compress_to=1','detect_3d/compress_to=0')]:
                text=text.replace(old,new)
        else:
            text='[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\nsource_file="res://'+rel+'"\n\n[params]\n'
            text+='compress/mode='+str(0 if palette else 2)+'\ncompress/normal_map='+str(1 if normal else 0)+'\n'
            text+='mipmaps/generate='+('false' if palette else 'true')+'\nprocess/size_limit='+str(0 if palette else 1024)+'\ndetect_3d/compress_to=0\n'
        imp.write_text(text)
    (HERE/'data/materials.json').write_text(json.dumps(selected_defs,indent=2)+'\n')
    (HERE/'data/asset_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    shutil.copyfile(ROOT/'docs/CREDITS.md',HERE/'ASSET_CREDITS.md')
    print('Prepared two regions;',len(asset_ids),'existing assets;',len(textures),'existing textures. No province files changed.')

if __name__=='__main__':main()
