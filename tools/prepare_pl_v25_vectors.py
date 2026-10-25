"""Independent vectors: all 24 fusion cases and exact intermediate engine masks."""
import json
from pathlib import Path
from review_pest import ROOT,samples
from precision_v25_core import detect,smooth_rgb
from pl_detector_v23_model import PROFILE
from lesion_detector_v25 import REFINEMENT_PROFILES

out=ROOT/'build/pl_detector_v25/vectors';out.mkdir(parents=True,exist_ok=True)
gold=json.loads((ROOT/'build/algorithm_v25/candidate_verified.json').read_text(encoding='utf-8'))['predictions']
dataset=json.loads((ROOT/'annotation_tool/dataset.json').read_text())['images']
def record(b):
 x0,y0,x1,y1=b['bbox']
 return x0|(y0<<9)|(x1<<18)|(y1<<27)|(b['area']<<36)|(b['score']<<53)
def mem(name,values,width): (out/name).write_text(''.join(f'{int(v):0{width}x}\n' for v in values))
board=[]
for (idx,_,raw),im in zip(samples(),dataset):
 rgb=smooth_rgb(raw);profiles=[PROFILE]+[PROFILE|p for p in REFINEMENT_PROFILES]
 mem(f'rgb_{idx}.mem',[int(r)|(int(g)<<8)|(int(b)<<16) for r,g,b in rgb.reshape(-1,3)],6)
 for mode,profile in enumerate(profiles):
  _,d=detect(rgb,profile=profile)
  selected=d['src_boxes'];mem(f'pool_{idx}_{mode}.mem',[len(selected)]+[record(b) for b in selected]+[0]*(32-len(selected)),24)
  mem(f'contrast_{idx}_{mode}.mem',d['contrast'].flat,2)
  mem(f'mask_{idx}_{mode}.mem',(d['leaf'].astype('uint8')*2+d['mask'].astype('uint8')).flat,1)
  if mode==0:
   parents=[]
   for p in d['records']:
    x0,y0,x1,y1=p['src']
    if p['area']>=400 and (x1-x0+1)*(y1-y0+1)>=1500:
     parents.append(max(0,x0-12)|(max(0,y0-12)<<9)|(min(256,x1+13)<<18)|(min(256,y1+13)<<27))
   assert len(parents)<=32
   mem(f'parents_{idx}.mem',[len(parents)]+parents+[0]*(32-len(parents)),9)
 expected=gold[im['id']];mem(f'final_{idx}.mem',[len(expected)]+[record(b) for b in expected]+[0]*(32-len(expected)),24)
 display=[]
 for p in expected:
  x0,y0,x1,y1=p['display_bbox'];display.extend([x0|(y0<<16),(x1-1)|((y1-1)<<16)])
 mem(f'display_{idx}.mem',display+[0]*(64-len(display)),8)
 board.append(dict(sample=idx+1,boxes=[p['display_bbox'][:2]+[p['display_bbox'][2]-1,p['display_bbox'][3]-1,p['area']] for p in expected]))
 print('v25 vectors',idx+1,'final',len(expected),'parents',len(parents),flush=True)
(out.parent/'python_results.json').write_text(json.dumps(board,indent=2))
