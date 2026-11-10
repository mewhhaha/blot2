// Short-lived canonical views with fixed snapshots of growing substitutions.
namespace blot_backend_activation_model;
import support.error;
import support.option;
import reuse.code_artifacts;
import check.core;
import .activation_intersection;
import .runtime_identity;
import .backend_plan;
import .runtime_operations;
import .optimizer_buffers;
type Error=blot_error::Error;
type Model=blot_backend_activation_intersection::Model;
type Function=blot_reuse_code_artifacts::Function;
type Span=blot_reuse_code_artifacts::Span;
type Operation=blot_reuse_code_artifacts::Operation;
type Request=blot_reuse_code_artifacts::Request;
struct Borrowed {borrowed:Model,functions:Function[:],rows:blot_reuse_code_artifacts::Substitutions,templates:blot_reuse_code_artifacts::Substitutions,operations:Operation[:]}
reusable[] var function_runs:Function[>..]=[];
reusable[] var operation_runs:Operation[>..]=[];
fn model(self_:const Borrowed&)->Model {return Model{units:self_.borrowed.units,functions:self_.functions,evidence:self_.borrowed.evidence,rows:self_.rows,templates:self_.templates,captures:self_.borrowed.captures,operations:self_.operations,identity:self_.borrowed.identity};}
fn registeredCaptures(value:blot_backend_backend_plan::TemplateCatalog)->const blot_reuse_code_artifacts::CapturedTemplate[:] {
 assert(value.len==value.items.len && value.len>=0 && value.len<=value.storage.len);
 if value.len==0 {return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>();}
 let owned=blot_backend_backend_plan::template_catalog_runs.realloc_slice(value.storage,value.storage.len);assert(blot_support::same_slice_identity(owned,value.storage));
 let start=blot_backend_backend_plan::template_catalog_runs.index_of(owned[0]);let result=blot_backend_backend_plan::template_catalog_runs[start..start+value.len];assert(blot_support::same_slice_identity(result,value.items));return result;
}
fn registeredOperationKey(value:blot_backend_runtime_operations::Store,entry:blot_backend_runtime_operations::Entry)->const u8[:] {
 let bytes=value.key_bytes;assert(bytes.len==bytes.items.len && bytes.len>=0 && bytes.len<=bytes.storage.len);
 assert(entry.key.start>=0 && entry.key.len>=0 && entry.key.start<=bytes.len && entry.key.len<=bytes.len-entry.key.start);
 if entry.key.len==0 {return default<const u8[:]>();}
 let owned=blot_backend_optimizer_buffers::pool_Bytes.realloc_slice(bytes.storage,bytes.storage.len);assert(blot_support::same_slice_identity(owned,bytes.storage));
 let start=blot_backend_optimizer_buffers::pool_Bytes.index_of(owned[0]);let items=blot_backend_optimizer_buffers::pool_Bytes[start..start+bytes.len];assert(blot_support::same_slice_identity(items,bytes.items));return items[entry.key.start..entry.key.start+entry.key.len];
}
fn init(generator,identity:blot_support::Option<blot_backend_runtime_identity::View>)->Borrowed,Error {var functions:Function[>..<]=[];
 generator.planning.instances.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.named{key:key},function:function,..}); }
 generator.planning.closures.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.closure{key:key},function:function,..}); }
 generator.planning.callables.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.callable{key:key},function:function,..}); }
 generator.planning.constructor_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.constructor{key:key},function:function,..}); }
 generator.planning.primitive_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.primitive{key:key},function:function,..}); }
 generator.planning.operation_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.operation{key:key},function:function,..}); }
 generator.planning.host_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.host{key:key},function:function,..}); }
 let rows=blot_reuse_code_artifacts::capture(generator.representations.row_keys);let templates=blot_reuse_code_artifacts::capture(generator.representations.template_keys);let symbols=operation_runs.alloc_slice(generator.planning.runtime_operations.entries.len);for &to,index in symbols {let from=generator.planning.runtime_operations.entries[index];to=Operation{key:registeredOperationKey(generator.planning.runtime_operations,from),foreign:from.foreign,runtime:from.runtime};}let owned=function_runs.alloc_slice(functions.len);for function,index in functions {owned[index]=function;}let borrowed=Model{units:generator.units,functions:default<const Function[:]>(),evidence:generator.evaluator.storage.evidence.view(),rows:rows,templates:templates,captures:registeredCaptures(generator.planning.template_catalog),operations:default<const Operation[:]>(),identity:identity};return Borrowed{borrowed:borrowed,functions:owned,rows:rows,templates:templates,operations:symbols},blot_error::Error.none;}
fn deinit(self_:Borrowed&) {if self_.functions.len!=0 {function_runs.free_slice(self_.functions);}self_.rows.deinit();self_.templates.deinit();if self_.operations.len!=0 {operation_runs.free_slice(self_.operations);}self_.functions=default<Function[:]>();self_.operations=default<Operation[:]>();}
fn fromPools(units:const blot_check_core::Module[:],pools:const blot_reuse_code_artifacts::Pools&)->Model {var identity=blot_support::none<blot_backend_runtime_identity::View>();if pools.identity.present {identity=blot_support::some(pools.identity.value.view());}return Model{units:units,functions:pools.functions,evidence:pools.evaluator.evidence.view(),rows:pools.rows,templates:pools.templates,captures:pools.captures,operations:pools.operations,identity:identity};}

fn withBorrowed<G,C,F>(generator:G&,identity:blot_support::Option<blot_backend_runtime_identity::View>,context:C&)->Error {var borrowed,error=init(generator,identity);if error!=blot_error::Error.none {return error;}let result=F(context,borrowed.model());borrowed.deinit();return result;}
