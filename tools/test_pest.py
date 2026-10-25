"""Run the actual compiled detector and geometry helpers, not a Python rewrite."""
import ctypes as ct
import numpy as np
from PIL import Image, ImageFilter
from review_pest import compile_detector, ROOT, Box, Result, samples

lib = compile_detector(ROOT/'ps_app/pest.c', 'after')
probe = compile_detector(ROOT/'tools/pest_host_probe.c', 'probe_closing')
probe.pest_review_closing.argtypes = [ct.POINTER(ct.c_uint8),ct.POINTER(ct.c_uint8)]
probe.pest_review_keep.argtypes = [ct.POINTER(Result),ct.POINTER(ct.c_uint32),ct.POINTER(Box),ct.c_uint32]
selected=Result();scores=(ct.c_uint32*8)()
for box,score in [(Box(0,0,10,10,121),10),(Box(12,0,22,10,121),30)]:
    probe.pest_review_keep(ct.byref(selected),scores,ct.byref(box),score)
spanning=Box(0,0,22,10,253)
probe.pest_review_keep(ct.byref(selected),scores,ct.byref(spanning),20)
assert selected.num_box==2 and list(scores[:2])==[30,10],'rejected duplicate mutated existing candidates'
probe.pest_review_keep(ct.byref(selected),scores,ct.byref(spanning),40)
assert selected.num_box==1 and scores[0]==40 and selected.box[0].area==253
random = np.random.default_rng(7010)
for a in [np.zeros((256,256),np.uint8),np.full((256,256),200,np.uint8),
          np.tile(np.arange(256,dtype=np.uint8),(256,1)),
          random.integers(0,256,(256,256),dtype=np.uint8)]:
    out=np.zeros_like(a)
    probe.pest_review_closing(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),out.ctypes.data_as(ct.POINTER(ct.c_uint8)))
    expected=np.asarray(Image.fromarray(a).filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.MinFilter(31)))
    assert np.array_equal(out,expected),'C monotone-window closing disagrees with reference'
lib.pest_map_box.argtypes = [ct.c_int]*4+[ct.c_uint32,ct.POINTER(Box)]
lib.pest_map_box.restype = ct.c_int
lib.pest_insert_box.argtypes = [ct.POINTER(Result),ct.POINTER(Box)]

def mapped(x0,y0,x1,y1):
    b = Box()
    ok = lib.pest_map_box(x0,y0,x1,y1,1,ct.byref(b))
    if ok:
        assert 0 <= b.x0 <= b.x1 < 320 and 0 <= b.y0 <= b.y1 < 240
    return ok,b

# Old full-height-box failure, invisible bottom boxes, inverted and crossing bounds.
for rect in [(40,0,50,20),(40,224,50,255),(30,50,20,70),(0,80,20,70),(-20,40,-1,50),(256,40,300,50)]:
    assert mapped(*rect)[0] == 0, rect
for rect in [(0,0,10,40),(250,220,270,255),(-10,20,270,260),(0,32,255,223)]:
    assert mapped(*rect)[0] == 1, rect

# Exhaustively cover every rendered source column and row at both scaling boundaries.
for x in range(256):
    ok,b=mapped(x,100,x,100)
    out=[p for p in range(320) if p*4//5 == x]
    assert ok and b.x0 <= min(out) <= max(out) <= b.x1
for y in range(32,224):
    ok,b=mapped(100,y,100,y)
    out=[p for p in range(240) if 32+p*4//5 == y]
    assert ok and b.y0 <= min(out) <= max(out) <= b.y1

# A larger blob arriving after the first eight must displace the smaller one.
r=Result()
for area in range(1,101):
    b=Box(1,1,4,4,area); lib.pest_insert_box(ct.byref(r),ct.byref(b))
assert r.num_box == 8 and [b.area for b in r.box] == list(range(100,92,-1))

def detect(a):
    r=Result(); lib.pest_detect(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(r))
    assert r.num_box <= 8
    areas=[]
    for b in r.box[:r.num_box]:
        assert 0 <= b.x0 <= b.x1 < 320 and 0 <= b.y0 <= b.y1 < 240
        areas.append(b.area)
    assert areas == sorted(areas,reverse=True)
    return r

# Empty/full masks exercise maximum-size flood queues and stale-state reset.
for rgb in [(0,0,0),(128,128,128),(40,120,40),(110,60,30)]:
    a=np.empty((256,256,3),dtype=np.uint8); a[:]=rgb; detect(a)

fixed=samples()
for order in (fixed,list(reversed(fixed))):
    for i,_,a in order:
        r=detect(a)
        assert r.diseased == int(r.num_box > 0), (i+1,r.diseased,r.num_box)
        if i<12: assert r.num_box == 0
        # Do not force a box just because the frame label is diseased.
        elif i in (12,13,14,17,18,22): assert r.num_box > 0

# Partial, manually inspected development anchors, not a complete annotation set.
for index, rect in [(14,(98,145,112,158)),(18,(106,160,113,169)),(12,(115,105,135,136)),(17,(104,113,143,146)),(22,(132,52,178,105))]:
    ok,expected=mapped(*rect)
    assert ok
    result=detect(fixed[index][2])
    ref_area=(expected.x1-expected.x0+1)*(expected.y1-expected.y0+1)
    covered=[]
    for b in result.box[:result.num_box]:
        w=max(0,min(b.x1,expected.x1)-max(b.x0,expected.x0)+1)
        h=max(0,min(b.y1,expected.y1)-max(b.y0,expected.y0)+1)
        covered.append(w*h/ref_area)
    assert max(covered,default=0)>.60, (index+1,covered)

# Background/shadow points that v1.3 enclosed in misleading large boxes.
for index,(sx,sy) in [(12,(210,180)),(18,(205,180)),(22,(90,220)),(16,(24,161)),(16,(38,145)),(21,(52,114))]:
    x,y=sx*5//4,(sy-32)*5//4
    result=detect(fixed[index][2])
    assert not any(b.x0<=x<=b.x1 and b.y0<=y<=b.y1 for b in result.box[:result.num_box]),index+1

print('PASS: crop/scaling, top-8 helper, full masks, 24 verdict/box consistency checks forward/reverse, lesion anchors and shadow exclusions.')
