namespace blot_eval_lexical_capture_inputs;
import dictionary;
import .type_evidence;
import .eval_values;
import .semantic_evidence_import;
import support.error;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
type Error=blot_error::Error;
type Mapping=blot_eval_type_evidence::Mapping;
type RowMapping=blot_eval_type_evidence::RowMapping;
struct Interfaces {map:blot_support_pooled_map::Map<u32,u32>=blot_support_pooled_map::Map<u32,u32> {}}
reusable[] var interface_slots:dictionary_slot<u32,u32>[>..]=[];
fn get(self:const Interfaces&,value:u32)->u32? {return blot_support_pooled_map::get(self.map,value);}
fn insert(self:Interfaces&,key:u32,value:u32) {blot_support_pooled_map::insert(self.map,key,value,interface_slots);}
fn deinit(self:Interfaces&) {blot_support_pooled_map::deinit(self.map,interface_slots);}
fn withInterfaces<C,F>(context:C&)->bool,Error {var selected=Interfaces {};let value,error=F(context,selected);selected.deinit();return value,error;}

struct Slot { binding: u32,interface: u32,alias: u32 }
struct Inputs { unit: u32,identity: u32,anonymous: bool,applied: u32,source_type: u32,existing: u32,parameters: i64,mappings: Mapping[:],rows: RowMapping[:],slots: Slot[:],words: u64[:],values: u32[:] }
reusable[] var mapping_pool: Mapping[>..]=[];
reusable[] var row_pool: RowMapping[>..]=[];
reusable[] var slot_pool: Slot[>..]=[];
reusable[] var word_pool: u64[>..]=[];
reusable[] var value_pool: u32[>..]=[];
fn interface<V>(view: V,selected: const Interfaces&,value: u32) -> u32 { let known=selected.get(value); if known { return known; } return view.value_evidence[value]; }
fn deinit(self: Inputs&) {if self.mappings.len!=0 {mapping_pool.free_slice(self.mappings);}if self.rows.len!=0 {row_pool.free_slice(self.rows);}if self.slots.len!=0 {slot_pool.free_slice(self.slots);}if self.words.len!=0 {word_pool.free_slice(self.words);}if self.values.len!=0 {value_pool.free_slice(self.values);} self.mappings=[]; self.rows=[]; self.slots=[]; self.words=[]; self.values=[]; }
fn copyTyping<I>(self: Inputs,importer: I&) -> Inputs,Error {
 var result=self; result.mappings=[]; result.rows=[]; result.slots=[]; result.words=[]; result.values=[];
 result.mappings=mapping_pool.alloc_slice(self.mappings.len); for mapping,index in self.mappings { let evidence,error=importer.ty(mapping.evidence,0); if error!=Error.none { deinit(result); return default<Inputs>(),error; } result.mappings[index]=Mapping {mapping.variable,evidence}; }
 result.rows=row_pool.alloc_slice(self.rows.len); for mapping,index in self.rows { let evidence,error=importer.row(mapping.evidence,0); if error!=Error.none { deinit(result); return default<Inputs>(),error; } result.rows[index]=RowMapping {mapping.variable,evidence}; }
 result.slots=slot_pool.alloc_slice(self.slots.len); for slot,index in self.slots { let evidence,error=importer.ty(slot.interface,0); if error!=Error.none { deinit(result); return default<Inputs>(),error; } result.slots[index]=Slot {slot.binding,evidence,slot.alias}; }
 result.words=word_pool.alloc_slice(self.words.len); for word,index in self.words { result.words[index]=word; }
 let evidence,error=importer.ty(self.existing,0); if error!=Error.none { deinit(result); return default<Inputs>(),error; } result.existing=evidence; return result,Error.none;
}
fn append(words: u64[>..]&,values: const u64[:],limit: i64,examined: i64&) -> Error { if words.len>limit||values.len>limit-words.len { return Error.declined; } examined+=values.len; words.append(values); return Error.none; }
fn bit(value: bool) -> u64 { if value { return 1; } return 0; }
struct Seen { ordinal: u32,active: bool }
struct Visit { value: u32,next: i64=0,depth: i64,opened: bool=false }
fn buildChecked<S>(session: S&,value: u32,selected: const Interfaces&,limit: i64,examined: i64&,allow_empty: bool) -> Inputs,Error {
 let view=session.snapshot();
 if value==0||value>=view.values.len||view.values[value].kind!=blot_eval_eval_values::ValueKind.closure { return default<Inputs>(),Error.declined; }
 let root=session.closureInfo(value); if root.origin!=blot_eval_eval_values::ClosureOrigin.anonymous&&root.origin!=blot_eval_eval_values::ClosureOrigin.named { return default<Inputs>(),Error.declined; }
 var owner: i64=-1; for module,index in session.units { if module.unit==root.unit||(module.unit==0&&index+1==root.unit) { owner=index; break; } } if owner<0 { return default<Inputs>(),Error.declined; }
 let module=session.units[owner]; let children=session.valueChildren(value);
 if (!allow_empty&&children.len==0)||children.len>session.options.max_children||children.len>limit/4 { return default<Inputs>(),Error.declined; }
 let anonymous=root.origin==blot_eval_eval_values::ClosureOrigin.anonymous; if anonymous&&root.identity>=module.closures.len { return default<Inputs>(),Error.declined; }
 var bindings: const u32[:]=[]; var parameters: i64=1;
 if anonymous { let captures=module.closures[root.identity].captures; bindings=module.extra[captures.start..captures.start+captures.len]; if bindings.len!=children.len { return default<Inputs>(),Error.declined; } }
 else { let definition=module.body(root.identity); if definition==null||children.len!=root.applied||root.applied>=definition.parameters.len { return default<Inputs>(),Error.declined; } parameters=definition.parameters.len-root.applied; }
 var slots: Slot[>..]=[]; var mappings: Mapping[>..]=[]; mappings.append(view.type_mappings[root.mappings.start..root.mappings.start+root.mappings.len]); var rows: RowMapping[>..]=[]; rows.append(view.row_mappings[root.row_mappings.start..root.row_mappings.start+root.row_mappings.len]);
 var values: u32[>..]=[value]; var words: u64[>..]=[];
 let e=append(words,[1,root.unit,root.identity,bit(anonymous),root.applied,root.ty,view.value_evidence[value],children.len as u64],limit,examined); if e!=Error.none { return default<Inputs>(),e; }
 let options: u64[11]=[bit(session.options.reuse_body_recipes),bit(session.options.reuse_validated_calls),bit(session.options.reuse_lexical_summaries),session.options.max_steps as u64,session.options.max_depth as u64,session.options.max_call_depth as u64,session.options.max_type_depth as u64,session.options.max_summary_transitions as u64,session.options.max_values as u64,session.options.max_children as u64,bit(session.options.trace_runtime_dependencies)];
 for option in options {let oe=append(words,[option],limit,examined);if oe!=Error.none {return default<Inputs>(),oe;}}
 let me=append(words,[mappings.len as u64],limit,examined); if me!=Error.none { return default<Inputs>(),me; }
 for mapping in mappings { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
 let re=append(words,[rows.len as u64],limit,examined); if re!=Error.none { return default<Inputs>(),re; }
 for mapping in rows { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
 var seen: dictionary<u32,Seen>=dictionary<u32,Seen> {}; var stack: Visit[>..<]=[]; var edges=0;
 for child,index in children {
  var binding: u32=0; if anonymous { binding=bindings[index]; } else { let body=module.body(root.identity); if body==null { return default<Inputs>(),Error.declined; } binding=module.bodyParameters(body)[index].binding; }
  if child>=view.values.len||child>=view.value_evidence.len||interface(view,selected,child)==0 { return default<Inputs>(),Error.declined; }
  let err=append(words,[0x736c6f74,binding as u64],limit,examined); if err!=Error.none { return default<Inputs>(),err; } stack.push(Visit {value:child,depth:0});
  while stack.len!=0 {
   let last=stack.len-1; let current=stack[last];
   if !current.opened {
    let prior=seen.get(current.value);
    if prior { if prior.active { return default<Inputs>(),Error.declined; } let error=append(words,[0,prior.ordinal as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } stack.resize(last); continue; }
    if current.depth>=session.options.max_type_depth||seen.count>=session.options.max_values||seen.count>=0xffffffff { return default<Inputs>(),Error.declined; }
    if current.value>=view.values.len||current.value>=view.value_evidence.len||interface(view,selected,current.value)==0 { return default<Inputs>(),Error.declined; }
    let ordinal=seen.count as u32; values.push(current.value); seen.insert(current.value,Seen {ordinal,true}); let info=view.values[current.value];
    if info.start>view.children.len||info.len>view.children.len-info.start { return default<Inputs>(),Error.declined; }
    let h=append(words,[1,ordinal as u64,blot_eval_eval_values::valueKindCode(info.kind) as u64,info.scalar as u64,interface(view,selected,current.value) as u64,info.len as u64],limit,examined); if h!=Error.none { return default<Inputs>(),h; }
    let kind=info.kind;
    if kind==blot_eval_eval_values::ValueKind.scalar||kind==blot_eval_eval_values::ValueKind.product||kind==blot_eval_eval_values::ValueKind.record||kind==blot_eval_eval_values::ValueKind.nominal||kind==blot_eval_eval_values::ValueKind.array||kind==blot_eval_eval_values::ValueKind.list||kind==blot_eval_eval_values::ValueKind.cursor { let error=append(words,[info.nominal,info.bits as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
    else if kind==blot_eval_eval_values::ValueKind.closure {
     if info.bits>=view.closures.len { return default<Inputs>(),Error.declined; } let metadata=view.closures[info.bits]; if metadata.staged!=0 { return default<Inputs>(),Error.declined; }
     let error=append(words,[metadata.unit as u64,metadata.identity as u64,blot_eval_eval_values::closureOriginCode(metadata.origin) as u64,metadata.applied as u64,metadata.ty as u64,metadata.mappings.len as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; }
     for mapping in view.type_mappings[metadata.mappings.start..metadata.mappings.start+metadata.mappings.len] { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
     let er=append(words,[metadata.row_mappings.len as u64],limit,examined); if er!=Error.none { return default<Inputs>(),er; }
     for mapping in view.row_mappings[metadata.row_mappings.start..metadata.row_mappings.start+metadata.row_mappings.len] { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
    } else if kind==blot_eval_eval_values::ValueKind.provider||kind==blot_eval_eval_values::ValueKind.state_provider { let error=append(words,[current.value as u64,info.nominal,info.bits as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } }
    else { return default<Inputs>(),Error.declined; }
    if kind==blot_eval_eval_values::ValueKind.record { let names=session.recordFieldNames(current.value); let error=append(words,[names.len as u64],limit,examined); if error!=Error.none { return default<Inputs>(),error; } for name in names { let er=append(words,[name as u64],limit,examined); if er!=Error.none { return default<Inputs>(),er; } } }
    stack[last].opened=true;
   }
   let info=view.values[current.value]; if current.next==info.len { let prior=seen.get(current.value);if prior {prior.active=false;} stack.resize(last); continue; }
   edges++; if edges>limit { return default<Inputs>(),Error.declined; } stack[last].next++; stack.push(Visit {value:view.children[info.start+current.next],depth:current.depth+1});
  }
  let item=seen.get(child); if !item { return default<Inputs>(),Error.declined; } slots.push(Slot {binding,interface(view,selected,child),item.ordinal});
 }
 let ms=mapping_pool.alloc_slice(mappings.len); for m,i in mappings { ms[i]=m; } let rs=row_pool.alloc_slice(rows.len); for r,i in rows { rs[i]=r; } let ss=slot_pool.alloc_slice(slots.len); for s,i in slots { ss[i]=s; } let ws=word_pool.alloc_slice(words.len); for w,i in words { ws[i]=w; } let vs=value_pool.alloc_slice(values.len); for v,i in values { vs[i]=v; }
 return Inputs {root.unit,root.identity,anonymous,root.applied,root.ty,view.value_evidence[value],parameters,ms,rs,ss,ws,vs},Error.none;
}
fn buildWithBudget<S>(session: S&,value: u32,selected: const Interfaces&,limit: i64,examined: i64&,allow_empty: bool) -> Inputs,bool,Error { let input,error=buildChecked(session,value,selected,limit,examined,allow_empty); if error==Error.declined { return input,false,Error.none; } return input,error==Error.none,error; }
fn build<S>(session: S&,value: u32) -> Inputs,bool,Error { var selected=Interfaces {}; return buildWithInterfaces(session,value,selected); }
fn buildWithInterfaces<S>(session: S&,value: u32,selected: const Interfaces&) -> Inputs,bool,Error { var examined: i64=0; return buildWithBudget(session,value,selected,session.options.max_children,examined,false); }
fn buildCanonical<S>(session: S&,value: u32) -> Inputs,bool,Error { var selected=Interfaces {}; var examined: i64=0; return buildWithBudget(session,value,selected,session.options.max_children,examined,true); }
fn buildCanonicalBudget<S>(session: S&,value: u32,limit: i64,examined: i64&) -> Inputs,bool,Error { var selected=Interfaces {}; return buildWithBudget(session,value,selected,limit,examined,true); }
struct InputBuffer {storage:Inputs[:]=[],items:Inputs[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var input_runs:Inputs[>..]=[];
fn ensure(self:InputBuffer&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}self.failure=blot_support_pooled_buffer::ensure(self,minimum,input_runs);return self.failure;}
fn push(self:InputBuffer&,value:Inputs) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,input_runs);self.len=self.items.len;}
fn clear(self:InputBuffer&) {for &input in self.items {input.deinit();}blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn release(self:InputBuffer&) {self.clear();blot_support_pooled_buffer::deinit(self,input_runs);}
type Keys=blot_support_pooled_map::Map<const u64[:],u32>;
reusable[] var key_slots:dictionary_slot<const u64[:],u32>[>..]=[];
fn get(self:const Keys&,key:const u64[:])->u32? {return blot_support_pooled_map::get(self,key);}
fn reserveOne(self:Keys&) {if self.slots.len==0 {blot_support_pooled_map::grow(self,8,key_slots);}else if (self.count+1)*3>self.slots.len*2 {blot_support_pooled_map::grow(self,self.slots.len*2,key_slots);}}
fn insert(self:Keys&,key:const u64[:],value:u32) {blot_support_pooled_map::insert(self,key,value,key_slots);}
fn clear(self:Keys&) {blot_support_pooled_map::clear(self);}
fn release(self:Keys&) {blot_support_pooled_map::deinit(self,key_slots);}
struct CacheState {live:bool=false,generation:u64=0,keys:Keys=Keys {}, inputs:InputBuffer=InputBuffer {},owner_id:u64=0, requests:i64=0, reused:i64=0, retained_words:i64=0, examined_words:i64=0, interface_visits:i64=0}
var inactive:CacheState=CacheState {};
struct Cache {lease:u32=0,generation:u64=0,keys:Keys&=inactive.keys, inputs:InputBuffer&=inactive.inputs, owner_id:(u64)&=inactive.owner_id, requests:(i64)&=inactive.requests, reused:(i64)&=inactive.reused, retained_words:(i64)&=inactive.retained_words, examined_words:(i64)&=inactive.examined_words, interface_visits:(i64)&=inactive.interface_visits}
struct CacheSlot {state:CacheState=CacheState {},handle:Cache=Cache {}}
reusable var cache_slots:CacheSlot[>..]=[];
fn valid(self:const Cache&)->bool {return self.lease!=0&&self.lease-1<cache_slots.len&&cache_slots[self.lease-1].state.live&&cache_slots[self.lease-1].state.generation==self.generation;}
fn initPooled()->Cache,Error {
 if cache_slots.len>=0xffffffff {return Cache {},Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=cache_slots.alloc_index(CacheSlot {state:CacheState {live:true,generation:generation,owner_id:blot_native::fresh_owner_id()}});let slot:CacheSlot&=cache_slots[at];
 slot.handle=Cache {lease:(at+1) as u32,generation:generation,keys:slot.state.keys, inputs:slot.state.inputs, owner_id:slot.state.owner_id, requests:slot.state.requests, reused:slot.state.reused, retained_words:slot.state.retained_words, examined_words:slot.state.examined_words, interface_visits:slot.state.interface_visits};return copy(slot.handle),Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let cache,error=initPooled();if error!=Error.none {return null,error;}return cache_slots[cache.lease-1].handle,Error.none;}
fn deinit(self:Cache&) {if self.lease==0 {return;}assert(valid(self));self.inputs.release();self.keys.release();let at=self.lease-1;cache_slots[at].state.live=false;self=Cache {};cache_slots.free(at);}

fn intern<S>(self:Cache&,session:S&,value:u32,selected:const Interfaces&)->u32,bool,Error {
 assert(valid(self));self.requests++;if self.examined_words>=session.options.max_children {return 0,false,Error.none;}
 var examined:i64=0;var input,present,error=buildWithBudget(session,value,selected,session.options.max_children-self.examined_words,examined,false);self.examined_words+=examined;
 if error!=Error.none||!present {return 0,false,error;}
 {let existing=self.keys.get(input.words);if existing {let id=copy(existing);input.deinit();self.reused++;return id,true,Error.none;}}
 var available=session.options.max_children-self.retained_words;if available<0 {available=0;}
 if self.inputs.len>=session.options.max_values||self.inputs.len>=0xffffffff||input.words.len>available {input.deinit();return 0,false,Error.none;}
 self.keys.reserveOne();let prepared=self.inputs.ensure(self.inputs.len+1);if prepared!=Error.none {input.deinit();return 0,false,prepared;}
 let index=(self.inputs.len+1) as u32;self.keys.insert(input.words,index);self.inputs.push(input);assert(self.inputs.failure==Error.none);self.retained_words+=input.words.len;return index,true,Error.none;
}
fn reset(self:Cache&) {assert(valid(self));self.inputs.clear();self.keys.clear();self.owner_id=blot_native::fresh_owner_id();self.requests=0;self.reused=0;self.retained_words=0;self.examined_words=0;self.interface_visits=0;}
