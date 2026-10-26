// Producer for one closed source adapter; independent consumer replays the
// exact kernel, formal proof and adapter token stream before use.
namespace m12_adapter_build;
import lexer;
import i08_link_build;
import i08_link_affine;
import i08_transition_build;
import m12_adapter_core;
import m12_adapter_schema;
fn kind(s:u8[:])->i64 {if s=="begin_append" {return 1;}if s=="project" {return 2;}if s=="open" {return 3;}if s=="pack" {return 4;}if s=="return" {return 5;}return 0;}
fn build(kernel:u8[:],adapter:u8[:])->m12_adapter_core::Program,i64 {
 if kernel.len==0 || adapter.len==0 || kernel.len+adapter.len>65536 {return m12_adapter_core::Program {},2;}
 if kernel[kernel.len-1]!='\n' {return m12_adapter_core::Program {},1;}
 var linked,status=i08_link_build::build(kernel);if status!=0{return m12_adapter_core::Program {},status;}
 let a=i08_link_affine::build(linked,kernel);if a.status!=0{return m12_adapter_core::Program {},1;}
 let proof=i08_transition_build::build(linked,kernel,a.plan);if proof.status!=0{return m12_adapter_core::Program {},1;}
 let schema=m12_adapter_schema::source();var lx=lexer::init(adapter);var tx=lexer::init(schema);var events:m12_adapter_core::Event[>..]=[];
 while true {let t=lexer::next(adapter,lx);let e=lexer::next(schema,tx);if t.kind==9 || e.kind==9 || t.kind!=e.kind {return m12_adapter_core::Program {},1;}
  if t.kind==0 {break;}if t.kind>=1 && t.kind<=5 {if t.start<0 || t.end<=t.start || t.end>adapter.len || e.start<0 || e.end<=e.start || e.end>schema.len || adapter[t.start..t.end]!=schema[e.start..e.end] {return m12_adapter_core::Program {},1;}
   let k=kind(adapter[t.start..t.end]);if k!=0 {events.push(m12_adapter_core::Event {kind:k,site:kernel.len+t.start});}
  }
 }
 if events.len!=5 {return m12_adapter_core::Program {},1;}
 var module:u8[>..]=[];module.append(kernel);module.append(adapter);
 return m12_adapter_core::Program {module:copy(module),split:kernel.len,linked:copy(linked),affine:a.plan,transition:proof.proof,events:copy(events)},0;
}
