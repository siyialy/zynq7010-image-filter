(()=>{
 'use strict';
 const D=window.ANNOTATION_DATASET,M=window.AnnotationModel,$=id=>document.getElementById(id);
 const key='fpga-leaf-truth:'+D.dataset_id,canvas=$('canvas'),ctx=canvas.getContext('2d');
 const colors={lesion:'#28e67a',uncertain:'#dc91ff',background:'#6bb9ff'},names={lesion:'病斑',uncertain:'不确定',background:'背景 / 非病斑'};
 const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let state=M.blank(D),index=13,selection=null,mode='select',drag=null,history=[],image=null,imageToken=0,noteHistory=false;
 let persistence=true,saveTimer;
 const im=()=>D.images[index],row=()=>state.images[im().id];
 const uid=()=>('a_'+(globalThis.crypto?.randomUUID?.()||Date.now().toString(36)+'_'+Math.random().toString(36).slice(2)));
 function message(text,error=false){$('notice').textContent=text;$('notice').classList.toggle('error',error);}
 try{const saved=localStorage.getItem(key);if(saved){state=M.restore(D,JSON.parse(saved));message('已恢复本浏览器中的标注草稿。请定期导出 JSON 备份。');}}catch(e){persistence=false;message('未能恢复本地草稿：'+e.message+' 请使用导入 / 导出保存进度。',true);}
 function save(){
   try{localStorage.setItem(key,JSON.stringify(M.exportState(D,state)));persistence=true;$('saveState').textContent='已保存到本浏览器 · 请定期导出 JSON';}
   catch(e){persistence=false;$('saveState').textContent='浏览器无法自动保存，请立即导出 JSON';message('浏览器存储不可用，当前修改仍在页面内，请导出备份。',true);}
 }
 function snapshot(){history.push(M.copy(state));if(history.length>40)history.shift();}
 function touch(){row().reviewed=false;row().empty_confirmed=false;}
 function change(fn){snapshot();fn();touch();save();render();}
 function annotations(){return row().annotations;}
 function current(){return selection?.type==='truth'?annotations().find(a=>a.id===selection.id):im().proposals.find(a=>a.id===selection?.id);}
 function boxText(a){const [x,y,x1,y1]=a.bbox;return `位置 (${x}, ${y}) · ${x1-x}×${y1-y} 像素`;}
 function render(){
   const r=row(),meta=im(),pending=M.pending(meta,r),done=D.images.filter(x=>state.images[x.id].reviewed).length;
   $('progress').textContent=`审核完成 ${done} / ${D.images.length}`;
   $('sampleTitle').textContent=`第 ${meta.number} 张`;
   $('sampleMeta').textContent=`原始 RGB · ${meta.width}×${meta.height} · ${r.reviewed?'已完成审核':'待人工审核'}`;
   $('sampleList').innerHTML=D.images.map((m,i)=>`<button data-sample="${i}" class="${i===index?'active':''}" aria-label="第 ${m.number} 张"><img src="${esc(m.image_url)}" alt=""><span>${String(m.number).padStart(2,'0')}<span class="sample-state ${state.images[m.id].reviewed?'done':''}">${state.images[m.id].reviewed?' · 完成':' · 待审'}</span></span></button>`).join('');
   $('previous').disabled=index===0;$('next').disabled=index===D.images.length-1;$('undo').disabled=!history.length;
   $('selectMode').classList.toggle('active',mode==='select');$('drawMode').classList.toggle('active',mode==='draw');canvas.classList.toggle('draw',mode==='draw');
   $('truthTitle').textContent=`人工标注 · ${annotations().filter(a=>a.category==='lesion').length} 个病斑`;
   $('truthList').innerHTML=annotations().map((a,i)=>`<div class="entry"><button class="pick" data-truth="${esc(a.id)}">${i+1}. ${names[a.category]}<small>${boxText(a)}</small></button><button data-remove="${esc(a.id)}" aria-label="删除人工框 ${i+1}">删除</button></div>`).join('')||'<div class="empty">尚无人工标注，候选框不计入这里。</div>';
   $('proposalTitle').textContent=`待确认候选 · ${pending.length}`;
   $('proposalList').innerHTML=pending.map((p,i)=>`<div class="entry"><button class="pick" data-proposal="${esc(p.id)}">候选 ${im().proposals.indexOf(p)+1}<small>${boxText(p)}</small></button><button data-accept="${esc(p.id)}">接受</button><button data-reject="${esc(p.id)}">排除</button></div>`).join('')||'<div class="empty">无待确认候选。仍需检查算法漏掉的区域。</div>';
   const rejected=meta.proposals.filter(p=>r.proposal_decisions[p.id]==='rejected');$('rejectedTitle').textContent=`已排除候选 · ${rejected.length}`;
   $('rejectedList').innerHTML=rejected.map(p=>`<div class="entry"><span>${esc(p.id)}</span><button data-restore="${esc(p.id)}">撤回排除</button></div>`).join('');
   if(document.activeElement!==$('notes'))$('notes').value=r.notes;
   $('emptyLabel').hidden=annotations().some(a=>a.category==='lesion');$('confirmEmpty').checked=r.empty_confirmed;
   $('review').textContent=r.reviewed?'已审核完成（修改后需重新确认）':'标记本张审核完成';$('review').disabled=r.reviewed;
   $('saveState').textContent=persistence?'浏览器草稿自动保存 · 导出 JSON 可跨浏览器恢复':'请导出 JSON 保存当前修改';
   const a=current();
   if(!a){selection=null;$('selection').innerHTML='<div class="empty">点击框可查看；点“新增框”后在图片上拖出病斑范围。</div>';}
   else if(selection.type==='proposal')$('selection').innerHTML=`<div class="selected-info"><strong>算法候选 · 尚未确认</strong><br>${boxText(a)}</div><div class="row"><button data-accept="${esc(a.id)}">接受为病斑</button><button data-uncertain="${esc(a.id)}">不确定</button><button data-background="${esc(a.id)}">背景</button><button data-reject="${esc(a.id)}">排除</button></div><p class="muted">背景区域里的算法框仍计为误框。不确定区域单独记录，不直接当作病斑或健康。</p>`;
   else $('selection').innerHTML=`<div class="selected-info"><strong>${names[a.category]} · 人工标注</strong><br>${boxText(a)}<br>可拖动框体或四角调整。</div><div class="row">${M.categories.map(c=>`<button data-category="${c}" class="${c===a.category?'active':''}">${names[c]}</button>`).join('')}</div><div class="coords">${[['X',a.bbox[0]],['Y',a.bbox[1]],['宽',a.bbox[2]-a.bbox[0]],['高',a.bbox[3]-a.bbox[1]]].map(([name,value],i)=>`<label>${name}<input id="edit${i}" type="number" min="${i<2?0:1}" max="256" value="${value}"></label>`).join('')}</div><button data-apply-box="1">应用精确坐标</button>`;
   draw();
 }
 function load(){const token=++imageToken;image=null;$('loading').hidden=false;const img=new Image();img.onload=()=>{if(token!==imageToken)return;image=img;$('loading').hidden=true;draw();};img.onerror=()=>{if(token===imageToken){$('loading').textContent='原图加载失败，请从完整文件夹打开工具。';}};img.src=im().image_url;}
 function rect(a,color,dashed=false,label=''){
   const b=a.bbox.map(v=>v*4);ctx.strokeStyle=color;ctx.lineWidth=selection?.id===a.id?3:2;ctx.setLineDash(dashed?[8,5]:[]);ctx.strokeRect(b[0],b[1],b[2]-b[0],b[3]-b[1]);ctx.setLineDash([]);
   if(label){ctx.font='bold 16px sans-serif';ctx.fillStyle=color;ctx.fillText(label,b[0]+3,Math.max(18,b[1]-5));}
   if(selection?.type==='truth'&&selection.id===a.id){for(const [x,y] of [[b[0],b[1]],[b[2],b[1]],[b[0],b[3]],[b[2],b[3]]]){ctx.fillStyle=color;ctx.fillRect(x-5,y-5,10,10);ctx.strokeStyle='#173026';ctx.strokeRect(x-5,y-5,10,10);}}
 }
 function draw(){ctx.clearRect(0,0,1024,1024);if(image){ctx.imageSmoothingEnabled=false;ctx.drawImage(image,0,0,1024,1024);}if($('showProposals').checked)M.pending(im(),row()).forEach((a,i)=>rect(a,'#ffbc52',true,'候选'+(im().proposals.indexOf(a)+1)));annotations().forEach((a,i)=>rect(a,colors[a.category],false,String(i+1)));if(drag?.type==='draw'&&drag.box)rect({bbox:drag.box,id:'preview'},colors[$('drawCategory').value]);}
 function goto(i){if(drag)cancelDrag();index=Math.max(0,Math.min(D.images.length-1,i));selection=null;noteHistory=false;$('zoom').value='1';canvas.style.width='100%';canvas.style.height='100%';$('canvasViewport').scrollLeft=0;$('canvasViewport').scrollTop=0;render();load();$('sampleList').querySelector?.('[data-sample="'+index+'"]')?.scrollIntoView({block:'nearest'});}
 function accept(id,category='lesion'){const p=im().proposals.find(p=>p.id===id);if(!p||row().proposal_decisions[id])return;change(()=>{const a={id:uid(),bbox:[...p.bbox],category,origin:id};annotations().push(a);row().proposal_decisions[id]='accepted';selection={type:'truth',id:a.id};});message('已转成人工标注，请检查框边界，确认整张图片的其他位置。');}
 function reject(id){change(()=>{row().proposal_decisions[id]='rejected';selection=null;});}
 function remove(id){change(()=>{const a=annotations().find(a=>a.id===id);if(a&&a.origin!=='manual')row().proposal_decisions[a.origin]='rejected';row().annotations=annotations().filter(a=>a.id!==id);selection=null;});}
 function undo(){if(drag){cancelDrag();return;}if(!history.length)return;state=history.pop();selection=null;save();render();message('已撤销最近一次标注操作。');}
 document.addEventListener('click',e=>{
   const b=e.target.closest('button');if(!b)return;
   if(b.dataset.sample!==undefined)goto(Number(b.dataset.sample));
   else if(b.dataset.truth){selection={type:'truth',id:b.dataset.truth};mode='select';render();}
   else if(b.dataset.proposal){selection={type:'proposal',id:b.dataset.proposal};mode='select';render();}
   else if(b.dataset.accept)accept(b.dataset.accept);
   else if(b.dataset.uncertain)accept(b.dataset.uncertain,'uncertain');
   else if(b.dataset.background)accept(b.dataset.background,'background');
   else if(b.dataset.reject)reject(b.dataset.reject);
   else if(b.dataset.restore)change(()=>{delete row().proposal_decisions[b.dataset.restore];});
   else if(b.dataset.applyBox&&selection?.type==='truth'){const values=[0,1,2,3].map(i=>Number($('edit'+i).value));const [x,y,w,h]=values;if(!values.every(Number.isInteger)||x<0||y<0||w<1||h<1||x+w>256||y+h>256){message('坐标需为整数，框必须完整位于 256×256 原图内。',true);return;}change(()=>{current().bbox=[x,y,x+w,y+h];});}
   else if(b.dataset.remove)remove(b.dataset.remove);
   else if(b.dataset.category&&selection?.type==='truth')change(()=>{current().category=b.dataset.category;});
 });
 $('previous').onclick=()=>goto(index-1);$('next').onclick=()=>goto(index+1);
 $('selectMode').onclick=()=>{mode='select';render();};$('drawMode').onclick=()=>{mode='draw';selection=null;render();};$('undo').onclick=undo;$('showProposals').onchange=draw;
 $('zoom').onchange=()=>{const z=Number($('zoom').value),v=$('canvasViewport'),a=current();canvas.style.width=(z*100)+'%';canvas.style.height=(z*100)+'%';const b=a?.bbox||[0,0,256,256];v.scrollLeft=(b[0]+b[2])/512*v.scrollWidth-v.clientWidth/2;v.scrollTop=(b[1]+b[3])/512*v.scrollHeight-v.clientHeight/2;};
 function point(e){const r=canvas.getBoundingClientRect();return [Math.max(0,Math.min(256,Math.round((e.clientX-r.left)*256/r.width))),Math.max(0,Math.min(256,Math.round((e.clientY-r.top)*256/r.height)))];}
 function contains(a,p){return p[0]>=a.bbox[0]&&p[0]<=a.bbox[2]&&p[1]>=a.bbox[1]&&p[1]<=a.bbox[3];}
 canvas.onpointerdown=e=>{
   if(e.button!==0||!image)return;e.preventDefault();canvas.focus();const p=point(e);canvas.setPointerCapture(e.pointerId);
   if(mode==='draw'){drag={type:'draw',start:p,box:[...p,...p]};return;}
   const selected=selection?.type==='truth'?current():null;
   if(selected&&!e.altKey){const b=selected.bbox,corners=[[b[0],b[1]],[b[2],b[1]],[b[0],b[3]],[b[2],b[3]]],radius=9*256/canvas.getBoundingClientRect().width;const distances=corners.map(c=>Math.hypot(c[0]-p[0],c[1]-p[1])),nearest=Math.min(...distances),corner=nearest<=radius?distances.indexOf(nearest):-1;if(corner>=0){drag={type:'resize',corner,start:p,box:[...b],before:M.copy(state),id:selected.id};return;}}
   const a=[...annotations()].reverse().find(a=>contains(a,p));
   if(a){selection={type:'truth',id:a.id};drag={type:'move',start:p,box:[...a.bbox],before:M.copy(state),id:a.id};render();return;}
   const candidate=$('showProposals').checked?[...M.pending(im(),row())].reverse().find(a=>contains(a,p)):null;selection=candidate?{type:'proposal',id:candidate.id}:null;render();
 };
 canvas.onpointermove=e=>{
   if(!drag)return;const p=point(e),b=drag.box;
   if(drag.type==='draw'){drag.box=[Math.min(drag.start[0],p[0]),Math.min(drag.start[1],p[1]),Math.max(drag.start[0],p[0]),Math.max(drag.start[1],p[1])];draw();return;}
   const a=annotations().find(a=>a.id===drag.id);if(!a)return;
   if(drag.type==='move'){let dx=p[0]-drag.start[0],dy=p[1]-drag.start[1];dx=Math.max(-b[0],Math.min(256-b[2],dx));dy=Math.max(-b[1],Math.min(256-b[3],dy));a.bbox=[b[0]+dx,b[1]+dy,b[2]+dx,b[3]+dy];}
   else {const c=[...b],left=drag.corner%2===0,top=drag.corner<2;c[left?0:2]=left?Math.min(p[0],b[2]-1):Math.max(p[0],b[0]+1);c[top?1:3]=top?Math.min(p[1],b[3]-1):Math.max(p[1],b[1]+1);a.bbox=c;}
   draw();
 };
 canvas.onpointerup=e=>{
   if(!drag)return;const action=drag;drag=null;
   if(action.type==='draw'){const b=action.box;if(b[2]>b[0]&&b[3]>b[1])change(()=>{const a={id:uid(),bbox:b,category:$('drawCategory').value,origin:'manual'};annotations().push(a);selection={type:'truth',id:a.id};mode='select';});else draw();}
   else {const a=annotations().find(a=>a.id===action.id);if(a&&JSON.stringify(a.bbox)!==JSON.stringify(action.box)){history.push(action.before);if(history.length>40)history.shift();touch();save();}render();}
 };
 function cancelDrag(){if(drag?.before)state=drag.before;drag=null;render();}
 canvas.onpointercancel=cancelDrag;
 document.addEventListener('keydown',e=>{if(/INPUT|TEXTAREA|SELECT/.test(e.target.tagName))return;if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();undo();}else if(e.key==='Delete'&&selection?.type==='truth'){e.preventDefault();remove(selection.id);}else if(e.key==='Escape'){cancelDrag();}else if(e.key==='ArrowRight')goto(index+1);else if(e.key==='ArrowLeft')goto(index-1);});
 $('notes').oninput=()=>{if(!noteHistory){snapshot();noteHistory=true;}row().notes=$('notes').value;touch();clearTimeout(saveTimer);saveTimer=setTimeout(save,300);$('progress').textContent=`审核完成 ${D.images.filter(x=>state.images[x.id].reviewed).length} / ${D.images.length}`;};$('notes').onblur=()=>{noteHistory=false;save();render();};
 $('review').onclick=()=>{
   if(M.pending(im(),row()).length){message('还有待确认候选，请逐个接受、标记类别或排除；也请检查未框出的区域。',true);return;}
   if(!annotations().some(a=>a.category==='lesion')&&!$('confirmEmpty').checked){message('没有人工病斑框。请确认已检查整张图，并勾选“未标出可靠病斑”。',true);return;}
   snapshot();row().reviewed=true;row().empty_confirmed=!annotations().some(a=>a.category==='lesion');save();render();message('本张已审核完成。后续改框会自动恢复为待审核状态。');
 };
 $('export').onclick=()=>{if(drag){message('请先完成或取消当前拖动。',true);return;}save();const payload=M.exportState(D,state);const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='leaf_annotations_dev_'+new Date().toISOString().replace(/[:.]/g,'-')+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),3000);message('已导出标注文件。未审核图片保留为草稿，不会计入定位评估。');};
 $('import').onclick=()=>$('importFile').click();$('importFile').onchange=async e=>{const file=e.target.files[0];if(!file)return;try{if(file.size>10*1024*1024)throw new Error('标注文件超过 10 MB。');const restored=M.restore(D,JSON.parse(await file.text()));snapshot();state=restored;selection=null;save();render();message('已导入并核对图片校验值。');}catch(err){message('导入失败：'+err.message,true);}finally{e.target.value='';}};
 render();load();
})();
