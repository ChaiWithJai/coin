"""GB10 CPU integration only. Synthetic decision cases, not boxing validation."""
import json,time,hashlib,importlib.metadata,inspect
from pathlib import Path
from huggingface_hub import HfApi,snapshot_download
import laya
ROOT=Path(__file__).resolve().parent
repo='convaiinnovations/laya-multilingual'
info=HfApi().model_info(repo)
revision=info.sha
path=snapshot_download(repo,revision=revision,allow_patterns=['*.json','*.safetensors','*.txt','*.model'])
files={str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(path).rglob('*') if p.is_file()}
manifest={'repo':repo,'revision':revision,'files':files,'device':'cpu','laya_version':importlib.metadata.version('laya'),'torch_version':importlib.metadata.version('torch'),'purpose':'synthetic decision integration'}
(ROOT/'laya-manifest.json').write_text(json.dumps(manifest,indent=2))
start=time.perf_counter();agent=laya.load(path,device='cpu');load_seconds=time.perf_counter()-start
cases=[
 {'id':'confirmed-fr','state':'Boxe en solo. Observation confirmée par le boxeur: main arrière basse après le jab. Image actuelle nette. Aucun signal récent. Pas de douleur signalée.'},
 {'id':'occluded-en','state':'Solo boxing. The boxer is hidden behind the bag. Hand position is unknown. There is no confirmed movement observation.'},
 {'id':'cooldown-fr','state':'Boxe en solo. Main arrière basse confirmée, mais un signal a déjà été donné il y a une seconde. Attendre au moins cinq secondes entre les signaux.'}
]
questions={'intervention':{'type':'choice','instructions':'Choose whether to cue now, stay quiet, or request review. Only cue on a confirmed visible issue and when five-second cooldown is clear. Do not guess hidden movements.','criteria':{'cue':'Confirmed visible issue, cooldown clear.','quiet':'No reliable issue or cooldown active.','review':'Conflicting evidence needing review.'}}}
results=[]
for case in cases:
 start=time.perf_counter();out=agent.predict(case['state'],questions);elapsed=time.perf_counter()-start
 results.append({'case':case,'questions':questions,'result':out,'seconds':elapsed})
report={'manifest':manifest,'load_seconds':load_seconds,'results':results}
(ROOT/'laya-cpu-result.json').write_text(json.dumps(report,indent=2,ensure_ascii=False,default=str))
print(json.dumps({'revision':revision,'load_seconds':load_seconds,'results':results},ensure_ascii=False,default=str))
