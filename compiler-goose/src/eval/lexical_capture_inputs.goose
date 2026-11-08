namespace blot_eval_lexical_capture_inputs;
import eval.eval_values;
import eval.type_evidence;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import dictionary;
import .semantic_evidence_import;
type Error=blot_error::Error;
type Mapping=blot_eval_type_evidence::Mapping;
type RowMapping=blot_eval_type_evidence::RowMapping;
struct Interfaces {map:blot_support_pooled_map::Map<u32,u32> =blot_support_pooled_map::Map<u32,u32> {}}
reusable[] var interface_slots:dictionary_slot<u32,u32>[>..]=[];
fn get(self_:const Interfaces&,value:u32)->u32? {return blot_support_pooled_map::get(self_.map,value);}
fn insert(self_:Interfaces&,key:u32,value:u32) {blot_support_pooled_map::insert(self_.map,key,value,interface_slots);}
fn deinit(self_:Interfaces&) {blot_support_pooled_map::deinit(self_.map,interface_slots);}
fn withInterfaces<C,F>(context:C&)->bool,Error {var selected=Interfaces {};let value,error=F(context,selected);selected.deinit();return value,error;}

struct Slot { binding: u32,interface: u32,alias: u32 }
struct Inputs { unit: u32,identity: u32,anonymous: bool,applied: u32,source_type: u32,existing: u32,parameters: i64,mappings: Mapping[:],rows: RowMapping[:],slots: Slot[:],words: u64[:],values: u32[:] }
reusable[] var mapping_pool: Mapping[>..]=[];
reusable[] var row_pool: RowMapping[>..]=[];
reusable[] var slot_pool: Slot[>..]=[];
reusable[] var word_pool: u64[>..]=[];
reusable[] var value_pool: u32[>..]=[];
fn interface<V>(view: V,selected: const Interfaces&,value: u32) -> u32 { let known=selected.get(value); if known { return known; } return view.value_evidence[value]; }
fn deinit(self_: Inputs&) {if self_.mappings.len!=0 {mapping_pool.free_slice(self_.mappings);}if self_.rows.len!=0 {row_pool.free_slice(self_.rows);}if self_.slots.len!=0 {slot_pool.free_slice(self_.slots);}if self_.words.len!=0 {word_pool.free_slice(self_.words);}if self_.values.len!=0 {value_pool.free_slice(self_.values);} self_.mappings=default<blot_eval_lexical_capture_inputs::Mapping[:]>(); self_.rows=default<blot_eval_lexical_capture_inputs::RowMapping[:]>(); self_.slots=default<blot_eval_lexical_capture_inputs::Slot[:]>(); self_.words=default<u64[:]>(); self_.values=default<u32[:]>(); }
fn copyTyping<I>(self_: Inputs,importer: I&) -> Inputs,Error {
 var result=self_; result.mappings=default<blot_eval_lexical_capture_inputs::Mapping[:]>(); result.rows=default<blot_eval_lexical_capture_inputs::RowMapping[:]>(); result.slots=default<blot_eval_lexical_capture_inputs::Slot[:]>(); result.words=default<u64[:]>(); result.values=default<u32[:]>();
 result.mappings=mapping_pool.alloc_slice(self_.mappings.len); for mapping,index in self_.mappings { let evidence,error=importer.ty(mapping.evidence,0); if error!=blot_error::Error.none { deinit(result); return default<Inputs>(),error; } result.mappings[index]=Mapping {mapping.variable,evidence}; }
 result.rows=row_pool.alloc_slice(self_.rows.len); for mapping,index in self_.rows { let evidence,error=importer.row(mapping.evidence,0); if error!=blot_error::Error.none { deinit(result); return default<Inputs>(),error; } result.rows[index]=RowMapping {mapping.variable,evidence}; }
 result.slots=slot_pool.alloc_slice(self_.slots.len); for slot,index in self_.slots { let evidence,error=importer.ty(slot.interface,0); if error!=blot_error::Error.none { deinit(result); return default<Inputs>(),error; } result.slots[index]=Slot {slot.binding,evidence,slot.alias}; }
 result.words=word_pool.alloc_slice(self_.words.len); for word,index in self_.words { result.words[index]=word; }
 let evidence,error=importer.ty(self_.existing,0); if error!=blot_error::Error.none { deinit(result); return default<Inputs>(),error; } result.existing=evidence; return result,blot_error::Error.none;
}
fn append(words: u64[>..]&,values: const u64[:],limit: i64,examined: i64&) -> Error { if words.len>limit||values.len>limit-words.len { return blot_error::Error.declined; } examined+=values.len; words.append(values); return blot_error::Error.none; }
fn bit(value: bool) -> u64 { if value { return 1; } return 0; }
struct Seen { ordinal: u32,active: bool }
struct Visit { value: u32,next: i64=0,depth: i64,opened: bool=false }
fn buildChecked<S>(session: S&,value: u32,selected: const Interfaces&,limit: i64,examined: i64&,allow_empty: bool) -> Inputs,Error {
 let view=session.snapshot();
 if value==0||value>=view.values.len||view.values[value].kind!=blot_eval_eval_values::ValueKind.closure { return default<Inputs>(),blot_error::Error.declined; }
 let root=session.closureInfo(value); if root.origin!=blot_eval_eval_values::ClosureOrigin.anonymous&&root.origin!=blot_eval_eval_values::ClosureOrigin.named { return default<Inputs>(),blot_error::Error.declined; }
 var owner: i64=-1; for module,index in session.units { if module.unit==root.unit||(module.unit==0&&index+1==root.unit) { owner=index; break; } } if owner<0 { return default<Inputs>(),blot_error::Error.declined; }
 let module=session.units[owner]; let children=session.valueChildren(value);
 if (!allow_empty&&children.len==0)||children.len>session.options.max_children||children.len>limit/4 { return default<Inputs>(),blot_error::Error.declined; }
 let anonymous=root.origin==blot_eval_eval_values::ClosureOrigin.anonymous; if anonymous&&root.identity>=module.closures.len { return default<Inputs>(),blot_error::Error.declined; }
 let binding_count=selectedCaptureBindings(module,root.identity,anonymous).len; var parameters: i64=1;
 if anonymous { if binding_count!=children.len { return default<Inputs>(),blot_error::Error.declined; } }
 else { let definition=module.body(root.identity); if definition==null||children.len!=root.applied||root.applied>=definition.parameters.len { return default<Inputs>(),blot_error::Error.declined; } parameters=definition.parameters.len-root.applied; }
 var slots: Slot[>..]=[]; var mappings: Mapping[>..]=[]; mappings.append(view.type_mappings[root.mappings.start..root.mappings.start+root.mappings.len]); var rows: RowMapping[>..]=[]; rows.append(view.row_mappings[root.row_mappings.start..root.row_mappings.start+root.row_mappings.len]);
 var values: u32[>..]=[value]; var words: u64[>..]=[];
 let e=append(words,[1 as u64,root.unit,root.identity,bit(anonymous),root.applied,root.ty,view.value_evidence[value],children.len as u64],limit,examined); if e!=blot_error::Error.none { return default<Inputs>(),e; }
 let options: u64[11]=[bit(session.options.reuse_body_recipes),bit(session.options.reuse_validated_calls),bit(session.options.reuse_lexical_summaries),session.options.max_steps as u64,session.options.max_depth as u64,session.options.max_call_depth as u64,session.options.max_type_depth as u64,session.options.max_summary_transitions as u64,session.options.max_values as u64,session.options.max_children as u64,bit(session.options.trace_runtime_dependencies)];
 for option in options {let oe=append(words,[option],limit,examined);if oe!=blot_error::Error.none {return default<Inputs>(),oe;}}
 let me=append(words,[mappings.len as u64],limit,examined); if me!=blot_error::Error.none { return default<Inputs>(),me; }
 for mapping in mappings { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
 let re=append(words,[rows.len as u64],limit,examined); if re!=blot_error::Error.none { return default<Inputs>(),re; }
 for mapping in rows { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
 var seen: dictionary<u32,Seen> =dictionary<u32,Seen> {}; var stack: Visit[>..<]=[]; var edges=0;
 for child,index in children {
  var binding: u32=0; if anonymous { binding=selectedCaptureBinding(module,root.identity,index); } else { let body=module.body(root.identity); if body==null { return default<Inputs>(),blot_error::Error.declined; } binding=module.bodyParameters(body)[index].binding; }
  if child>=view.values.len||child>=view.value_evidence.len||interface(view,selected,child)==0 { return default<Inputs>(),blot_error::Error.declined; }
  let err=append(words,[0x736c6f74 as u64,binding as u64],limit,examined); if err!=blot_error::Error.none { return default<Inputs>(),err; } stack.push(Visit {value:child,depth:0});
  while stack.len!=0 {
   let last=stack.len-1; let current=stack[last];
   if !current.opened {
    let prior=::get(seen,current.value);
    if prior { if prior.active { return default<Inputs>(),blot_error::Error.declined; } let error=append(words,[0 as u64,prior.ordinal as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } stack.resize(last); continue; }
    if current.depth>=session.options.max_type_depth||seen.count>=session.options.max_values||seen.count>=0xffffffff { return default<Inputs>(),blot_error::Error.declined; }
    if current.value>=view.values.len||current.value>=view.value_evidence.len||interface(view,selected,current.value)==0 { return default<Inputs>(),blot_error::Error.declined; }
    let ordinal=seen.count as u32; values.push(current.value); ::insert(seen,current.value,Seen {ordinal,true}); let info=view.values[current.value];
    if info.start>view.children.len||info.len>view.children.len-info.start { return default<Inputs>(),blot_error::Error.declined; }
    let h=append(words,[1 as u64,ordinal as u64,blot_eval_eval_values::valueKindCode(info.kind) as u64,info.scalar as u64,interface(view,selected,current.value) as u64,info.len as u64],limit,examined); if h!=blot_error::Error.none { return default<Inputs>(),h; }
    let kind=info.kind;
    if kind==blot_eval_eval_values::ValueKind.scalar||kind==blot_eval_eval_values::ValueKind.product||kind==blot_eval_eval_values::ValueKind.record||kind==blot_eval_eval_values::ValueKind.nominal||kind==blot_eval_eval_values::ValueKind.array||kind==blot_eval_eval_values::ValueKind.list||kind==blot_eval_eval_values::ValueKind.cursor { let error=append(words,[info.nominal,info.bits as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
    else if kind==blot_eval_eval_values::ValueKind.closure {
     if info.bits>=view.closures.len { return default<Inputs>(),blot_error::Error.declined; } let metadata=view.closures[info.bits]; if metadata.staged!=0 { return default<Inputs>(),blot_error::Error.declined; }
     let error=append(words,[metadata.unit as u64,metadata.identity as u64,blot_eval_eval_values::closureOriginCode(metadata.origin) as u64,metadata.applied as u64,metadata.ty as u64,metadata.mappings.len as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; }
     for mapping in view.type_mappings[metadata.mappings.start..metadata.mappings.start+metadata.mappings.len] { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
     let er=append(words,[metadata.row_mappings.len as u64],limit,examined); if er!=blot_error::Error.none { return default<Inputs>(),er; }
     for mapping in view.row_mappings[metadata.row_mappings.start..metadata.row_mappings.start+metadata.row_mappings.len] { let error=append(words,[mapping.variable as u64,mapping.evidence as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
    } else if kind==blot_eval_eval_values::ValueKind.provider||kind==blot_eval_eval_values::ValueKind.state_provider { let error=append(words,[current.value as u64,info.nominal,info.bits as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } }
    else { return default<Inputs>(),blot_error::Error.declined; }
    if kind==blot_eval_eval_values::ValueKind.record { let names=session.recordFieldNames(current.value); let error=append(words,[names.len as u64],limit,examined); if error!=blot_error::Error.none { return default<Inputs>(),error; } for name in names { let er=append(words,[name as u64],limit,examined); if er!=blot_error::Error.none { return default<Inputs>(),er; } } }
    stack[last].opened=true;
   }
   let info=view.values[current.value]; if current.next==info.len { let prior=::get(seen,current.value);if prior {prior.active=false;} stack.resize(last); continue; }
   edges++; if edges>limit { return default<Inputs>(),blot_error::Error.declined; } stack[last].next++; stack.push(Visit {value:view.children[info.start+current.next],depth:current.depth+1});
  }
  let item=::get(seen,child); if !item { return default<Inputs>(),blot_error::Error.declined; } slots.push(Slot {binding,interface(view,selected,child),item.ordinal});
 }
 let ms=mapping_pool.alloc_slice(mappings.len); for m,i in mappings { ms[i]=m; } let rs=row_pool.alloc_slice(rows.len); for r,i in rows { rs[i]=r; } let ss=slot_pool.alloc_slice(slots.len); for s,i in slots { ss[i]=s; } let ws=word_pool.alloc_slice(words.len); for w,i in words { ws[i]=w; } let vs=value_pool.alloc_slice(values.len); for v,i in values { vs[i]=v; }
 return Inputs {root.unit,root.identity,anonymous,root.applied,root.ty,view.value_evidence[value],parameters,ms,rs,ss,ws,vs},blot_error::Error.none;
}
fn buildWithBudget<S>(session: S&,value: u32,selected: const Interfaces&,limit: i64,examined: i64&,allow_empty: bool) -> Inputs,bool,Error { let input,error=buildChecked(session,value,selected,limit,examined,allow_empty); if error==blot_error::Error.declined { return input,false,blot_error::Error.none; } return input,error==blot_error::Error.none,error; }
fn build<S>(session: S&,value: u32) -> Inputs,bool,Error { var selected=Interfaces {}; return buildWithInterfaces(session,value,selected); }
fn buildWithInterfaces<S>(session: S&,value: u32,selected: const Interfaces&) -> Inputs,bool,Error { var examined: i64=0; return buildWithBudget(session,value,selected,session.options.max_children,examined,false); }
fn buildCanonical<S>(session: S&,value: u32) -> Inputs,bool,Error { var selected=Interfaces {}; var examined: i64=0; return buildWithBudget(session,value,selected,session.options.max_children,examined,true); }
fn buildCanonicalBudget<S>(session: S&,value: u32,limit: i64,examined: i64&) -> Inputs,bool,Error { var selected=Interfaces {}; return buildWithBudget(session,value,selected,limit,examined,true); }
struct InputBuffer {storage:Inputs[:]=default<Inputs[:]>(),items:Inputs[:]=default<Inputs[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var input_runs:Inputs[>..]=[];
fn ensure(self_:InputBuffer&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,input_runs);return self_.failure;}
fn push(self_:InputBuffer&,value:Inputs) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,canonicalOwned(value),input_runs);self_.len=self_.items.len;}
fn clear(self_:InputBuffer&) {for &input in self_.items {input.deinit();}blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn release(self_:InputBuffer&) {self_.clear();blot_support_pooled_buffer::deinit(self_,input_runs);}
type Keys=blot_support_pooled_map::Map<const u64[:],u32>;
reusable[] var key_slots:dictionary_slot<const u64[:],u32>[>..]=[];
fn get(self_:const Keys&,key:const u64[:])->u32? {return blot_support_pooled_map::get(self_,key);}
fn reserveOne(self_:Keys&) {if self_.slots.len==0 {blot_support_pooled_map::grow(self_,8,key_slots);}else if (self_.count+1)*3>self_.slots.len*2 {blot_support_pooled_map::grow(self_,self_.slots.len*2,key_slots);}}
fn insert(self_:Keys&,key:const u64[:],value:u32) {blot_support_pooled_map::insert(self_,key,value,key_slots);}
fn clear(self_:Keys&) {blot_support_pooled_map::clear(self_);}
fn release(self_:Keys&) {blot_support_pooled_map::deinit(self_,key_slots);}
struct CacheState {live:bool=false,generation:u64=0,keys:Keys=Keys {}, inputs:InputBuffer=InputBuffer {},owner_id:u64=0, requests:i64=0, reused:i64=0, retained_words:i64=0, examined_words:i64=0, interface_visits:i64=0}
var inactive:CacheState=CacheState {};
struct Cache {lease:u32=0,generation:u64=0,keys:Keys& =inactive.keys, inputs:InputBuffer& =inactive.inputs, owner_id:(u64)& =inactive.owner_id, requests:(i64)& =inactive.requests, reused:(i64)& =inactive.reused, retained_words:(i64)& =inactive.retained_words, examined_words:(i64)& =inactive.examined_words, interface_visits:(i64)& =inactive.interface_visits}
struct CacheSlot {state:CacheState=CacheState {},handle:Cache=Cache {}}
reusable var cache_slots:CacheSlot[>..]=[];
fn valid(self_:const Cache&)->bool {return self_.lease!=0&&self_.lease-1<cache_slots.len&&cache_slots[self_.lease-1].state.live&&cache_slots[self_.lease-1].state.generation==self_.generation;}
fn initPooled()->Cache,Error {
 if cache_slots.len>=0xffffffff {return Cache {},blot_error::Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=cache_slots.alloc_index(CacheSlot {state:CacheState {live:true,generation:generation,owner_id:blot_native::fresh_owner_id()}});let slot:CacheSlot& =cache_slots[at];
 slot.handle=Cache {lease:(at+1) as u32,generation:generation,keys:slot.state.keys, inputs:slot.state.inputs, owner_id:slot.state.owner_id, requests:slot.state.requests, reused:slot.state.reused, retained_words:slot.state.retained_words, examined_words:slot.state.examined_words, interface_visits:slot.state.interface_visits};return copy(slot.handle),blot_error::Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let cache,error=initPooled();if error!=blot_error::Error.none {return null,error;}return cache_slots[cache.lease-1].handle,blot_error::Error.none;}
fn deinit(self_:Cache&) {if self_.lease==0 {return;}assert(valid(self_));blot_eval_lexical_capture_inputs::release(self_.inputs);blot_eval_lexical_capture_inputs::release(self_.keys);let at=self_.lease-1;cache_slots[at].state.live=false;self_=Cache {};cache_slots.free(at);}

fn intern<S>(self_:Cache&,session:S&,value:u32,selected:const Interfaces&)->u32,bool,Error {
 assert(valid(self_));self_.requests++;if self_.examined_words>=session.options.max_children {return 0,false,blot_error::Error.none;}
 var examined:i64=0;var input,present,error=buildWithBudget(session,value,selected,session.options.max_children-self_.examined_words,examined,false);self_.examined_words+=examined;
 if error!=blot_error::Error.none||!present {return 0,false,error;}
 {let existing=blot_eval_lexical_capture_inputs::get(self_.keys,input.words);if existing {let id=copy(existing);input.deinit();self_.reused++;return id,true,blot_error::Error.none;}}
 var available=session.options.max_children-self_.retained_words;if available<0 {available=0;}
 if self_.inputs.len>=session.options.max_values||self_.inputs.len>=0xffffffff||input.words.len>available {input.deinit();return 0,false,blot_error::Error.none;}
 blot_eval_lexical_capture_inputs::reserveOne(self_.keys);let prepared=self_.inputs.ensure(self_.inputs.len+1);if prepared!=blot_error::Error.none {input.deinit();return 0,false,prepared;}
 let index=(self_.inputs.len+1) as u32;blot_eval_lexical_capture_inputs::insert(self_.keys,input.words,index);self_.inputs.push(input);assert(self_.inputs.failure==blot_error::Error.none);self_.retained_words+=input.words.len;return index,true,blot_error::Error.none;
}
fn reset(self_:Cache&) {assert(valid(self_));self_.inputs.clear();blot_eval_lexical_capture_inputs::clear(self_.keys);self_.owner_id=blot_native::fresh_owner_id();self_.requests=0;self_.reused=0;self_.retained_words=0;self_.examined_words=0;self_.interface_visits=0;}

fn selectedCaptureBinding<M>(module:const M&,identity:u32,index:i64)->u32 {return selectedCaptureBindings(module,identity,true)[index];}
fn selectedCaptureBindings<M>(module:const M&,identity:u32,anonymous:bool)->const u32[:] {if anonymous {let captures=module.closures[identity].captures;return module.extra[captures.start..captures.start+captures.len];}return default<const u32[:]>();}

fn canonicalOwned(source:Inputs)->Inputs {
 return Inputs{source.unit,source.identity,source.anonymous,source.applied,source.source_type,source.existing,source.parameters,
  mapping_pool.realloc_slice(source.mappings,source.mappings.len),row_pool.realloc_slice(source.rows,source.rows.len),
  slot_pool.realloc_slice(source.slots,source.slots.len),word_pool.realloc_slice(source.words,source.words.len),value_pool.realloc_slice(source.values,source.values.len)};
}
