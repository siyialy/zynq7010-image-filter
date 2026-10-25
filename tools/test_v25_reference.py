"""Label-free synthetic checks of the v2.5 offline reference."""
import copy
import numpy as np
from lesion_detector_v25 import detect,refine,display_bounds
from pl_detector_model import smooth_rgb

for rgb in [(40,120,40),(100,100,100)]:
    a=np.zeros((256,256,3),np.uint8);a[:]=rgb
    assert detect(smooth_rgb(a))==[]
a=np.empty((256,256,3),np.uint8);a[:]=(40,120,40);a[100:112,100:112]=(100,60,40)
first=detect(smooth_rgb(a));assert first
b=np.empty_like(a);b[:]=(40,120,40);b[104:116,108:120]=(100,60,40)
second=detect(smooth_rgb(b));assert len(first)==len(second)
assert [p['bbox'] for p in second]==[[q['bbox'][0]+8,q['bbox'][1]+4,q['bbox'][2]+8,q['bbox'][3]+4] for q in first]
assert first==detect(smooth_rgb(a)),'Detector must not depend on prior image/order'
assert display_bounds([0,0,1,1])==[40,0,41,1]
assert display_bounds([255,255,256,256])==[279,239,280,240]
try:detect(np.zeros((32,32,3),np.uint8));raise AssertionError('Wrong size accepted')
except ValueError:pass
base=[dict(bbox=[10,10,130,130],area=4000,score=12000)]
parents=[dict(src=[10,10,129,129],area=4000)]
branch=[[dict(bbox=[30,30,40,40],area=30,score=200)]]
saved=copy.deepcopy((base,parents,branch));result=refine(base,parents,branch)
assert result[0]['bbox']==[27,27,43,43]
assert (base,parents,branch)==saved,'Input records must not be modified'
print('PASS: constant inputs, translation, repeated image/order independence, integer display edges, size guards and non-mutating refinement; no human labels used in these tests.')
