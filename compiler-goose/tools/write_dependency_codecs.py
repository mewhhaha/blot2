# Source authoring only: the wire model -> concrete Goose codecs.
# Never executes either compiler, a checker, tests, formatting or qualification.
from pathlib import Path
import re,json,sys
REPO=Path(__file__).resolve().parents[2]
GOOSE=REPO/'compiler-goose/src'
OWNER_DISPATCH='''// Decode storage belongs to the concrete caller's allocation journal.
fn allocateDecoded<T>(owner:Owner&,length:i64)->T[:],Error {return squid_reuse_dependency_format::alloc<T>(owner,length);}
fn allocateDecoded<T>(owner:squid_reuse_dependency_payload::Owner&,length:i64)->T[:],Error {return squid_reuse_dependency_payload::alloc<T>(owner,length);}
'''
if sys.argv[1:]==['--repair-owner-dispatch']:
 # Preserve later syntax/semantic repairs when updating this generator frontier.
 path=GOOSE/'reuse/dependency_format_codecs.goose'
 source=path.read_text()
 source,count=re.subn(r'squid_reuse_dependency_format::alloc<([^;]+?)>\(reader\.owner,([^;]*?)\)',r'allocateDecoded<\1>(reader.owner,\2)',source)
 source,receiver_count=re.subn(r'reader\.owner\.alloc<([^;]+?)>\(([^;]*?)\)',r'allocateDecoded<\1>(reader.owner,\2)',source)
 count+=receiver_count
 if not count and OWNER_DISPATCH not in source:raise SystemExit('no decoder allocation sites found')
 if OWNER_DISPATCH not in source:
  source=source.replace('struct Void {}\n','struct Void {}\n'+OWNER_DISPATCH)
 if 'import reuse.dependency_payload;' not in source:
  source=source.replace('import reuse.dependency_format;','import reuse.dependency_format;\nimport reuse.dependency_payload;')
 path.write_text(source)
 print(f'Updated {count} decoder allocation sites')
 raise SystemExit(0)
from source_model import clean,balanced,split
from normalize_syntax import normalize,finish_syntax
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
# The wire model: every type on the wire and its Goose type, in the order
# the codecs are emitted. It was derived from the Zig compiler's declarations
# until 15 November 2026, when Zig was removed; dependency-wire-model.json is
# now the declaration, edited by hand.
MODEL=json.loads(Path(__file__).with_name('dependency-wire-model.json').read_text())
DESCS={};ORDER=[];ROOTS=[]
for entry in MODEL['descriptors']:
 d={'name':entry['name'],'kind':entry['kind'],'goose':entry['goose'],'children':[]}
 for key in ('count','primitive'):
  if key in entry:d[key]=entry[key]
 DESCS[d['name']]=d;ORDER.append(d)
for entry in MODEL['descriptors']:
 d=DESCS[entry['name']];d['children']=[DESCS[name] for name in entry.get('children',[])]
 if entry['kind']=='struct':d['fields']=[(field,DESCS[child],target) for field,child,target in entry['fields']];d['variants']=[]
 elif entry['kind'] in ('enum','union_tag'):d['variants']=[tuple(v) for v in entry['variants']]
 elif entry['kind']=='union':
  d['fields']=[];d['variants']=[(field,ordinal,target,DESCS[child],[tuple(x) for x in fs]) for field,ordinal,target,child,fs in entry['variants']];d['tag']=DESCS[entry['tag']]
ROOTS=[DESCS[name] for name in MODEL['roots']]
# A Goose type that changed without the model is an error here, not a field
# that silently stays off the wire.
def stale(message):raise SystemExit('dependency-wire-model.json: '+message)
for entry in MODEL['descriptors']:
 goose=entry['goose']
 if goose not in G:continue
 gkind,gbody,gns=G[goose]
 if entry['kind']=='struct' and gkind=='struct':
  have=[name for name,_ in gbody];wired=[target for _,_,target in entry['fields']];unwired=entry.get('unwired',[])
  for name in wired+unwired:
   if name not in have:stale(f'{entry["name"]} names `{name}`, which {goose} no longer has')
  for name in have:
   if name not in wired and name not in unwired:stale(f'{goose} has a new field `{name}`: add it to `fields` of {entry["name"]} to put it on the wire, or to `unwired` to keep it off')
 elif entry['kind'] in ('enum','union') and gkind=='enum':
  have=[name for name,_ in gbody];listed=[v[2] for v in entry['variants']]
  for name in listed:
   if name not in have:stale(f'{entry["name"]} names variant `{name}`, which {goose} no longer has')
  for name in have:
   if name not in listed:stale(f'{goose} has a new variant `{name}`: add it to `variants` of {entry["name"]}')
  if entry['kind']=='union':
   for field,ordinal,target,child,fs in entry['variants']:
    if [list(x) for x in dict(gbody)[target]]!=fs:stale(f'{goose}.{target} changed its payload: update `variants` of {entry["name"]}')
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
imports={'support.error','support.option','support.native','support.blake3','reuse.dependency_format','reuse.dependency_payload','check.core','check.types'}
for d in ORDER:
 for namespace in re.findall(r'\b(squid_\w+)::',actual(d)):
  if namespace in GF:imports.add(GF[namespace])
# The port's spelling: qualified errors, varint_, unqualified match patterns.
SYNTAX_TYPES={'T','bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}
for path in GOOSE.rglob('*.goose'):SYNTAX_TYPES.update(re.findall(r'\b(?:struct|enum|type)\s+(\w+)',path.read_text()))
def port_syntax(text):return finish_syntax(normalize(text,SYNTAX_TYPES))
lines=['// Concrete native-schema wire codecs, authored from frozen declarations.\n// Package/anonymous/generic native type-name spellings remain unqualified.\nnamespace squid_reuse_dependency_format;\n']+['import '+p+';\n' for p in sorted(imports)]+['struct Void {}\n',OWNER_DISPATCH]
for d in ORDER:
 t=actual(d);name=proc(d);kind=d['kind']
 # The schema's spelling is independent of Goose public/private owner fields.
 lines.append(f'fn describe_{name}(hasher:squid_support_blake3::State&,value:{t}) {{hasher.update({q(d["name"])});hasher.update([0]);')
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
  elif p in ('f32','f64'):lines.append(f'return writer.integer(squid_native::{p}_bits(value) as u64,{int(p[1:])//8});')
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
   lines.append(f'block {{let error=write_{proc(child)}(writer,value.{target},level+1);if error!=Error.none {{return error;}}}}')
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
  elif p in ('f32','f64'):lines.append(f'let bits,error=reader.integer({int(p[1:])//8});if error!=Error.none {{{error_return(d)}}}return squid_native::{p}_from_bits(bits as '+('u32' if p=='f32' else 'u64')+'),Error.none;')
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
   lines.append(code)
  if t in G and G[t][0]=='struct' and 'owner_id' in dict(G[t][1]):lines.append('result.owner_id=squid_native::fresh_owner_id();')
  lines.append('return result,Error.none;')
 elif kind=='array':
  child=d['children'][0];lines.append(f'var result=default<{t}>();for index in 0..{d["count"]} '+step(d,f'read_{proc(child)}(reader,level+1)','result[index]')+'return result,Error.none;')
 elif kind=='slice':
  child=d['children'][0];w=minimum(child);lines.append('let count,error=reader.varint();if error!=Error.none {'+error_return(d)+'}if count>0xffffffff {'+error_return(d,'Error.invalid_artifact')+'}if reader.remaining<0 || count>reader.remaining as u64 {'+error_return(d,'Error.artifact_limit')+'}reader.remaining-=count as i64;')
  if w:lines.append(f'if count>((reader.bytes.len-reader.at)/{w}) as u64 {{{error_return(d,"Error.invalid_artifact")}}}')
  lines.append(f'let result,error=allocateDecoded<{actual(child)}>(reader.owner,count as i64);if error!=Error.none {{{error_return(d)}}}')
  if child['name']=='u8':lines.append('let bytes,error=reader.take(count as i64);if error!=Error.none {'+error_return(d)+'}for byte,index in bytes {result[index]=byte;}')
  else:lines.append('for index in 0..count as i64 '+step(d,f'read_{proc(child)}(reader,level+1)','result[index]'))
  lines.append('return result,Error.none;')
 elif kind=='optional':
  child=d['children'][0];option_type=t[len('squid_support::Option<'):-1];lines.append('let flag,error=reader.integer(1);if error!=Error.none {'+error_return(d)+'}if flag==0 {return squid_support::none<'+option_type+'>(),Error.none;}if flag!=1 {'+error_return(d,'Error.invalid_artifact')+'}let value,error=read_'+proc(child)+'(reader,level+1);if error!=Error.none {'+error_return(d)+'}return squid_support::Option<'+option_type+'>{true,value},Error.none;')
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
 lines.append(f'fn describe(hasher:squid_support_blake3::State&,value:{t}) {{describe_{name}(hasher,value);}}\n')
(GOOSE/'reuse/dependency_format_codecs.goose').write_text(''.join(lines))
# Decode allocation journal: one finite ADT and reusable typed pool per actual
# Goose element type. Rollback/deinit never traverse partially built records.
elements={}
for d in ORDER:
 if d['kind']=='slice':elements.setdefault(actual(d['children'][0]),d['children'][0])
elements.setdefault('u32',DESCS['u32'])
owner=['// Typed archive decode runs; this owner is distinct from Payload.Owner.\nnamespace squid_reuse_dependency_format;\n']+['import '+p+';\n' for p in sorted(imports)]
owner+=['struct Owner {lease:u32=0,generation:u64=0}\n','enum Run {inactive,\n']
for t in elements:owner.append('run_'+ident(t)+'{values:'+t+'[:]},\n')
owner+=['}\n','struct Link {run:Run=Run.inactive,next:u32=0}\n','struct Lease {head:u32=0,generation:u64=0,live:bool=false}\n','reusable var links:Link[>..]=[];\n','reusable var owners:Lease[>..]=[];\n']
for t in elements:owner.append('reusable[] var pool_'+ident(t)+':'+t+'[>..]=[];\n')
owner.append('''fn valid(self:const Owner&)->bool {return self.lease!=0 && self.lease-1<owners.len && owners[self.lease-1].live && owners[self.lease-1].generation==self.generation;}
fn initOwner()->Owner,Error {if owners.len>=0xffffffff {return Owner{},Error.out_of_memory;}let generation=squid_native::fresh_owner_id();let at=owners.alloc_index(Lease{generation:generation,live:true});return Owner{(at+1) as u32,generation},Error.none;}
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
fn mutable(self:const Owner&,values:const {t}[:])->{t}[:] {{assert(self.valid());if values.len==0 {{return [];}}var link=owners[self.lease-1].head;while link!=0 {{let entry=links[link-1];match entry.run {{Run.run_{tag} run=>{{if squid_support::same_slice_identity(run.values,values) {{return pool_{tag}.realloc_slice(run.values,run.values.len);}}}},_=>{{}}}}link=entry.next;}}abort("archive slice is outside its owner");}}
''')
def owner_syntax(text):
 # Receivers are `self_` in the port, and an empty typed slice is spelled out.
 text=re.sub(r'\breceiver\b','self_',port_syntax(text));out=[]
 for line in text.split('\n'):
  m=re.match(r'fn allocate\(self_:Owner&,witness:(.+?),length:i64\)->',line) or re.match(r'fn mutable\(self_:const Owner&,values:const (.+?)\[:\]\)->',line)
  if m:line=line.replace('return [],','return default<'+m[1]+'[:]>(),').replace('return [];','return default<'+m[1]+'[:]>();')
  out.append(line)
 return '\n'.join(out)
(GOOSE/'reuse/dependency_format_owners.goose').write_text(''.join(owner))
# Explicit partial-field cleanup remains available for record constructors.
# It unlinks exact completed typed runs; unfinished decoder records are instead
# rolled back to their caller's mark by decodeWithOwner.
release_lines=['\n// Native field-order partial cleanup for completed aggregate fields.\n']
for d in ORDER:
 t=actual(d);name=proc(d);kind=d['kind'];release_lines.append(f'fn release_{name}(owner:Owner&,value:{t}) {{')
 if kind=='struct':
  for field,child,target in d['fields']:release_lines.append(f'release_{proc(child)}(owner,value.{target});')
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
with (GOOSE/'reuse/dependency_format_codecs.goose').open('a') as file:file.write(''.join(release_lines))
(GOOSE/'reuse/dependency_format_codecs.goose').write_text(port_syntax((GOOSE/'reuse/dependency_format_codecs.goose').read_text()))
release_owner=[]
for t in elements:
 tag=ident(t);release_owner.append(f'''fn releaseSlice(self:Owner&,values:const {t}[:]) {{assert(self.valid());if values.len==0 {{return;}}var previous:u32=0;var link=owners[self.lease-1].head;while link!=0 {{let at=link-1;let entry=links[at];match entry.run {{Run.run_{tag} run=>{{if squid_support::same_slice_identity(run.values,values) {{if previous==0 {{owners[self.lease-1].head=entry.next;}}else {{links[previous-1].next=entry.next;}}freeRun(entry.run);links[at]=Link{{}};links.free(at);return;}}}},_=>{{}}}}previous=link;link=entry.next;}}abort("partial field cleanup requires its exact archive owner");}}
''')
with (GOOSE/'reuse/dependency_format_owners.goose').open('a') as file:file.write(''.join(release_owner))
(GOOSE/'reuse/dependency_format_owners.goose').write_text(owner_syntax((GOOSE/'reuse/dependency_format_owners.goose').read_text()))

from write_body_shape import write_body_shape
write_body_shape(GOOSE.parent)
