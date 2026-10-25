"""Full-size, radius-15 closing checks: real lesion and varied grey terrain."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from pl_detector_model import detect,smooth_rgb
from review_pest import samples

dest=Path('build/pl_detector_v21/full_vectors');dest.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(701021)
terrain=np.asarray(Image.fromarray(rng.integers(0,256,(16,16),np.uint8)).resize((256,256),Image.Resampling.BILINEAR))
cases=[smooth_rgb(samples()[14][2]),np.repeat(terrain[:,:,None],3,axis=2)]
manifest=[]
for i,a in enumerate(cases):
    boxes,d=detect(a)
    (dest/f'rgb_{i}.mem').write_text('\n'.join(f'{int(b)<<16|int(g)<<8|int(r):06x}' for r,g,b in a.reshape(-1,3))+'\n')
    (dest/f'contrast_{i}.mem').write_text('\n'.join(f'{int(v)&31:02x}' for v in d['contrast'].flat)+'\n')
    packed=d['leaf'].astype(np.uint8)*2+d['mask'].astype(np.uint8)
    (dest/f'masks_{i}.mem').write_text('\n'.join(f'{int(v):x}' for v in packed.flat)+'\n')
    flat=[len(boxes)]+[v for b in boxes for v in b[:5]]
    (dest/f'expected_{i}.mem').write_text('\n'.join(f'{v:08x}' for v in flat+[0]*(41-len(flat)))+'\n')
    manifest.append(dict(case=i,boxes=boxes))
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Prepared full 256x256, radius-15 vectors:',[len(x['boxes']) for x in manifest])
