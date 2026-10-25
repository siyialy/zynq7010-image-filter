"""Develop global rules against reviewed development labels; detection never reads labels."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from review_pest import ROOT,samples
from pl_detector_v23_model import PROFILE
from precision_v25_experiment import detect,smooth_rgb
from evaluate_annotations import evaluate

OUT=ROOT/'build/algorithm_v25';OUT.mkdir(exist_ok=True)
DATA=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
ANNOTATION=max((ROOT/'annotation_tool/人工标注备份').glob('*.json'),key=lambda p:p.stat().st_mtime)
TRUTH=json.loads(ANNOTATION.read_text(encoding='utf-8-sig'))
RGB=[]
for (i,_,raw),im in zip(samples(),DATA['images']):
    assert hashlib.sha256(raw.tobytes()).hexdigest()==im['pixel_sha256']
    RGB.append(smooth_rgb(raw))

def experiment(name,extra):
    predictions={};details=[]
    for i,rgb in enumerate(RGB):
        options=PROFILE|extra;radius=options.pop('radius',15)
        _,debug=detect(rgb,radius=radius,profile=options)
        source=debug['src_boxes']
        predictions[DATA['images'][i]['id']]=[dict(id=f'pred_{i+1}_{j}',**p) for j,p in enumerate(source)]
        details.append(dict(sample=i+1,records=debug['records']))
    src=evaluate(DATA,TRUTH,predictions=predictions);disp=evaluate(DATA,TRUTH,space='display',predictions=predictions)
    row=dict(name=name,profile=extra,source=src,display=disp,predictions=predictions,details=details,
             healthy_false_boxes=sum(r['fp'] for r in src['images'][:12]),annotation_sha256=hashlib.sha256(ANNOTATION.read_bytes()).hexdigest(),independent_test=False)
    (OUT/f'{name}.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,'TP',src['tp'],'FP',src['fp'],'FN',src['fn'],'healthy_FP',row['healthy_false_boxes'],'display_TP',disp['tp'],flush=True)
    return row

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--group',default='leaf');args=parser.parse_args()
    profiles={
        'edge':{
            'brown_strict3':{'brown_leaf':True,'strict_candidate':True,'extra_erode':3,'max_boxes':32},
            'brown_strict5':{'brown_leaf':True,'strict_candidate':True,'extra_erode':5,'max_boxes':32},
            'brown_strict7':{'brown_leaf':True,'strict_candidate':True,'extra_erode':7,'max_boxes':32},
            'leaf12_strict5':{'leaf_chroma':12,'strict_candidate':True,'extra_erode':5,'max_boxes':32},
        },
        'erode':{
            'strict_erode3':{'strict_candidate':True,'extra_erode':3,'max_boxes':32},
            'strict_erode5':{'strict_candidate':True,'extra_erode':5,'max_boxes':32},
            'strict_erode7':{'strict_candidate':True,'extra_erode':7,'max_boxes':32},
            'erode3':{'extra_erode':3,'max_boxes':32},
            'erode5':{'extra_erode':5,'max_boxes':32},
        },
        'strict':{
            'strict15':{'strict_candidate':True,'max_boxes':32},
            'strict9':{'strict_candidate':True,'max_boxes':32,'radius':9},
            'strict7':{'strict_candidate':True,'max_boxes':32,'radius':7},
            'strict_dark15':{'strict_candidate':True,'strict_dark':True,'max_boxes':32},
            'strict_dark7':{'strict_candidate':True,'strict_dark':True,'max_boxes':32,'radius':7},
            'strong_brown15':{'bg':90,'dark_olive':False,'max_boxes':32},
        },
        'scale':{f'radius{radius}':{'radius':radius,'max_boxes':32} for radius in (3,5,7,9,11)},
        'leaf':{
            'baseline':{},'capacity32':{'max_boxes':32},
            'leaf12':{'max_boxes':32,'leaf_chroma':12},
            'leaf16':{'max_boxes':32,'leaf_chroma':16},
            'brown_leaf':{'max_boxes':32,'brown_leaf':True},
            'leaf12_brown':{'max_boxes':32,'leaf_chroma':12,'brown_leaf':True},
        }
    }
    for name,profile in profiles[args.group].items():experiment(name,profile)
