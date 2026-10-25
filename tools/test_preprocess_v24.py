"""Real C rolling-row mean must exactly retain border and integer-rounding semantics."""
import ctypes as ct
from pathlib import Path
import numpy as np
from review_pest import samples
from pl_detector_model import smooth_rgb

lib=ct.CDLL(str(Path('build/pl_detector_v24/preprocess.dll').resolve()))
lib.pl_preprocess_frame.argtypes=[ct.POINTER(ct.c_uint8),ct.POINTER(ct.c_uint32)]
def check(a):
    result=np.zeros((256,256),np.uint32)
    lib.pl_preprocess_frame(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),result.ctypes.data_as(ct.POINTER(ct.c_uint32)))
    sm=smooth_rgb(a).astype(np.uint32)
    assert np.array_equal(result,sm[:,:,0]|(sm[:,:,1]<<8)|(sm[:,:,2]<<16))
for _,_,a in samples():check(a)
for value in (0,1,127,255):check(np.full((256,256,3),value,np.uint8))
a=np.zeros((256,256,3),np.uint8)
a[0,0]=[255,1,128];a[-1,-1]=[1,255,128];a[0,-1]=[128,1,255];a[-1,0]=255
check(a)
check(np.random.default_rng(24).integers(0,256,(256,256,3),dtype=np.uint8))
print('PASS: 24 complete RGB frames, constant levels, corner impulses and random input match exact original 3x3 mean')
