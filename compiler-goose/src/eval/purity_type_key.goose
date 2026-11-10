// Frozen state_specialize TypeKey grammar with fixed recursive descriptors.
namespace blot_eval_purity_type_key;
import check.effects;
import check.types;
import parse.lexer;
import support.error;
import support.pooled_buffer;

import std;
type Error=blot_error::Error;
enum Kind { nominal,operation }
struct Identity { module: const u8[:],declaration: const u8[:] }
struct BytePart { value: const u8[:]=default<const u8[:]>() }
struct IdentityRun { bytes: u8[:]=default<u8[:]>() }
reusable[] var key_bytes: u8[>..]=[];
reusable[] var identity_runs: IdentityRun[>..]=[];
reusable[] var saved_words: u32[>..]=[];
// Sort owned encodings by their original byte ranges; no source header escapes into scratch.
struct SavedIdentity {encoded:const u8[:],module_start:i64,module_len:i64,declaration_start:i64}
reusable[] var saved_identities: SavedIdentity[>..]=[];
struct IdentityRuns { storage: IdentityRun[:]=default<IdentityRun[:]>(),items: IdentityRun[:]=default<IdentityRun[:]>() }
fn push(self_: IdentityRuns&,run: IdentityRun) -> Error { return blot_support_pooled_buffer::push(self_,run,identity_runs); }
fn deinit(self_: IdentityRuns&) { for run in self_.items { if run.bytes.len!=0 { key_bytes.free_slice(run.bytes); } } blot_support_pooled_buffer::deinit(self_,identity_runs); }
struct BytesBuffer { storage: u8[:]=default<u8[:]>(),items: u8[:]=default<u8[:]>() }
fn append(self_: BytesBuffer&,bytes: const u8[:]) -> Error { return blot_support_pooled_buffer::append(self_,bytes,key_bytes); }
fn deinit(self_: BytesBuffer&) { blot_support_pooled_buffer::deinit(self_,key_bytes); }
fn finish(self_: const BytesBuffer&) -> const u8[:],Error { return join([BytePart {self_.items}]); }
struct Context<S> { types: blot_check_types::Store,source: S,identities: IdentityRuns=IdentityRuns {} }
fn initContext<S>(types: blot_check_types::Store,source: S) -> Context<S>,Error { return Context<S> {types,source},blot_error::Error.none; }
fn deinit<S>(self_: Context<S>&) { self_.identities.deinit(); }
fn release(bytes: const u8[:]) { if bytes.len!=0 { key_bytes.free_slice(bytes); } }
fn join(parts: const BytePart[:]) -> const u8[:],Error { var length: i64=0; for part in parts { if part.value.len>0x7fffffffffffffff-length { return default<const u8[:]>(),blot_error::Error.out_of_memory; } length+=part.value.len; } let bytes=key_bytes.alloc_slice(length); var at=0; for part in parts { for byte in part.value { bytes[at]=byte; at++; } } return bytes,blot_error::Error.none; }
fn count(text: const u8[:]) -> i64,Error { var at=0; var points=0; while at<text.len { let width=blot_parse_lexer::utf8_width(text[at]); if width==0||width>text.len-at { return 0,blot_error::Error.type_limit; } let point,error=blot_parse_lexer::decode_point(text[at..at+width]); if error!=blot_error::Error.none { return 0,blot_error::Error.type_limit; } points++; at+=width; } return points,blot_error::Error.none; }
fn pack(text: const u8[:]) -> const u8[:],Error { let length,error=count(text); if error!=blot_error::Error.none { return default<const u8[:]>(),error; } let prefix=str(length,":"); return join([BytePart {prefix},BytePart {text}]); }
fn nominal(identity: Identity) -> const u8[:],Error { let module,error=pack(identity.module); if error!=blot_error::Error.none { return default<const u8[:]>(),error; } let declaration,e=pack(identity.declaration); if e!=blot_error::Error.none { release(module); return default<const u8[:]>(),e; } let result,joined=join([BytePart {module},BytePart {declaration}]); release(declaration); release(module); return result,joined; }
fn fixed<S>(self_: Context<S>&,module: const u8[:],declaration: const u8[:]) -> Identity,Error {
 if declaration.len>0x7fffffffffffffff-module.len { return default<Identity>(),blot_error::Error.out_of_memory; } let bytes=key_bytes.alloc_slice(module.len+declaration.len); for byte,index in module { bytes[index]=byte; } for byte,index in declaration { bytes[module.len+index]=byte; } let error=self_.identities.push(IdentityRun {bytes}); if error!=blot_error::Error.none { key_bytes.free_slice(bytes); return default<Identity>(),error; } return Identity {bytes[..module.len],bytes[module.len..]},blot_error::Error.none;
}
recursive fn typesKey<S>(self_: Context<S>&,values: const u32[:],fuel: i64) -> const u8[:],Error {
 let owned=saved_words.alloc_slice(values.len); for value,index in values { owned[index]=value; }  var remaining=fuel; var bytes=BytesBuffer {};
 for value in owned { if remaining==0 { let __cleanup_result_1_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_1_1: Error = blot_error::Error.specialization_limit; { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_1_0, __cleanup_result_1_1; } remaining--; let key,error=typeKey(self_,value,remaining); if error!=blot_error::Error.none { let __cleanup_result_2_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_2_1: Error = error; { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_2_0, __cleanup_result_2_1; } let packed,e=pack(key); release(key); if e!=blot_error::Error.none { let __cleanup_result_3_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_3_1: Error = e; { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_3_0, __cleanup_result_3_1; } let appended=bytes.append(packed); release(packed); if appended!=blot_error::Error.none { let __cleanup_result_4_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_4_1: Error = appended; { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_4_0, __cleanup_result_4_1; } }
 if remaining==0 { let __cleanup_result_5_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_5_1: Error = blot_error::Error.specialization_limit; { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_5_0, __cleanup_result_5_1; } let __cleanup_result_6_0, __cleanup_result_6_1 = bytes.finish(); { bytes.deinit(); } { saved_words.free_slice(owned); } return __cleanup_result_6_0, __cleanup_result_6_1;
 { bytes.deinit(); } { saved_words.free_slice(owned); } }
// Dynamic source results end their scope before recursive key construction.
fn savedArguments<S>(self_:Context<S>&,identity:blot_check_types::NominalIdentity,kind:Kind,actual:const u32[:])->u32[:],Error {
 let values,error=self_.source.arguments(identity,kind,actual);if error!=blot_error::Error.none {return default<u32[:]>(),error;}
 let saved=saved_words.alloc_slice(values.len);for value,index in values {saved[index]=value;}return saved,blot_error::Error.none;
}
recursive fn operation<S>(self_: Context<S>&,label: u32,fuel: i64) -> Identity,Error {
 let operation=self_.types.operation(label); if label==blot_check_types::foreign_operation { return fixed(self_,"blot:compiler","Foreign"); }
 if operation.identity.unit==0xffffffff&&(operation.identity.decl==1||operation.identity.decl==2) { let arguments=self_.types.list(operation.arguments); if arguments.len!=1 { return default<Identity>(),blot_error::Error.ambiguous_type_key; } let key,error=typeKey(self_,arguments[0],fuel); if error!=blot_error::Error.none { return default<Identity>(),error; } var action: const u8[:]="write"; if operation.identity.decl==1 { action="read"; } let declaration,e=join([BytePart {action},BytePart {":"},BytePart {key}]); release(key); if e!=blot_error::Error.none { return default<Identity>(),e; } let result,e2=fixed(self_,"blot:state",declaration); release(declaration); return result,e2; }
 let identity,error=self_.source.origin(operation.identity,Kind.operation); if error!=blot_error::Error.none { return default<Identity>(),error; } let arguments,e=savedArguments(self_,operation.identity,Kind.operation,self_.types.list(operation.arguments)); if e!=blot_error::Error.none { return default<Identity>(),e; } if arguments.len==0&&operation.arguments.len==0 { saved_words.free_slice(arguments);return identity,blot_error::Error.none; } let key,e2=typesKey(self_,arguments,fuel);saved_words.free_slice(arguments); if e2!=blot_error::Error.none { return default<Identity>(),e2; } let declaration,e3=join([BytePart {identity.declaration},BytePart {"<"},BytePart {key},BytePart {">"}]); release(key); if e3!=blot_error::Error.none { return default<Identity>(),e3; } let result,e4=fixed(self_,identity.module,declaration); release(declaration); return result,e4;
}
fn compareBytes(a:const u8[:],b:const u8[:])->i64 {
 var index:i64=0;while index<a.len && index<b.len {if a[index]<b[index] {return -1;}if a[index]>b[index] {return 1;}index+=1;}
 if a.len<b.len {return -1;}if a.len>b.len {return 1;}return 0;
}
fn savedIdentity(identity:Identity)->SavedIdentity,Error {
 let name,error=nominal(identity);if error!=blot_error::Error.none {return default<SavedIdentity>(),error;}
 let owned=key_bytes.realloc_slice(name,name.len);assert(blot_support::same_slice_identity(owned,name));
 var module_start:i64=0;while owned[module_start]!=58 {module_start++;}module_start++;
 var declaration_start=module_start+identity.module.len;while owned[declaration_start]!=58 {declaration_start++;}declaration_start++;
 return SavedIdentity{encoded:owned,module_start:module_start,module_len:identity.module.len,declaration_start:declaration_start},blot_error::Error.none;
}
fn less(left:SavedIdentity,right:SavedIdentity)->bool {
 let module=compareBytes(left.encoded[left.module_start..left.module_start+left.module_len],right.encoded[right.module_start..right.module_start+right.module_len]);
 if module!=0 {return module<0;}
 return compareBytes(left.encoded[left.declaration_start..],right.encoded[right.declaration_start..])<0;
}
fn releaseIdentities(identities:SavedIdentity[:],initialized:i64) {
 for index in initialized {release(identities[index].encoded);}saved_identities.free_slice(identities);
}
recursive fn rowKey<S>(self_:Context<S>&,row:u32,fuel:i64)->const u8[:],Error {
 let resolved,error=self_.types.resolveEffects(row,0);if error!=blot_error::Error.none {return default<const u8[:]>(),error;}
 if self_.types.row(resolved).tail!=blot_check_effects::Tail.closed {return default<const u8[:]>(),blot_error::Error.ambiguous_type_key;}
 let source=self_.types.rowLabels(resolved);let labels=saved_words.alloc_slice(source.len);for label,index in source {labels[index]=label;}
 let identities=saved_identities.alloc_slice(labels.len);var initialized:i64=0;var encoding_error=blot_error::Error.none;
 for label,index in labels {
  let identity,error=operation(self_,label,65536);if error!=blot_error::Error.none {releaseIdentities(identities,initialized);saved_words.free_slice(labels);return default<const u8[:]>(),error;}
  if encoding_error!=blot_error::Error.none {continue;}
  let saved,error=savedIdentity(identity);if error!=blot_error::Error.none {encoding_error=error;continue;}
  identities[index]=saved;initialized++;
 }
 if encoding_error!=blot_error::Error.none {releaseIdentities(identities,initialized);saved_words.free_slice(labels);return default<const u8[:]>(),encoding_error;}
 ::sort(identities,less);var bytes=BytesBuffer{};
 for identity in identities {
  let key,error=pack(identity.encoded);if error!=blot_error::Error.none {bytes.deinit();releaseIdentities(identities,initialized);saved_words.free_slice(labels);return default<const u8[:]>(),error;}
  let error=bytes.append(key);release(key);if error!=blot_error::Error.none {bytes.deinit();releaseIdentities(identities,initialized);saved_words.free_slice(labels);return default<const u8[:]>(),error;}
 }
 let result,error=bytes.finish();bytes.deinit();releaseIdentities(identities,initialized);saved_words.free_slice(labels);return result,error;
}
recursive fn functionKey<S>(self_: Context<S>&,parameter_id: u32,result_id: u32,row: u32,fuel: i64) -> const u8[:],Error {
 if fuel==0 { return default<const u8[:]>(),blot_error::Error.specialization_limit; } let parameter,error=typeKey(self_,parameter_id,fuel-1); if error!=blot_error::Error.none { return default<const u8[:]>(),error; }  let result,e=typeKey(self_,result_id,fuel-1); if e!=blot_error::Error.none { let __cleanup_result_12_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_12_1: Error = e; { release(parameter); } return __cleanup_result_12_0, __cleanup_result_12_1; }  let effects,e2=rowKey(self_,row,fuel-1); if e2!=blot_error::Error.none { let __cleanup_result_13_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_13_1: Error = e2; { release(result); } { release(parameter); } return __cleanup_result_13_0, __cleanup_result_13_1; }  let pk,e3=pack(parameter); if e3!=blot_error::Error.none { let __cleanup_result_14_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_14_1: Error = e3; { release(effects); } { release(result); } { release(parameter); } return __cleanup_result_14_0, __cleanup_result_14_1; }  let rk,e4=pack(result); if e4!=blot_error::Error.none { let __cleanup_result_15_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_15_1: Error = e4; { release(pk); } { release(effects); } { release(result); } { release(parameter); } return __cleanup_result_15_0, __cleanup_result_15_1; }  let ek,e5=pack(effects); if e5!=blot_error::Error.none { let __cleanup_result_16_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_16_1: Error = e5; { release(rk); } { release(pk); } { release(effects); } { release(result); } { release(parameter); } return __cleanup_result_16_0, __cleanup_result_16_1; }  let __cleanup_result_17_0, __cleanup_result_17_1 = join([BytePart {"c"},BytePart {pk},BytePart {rk},BytePart {ek}]); { release(ek); } { release(rk); } { release(pk); } { release(effects); } { release(result); } { release(parameter); } return __cleanup_result_17_0, __cleanup_result_17_1;
 { release(ek); } { release(rk); } { release(pk); } { release(effects); } { release(result); } { release(parameter); } }
recursive fn typeKey<S>(self_: Context<S>&,id: u32,fuel: i64) -> const u8[:],Error {
 if fuel==0 { return default<const u8[:]>(),blot_error::Error.specialization_limit; } let rest=fuel-1; let resolved,error=self_.types.resolve(id,0); if error!=blot_error::Error.none { return default<const u8[:]>(),error; } let node=self_.types.node(resolved); let tag=node.tag;
 if tag==blot_check_types::Tag.unit { return join([BytePart {"u"}]); } if tag==blot_check_types::Tag.unsigned32 { return join([BytePart {"i"}]); } if tag==blot_check_types::Tag.floating32 { return join([BytePart {"f"}]); } if tag==blot_check_types::Tag.boolean { return join([BytePart {"b"}]); }
 if tag==blot_check_types::Tag.nominal { let identity=blot_check_types::NominalIdentity {node.a,node.b}; let origin,e=self_.source.origin(identity,Kind.nominal); if e!=blot_error::Error.none { return default<const u8[:]>(),e; } let name,e2=nominal(origin); if e2!=blot_error::Error.none { return default<const u8[:]>(),e2; }  let logical,e3=savedArguments(self_,identity,Kind.nominal,self_.types.nominalArguments(node)); if e3!=blot_error::Error.none { let __cleanup_result_18_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_18_1: Error = e3; { release(name); } return __cleanup_result_18_0, __cleanup_result_18_1; } let arguments,e4=typesKey(self_,logical,rest);saved_words.free_slice(logical); if e4!=blot_error::Error.none { let __cleanup_result_19_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_19_1: Error = e4; { release(name); } return __cleanup_result_19_0, __cleanup_result_19_1; }  let packed,e5=pack(arguments); if e5!=blot_error::Error.none { let __cleanup_result_20_0: const u8[:] = default<const u8[:]>(); let __cleanup_result_20_1: Error = e5; { release(arguments); } { release(name); } return __cleanup_result_20_0, __cleanup_result_20_1; }  let __cleanup_result_21_0, __cleanup_result_21_1 = join([BytePart {"n"},BytePart {name},BytePart {packed}]); { release(packed); } { release(arguments); } { release(name); } return __cleanup_result_21_0, __cleanup_result_21_1;  { release(packed); } { release(arguments); } { release(name); } }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor { let element,e=typeKey(self_,node.a,rest); if e!=blot_error::Error.none { return default<const u8[:]>(),e; } let key,e2=pack(element); release(element); if e2!=blot_error::Error.none { return default<const u8[:]>(),e2; } var prefix: const u8[:]="a"; if tag==blot_check_types::Tag.cursor { prefix="c"; } else if tag==blot_check_types::Tag.list { prefix="l"; } let result,e3=join([BytePart {prefix},BytePart {key}]); release(key); return result,e3; }
 if tag==blot_check_types::Tag.product { let elements,e=typesKey(self_,self_.types.extra.items[node.a..node.a+node.b],rest); if e!=blot_error::Error.none { return default<const u8[:]>(),e; } let key,e2=pack(elements); release(elements); if e2!=blot_error::Error.none { return default<const u8[:]>(),e2; } let result,e3=join([BytePart {"p"},BytePart {key}]); release(key); return result,e3; } if tag==blot_check_types::Tag.function { return functionKey(self_,node.a,node.b,node.c,fuel); } return default<const u8[:]>(),blot_error::Error.ambiguous_type_key;
}
