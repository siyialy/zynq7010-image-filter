"""Sparse review locations: guard known background FPs and recovered edge spots.

These checks are not a complete lesion annotation set or an accuracy estimate.
Coordinates below are in the original 256-square sample, not photographed HDMI.
"""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
rows=json.loads((root/'build/pl_detector_v22/board_results.json').read_text())
def covered(n,x,y):
    px=40+x*15/16;py=y*15/16
    return any(b[0]<=px<=b[2] and b[1]<=py<=b[3] for b in rows[n-1]['boxes'])
for n,x,y in ((20,211,98),(20,215,146),(17,24,161),(17,38,145)):
    assert not covered(n,x,y),f'Background reappeared at {n}:{x},{y}'
for n,x,y in ((19,79,113),(19,111,165),(17,122,142),(14,150,155)):
    assert covered(n,x,y),f'Recovered review location lost at {n}:{x},{y}'
assert all(not r['boxes'] for r in rows[:12]),'New healthy development false positive'
print('PASS: four background locations excluded, four reviewed lesion locations retained, healthy development images unchanged')
print('Sparse checks only; sample 16 dark tip and unannotated lesions remain outside these assertions.')
