"""Preview the actual C renderer. Only generated previews are written."""
import ctypes as ct
import json
import numpy as np
from PIL import Image,ImageDraw
from review_pest import ROOT,OUT,Box,Result,samples,compile_detector

lib=compile_detector(ROOT/'ps_app/pest.c','after')
lib.pest_render_background.argtypes=[ct.POINTER(ct.c_uint8),ct.POINTER(ct.c_uint8)]
reference=json.loads((OUT/'after.json').read_text())
dest=ROOT/'build/display_review'
chosen=[]
for i,name,a in samples():
    r=Result();lib.pest_detect(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(r))
    actual=[[b.x0,b.y0,b.x1,b.y1,b.area] for b in r.box[:r.num_box]]
    assert actual==reference[i]['boxes'] and r.diseased==reference[i]['diseased'],i+1
    buf=np.zeros((240,320),np.uint8)
    lib.pest_render(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(r),buf.ctypes.data_as(ct.POINTER(ct.c_uint8)))
    bg=np.zeros((60,32),np.uint8)
    lib.pest_render_background(buf.ctypes.data_as(ct.POINTER(ct.c_uint8)),bg.ctypes.data_as(ct.POINTER(ct.c_uint8)))
    assert buf.max()<128 and bg.max()<128
    # Check scratch-buffer reuse cannot change a subsequent detection.
    again=Result();lib.pest_detect(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(again))
    assert bytes(r)==bytes(again)
    if i in (1,8,11,17):
        rows=32+np.arange(240)*4//5;cols=np.arange(320)*4//5
        rgb=a[rows[:,None],cols[None,:]].astype(np.uint32)
        raw=(((77*rgb[...,0]+150*rgb[...,1]+29*rgb[...,2])>>8).astype(np.uint8)>>1)*2
        chosen.append((i+1,Image.fromarray(raw),Image.fromarray(buf*2)))
    if i in (11,22):
        frame=Image.new('RGB',(1280,720))
        frame.paste(Image.fromarray(buf*2).convert('RGB').resize((960,720),Image.Resampling.NEAREST),(160,0))
        frame.paste(Image.fromarray(bg[:,:16]*2).convert('RGB').resize((160,720),Image.Resampling.NEAREST),(0,0))
        frame.paste(Image.fromarray(bg[:,16:]*2).convert('RGB').resize((160,720),Image.Resampling.NEAREST),(1120,0))
        frame.save(dest/f'sample_{i+1}_soft_background.jpg')
        buf.tofile(dest/f'sample_{i+1}_main.bin');bg.tofile(dest/f'sample_{i+1}_background.bin')
canvas=Image.new('RGB',(1280,560),'white');d=ImageDraw.Draw(canvas)
for j,(index,before,after) in enumerate(chosen):
    x=j%2*640;y=j//2*280
    canvas.paste(before.convert('RGB'),(x,y+30));canvas.paste(after.convert('RGB'),(x+320,y+30))
    d.text((x+8,y+8),f'Sample {index}: original display',fill='black')
    d.text((x+328,y+8),f'Sample {index}: denoise + bilinear',fill='black')
canvas.save(dest/'display_before_after.jpg')
print('PASS: current detector results match review for all 24 samples, renderer bit7 clear, render/detect scratch reuse safe.')
