# Source authoring: close the finite set of copied project data types, then emit
# concrete enum/array codecs and typed allocation families. No compiler/checks.
from pathlib import Path
import re,json
R=Path(__file__).resolve().parents[1]/'src'
from source_model import clean,balanced,split
(R.parent/'build').mkdir(parents=True,exist_ok=True)
D={};PATHS={}
for path in R.rglob('*.goose'):
 s=clean(path.read_text());m=re.search(r'namespace\s+(\w+)\s*;',s)
 if not m:continue
 ns=m[1];PATHS.setdefault(ns,path.relative_to(R).with_suffix('').as_posix().replace('/','.'))
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
def resolve(t,ns='blot_project_packet'):
 t=q(t,ns).strip();t=re.sub(r'^const\s+','',t)
 # Normalize aliases while keeping numeric domains as actual storage types.
 m=re.fullmatch(r'(\w+::\w+)(?:<(.*)>)?',t,re.S)
 if m and m[1] in D:
  k,ps,data,owner=D[m[1]]
  if k=='alias':return resolve(q(data,owner,dict(zip(ps,split(m[2] or '')))),owner)
 return t
SPECIAL={
 'blot_check_check::Checked':{'owner','types','parameter_patterns'},
 'blot_check_types::Store':None,
 'blot_check_parameter_patterns::Store':None,
 'blot_parse_ast::Tree':None,
 'blot_parse_symbols::Pool':None,
 'blot_reuse_body_check_cache::Cache':None,
 'blot_reuse_body_check_cache::Body':{'owner'},
 'blot_reuse_body_check_cache::Chunk':{'references','graph_owner','live'},
 'blot_check_type_store_snapshot::Snapshot':{'lease_index','generation'},
 'blot_check_type_store_snapshot::State':{'store_owner_id'},
}
ROOTS=[
 'blot_check_check::Checked','blot_parse_ast::Tree','blot_parse_symbols::Pool',
 'blot_check_check::ModuleOrigins','blot_reuse_project_check::Diagnostic','blot_reuse_project_check::Export',
 'blot_reuse_project::Import','blot_reuse_project::Diagnostic','blot_reuse_project::Lowering','blot_reuse_project::InputMode',
 'blot_reuse_frozen_dependency::Module','blot_reuse_body_check_cache::Cache',
 'blot_check_type_store_snapshot::Snapshot','blot_check_parameter_patterns::Node',
 'blot_reuse_body_check_cache::Chunk','blot_reuse_body_check_cache::Body',
 'blot_work_counters::Frontend','blot_phase_profile::WorkerContext','blot_phase_profile::WorkerSnapshot',
]
CUSTOM_CHILDREN={
 'blot_parse_ast::Tree':[],
 'blot_parse_symbols::Pool':['u8[:]','blot_parse_symbols::Entry[:]','u32[:]'],
 'blot_check_types::Store':['blot_check_type_store_snapshot::Snapshot'],
 'blot_check_parameter_patterns::Store':['blot_check_parameter_patterns::Node[:]','u32[:]'],
 'blot_reuse_body_check_cache::Cache':['blot_reuse_body_check_cache::Chunk','u32[:]','dictionary_slot<const u8[:],i64>[:]'],
}
# Every AST owner table is explicit, preserving actual tag/ID ordinals.
for field,t in D['blot_parse_ast::Tree'][2]:
 if t.endswith('&'):
  bt=resolve(t[:-1],'blot_parse_ast');info=D.get(bt)
  if info:
   item=dict(info[2]).get('items')
   if item:CUSTOM_CHILDREN['blot_parse_ast::Tree'].append(q(item,info[3]))
PRIM={'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}
SEEN={};SLICES={};ARRAYS=set();ENUMS={};IMPORTS=set()
def visit(t,ns='blot_project_packet'):
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
 if t.startswith('blot_support::Option<'):
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
  skip=SPECIAL.get(t,set())
  for name,ty in data:
   if skip is not None and name in skip:continue
   visit(q(ty,owner,subs),owner)
 else:raise ValueError((kind,t))
for root in ROOTS:visit(root)
# Header vectors and mutable body data also allocate exact typed slices.
for t in ['u8','u32','blot_reuse_project_check::Export','blot_reuse_project_check::Diagnostic','blot_reuse_frozen_dependency::Module','blot_reuse_body_check_cache::Body','blot_check_parameter_patterns::Node','blot_reuse_project::Import','blot_reuse_project::Diagnostic','blot_reuse_body_check_cache::Cache','bool']:
 t=resolve(t);visit(t);SLICES[t]=True
for t in list(SLICES):visit(t)
# Concrete code below is emitted after the contexts file has defined all roots.
def ident(t):return re.sub(r'[^A-Za-z0-9_]','_',t)
imports='\n'.join('import '+x+';' for x in sorted(IMPORTS))
code=['// Concrete data domains for the same-executable copied worker protocol.','namespace blot_project_packet;',imports,'import .project_packet;']
for typ in ['u8','u16','u32','u64','i8','i16','i32','i64']:
 width=int(typ[1:])//8;u='u'+typ[1:]
 code.append(f'fn put(self:Writer&,value:{typ}) {{if !self.room({width}) {{return;}}let bits=value as! {u};for index in {width} {{self.output.push((bits>>(index*8)) as! u8);}}}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{if !self.available({width}) {{return;}}var bits:{u}=0;for index in {width} {{bits|=(self.bytes[self.at+index] as {u})<<(index*8);}}self.at+={width};value=bits as! {typ};}}')
for typ,bits in [('f32','u32'),('f64','u64')]:
 code.append(f'fn put(self:Writer&,value:{typ}) {{put(self,blot_native::{typ}_bits(value));}}')
 code.append(f'fn get(self:Reader&,value:{typ}&) {{var bits:{bits}=0;get(self,bits);value=blot_native::{typ}_from_bits(bits);}}')
for t,values in ENUMS.items():
 body=[]
 for i,(name,fs) in enumerate(values):
  pat=f'{t}.{name}'
  if fs:pat+=' payload'
  body.append(pat+'=>{put(self,'+str(i)+' as u32);'+''.join('put(self,payload.'+f+');' for f,ty in fs)+'},')
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}match value {'+''.join(body)+'}self.depth--;}')
 body=[]
 for i,(name,fs) in enumerate(values):
  temp=''.join('var '+f+':'+ty+'=default<'+ty+'>();get(self,'+f+');' for f,ty in fs)
  ctor=t+'.'+name
  if fs:ctor+='{'+','.join(f+':'+f for f,ty in fs)+'}'
  body.append(str(i)+'=>{'+temp+'value='+ctor+';},')
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}var tag:u32=0;get(self,tag);if self.failure==Error.none {match tag {'+''.join(body)+'_=>{self.failure=Error.invalid_artifact;},}}self.depth--;}')
for t,n in sorted(ARRAYS):
 code.append(f'fn put(self:Writer&,value:{t}[{n}]) {{for item in value {{put(self,item);}}}}')
 code.append(f'fn get(self:Reader&,value:{t}[{n}]&) {{for &item in value {{get(self,item);}}}}')
# Core private IDs/derived child lane do not cross the process protocol.
for t,skip in [('blot_check_core::Module',{'owner_id','package_payloads'}),('blot_check_core::Types',{'owner_id'}),('blot_check_frozen_types::Graph',{'owner_id'}),('blot_check_type_store_snapshot::Snapshot',{'lease_index','generation'}),('blot_check_type_store_snapshot::State',{'store_owner_id'})]:
 if t not in SEEN:continue
 data=D[t][2];owner=D[t][3]
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join('put(self,value.'+f+');' for f,ty in data if f not in skip)+'self.depth--;}')
 trailer=''
 if t=='blot_check_core::Module':trailer='value.owner_id=blot_native::fresh_owner_id();let lanes,error=self.owner.alloc<u32>(value.nodes.len);if error!=Error.none {self.failure=error;}else {for node,index in value.nodes {lanes[index]=0;if node.tag==blot_check_core::Tag.package_pack {lanes[index]=node.a;}}value.package_payloads=lanes;}'
 elif t in ('blot_check_core::Types','blot_check_frozen_types::Graph'):trailer='value.owner_id=blot_native::fresh_owner_id();'
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}'+''.join('get(self,value.'+f+');' for f,ty in data if f not in skip)+trailer+'self.depth--;}')
(R/'support/project_packet_codecs.goose').write_text('\n'.join(code)+'\n')
# Every family is concrete; no generic cast, byte arena or ownership erasure.
owner=['// Typed bounded decode journal. The owner is shared only within one process.','namespace blot_project_packet;',imports,'import .project_packet;','struct Owner {slot:u32=0,generation:u64=0}','enum Run {']
for t in sorted(SLICES):owner.append('run_'+ident(t)+' {values:'+t+'[:]},')
owner+=['}','struct Link {value:Run,next:u32=0}','struct Lease {generation:u64=0,live:bool=false,references:u64=1,head:u32=0}','reusable var leases:Lease[>..]=[];','reusable var links:Link[>..]=[];']
for t in sorted(SLICES):owner.append('reusable[] var pool_'+ident(t)+':'+t+'[>..]=[];')
owner+=['fn valid(self:Owner)->bool {return self.slot!=0&&self.slot-1<leases.len&&leases[self.slot-1].live&&leases[self.slot-1].generation==self.generation;}','fn initOwner()->Owner,Error {if leases.len>=0xffffffff {return Owner{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=leases.alloc_index(Lease{generation:generation,live:true,..});return Owner{(at+1) as u32,generation},Error.none;}','fn retain(self:Owner)->Owner,Error {if !self.valid() {return Owner{..},Error.invalid_artifact;}let state:Lease&=leases[self.slot-1];if state.references==0xffffffffffffffff {return Owner{..},Error.dependency_limit;}state.references++;return self,Error.none;}']
for t in sorted(SLICES):
 owner.append('fn allocate(self:Owner&,length:i64,witness:'+t+')->'+t+'[:],Error {if !self.valid()||length<0||length>element_limit {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}if links.len>=0xfffffffe {return [],Error.out_of_memory;}let run=pool_'+ident(t)+'.alloc_slice(length);for &item in run {item=default<'+t+'>();}let state:Lease&=leases[self.slot-1];let at=links.alloc_index(Link{Run.run_'+ident(t)+'{run},state.head});state.head=(at+1) as u32;return run,Error.none;}')
owner.append('fn alloc<T>(self:Owner&,length:i64)->T[:],Error {return allocate(self,length,default<T>());}')
owner.append('fn deinit(self:Owner&) {if self.slot==0 {return;}assert(self.valid());let state:Lease&=leases[self.slot-1];assert(state.references!=0);state.references--;if state.references==0 {var next=state.head;while next!=0 {let at=next-1;let link=links[at];next=link.next;match link.value {')
for t in sorted(SLICES):owner.append('Run.run_'+ident(t)+' value=>{pool_'+ident(t)+'.free_slice(value.values);},')
owner.append('}links.free(at);}state.live=false;leases.free(self.slot-1);}self=Owner{..};}')
(R/'support/project_packet_owners.goose').write_text('\n'.join(owner)+'\n')
(R.parent/'build/project-packet-model.json').write_text(json.dumps({'definitions':D,'roots':ROOTS,'seen':list(SEEN),'slices':list(SLICES),'imports':sorted(IMPORTS),'special_children':CUSTOM_CHILDREN},indent=2))
