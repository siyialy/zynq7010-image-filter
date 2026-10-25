"""Verify the generic shadow gate against the frozen v2.5 development baseline."""
import hashlib,json
from review_pest import ROOT,samples
from precision_v26_core import smooth_rgb
from lesion_detector_v26 import detect
from evaluate_annotations import evaluate

out=ROOT/'build/algorithm_v26';out.mkdir(exist_ok=True)
old=json.loads((ROOT/'build/algorithm_v25/candidate_verified.json').read_text(encoding='utf-8'))
dataset=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
annotation=ROOT/old['annotation_file'];truth=json.loads(annotation.read_text(encoding='utf-8-sig'))
annotation_hash=hashlib.sha256(annotation.read_bytes()).hexdigest();assert annotation_hash==old['annotation_sha256']
predictions={}
for (i,_,rgb),im in zip(samples(),dataset['images']):
    assert hashlib.sha256(rgb.tobytes()).hexdigest()==im['pixel_sha256']
    predictions[im['id']]=detect(smooth_rgb(rgb));print('v26 sample',i+1,len(predictions[im['id']]),flush=True)
source=evaluate(dataset,truth,predictions=predictions)
display=evaluate(dataset,truth,predictions=predictions,space='display')
for space,result in [('source',source),('display',display)]:
    before={(r['sample'],m['truth_index']) for r in old[space]['images'] for m in r['matches']}
    after={(r['sample'],m['truth_index']) for r in result['images'] for m in r['matches']}
    assert before<=after,f'Previously matched {space} lesion lost: {before-after}'
    assert all(a['fp']<=b['fp'] for a,b in zip(result['images'],old[space]['images'])),f'New {space} false positive on another image'
assert source['images'][12]['fp']==0,'Reported sample 13 shadow remains'
assert all(predictions[k]==old['predictions'][k] for k in predictions if k!='sample_13'),'Another image output changed'
assert predictions['sample_13']==[p for p in old['predictions']['sample_13'] if p['bbox']!=[126,164,139,178]],'Unexpected sample 13 output change'
assert all(r['fp']==0 for r in source['images'][:12]),'Healthy false positive introduced'
assert hashlib.sha256(annotation.read_bytes()).hexdigest()==annotation_hash
report=dict(version='v2.6 offline shadow fix',deployment='pending PL verification',dataset_role='development',independent_test=False,
    annotation_file=str(annotation),annotation_sha256=annotation_hash,source=source,display=display,predictions=predictions,
    baseline_source=old['source'],baseline_display=old['display'],
    source_sha256={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ('tools/lesion_detector_v26.py','tools/precision_v26_core.py','tools/lesion_detector_v25.py')})
(out/'candidate_verified.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS v26 source',source['tp'],source['fp'],source['fn'],'display',display['tp'],display['fp'],display['fn'])
