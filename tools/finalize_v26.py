"""Publish reproducible evidence only after every v2.6 gate passes."""
import hashlib,json,re
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/pl_detector_v26'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def log_pass(name,token):
 p=OUT/name;s=p.read_text(encoding='utf-8',errors='replace')
 assert token in s and 'Fatal:' not in s and 'FAIL:' not in s,(name,'No passing result')
 return sha(p)
evidence={}
evidence['fusion']=log_pass('sim_fusion.log','PASS: v25 fusion all 24')
evidence['engine']=log_pass('sim_full_pipeline.log','PASS: v26 full engine and fusion')
evidence['pool32']=log_pass('sim_pool32_pipeline.log','PASS: v25 pool32')
project=Path((OUT/'build_path.txt').read_text().strip())
timing=project/'detector_timing_final.rpt'
if not timing.exists():timing=project/'detector_timing.rpt'
s=timing.read_text();assert 'All user specified timing constraints are met.' in s
match=re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([\d.-]+)\s+[\d.-]+\s+\d+\s+\d+\s+([\d.-]+)',s,re.S)
assert match,'Cannot parse timing';wns,whs=map(float,match.groups());assert wns>=0 and whs>=0
staged=Path(str(project).replace('pl_detector_','pl_detector_src_'))
names=['image_rom_src.v','img_buf.v','video_pipeline.v','system_top.v','cdc_boxes.v','box_overlay.v','pl_pest_engine_v25.v','pl_candidate_fusion.v','pl_detector_v25.v']
sources={}
for name in names:
 p=ROOT/'src/rtl'/name;assert sha(p)==sha(staged/name),f'RTL changed after build: {name}';sources[str(p.relative_to(ROOT))]=sha(p)
arm=json.loads((ROOT/'build/pest_review/img_filter_app_v2_6.build.json').read_text(encoding='utf-8-sig'))
for name,h in arm['sources'].items():assert sha(ROOT/name)==h,f'PS changed after build: {name}'
elf=ROOT/'build/pest_review/img_filter_app_v2_6.elf';assert sha(elf)==arm['elf_sha256']
board=json.loads((OUT/'board_results.json').read_text());expected=json.loads((OUT/'python_results.json').read_text());assert board==expected
candidate=json.loads((ROOT/'build/algorithm_v26/candidate_verified.json').read_text(encoding='utf-8'))
assert sha(Path(candidate['annotation_file']))==candidate['annotation_sha256'],'Human annotations changed'
for name,h in candidate['source_sha256'].items():assert sha(ROOT/name)==h,f'Offline reference changed: {name}'
uart=ROOT/'build/pest_review/board_uart_v2_6.txt';assert 'detector errors = 0' in uart.read_text(encoding='utf-8-sig')
control=OUT/'control_uart.txt';ct=control.read_text(encoding='utf-8-sig')
assert 'restoring displayed sample 14 after benchmark' in ct and 'box overlay OFF' in ct and 'box overlay ON' in ct
assert 'display sample=14 result sample=14' in ct and 'detector errors = 0' in ct
max_detect=int(re.search(r'max detect time = (\d+) us',uart.read_text(encoding='utf-8-sig'))[1])
cached_ms=float(re.findall(r'whole sample work \(display \+ detect\): (\d+\.\d+) ms',ct)[-1])
shadow=OUT/'sample13_uart.txt';shadow_text=shadow.read_text(encoding='utf-8-sig')
assert 'sample 13/24' in shadow_text and 'boxes=1' in shadow_text and 'display sample=13 result sample=13' in shadow_text
screen_match=re.search(r'box0: screen \((\d+),(\d+)\)-\((\d+),(\d+)\) area (\d+)',shadow_text)
target=expected[12]['boxes'];assert len(target)==1
x0,y0,x1,y1,area=target[0]
# Existing UART prints the origin of the final 3x3 display pixel; RTL adds
# two screen pixels to its inclusive right/bottom extent (fusion TB checks it).
assert screen_match and list(map(int,screen_match.groups()))==[x0*3+160,y0*3,x1*3+160,y1*3,area]
report=dict(verified=True,version='2_6',time_utc=datetime.now(timezone.utc).isoformat(),project=str(project),
 bit_sha256=sha(Path('D:/fpga_build/bits/system_top_v2_6.bit')),elf_sha256=sha(elf),
 setup_wns_ns=wns,hold_whs_ns=whs,rtl_sources=sources,ps_sources=arm['sources'],
 simulation_sha256=evidence,board_uart_sha256=sha(uart),board_results_sha256=sha(OUT/'board_results.json'),
 control_uart_sha256=sha(control),sample13_uart_sha256=sha(shadow),max_detect_us=max_detect,cached_sample14_ms=cached_ms,
 development_metrics={space:{k:candidate[space][k] for k in ('tp','fp','fn','precision','recall')} for space in ('source','display')},
 independent_test=False,dataset_role='development')
(OUT/'release_verified.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('VERIFIED v2.6 release: RTL, setup/hold, PS/PL feature match and 24 board outputs; development set only')
