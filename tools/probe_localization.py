"""Offline localization experiments on the embedded RGB samples, never photo pixels."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from review_pest import samples, sheet, OUT

def components(mask):
    h,w=mask.shape; seen=np.zeros(mask.shape,bool)
    for y,x in zip(*np.where(mask)):
        if seen[y,x]: continue
        q=[(int(y),int(x))];seen[y,x]=1
        for yy,xx in q:
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    ny,nx=yy+dy,xx+dx
                    if 0<=ny<h and 0<=nx<w and mask[ny,nx] and not seen[ny,nx]:
                        seen[ny,nx]=1;q.append((ny,nx))
        yield q

def morph(a,op,size):
    f=ImageFilter.MaxFilter(size) if op=='max' else ImageFilter.MinFilter(size)
    return np.array(Image.fromarray(a.astype(np.uint8)).filter(f))

def leaf_mask(r,g,b):
    plant=(((g-b>6)|(r-b>15)) & (np.maximum.reduce([r,g,b])-np.minimum.reduce([r,g,b])>12))
    plant=morph(morph(plant,'max',3),'min',3)>0
    main=max(components(plant),key=len,default=[]); leaf=np.zeros((256,256),bool)
    for y,x in main:leaf[y,x]=1
    outside=np.zeros_like(leaf);q=[]
    for y,x in [(y,x) for y in (0,255) for x in range(256)]+[(y,x) for x in (0,255) for y in range(256)]:
        if not leaf[y,x] and not outside[y,x]:outside[y,x]=1;q.append((y,x))
    for y,x in q:
        for dy,dx in ((0,1),(0,-1),(1,0),(-1,0)):
            ny,nx=y+dy,x+dx
            if 0<=ny<256 and 0<=nx<256 and not leaf[ny,nx] and not outside[ny,nx]:outside[ny,nx]=1;q.append((ny,nx))
    return morph(~outside,'min',3)>0

def run(a):
    padded=np.pad(a.astype(int),((1,1),(1,1),(0,0)),mode='edge'); sm=np.zeros_like(a,dtype=int)
    for dy in range(3):
        for dx in range(3):sm+=padded[dy:dy+256,dx:dx+256]
    sm//=9;r,g,b=sm.transpose(2,0,1);v=(r*77+g*150+b*29)>>8
    # Closing estimates the local bright tissue envelope rather than one global threshold.
    closed=morph(morph(v,'max',31),'min',31).astype(int)
    contrast=closed-v
    green=(g-b>10)&(g*100>r*70)
    leaf=leaf_mask(r,g,b)
    # Disease colours include brown and desaturated grey/purple, but not saturated yellow.
    brown=(r-g>6)&(r-b>5)&((r-g)*100>(r-b)*45)
    neutral=(r*100>=g*80)&(b*100>=g*90)
    candidate=(brown|neutral)&(v>=30)&(v<145)&(contrast>=12)&leaf
    candidate=morph(morph(candidate,'min',3),'max',3)>0
    candidate=morph(morph(candidate,'max',3),'min',3)>0
    candidate &= leaf
    boxes=[]
    for cc in components(candidate):
        ys,xs=np.array(cc).T;x0,x1=int(xs.min()),int(xs.max());y0,y1=int(ys.min()),int(ys.max())
        w,h=x1-x0+1,y1-y0+1; area=len(cc)
        if area<10 or min(w,h)<3 or max(w,h)>4*min(w,h) or area*100<w*h*25:continue
        sides=[green[max(0,y0-5):y0,max(0,x0-2):min(256,x1+3)],green[y1+1:min(256,y1+6),max(0,x0-2):min(256,x1+3)],green[y0:y1+1,max(0,x0-5):x0],green[y0:y1+1,x1+1:min(256,x1+6)]]
        support=[int(s.mean()*100) if s.size else 0 for s in sides]
        if sum(s>25 for s in support)<3 or sum(support)<180:continue
        # Reject broad edge bands and rank by reliable support / local darkness.
        if w>65 or h>65:continue
        score=int(sum(contrast[yy,xx] for yy,xx in cc))
        boxes.append((score,(x0,y0,x1,y1),area,support))
    boxes.sort(reverse=True)
    return boxes[:8],candidate,contrast

if __name__=='__main__':
    items=[]; masks=[]
    for i,n,a in samples():
        boxes,cand,con=run(a)
        im=Image.fromarray(a);d=ImageDraw.Draw(im)
        for score,box,area,sup in boxes:d.rectangle(box,outline='red',width=1)
        items.append((i,f'{len(boxes)} boxes',im))
        m=a.copy();m[cand]=(255,0,0);masks.append((i,'candidates',Image.fromarray(m)))
        print(i+1,boxes)
    sheet(items[:12],'probe_v14_healthy.jpg');sheet(items[12:],'probe_v14_blight.jpg')
    sheet(masks[12:],'probe_v14_masks.jpg')
