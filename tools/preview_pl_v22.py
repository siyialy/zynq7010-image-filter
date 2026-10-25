"""Render PS pixels with board-read PL boxes; images are previews, not HDMI captures."""
import ctypes as ct,json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from review_pest import samples

root=Path(__file__).resolve().parents[1];out=root/'build/pl_detector_v22'
board=json.loads((out/'board_results.json').read_text())
old=json.loads((root/'build/precision_review/board_v21.json').read_text())
ptr=ct.POINTER(ct.c_uint8)
newlib=ct.CDLL(str(out/'render.dll'))
oldlib=ct.CDLL(str(root/'build/pest_review/after.dll'))
for lib in (oldlib,newlib):lib.pest_render.argtypes=[ptr,ct.c_void_p,ptr]
def frame(lib,a,boxes):
    buf=np.zeros((240,320),np.uint8);result=ct.create_string_buffer(256)
    lib.pest_render(a.ctypes.data_as(ptr),result,buf.ctypes.data_as(ptr))
    im=Image.fromarray(buf*2).convert('RGB');draw=ImageDraw.Draw(im)
    for b in boxes:draw.rectangle(b[:4],outline=(255,30,20),width=1)
    return im.resize((640,480),Image.Resampling.NEAREST)
items={i+1:a for i,_,a in samples()}
review=[14,16,17,19,20,24]
canvas=Image.new('RGB',(1280,510*len(review)),(24,26,28));d=ImageDraw.Draw(canvas)
for row,n in enumerate(review):
    a=items[n];before=old[n-1]['boxes'];after=board[n-1]['boxes']
    d.text((12,row*510+8),f'Sample {n} | v2.1: {len(before)} boxes',fill='white')
    d.text((652,row*510+8),f'Sample {n} | v2.2: {len(after)} boxes | full source image',fill='white')
    canvas.paste(frame(oldlib,a,before),(0,row*510+30))
    im=frame(newlib,a,after);canvas.paste(im,(640,row*510+30))
    im.save(out/f'sample_{n:02d}_v22.png')
canvas.save(out/'localization_before_after.jpg',quality=92)
print(out/'localization_before_after.jpg')
