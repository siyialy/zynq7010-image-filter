"""v2.6 shadow rejection; image content only, no sample numbers or labels."""
from pl_detector_v23_model import PROFILE as BASE_PROFILE
from precision_v26_core import detect as region_detect
from lesion_detector_v25 import refine,REFINEMENT_PROFILES,display_bounds

def detect(rgb):
    if getattr(rgb,'shape',None)!=(256,256,3):raise ValueError('Expected 256x256 smoothed RGB')
    profile=BASE_PROFILE|dict(reject_olive_shadow=True)
    _,base=region_detect(rgb,profile=profile)
    branches=[region_detect(rgb,profile=profile|options)[1]['src_boxes'] for options in REFINEMENT_PROFILES]
    return refine(base['src_boxes'],base['records'],branches)
