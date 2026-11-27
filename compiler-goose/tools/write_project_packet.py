# Source authoring: close the finite set of copied project data types, then emit
# concrete enum/array codecs and typed allocation families. No compiler/checks.
from pathlib import Path
import re,json
R=Path(__file__).resolve().parents[1]/'src'
from source_model import clean,balanced,split
from normalize_syntax import normalize,finish_syntax
(R.parent/'build').mkdir(parents=True,exist_ok=True)
D={};PATHS={}
for path in sorted(R.rglob('*.goose')):
 if path.name.startswith('_') or (path.parent == R and 'probe' in path.stem):continue
 s=clean(path.read_text());m=re.search(r'namespace\s+(\w+)\s*;',s)
 if not m:continue
 ns=m[1];module_path=path.relative_to(R).with_suffix('').as_posix().replace('/','.')
 PATHS.setdefault(ns,module_path)
 if ns=='squid_'+module_path.replace('.','_'):PATHS[ns]=module_path
 for m in re.finditer(r'\b(struct|enum|type)\s+(\w+)\s*(<[^>{}]+>)?\s*(\{|=)',s):
  kind,name,params,tok=m.groups();key=ns+'::'+name
  if tok=='=':
   if kind=='type':D[key]=('alias',[],s[m.end():s.find(';',m.end())].strip(),ns)
  else:
   end=balanced(s,m.end()-1);body=s[m.end():end];data=[]
   if kind=='struct':
    for part in split(body):
     fm=re.match(r'^(\w+)\s*:\s*(.*)$',part,re.S)
     if fm:data.append((fm[1],split(fm[2],'=')[0].strip()))
   else:
    for part in split(body):
     vm=re.fullmatch(r'(\w+)\s*(?:\{(.*)\})?',part,re.S)
     if vm:
      fs=[]
      for field in split(vm[2] or ''):
       fm=re.match(r'^(\w+)\s*:\s*(.*)$',field,re.S)
       if fm:fs.append((fm[1],split(fm[2],'=')[0].strip()))
      data.append((vm[1],fs))
   D[key]=(kind,split((params or '<>')[1:-1]),data,ns)
def q(t,ns,subs={}):
 return re.sub(r'(?<![\w:])\b\w+\b(?!::)',lambda m:subs.get(m[0],ns+'::'+m[0] if ns+'::'+m[0] in D else m[0]),t)
def resolve(t,ns='squid_project_packet'):
 t=q(t,ns).strip();t=re.sub(r'^const\s+','',t)
 # Normalize aliases while keeping numeric domains as actual storage types.
 m=re.fullmatch(r'(\w+::\w+)(?:<(.*)>)?',t,re.S)
 if m and m[1] in D:
  k,ps,data,owner=D[m[1]]
  if k=='alias':return resolve(q(data,owner,dict(zip(ps,split(m[2] or '')))),owner)
 return t
SPECIAL={
 'squid_check_check::Checked':{'owner','types','parameter_patterns'},
 'squid_check_types::Store':None,
 'squid_check_parameter_patterns::Store':None,
 'squid_parse_ast::Tree':None,
 'squid_parse_symbols::Pool':None,
 'squid_check_type_store_snapshot::Snapshot':{'lease_index','generation'},
 'squid_check_type_store_snapshot::State':{'store_owner_id'},
}
ROOTS=[
 'squid_check_check::Checked','squid_parse_ast::Tree','squid_parse_symbols::Pool',
 'squid_check_check::ModuleOrigins','squid_reuse_project_check::Diagnostic','squid_reuse_project_check::Export',
 'squid_reuse_project::Range','squid_reuse_project::Import','squid_reuse_project::Diagnostic','squid_reuse_project::Lowering','squid_reuse_project::InputMode',
 'squid_reuse_frozen_dependency::Module',
 'squid_check_type_store_snapshot::Snapshot','squid_check_parameter_patterns::Node',
 'squid_work_counters::Frontend','squid_phase_profile::WorkerContext','squid_phase_profile::WorkerSnapshot',
]
CUSTOM_CHILDREN={
 'squid_parse_ast::Tree':[],
 'squid_parse_symbols::Pool':['u8[:]','squid_parse_symbols::Entry[:]','u32[:]'],
 'squid_check_types::Store':['squid_check_type_store_snapshot::Snapshot'],
 'squid_check_parameter_patterns::Store':['squid_check_parameter_patterns::Node[:]','u32[:]'],
}
# Every AST owner table is explicit, preserving actual tag/ID ordinals.
for field,t in D['squid_parse_ast::Tree'][2]:
 if t.endswith('&'):
  bt=resolve(t[:-1],'squid_parse_ast');info=D.get(bt)
  if info:
   item=dict(info[2]).get('items')
   if item:CUSTOM_CHILDREN['squid_parse_ast::Tree'].append(q(item,info[3]))
PRIM={'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}
SEEN={};SLICES={};ARRAYS=set();ENUMS={};STRUCTS={};IMPORTS=set()
def visit(t,ns='squid_project_packet'):
 t=resolve(t,ns);t=re.sub(r'\s+',' ',t).strip()
 if t in SEEN:return
 SEEN[t]=True
 for n in re.findall(r'\b(\w+)::',t):
  if n in PATHS:IMPORTS.add(PATHS[n])
 if t in PRIM:return
 m=re.fullmatch(r'(.+)\[(:|\d+)\]',t)
 if m:
  inner=resolve(m[1],ns);visit(inner,ns)
  if m[2]==':':SLICES[inner]=True
  else:ARRAYS.add((inner,int(m[2])))
  return
 if t.endswith('?'):
  inner=resolve(t[:-1],ns);SLICES[inner]=True;visit(inner,ns);return
 if t.startswith('dictionary_slot<'):
  args=split(t[t.index('<')+1:-1]);visit(args[0],ns);visit(args[1],ns);return
 if t.startswith('squid_support::Option<'):
  visit(t[t.index('<')+1:-1],ns);return
 if t in CUSTOM_CHILDREN:
  for child in CUSTOM_CHILDREN[t]:visit(child,ns)
  return
 if '&' in t or '[>' in t or 'dictionary<' in t:raise ValueError(('unowned process field',t))
 m=re.fullmatch(r'(\w+::\w+)(?:<(.*)>)?',t,re.S)
 if not m or m[1] not in D:raise ValueError(('undeclared process data type',t))
 kind,params,data,owner=D[m[1]];subs=dict(zip(params,split(m[2] or '')))
 if kind=='enum':
  ENUMS[t]=[(name,[(f,resolve(q(ty,owner,subs),owner)) for f,ty in fs]) for name,fs in data]
  for name,fs in ENUMS[t]:
   for f,ty in fs:visit(ty,owner)
 elif kind=='struct':
  STRUCTS[t]=data
  skip=SPECIAL.get(t,set())
  for name,ty in data:
   if skip is not None and name in skip:continue
   visit(q(ty,owner,subs),owner)
 else:raise ValueError((kind,t))
for root in ROOTS:visit(root)
# Header vectors and mutable body data also allocate exact typed slices.
for t in ['u8','u32','squid_reuse_project_check::Export','squid_reuse_project_check::Diagnostic','squid_reuse_frozen_dependency::Module','squid_check_parameter_patterns::Node','squid_reuse_project::Import','squid_reuse_project::Diagnostic','bool']:
 t=resolve(t);visit(t);SLICES[t]=True
for t in list(SLICES):visit(t)
# Concrete code below is emitted after the contexts file has defined all roots.
def ident(t):return re.sub(r'[^A-Za-z0-9_]','_',t)
imports='\n'.join('import '+x+';' for x in sorted(IMPORTS))
code=['// Concrete data domains for the same-executable copied worker protocol.','namespace squid_project_packet;','import binary;',imports,'import .project_packet;']
for typ in ['u8','i8']:
 code.append(f'fn put(self:Writer&,value:{typ}) {{if !self.room(1) {{return;}}self.output.push(value as! u8);}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{if !self.available(1) {{return;}}value=self.bytes[self.at] as! {typ};self.at+=1;}}')
for typ in ['u16','i16']:
 code.append(f'fn put(self:Writer&,value:{typ}) {{if !self.room(2) {{return;}}let bits=value as! u16;var buf:u8[2]=[bits as! u8,(bits>>8) as! u8];self.output.append(buf);}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{if !self.available(2) {{return;}}value=binary::u16le(self.bytes,self.at) as! {typ};self.at+=2;}}')
for typ in ['u32','i32']:
 code.append(f'fn put(self:Writer&,value:{typ}) {{if !self.room(4) {{return;}}let bits=value as! u32;var buf:u8[4]=[bits as! u8,(bits>>8) as! u8,(bits>>16) as! u8,(bits>>24) as! u8];self.output.append(buf);}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{if !self.available(4) {{return;}}value=binary::u32le(self.bytes,self.at) as! {typ};self.at+=4;}}')
for typ in ['u64','i64']:
 code.append(f'fn put(self:Writer&,value:{typ}) {{if !self.room(8) {{return;}}let bits=value as! u64;var buf:u8[8]=[bits as! u8,(bits>>8) as! u8,(bits>>16) as! u8,(bits>>24) as! u8,(bits>>32) as! u8,(bits>>40) as! u8,(bits>>48) as! u8,(bits>>56) as! u8];self.output.append(buf);}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{if !self.available(8) {{return;}}value=binary::u64le(self.bytes,self.at) as! {typ};self.at+=8;}}')
for typ,bits in [('f32','u32'),('f64','u64')]:
 code.append(f'fn put(self:Writer&,value:{typ}) {{put(self,squid_native::{typ}_bits(value));}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{var bits:{bits}=0;get(self,bits);value=squid_native::{typ}_from_bits(bits);}}')
for t,values in ENUMS.items():
 body=[]
 for i,(name,fs) in enumerate(values):
  pat=name
  if fs:pat+=' payload'
  body.append(pat+'=>{put(self,'+str(i)+' as u32);'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,payload.'+f+');' for f,ty in fs)+'},')
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}match value {'+''.join(body)+'}self.depth--;}')
 body=[]
 for i,(name,fs) in enumerate(values):
  decoded=[]
  for f,ty in fs:
   if ty.endswith('?'):decoded.append('let decoded_'+f+':'+ty+'=readOptional(self,default<'+ty[:-1]+'>());')
   else:decoded.append('var decoded_'+f+':'+ty+'=default<'+ty+'>();get(self,decoded_'+f+');')
  temp=''.join(decoded)
  ctor=t+'.'+name
  if fs:ctor+='{'+','.join(f+':decoded_'+f for f,ty in fs)+'}'
  body.append(str(i)+'=>{'+temp+'value='+ctor+';},')
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}var tag:u32=0;get(self,tag);if self.failure==Error.none {match tag {'+''.join(body)+'_=>{self.failure=Error.invalid_artifact;},}}self.depth--;}')
for t,n in sorted(ARRAYS):
 code.append(f'fn put(self:Writer&,value:{t}[{n}]) {{for item in value {{put(self,item);}}}}')
 code.append(f'fn get(self:Reader&,value:{t}[{n}]&) {{for &item in value {{get(self,item);}}}}')
# Core private IDs/derived child lane do not cross the process protocol.
for t,skip in [('squid_check_core::Module',{'owner_id'}),('squid_check_core::Types',{'owner_id'}),('squid_check_frozen_types::Graph',{'owner_id'}),('squid_check_type_store_snapshot::Snapshot',{'lease_index','generation'}),('squid_check_type_store_snapshot::State',{'store_owner_id'})]:
 if t not in SEEN:continue
 data=D[t][2];owner=D[t][3]
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,value.'+f+');' for f,ty in data if f not in skip)+'self.depth--;}')
 trailer=''
 if t in ('squid_check_core::Module','squid_check_core::Types','squid_check_frozen_types::Graph') and any(f=='owner_id' for f,ty in data):trailer='value.owner_id=squid_native::fresh_owner_id();'
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}'+''.join('get(self,value.'+f+');' for f,ty in data if f not in skip)+trailer+'self.depth--;}')
# Explicit nominal heads avoid ties between the generic record, slice and
# optional helpers. Reader/writer inference keeps unused codecs uninstantiated.
private={'squid_check_core::Module','squid_check_core::Types','squid_check_frozen_types::Graph'}
for t in sorted(STRUCTS):
 if t in private or t in SPECIAL:continue
 owner=D[t.split('<')[0]][3]
 fields=[(f,resolve(q(ty,owner),owner)) for f,ty in STRUCTS[t] if f not in SPECIAL.get(t,set())]
 # The hot two-word descriptor has a handwritten wire-compatible codec.
 if t == 'squid_check_types::List':
  assert fields == [('start', 'u32'), ('len', 'u32')]
  continue
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,value.'+f+');' for f,ty in fields)+'self.depth--;}')
 parts=[]
 for f,ty in fields:
  if ty.endswith('?'):parts.append('value.'+f+' .= readOptional(self,default<'+ty[:-1]+'>());')
  else:parts.append('get(self,value.'+f+');')
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}'+''.join(parts)+'self.depth--;}')
code=[line.replace('fn put(self:Writer&','fn put<PacketWriter>(self:PacketWriter&').replace('fn get(self:Reader&','fn get<PacketReader>(self:PacketReader&') for line in code]
# Contiguous tables selected by profiling copied worker packets. Goose checks
# that their records have a flat representation and verifies the decoded image.
# Never include structs that transitively contain a tagged union (an enum with
# payload variants): payloadless variants leave inactive union bytes
# uninitialized, making raw flat images non-deterministic across processes.
FLAT_SLICES = (
    'squid_check_core::Associated',
    'squid_check_core::Binding',
    'squid_check_core::Body',
    'squid_check_core::ClosureInfo',
    'squid_check_core::Constructor',
    'squid_check_core::Contract',
    'squid_check_core::DeclarationDependencies',
    'squid_check_core::DependencyMember',
    'squid_check_core::Diagnostic',
    'squid_check_core::ErasedDeclarationReference',
    'squid_check_core::LoopInfo',
    'squid_check_core::MatchArm',
    'squid_check_core::MatchInfo',
    'squid_check_core::Node',
    'squid_check_core::Nominal',
    'squid_check_core::Obligation',
    'squid_check_core::OperationName',
    'squid_check_core::OperationValue',
    'squid_check_core::Parameter',
    'squid_check_core::Pattern',
    'squid_check_core::Primitive',
    'squid_check_core::Projection',
    'squid_check_core::TypeTag',
    'squid_check_core::UpdateInfo',
    'squid_check_core::UpdateStep',
    'squid_check_parameter_patterns::Node',
    'squid_check_types::Node',
    'squid_check_types::Obligation',
    'squid_check_types::Operation',
    'squid_reuse_frozen_dependency::Export',
    'squid_reuse_principal_interface::Associated',
    'squid_reuse_principal_interface::Binding',
    'squid_reuse_principal_interface::Constructor',
    'squid_reuse_principal_interface::Contract',
    'squid_reuse_principal_interface::ContractMember',
    'squid_reuse_principal_interface::EffectFamily',
    'squid_reuse_principal_interface::EffectTemplate',
    'squid_reuse_principal_interface::Implementation',
    'squid_reuse_principal_interface::ImplementationMember',
    'squid_reuse_principal_interface::MemberTemplate',
    'squid_reuse_principal_interface::Nominal',
    'squid_reuse_project_check::Export',
)
def has_tagged_union(t, ns='squid_project_packet'):
 t = resolve(t, ns)
 if t.startswith('squid_support::Option<'):
  return has_tagged_union(t[len('squid_support::Option<'):-1], ns)
 m = re.fullmatch(r'(.+)\[\d+\]', t)
 if m:
  return has_tagged_union(m[1], ns)
 if t not in D:
  return False
 kind, params, data, owner = D[t]
 if kind == 'enum':
  return any(fs for _, fs in data)
 if kind == 'struct':
  return any(has_tagged_union(ty, owner) for _, ty in data)
 return False
VERIFIED_FLAT_SLICES = {'squid_reuse_principal_interface::Binding'}
for t in FLAT_SLICES:
 assert t in SLICES, t
 assert not has_tagged_union(t), f'FLAT_SLICES type {t} contains a tagged union with uninitialized inactive bytes'
 if t in VERIFIED_FLAT_SLICES:
  code.append(f'fn put(receiver:Writer&,value:const {t}[:]) {{putFlat(receiver,value);}}')
  code.append(f'fn get(receiver:Reader&,value:{t}[:]& ) {{getFlat(receiver,value);}}')
 else:
  code.append(f'fn put(receiver:Writer&,value:const {t}[:]) {{putRawFlat(receiver,value);}}')
  code.append(f'fn get(receiver:Reader&,value:{t}[:]& ) {{getRawFlat(receiver,value);}}')
syntax_types=PRIM|{name.split('::')[-1] for name in D}
(R/'support/project_packet_codecs.goose').write_text(finish_syntax(normalize('\n'.join(code)+'\n',syntax_types)))
# Every family is concrete; no generic cast, byte arena or ownership erasure.
owner=['// Typed bounded decode journal. The owner is shared only within one process.','namespace squid_project_packet;',imports,'import .project_packet;','struct Owner {slot:u32=0,generation:u64=0}','enum Run {']
for t in sorted(SLICES):owner.append('run_'+ident(t)+' {values:'+t+'[:]},')
owner+=['}','struct Link {value:Run,next:u32=0}','struct Lease {generation:u64=0,live:bool=false,references:u64=1,head:u32=0}','reusable var leases:Lease[>..]=[];','reusable var links:Link[>..]=[];']
for t in sorted(SLICES):owner.append('reusable[] var pool_'+ident(t)+':'+t+'[>..]=[];')
owner+=['fn valid(self:Owner)->bool {return self.slot!=0&&self.slot-1<leases.len&&leases[self.slot-1].live&&leases[self.slot-1].generation==self.generation;}','fn initOwner()->Owner,Error {if leases.len>=0xffffffff {return Owner{..},Error.out_of_memory;}let generation=squid_native::fresh_owner_id();let at=leases.alloc_index(Lease{generation:generation,live:true,..});return Owner{(at+1) as u32,generation},Error.none;}','fn retain(self:Owner)->Owner,Error {if !self.valid() {return Owner{..},Error.invalid_artifact;}let state:Lease&=leases[self.slot-1];if state.references==0xffffffffffffffff {return Owner{..},Error.dependency_limit;}state.references++;return self,Error.none;}']
for t in sorted(SLICES):
 owner.append('fn allocate<PacketOwner>(self:PacketOwner&,length:i64,witness:'+t+')->'+t+'[:],Error {if !self.valid()||length<0||length>element_limit {return default<'+t+'[:]>(),Error.invalid_artifact;}if length==0 {return default<'+t+'[:]>(),Error.none;}if links.len>=0xfffffffe {return default<'+t+'[:]>(),Error.out_of_memory;}let run=pool_'+ident(t)+'.alloc_slice(length);let state:Lease& =leases[self.slot-1];let at=links.alloc_index(Link{Run.run_'+ident(t)+'{run},state.head});state.head=(at+1) as u32;return run,Error.none;}')
# Only Checked's retained packet slices need public header observation.
observe_types=set()
for key in ['squid_check_check::Checked','squid_check_check::EditorCapture']:
 for field,ty in D[key][2]:
  ty=resolve(ty,D[key][3])
  if ty.endswith('[:]'):observe_types.add(resolve(ty[:-3],D[key][3]))
for t in sorted(observe_types):
 if t not in SLICES:raise ValueError('Unknown Checked packet run '+t)
 for method,qual in [('view',''),('readView','const ')]:
  owner.append('fn '+method+'(self:Owner,values:'+qual+t+'[:])->'+qual+t+'[:] {assert(self.valid());if values.len==0 {return default<'+qual+t+'[:]>();}var next=leases[self.slot-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_'+ident(t)+' run=>{if squid_support::same_slice_identity(values,run.values) {let owned=pool_'+ident(t)+'.realloc_slice(run.values,run.values.len);let start=pool_'+ident(t)+'.index_of(owned[0]);return pool_'+ident(t)+'[start..start+owned.len];}},_=>{}}}abort("packet view must name this owner\'s exact live typed run");}')
owner.append('fn deinit(self:Owner&) {if self.slot==0 {return;}assert(self.valid());let state:Lease&=leases[self.slot-1];assert(state.references!=0);state.references--;if state.references==0 {var next=state.head;while next!=0 {let at=next-1;let link=links[at];next=link.next;match link.value {')
for t in sorted(SLICES):owner.append('Run.run_'+ident(t)+' value=>{pool_'+ident(t)+'.free_slice(value.values);},')
owner.append('}links.free(at);}state.live=false;leases.free(self.slot-1);}self=Owner{..};}')
(R/'support/project_packet_owners.goose').write_text(finish_syntax(normalize('\n'.join(owner)+'\n',syntax_types)))
(R.parent/'build/project-packet-model.json').write_text(json.dumps({'definitions':D,'roots':ROOTS,'seen':list(SEEN),'slices':list(SLICES),'imports':sorted(IMPORTS),'special_children':CUSTOM_CHILDREN},indent=2))
