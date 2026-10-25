"""Integer PL reference. Input is RGB smoothed by PS; no dataset labels in detection."""
from collections import deque
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image,ImageFilter
from review_pest import samples

def smooth_rgb(a):
 p=np.pad(a.astype(np.int32),((1,1),(1,1),(0,0)),mode='edge');s=np.zeros(a.shape,np.int32)
 for dy in range(3):
  for dx in range(3):s+=p[dy:dy+a.shape[0],dx:dx+a.shape[1]]
 return (s//9).astype(np.uint8)

def morph(a,dilate,size=3):
 return np.asarray(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.MaxFilter(size) if dilate else ImageFilter.MinFilter(size)))

def components(a):
 m=a.copy();h,w=m.shape
 for y in range(h):
  for x in range(w):
   if not m[y,x]:continue
   m[y,x]=0;q=deque([(y,x)]);pixels=[];peak=1
   while q:
    yy,xx=q.popleft();pixels.append((yy,xx))
    for dy in (-1,0,1):
     for dx in (-1,0,1):
      ny,nx=yy+dy,xx+dx
      if 0<=ny<h and 0<=nx<w and m[ny,nx]:m[ny,nx]=0;q.append((ny,nx))
    peak=max(peak,len(q))
   yield pixels,peak

def detect(rgb,radius=15,crop_y=32,crop_h=192,threshold=6):
 p=rgb.astype(np.int32);r,g,b=p.transpose(2,0,1);v=((r*77+g*150+b*29)>>11).astype(np.uint8)
 brown=(r-g>threshold)&(r-b>5)&((r-g)*100>(r-b)*45)
 cand=brown|((r*100>=g*80)&(b*100>=g*90))
 seed=((g-b>12)|(r-b>25))&((p.max(2)-p.min(2))>20)
 tissue=(g-b>10)&(g*100>r*70);green=(g-r>8)&(g-b>8)
 leaf=morph(morph(seed,True),False)>0
 h,w=leaf.shape;outside=np.zeros_like(leaf);q=deque()
 for y in range(h):
  for x in range(w):
   if (y in (0,h-1) or x in (0,w-1)) and not leaf[y,x]:outside[y,x]=1;q.append((y,x))
 while q:
  y,x=q.popleft()
  for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):
   ny,nx=y+dy,x+dx
   if 0<=ny<h and 0<=nx<w and not leaf[ny,nx] and not outside[ny,nx]:outside[ny,nx]=1;q.append((ny,nx))
 leaf=morph(~outside,False)>0
 dil=morph(v,True,2*radius+1);env=morph(dil,False,2*radius+1)
 contrast=env.astype(int)-v.astype(int)
 mask=leaf&cand&(v>=4)&(v<18)&(contrast>=2)
 mask=morph(morph(mask,False),True);mask=morph(morph(mask,True),False)>0;mask&=leaf
 selected=[];peaks=[]
 def support(flag,x0,y0,x1,y1):
  a=flag[max(0,y0):min(h,y1),max(0,x0):min(w,x1)];return int(a.sum())*100//a.size if a.size else 0
 for pixels,peak in components(mask):
  peaks.append(peak);ys,xs=zip(*pixels);area=len(pixels);x0,x1=min(xs),max(xs);y0,y1=min(ys),max(ys);ww,hh=x1-x0+1,y1-y0+1
  if area<10 or ww<3 or hh<3 or ww>4*hh or hh>4*ww or area*100<ww*hh*25 or max(ww,hh)>65:continue
  rings=[(x0-2,y0-5,x1+3,y0),(x0-2,y1+1,x1+3,y1+6),(x0-5,y0,x0,y1+1),(x1+1,y0,x1+6,y1+1)]
  ts=[support(tissue,*z) for z in rings];gs=[support(green,*z) for z in rings];score=sum(int(contrast[y,x]) for y,x in pixels)
  if sum(z>25 for z in ts)<3 or sum(ts)<180:continue
  strong=sum(bool(seed[y,x] and not green[y,x]) for y,x in pixels)
  faded=area>=20 and min(ts)>25 and sum(ts)>=290 and sum(gs)>=60 and score>=area*2
  if strong*2<area and sum(gs)<120 and not faded:continue
  if sum(gs)<180 and not faded and strong*2<area:continue
  if y1<crop_y or y0>=crop_y+crop_h:continue
  # Match the existing display crop mapping and two display-pixel margin.
  bx0=max(0,(x0*5+3)//4-2);bx1=min(319,((x1+1)*5+3)//4+1)
  by0=max(0,((max(y0,crop_y)-crop_y)*5+3)//4-2);by1=min(239,((min(y1,crop_y+crop_h-1)-crop_y+1)*5+3)//4+1)
  box=[bx0,by0,bx1,by1,area,score]
  def dup(a):
   xx=max(0,min(a[2],box[2])-max(a[0],box[0])+1);yy=max(0,min(a[3],box[3])-max(a[1],box[1])+1)
   return xx*yy*100>min((a[2]-a[0]+1)*(a[3]-a[1]+1),(box[2]-box[0]+1)*(box[3]-box[1]+1))*60
  if any(dup(a) and a[5]>=score for a in selected):continue
  selected=[a for a in selected if not dup(a)]+[box];selected.sort(key=lambda a:-a[5]);selected=selected[:8]
 return selected,dict(contrast=contrast,peak=max(peaks,default=0),mask=mask,leaf=leaf,meta=v.astype(np.uint16)|(cand.astype(np.uint16)<<5)|(seed.astype(np.uint16)<<6)|(tissue.astype(np.uint16)<<7)|(green.astype(np.uint16)<<8))

if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--brown-cut',type=int,default=6)
 parser.add_argument('--radius',type=int,default=15)
 parser.add_argument('--output',type=Path,default=Path('build/pl_detector/python_results.json'))
 args=parser.parse_args()
 if not 1<=args.brown_cut<=255 or not 1<=args.radius<=15:parser.error('brown-cut must be 1..255, radius 1..15')
 rows=[]
 for i,name,a in samples():
  boxes,debug=detect(smooth_rgb(a),radius=args.radius,threshold=args.brown_cut);rows.append(dict(sample=i+1,diseased=int(bool(boxes)),boxes=boxes,peak=debug['peak']))
 print('boxes',[len(x['boxes']) for x in rows]);print('TP',sum(x['diseased'] for x in rows[12:]),'FP',sum(x['diseased'] for x in rows[:12]),'peak',max(x['peak'] for x in rows))
 args.output.parent.mkdir(parents=True,exist_ok=True)
 args.output.write_text(json.dumps(rows,indent=2))
