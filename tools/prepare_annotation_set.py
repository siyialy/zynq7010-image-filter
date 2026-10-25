"""Export exact embedded RGB samples and source-coordinate PL proposals.

Proposals are never ground truth. No existing annotations or browser saves are
read or overwritten by this exporter.
"""
import hashlib,json
from pathlib import Path
from PIL import Image
from review_pest import samples,ROOT
from pl_detector_v23_model import detect,smooth_rgb

out=ROOT/'annotation_tool';(out/'images').mkdir(parents=True,exist_ok=True)
header_sha=hashlib.sha256((ROOT/'ps_app/pv_samples.h').read_bytes()).hexdigest()
board=json.loads((ROOT/'build/pl_detector_v24/board_results.json').read_text())
def mapped(src):
    x0,y0,x1,y1=src
    return [max(40,(x0*15+15)//16+38),max(0,(y0*15+15)//16-2),
            min(279,((x1+1)*15+15)//16+41),min(239,((y1+1)*15+15)//16+1)]
rows=[]
for i,name,rgb in samples():
    n=i+1;filename=f'sample_{n:02d}.png'
    Image.fromarray(rgb).save(out/'images'/filename)
    boxes,debug=detect(smooth_rgb(rgb))
    assert [b[:5] for b in boxes]==board[i]['boxes'],f'Golden/board mismatch {n}'
    proposals=[]
    for j,b in enumerate(boxes):
        matches=[r for r in debug['records'] if mapped(r['src'])==b[:4] and r['area']==b[4] and r['score']==b[5]]
        assert len(matches)==1,(n,j,matches)
        x0,y0,x1,y1=matches[0]['src']
        proposals.append(dict(id=f'pl_{n:02d}_{j:02d}',bbox=[x0,y0,x1+1,y1+1],
                              display_bbox=[b[0],b[1],b[2]+1,b[3]+1],area=b[4],score=b[5]))
    rows.append(dict(id=f'sample_{n:02d}',number=n,filename=filename,original_name=name,
                     image_url='images/'+filename,width=256,height=256,
                     pixel_sha256=hashlib.sha256(rgb.tobytes()).hexdigest(),proposals=proposals))
dataset=dict(schema_version=1,dataset_id=header_sha,dataset_role='development',
             bbox_format='xyxy_half_open',proposal_source='v2.4 PL (same algorithm as v2.3)',
             images=rows)
(out/'dataset.json').write_text(json.dumps(dataset,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'dataset.js').write_text('window.ANNOTATION_DATASET='+json.dumps(dataset,ensure_ascii=False)+';\n',encoding='utf-8')
print(f'Prepared {len(rows)} unchanged RGB images and {sum(len(r["proposals"]) for r in rows)} unreviewed proposals; no truth labels assigned.')
