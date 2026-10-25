"""Independent synthetic stress: full pool, late high-score insertion and truncation."""
import numpy as np
from review_pest import ROOT
from precision_v25_core import detect
from pl_detector_v23_model import PROFILE
a=np.empty((128,128,3),np.uint8);a[:]=(40,120,40)
for row in range(5):
 for col in range(8):
  y,x=8+row*22,8+col*14
  size=11 if (row,col)==(4,7) else 9
  a[y:y+size,x:x+size]=(80,40,20)
_,d=detect(a,profile=PROFILE|dict(strict_candidate=True,extra_erode=5,max_boxes=32))
assert len(d['src_boxes'])==32 and d['src_boxes'][0]['area']==49
out=ROOT/'build/pl_detector_v25/vectors'
(out/'pool_rgb.mem').write_text(''.join(f'{int(r)|(int(g)<<8)|(int(b)<<16):06x}\n' for r,g,b in a.reshape(-1,3)))
records=[]
for p in d['src_boxes']:
 x0,y0,x1,y1=p['bbox'];records.append(x0|(y0<<9)|(x1<<18)|(y1<<27)|(p['area']<<36)|(p['score']<<53))
(out/'pool_expected.mem').write_text(''.join(f'{v:024x}\n' for v in records))
print('Prepared 40 synthetic components -> 32 retained; late high-score component sorted first')
