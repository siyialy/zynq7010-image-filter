"""Frozen v2.3 hardware reference; decisions never depend on sample labels/IDs."""
import json
from pathlib import Path
from precision_v23_model import detect as evaluate
from pl_detector_model import smooth_rgb
from review_pest import samples

PROFILE=dict(largest=True,full_view=True,halo_gate=120,vmin=0,core=30,
             dark_olive=True,olive_vmax=18,olive_delta=3,max_dim=256,bg=65,
             keep_edge=True,max_boxes=16,new_tier=True,enclosed_gray=True,min_area=9,low_gray=True)

def detect(rgb,radius=15):
    return evaluate(rgb,radius=radius,profile=PROFILE)

if __name__=='__main__':
    rows=[]
    for i,name,a in samples():
        boxes,debug=detect(smooth_rgb(a))
        rows.append(dict(sample=i+1,boxes=boxes,diseased=int(bool(boxes))))
    out=Path('build/pl_detector_v23');out.mkdir(parents=True,exist_ok=True)
    (out/'python_results.json').write_text(json.dumps(rows,indent=2))
    print('v2.3 boxes:',[len(z['boxes']) for z in rows])
    print('Development FP:',sum(bool(z['boxes']) for z in rows[:12]),
          'detected positive images:',sum(bool(z['boxes']) for z in rows[12:]))
