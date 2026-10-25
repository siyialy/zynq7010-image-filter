"""Independent synthetic and real-image vectors for the frozen v2.3 rules."""
from pathlib import Path
import json
import numpy as np
from pl_detector_v23_model import detect,smooth_rgb
from review_pest import samples

def write_cases(dest,cases,radius):
    dest.mkdir(parents=True,exist_ok=True)
    for i,a in enumerate(cases):
        boxes,d=detect(a,radius=radius)
        (dest/f'rgb_{i}.mem').write_text('\n'.join(f'{int(b)<<16|int(g)<<8|int(r):06x}' for r,g,b in a.reshape(-1,3))+'\n')
        (dest/f'contrast_{i}.mem').write_text('\n'.join(f'{int(v)&31:02x}' for v in d['contrast'].flat)+'\n')
        packed=d['leaf'].astype(np.uint8)*2+d['mask'].astype(np.uint8)
        (dest/f'masks_{i}.mem').write_text('\n'.join(f'{int(v):x}' for v in packed.flat)+'\n')
        flat=[len(boxes)]+[v for b in boxes for v in b[:5]]
        (dest/f'expected_{i}.mem').write_text('\n'.join(f'{v:08x}' for v in flat+[0]*(81-len(flat)))+'\n')
        print(dest.name,i,'boxes',len(boxes),flush=True)

def frame(c):
    a=np.empty((32,32,3),np.uint8);a[:]=c;return a
small=[frame((40,120,40)),frame((100,100,100)),frame((90,55,30))]
a=frame((40,120,40));a[12:19,12:19]=(100,60,40);small.append(a)
a=frame((40,120,40));a[12:19,12:19]=(65,65,65);small.append(a)
a=frame((140,130,140));a[5:27,5:27]=(50,120,50);a[12:18,12:18]=(100,60,40);small.append(a)
a=frame((140,130,140));a[5:27,5:27]=(50,120,50);a[:5,:5]=(55,45,40);small.append(a)
a=frame((40,120,40));a[6:11,6:11]=(100,60,40);a[21:26,21:26]=(100,60,40);small.append(a)
write_cases(Path('build/pl_detector_v24/small_vectors'),small,3)
write_cases(Path('build/pl_detector_v24/full_vectors'),[smooth_rgb(samples()[13][2]),smooth_rgb(samples()[9][2])],15)
a=np.empty((64,64,3),np.uint8);a[:]=(40,120,40)
for y in (8,20,32,44):
    for x in (8,20,32,44):a[y:y+4,x:x+4]=(100,60,40)
write_cases(Path('build/pl_detector_v24/many_vectors'),[a],3)
assert len(detect(a,radius=3)[0])==16
