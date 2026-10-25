"""Test general parent-region refinement using cached detector branches.

No sample IDs, truth boxes or labels are inputs to fuse().
"""
import argparse,itertools,json
from pathlib import Path
from experiment_v25 import DATA,TRUTH,OUT
from evaluate_annotations import evaluate,area,intersection

def overlap_small(a,b):return intersection(a,b)/min(area(a),area(b))
def grow(b,pad):return [max(0,b[0]-pad),max(0,b[1]-pad),min(256,b[2]+pad),min(256,b[3]+pad)]
def fuse(base,branches,*,pad=3,parent_min=400,remove_dim=85,min_area=20,merge=True,parent_pad=0,priority=False,merge_overlap=False,weak_large=False):
    predictions={}
    for image,details in zip(DATA['images'],base['details']):
        image_id=image['id'];old=base['predictions'][image_id]
        kept=[dict(p) for p in old if max(p['bbox'][2]-p['bbox'][0],p['bbox'][3]-p['bbox'][1])<remove_dim and not (weak_large and p['area']>=200 and p['score']<p['area']*3)]
        parents=[]
        for r in details['records']:
            x0,y0,x1,y1=r['src'];b=[x0,y0,x1+1,y1+1]
            if r['area']>=parent_min and area(b)>=1500:parents.append(grow(b,parent_pad))
        extra=[]
        for rank,branch in enumerate(branches):
            for p in branch['predictions'][image_id]:
                if p['area']<min_area:continue
                if priority and (min(p['bbox'][:2])<=0 or max(p['bbox'][2:])>=256):continue
                b=grow(p['bbox'],pad)
                if not any(intersection(b,parent)/area(b)>=.8 for parent in parents):continue
                if any(overlap_small(b,q['bbox'])>=.5 for q in kept):continue
                extra.append(dict(p,bbox=b,_tier=rank))
        if priority:
            unique=[]
            for p in extra:
                if any(overlap_small(p['bbox'],q['bbox'])>=.65 for q in unique):continue
                unique.append(p)
            extra=unique
        if merge:
            changed=True
            while changed:
                changed=False
                for i,j in itertools.combinations(range(len(extra)),2):
                    a,b=extra[i]['bbox'],extra[j]['bbox']
                    gapx=max(0,max(a[0],b[0])-min(a[2],b[2]));gapy=max(0,max(a[1],b[1])-min(a[3],b[3]))
                    if (min(area(a),area(b))<=200 and max(gapx,gapy)<=3) or (merge_overlap and overlap_small(a,b)>=.25):
                        box=[min(a[0],b[0]),min(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])]
                        extra[i]=dict(extra[i],bbox=box,score=max(extra[i]['score'],extra[j]['score']));extra.pop(j);changed=True;break
        extra.sort(key=lambda p:(p.get('_tier',0) if priority else 0,-p['score']))
        for p in extra:
            if any(overlap_small(p['bbox'],q['bbox'])>=.5 for q in kept):continue
            kept.append(p)
        for j,p in enumerate(kept):
            b=p['bbox'];p['id']=f'new_{j}'
            # Display the tight source box with a bounded, size-aware margin.
            x0=max(40,min(279,40+(b[0]*15+8)//16));y0=max(0,min(239,(b[1]*15+8)//16))
            p['display_bbox']=[x0,y0,max(x0+1,min(280,40+(b[2]*15+8)//16)),max(y0+1,min(240,(b[3]*15+8)//16))]
        predictions[image_id]=kept[:32]
    return predictions

if __name__=='__main__':
    base=json.loads((OUT/'baseline.json').read_text())
    for branch_name,pad,min_area in itertools.product(['strict_erode7','strict_erode5','strict_erode3'],[0,1,2,3,4],[9,20,40]):
        branch=json.loads((OUT/f'{branch_name}.json').read_text());name=f'fusion_{branch_name}_p{pad}_a{min_area}'
        prediction=fuse(base,[branch],pad=pad,min_area=min_area)
        src=evaluate(DATA,TRUTH,predictions=prediction);disp=evaluate(DATA,TRUTH,predictions=prediction,space='display')
        if src['tp']>=57 and src['fp']<=10:
            row=dict(name=name,branch=branch_name,pad=pad,min_area=min_area,source=src,display=disp,predictions=prediction)
            (OUT/f'{name}.json').write_text(json.dumps(row,indent=2))
            print(name,'TP',src['tp'],'FP',src['fp'],'FN',src['fn'],'displayTP',disp['tp'],flush=True)
