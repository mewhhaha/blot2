# Source authoring only: native wire declarations -> concrete Goose codecs.
# Never executes either compiler, a checker, tests, formatting or qualification.
from pathlib import Path
import re,json
REPO=Path(__file__).resolve().parents[2]
ROOT=REPO/'compiler/src';GOOSE=REPO/'compiler-goose/src'
from source_model import clean,balanced,split
def fields(body):
 out=[]
 for part in split(body):
  if not re.match(r'\s*\w+\s*:',part):continue
  name,ty=part.split(':',1);out.append((name.strip(),split(ty,'=')[0].strip()))
 return out
G={};GF={}
for path in sorted(GOOSE.rglob('*.goose')):
 text=clean(path.read_text());m=re.search(r'namespace\s+(\w+)\s*;',text)
 if not m:continue
 namespace=m[1];GF.setdefault(namespace,path.relative_to(GOOSE).with_suffix('').as_posix().replace('/','.'))
 for m in re.finditer(r'\b(struct|enum|type)\s+(\w+)\s*(\{|=)',text):
  kind,name,token=m.groups();key=namespace+'::'+name
  if token=='=':
   if kind=='type':G[key]=('alias',text[m.end():text.find(';',m.end())].strip(),namespace)
  else:
   end=balanced(text,m.end()-1);body=text[m.end():end]
   if kind=='struct':G[key]=('struct',fields(body),namespace)
   elif kind=='enum':
    variants=[]
    for part in split(body):
     m=re.fullmatch(r'(\w+)\s*(?:\{(.*)\})?',part.strip(),re.S)
     if m:variants.append((m[1],fields(m[2] or '')))
    G[key]=('enum',variants,namespace)
(GOOSE.parent/'build').mkdir(parents=True,exist_ok=True)
# Native declarations retain qualified source names and field scalar domains.
N={};NI={};NA={};NFILE={}
for path in sorted(ROOT.rglob('*.zig')):
 module=path.relative_to(ROOT).with_suffix('').as_posix().replace('/','.')
 text=clean(path.read_text());NFILE[module]=path
 NI[module]={}
 for m in re.finditer(r'\bconst\s+(\w+)\s*=\s*@import\("([^"\n]+)"\)\s*;',text):
  target=(path.parent/m[2]).resolve()
  try:NI[module][m[1]]=target.relative_to(ROOT.resolve()).with_suffix('').as_posix().replace('/','.')
  except ValueError:pass
 containers=[]
 for m in re.finditer(r'\b(?:pub\s+)?const\s+(\w+)\s*=\s*(?:(packed|extern)\s+)?(struct|enum|union)(?:\(([^)]*)\))?\s*\{',text):
  name,layout,kind,backing=m.groups();start=m.end()-1;end=balanced(text,start);parent=[c for c in containers if c[1]<m.start()<c[2]]
  full=(max(parent,key=lambda x:x[1])[0]+'.'+name) if parent else module+'.'+name
  containers.append((full,start,end));N[full]=(kind,text[start+1:end],module,backing or '')
 for m in re.finditer(r'\b(?:pub\s+)?const\s+(\w+)\s*=\s*([^;\n]+);',text):
  name,expr=m.groups();parent=[c for c in containers if c[1]<m.start()<c[2]];full=(max(parent,key=lambda x:x[1])[0]+'.'+name) if parent else module+'.'+name
  if full not in N:NA[full]=(expr.strip(),module)
# Native declaration parsing does not infer a schema from Goose owner fields.
def native_fields(body):
 # Methods follow fields in all transported native records. Nested public
 # type declarations end with semicolons, so remove those before splitting.
 body=re.sub(r'(?m)^\s*(?:pub\s+)?const\s+\w+\s*=\s*[^;]*;', '', body)
 out=[]
 for part in split(body):
  m=re.match(r'^\s*(\w+)\s*:\s*(.*)',part,re.S)
  if m:out.append((m[1],split(m[2],'=')[0].strip()))
 return out
PRIMITIVES={'bool','void','usize','isize','f16','f32','f64'}|{p+str(n) for p in ('u','i') for n in range(1,65)}
RENAMES={'u32':'unsigned32','f32':'floating32','block':'block_','match':'match_','loop':'loop_','opaque':'opaque_'}
def goose_type(raw,namespace):
 raw=raw.strip()
 if raw.startswith('const '):raw=raw[6:].strip()
 if raw in ('u8','u16','u32','u64','i8','i16','i32','i64','bool','f32','f64'):return raw
 m=re.fullmatch(r'(.+)\[(:|\d+)\]',raw)
 if m:return goose_type(m[1],namespace)+'['+m[2]+']'
 if raw.startswith('blot_support::Option<'):return 'blot_support::Option<'+goose_type(raw[21:-1],namespace)+'>'
 if raw.startswith('Option<'):return 'blot_support::Option<'+goose_type(raw[7:-1],namespace)+'>'
 key=raw if '::' in raw else namespace+'::'+raw
 if key not in G:raise ValueError(('undeclared Goose wire type',key))
 kind,body,owner=G[key]
 if kind=='alias':return goose_type(body,owner)
 return key
# Explicit spelling frontiers for anonymous native field types are recorded
# separately. The source compiler's generated names need oracle qualification.
SPELLINGS={
 # Assigned native definitions resolve aliases before their type names hash.
}
DESCS={};ORDER=[];ROOTS=[]
def native_resolve(raw,module,parent='',field='',hint=None,seen=()):
 raw=raw.strip()
 if raw=='@TypeOf(@as(Value, undefined).scalar)' and module=='eval.eval_values':raw='backend.runtime_ir.Scalar'
 if raw.startswith('?'):
  child=native_resolve(raw[1:],module,parent,field,hint=option_child(hint));return install('?'+child['name'],'optional',hint,[child])
 if raw.startswith('[]'):
  tail=raw[2:].strip();const=tail.startswith('const ')
  if const:tail=tail[6:].strip()
  child=native_resolve(tail,module,parent,field,hint=slice_child(hint));return install('[]'+('const ' if const else '')+child['name'],'slice',hint,[child])
 m=re.match(r'^\[(\d+)\](.*)',raw,re.S)
 if m:
  child=native_resolve(m[2],module,parent,field,hint=slice_child(hint));return install('['+m[1]+']'+child['name'],'array',hint,[child],count=int(m[1]))
 if raw in PRIMITIVES:return install(raw,'primitive',hint,[],primitive=raw)
 if raw.startswith(('enum','struct','union')):
  kind=re.match(r'(enum|struct|union)',raw)[1];a=raw.index('{');body=raw[a+1:balanced(raw,a)];name=SPELLINGS.get(parent+'.'+field,parent+'.'+field)
  return build_named(name,kind,body,module,hint)
 imp=re.fullmatch(r'@import\("([^"\n]+)"\)\.([\w.]+)',raw)
 if imp:
  p=(NFILE[module].parent/imp[1]).resolve();mod=p.relative_to(ROOT.resolve()).with_suffix('').as_posix().replace('/','.');return native_resolve(mod+'.'+imp[2],mod,parent,field,hint,seen)
 if raw.startswith('@FieldType('):
  m=re.fullmatch(r'@FieldType\(([^,]+),\s*"([^"]+)"\)',raw);base=native_resolve(m[1],module,hint=None);return next(x[1] for x in base['fields'] if x[0]==m[2])
 if raw in NI.get(module,{}):raise ValueError(('module requested as data',raw,module))
 candidates=[raw]
 if '.' in raw:
  first,rest=raw.split('.',1)
  if first in NI.get(module,{}):candidates=[NI[module][first]+'.'+rest]
  else:candidates=[module+'.'+raw,raw]
 else:
  scope=parent
  while scope and scope!=module:
   candidates.append(scope+'.'+raw);scope=scope.rpartition('.')[0]
  candidates.append(module+'.'+raw)
 for key in candidates:
  if key in DESCS:return DESCS[key]
  if key in N:
   kind,body,owner,backing=N[key]
   if kind=='struct' or kind in ('enum','union'):return build_named(key,kind,body,owner,hint)
  if key in NA and key not in seen:
   expr,owner=NA[key]
   if expr.startswith('@import(') and re.fullmatch(r'@import\("[^"]+"\)',expr):continue
   # Public aliases can traverse an imported alias namespace (T.Effects.Row).
   return native_resolve(expr,owner,parent,field,hint,seen+(key,))
  # T.Effects names a module-valued const in the imported type namespace.
  parts=key.split('.')
  for cut in range(len(parts)-1,0,-1):
   alias='.'.join(parts[:cut]);tail='.'.join(parts[cut:])
   if alias in NA:
    expr,owner=NA[alias];m=re.fullmatch(r'@import\("([^"]+)"\)',expr)
    if m:
     target=(NFILE[owner].parent/m[1]).resolve().relative_to(ROOT.resolve()).with_suffix('').as_posix().replace('/','.')
     return native_resolve(target+'.'+tail,target,parent,field,hint,seen+(alias,))
 raise ValueError(('unresolved native wire type',raw,module,parent,field,hint))
def option_child(hint):
 if hint and hint.startswith('blot_support::Option<'):return hint[21:-1]
 return None
def slice_child(hint):
 if hint:
  m=re.fullmatch(r'(.+)\[(:|\d+)\]',hint)
  if m:return m[1]
 return None
def install(name,kind,hint,children,**extra):
 if name in DESCS:return DESCS[name]
 if not hint:
  if kind=='primitive':
   if name=='void':hint='Void'
   elif name=='usize' or name=='isize':hint='i64'
   elif name=='bool':hint='bool'
   elif name.startswith('u'):
    bits=int(name[1:]);hint=next('u'+str(n) for n in (8,16,32,64) if n>=bits)
   elif name.startswith('i'):
    bits=int(name[1:]);hint=next('i'+str(n) for n in (8,16,32,64) if n>=bits)
   else:hint=name
  elif kind=='slice':hint=children[0]['goose']+'[:]'
  elif kind=='array':hint=children[0]['goose']+'['+str(extra['count'])+']'
  elif kind=='optional':hint='blot_support::Option<'+children[0]['goose']+'>'
 d={'name':name,'kind':kind,'goose':hint,'children':children,**extra};DESCS[name]=d;ORDER.append(d);return d
def build_named(name,kind,body,module,hint):
 if name in DESCS:return DESCS[name]
 if hint is None:
  suffix=name.split('.')[-1];goose_ns='blot_'+module.replace('.','_');hint=goose_ns+'::'+suffix
 if hint not in G:
  if kind=='enum' and hint in ('u8','u16','u32','u64','i8','i16','i32','i64'):gkind,gbody,gns='primitive',[],''
  else:raise ValueError(('missing Goose counterpart',name,hint))
 else:gkind,gbody,gns=G[hint]
 d=install(SPELLINGS.get(name,name),kind,hint,[]);DESCS[name]=d;d['fields']=[];d['variants']=[]
 if kind=='struct':
  gf=dict(gbody);nf=native_fields(body)
  if name=='check.types.Node':nf=[(n,t) for n,t in nf if n in ('tag','a','b','c')]
  for field,raw in nf:
   target=field
   if field not in gf:
    target={'type':'ty'}.get(field,field)
   if target not in gf:raise ValueError(('missing Goose wire field',name,field,hint,list(gf)))
   gh=goose_type(gf[target],gns);child=native_resolve(raw,module,name,field,gh);d['fields'].append((field,child,target))
 elif kind=='enum':
  current=-1;gv={n:fs for n,fs in gbody}
  for part in split(body):
   part=part.strip()
   if not re.match(r'^(?:@"[^"]+"|\w+)(?:\s*=|\s*$)',part):continue
   m=re.fullmatch(r'(@"[^"]+"|\w+)(?:\s*=\s*(\d+|0x[0-9a-fA-F]+))?',part)
   if not m:continue
   field=m[1].removeprefix('@"').removesuffix('"')
   if field=='_':continue
   current=int(m[2],0) if m[2] else current+1;target=RENAMES.get(field,field)
   if gkind=='enum' and target not in gv:raise ValueError(('missing Goose enum field',name,field,hint))
   d['variants'].append((field,current,target))
 elif kind=='union':
  gv=dict(gbody);tagname=SPELLINGS.get(name+'.tag','@typeInfo('+name+').@"union".tag_type.?');tag=install(tagname,'union_tag','u32',[]);tag['variants']=[]
  for ordinal,(field,raw) in enumerate(native_fields(body)):
   target=RENAMES.get(field,field)
   if target not in gv:raise ValueError(('missing Goose union variant',name,field,hint))
   fs=gv[target];payload_hint=None
   if len(fs)==1:payload_hint=goose_type(fs[0][1],gns)
   payload=native_resolve(raw,module,name,field,payload_hint);d['variants'].append((field,ordinal,target,payload,fs));tag['variants'].append((field,ordinal,target))
  d['tag']=tag
 return d
ROOT_PAIRS=[
 ('blot_reuse_dependency_format::Key','reuse.dependency_format.Key'),
 ('blot_reuse_frozen_dependency::FrozenDependency','reuse.frozen_dependency.FrozenDependency'),
 ('blot_reuse_frozen_dependency::Module','reuse.frozen_dependency.Module'),
 ('blot_reuse_principal_interface::Interface','reuse.principal_interface.Interface'),
 ('blot_check_core::Module','check.core.Module'),
 ('blot_reuse_revision_inputs::Wire','reuse.revision_inputs.Persisted.Wire'),
 ('blot_reuse_principal_archive::Snapshot','reuse.principal_archive.Snapshot'),
 ('blot_reuse_semantic_archive::Snapshot','reuse.semantic_archive.Snapshot'),
 ('blot_reuse_optimized_archive::Snapshot','reuse.optimized_archive.Snapshot'),
 ('blot_backend_backend_checkpoint::Wire','backend.backend_checkpoint.Wire'),
 ('blot_reuse_retained_revision::RestoredWire','reuse.retained_revision.Restored.Wire'),
]
# Section is a concrete Goose record per archive; source uses a generic factory.
for module,claim in [('principal_archive','principal_complete_proof'),('semantic_archive','selected_complete_proof'),('optimized_archive','optimizer_output')]:
 name='reuse.'+module+'.Section';N[name]=('struct','header: @import("portable_query.zig").Header, records: []Record,','reuse.'+module,'')
 SPELLINGS[name]='reuse.portable_query.Section(.'+claim+',reuse.'+module+'.Record)'
for g,n in ROOT_PAIRS:
 # Wire DTO identity uses readonly data; the native spelling remains Metadata.
 if g=='blot_reuse_semantic_archive::Snapshot':
  G.setdefault('blot_backend_runtime_identity::Metadata',G['blot_reuse_code_artifacts::IdentityMetadata'])
 d=native_resolve(n,n.rpartition('.')[0],hint=g);ROOTS.append(d)
# Primitive and fixed digest are public format roots too.
for p in ('u8','u16','u32','u64','i8','i16','i32','i64','bool','f32','f64'):
 ROOTS.append(native_resolve(p,'reuse.dependency_format'))
ROOTS.append(native_resolve('[32]u8','reuse.dependency_format',hint='u8[32]'))
(GOOSE.parent/'build/dependency-wire-model.json').write_text(json.dumps({'roots':[d['name'] for d in ROOTS],'descriptors':[{'name':d['name'],'kind':d['kind'],'goose':d['goose'],'children':[x['name'] for x in d['children']],'fields':[(n,c['name'],g) for n,c,g in d.get('fields',[])],'variants':[(v[0],v[1],v[2]) for v in d.get('variants',[])]} for d in ORDER]},indent=2))
# Concrete procedure names retain each native wire domain even when Goose
# aliases share the same storage type (e.g Op/Role/Scalar are all u8).
def ident(text):return re.sub(r'[^A-Za-z0-9_]','_',text)
def proc(d):return ident(d['name'])
def q(text):return json.dumps(text,ensure_ascii=False)
def actual(d):return d['goose'] or 'Void'
def error_return(d,error='error'):return 'return default<'+actual(d)+'>(),'+error+';'
def step(d,expr,target,var='decoded'):
 return '{let '+var+',error='+expr+';if error!=Error.none {'+error_return(d)+'}'+target+'='+var+';}'
def minimum(d):
 kind=d['kind']
 if kind in ('slice','optional','enum','union','union_tag'):return 1
 if kind=='primitive':
  p=d['primitive'];return 0 if p=='void' else (int(p[1:])//8 if p.startswith('f') else 1)
 if kind=='array':return d['count']*minimum(d['children'][0])
 return sum(minimum(c) for n,c,g in d['fields'])
def scalar_bounds(p):
 if p=='usize':return 0,0x7fffffffffffffff
 if p=='isize':return -0x8000000000000000,0x7fffffffffffffff
 bits=int(p[1:]);return ((0,(1<<bits)-1) if p[0]=='u' else (-(1<<(bits-1)),(1<<(bits-1))-1))
imports={'support.error','support.option','support.native','support.blake3','reuse.dependency_format','check.core','check.types'}
for d in ORDER:
 for namespace in re.findall(r'\b(blot_\w+)::',actual(d)):
  if namespace in GF:imports.add(GF[namespace])
lines=['// Concrete native-schema wire codecs, authored from frozen declarations.\n// Package/anonymous/generic native type-name spellings remain unqualified.\nnamespace blot_reuse_dependency_format;\n']+['import '+p+';\n' for p in sorted(imports)]+['struct Void {}\n']
for d in ORDER:
 t=actual(d);name=proc(d);kind=d['kind']
 # The schema's spelling is independent of Goose public/private owner fields.
 lines.append(f'fn describe_{name}(hasher:blot_support_blake3::State&,value:{t}) {{hasher.update({q(d["name"])});hasher.update([0]);')
 if kind=='struct':
  for field,child,target in d['fields']:lines.append(f'hasher.update({q(field)});hasher.update([0]);describe_{proc(child)}(hasher,default<{actual(child)}>());')
 elif kind in ('array','slice','optional'):lines.append(f'describe_{proc(d["children"][0])}(hasher,default<{actual(d["children"][0])}>());')
 elif kind in ('enum','union_tag'):
  for field,ordinal,target in d['variants']:lines.append(f'hasher.update({q(field)});block {{let bits:u64={ordinal};var bytes:u8[8];for index in 0..8 {{bytes[index]=(bits>>((index*8) as u32)) as! u8;}}hasher.update(bytes[:]);}}')
 elif kind=='union':
  lines.append(f'describe_{proc(d["tag"])}(hasher,0);')
  for field,ordinal,target,child,fs in d['variants']:lines.append(f'hasher.update({q(field)});hasher.update([0]);describe_{proc(child)}(hasher,default<{actual(child)}>());')
 lines.append('}\n')
 # Encode using a counting or exact-output Encoder; only slices spend elements.
 lines.append(f'fn write_{name}(writer:Encoder&,value:{t},level:i64)->Error {{let error=writer.depth(level);if error!=Error.none {{return error;}}')
 if kind=='primitive':
  p=d['primitive']
  if p=='void':lines.append('return Error.none;')
  elif p=='bool':lines.append('var bit:u64=0;if value {bit=1;}return writer.integer(bit,1);')
  elif p in ('f32','f64'):lines.append(f'return writer.integer(blot_native::{p}_bits(value) as u64,{int(p[1:])//8});')
  else:
   lo,hi=scalar_bounds(p);bits=int(p[1:]) if p not in ('usize','isize') else 64
   if p=='usize':lines.append('if value<0 {return Error.artifact_limit;}')
   elif p not in ('u64','i64','isize'):
    lines.append(f'if value<{lo} || value>{hi} {{return Error.invalid_artifact;}}')
   if bits<=8:lines.append('return writer.integer(value as! u64,1);')
   elif p[0]=='u':lines.append('return writer.varint(value as u64);')
   else:lines.append('return writer.varint(zigzag(value as i64));')
 elif kind=='enum':
  if t in G and G[t][0]=='enum':
   valid={target:ordinal for field,ordinal,target in d['variants']};lines.append('match value {')
   for target,fs in G[t][1]:
    if target in valid:lines.append(f'{t}.{target}=>{{return writer.varint({valid[target]});}},')
    else:lines.append(f'{t}.{target}=>{{return Error.invalid_artifact;}},')
   lines.append('}')
  else:lines.append('return writer.varint(value as u64);')
 elif kind=='union_tag':lines.append('return writer.varint(value as u64);')
 elif kind=='struct':
  for field,child,target in d['fields']:
   if d['name']=='check.capability_flow.Parameters' and field in ('invocation_arguments','invocation_count'):
    lines.append(f'if value.kind==blot_check_capability_flow::ParameterResult.invoke_inputs {{let error=write_{proc(child)}(writer,value.{target},level+1);if error!=Error.none {{return error;}}}}')
   else:lines.append(f'block {{let error=write_{proc(child)}(writer,value.{target},level+1);if error!=Error.none {{return error;}}}}')
  lines.append('return Error.none;')
 elif kind=='array':
  child=d['children'][0];lines.append(f'for item in value {{let error=write_{proc(child)}(writer,item,level+1);if error!=Error.none {{return error;}}}}return Error.none;')
 elif kind=='slice':
  child=d['children'][0];lines.append('if value.len>writer.remaining || value.len>0xffffffff {return Error.artifact_limit;}writer.remaining-=value.len;let error=writer.varint(value.len as u64);if error!=Error.none {return error;}')
  if child['name']=='u8':lines.append('return writer.append(value);')
  else:lines.append(f'for item in value {{let error=write_{proc(child)}(writer,item,level+1);if error!=Error.none {{return error;}}}}return Error.none;')
 elif kind=='optional':
  child=d['children'][0];lines.append('var flag:u64=0;if value.present {flag=1;}let error=writer.integer(flag,1);if error!=Error.none {return error;}if !value.present {return Error.none;}'+f'return write_{proc(child)}(writer,value.value,level+1);')
 elif kind=='union':
  lines.append('match value {')
  native_targets={v[2] for v in d['variants']}
  for field,ordinal,target,child,fs in d['variants']:
   pattern=f'{t}.{target}' + (' payload' if fs else '')
   expression='Void{}' if child['kind']=='primitive' and child['primitive']=='void' else ('payload.'+fs[0][0] if len(fs)==1 else 'payload')
   lines.append(f'{pattern}=>{{let error=writer.depth(level+1);if error!=Error.none {{return error;}}let error=writer.varint({ordinal});if error!=Error.none {{return error;}}return write_{proc(child)}(writer,{expression},level+1);}},')
  for target,fs in G[t][1]:
   if target not in native_targets:lines.append(f'{t}.{target}=>{{return Error.invalid_artifact;}},')
  lines.append('}')
 lines.append('}\n')
 # Decode against a statically typed owner. All allocated runs are journaled
 # before children, so any error rolls back even partial records/arrays.
 lines.append(f'fn read_{name}<O>(reader:Decoder<O>&,level:i64)->{t},Error {{let error=reader.depth(level);if error!=Error.none {{{error_return(d)}}}')
 if kind=='primitive':
  p=d['primitive']
  if p=='void':lines.append('return Void{},Error.none;')
  elif p=='bool':lines.append('let bits,error=reader.integer(1);if error!=Error.none {'+error_return(d)+'}if bits>1 {'+error_return(d,'Error.invalid_artifact')+'}return bits!=0,Error.none;')
  elif p in ('f32','f64'):lines.append(f'let bits,error=reader.integer({int(p[1:])//8});if error!=Error.none {{{error_return(d)}}}return blot_native::{p}_from_bits(bits as '+('u32' if p=='f32' else 'u64')+'),Error.none;')
  else:
   bits=int(p[1:]) if p not in ('usize','isize') else 64;lo,hi=scalar_bounds(p);raw='reader.integer(1)' if bits<=8 else 'reader.varint()'
   lines.append(f'let bits,error={raw};if error!=Error.none {{{error_return(d)}}}')
   if p.startswith('i') or p=='isize':
    if bits<=8:lines.append('var number=bits as i64;if bits>=128 {number-=256;}')
    else:lines.append('let number=unzigzag(bits);')
    if bits<64:lines.append(f'if number<{lo} || number>{hi} {{{error_return(d,"Error.invalid_artifact")}}}')
    lines.append(f'return number as {t},Error.none;')
   else:
    if hi<0xffffffffffffffff:lines.append(f'if bits>{hi} {{{error_return(d,"Error.artifact_limit" if p=="usize" else "Error.invalid_artifact")}}}')
    lines.append(f'return bits as {t},Error.none;')
 elif kind in ('enum','union_tag'):
  lines.append('let raw,error=reader.varint();if error!=Error.none {'+error_return(d)+'}')
  for field,ordinal,target in d['variants']:
   expression=t+'.'+target if t in G and G[t][0]=='enum' else str(ordinal)+' as '+t
   lines.append(f'if raw=={ordinal} {{return {expression},Error.none;}}')
  lines.append(error_return(d,'Error.invalid_artifact'))
 elif kind=='struct':
  lines.append(f'var result=default<{t}>();')
  for field,child,target in d['fields']:
   code=step(d,f'read_{proc(child)}(reader,level+1)','result.'+target)
   if d['name']=='check.capability_flow.Parameters' and field in ('invocation_arguments','invocation_count'):code='if result.kind==blot_check_capability_flow::ParameterResult.invoke_inputs {'+code+'}'
   lines.append(code)
  if d['name']=='check.capability_flow.Parameters':lines.append('if !result.valid() {'+error_return(d,'Error.invalid_artifact')+'}')
  if t in G and G[t][0]=='struct' and 'owner_id' in dict(G[t][1]):lines.append('result.owner_id=blot_native::fresh_owner_id();')
  if d['name']=='check.core.Module':
   lines.append('var packages=false;for node in result.nodes {if node.tag==blot_check_core::Tag.package_pack {packages=true;break;}}if packages && result.nodes.len!=0 {let lane,error=reader.owner.alloc<u32>(result.nodes.len);if error!=Error.none {'+error_return(d)+'}for node,index in result.nodes {lane[index]=node.a;}result.package_payloads=lane;}')
  lines.append('return result,Error.none;')
 elif kind=='array':
  child=d['children'][0];lines.append(f'var result=default<{t}>();for index in 0..{d["count"]} '+step(d,f'read_{proc(child)}(reader,level+1)','result[index]')+'return result,Error.none;')
 elif kind=='slice':
  child=d['children'][0];w=minimum(child);lines.append('let count,error=reader.varint();if error!=Error.none {'+error_return(d)+'}if count>0xffffffff {'+error_return(d,'Error.invalid_artifact')+'}if reader.remaining<0 || count>reader.remaining as u64 {'+error_return(d,'Error.artifact_limit')+'}reader.remaining-=count as i64;')
  if w:lines.append(f'if count>((reader.bytes.len-reader.at)/{w}) as u64 {{{error_return(d,"Error.invalid_artifact")}}}')
  lines.append(f'let result,error=reader.owner.alloc<{actual(child)}>(count as i64);if error!=Error.none {{{error_return(d)}}}')
  if child['name']=='u8':lines.append('let bytes,error=reader.take(count as i64);if error!=Error.none {'+error_return(d)+'}for byte,index in bytes {result[index]=byte;}')
  else:lines.append('for index in 0..count as i64 '+step(d,f'read_{proc(child)}(reader,level+1)','result[index]'))
  lines.append('return result,Error.none;')
 elif kind=='optional':
  child=d['children'][0];lines.append('let flag,error=reader.integer(1);if error!=Error.none {'+error_return(d)+'}if flag==0 {return blot_support::none<'+actual(child)+'>(),Error.none;}if flag!=1 {'+error_return(d,'Error.invalid_artifact')+'}let value,error=read_'+proc(child)+'(reader,level+1);if error!=Error.none {'+error_return(d)+'}return blot_support::some(value),Error.none;')
 elif kind=='union':
  lines.append('let error=reader.depth(level+1);if error!=Error.none {'+error_return(d)+'}let tag,error=reader.varint();if error!=Error.none {'+error_return(d)+'}')
  for field,ordinal,target,child,fs in d['variants']:
   expression=t+'.'+target
   if fs:expression+='{'+','.join(f'{fn}:value' for fn,ft in fs)+'}'
   lines.append(f'if tag=={ordinal} {{let value,error=read_{proc(child)}(reader,level+1);if error!=Error.none {{{error_return(d)}}}return {expression},Error.none;}}')
  lines.append(error_return(d,'Error.invalid_artifact'))
 lines.append('}\n')
# Public overload dispatch is per distinct root type; internal domains never
# collapse merely because two native scalar enums share Goose u8 storage.
seen_roots=set()
for d in ROOTS:
 t=actual(d)
 if t in seen_roots:continue
 seen_roots.add(t);name=proc(d)
 lines.append(f'fn writeValue(writer:Encoder&,value:{t},level:i64)->Error {{return write_{name}(writer,value,level);}}\n')
 lines.append(f'fn readValue<O>(reader:Decoder<O>&,witness:{t},level:i64)->{t},Error {{return read_{name}(reader,level);}}\n')
 lines.append(f'fn describe(hasher:blot_support_blake3::State&,value:{t}) {{describe_{name}(hasher,value);}}\n')
Path('compiler-goose/src/reuse/dependency_format_codecs.goose').write_text(''.join(lines))
# Decode allocation journal: one finite ADT and reusable typed pool per actual
# Goose element type. Rollback/deinit never traverse partially built records.
elements={}
for d in ORDER:
 if d['kind']=='slice':elements.setdefault(actual(d['children'][0]),d['children'][0])
elements.setdefault('u32',DESCS['u32'])
owner=['// Typed archive decode runs; this owner is distinct from Payload.Owner.\nnamespace blot_reuse_dependency_format;\n']+['import '+p+';\n' for p in sorted(imports)]
owner+=['struct Owner {lease:u32=0,generation:u64=0}\n','enum Run {inactive,\n']
for t in elements:owner.append('run_'+ident(t)+'{values:'+t+'[:]},\n')
owner+=['}\n','struct Link {run:Run=Run.inactive,next:u32=0}\n','struct Lease {head:u32=0,generation:u64=0,live:bool=false}\n','reusable var links:Link[>..]=[];\n','reusable var owners:Lease[>..]=[];\n']
for t in elements:owner.append('reusable[] var pool_'+ident(t)+':'+t+'[>..]=[];\n')
owner.append('''fn valid(self:const Owner&)->bool {return self.lease!=0 && self.lease-1<owners.len && owners[self.lease-1].live && owners[self.lease-1].generation==self.generation;}
fn initOwner()->Owner,Error {if owners.len>=0xffffffff {return Owner{},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=owners.alloc_index(Lease{generation:generation,live:true});return Owner{(at+1) as u32,generation},Error.none;}
fn remember(self:Owner&,run:Run)->Error {assert(self.valid());if links.len>=0xffffffff {return Error.out_of_memory;}let at=links.alloc_index(Link{run,owners[self.lease-1].head});owners[self.lease-1].head=(at+1) as u32;return Error.none;}
fn mark(self:const Owner&)->u32 {assert(self.valid());return owners[self.lease-1].head;}
fn freeRun(run:Run) {match run {Run.inactive=>{},
''')
for t in elements:owner.append('Run.run_'+ident(t)+' payload=>{if payload.values.len!=0 {pool_'+ident(t)+'.free_slice(payload.values);}},\n')
owner.append('''}}
fn rollback(self:Owner&,mark:u32) {assert(self.valid());var head=owners[self.lease-1].head;while head!=mark {assert(head!=0);let at=head-1;let link=links[at];head=link.next;freeRun(link.run);links[at]=Link{};links.free(at);}owners[self.lease-1].head=mark;}
fn deinit(self:Owner&) {if self.lease==0 {return;}assert(self.valid());self.rollback(0);let at=self.lease-1;owners[at]=Lease{};owners.free(at);self=Owner{};}
fn alloc<T>(self:Owner&,length:i64)->T[:],Error {return allocate(self,default<T>(),length);}
''')
for t in elements:
 tag=ident(t);owner.append(f'''fn allocate(self:Owner&,witness:{t},length:i64)->{t}[:],Error {{assert(self.valid());if length<0 {{return [],Error.artifact_limit;}}if length==0 {{return [],Error.none;}}let values=pool_{tag}.alloc_slice(length);let error=self.remember(Run.run_{tag}{{values}});if error!=Error.none {{pool_{tag}.free_slice(values);return [],error;}}return values,Error.none;}}
fn mutable(self:const Owner&,values:const {t}[:])->{t}[:] {{assert(self.valid());if values.len==0 {{return [];}}var link=owners[self.lease-1].head;while link!=0 {{let entry=links[link-1];match entry.run {{Run.run_{tag} run=>{{if run.values .== values {{return run.values;}}}},_=>{{}}}}link=entry.next;}}abort("archive slice is outside its owner");}}
''')
Path('compiler-goose/src/reuse/dependency_format_owners.goose').write_text(''.join(owner))
# Explicit partial-field cleanup remains available for record constructors.
# It unlinks exact completed typed runs; unfinished decoder records are instead
# rolled back to their caller's mark by decodeWithOwner.
release_lines=['\n// Native field-order partial cleanup for completed aggregate fields.\n']
for d in ORDER:
 t=actual(d);name=proc(d);kind=d['kind'];release_lines.append(f'fn release_{name}(owner:Owner&,value:{t}) {{')
 if kind=='struct':
  for field,child,target in d['fields']:release_lines.append(f'release_{proc(child)}(owner,value.{target});')
  if d['name']=='check.core.Module':release_lines.append('owner.releaseSlice(value.package_payloads);')
 elif kind=='slice':
  child=d['children'][0]
  if child['kind'] not in ('primitive','enum','union_tag'):release_lines.append(f'for item in value {{release_{proc(child)}(owner,item);}}')
  release_lines.append('owner.releaseSlice(value);')
 elif kind=='array':release_lines.append(f'for item in value {{release_{proc(d["children"][0])}(owner,item);}}')
 elif kind=='optional':release_lines.append(f'if value.present {{release_{proc(d["children"][0])}(owner,value.value);}}')
 elif kind=='union':
  release_lines.append('match value {');targets=set()
  for field,ordinal,target,child,fs in d['variants']:
   targets.add(target);pattern=t+'.'+target+(' payload' if fs else '');expr='Void{}' if child['name']=='void' else ('payload.'+fs[0][0] if len(fs)==1 else 'payload');release_lines.append(pattern+'=>{release_'+proc(child)+'(owner,'+expr+');},')
  for target,fs in G[t][1]:
   if target not in targets:release_lines.append(t+'.'+target+'=>{},')
  release_lines.append('}')
 release_lines.append('}\n')
partial=set()
for d in ORDER:
 if d['kind']!='struct' or actual(d) in partial:continue
 partial.add(actual(d));release_lines.append(f'fn deinitFields(owner:Owner&,value:{actual(d)}&,initialized:i64) {{')
 for index,(field,child,target) in enumerate(d['fields']):release_lines.append(f'if initialized>{index} {{release_{proc(child)}(owner,value.{target});}}')
 release_lines.append('}\n')
with Path('compiler-goose/src/reuse/dependency_format_codecs.goose').open('a') as file:file.write(''.join(release_lines))
release_owner=[]
for t in elements:
 tag=ident(t);release_owner.append(f'''fn releaseSlice(self:Owner&,values:const {t}[:]) {{assert(self.valid());if values.len==0 {{return;}}var previous:u32=0;var link=owners[self.lease-1].head;while link!=0 {{let at=link-1;let entry=links[at];match entry.run {{Run.run_{tag} run=>{{if run.values .== values {{if previous==0 {{owners[self.lease-1].head=entry.next;}}else {{links[previous-1].next=entry.next;}}freeRun(entry.run);links[at]=Link{{}};links.free(at);return;}}}},_=>{{}}}}previous=link;link=entry.next;}}abort("partial field cleanup requires its exact archive owner");}}
''')
with Path('compiler-goose/src/reuse/dependency_format_owners.goose').open('a') as file:file.write(''.join(release_owner))
