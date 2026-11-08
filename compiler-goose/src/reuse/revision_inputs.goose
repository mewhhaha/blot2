// One revision owns exact settings, acquisition outcomes and import decisions.
// These are source observations, never semantic/evaluated-value certificates.
namespace blot_reuse_revision_inputs;
import dictionary;
import reuse.project;
import reuse.frozen_dependency;
import reuse.dependency_closure;
import reuse.source_overlays;
import parse.lexer;
import parse.token;
import support.option;
import support.error;
import support.native;
import support.blake3;
import support.pooled_buffer;
import support.pooled_map;
type Error=blot_error::Error;
type Options=blot_reuse_project::Options;
type Alias=blot_reuse_project::Alias;
type Digest=u8[32];
type Text=blot_support::Option<const u8[:]>;
enum Outcome {inactive,bytes{value:const u8[:]},failure{error:Error,cause:const u8[:]}}
struct Entry {key:const u8[:]=default<const u8[:]>(),result:Outcome=Outcome.inactive}
struct Resolution {source:const u8[:]=default<const u8[:]>(),request:const u8[:]=default<const u8[:]>(),result:Outcome=Outcome.inactive}
struct Counts {canonical_reads:i64=0,source_reads:i64=0,resolutions:i64=0}
struct Settings {options:Options}
struct Observations {paths:const Entry[:]=default<const Entry[:]>(),files:const Entry[:]=default<const Entry[:]>(),imports:const Resolution[:]=default<const Resolution[:]>()}
struct Acquired {counts:Counts=Counts{}}
struct Record {key:Settings,dependencies:Observations,value:Acquired}
struct View {options:Options,paths:const Entry[:]=default<const Entry[:]>(),files:const Entry[:]=default<const Entry[:]>(),imports:const Resolution[:]=default<const Resolution[:]>(),counts:Counts=Counts{}}
reusable[] var bytes_pool:u8[>..]=[];
reusable[] var aliases_pool:Alias[>..]=[];
reusable[] var entry_pool:Entry[>..]=[];
reusable[] var resolution_pool:Resolution[>..]=[];
reusable[] var index_pool:dictionary_slot<const u8[:],u32>[>..]=[];
reusable[] var digest_pool:dictionary_slot<u32,Digest>[>..]=[];
reusable[] var mask_pool:bool[>..]=[];
fn own(bytes:const u8[:])->const u8[:] {let result=bytes_pool.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn ownedText(bytes:const u8[:])->const u8[:] {return bytes_pool.realloc_slice(bytes,bytes.len);}
fn free(bytes:const u8[:]) {if bytes.len!=0 {bytes_pool.free_slice(bytes);}}
fn deinit(result:Outcome) {match result {bytes payload=>{free(payload.value);},failure=>{},inactive=>{}}}
fn deinit(entry:Entry) {free(entry.key);entry.result.deinit();}
fn deinit(entry:Resolution) {free(entry.source);free(entry.request);entry.result.deinit();}
fn value(result:Outcome)->const u8[:],Error {match result {bytes payload=>{return payload.value,blot_error::Error.none;},failure payload=>{return default<const u8[:]>(),payload.error;},inactive=>{abort("inactive source observation");}}}
fn success(result:Outcome)->Text {match result {bytes payload=>{return blot_support::some(payload.value);},failure=>{return blot_support::none<const u8[:]>();},inactive=>{abort("inactive source observation");}}}
fn get(entries:const Entry[:],key:const u8[:])->blot_support::Option<Outcome> {for entry in entries {if entry.key==key {return blot_support::some(entry.result);}}return blot_support::none<Outcome>();}
fn capturedSource(self_:View,canonical_path:const u8[:])->Text {let result=get(self_.files,canonical_path);if !result.present {return blot_support::none<const u8[:]>();}return success(result.value);}
fn copyText(text:Text)->Text {if text.present {return blot_support::some(own(text.value));}return blot_support::none<const u8[:]>();}
fn copyOptions(options:Options)->Options {
 let prelude=copyText(options.prelude_path);let std_root=copyText(options.std_root);
 let aliases=aliases_pool.alloc_slice(options.aliases.len);for alias,index in options.aliases {aliases[index]=Alias{own(alias.prefix),own(alias.root)};}
 return Options{options.input_mode,prelude,std_root,aliases,options.max_source_bytes,options.max_total_source_bytes,options.max_files};
}
fn freeOptions(options:Options) {if options.prelude_path.present {free(options.prelude_path.value);}if options.std_root.present {free(options.std_root.value);}for alias in options.aliases {free(alias.prefix);free(alias.root);}if options.aliases.len!=0 {aliases_pool.free_slice(options.aliases);}}
struct State {
 live:bool=false,frozen:bool=false,generation:u64=0,options:Options=default<Options>(),paths:blot_support_pooled_buffer::Buffer<Entry> =blot_support_pooled_buffer::Buffer<Entry>{},files:blot_support_pooled_buffer::Buffer<Entry> =blot_support_pooled_buffer::Buffer<Entry>{},imports:blot_support_pooled_buffer::Buffer<Resolution> =blot_support_pooled_buffer::Buffer<Resolution>{},
 path_index:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{},file_index:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{},import_index:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{},digests:blot_support_pooled_map::Map<u32,Digest> =blot_support_pooled_map::Map<u32,Digest>{},counts:Counts=Counts{},sources:blot_support::Option<blot_reuse_source_overlays::Set> =blot_support::none<blot_reuse_source_overlays::Set>(),last_cause:const u8[:]=default<const u8[:]>(),
}
reusable var states:State[>..]=[];
var inactive:State=State{};
struct Snapshot {slot:u32=0,generation:u64=0,options:Options=default<Options>(),paths:blot_support_pooled_buffer::Buffer<Entry>& =inactive.paths,files:blot_support_pooled_buffer::Buffer<Entry>& =inactive.files,imports:blot_support_pooled_buffer::Buffer<Resolution>& =inactive.imports,path_index:blot_support_pooled_map::Map<const u8[:],u32>& =inactive.path_index,file_index:blot_support_pooled_map::Map<const u8[:],u32>& =inactive.file_index,import_index:blot_support_pooled_map::Map<const u8[:],u32>& =inactive.import_index,digests:blot_support_pooled_map::Map<u32,Digest>& =inactive.digests,counts:Counts& =inactive.counts,sources:blot_support::Option<blot_reuse_source_overlays::Set>& =inactive.sources,last_cause:const u8[:]& =inactive.last_cause}
fn valid(self_:const Snapshot&)->bool {return self_.slot!=0 && self_.slot-1<states.len && states[self_.slot-1].live && !states[self_.slot-1].frozen && states[self_.slot-1].generation==self_.generation;}
fn init(options:Options)->Snapshot,Error {
 if states.len>=0xffffffff {return Snapshot{},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State{live:true,generation:generation,options:copyOptions(options)});let state:State& =states[at];return Snapshot{(at+1) as u32,generation,state.options,state.paths,state.files,state.imports,state.path_index,state.file_index,state.import_index,state.digests,state.counts,state.sources,state.last_cause},blot_error::Error.none;
}
fn initWithSources(options:Options,sources:const blot_reuse_source_overlays::Source[:])->Snapshot,Error {let value,error=init(options);if error!=blot_error::Error.none {return Snapshot{},error;}var result=value;if sources.len!=0 {let value,error=blot_reuse_source_overlays::init(sources,options);if error!=blot_error::Error.none {result.deinit();return Snapshot{},error;}result.sources=blot_support::some(value);}return result,blot_error::Error.none;}
fn deinitIndexes(self_:Snapshot&) {self_.path_index.deinit(index_pool);self_.file_index.deinit(index_pool);for slot in self_.import_index.slots {if slot.tag!=0 {free(slot.key);}}self_.import_index.deinit(index_pool);self_.digests.deinit(digest_pool);}
fn destroy(slot:u32,generation:u64) {assert(slot!=0 && slot-1<states.len && states[slot-1].live && states[slot-1].generation==generation);let at=slot-1;let state:State& =states[at];if state.sources.present {state.sources.value.deinit();}freeOptions(state.options);for entry in state.paths.items {entry.deinit();}for entry in state.files.items {entry.deinit();}for entry in state.imports.items {entry.deinit();}state.paths.deinit(entry_pool);state.files.deinit(entry_pool);state.imports.deinit(resolution_pool);state.path_index.deinit(index_pool);state.file_index.deinit(index_pool);for slot in state.import_index.slots {if slot.tag!=0 {free(slot.key);}}state.import_index.deinit(index_pool);state.digests.deinit(digest_pool);free(state.last_cause);state=State{};states.free(at);}
fn deinit(self_:Snapshot&) {if self_.slot==0 {return;}assert(self_.valid());destroy(self_.slot,self_.generation);self_=Snapshot{};}
fn view(self_:const Snapshot&)->View {assert(self_.valid());return View{self_.options,self_.paths.items,self_.files.items,self_.imports.items,self_.counts};}
struct Frozen {slot:u32=0,generation:u64=0,record:Record=default<Record>(),sources:blot_support::Option<blot_reuse_source_overlays::Set> =blot_support::none<blot_reuse_source_overlays::Set>()}
fn frozenOwner(slot:u32,generation:u64)->Frozen {let state:const State& =states[slot-1];return Frozen{slot,generation,Record{Settings{state.options},Observations{state.paths.items,state.files.items,state.imports.items},Acquired{state.counts}},state.sources};}
fn freeze(self_:Snapshot&)->Frozen {assert(self_.valid());self_.deinitIndexes();let state:State& =states[self_.slot-1];state.frozen=true;let result=frozenOwner(self_.slot,self_.generation);self_=Snapshot{};return result;}
fn deinit(self_:Frozen&) {if self_.slot!=0 {destroy(self_.slot,self_.generation);}self_=Frozen{};}
fn frozenView(slot:u32,generation:u64)->View {assert(slot!=0 && states[slot-1].live && states[slot-1].frozen && states[slot-1].generation==generation);let state:const State& =states[slot-1];return View{state.options,state.paths.items,state.files.items,state.imports.items,state.counts};}
fn view(self_:const Frozen&)->View {return frozenView(self_.slot,self_.generation);}
fn capturedSource(self_:const Frozen&,path:const u8[:])->Text {return self_.view().capturedSource(path);}
fn capturedSource(self_:const Snapshot&,path:const u8[:])->Text {assert(self_.valid());let position .= self_.file_index.get(path);if !position {return blot_support::none<const u8[:]>();}return success(self_.files.items[position].result);}
fn lookup(entries:const Entry[:],index:const blot_support_pooled_map::Map<const u8[:],u32>&,key:const u8[:])->blot_support::Option<Outcome> {let position .= index.get(key);if !position {return blot_support::none<Outcome>();}return blot_support::some(entries[position].result);}
fn publish(self_:Snapshot&,entries:blot_support_pooled_buffer::Buffer<Entry>&,index:blot_support_pooled_map::Map<const u8[:],u32>&,key:const u8[:],result:Outcome)->Outcome,Error {
 if entries.items.len>=0xffffffff {result.deinit();return Outcome.inactive,blot_error::Error.out_of_memory;}let error=entries.ensure(entries.items.len+1,entry_pool);if error!=blot_error::Error.none {result.deinit();return Outcome.inactive,error;}
 if index.slots.len==0 {index.grow(8,index_pool);}else if (index.count+1)*3>index.slots.len*2 {index.grow(index.slots.len*2,index_pool);}
 let owned=own(key);let position=entries.items.len as u32;let error=entries.push(Entry{owned,result},entry_pool);if error!=blot_error::Error.none {free(owned);result.deinit();return Outcome.inactive,error;}index.insert(owned,position,index_pool);return result,blot_error::Error.none;
}
fn clearCause(self_:Snapshot&) {free(self_.last_cause);self_.last_cause=default<const u8[:]>();}
fn setCause(self_:Snapshot&,cause:const u8[:]) {let owned=own(cause);self_.clearCause();self_.last_cause=owned;}
fn observedValue(self_:Snapshot&,result:Outcome)->const u8[:],Error {match result {failure payload=>{self_.setCause(payload.cause);},_=>{self_.clearCause();}}return value(result);}
fn canonical(self_:Snapshot&,path:const u8[:])->const u8[:],Error {
 if !self_.valid() {return default<const u8[:]>(),blot_error::Error.invalid_artifact;}let old=lookup(self_.paths.items,self_.path_index,path);if old.present {return self_.observedValue(old.value);}self_.counts.canonical_reads++;
 var result=Outcome.inactive;var name:u8[>..<]=[];
 if self_.sources.present {let error=blot_reuse_source_overlays::canonicalPath(path,name);if error==blot_error::Error.out_of_memory {return default<const u8[:]>(),error;}if error!=blot_error::Error.none {result=Outcome.failure{error,blot_error::error_name(error)};}else if self_.sources.value.files.contains(name[..]) {result=Outcome.bytes{own(name[..])};}}
 if result==Outcome.inactive {var inputs=blot_reuse_project::FileInputs{};name.clear();let error=inputs.canonical(path,name);if error==blot_error::Error.out_of_memory {return default<const u8[:]>(),error;}if error!=blot_error::Error.none {result=Outcome.failure{error,inputs.cause(error)};}else {result=Outcome.bytes{own(name[..])};}}
 let published,error=self_.publish(self_.paths,self_.path_index,path,result);if error!=blot_error::Error.none {return default<const u8[:]>(),error;}return self_.observedValue(published);
}
fn read(self_:Snapshot&,path:const u8[:])->const u8[:],Error {
 if !self_.valid() {return default<const u8[:]>(),blot_error::Error.invalid_artifact;}let old=lookup(self_.files.items,self_.file_index,path);if old.present {return self_.observedValue(old.value);}self_.counts.source_reads++;let cap=min(self_.options.max_source_bytes,4294967295)+1;var result=Outcome.inactive;
 if self_.sources.present {let found .= self_.sources.value.files.get(path);if found {if found.present {result=Outcome.bytes{own(found.value)};}else {result=Outcome.failure{blot_error::Error.file_not_found,"FileNotFound"};}}}
 if result==Outcome.inactive {var inputs=blot_reuse_project::FileInputs{};var bytes:u8[>..<]=[];let error=inputs.read(path,cap,bytes);if error==blot_error::Error.out_of_memory {return default<const u8[:]>(),error;}if error!=blot_error::Error.none {result=Outcome.failure{error,inputs.cause(error)};}else {result=Outcome.bytes{own(bytes[..])};}}
 let published,error=self_.publish(self_.files,self_.file_index,path,result);if error!=blot_error::Error.none {return default<const u8[:]>(),error;}return self_.observedValue(published);
}
fn resolve(self_:Snapshot&,source:const u8[:],request:const u8[:])->const u8[:],Error {
 if !self_.valid() {return default<const u8[:]>(),blot_error::Error.invalid_artifact;}var key:u8[>..<]=[];let length=source.len as u64;for shift in 0..8 {key.push((length>>(shift*8)) as! u8);}key.append(source);key.append(request);
 let prior .= self_.import_index.get(key[..]);if prior {let result=self_.imports.items[prior].result;match result {bytes payload=>{return payload.value,blot_error::Error.none;},failure=>{return default<const u8[:]>(),blot_error::Error.invalid_path;},inactive=>{abort("inactive import observation");}}}
 self_.counts.resolutions++;var bytes:u8[>..<]=[];let error=blot_reuse_project::resolveImportPath(source,request,self_.options,bytes);if error==blot_error::Error.out_of_memory {return default<const u8[:]>(),error;}if error!=blot_error::Error.none && error!=blot_error::Error.invalid_path {return default<const u8[:]>(),error;}var result:Outcome=Outcome.failure{blot_error::Error.invalid_path,"InvalidPath"};if error==blot_error::Error.none {result=Outcome.bytes{own(bytes[..])};}
 var published=false;
 if self_.imports.items.len>=0xffffffff {let __cleanup_result_1_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_1_1: Error = blot_error::Error.out_of_memory; {if !published {result.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}let error=self_.imports.ensure(self_.imports.items.len+1,resolution_pool);if error!=blot_error::Error.none {let __cleanup_result_2_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_2_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}
 if self_.import_index.slots.len==0 {self_.import_index.grow(8,index_pool);}else if (self_.import_index.count+1)*3>self_.import_index.slots.len*2 {self_.import_index.grow(self_.import_index.slots.len*2,index_pool);}
 let position=self_.imports.items.len as u32;let owned_source=own(source);let owned_request=own(request);let error=self_.imports.push(Resolution{owned_source,owned_request,result},resolution_pool);if error!=blot_error::Error.none {free(owned_source);free(owned_request);let __cleanup_result_3_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_3_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;}self_.import_index.insert(own(key[..]),position,index_pool);published=true;let __cleanup_result_4_0, __cleanup_result_4_1 = value(result); {if !published {result.deinit();}} return __cleanup_result_4_0, __cleanup_result_4_1;
 {if !published {result.deinit();}} }
fn sourceDigest(self_:Snapshot&,path:const u8[:],bytes:const u8[:])->Digest,Error {assert(self_.valid());let position .= self_.file_index.get(path);if !position {return blot_support_blake3::hash(bytes),blot_error::Error.none;}match self_.files.items[position].result {bytes payload=>{assert(blot_support::same_slice_identity(payload.value,bytes));},_=>{abort("digest requires successful captured source");}}let position_value:u32=position;let found .= self_.digests.get(position_value);if found {return found,blot_error::Error.none;}let digest=blot_support_blake3::hash(bytes);self_.digests.insert(position_value,digest,digest_pool);return digest,blot_error::Error.none;}
struct Provider {snapshot:Snapshot=Snapshot{}}
fn provider(self_:Snapshot&)->Provider {assert(self_.valid());return Provider{self_};}
fn canonical(self_:Provider&,path:const u8[:],output:u8[>..<]&)->Error {let bytes,error=self_.snapshot.canonical(path);if error!=blot_error::Error.none {return error;}output.append(bytes);return blot_error::Error.none;}
fn read(self_:Provider&,path:const u8[:],limit:i64,output:u8[>..<]&)->Error {let bytes,error=self_.snapshot.read(path);if error!=blot_error::Error.none {return error;}if bytes.len>limit {self_.snapshot.setCause("StreamTooLong");return blot_error::Error.stream_too_long;}output.append(bytes);return blot_error::Error.none;}
fn resolve(self_:Provider&,source:const u8[:],request:const u8[:],options:Options,output:u8[>..<]&)->Error {let bytes,error=self_.snapshot.resolve(source,request);if error!=blot_error::Error.none {return error;}output.append(bytes);return blot_error::Error.none;}
fn cause(self_:const Provider&,error:Error)->const u8[:] {if self_.snapshot.last_cause.len!=0 {return self_.snapshot.last_cause;}return blot_error::error_name(error);}
fn optionalTextEqual(left:Text,right:Text)->bool {if left.present!=right.present {return false;}if !left.present {return true;}return left.value==right.value;}
fn entryPathEqualsPrevious(self_:Snapshot&,requested:const u8[:],old_canonical:const u8[:])->bool,Error {let path,error=self_.canonical(requested);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}return path==old_canonical,blot_error::Error.none;}
fn entryEqualsPrevious(self_:Snapshot&,requested:const u8[:],old_canonical:const u8[:],previous:View)->bool,Error {
 let same,error=self_.entryPathEqualsPrevious(requested,old_canonical);if error!=blot_error::Error.none || !same {return false,error;}let captured=get(previous.files,old_canonical);if !captured.present {return false,blot_error::Error.none;}let expected=success(captured.value);if !expected.present {return false,blot_error::Error.none;}let actual,error=self_.read(old_canonical);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}return expected.value==actual,blot_error::Error.none;
}
fn equalsPrevious(self_:Snapshot&,previous:View)->bool,Error {return self_.matchesPrevious(previous,false);}
fn triviaEqualsPrevious(self_:Snapshot&,previous:View)->bool,Error {return self_.matchesPrevious(previous,true);}
fn matchesPrevious(self_:Snapshot&,previous:View,trivia:bool)->bool,Error {
 let left=self_.options;let right=previous.options;
 // Keep the source's exact option schema guard next to its explicit comparison.
 var option_fields:i64=0;const for <N,A> in fields<Options> {option_fields++;}var alias_fields:i64=0;const for <N,A> in fields<Alias> {alias_fields++;}assert(option_fields==7 && alias_fields==2);
 if left.input_mode!=right.input_mode || left.max_source_bytes!=right.max_source_bytes || left.max_total_source_bytes!=right.max_total_source_bytes || left.max_files!=right.max_files || !optionalTextEqual(left.prelude_path,right.prelude_path) || !optionalTextEqual(left.std_root,right.std_root) || left.aliases.len!=right.aliases.len {return false,blot_error::Error.none;}
 for actual,index in left.aliases {let old=right.aliases[index];if actual.prefix!=old.prefix || actual.root!=old.root {return false,blot_error::Error.none;}}
 if previous.files.len==0 {return false,blot_error::Error.none;}var total:i64=0;
 for entry in previous.paths {let expected=success(entry.result);if !expected.present {return false,blot_error::Error.none;}let actual,error=self_.canonical(entry.key);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none || expected.value!=actual {return false,blot_error::Error.none;}}
 for entry in previous.files {
  let expected=success(entry.result);if !expected.present {return false,blot_error::Error.none;}let actual,error=self_.read(entry.key);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}
  if expected.value!=actual {if !trivia || actual.len>self_.options.max_source_bytes {return false,blot_error::Error.none;}let same,error=sameTokens(expected.value,actual);if error!=blot_error::Error.none || !same {return false,error;}}
  if actual.len>0x7fffffffffffffff-total {total=0x7fffffffffffffff;}else {total+=actual.len;}
 }
 if total>self_.options.max_total_source_bytes {return false,blot_error::Error.none;}
 for entry in previous.imports {let expected=success(entry.result);if !expected.present {return false,blot_error::Error.none;}let actual,error=self_.resolve(entry.source,entry.request);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none || expected.value!=actual {return false,blot_error::Error.none;}}return true,blot_error::Error.none;
}
fn sameTokens(left:const u8[:],right:const u8[:])->bool,Error {
 var old_tokens:blot_parse_token::Token[>..<]=[];var old_comments:blot_parse_token::Token[>..<]=[];var old_issues:blot_parse_lexer::Diagnostic[>..<]=[];var before=blot_parse_lexer::init(old_tokens,old_comments,old_issues);let error=blot_parse_lexer::lex(left,before);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}
 var new_tokens:blot_parse_token::Token[>..<]=[];var new_comments:blot_parse_token::Token[>..<]=[];var new_issues:blot_parse_lexer::Diagnostic[>..<]=[];var after=blot_parse_lexer::init(new_tokens,new_comments,new_issues);let error=blot_parse_lexer::lex(right,after);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}
 if old_issues.len!=0 || new_issues.len!=0 || old_tokens.len!=new_tokens.len {return false,blot_error::Error.none;}
 for old,index in old_tokens {let new=new_tokens[index];if old.tag!=new.tag || blot_parse_token::text(old,left)!=blot_parse_token::text(new,right) {return false,blot_error::Error.none;}if index!=0 && (old_tokens[index-1].end==old.start)!=(new_tokens[index-1].end==new.start) {return false,blot_error::Error.none;}}return true,blot_error::Error.none;
}
fn releaseMask(mask:bool[:]) {if mask.len!=0 {mask_pool.free_slice(mask);}}
fn reusableModules(self_:Snapshot&,seed:const blot_reuse_frozen_dependency::FrozenDependency&)->blot_support::Option<bool[:]>,Error {return self_.reuseMask(seed,true);}
fn libraryModules(self_:Snapshot&,seed:const blot_reuse_frozen_dependency::FrozenDependency&)->blot_support::Option<bool[:]>,Error {return self_.reuseMask(seed,false);}
fn reuseMask(self_:Snapshot&,seed:const blot_reuse_frozen_dependency::FrozenDependency&,changed_only:bool)->blot_support::Option<bool[:]>,Error {
 if self_.options.input_mode!=blot_reuse_project::InputMode.project || seed.modules.len==0 || seed.modules.len>=self_.options.max_files {return blot_support::none<bool[:]>(),blot_error::Error.none;}
 let reuse=mask_pool.alloc_slice(seed.modules.len);for &same in reuse {same=false;}var transferred=false;var total:i64=0;var prelude=blot_support::none<i64>();
 for module,index in seed.modules {
  let canonical_path,error=self_.canonical(module.identity.normalized_path);if error==blot_error::Error.out_of_memory {let __cleanup_result_5_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_5_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_5_0, __cleanup_result_5_1;}if error!=blot_error::Error.none || canonical_path!=module.identity.normalized_path {let __cleanup_result_6_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_6_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_6_0, __cleanup_result_6_1;}
  let bytes,error=self_.read(canonical_path);if error==blot_error::Error.out_of_memory {let __cleanup_result_7_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_7_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_7_0, __cleanup_result_7_1;}if error!=blot_error::Error.none {let __cleanup_result_8_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_8_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_8_0, __cleanup_result_8_1;}
  if bytes.len>self_.options.max_source_bytes || bytes.len>max(self_.options.max_total_source_bytes-total,0) {let __cleanup_result_9_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_9_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_9_0, __cleanup_result_9_1;}total+=bytes.len;
  let digest,error=self_.sourceDigest(canonical_path,bytes);if error!=blot_error::Error.none {let __cleanup_result_10_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_10_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_10_0, __cleanup_result_10_1;}reuse[index]=bytes.len==module.identity.source_bytes && digest==module.identity.source_digest;
  if module.identity.prelude {if prelude.present || !self_.options.prelude_path.present {let __cleanup_result_11_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_11_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_11_0, __cleanup_result_11_1;}let actual,error=self_.canonical(self_.options.prelude_path.value);if error==blot_error::Error.out_of_memory {let __cleanup_result_12_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_12_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_12_0, __cleanup_result_12_1;}if error!=blot_error::Error.none || actual!=canonical_path {let __cleanup_result_13_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_13_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_13_0, __cleanup_result_13_1;}prelude=blot_support::some(index);}
  if reuse[index] {for request in module.source_imports {if request.target==0 || request.target>seed.modules.len {let __cleanup_result_14_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_14_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_14_0, __cleanup_result_14_1;}let resolved,error=self_.resolve(canonical_path,request.path);if error==blot_error::Error.out_of_memory {let __cleanup_result_15_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_15_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_15_0, __cleanup_result_15_1;}if error!=blot_error::Error.none {let __cleanup_result_16_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_16_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_16_0, __cleanup_result_16_1;}let target,error=self_.canonical(resolved);if error==blot_error::Error.out_of_memory {let __cleanup_result_17_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_17_1: Error = error; {if !transferred {releaseMask(reuse);}} return __cleanup_result_17_0, __cleanup_result_17_1;}if error!=blot_error::Error.none || target!=seed.modules[request.target-1].identity.normalized_path {let __cleanup_result_18_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_18_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_18_0, __cleanup_result_18_1;}}}
 }
 var dictionary_budget:i64=0x7fffffffffffffff;if total<=0x3fffffffffffffff {dictionary_budget=max(65536,total*2);}for symbol in seed.symbols {if symbol.text.len>dictionary_budget {let __cleanup_result_19_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_19_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_19_0, __cleanup_result_19_1;}dictionary_budget-=symbol.text.len;}
 if prelude.present!=self_.options.prelude_path.present {let __cleanup_result_20_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_20_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_20_0, __cleanup_result_20_1;}var changed=true;
 while changed {changed=false;for module,index in seed.modules {if !reuse[index] {continue;}for target in module.imports {if target==0 || target>reuse.len {let __cleanup_result_21_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_21_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_21_0, __cleanup_result_21_1;}if !reuse[target-1] {reuse[index]=false;changed=true;break;}}}}
 if prelude.present && !reuse[prelude.value] {let __cleanup_result_22_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_22_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_22_0, __cleanup_result_22_1;}var count:i64=0;for same in reuse {if same {count++;}}if changed_only && count==reuse.len {let __cleanup_result_23_0: blot_support::Option<bool[:]> = blot_support::none<bool[:]>(); let __cleanup_result_23_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_23_0, __cleanup_result_23_1;}transferred=true;let __cleanup_result_24_0: blot_support::Option<bool[:]> = blot_support::some(reuse); let __cleanup_result_24_1: Error = blot_error::Error.none; {if !transferred {releaseMask(reuse);}} return __cleanup_result_24_0, __cleanup_result_24_1;
 {if !transferred {releaseMask(reuse);}} }
fn admits(self_:Snapshot&,seed:const blot_reuse_frozen_dependency::FrozenDependency&)->bool,Error {
 if self_.options.input_mode!=blot_reuse_project::InputMode.project || seed.modules.len>=self_.options.max_files {return false,blot_error::Error.none;}var total:i64=0;var found_prelude=false;
 for module in seed.modules {
  let canonical_path,error=self_.canonical(module.identity.normalized_path);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}let bytes,error=self_.read(canonical_path);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}let digest,error=self_.sourceDigest(canonical_path,bytes);if error!=blot_error::Error.none {return false,error;}if blot_reuse_dependency_closure::validateProducerDigest(module,canonical_path,bytes.len,digest)!=blot_error::Error.none {return false,blot_error::Error.none;}
  if bytes.len>self_.options.max_source_bytes || bytes.len>max(self_.options.max_total_source_bytes-total,0) {return false,blot_error::Error.none;}total+=bytes.len;
  if module.identity.prelude {if !self_.options.prelude_path.present {return false,blot_error::Error.none;}let prelude,error=self_.canonical(self_.options.prelude_path.value);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none || prelude!=canonical_path {return false,blot_error::Error.none;}found_prelude=true;}
  for request in module.source_imports {if request.target==0 || request.target>seed.modules.len {return false,blot_error::Error.none;}let resolved,error=self_.resolve(canonical_path,request.path);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none {return false,blot_error::Error.none;}let target,error=self_.canonical(resolved);if error==blot_error::Error.out_of_memory {return false,error;}if error!=blot_error::Error.none || target!=seed.modules[request.target-1].identity.normalized_path {return false,blot_error::Error.none;}}
 }return found_prelude==self_.options.prelude_path.present,blot_error::Error.none;
}
// Portable views borrow byte runs; only their three header arrays are owned.
struct Pair {key:const u8[:]=default<const u8[:]>(),value:const u8[:]=default<const u8[:]>()}
struct PersistedImport {source:const u8[:]=default<const u8[:]>(),request:const u8[:]=default<const u8[:]>(),value:const u8[:]=default<const u8[:]>()}
struct Wire {options:Options,paths:const Pair[:],files:const Pair[:],imports:const PersistedImport[:]}
reusable[] var pairs_pool:Pair[>..]=[];
reusable[] var persisted_imports_pool:PersistedImport[>..]=[];
struct Persisted {wire:Wire=default<Wire>(),paths:const Entry[:]=default<const Entry[:]>(),files:const Entry[:]=default<const Entry[:]>(),imports:const Resolution[:]=default<const Resolution[:]>(),owner:Frozen=Frozen{}}
fn capturePersisted(owner:const Frozen&)->blot_support::Option<Wire>,Error {
 let record=owner.view();
 let paths=pairs_pool.alloc_slice(record.paths.len);let files=pairs_pool.alloc_slice(record.files.len);let imports=persisted_imports_pool.alloc_slice(record.imports.len);var published=false;
 for entry,index in record.paths {let bytes=success(entry.result);if !bytes.present {let __cleanup_result_25_0: blot_support::Option<Wire> = blot_support::none<Wire>(); let __cleanup_result_25_1: Error = blot_error::Error.none; {if !published {releaseWire(Wire{record.options,paths,files,imports});}} return __cleanup_result_25_0, __cleanup_result_25_1;}paths[index]=Pair{ownedText(entry.key),ownedText(bytes.value)};}for entry,index in record.files {let bytes=success(entry.result);if !bytes.present {let __cleanup_result_26_0: blot_support::Option<Wire> = blot_support::none<Wire>(); let __cleanup_result_26_1: Error = blot_error::Error.none; {if !published {releaseWire(Wire{record.options,paths,files,imports});}} return __cleanup_result_26_0, __cleanup_result_26_1;}files[index]=Pair{ownedText(entry.key),ownedText(bytes.value)};}for entry,index in record.imports {let bytes=success(entry.result);if !bytes.present {let __cleanup_result_27_0: blot_support::Option<Wire> = blot_support::none<Wire>(); let __cleanup_result_27_1: Error = blot_error::Error.none; {if !published {releaseWire(Wire{record.options,paths,files,imports});}} return __cleanup_result_27_0, __cleanup_result_27_1;}imports[index]=PersistedImport{ownedText(entry.source),ownedText(entry.request),ownedText(bytes.value)};}published=true;let __cleanup_result_28_0: blot_support::Option<Wire> = blot_support::some(Wire{record.options,paths,files,imports}); let __cleanup_result_28_1: Error = blot_error::Error.none; {if !published {releaseWire(Wire{record.options,paths,files,imports});}} return __cleanup_result_28_0, __cleanup_result_28_1;
 {if !published {releaseWire(Wire{record.options,paths,files,imports});}} }
fn releaseWire(wire:Wire) {if wire.paths.len!=0 {pairs_pool.free_slice(wire.paths);}if wire.files.len!=0 {pairs_pool.free_slice(wire.files);}if wire.imports.len!=0 {persisted_imports_pool.free_slice(wire.imports);}}
fn cloneWire(wire:Wire)->Persisted,Error {
 let value,error=init(wire.options);if error!=blot_error::Error.none {return Persisted{},error;}var snapshot=value;var transferred=false;
 for pair in wire.paths {let outcome,error=snapshot.publish(snapshot.paths,snapshot.path_index,pair.key,Outcome.bytes{own(pair.value)});if error!=blot_error::Error.none {let __cleanup_result_29_0: Persisted = Persisted{}; let __cleanup_result_29_1: Error = error; {if !transferred {snapshot.deinit();}} return __cleanup_result_29_0, __cleanup_result_29_1;}}for pair in wire.files {let outcome,error=snapshot.publish(snapshot.files,snapshot.file_index,pair.key,Outcome.bytes{own(pair.value)});if error!=blot_error::Error.none {let __cleanup_result_30_0: Persisted = Persisted{}; let __cleanup_result_30_1: Error = error; {if !transferred {snapshot.deinit();}} return __cleanup_result_30_0, __cleanup_result_30_1;}}
 for entry in wire.imports {let result=Resolution{own(entry.source),own(entry.request),Outcome.bytes{own(entry.value)}};let error=snapshot.imports.push(result,resolution_pool);if error!=blot_error::Error.none {result.deinit();let __cleanup_result_31_0: Persisted = Persisted{}; let __cleanup_result_31_1: Error = error; {if !transferred {snapshot.deinit();}} return __cleanup_result_31_0, __cleanup_result_31_1;}}
 var owner=snapshot.freeze();transferred=true;let captured,error=capturePersisted(owner);if error!=blot_error::Error.none {owner.deinit();let __cleanup_result_32_0: Persisted = Persisted{}; let __cleanup_result_32_1: Error = error; {if !transferred {snapshot.deinit();}} return __cleanup_result_32_0, __cleanup_result_32_1;}assert(captured.present);let view=owner.view();let __cleanup_result_33_0: Persisted = Persisted{captured.value,view.paths,view.files,view.imports,owner}; let __cleanup_result_33_1: Error = blot_error::Error.none; {if !transferred {snapshot.deinit();}} return __cleanup_result_33_0, __cleanup_result_33_1;
 {if !transferred {snapshot.deinit();}} }
// Decoded wire always arrives with its typed decoder owner. Success consumes
// that owner; failure leaves it intact. No const-cast or foreign-pool free occurs.
fn adoptPersisted<W>(decoded:W&)->Persisted,Error {let result,error=cloneWire(decoded.value);if error!=blot_error::Error.none {return Persisted{},error;}decoded.deinit();return result,blot_error::Error.none;}
fn deinit(self_:Persisted&) {releaseWire(self_.wire);self_.owner.deinit();self_=Persisted{};}
fn view(self_:const Persisted&)->View {return View{self_.wire.options,self_.paths,self_.files,self_.imports,Counts{}};}
