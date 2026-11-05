// Short-lived canonical ownership views; only temporary coordinate arrays are owned.
namespace blot_backend_activation_model;
import support.error;
import support.option;
import reuse.code_artifacts;
import check.core;
import .activation_intersection;
import .runtime_identity;
type Error=blot_error::Error;
type Model=blot_backend_activation_intersection::Model;
type Function=blot_reuse_code_artifacts::Function;
type Span=blot_reuse_code_artifacts::Span;
type Operation=blot_reuse_code_artifacts::Operation;
type Request=blot_reuse_code_artifacts::Request;
struct Borrowed {borrowed:Model,functions:Function[:],rows:Span[:],templates:Span[:],operations:Operation[:]}
reusable[] var function_runs:Function[>..]=[];
reusable[] var span_runs:Span[>..]=[];
reusable[] var operation_runs:Operation[>..]=[];
fn model(self_:const Borrowed&)->Model {var result=self_.borrowed;result.functions=self_.functions;result.rows.spans=self_.rows;result.templates.spans=self_.templates;result.operations=self_.operations;return result;}
fn spanCopy(store)->Span[:] {let result=span_runs.alloc_slice(store.spans.len);for &to,index in result {let from=store.spans[index];to=Span{start:from.start,len:from.len};}return result;}
fn init(generator,identity:blot_support::Option<blot_backend_runtime_identity::View>)->Borrowed,Error {var functions:Function[>..<]=[];
 generator.planning.instances.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.named{key:key},function:function,..}); }
 generator.planning.closures.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.closure{key:key},function:function,..}); }
 generator.planning.callables.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.callable{key:key},function:function,..}); }
 generator.planning.constructor_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.constructor{key:key},function:function,..}); }
 generator.planning.primitive_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.primitive{key:key},function:function,..}); }
 generator.planning.operation_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.operation{key:key},function:function,..}); }
 generator.planning.host_functions.each() { key,function => functions.push(Function{request:blot_reuse_code_artifacts::Request.host{key:key},function:function,..}); }
 let rows=spanCopy(generator.representations.row_keys);let templates=spanCopy(generator.representations.template_keys);let symbols=operation_runs.alloc_slice(generator.planning.runtime_operations.entries.len);for &to,index in symbols {let from=generator.planning.runtime_operations.entries[index];to=Operation{key:generator.planning.runtime_operations.key(from),foreign:from.foreign,runtime:from.runtime};}let owned=function_runs.alloc_slice(functions.len);for function,index in functions {owned[index]=function;}let borrowed=Model{units:generator.units,functions:[],evidence:generator.evaluator.storage.evidence.view(),rows:blot_reuse_code_artifacts::Substitutions{entries:generator.representations.row_keys.entries,spans:[]},templates:blot_reuse_code_artifacts::Substitutions{entries:generator.representations.template_keys.entries,spans:[]},captures:generator.planning.template_catalog.items,operations:[],identity:identity};return Borrowed{borrowed:borrowed,functions:owned,rows:rows,templates:templates,operations:symbols},blot_error::Error.none;}
fn deinit(self_:Borrowed&) {if self_.functions.len!=0 {function_runs.free_slice(self_.functions);}if self_.rows.len!=0 {span_runs.free_slice(self_.rows);}if self_.templates.len!=0 {span_runs.free_slice(self_.templates);}if self_.operations.len!=0 {operation_runs.free_slice(self_.operations);}self_.functions=[];self_.rows=[];self_.templates=[];self_.operations=[];}
fn fromPools(units:const blot_check_core::Module[:],pools:const blot_reuse_code_artifacts::Pools&)->Model {var identity=blot_support::none<blot_backend_runtime_identity::View>();if pools.identity.present {identity=blot_support::some(pools.identity.value.view());}return Model{units:units,functions:pools.functions,evidence:pools.evaluator.evidence.view(),rows:pools.rows,templates:pools.templates,captures:pools.captures,operations:pools.operations,identity:identity};}

fn withBorrowed<G,C,F>(generator:G&,identity:blot_support::Option<blot_backend_runtime_identity::View>,context:C&)->Error {var borrowed,error=init(generator,identity);if error!=blot_error::Error.none {return error;}let result=F(context,borrowed.model());borrowed.deinit();return result;}
