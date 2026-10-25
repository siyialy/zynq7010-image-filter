"""Check the real PS preprocessing function against the Python RGB model."""
import ctypes as ct
from pathlib import Path
import numpy as np
from pl_detector_model import smooth_rgb
from review_pest import samples
lib=ct.CDLL(str(Path('build/pl_detector/preprocess.dll').resolve()))
lib.pl_preprocess_pixel.argtypes=[ct.POINTER(ct.c_uint8),ct.c_int,ct.c_int]
lib.pl_preprocess_pixel.restype=ct.c_uint32
for i,_,a in samples():
    ptr=a.ctypes.data_as(ct.POINTER(ct.c_uint8))
    got=np.fromiter((lib.pl_preprocess_pixel(ptr,x,y) for y in range(256) for x in range(256)),np.uint32).reshape(256,256)
    sm=smooth_rgb(a).astype(np.uint32)
    expected=sm[:,:,0]|(sm[:,:,1]<<8)|(sm[:,:,2]<<16)
    assert np.array_equal(got,expected),i+1
print('PASS: PS C and Python smoothed RGB agree at every pixel of all 24 frames')
