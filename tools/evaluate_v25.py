"""Recompute the candidate from actual firmware RGB, then compare human truth."""
import hashlib,json
from pathlib import Path
from review_pest import ROOT,samples
from pl_detector_model import smooth_rgb
from lesion_detector_v25 import detect
from evaluate_annotations import evaluate

out=ROOT/'build/algorithm_v25';out.mkdir(exist_ok=True)
dataset=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
annotation=max((ROOT/'annotation_tool/人工标注备份').glob('*.json'),key=lambda p:p.stat().st_mtime)
annotation_hash=hashlib.sha256(annotation.read_bytes()).hexdigest()
truth=json.loads(annotation.read_text(encoding='utf-8-sig'))
baseline=evaluate(dataset,truth);old_display=evaluate(dataset,truth,space='display')
predictions={}
for (i,_,raw),im in zip(samples(),dataset['images']):
    assert hashlib.sha256(raw.tobytes()).hexdigest()==im['pixel_sha256']
    predictions[im['id']]=detect(smooth_rgb(raw))
    print('sample',i+1,'boxes',len(predictions[im['id']]),flush=True)
source=evaluate(dataset,truth,predictions=predictions);display=evaluate(dataset,truth,predictions=predictions,space='display')
old_matches={(row['sample'],m['truth_index']) for row in baseline['images'] for m in row['matches']}
new_matches={(row['sample'],m['truth_index']) for row in source['images'] for m in row['matches']}
assert old_matches<=new_matches,'An originally matched lesion was lost'
old_display_matches={(row['sample'],m['truth_index']) for row in old_display['images'] for m in row['matches']}
new_display_matches={(row['sample'],m['truth_index']) for row in display['images'] for m in row['matches']}
assert old_display_matches<=new_display_matches,'An originally matched displayed box was lost'
assert sum(row['fp'] for row in source['images'][:12])==0,'Healthy development false positive introduced'
assert all(len(p)<=32 and all(all(type(v) is int for v in q['display_bbox']) for q in p) for p in predictions.values())
assert hashlib.sha256(annotation.read_bytes()).hexdigest()==annotation_hash,'Annotations must not change'
report=dict(version='v2.5 offline candidate',deployment='Not implemented or verified on PL',dataset_role='development',independent_test=False,
    annotation_file=str(annotation),annotation_sha256=annotation_hash,baseline_source=baseline,baseline_display=old_display,
    source=source,display=display,predictions=predictions,
    original_lesions_retained=len(old_matches&new_matches),newly_matched_lesions=sorted(new_matches-old_matches),
    source_sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ('tools/lesion_detector_v25.py','tools/precision_v25_core.py')})
(out/'candidate_verified.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('VERIFIED source:',source['tp'],source['fp'],source['fn'],'display:',display['tp'],display['fp'],display['fn'])
