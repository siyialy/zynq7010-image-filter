"""Synthetic evaluation checks; fixtures are never delivered as manual truth."""
import copy,itertools,json,random
from evaluate_annotations import evaluate,match_boxes,iou

def image(n,pred):return dict(id=f'sample_{n}',number=n,width=256,height=256,pixel_sha256=str(n),proposals=[dict(id=f'p{n}_{i}',bbox=b,display_bbox=[40+b[0]*15/16,b[1]*15/16,40+b[2]*15/16,b[3]*15/16]) for i,b in enumerate(pred)])
def row(im,annotations,reviewed=True):return dict(id=im['id'],width=256,height=256,pixel_sha256=im['pixel_sha256'],reviewed=reviewed,empty_confirmed=not any(a['category']=='lesion' for a in annotations),annotations=annotations,proposal_decisions={p['id']:'rejected' for p in im['proposals']})
def ann(i,kind,b):return dict(id=i,category=kind,bbox=b,origin='manual')
images=[image(1,[[0,0,10,10],[0,0,10,10],[30,30,40,40]]),image(2,[[50,50,60,60],[70,70,80,80]]),image(3,[[0,0,10,10]])]
dataset=dict(dataset_id='synthetic-only',images=images)
payload=dict(schema_version=1,dataset_id='synthetic-only',dataset_role='development',bbox_format='xyxy_half_open',images=[
 row(images[0],[ann('a','lesion',[0,0,10,10]),ann('b','lesion',[100,100,110,110])]),
 row(images[1],[ann('c','uncertain',[50,50,60,60]),ann('d','background',[70,70,80,80])]),row(images[2],[],False)])
result=evaluate(dataset,payload)
assert (result['tp'],result['fp'],result['fn'])==(1,3,1),result
assert result['reviewed_images']==2 and result['skipped_images']==1
assert result['recall']==.5 and result['false_boxes_per_image']==1.5 and result['ignored_predictions']==1
assert result['images'][1]['background_fp']==1
assert len(match_boxes([[0,0,1,1]],[[0,0,1,1]],.5))==1
assert evaluate(dataset,payload,space='display')['tp']==1
saved=copy.deepcopy(payload)
empty_predictions={im['id']:[] for im in images}
empty=evaluate(dataset,payload,predictions=empty_predictions)
assert (empty['tp'],empty['fp'],empty['fn'])==(0,0,2)
assert payload==saved,'Evaluating new predictions must not modify human truth/review decisions'
try:evaluate(dataset,payload,predictions={});raise AssertionError('Wrong prediction image set accepted')
except ValueError:pass
bad=copy.deepcopy(payload);bad['images'][0]['pixel_sha256']='wrong'
try:evaluate(dataset,bad);raise AssertionError('Wrong image accepted')
except ValueError:pass
# Cross-check the assignment against brute force on small random instances.
rng=random.Random(24)
for _ in range(60):
 pred=[[x,y,x+w,y+h] for x,y,w,h in [(rng.randrange(8),rng.randrange(8),rng.randrange(1,8),rng.randrange(1,8)) for _ in range(4)]]
 truth=[[x,y,x+w,y+h] for x,y,w,h in [(rng.randrange(8),rng.randrange(8),rng.randrange(1,8),rng.randrange(1,8)) for _ in range(4)]]
 actual=match_boxes(pred,truth,.2);key=(len(actual),round(sum(p[2] for p in actual),9));best=(0,0)
 for permutation in itertools.permutations(range(4)):
  scores=[iou(pred[i],truth[j]) for i,j in enumerate(permutation) if iou(pred[i],truth[j])>=.2]
  best=max(best,(len(scores),round(sum(scores),9)))
 assert key==best,(key,best)
print('PASS: one-to-one maximum matching, duplicate FP, missed lesions, unreviewed exclusion, uncertainty exclusion, background FP, coordinate identity and display projection.')
