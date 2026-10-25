"""Compare actual board-produced boxes with Python, without trusting labels."""
import json,re
from pathlib import Path

import argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--version',choices=['2_0','2_1','2_2','2_3','2_4','2_5','2_6'],default='2_6')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
log=(root/f'build/pest_review/board_uart_v{args.version}.txt').read_text(encoding='utf-8-sig')
expected=json.loads((root/('build/pl_detector_v26/python_results.json' if args.version=='2_6' else 'build/pl_detector_v25/python_results.json' if args.version=='2_5' else 'build/pl_detector_v23/python_results.json' if args.version in ('2_3','2_4','2_5','2_6') else 'build/pl_detector_v22/python_results.json' if args.version=='2_2' else 'build/pl_detector/python_results.json')).read_text())
assert 'detector errors = 0' in log,'Board reported a protocol or timeout error'
counts={int(n):int(c) for n,c in re.findall(r'^\s*(\d+) label=\w+ boxes=(\d+) ->',log,re.M)}
assert set(counts)==set(range(1,25)),f'Incomplete benchmark: {sorted(counts)}'
actual={i:[] for i in range(1,25)}
for n,k,x0,y0,x1,y1,area in re.findall(r'PL_BOX (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)',log):
    assert int(k)==len(actual[int(n)]),'Missing or reordered box readback'
    actual[int(n)].append(list(map(int,(x0,y0,x1,y1,area))))
for row in expected:
    n=row['sample'];assert counts[n]==len(row['boxes']),(n,counts[n],row['boxes'])
    assert actual[n]==[b[:5] for b in row['boxes']],(n,actual[n],row['boxes'])
out=[dict(sample=n,boxes=actual[n]) for n in range(1,25)]
destination=root/('build/pl_detector_v26' if args.version=='2_6' else 'build/pl_detector_v25' if args.version=='2_5' else 'build/pl_detector_v24' if args.version=='2_4' else 'build/pl_detector_v23' if args.version=='2_3' else 'build/pl_detector_v22' if args.version=='2_2' else 'build/pl_detector_v21' if args.version=='2_1' else 'build/pl_detector')
(destination/'board_results.json').write_text(json.dumps(out,indent=2))
print('PASS: all 24 board frames agree with Python in box count, coordinates, component area and order')
