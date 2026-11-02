#!/usr/bin/env python3
"""Read-only diagnostics of the current province and renderer source inputs."""
import json
import math
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]

def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def intersections(p):
    out=[];n=len(p)
    for i in range(n):
        a,b=p[i],p[(i+1)%n]
        for j in range(i+2,n):
            if (j+1)%n==i:continue
            c,d=p[j],p[(j+1)%n]
            if cross(a,b,c)*cross(a,b,d)<-1e-7 and cross(c,d,a)*cross(c,d,b)<-1e-7:out.append([i,j])
    return out

def rectangle(p):
    if len(p)!=4:return False
    for i in range(4):
        a,b,c=p[i],p[(i+1)%4],p[(i+2)%4]
        u=(b[0]-a[0],b[1]-a[1]);v=(c[0]-b[0],c[1]-b[1])
        if abs(u[0]*v[0]+u[1]*v[1])/max(math.hypot(*u)*math.hypot(*v),1e-9)>.002:return False
    return True

def main():
    base=json.loads((ROOT/'data/world/nyc_1977.json').read_text())
    overlay=json.loads((ROOT/'data/world/landscape.json').read_text())
    polygons=[]
    for label,data in [('city',base),('outer',overlay)]:
        for c in data['landmasses']:
            polygons.append({'source':label,'id':c['id'],'vertices':len(c['polygon']),'proper_self_intersections':intersections(c['polygon'])})
    rect_lakes=[]
    for park in base['parks']:
        for i,lake in enumerate(park.get('lakes',[])):
            if rectangle(lake):rect_lakes.append({'park':park['id'],'lake_index':i,'coordinates':lake})
    result={'land_polygon_diagnostics':polygons,'rectangular_authored_park_lakes':rect_lakes,
            'terrain_sampling_m':[16,128],'detail_radius_formula':'clamp(260 - distance * .6, 0, 220), cutoff 60',
            'building_detail_disappears_camera_distance_m':333.333333,
            'natural_waterway_example_width_m':7,'coarse_sample_to_stream_width_ratio':128/7,
            'coast_height_jump_on_road_centre_m':1.87,
            'scope':'Read-only source diagnostics; screenshot attribution remains pending latest screenshot paths.'}
    (HERE/'results/current_renderer_audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Rectangular park lakes:',[(r['park'],r['lake_index']) for r in rect_lakes])
    print('Self-intersecting input land polygons:',[(r['id'],r['proper_self_intersections']) for r in polygons if r['proper_self_intersections']])
if __name__=='__main__':main()
