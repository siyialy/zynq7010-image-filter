/* Pure Node model / event-flow tests. This does not claim browser rendering QA. */
'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const root=path.resolve(__dirname,'..'),folder=path.join(root,'annotation_tool');
const D=JSON.parse(fs.readFileSync(path.join(folder,'dataset.json'),'utf8'));
const M=require(path.join(folder,'model.js'));
assert.strictEqual(D.images.length,24);assert.strictEqual(D.images.reduce((s,i)=>s+i.proposals.length,0),65);
let blank=M.blank(D),payload=M.exportState(D,blank);
assert(payload.images.every(i=>!i.reviewed&&!i.annotations.length));
assert.deepStrictEqual(M.restore(D,payload),blank);
for(const corrupt of [p=>p.dataset_id='wrong',p=>p.images[0].pixel_sha256='wrong',p=>{p.images[13].reviewed=true;},p=>p.images[0].annotations.push({id:'bad',category:'lesion',origin:'manual',bbox:[0,0,257,5]})]){
 const bad=M.copy(payload);corrupt(bad);assert.throws(()=>M.restore(D,bad));
}

function makeDOM(){
 const elements=new Map(),listeners={},storage=new Map(),downloads=[];
 const context={clearRect(){},drawImage(){},strokeRect(){},setLineDash(){},fillText(){},fillRect(){}};
 function element(id){
  if(elements.has(id))return elements.get(id);
  const el={id,tagName:'DIV',dataset:{},style:{},value:'',checked:false,disabled:false,hidden:false,
   textContent:'',scrollLeft:0,scrollTop:0,clientWidth:512,clientHeight:512,
   classList:{toggle(){},add(){},remove(){}},focus(){document.activeElement=this;},setPointerCapture(){},
   getContext(){return context;},closest(){return this;},click(){downloads.push(this);},
   getBoundingClientRect(){const z=parseFloat(element('canvas').style.width||'100')/100;return {left:-element('canvasViewport').scrollLeft,top:-element('canvasViewport').scrollTop,width:512*z,height:512*z};}};
  Object.defineProperty(el,'scrollWidth',{get:()=>512*parseFloat(element('canvas').style.width||'100')/100});
  Object.defineProperty(el,'scrollHeight',{get:()=>el.scrollWidth});
  let inner='';Object.defineProperty(el,'innerHTML',{get:()=>inner,set:value=>{inner=value;for(const m of value.matchAll(/<input id="([^"]+)"[^>]*value="([^"]*)"/g)){element(m[1]).value=m[2];element(m[1]).tagName='INPUT';}}});
  elements.set(id,el);return el;
 }
 for(const m of fs.readFileSync(path.join(folder,'index.html'),'utf8').matchAll(/id="([^"]+)"/g))element(m[1]);
 element('showProposals').checked=true;element('drawCategory').value='lesion';element('zoom').value='1';
 const document={activeElement:null,getElementById:element,addEventListener:(n,f)=>{listeners[n]=f;},createElement:()=>element('anchor'+downloads.length)};
 class FakeImage{set src(value){this.value=value;queueMicrotask(()=>this.onload?.());}}
 const sandbox={window:{ANNOTATION_DATASET:D,AnnotationModel:M},document,Image:FakeImage,console,crypto:require('crypto').webcrypto,
  localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},Blob,
  URL:{createObjectURL:b=>{downloads.push(b);return 'blob:test';},revokeObjectURL(){}},setTimeout:()=>0,clearTimeout(){}};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(folder,'app.js'),'utf8'),sandbox);
 const click=(id,dataset)=>{if(dataset){listeners.click({target:{dataset,closest(){return this;}}});}else if(!element(id).disabled){element(id).onclick?.({target:element(id)});}};
 const saved=()=>JSON.parse([...storage.values()][0]);
 return {element,listeners,click,saved,downloads};
}
(async()=>{
 const h=makeDOM();await new Promise(r=>setImmediate(r));
 assert.strictEqual(h.element('sampleTitle').textContent,'第 14 张');
 h.click('review');assert(h.element('notice').textContent.includes('还有待确认候选'));
 const p=D.images[13].proposals[0];h.click(null,{accept:p.id});
 assert.strictEqual(h.saved().images[13].annotations.length,1);
 assert.strictEqual(h.saved().images[13].reviewed,false);
 h.element('edit0').value='250';h.element('edit1').value='250';h.element('edit2').value='20';h.element('edit3').value='20';
 h.click(null,{applyBox:'1'});assert(h.element('notice').textContent.includes('坐标需为整数'));
 h.element('edit0').value='100';h.element('edit1').value='100';h.element('edit2').value='10';h.element('edit3').value='12';h.click(null,{applyBox:'1'});
 assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,[100,100,110,112]);
 h.click('undo');assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,p.bbox);
 h.click('undo');assert.strictEqual(h.saved().images[13].annotations.length,0);
 h.click('drawMode');const canvas=h.element('canvas');
 canvas.onpointerdown({button:0,clientX:200,clientY:200,pointerId:1,preventDefault(){}});
 canvas.onpointermove({clientX:240,clientY:250});canvas.onpointerup({});
 assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,[100,100,120,125]);
 h.element('zoom').value='2';h.element('zoom').onchange();assert.strictEqual(canvas.style.width,'200%');
 h.click('undo');assert.strictEqual(h.saved().images[13].annotations.length,0);
 h.click('drawMode');let rect=canvas.getBoundingClientRect();
 const xy=(x,y)=>({clientX:rect.left+x*rect.width/256,clientY:rect.top+y*rect.height/256});
 canvas.onpointerdown({button:0,...xy(100,100),pointerId:2,preventDefault(){}});
 canvas.onpointermove(xy(120,125));canvas.onpointerup({});
 assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,[100,100,120,125]);
 canvas.onpointerdown({button:0,...xy(120,125),pointerId:3,preventDefault(){}});
 canvas.onpointermove(xy(125,130));canvas.onpointerup({});
 assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,[100,100,125,130]);
 h.click('undo');
 canvas.onpointerdown({button:0,altKey:true,...xy(110,112),pointerId:4,preventDefault(){}});
 canvas.onpointermove(xy(115,115));canvas.onpointerup({});
 assert.deepStrictEqual(h.saved().images[13].annotations[0].bbox,[105,103,125,128]);
 h.click('undo');h.click('undo');assert.strictEqual(h.saved().images[13].annotations.length,0);
 h.click(null,{sample:'0'});await new Promise(r=>setImmediate(r));
 h.click('review');assert(h.element('notice').textContent.includes('没有人工病斑框'));
 h.element('confirmEmpty').checked=true;h.click('review');assert(h.saved().images[0].reviewed);
 h.click('drawMode');
 canvas.onpointerdown({button:0,clientX:200,clientY:200,pointerId:5,preventDefault(){}});
 canvas.onpointermove({clientX:220,clientY:220});canvas.onpointerup({});
 assert.strictEqual(h.saved().images[0].reviewed,false);
 h.click('undo');assert.strictEqual(h.saved().images[0].reviewed,true);
 h.click('export');const exported=JSON.parse(await h.downloads.find(x=>x instanceof Blob).text());
 assert(exported.images[0].reviewed);assert(!exported.images[13].reviewed);assert.strictEqual(exported.images[13].annotations.length,0);
 assert(M.restore(D,exported));
 console.log('PASS: 24 images / 65 proposals; no automatic truth; import identity checks; accept / edit / reject-review gate / draw / undo / zoom / empty-image confirmation / JSON export flows.');
 console.log('Event tests use a DOM substitute, not a real browser rendering or pointer-device test.');
})().catch(e=>{console.error(e);process.exitCode=1;});
