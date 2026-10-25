"""Visual audit of user annotations; never edits truth or firmware."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from evaluate_annotations import ROOT,evaluate,iou,intersection,area

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--annotations',type=Path,required=True)
args=parser.parse_args()
dataset=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
truth=json.loads(args.annotations.read_text(encoding='utf-8-sig'))
source=evaluate(dataset,truth);display=evaluate(dataset,truth,space='display')
out=ROOT/'annotation_tool/reports';out.mkdir(exist_ok=True)
try:font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23);small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
except OSError:font=small=ImageFont.load_default()
gt_by_id={r['id']:r for r in truth['images']};stats_by_n={r['sample']:r for r in source['images']}
board=json.loads((ROOT/'build/pl_detector_v24/board_results.json').read_text())
contact=Image.new('RGB',(1536,4*310),(246,248,243));cd=ImageDraw.Draw(contact)
issues=[];labels_total=accepted_unchanged=manual_total=0
no_overlap_fp=partial_fp=duplicate_fp=0
for im in dataset['images']:
    n=im['number'];row=gt_by_id[im['id']]
    assert [[b['display_bbox'][0],b['display_bbox'][1],b['display_bbox'][2]-1,b['display_bbox'][3]-1] for b in im['proposals']]==[b[:4] for b in board[n-1]['boxes']]
    if not row['reviewed']:continue
    stat=stats_by_n[n];gts=[a for a in row['annotations'] if a['category']=='lesion'];labels_total+=len(gts)
    raw=Image.open(ROOT/'annotation_tool'/im['image_url']).convert('RGB')
    left=raw.resize((768,768),Image.Resampling.NEAREST);right=left.copy();dl=ImageDraw.Draw(left);dr=ImageDraw.Draw(right)
    missed=set(stat['missed_truth_ids']);bad=set(stat['false_proposal_ids']);details=[]
    for j,a in enumerate(gts):
        b=a['bbox'];box=[b[0]*3,b[1]*3,b[2]*3-1,b[3]*3-1]
        dl.rectangle(box,outline='#f184ff' if a['id'] in missed else '#3cff8d',width=3)
        dl.text((box[0]+2,max(0,box[1]-23)),str(j+1),font=small,fill='#f184ff' if a['id'] in missed else '#3cff8d',stroke_width=1,stroke_fill='#152219')
        manual_total+=a['origin']=='manual'
        original=next((p for p in im['proposals'] if p['id']==a['origin']),None)
        accepted_unchanged+=bool(original and a['bbox']==original['bbox'])
        if a['id'] in missed:
            overlaps=[iou(b,p['bbox']) for p in im['proposals']]
            covered=sum(intersection(b,p['bbox'])>0 for p in im['proposals'])
            details.append(dict(kind='FN',truth_number=j+1,bbox=b,best_prediction_iou=max(overlaps,default=0),any_intersecting_prediction=bool(covered)))
    for j,p in enumerate(im['proposals']):
        b=p['bbox'];box=[b[0]*3,b[1]*3,b[2]*3-1,b[3]*3-1]
        dr.rectangle(box,outline='#ff594d' if p['id'] in bad else '#3cff8d',width=3)
        dr.text((box[0]+2,max(0,box[1]-23)),str(j+1),font=small,fill='#ff594d' if p['id'] in bad else '#3cff8d',stroke_width=1,stroke_fill='#152219')
        if p['id'] in bad:
            best=max((iou(b,a['bbox']) for a in gts),default=0)
            overlaps=sum(intersection(b,a['bbox'])>0 for a in gts)
            covered=[k+1 for k,a in enumerate(gts) if intersection(b,a['bbox'])/area(a['bbox'])>=.5]
            classification='duplicate_match' if best>=.5 else 'overlap_below_iou' if overlaps else 'no_truth_overlap'
            duplicate_fp+=classification=='duplicate_match';partial_fp+=classification=='overlap_below_iou';no_overlap_fp+=classification=='no_truth_overlap'
            details.append(dict(kind='FP',proposal_number=j+1,bbox=b,best_truth_iou=best,classification=classification,mostly_covered_truth_numbers=covered))
    if not gts and not im['proposals']:continue
    pair=Image.new('RGB',(1552,852),'#17261f');d=ImageDraw.Draw(pair)
    d.text((12,10),f'第 {n} 张 · 人工标注 {len(gts)} 个',font=font,fill='white')
    d.text((796,10),f'v2.4 候选 {len(im["proposals"])} 个 · TP {stat["tp"]} / FP {stat["fp"]} / FN {stat["fn"]}',font=font,fill='white')
    pair.paste(left,(0,45));pair.paste(right,(784,45))
    d.text((12,816),'左：紫色为漏检真值；绿色为已匹配真值。右：红色为未匹配预测，绿色为匹配预测。',font=small,fill='white')
    pair.save(out/f'sample_{n:02d}_truth_vs_prediction.png')
    k=n-13;x=(k%3)*512;y=(k//3)*310
    contact.paste(left.resize((256,256)),(x,y+35));contact.paste(right.resize((256,256)),(x+256,y+35))
    cd.text((x+6,y+5),f'{n}: TP {stat["tp"]}   FP {stat["fp"]}   FN {stat["fn"]}',font=small,fill='#1f4431')
    issues.append(dict(sample=n,truth_count=len(gts),prediction_count=len(im['proposals']),tp=stat['tp'],fp=stat['fp'],fn=stat['fn'],details=details))
contact.save(out/'all_localization_audit.jpg',quality=94)
audit=dict(annotation_file=str(args.annotations),annotation_sha256=hashlib.sha256(args.annotations.read_bytes()).hexdigest(),
    reviewed_images=source['reviewed_images'],lesions=labels_total,manual_origin_lesions=manual_total,
    accepted_unchanged_lesions=accepted_unchanged,source_metrics={k:v for k,v in source.items() if k!='images'},
    display_metrics={k:v for k,v in display.items() if k!='images'},false_prediction_types=dict(no_truth_overlap=no_overlap_fp,overlap_below_iou=partial_fp,duplicate_match=duplicate_fp),issues=issues)
(out/'annotation_audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 人工标注审查与改进顺序','',f'已核对 {source["reviewed_images"]} 张审核完成图片，共 {labels_total} 个病斑；人工新画 {manual_total} 个，接受后未改边界 {accepted_unchanged} 个。',
    '',f'源图候选区域：TP={source["tp"]}、FP={source["fp"]}、FN={source["fn"]}，病斑召回率 {source["recall"]*100:.2f}%，每图误框 {source["false_boxes_per_image"]:.3f}。',
    f'未匹配预测中，{no_overlap_fp} 个与真值完全不相交，{partial_fp} 个有交叠但 IoU 不足，{duplicate_fp} 个属于重复配对竞争；不能把全部 FP 都叫作背景误检。',
    '', '## 优先处理',
    '- 第 21 张：20 个真值、16 个预测，16 个都正确匹配；当前 16 框容量是明确上限，应评估扩大容量，并检查额外病斑是否已有候选。',
    '- 第 16、22、23 张：检查大候选合并、边界偏大/偏移及相邻病斑分离。',
    '- 第 14、17、18、20 张：按漏检坐标检查叶片掩膜、颜色/对比度、形态学和筛选规则。',
    '', '## 结果解释',
    f'- {accepted_unchanged} 个已匹配框的边界沿用你接受的算法候选，因此其源图平均 IoU 为 100%；不能把这个数字当作独立边界精度证明。',
    '- HDMI 红框含显示外扩边距，对小病斑 IoU 的影响明显，需和源候选框分开评估。',
    '- 现有 24 张仍是开发集，不能作为独立测试精度。标注原文件保持不变；本次没有改写检测规则或下载新程序。',
    '', '| 图片 | 真值 | 预测 | TP | FP | FN | 对照图 |','|---|---:|---:|---:|---:|---:|---|']
lines += [f'| {r["sample"]} | {r["truth_count"]} | {r["prediction_count"]} | {r["tp"]} | {r["fp"]} | {r["fn"]} | [查看](sample_{r["sample"]:02d}_truth_vs_prediction.png) |' for r in issues]
(out/'annotation_audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(f'Audit generated: reviewed={source["reviewed_images"]}, lesions={labels_total}, manual={manual_total}, accepted unchanged={accepted_unchanged}')
print('FP types:',audit['false_prediction_types'])
