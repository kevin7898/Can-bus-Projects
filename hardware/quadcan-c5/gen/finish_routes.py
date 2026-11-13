"""Resolve signal/ground escapes on a local 0.025 mm grid, without moving routes.

The coarse router's reserved escape lanes are not copper. At this final stage,
use actual pad/track geometry, keep the electrical clearance, and verify with
KiCad DRC. Never narrow regulator/MCU/transceiver power connections.
Usage: python finish_routes.py geom.json routes.json
"""
import copy
import hashlib
import json
import sys
import numpy as np
from scipy.ndimage import distance_transform_edt
import route


def main(geom_path, route_path):
    g = json.load(open(geom_path))
    data = json.load(open(route_path))
    remaining = list(data['failed'])
    route.GRID = 0.025
    route.CLR = 0.18
    for net, ref, pin in list(remaining):
        low_current = net == '+3V3' and (ref.startswith('R') or ref in ('U17','U18','U19','U20'))
        if net in route.WIDE and net != 'GND' and not low_current:
            print('Keep power width:',net,ref,pin,flush=True)
            continue
        pad = next(p for p in g['pads'] if p['net']==net and p['ref']==ref and p['pad']==pin)
        local = copy.deepcopy(g)
        bb=g['bbox'];x,y=pad['x'],pad['y']
        goals=[pt for t in data['tracks'] if t['net']==net for pt in t['pts']]
        goals += [(q['x'],q['y']) for q in g['pads'] if q['net']==net and [net,q['ref'],q['pad']] not in remaining]
        if not goals: continue
        gx,gy=min(goals,key=lambda q:(q[0]-x)**2+(q[1]-y)**2)
        local['bbox']=[max(bb[0],min(x,gx)-4),max(bb[1],min(y,gy)-4),min(bb[2],max(x,gx)+4),min(bb[3],max(y,gy)+4)]
        pbn={}
        for p in local['pads']:
            if p['net']:pbn.setdefault(p['net'],[]).append(p)
        r=route.Router(local,pbn,list(pbn))
        for lane in r.G.corridor:lane.fill(0)  # all other routes already exist
        for t in data['tracks']:
            rec=r.geom.setdefault(t['net'],{'tracks':[],'vias':[],'raster':[]})
            for a,b in zip(t['pts'],t['pts'][1:]):
                r._draw(t['net'],route.LAYERS.index(t['layer']),a,b,t['w'])
        for v in data['vias']:
            r.add_via(v['net'],v['x'],v['y'])
        tree=np.zeros((len(route.LAYERS),r.G.H,r.G.W),np.uint8)
        for li,sl,mask in r.geom.get(net,{}).get('raster',[]):tree[li][sl][mask]=1
        for q in pbn[net]:
            if [net,q['ref'],q['pad']] not in remaining:
                for li,cy,cx in r.sources(q):tree[li,cy,cx]=1
        if not tree.any():continue
        heur=distance_transform_edt(tree.max(axis=0)==0).astype(np.float32)
        path=None
        for width in ((0.25,0.2) if net=='GND' else (0.2,0.15)):
            free,vfree=r.G.free_maps(r.G.netid[net],width)
            path=route.astar(r.G,free,vfree,r.sources(pad),tree,heur)
            if path is not None:break
        if path is None:
            from scipy.ndimage import label
            labels,_=label(free[0],np.ones((3,3)))
            ids={labels[cy,cx] for li,cy,cx in r.sources(pad) if li==0}
            region=np.isin(labels,list(ids)) & (labels!=0)
            print('Still open:',net,ref,pin,'source region',int(region.sum()),'via sites',int((region & vfree.astype(bool)).sum()),'search',route.STATS,flush=True)
            continue
        # Only export new connections; the original routes stay byte-for-byte intact.
        r.geom[net]={'tracks':[],'vias':[],'raster':[]}
        r.commit(net,width,path,pad)
        data['tracks'].extend(r.geom[net]['tracks'])
        data['vias'].extend(r.geom[net]['vias'])
        remaining.remove([net,ref,pin])
        print('Fine-grid escape:',net,ref,pin,'width',width,flush=True)
    data['failed']=remaining
    data['geometry_sha256']=hashlib.sha256(open(geom_path,'rb').read()).hexdigest()
    json.dump(data,open(route_path,'w'))
    print('Remaining connections:',len(remaining),flush=True)

if __name__=='__main__':main(*sys.argv[1:])
