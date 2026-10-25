"""Frozen integer operations for the v2.5 offline reference; no annotations or sample IDs."""
from collections import deque
import numpy as np
from PIL import Image,ImageFilter

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

def detect(rgb,radius=15,crop_y=32,crop_h=192,threshold=6,profile=None):
 profile=profile or {}
 p=rgb.astype(np.int32);r,g,b=p.transpose(2,0,1);v=((r*77+g*150+b*29)>>11).astype(np.uint8)
 brown=(r-g>threshold)&(r-b>5)&((r-g)*100>(r-b)*45)
 classic=brown|((r*100>=g*80)&(b*100>=g*profile.get('core_bg',90)))
 if profile.get('warm_dark',False):classic |= (v<=3)&(r>=g+3)&(g-b>6)
 if profile.get('flat_dark',-1)>=0:classic |= v<=profile['flat_dark']
 original=classic.copy()
 if profile.get('dark_olive',False):original |= (r>=g+profile.get('olive_delta',0))&(g-b>10)&(v<profile.get('olive_vmax',9))
 cand=brown|((r*100>=g*profile.get('rg',80))&(b*100>=g*profile.get('bg',90)))
 if profile.get('dark_olive',False):cand |= (r>=g+profile.get('olive_delta',0))&(g-b>10)&(v<profile.get('olive_vmax',9))
 if profile.get('warm_dark',False):cand |= (v<=3)&(r>=g+3)&(g-b>6)
 if profile.get('flat_dark',-1)>=0:cand |= v<=profile['flat_dark']
 if profile.get('olive',False):cand |= (r+profile.get('olive_gap',6)>=g)&(r-b>12)
 if profile.get('strict_candidate',False):cand=classic.copy()
 if profile.get('strict_dark',False):cand |= (v<=profile.get('strict_dark_v',3))&(r>=g)&(r-b>4)
 seed=((g-b>12)|(r-b>25))&((p.max(2)-p.min(2))>20)
 tissue=(g-b>10)&(g*100>r*70);green=(g-r>8)&(g-b>8)
 if profile.get('warm_dark',False):seed |= (v<=3)&(r>=g+3)&(g-b>6)
 if profile.get('dark_seed',-1)>=0:seed |= v<=profile['dark_seed']
 if profile.get('leaf_chroma',0):seed |= ((g-b>profile.get('leaf_gb',10))|(r-b>profile.get('leaf_rb',12)))&((p.max(2)-p.min(2))>profile['leaf_chroma'])
 if profile.get('brown_leaf',False):seed |= (r-g>=3)&(g-b>=3)&(r-b>=8)
 leaf=morph(morph(seed,True),False)>0
 if profile.get('largest',False):
  best=max((p for p,_ in components(leaf)),key=len,default=[]);leaf[:]=False
  for yy,xx in best:leaf[yy,xx]=True
 h,w=leaf.shape;outside=np.zeros_like(leaf);q=deque()
 for y in range(h):
  for x in range(w):
   if (y in (0,h-1) or x in (0,w-1)) and not leaf[y,x]:outside[y,x]=1;q.append((y,x))
 while q:
  y,x=q.popleft()
  for dy,dx in ((-1,0),(1,0),(0,-1),(0,1)):
   ny,nx=y+dy,x+dx
   if 0<=ny<h and 0<=nx<w and not leaf[ny,nx] and not outside[ny,nx]:outside[ny,nx]=1;q.append((ny,nx))
 leaf=(~outside) if profile.get('keep_edge',False) else (morph(~outside,False)>0)
 dil=morph(v,True,2*radius+1);env=morph(dil,False,2*radius+1)
 contrast=env.astype(int)-v.astype(int)
 low=(contrast>=profile.get('contrast',2))
 if profile.get('warm_flat',False):low |= (v<=3)&original
 if profile.get('flat_dark',-1)>=0:low |= v<=profile['flat_dark']
 if profile.get('low_gray',False):low |= (contrast>=1)&classic&(v<=9)
 mask=leaf&cand&(v>=profile.get('vmin',4))&(v<18)&low
 if profile.get('grow',0):
  allowed=mask.copy();mask=allowed&original
  for _ in range(profile['grow']):mask=(morph(mask,True)>0)&allowed
 if profile.get('preclose',False):mask=morph(morph(mask,True),False)>0
 if profile.get('median',False):mask=np.asarray(Image.fromarray(mask.astype(np.uint8)).filter(ImageFilter.MedianFilter(3)))
 else:mask=morph(morph(mask,False),True)
 mask=morph(morph(mask,True),False)>0;mask&=leaf
 if profile.get('extra_erode',0):mask=morph(mask,False,profile['extra_erode'])>0
 selected=[];peaks=[];records=[];source_lookup={}
 def support(flag,x0,y0,x1,y1):
  a=flag[max(0,y0):min(h,y1),max(0,x0):min(w,x1)];return int(a.sum())*100//a.size if a.size else 0
 for pixels,peak in components(mask):
  peaks.append(peak);ys,xs=zip(*pixels);area=len(pixels);x0,x1=min(xs),max(xs);y0,y1=min(ys),max(ys);ww,hh=x1-x0+1,y1-y0+1
  if area<profile.get('min_area',10) or ww<3 or hh<3 or ww>4*hh or hh>4*ww or area*100<ww*hh*25 or max(ww,hh)>profile.get('max_dim',65):continue
  rings=[(x0-2,y0-5,x1+3,y0),(x0-2,y1+1,x1+3,y1+6),(x0-5,y0,x0,y1+1),(x1+1,y0,x1+6,y1+1)]
  dark_count=sum(bool(v[y,x]<=(3 if profile.get('warm_dark',False) else profile.get('flat_dark',-1))) for y,x in pixels)
  ts=[support(tissue,*z) for z in rings];gs=[support(green,*z) for z in rings];hs=[support(original&tissue&~green,*z) for z in rings];score=sum(int(contrast[y,x]) for y,x in pixels)+dark_count*2
  core=sum(bool(original[y,x]) for y,x in pixels)
  records.append(dict(src=[x0,y0,x1,y1],area=area,tissue=ts,green=gs,halo=hs,score=score,core=core))
  enclosed_gray=(profile.get('enclosed_gray',False) and core>=profile.get('enc_core',1) and 9<=area<=256 and min(ts)>=profile.get('enc_t',75) and min(gs)>=profile.get('enc_g',75) and sum(gs)>=profile.get('enc_sum',340) and score>=area*profile.get('enc_score',3) and ww<=2*hh and hh<=2*ww and area*100>=ww*hh*50)
  if profile.get('core',0) and core*100<area*profile['core'] and not enclosed_gray:continue
  classic_count=sum(bool(classic[y,x]) for y,x in pixels)
  if profile.get('new_tier',False) and classic_count*100<area*30:
   enclosed=min(ts)>25 and sum(ts)>=290 and (sum(gs)>=120 or sum(hs)>=160)
   compact=area>=100 and (score>=area*6 or (area*100>=ww*hh*50 and score>=area*4))
   edge=area<=64 and area*100>=ww*hh*50 and sum(gs)>=100 and sum(hs)>=60 and score>=area*3
   if not (enclosed or compact or edge or enclosed_gray):continue
  is_dark=profile.get('dark_edge',False) and area>=20 and dark_count*2>=area
  if sum(z>25 for z in ts)<(2 if is_dark else profile.get('sides',3)) or sum(ts)<(100 if is_dark else profile.get('tsum',180)):continue
  if profile.get('halo_gate',0) and sum(gs)+sum(hs)<profile['halo_gate']:continue
  if profile.get('edge_green',False) and sum(gs)<30 and area<100:continue
  strong=sum(bool(seed[y,x] and not green[y,x]) for y,x in pixels)
  faded=area>=20 and min(ts)>25 and sum(ts)>=290 and sum(gs)>=60 and score>=area*2
  if strong*2<area and sum(gs)<120 and not faded and not enclosed_gray:continue
  if sum(gs)<180 and not faded and strong*2<area and not enclosed_gray:continue
  if not profile.get('full_view',False) and (y1<crop_y or y0>=crop_y+crop_h):continue
  # Match the existing display crop mapping and two display-pixel margin.
  bx0=max(0,(x0*5+3)//4-2);bx1=min(319,((x1+1)*5+3)//4+1)
  by0=max(0,((max(y0,crop_y)-crop_y)*5+3)//4-2);by1=min(239,((min(y1,crop_y+crop_h-1)-crop_y+1)*5+3)//4+1)
  if profile.get('full_view',False):
   bx0=max(40,(x0*15+15)//16+38);bx1=min(279,((x1+1)*15+15)//16+41)
   by0=max(0,(y0*15+15)//16-2);by1=min(239,((y1+1)*15+15)//16+1)
  if profile.get('display_padding',2)!=2:
   pad=profile['display_padding'];bx0=max(40,(x0*15+15)//16+40-pad);by0=max(0,(y0*15+15)//16-pad)
   bx1=min(279,((x1+1)*15+15)//16+39+pad);by1=min(239,((y1+1)*15+15)//16-1+pad)
  box=[bx0,by0,bx1,by1,area,score]
  source_lookup[tuple(box)]=[x0,y0,x1+1,y1+1]
  def dup(a):
   xx=max(0,min(a[2],box[2])-max(a[0],box[0])+1);yy=max(0,min(a[3],box[3])-max(a[1],box[1])+1)
   return xx*yy*100>min((a[2]-a[0]+1)*(a[3]-a[1]+1),(box[2]-box[0]+1)*(box[3]-box[1]+1))*60
  if any(dup(a) and a[5]>=score for a in selected):continue
  selected=[a for a in selected if not dup(a)]+[box];selected.sort(key=lambda a:-a[5]);selected=selected[:profile.get('max_boxes',8)]
 return selected,dict(src_boxes=[dict(bbox=source_lookup[tuple(b)],area=b[4],score=b[5],display_bbox=[b[0],b[1],b[2]+1,b[3]+1]) for b in selected],records=records,contrast=contrast,peak=max(peaks,default=0),mask=mask,leaf=leaf,meta=v.astype(np.uint16)|(cand.astype(np.uint16)<<5)|(seed.astype(np.uint16)<<6)|(tissue.astype(np.uint16)<<7)|(green.astype(np.uint16)<<8))

