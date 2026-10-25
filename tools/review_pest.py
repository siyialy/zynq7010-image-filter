"""Review the exact embedded sample order; never reselect or relabel samples."""
from pathlib import Path
import re
import ctypes as ct
import subprocess
import json
import sys
import hashlib
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'pest_review'
OUT.mkdir(parents=True, exist_ok=True)

class Box(ct.Structure):
    _fields_ = [('x0',ct.c_uint16),('y0',ct.c_uint16),('x1',ct.c_uint16),('y1',ct.c_uint16),('area',ct.c_uint32)]

class Result(ct.Structure):
    _fields_ = [(n,ct.c_uint32) for n in ('brown_px','leaf_px','frac_x100','num_box')] + [('diseased',ct.c_int),('bg',ct.c_uint8*3),('box',Box*8)]

def compile_detector(source, name):
    shim = OUT/'host_include'
    shim.mkdir(exist_ok=True)
    (shim/'xil_types.h').write_text('#include <stdint.h>\ntypedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;\n')
    dll = OUT/(name+'.dll')
    gcc = Path('D:/XILINX/Vivado/2018.3/tps/mingw/6.2.0/win64.o/nt/bin/gcc.exe')
    if '--no-compile' not in sys.argv:
        subprocess.run([str(gcc),'-shared','-O2','-Wall','-Wextra','-Ibuild/pest_review/host_include','-Ips_app',str(source.relative_to(ROOT)),'-o',str(dll.relative_to(ROOT))],cwd=ROOT,check=True)
    lib = ct.CDLL(str(dll))
    lib.pest_detect.argtypes = [ct.POINTER(ct.c_uint8),ct.POINTER(Result)]
    lib.pest_render.argtypes = [ct.POINTER(ct.c_uint8),ct.POINTER(Result),ct.POINTER(ct.c_uint8)]
    return lib

def evaluate(lib, name):
    items, rows = [], []
    for idx, title, a in samples():
        r = Result()
        lib.pest_detect(a.ctypes.data_as(ct.POINTER(ct.c_uint8)), ct.byref(r))
        disp = np.zeros((240,320),dtype=np.uint8)
        lib.pest_render(a.ctypes.data_as(ct.POINTER(ct.c_uint8)),ct.byref(r),disp.ctypes.data_as(ct.POINTER(ct.c_uint8)))
        im = Image.fromarray(disp.astype(np.uint8)*2).convert('RGB')
        d = ImageDraw.Draw(im)
        boxes = []
        for b in r.box[:r.num_box]:
            coords = (b.x0,b.y0,b.x1,b.y1)
            boxes.append([*coords,b.area])
            # Draw only representable coordinates; JSON retains invalid old boxes.
            if b.x0 <= b.x1 and b.y0 <= b.y1 and b.y1 < 240:
                d.rectangle(coords,outline='red',width=1)
        items.append((idx,f'{"D" if r.diseased else "H"} {r.frac_x100/100:.2f}% {r.num_box} boxes',im))
        rows.append(dict(sample=idx+1,label=int(idx>=12),diseased=r.diseased,frac=r.frac_x100,boxes=boxes))
    sheet(items[:12],name+'_healthy.jpg')
    sheet(items[12:],name+'_blight.jpg')
    (OUT/(name+'.json')).write_text(json.dumps(rows,indent=2))
    print(name, 'correct:',sum(r['label']==r['diseased'] for r in rows),'/24', 'boxes:',[len(r['boxes']) for r in rows])
    if name == 'after' and (OUT/'v1_3.json').exists():
        before=json.loads((OUT/'v1_3.json').read_text())
        canvas=Image.new('RGB',(1280,600),'white'); draw=ImageDraw.Draw(canvas)
        current={idx:im for idx,_,im in items}
        for slot,number in enumerate((19,20,22,23)):
            # Renderer pixel values are unchanged; draw both versions on the same crop.
            a=samples()[number-1][2]
            ys=32+np.arange(240)*4//5; xs=np.arange(320)*4//5
            rgb=a[ys[:,None],xs[None,:]].astype(np.uint32)
            lum=((rgb[...,0]*77+rgb[...,1]*150+rgb[...,2]*29)>>8).astype(np.uint8)
            old=Image.fromarray((lum>>1)*2).convert('RGB'); od=ImageDraw.Draw(old)
            for x0,y0,x1,y1,_ in before[number-1]['boxes']:
                if x0<=x1<320 and y0<=y1<240:od.rectangle((x0,y0,x1,y1),outline='red')
            base_x=(slot%2)*640; base_y=(slot//2)*300
            canvas.paste(old,(base_x,base_y+32));canvas.paste(current[number-1],(base_x+320,base_y+32))
            draw.text((base_x+8,base_y+8),f'Sample {number}: v1.3',fill='black')
            draw.text((base_x+328,base_y+8),f'Sample {number}: current detector',fill='black')
        canvas.save(OUT/'v13_vs_current.jpg')
    if name == 'after':
        (OUT/'review_manifest.json').write_text(json.dumps({'source_sha256':hashlib.sha256((ROOT/'ps_app/pest.c').read_bytes()).hexdigest(),'sample_header_sha256':hashlib.sha256((ROOT/'ps_app/pv_samples.h').read_bytes()).hexdigest(),'scope':'development samples, not an independent localization accuracy test'},indent=2))
    return rows

def samples():
    text = (ROOT/'ps_app/pv_samples.h').read_text(encoding='utf-8')
    data = text.split('static const unsigned char pv_rgb', 1)[1]
    result = []
    for match in re.finditer(r'\{\s*//\s*(\d+):\s*([^\s]+).*?\n(.*?)\n\s*\},', data, re.S):
        idx, name, values = match.groups()
        a = np.fromstring(values.replace('\n', '').replace(' ', '').rstrip(','), sep=',', dtype=np.uint8)
        result.append((int(idx), name, a.reshape(256,256,3)))
    assert len(result) == 24
    return result

def sheet(items, name):
    canvas = Image.new('RGB', (1200, 900), 'white')
    d = ImageDraw.Draw(canvas)
    for j, (idx, title, im) in enumerate(items):
        x, y = j%4*300, j//4*300
        thumb=im.copy();thumb.thumbnail((276,256))
        canvas.paste(thumb, (x+(300-thumb.width)//2,y+30))
        d.text((x+12,y+8), f'{idx+1}: {title}', fill='black')
    canvas.save(OUT/name)

if __name__ == '__main__':
    items = [(i,n,Image.fromarray(a)) for i,n,a in samples()]
    sheet(items[:12], 'original_healthy.jpg')
    sheet(items[12:], 'original_blight.jpg')
    source = ROOT/'ps_app/pest.c'
    baseline = OUT/'pest_before.c'
    if baseline.exists():
        evaluate(compile_detector(baseline,'before'),'before')
    else:
        print('No archived old source: skipping before comparison.')
    evaluate(compile_detector(source,'after'),'after')
