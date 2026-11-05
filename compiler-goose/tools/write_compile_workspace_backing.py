# Source authoring from existing Goose context declarations; no language check.
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]/'src'
from source_model import clean,balanced,split
D={};paths={}
for p in root.rglob('*.goose'):
 s=clean(p.read_text());m=re.search(r'namespace\s+(\w+)\s*;',s)
 if not m:continue
 n=m[1];paths.setdefault(n,p.relative_to(root).with_suffix('').as_posix().replace('/','.'))
 for m in re.finditer(r'\b(struct|enum|type)\s+(\w+)\s*(<[^>{}]+>)?\s*(\{|=)',s):
  kind,name,gen,tok=m.groups();key=n+'::'+name
  if tok=='=':
   if kind=='type':D[key]=(kind,[],s[m.end():s.find(';',m.end())].strip(),n)
  elif kind=='struct':
   fs=[];end=balanced(s,m.end()-1)
   for part in split(s[m.end():end]):
    mm=re.match(r'^(\w+)\s*:\s*(.*)$',part,re.S)
    if not mm:continue
    xs=split(mm[2],'=');fs.append((mm[1],xs[0].strip(),len(xs)>1))
   D[key]=(kind,split((gen or '<>')[1:-1]),fs,n)
  else:D[key]=(kind,[],[],n)
def qualify(t,n,subs):
 def sub(m):
  w=m[0]
  if w in subs:return subs[w]
  if n+'::'+w in D:return n+'::'+w
  return w
 return re.sub(r'(?<![\w:])\b\w+\b(?!::)',sub,t)
def info(t):
 t=t.strip();m=re.fullmatch(r'(\w+::\w+)(?:<(.*)>)?',t,re.S)
 if not m or m[1] not in D:return None
 kind,params,body,n=D[m[1]];args=split(m[2] or '');sub=dict(zip(params,args))
 if kind=='type':return info(qualify(body,n,sub))
 if kind!='struct':return None
 return [(name,qualify(ft,n,sub),default) for name,ft,default in body]
lines=[];used=set();allowners=[];record_types={};exprs={}
def imp(t):
 for n in re.findall(r'\b(\w+)::',t):
  if n in paths:used.add(paths[n])
def stripouter(t):
 t=t.strip()
 while t.startswith('(') and balanced(t,0,'(',')')==len(t)-1:t=t[1:-1].strip()
 return t
special={
 'blot_reuse_artifact_capture::Capture':'blot_reuse_artifact_capture::inactive_capture',
}
def defaults_expr(t,name):
 t=stripouter(t);imp(t)
 if t in special:return special[t]
 fs=info(t)
 if fs is None:return 'default<'+t+'>()'
 assigned=[]
 for field,ft,hasdefault in fs:
  if hasdefault:continue
  ff=stripouter(ft)
  if ff.endswith('&'):
   inner=stripouter(ff[:-1]);inner=re.sub(r'^const\s+','',inner);value=owner(name+'_'+field,inner);assigned.append(field+':'+value)
  elif info(ff) and mandatory(ff):assigned.append(field+':'+defaults_expr(ff,name+'_'+field))
 return t+'{'+','.join(assigned)+(',..' if assigned else '..')+'}'
def mandatory(t,seen=None):
 seen=set() if seen is None else seen
 if t in seen:return False
 seen=seen|{t}
 fs=info(t)
 if fs is None:return False
 return any(not hd and (stripouter(ft).endswith('&') or mandatory(ft,seen)) for f,ft,hd in fs)
def owner(name,t):
 name=re.sub(r'[^a-zA-Z0-9_]','_',name);t=stripouter(t);imp(t)
 if name in exprs:return name
 exprs[name]=t
 if t in special:return special[t]
 if '[>..' in t:
  init='[]';allowners.append((name,t,'grow'))
 elif t.startswith('dictionary<'):
  init=t+'{..}';allowners.append((name,t,'dictionary'))
 else:init=defaults_expr(t,name);record_types[name]=t
 lines.append('var '+name+': '+t+' = '+init+';')
 return name
# Canonical dynamic handles are supplied only after every successful allocation.
ws='blot_backend_core_backend::CompileWorkspace'
wsargs={'publication_owner':'blot_backend_result_publication::Owner{..}','allocation_owner':'allocation_owner','generator':'generator','session_tables':'tables','journal':'capture.emission','metadata':'capture.metadata','capture':'capture','optimized':'optimized'}
for f,t,hd in info(ws):
 if f in wsargs or hd:continue
 assert t.endswith('&'),(f,t)
 wsargs[f]=owner('backing_'+f,t[:-1])
gen='blot_backend_core_backend::Generator'
gargs={'allocation_owner':'allocation_owner','units':'[]','evaluator':'session'}
for f,t,hd in info(gen):
 if f in gargs or hd:continue
 if t.endswith('&'):gargs[f]=owner('backing_generator_'+f,t[:-1])
 elif mandatory(t):gargs[f]=defaults_expr(t,'backing_generator_'+f)
# All backing data is explicit, named and long lived. Releasing a frame clears
# both Grow and dictionary containers; their high-water capacity belongs to this
# process compiler backing and is reused by subsequent frames.
header='''// One active compiler attempt per process. Every growing owner is named here;
// retained publication data and captures live in separate typed owner pools.
namespace blot_compile_workspace;
'''
used.update(['dictionary','backend.core_backend','backend.result_publication','eval.core_eval','reuse.artifact_capture','backend.optimized_bodies'])
body=header+'\n'.join('import '+x+';' for x in sorted(used))+'\n\n'+'\n'.join(lines)+'\n\n'
body+='fn makeGenerator(allocation_owner:u64,session:blot_eval_core_eval::Session&)->blot_backend_core_backend::Generator {return '+gen+'{'+','.join(k+':'+v for k,v in gargs.items())+',..};}\n'
body+='fn makeWorkspace(allocation_owner:u64,generator:blot_backend_core_backend::Generator&,tables:blot_eval_core_eval::SessionTables,capture:blot_reuse_artifact_capture::Capture&,optimized:blot_backend_optimized_bodies::Capture&)->'+ws+' {return '+ws+'{'+','.join(k+':'+v for k,v in wsargs.items())+',..};}\n'
body+='fn resetBackingDescriptors() {\n'+'\n'.join(' '+line[4:line.index(':')]+line[line.index(' = '):] for line in lines if line[4:line.index(':')] in record_types)+'\n}\n'
body+='fn clearBacking() {\n'+'\n'.join(' '+n+'.clear();' for n,t,k in allowners)+'\n}\n'
(root/'driver/compile_workspace_backing.goose').write_text(body)
import json
(root.parent/'build/compile-workspace-backing-model.json').write_text(json.dumps({'workspace':wsargs,'generator':gargs,'records':record_types,'owners':allowners},indent=2))
