(function(root){
  'use strict';
  const categories=['lesion','uncertain','background'];
  const copy=x=>JSON.parse(JSON.stringify(x));
  function blank(data){return {dataset_id:data.dataset_id,images:Object.fromEntries(data.images.map(im=>[im.id,{reviewed:false,empty_confirmed:false,notes:'',annotations:[],proposal_decisions:{}}]))};}
  function pending(im,row){return im.proposals.filter(p=>!row.proposal_decisions[p.id]);}
  function exportState(data,state){return {schema_version:1,dataset_id:data.dataset_id,dataset_role:'development',bbox_format:'xyxy_half_open',proposal_source:data.proposal_source,exported_at:new Date().toISOString(),images:data.images.map(im=>({id:im.id,filename:im.filename,original_name:im.original_name,width:im.width,height:im.height,pixel_sha256:im.pixel_sha256,...copy(state.images[im.id])}))};}
  function restore(data,payload){
    const fail=msg=>{throw new Error(msg);};
    if(payload.schema_version!==1||payload.dataset_id!==data.dataset_id||payload.bbox_format!=='xyxy_half_open'||payload.dataset_role!=='development')fail('标注文件的图片集或坐标格式不匹配，未覆盖当前内容。');
    if(!Array.isArray(payload.images)||payload.images.length!==data.images.length)fail('图片数量不匹配。');
    const state=blank(data),seen=new Set();
    for(const item of payload.images){
      const im=data.images.find(x=>x.id===item.id);
      if(!im||seen.has(item.id)||im.pixel_sha256!==item.pixel_sha256||item.width!==im.width||item.height!==im.height)fail('图片编号、尺寸或 RGB 校验值不匹配。');
      seen.add(item.id);
      if(typeof item.reviewed!=='boolean'||typeof item.empty_confirmed!=='boolean'||typeof item.notes!=='string'||item.notes.length>3000||!Array.isArray(item.annotations)||item.annotations.length>2000)fail('审核状态或标注内容格式有误。');
      const decisions=item.proposal_decisions;
      if(!decisions||typeof decisions!=='object'||Array.isArray(decisions))fail('候选审核记录格式有误。');
      const known=new Set(im.proposals.map(p=>p.id));
      for(const [id,value] of Object.entries(decisions))if(!known.has(id)||!['accepted','rejected'].includes(value))fail('存在未知候选或无效审核决定。');
      const ids=new Set(),origins=new Set();
      for(const a of item.annotations){
        if(!a||typeof a.id!=='string'||!/^[A-Za-z0-9_-]{1,100}$/.test(a.id)||ids.has(a.id)||!categories.includes(a.category))fail('标注编号重复或类别无效。');
        ids.add(a.id);
        const b=a.bbox;
        if(!Array.isArray(b)||b.length!==4||!b.every(Number.isInteger)||b[0]<0||b[1]<0||b[2]>im.width||b[3]>im.height||b[2]<=b[0]||b[3]<=b[1])fail('标注框超出原图或尺寸无效。');
        if(a.origin!=='manual'){
          if(!known.has(a.origin)||decisions[a.origin]!=='accepted'||origins.has(a.origin))fail('候选与人工标注的对应关系不完整。');
          origins.add(a.origin);
        }
      }
      for(const [id,value] of Object.entries(decisions))if(value==='accepted'&&!origins.has(id))fail('已接受候选缺少人工标注。');
      const row=copy({reviewed:item.reviewed,empty_confirmed:item.empty_confirmed,notes:item.notes,annotations:item.annotations,proposal_decisions:decisions});
      if(row.reviewed&&(pending(im,row).length||(!row.annotations.some(a=>a.category==='lesion')&&!row.empty_confirmed)))fail('审核完成状态缺少候选处理或无病斑确认。');
      state.images[im.id]=row;
    }
    return state;
  }
  const api={blank,pending,exportState,restore,copy,categories};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.AnnotationModel=api;
})(typeof window!=='undefined'?window:globalThis);
