let data, index=0, previous=null, noteTimer=null;
const $=id=>document.getElementById(id);
const key=item=>item.blockID+'::'+item.sourceItemID;
const esc=s=>String(s??'');
function pill(value, warning=false){const e=document.createElement('span');e.className='pill'+(warning?' warning':'');e.textContent=esc(value);return e}
function put(id,value){$(id).textContent=esc(value)}
function selected(){return data.source.items[index]}
function label(){return data.labels.labels[key(selected())]}
function render(){const item=selected(), labels=data.labels.labels, current=label();
 put('subtitle', `${data.source.lessonID} · ${item.sourceItemID} · ${data.source.items.length} source items`);
 put('counter',`${index+1} / ${data.source.items.length}`);
 const count=Object.keys(labels).length;put('counts',` · ${count} reviewed · ${data.source.items.length-count} open`);
 $('fill').style.width=`${100*count/data.source.items.length}%`;
 put('sourceText',item.sourceText);put('context',item.sectionContext||'Section context unavailable');put('french',item.proposedFrench);
 const prescription=$('prescription');prescription.replaceChildren();
 for(const [k,v] of Object.entries(item.prescription||{}))if(v!==null&&v!==undefined)prescription.append(pill(`${k}: ${v}`));
 const links=$('links');links.replaceChildren();
 for(const [n,url] of (item.sourceDemoURLs||[]).entries()){try{const u=new URL(url);if(!['https:','http:'].includes(u.protocol))continue;const a=document.createElement('a');a.href=u.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent=`Demo ${n+1} ↗`;links.append(a,document.createTextNode('  '))}catch{}}
 const flags=$('flags');flags.replaceChildren();const all=[...(item.ambiguityFlags||[]),...(item.qualityWarnings||[])];if(all.length)for(const f of all)flags.append(pill(f,true));else flags.append(pill('No flags recorded'));
 $('notes').value=current?.notes||'';for(const d of ['pass','fail','defer']){$(d).classList.toggle('selected',current?.decision===d)}
 const trace={jobID:data.source.jobID,modelIdentity:data.source.modelIdentity,promptVersion:data.source.promptVersion,sourceSHA256:data.source.sourceSHA256,sourceTextSHA256:item.sourceTextSHA256,sourceURL:item.sourceURL,blockID:item.blockID,sourceItemID:item.sourceItemID,runtimeEligible:false};
 put('trace',JSON.stringify(trace,null,2));const attempts=data.attempts[JSON.stringify([item.blockID,item.sourceItemID])]||[];
 put('attempts',attempts.length?JSON.stringify(attempts,null,2):'No attempt database or attempt record available. Actual cost unknown.');
 put('record',JSON.stringify(item,null,2));put('save','');$('prev').disabled=index===0;$('next').disabled=index===data.source.items.length-1;
}
async function save(decision=label()?.decision??null){clearTimeout(noteTimer);const item=selected(), itemKey=key(item),notes=$('notes').value;
 put('save','Saving…');const response=await fetch('/api/label',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({itemKey,decision,notes})});
 const body=await response.json();if(!response.ok){put('save',body.error||'Save failed');return}
 if(body.label)data.labels.labels[itemKey]=body.label;else delete data.labels.labels[itemKey];render();put('save','Saved locally.');
}
async function decide(decision){previous={key:key(selected()),label:label()?{...label()}:null};await save(decision)}
async function undo(){if(!previous)return;const itemIndex=data.source.items.findIndex(i=>key(i)===previous.key);if(itemIndex<0)return;index=itemIndex;render();$('notes').value=previous.label?.notes||'';const restore=previous;previous=null;await save(restore.label?.decision??null)}
function move(delta){clearTimeout(noteTimer);index=Math.max(0,Math.min(data.source.items.length-1,index+delta));render()}
async function init(){const response=await fetch('/api/data');if(!response.ok)throw new Error('Could not load review data');data=await response.json();render();
 for(const d of ['pass','fail','defer'])$(d).onclick=()=>decide(d);
 $('prev').onclick=()=>move(-1);$('next').onclick=()=>move(1);
 $('notes').addEventListener('input',()=>{clearTimeout(noteTimer);if(label())noteTimer=setTimeout(()=>save(),450)});
 $('jump').addEventListener('keydown',e=>{if(e.key==='Enter'){const target=$('jump').value.trim();const found=data.source.items.findIndex(i=>i.sourceItemID===target||key(i)===target);if(found>=0){index=found;render();$('jump').value=''}else put('save','Source item ID not found')}});
 window.addEventListener('keydown',async e=>{if(e.target===$('jump'))return;const typing=e.target===$('notes');if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='s'){e.preventDefault();await save();return}if((e.metaKey||e.ctrlKey)&&e.key==='Enter'){e.preventDefault();await save();move(1);return}if(typing)return;if(e.key==='ArrowLeft')move(-1);if(e.key==='ArrowRight')move(1);if(e.key==='1')decide('pass');if(e.key==='2')decide('fail');if(e.key.toLowerCase()==='d')decide('defer');if(e.key.toLowerCase()==='u')undo()});}
init().catch(err=>put('error',err.message));
