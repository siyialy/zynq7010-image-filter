from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageDraw
from review_pest import ROOT,samples

out=ROOT/'build/leaf_review'
rows=json.loads((out/'results_v15.json').read_text())
for i,n,a in samples():
    p=np.pad(a.astype(int),((1,1),(1,1),(0,0)),mode='edge');sm=np.zeros_like(a,dtype=int)
    for dy in range(3):
        for dx in range(3):sm+=p[dy:dy+256,dx:dx+256]
    sm//=9;r,g,b=sm.transpose(2,0,1)
    green=(g-r>8)&(g-b>8)
    strict=(g-r>3)&(g-b>6)
    if i not in (16,21,23):continue
    im=Image.fromarray(a).resize((768,768));d=ImageDraw.Draw(im)
    print('SAMPLE',i+1)
    for j,(dx0,dy0,dx1,dy1,area) in enumerate(rows[i]['boxes']):
        x0=max(0,int(dx0*.8));x1=min(255,int(dx1*.8));y0=max(0,int(dy0*.8)+32);y1=min(255,int(dy1*.8)+32)
        sides=[green[max(0,y0-5):y0,max(0,x0-2):min(256,x1+3)],green[y1+1:min(256,y1+6),max(0,x0-2):min(256,x1+3)],green[y0:y1+1,max(0,x0-5):x0],green[y0:y1+1,x1+1:min(256,x1+6)]]
        sup=[int(s.mean()*100) if s.size else 0 for s in sides]
        cx=(x0+x1)//2;cy=(y0+y1)//2
        print(j,(x0,y0,x1,y1),'RGB',sm[cy,cx].tolist(),'strict_green',int(strict[y0:y1+1,x0:x1+1].sum()),'support',sup)
        d.rectangle((x0*3,y0*3,x1*3,y1*3),outline='red',width=2);d.text((x0*3,y0*3),str(j),fill='yellow')
    im.save(out/f'source_{i+1}_candidates.jpg')
    raw=a.astype(int);rr,gg,bb=raw.transpose(2,0,1);v=(rr*77+gg*150+bb*29)>>8
    cand=(rr-gg>15)&(v<140)
    print('raw brown total',int(cand.sum()),'raw brown on strong green',int((cand&green).sum()))
