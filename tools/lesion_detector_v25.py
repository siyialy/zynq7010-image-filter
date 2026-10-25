"""Offline v2.5 candidate: global region refinement, no labels or sample IDs.

Input is the same 3x3-smoothed RGB consumed by PL. This is an algorithm
reference, not a bitstream and not a claim about hardware execution speed.
"""
from pl_detector_v23_model import PROFILE as BASE_PROFILE
from precision_v25_core import detect as region_detect

MAX_BOXES=32
REFINEMENT_PROFILES=(
    dict(brown_leaf=True,strict_candidate=True,extra_erode=7,max_boxes=32),
    dict(strict_candidate=True,extra_erode=7,max_boxes=32),
    dict(strict_candidate=True,extra_erode=5,max_boxes=32),
)

def area(b):return (b[2]-b[0])*(b[3]-b[1])
def intersection(a,b):return max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
def overlap_small(a,b):return intersection(a,b)/min(area(a),area(b))
def grow(b,pad):return [max(0,b[0]-pad),max(0,b[1]-pad),min(256,b[2]+pad),min(256,b[3]+pad)]
def display_bounds(b):
    """Integer 320x240 pixel grid, tight nearest-edge rounding; half-open."""
    x0=max(40,min(279,40+(b[0]*15+8)//16));y0=max(0,min(239,(b[1]*15+8)//16))
    return [x0,y0,max(x0+1,min(280,40+(b[2]*15+8)//16)),max(y0+1,min(240,(b[3]*15+8)//16))]

def refine(base_boxes,parent_records,branch_boxes):
    kept=[dict(p) for p in base_boxes
          if max(p['bbox'][2]-p['bbox'][0],p['bbox'][3]-p['bbox'][1])<85
          and not (p['area']>=200 and p['score']<p['area']*3)]
    parents=[]
    for r in parent_records:
        x0,y0,x1,y1=r['src'];b=[x0,y0,x1+1,y1+1]
        if r['area']>=400 and area(b)>=1500:parents.append(grow(b,12))
    extra=[]
    for tier,boxes in enumerate(branch_boxes):
        for p in boxes:
            if p['area']<20 or min(p['bbox'][:2])<=0 or max(p['bbox'][2:])>=256:continue
            b=grow(p['bbox'],3)
            if not any(intersection(b,parent)/area(b)>=.8 for parent in parents):continue
            if any(overlap_small(b,q['bbox'])>=.5 for q in kept):continue
            extra.append(dict(p,bbox=b,tier=tier))
    unique=[]
    for p in extra:
        if any(overlap_small(p['bbox'],q['bbox'])>=.65 for q in unique):continue
        unique.append(p)
    extra=unique;changed=True
    while changed:
        changed=False
        for i in range(len(extra)):
            for j in range(i+1,len(extra)):
                a,b=extra[i]['bbox'],extra[j]['bbox']
                gapx=max(0,max(a[0],b[0])-min(a[2],b[2]));gapy=max(0,max(a[1],b[1])-min(a[3],b[3]))
                if (min(area(a),area(b))<=200 and max(gapx,gapy)<=3) or overlap_small(a,b)>=.25:
                    extra[i]=dict(extra[i],bbox=[min(a[0],b[0]),min(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])],score=max(extra[i]['score'],extra[j]['score']))
                    extra.pop(j);changed=True;break
            if changed:break
    extra.sort(key=lambda p:(p['tier'],-p['score']))
    for p in extra:
        if not any(overlap_small(p['bbox'],q['bbox'])>=.5 for q in kept):kept.append(p)
    result=[]
    for i,p in enumerate(kept[:MAX_BOXES]):
        result.append(dict(id=f'candidate_{i}',bbox=list(p['bbox']),display_bbox=display_bounds(p['bbox']),area=p['area'],score=p['score'],branch='baseline' if 'tier' not in p else f'refinement_{p["tier"]}'))
    return result

def detect(rgb):
    if getattr(rgb,'shape',None)!=(256,256,3):raise ValueError('Expected one 256x256 RGB image, PS-equivalent smoothed input.')
    _,base=region_detect(rgb,profile=BASE_PROFILE)
    # The baseline and all branches use one common luminance closing definition.
    # A hardware implementation should share/reuse this work, not copy engines.
    branches=[]
    for options in REFINEMENT_PROFILES:
        _,debug=region_detect(rgb,profile=BASE_PROFILE|options)
        branches.append(debug['src_boxes'])
    return refine(base['src_boxes'],base['records'],branches)
