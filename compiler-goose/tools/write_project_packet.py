# Source authoring: close the finite set of copied project data types, then emit
# concrete enum/array codecs and typed allocation families. No compiler/checks.
from pathlib import Path
import re,json
R=Path(__file__).resolve().parents[1]/'src'
from source_model import clean,balanced,split
from normalize_syntax import normalize,finish_syntax
(R.parent/'build').mkdir(parents=True,exist_ok=True)
D={};PATHS={}
for path in R.rglob('*.goose'):
 if path.name.startswith('_') or (path.parent == R and 'probe' in path.stem):continue
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
 'blot_reuse_body_check_cache::Loops':{'slot'},
 'blot_reuse_body_auxiliary::Owner':{'slot'},
 'blot_reuse_body_check_cache::Chunk':{'references','graph_owner','live','slot'},
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
SEEN={};SLICES={};ARRAYS=set();ENUMS={};STRUCTS={};IMPORTS=set()
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
  STRUCTS[t]=data
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
for t,skip in [('blot_check_core::Module',{'owner_id','package_payloads'}),('blot_check_core::Types',{'owner_id'}),('blot_check_frozen_types::Graph',{'owner_id'}),('blot_check_type_store_snapshot::Snapshot',{'lease_index','generation'}),('blot_check_type_store_snapshot::State',{'store_owner_id'})]:
 if t not in SEEN:continue
 data=D[t][2];owner=D[t][3]
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,value.'+f+');' for f,ty in data if f not in skip)+'self.depth--;}')
 trailer=''
 if t=='blot_check_core::Module':trailer='value.owner_id=blot_native::fresh_owner_id();let lanes,error=allocate(self.owner,value.nodes.len,default<u32>());if error!=Error.none {self.failure=error;}else {for node,index in value.nodes {lanes[index]=0;if node.tag==blot_check_core::Tag.package_pack {lanes[index]=node.a;}}value.package_payloads=lanes;}'
 elif t in ('blot_check_core::Types','blot_check_frozen_types::Graph') and any(f=='owner_id' for f,ty in data):trailer='value.owner_id=blot_native::fresh_owner_id();'
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}'+''.join('get(self,value.'+f+');' for f,ty in data if f not in skip)+trailer+'self.depth--;}')
# Explicit nominal heads avoid ties between the generic record, slice and
# optional helpers. Reader/writer inference keeps unused codecs uninstantiated.
private={'blot_check_core::Module','blot_check_core::Types','blot_check_frozen_types::Graph'}
for t in sorted(STRUCTS):
 if t in private or (t in SPECIAL and t not in {'blot_reuse_body_check_cache::Loops','blot_reuse_body_auxiliary::Owner'}):continue
 owner=D[t.split('<')[0]][3]
 fields=[(f,resolve(q(ty,owner),owner)) for f,ty in STRUCTS[t] if f not in SPECIAL.get(t,set())]
 code.append('fn put(self:Writer&,value:'+t+') {if !self.enter() {return;}'+''.join(('putOptional' if ty.endswith('?') else 'put')+'(self,value.'+f+');' for f,ty in fields)+'self.depth--;}')
 parts=[]
 for f,ty in fields:
  if ty.endswith('?'):parts.append('value.'+f+' .= readOptional(self,default<'+ty[:-1]+'>());')
  else:parts.append('get(self,value.'+f+');')
 code.append('fn get(self:Reader&,value:'+t+'&) {if !self.enter() {return;}'+''.join(parts)+'self.depth--;}')
code=[line.replace('fn put(self:Writer&','fn put<PacketWriter>(self:PacketWriter&').replace('fn get(self:Reader&','fn get<PacketReader>(self:PacketReader&') for line in code]
syntax_types=PRIM|{name.split('::')[-1] for name in D}
(R/'support/project_packet_codecs.goose').write_text(finish_syntax(normalize('\n'.join(code)+'\n',syntax_types)))
# Every family is concrete; no generic cast, byte arena or ownership erasure.
owner=['// Typed bounded decode journal. The owner is shared only within one process.','namespace blot_project_packet;',imports,'import .project_packet;','struct Owner {slot:u32=0,generation:u64=0}','enum Run {']
for t in sorted(SLICES):owner.append('run_'+ident(t)+' {values:'+t+'[:]},')
owner+=['}','struct Link {value:Run,next:u32=0}','struct Lease {generation:u64=0,live:bool=false,references:u64=1,head:u32=0}','reusable var leases:Lease[>..]=[];','reusable var links:Link[>..]=[];']
for t in sorted(SLICES):owner.append('reusable[] var pool_'+ident(t)+':'+t+'[>..]=[];')
owner+=['fn valid(self:Owner)->bool {return self.slot!=0&&self.slot-1<leases.len&&leases[self.slot-1].live&&leases[self.slot-1].generation==self.generation;}','fn initOwner()->Owner,Error {if leases.len>=0xffffffff {return Owner{..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=leases.alloc_index(Lease{generation:generation,live:true,..});return Owner{(at+1) as u32,generation},Error.none;}','fn retain(self:Owner)->Owner,Error {if !self.valid() {return Owner{..},Error.invalid_artifact;}let state:Lease&=leases[self.slot-1];if state.references==0xffffffffffffffff {return Owner{..},Error.dependency_limit;}state.references++;return self,Error.none;}']
for t in sorted(SLICES):
 owner.append('fn allocate<PacketOwner>(self:PacketOwner&,length:i64,witness:'+t+')->'+t+'[:],Error {if !self.valid()||length<0||length>element_limit {return default<'+t+'[:]>(),Error.invalid_artifact;}if length==0 {return default<'+t+'[:]>(),Error.none;}if links.len>=0xfffffffe {return default<'+t+'[:]>(),Error.out_of_memory;}let run=pool_'+ident(t)+'.alloc_slice(length);let state:Lease& =leases[self.slot-1];let at=links.alloc_index(Link{Run.run_'+ident(t)+'{run},state.head});state.head=(at+1) as u32;return run,Error.none;}')
owner.append('fn deinit(self:Owner&) {if self.slot==0 {return;}assert(self.valid());let state:Lease&=leases[self.slot-1];assert(state.references!=0);state.references--;if state.references==0 {var next=state.head;while next!=0 {let at=next-1;let link=links[at];next=link.next;match link.value {')
for t in sorted(SLICES):owner.append('Run.run_'+ident(t)+' value=>{pool_'+ident(t)+'.free_slice(value.values);},')
owner.append('}links.free(at);}state.live=false;leases.free(self.slot-1);}self=Owner{..};}')
(R/'support/project_packet_owners.goose').write_text(finish_syntax(normalize('\n'.join(owner)+'\n',syntax_types)))
(R.parent/'build/project-packet-model.json').write_text(json.dumps({'definitions':D,'roots':ROOTS,'seen':list(SEEN),'slices':list(SLICES),'imports':sorted(IMPORTS),'special_children':CUSTOM_CHILDREN},indent=2))

# Fixed packet primitives are generated here alongside their concrete domains.
PACKET_BASE = r"""// Process-local project/check/lower wire images. Only typed data crosses this
// boundary; owner leases, callbacks and references are rebuilt in the child.
namespace blot_project_packet;
import support.error;
import support.native;
import support.option;
import support.bytes;
import .project_packet_owners;
import .project_packet_codecs;
import .project_packet_contexts;
type Error=blot_error::Error;
let limit:i64=536870912;
let element_limit:i64=67108864;
let depth_limit:i64=128;
struct Writer {output:u8[>..<]&,failure:Error=blot_error::Error.none,depth:i64=0}
struct Reader {bytes:const u8[:],owner:Owner,at:i64=0,failure:Error=blot_error::Error.none,remaining:i64=element_limit,depth:i64=0}
fn room(receiver:Writer&,amount:i64)->bool {if receiver.failure!=blot_error::Error.none {return false;}if amount<0||receiver.output.len>limit||amount>limit-receiver.output.len {receiver.failure=blot_error::Error.artifact_limit;return false;}return true;}
fn available(receiver:Reader&,amount:i64)->bool {if receiver.failure!=blot_error::Error.none {return false;}if amount<0||receiver.at>receiver.bytes.len||amount>receiver.bytes.len-receiver.at {receiver.failure=blot_error::Error.invalid_artifact;return false;}return true;}
fn enter(receiver:Writer&)->bool {if receiver.failure!=blot_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=blot_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn enter(receiver:Reader&)->bool {if receiver.failure!=blot_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=blot_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn put(receiver:Writer&,value:bool) {var bit:u8=0;if value {bit=1;}put(receiver,bit);}
fn get(receiver:Reader&,value:bool&) {var bit:u8=0;get(receiver,bit);if bit>1 {receiver.failure=blot_error::Error.invalid_artifact;return;}value=bit==1;}
fn count(receiver:Writer&,length:i64) {if length<0||length>element_limit {receiver.failure=blot_error::Error.artifact_limit;return;}put(receiver,length as u64);}
fn count(receiver:Reader&)->i64 {var length:u64=0;get(receiver,length);if receiver.failure!=blot_error::Error.none {return 0;}if length>receiver.remaining as u64||length>(receiver.bytes.len-receiver.at) as u64 {receiver.failure=blot_error::Error.artifact_limit;return 0;}receiver.remaining-=length as i64;return length as i64;}
fn put<T>(receiver:Writer&,value:const T[:]) {if !receiver.enter() {return;}count(receiver,value.len);for item in value {put(receiver,item);}receiver.depth--;}
fn get<T>(receiver:Reader&,value:T[:]& ) {if !receiver.enter() {return;}let length=count(receiver);if receiver.failure!=blot_error::Error.none {receiver.depth--;return;}let run,error=allocate(receiver.owner,length,default<T>());if error!=blot_error::Error.none {receiver.failure=error;receiver.depth--;return;}value=run;for &item in run {get(receiver,item);if receiver.failure!=blot_error::Error.none {break;}}receiver.depth--;}
fn get<T>(receiver:Reader&,value:(const T[:])&) {var run:T[:]=default<T[:]>();get(receiver,run);value=run;}
fn put<T>(receiver:Writer&,value:blot_support::Option<T>) {put(receiver,value.present);if value.present {put(receiver,value.value);}}
fn get<T>(receiver:Reader&,value:blot_support::Option<T>&) {get(receiver,value.present);if receiver.failure!=blot_error::Error.none {return;}if value.present {get(receiver,value.value);}}
fn putOptional<T>(receiver:Writer&,value:T?) {put(receiver,value!=null);if value {let item:T=value;put(receiver,item);}}
fn readOptional<T>(receiver:Reader&,witness:T)->T? {var present=false;get(receiver,present);if receiver.failure!=blot_error::Error.none||!present {return null;}let run,error=allocate(receiver.owner,1,default<T>());if error!=blot_error::Error.none {receiver.failure=error;return null;}get(receiver,run[0]);if receiver.failure!=blot_error::Error.none {return null;}return run[0];}
fn put<K,V>(receiver:Writer&,value:dictionary_slot<K,V>) {put(receiver,value.tag);if value.tag!=0 {put(receiver,value.key);put(receiver,value.val);}}
fn get<K,V>(receiver:Reader&,value:dictionary_slot<K,V>&) {get(receiver,value.tag);if value.tag!=0 {get(receiver,value.key);get(receiver,value.val);}}
"""
(R/'support/project_packet.goose').write_text(PACKET_BASE)
