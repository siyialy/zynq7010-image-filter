"""Check complete-frame rendering and coordinate mapping with structured inputs."""
import ctypes as ct
from pathlib import Path
import numpy as np

root=Path(__file__).resolve().parents[1]
lib=ct.CDLL(str(root/'build/pl_detector_v22/render.dll'))
ptr=ct.POINTER(ct.c_uint8)
lib.pest_render.argtypes=[ptr,ct.c_void_p,ptr]
class Box(ct.Structure):
    _fields_=[(n,ct.c_uint16) for n in ('x0','y0','x1','y1')]+[('area',ct.c_uint32)]
lib.pest_map_box.argtypes=[ct.c_int]*4+[ct.c_uint32,ct.POINTER(Box)]
def render(a):
    out=np.zeros((240,320),np.uint8)
    # Rendering does not inspect detection results; enough storage for either ABI.
    result=ct.create_string_buffer(256)
    lib.pest_render(a.ctypes.data_as(ptr),result,out.ctypes.data_as(ptr))
    assert out.max()<128
    return out

for value in (0,64,128,192,255):
    out=render(np.full((256,256,3),value,np.uint8))
    assert np.all(out[:,40:280]==value//2),'Image tone changed'
for edge in ('top','bottom','left','right'):
    a=np.zeros((256,256,3),np.uint8)
    if edge=='top':a[:8]=255
    if edge=='bottom':a[-8:]=255
    if edge=='left':a[:,:8]=255
    if edge=='right':a[:,-8:]=255
    out=render(a)[:,40:280]
    pixels={'top':out[0],'bottom':out[-1],'left':out[:,0],'right':out[:,-1]}[edge]
    assert np.all(pixels==127),f'{edge} cropped'
for y in range(256):
    for x in range(256):
        b=Box();assert lib.pest_map_box(x,y,x,y,1,ct.byref(b))
        expected=(max(40,min(279,(x*15+15)//16+38)),
                  max(0,min(239,(y*15+15)//16-2)),
                  max(40,min(279,((x+1)*15+15)//16+41)),
                  max(0,min(239,((y+1)*15+15)//16+1)))
        assert (b.x0,b.y0,b.x1,b.y1)==expected,(x,y,b.x0,b.y0,expected)
print('PASS: complete source edges, primary tones, 7-bit safety and all 65,536 coordinate mappings')
