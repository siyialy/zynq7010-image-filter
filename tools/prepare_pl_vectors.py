"""Synthetic, label-independent vectors for bit-exact Python/Verilog checks."""
from pathlib import Path
import json
import numpy as np
from pl_detector_model import detect

dest=Path('build/pl_detector/vectors');dest.mkdir(parents=True,exist_ok=True)
cases=[]
def frame(colour):
    a=np.zeros((32,32,3),np.uint8);a[:]=colour;return a
cases += [frame((40,120,40)),frame((100,100,100)),frame((90,55,30))]
a=frame((40,120,40));a[12:19,12:19]=(100,60,40);cases.append(a)
a=frame((40,120,40));a[12:19,12:19]=(65,65,65);cases.append(a)
a=frame((140,130,140));a[5:27,5:27]=(50,120,50);a[12:18,12:18]=(100,60,40);cases.append(a)
a=frame((140,130,140));a[5:27,5:27]=(50,120,50);a[0:5,0:5]=(55,45,40);cases.append(a)
a=frame((40,120,40));a[6:11,6:11]=(100,60,40);a[21:26,21:26]=(100,60,40);cases.append(a)
manifest=[]
for i,a in enumerate(cases):
    boxes,debug=detect(a,radius=3,crop_y=0,crop_h=32)
    (dest/f'rgb_{i}.mem').write_text('\n'.join(f'{int(b)<<16|int(g)<<8|int(r):06x}' for r,g,b in a.reshape(-1,3))+'\n')
    packed=debug['leaf'].astype(np.uint8)*2+debug['mask'].astype(np.uint8)
    (dest/f'masks_{i}.mem').write_text('\n'.join(f'{int(v):x}' for v in packed.flat)+'\n')
    flat=[len(boxes)]+[v for box in boxes for v in box[:5]]
    (dest/f'expected_{i}.mem').write_text('\n'.join(f'{v:08x}' for v in flat+[0]*(41-len(flat)))+'\n')
    manifest.append(dict(case=i,boxes=boxes,peak=debug['peak']))
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Prepared',len(cases),'synthetic cases; counts:',[len(z['boxes']) for z in manifest])
