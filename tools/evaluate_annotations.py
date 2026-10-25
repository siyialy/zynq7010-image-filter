"""Evaluate only manually reviewed development images; never promote proposals to truth."""
import argparse,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def area(b):return max(0,b[2]-b[0])*max(0,b[3]-b[1])
def intersection(a,b):return max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
def iou(a,b):
    value=intersection(a,b);den=area(a)+area(b)-value
    return value/den if den else 0
def match_boxes(pred,truth,threshold):
    """Maximum-cardinality one-to-one assignment; maximize IoU among equal counts."""
    n=max(len(pred),len(truth))
    if not n:return []
    overlaps=[[iou(a,b) for b in truth] for a in pred]
    cost=[[0.0]*n for _ in range(n)]
    for i in range(len(pred)):
        for j in range(len(truth)):
            if overlaps[i][j]>=threshold:cost[i][j]=-1-overlaps[i][j]/(n+1)
    u=[0.0]*(n+1);v=[0.0]*(n+1);p=[0]*(n+1);way=[0]*(n+1)
    for i in range(1,n+1):
        p[0]=i;j0=0;minimum=[float('inf')]*(n+1);used=[False]*(n+1)
        while True:
            used[j0]=True;i0=p[j0];delta=float('inf');j1=0
            for j in range(1,n+1):
                if used[j]:continue
                current=cost[i0-1][j-1]-u[i0]-v[j]
                if current<minimum[j]:minimum[j]=current;way[j]=j0
                if minimum[j]<delta:delta=minimum[j];j1=j
            for j in range(n+1):
                if used[j]:u[p[j]]+=delta;v[j]-=delta
                else:minimum[j]-=delta
            j0=j1
            if p[j0]==0:break
        while True:
            j1=way[j0];p[j0]=p[j1];j0=j1
            if j0==0:break
    return [(p[j]-1,j-1,overlaps[p[j]-1][j-1]) for j in range(1,n+1)
            if p[j] and p[j]<=len(pred) and j<=len(truth) and overlaps[p[j]-1][j-1]>=threshold]

def validate(dataset,payload):
    if payload.get('schema_version')!=1 or payload.get('dataset_id')!=dataset['dataset_id'] or payload.get('dataset_role')!='development' or payload.get('bbox_format')!='xyxy_half_open':
        raise ValueError('图片集或坐标格式不匹配。请使用本工具导出的标注 JSON。')
    rows=payload.get('images',[])
    if len(rows)!=len(dataset['images']) or len({r.get('id') for r in rows})!=len(rows):raise ValueError('图片条目缺失或重复。')
    known={r['id']:r for r in dataset['images']}
    for row in rows:
        im=known.get(row.get('id'))
        if not im or row.get('pixel_sha256')!=im['pixel_sha256'] or row.get('width')!=im['width'] or row.get('height')!=im['height']:raise ValueError('原图校验值或尺寸不匹配。')
        if type(row.get('reviewed')) is not bool:raise ValueError('缺少人工审核状态。')
        ids=set()
        for a in row.get('annotations',[]):
            b=a.get('bbox',[])
            if len(b)!=4 or any(type(x) is not int for x in b) or min(b)<0 or b[2]>im['width'] or b[3]>im['height'] or area(b)<=0 or b[2]<=b[0] or b[3]<=b[1]:raise ValueError('存在无效坐标。')
            if a.get('id') in ids or a.get('category') not in ('lesion','uncertain','background'):raise ValueError('标注编号重复或类别无效。')
            ids.add(a.get('id'))
        decisions=row.get('proposal_decisions',{})
        if row['reviewed'] and (any(decisions.get(p['id']) not in ('accepted','rejected') for p in im['proposals']) or
            (not any(a['category']=='lesion' for a in row['annotations']) and row.get('empty_confirmed') is not True)):
            raise ValueError('已审核图片仍有待确认候选，或缺少无病斑框确认。')
    return {r['id']:r for r in rows}

def evaluate(dataset,payload,threshold=.5,space='source',predictions=None):
    rows=validate(dataset,payload);results=[];total_iou=0;small_tp=small_gt=0
    if predictions is not None and set(predictions)!={im['id'] for im in dataset['images']}:
        raise ValueError('预测图片集合与人工标注集不匹配。')
    transform=lambda b:[40+b[0]*15/16,b[1]*15/16,40+b[2]*15/16,b[3]*15/16] if space=='display' else b
    for im in dataset['images']:
        row=rows[im['id']]
        if not row['reviewed']:continue
        gt_source=[a['bbox'] for a in row['annotations'] if a['category']=='lesion']
        truth=[transform(b) for b in gt_source]
        uncertain=[transform(a['bbox']) for a in row['annotations'] if a['category']=='uncertain']
        background=[transform(a['bbox']) for a in row['annotations'] if a['category']=='background']
        proposal_rows=im['proposals'] if predictions is None else predictions[im['id']]
        pred=[p['display_bbox'] if space=='display' else p['bbox'] for p in proposal_rows]
        matched=match_boxes(pred,truth,threshold);matched_p={m[0] for m in matched};matched_g={m[1] for m in matched}
        unmatched=[j for j in range(len(pred)) if j not in matched_p]
        ignored=[j for j in unmatched if any(intersection(pred[j],b)/area(pred[j])>=.5 for b in uncertain)]
        false_p=[j for j in unmatched if j not in ignored]
        small={j for j,b in enumerate(gt_source) if area(b)<64};small_gt+=len(small);small_tp+=len(small&matched_g)
        total_iou+=sum(m[2] for m in matched)
        results.append(dict(sample=im['number'],tp=len(matched),fp=len(false_p),fn=len(truth)-len(matched),
            ignored_predictions=len(ignored),background_fp=sum(any(intersection(pred[j],b)/area(pred[j])>=.5 for b in background) for j in false_p),
            missed_truth_ids=[a['id'] for j,a in enumerate([a for a in row['annotations'] if a['category']=='lesion']) if j not in matched_g],
            false_proposal_ids=[proposal_rows[j]['id'] for j in false_p],
            matches=[dict(proposal_id=proposal_rows[i]['id'],truth_index=j,iou=score) for i,j,score in matched]))
    tp=sum(r['tp'] for r in results);fp=sum(r['fp'] for r in results);fn=sum(r['fn'] for r in results)
    return dict(box_space=space,iou_threshold=threshold,reviewed_images=len(results),skipped_images=len(rows)-len(results),
        tp=tp,fp=fp,fn=fn,recall=tp/(tp+fn) if tp+fn else None,
        precision=tp/(tp+fp) if tp+fp else None,false_boxes_per_image=fp/len(results) if results else None,
        matched_mean_iou=total_iou/tp if tp else None,small_lesion_area_limit=64,
        small_lesion_recall=small_tp/small_gt if small_gt else None,
        ignored_predictions=sum(r['ignored_predictions'] for r in results),images=results)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--annotations',type=Path,required=True)
    parser.add_argument('--iou',type=float,default=.5)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'annotation_tool/reports')
    args=parser.parse_args()
    if not 0<args.iou<=1:parser.error('IoU 必须在 0 到 1 之间。')
    try:
        dataset=json.loads((ROOT/'annotation_tool/dataset.json').read_text(encoding='utf-8'))
        annotations=json.loads(args.annotations.read_text(encoding='utf-8-sig'))
        source=evaluate(dataset,annotations,args.iou);display=evaluate(dataset,annotations,args.iou,'display')
        if not source['reviewed_images']:raise ValueError('尚无人工审核完成的图片。请先在标注工具中完成至少一张，再导出。')
    except (ValueError,KeyError,TypeError) as e:parser.exit(1,str(e)+'\n')
    args.output_dir.mkdir(parents=True,exist_ok=True)
    report=dict(dataset_role='development',independent_test=False,annotation_file=str(args.annotations),
        source_component_metrics=source,display_frame_metrics=display,
        note='仅计算已人工审核图片。候选并非真值；背景预测仍计误框。不确定区域内的未匹配预测单独忽略并报告。')
    path=args.output_dir/'evaluation.json';path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    def pct(x):return '不适用' if x is None else f'{x*100:.2f}%'
    lines=['# 病斑定位开发集评估','',f'已审核 {source["reviewed_images"]} 张；跳过未审核 {source["skipped_images"]} 张。IoU 门限 {args.iou}。',
        '', '| 范围 | 召回率 | 每图误框 | 已匹配框平均 IoU |','|---|---:|---:|---:|']
    for name,r in [('源图候选区域',source),('HDMI 显示框投影',display)]:lines.append(f'| {name} | {pct(r["recall"])} | {r["false_boxes_per_image"]:.3f} | {pct(r["matched_mean_iou"])} |')
    lines+=['','这 24 张已用于算法开发，不是独立测试集。源图候选区域不含显示外扩边距，HDMI 投影指标包含实际显示框边距。',
        '不确定区域内被忽略的预测数量见 JSON；背景 / 非病斑区域不会被忽略。','', '| 图片 | 找到病斑 TP | 误框 FP | 漏检 FN |','|---|---:|---:|---:|']
    lines += [f'| {r["sample"]} | {r["tp"]} | {r["fp"]} | {r["fn"]} |' for r in source['images']]
    (args.output_dir/'evaluation.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(f'已审核 {source["reviewed_images"]} 张；源图病斑召回 {pct(source["recall"])}，每图误框 {source["false_boxes_per_image"]:.3f}。')
    print('报告：'+str(path));print('说明：开发集结果，不代表独立测试精度。')
