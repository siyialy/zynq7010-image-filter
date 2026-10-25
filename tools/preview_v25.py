"""Reconstruct unchanged PS display pixels and old/new candidate overlay."""
import ctypes as ct,json
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from review_pest import ROOT,samples

out=ROOT/'build/algorithm_v25';result=json.loads((out/'candidate_verified.json').read_text(encoding='utf-8'))
data=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
lib=ct.CDLL(str(ROOT/'build/pl_detector_v22/render.dll'));ptr=ct.POINTER(ct.c_uint8)
lib.pest_render.argtypes=[ptr,ct.c_void_p,ptr]
try:font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
except OSError:font=ImageFont.load_default()
numbers=[16,18,21,22,23];canvas=Image.new('RGB',(1280,len(numbers)*520),'#19261e');draw=ImageDraw.Draw(canvas)
raw={i+1:a for i,_,a in samples()}
for row,n in enumerate(numbers):
    a=raw[n];buf=np.zeros((240,320),np.uint8)
    lib.pest_render(a.ctypes.data_as(ptr),ct.create_string_buffer(256),buf.ctypes.data_as(ptr))
    groups=[data['images'][n-1]['proposals'],result['predictions'][f'sample_{n:02d}']]
    pair=Image.new('RGB',(1280,520),'#19261e');d=ImageDraw.Draw(pair)
    for col,boxes in enumerate(groups):
        image=Image.fromarray(buf*2).convert('RGB');p=ImageDraw.Draw(image)
        for box in boxes:
            x0,y0,x1,y1=box['display_bbox'];p.rectangle([x0,y0,x1-1,y1-1],outline=(255,30,20),width=1)
        pair.paste(image.resize((640,480),Image.Resampling.NEAREST),(col*640,40))
        d.text((col*640+12,8),f'第 {n} 张 · '+('v2.4 上板框' if col==0 else 'v2.5 离线拟用框')+f' · {len(boxes)} 个',font=font,fill='white')
    pair.save(out/f'sample_{n:02d}_before_after.png')
    canvas.paste(pair,(0,row*520))
canvas.save(out/'before_after.jpg',quality=94)
print('Offline previews generated from unchanged C-rendered pixels; not HDMI captures.')
