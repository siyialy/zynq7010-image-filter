"""Display-quality checks using structured inputs, independent of sample labels."""
import ctypes as ct
import numpy as np
from review_pest import ROOT,Result,compile_detector

lib=compile_detector(ROOT/'ps_app/pest.c','after')
lib.pest_render_background.argtypes=[ct.POINTER(ct.c_uint8),ct.POINTER(ct.c_uint8)]
def render(a):
    out=np.zeros((240,320),np.uint8);r=Result()
    lib.pest_render(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(r),out.ctypes.data_as(ct.POINTER(ct.c_uint8)))
    assert np.max(out)<128
    return out

for value in (0,64,128,192,255):
    a=np.full((256,256,3),value,np.uint8)
    out=render(a)
    assert np.all(out==value//2),'constant tone changed or falsely marked'
    bg=np.zeros((60,32),np.uint8)
    lib.pest_render_background(out.ctypes.data_as(ct.POINTER(ct.c_uint8)),bg.ctypes.data_as(ct.POINTER(ct.c_uint8)))
    assert bg.max()<128 and np.all(bg==bg[0,0])

# Isolated salt/pepper grain should disappear without changing the flat region.
a=np.full((256,256,3),128,np.uint8)
a[::7,::7]=255;a[3::7,3::7]=0
assert np.all(render(a)==64),'isolated salt/pepper survived'

# A strong edge remains narrow; display denoising must not average it away.
a=np.full((256,256,3),64,np.uint8);a[:,128:]=192
out=render(a)
assert np.all(out[:,0:158]==32) and np.all(out[:,161:]==96)
assert np.count_nonzero((out[100]>32)&(out[100]<96))<=2

# Bilinear interpolation must reproduce a smooth horizontal intensity ramp.
a=np.repeat(np.arange(256,dtype=np.uint8)[None,:,None],256,axis=0)
a=np.repeat(a,3,axis=2).copy()
out=render(a)
expected=(np.floor(np.arange(320)*4/5+0.5).astype(np.uint16)>>1)
assert np.array_equal(out[100,6:314],expected[6:314]),'bilinear ramp/scaling offset'
print('PASS: constant tones, isolated impulse rejection, strong-edge preservation, bilinear ramp and mark-bit safety.')
