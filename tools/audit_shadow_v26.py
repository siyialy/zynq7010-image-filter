"""Audit baseline candidate colour/support; labels are evaluation-only."""
import json
import numpy as np
from review_pest import ROOT,samples
from precision_v25_core import detect,smooth_rgb,components
from pl_detector_v23_model import PROFILE

out=ROOT/'build/algorithm_v26';out.mkdir(exist_ok=True)
published=json.loads((ROOT/'build/algorithm_v25/candidate_verified.json').read_text(encoding='utf-8'))
rows=[]
for index,_,raw in samples():
 rgb=smooth_rgb(raw);_,d=detect(rgb,profile=PROFILE)
 p=rgb.astype(int);r,g,b=p.transpose(2,0,1)
 classic=((r-g>6)&(r-b>5)&((r-g)*100>(r-b)*45))|((r*100>=g*80)&(b*100>=g*90))
 pixel_sets={}
 for pix,_ in components(d['mask']):
  ys,xs=zip(*pix);pixel_sets[(min(xs),min(ys),max(xs),max(ys))]=(ys,xs)
 final=published['predictions'][f'sample_{index+1:02d}']
 fp=published['source']['images'][index]['false_proposal_ids']
 selected={tuple(z['bbox']) for z in d['src_boxes']}
 for rec in d['records']:
  x0,y0,x1,y1=rec['src'];bbox=[x0,y0,x1+1,y1+1]
  if tuple(bbox) not in selected:continue
  ys,xs=pixel_sets[tuple(rec['src'])]
  matches=[z for z in final if z['branch']=='baseline' and z['bbox']==bbox]
  row=dict(sample=index+1,bbox=bbox,area=rec['area'],score=rec['score'],classic=int(classic[list(ys),list(xs)].sum()),green=rec['green'],halo=rec['halo'],tissue=rec['tissue'],published=bool(matches),false_positive=any(z['id'] in fp for z in matches))
  rows.append(row)
  if row['classic']==0:print(row,flush=True)
(out/'baseline_shadow_audit.json').write_text(json.dumps(rows,indent=2))
for threshold in (100,110,120,140,160,180,200):
 removed=[r for r in rows if r['published'] and r['classic']==0 and sum(r['green'])<threshold]
 print('threshold',threshold,'removed',[(r['sample'],r['false_positive']) for r in removed],flush=True)
