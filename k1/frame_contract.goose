// Private, conditional frame-plan derivation for one exact emitted fixture.
// The exact source and full target are independently rechecked. Contract
// treats fixed helper bodies as trusted zero-language-frame components; it is
// NOT a general M11/ABI/resource certificate or engine-stack guarantee.
namespace frame_contract;
import m12_adapter_core;
import m12_adapter_verify;
import m12_internal_target;
struct Slot {offset:u32=0,size:u32=0}
// wrapper_depth is source-contract arithmetic only; machine_path records
// six Wasm calls. `qualified` must remain false until adapters/helpers are
// classified and their frame contributions are independently checked.
struct Plan {kernel_depth:u32=0,kernel_frame:u32=0,adapter_depth:u32=0,adapter_frame:u32=0,
 wrapper_depth:u32=0,machine_path:u32=0,fixed_frontier:u32=0,qualified:bool=false,wrapper_span:u32=0,adapter_local:u32=0,reserved:u32=0,slots:Slot[5]=[Slot {};5]}
fn slots()->Slot[5] {return [Slot {offset:0,size:24},Slot {offset:32,size:8},Slot {offset:128,size:20},Slot {offset:160,size:16},Slot {offset:176,size:256}];}
// Span arithmetic is subtraction-checked before addition; ranges are half-open.
fn geometry(a:Slot[5],limit:u32)->bool {
 for x,i in a {if x.offset>limit || x.size>limit-x.offset || (x.offset&3)!=0 || (x.size&3)!=0 {return false;}
  for y,j in a {if j>=i || x.size==0 || y.size==0 {continue;}if x.offset<y.offset+y.size && y.offset<x.offset+x.size {return false;}}
 }
 return true;
}
fn create(p:m12_adapter_core::Program&,source:u8[:],target:u8[:])->Plan,bool {
 if !m12_adapter_verify::verify(p,source) || !m12_internal_target::verify(p,source,target) {return Plan {},false;}
 let plan=Plan {kernel_depth:2,kernel_frame:256,adapter_depth:3,adapter_frame:512,wrapper_depth:4,machine_path:6,fixed_frontier:0,qualified:false,wrapper_span:176,adapter_local:40,reserved:768,slots:slots()};
 return plan,verify(p,source,target,plan);
}
// Rechecks source-specific literal contracts and exact target binding before
// trusting the private slot map. m12_adapter_verify independently re-lexes the
// exact kernel and adapter signatures, including 2/256 and 3/512 declarations.
fn verify(p:m12_adapter_core::Program&,source:u8[:],target:u8[:],x:Plan)->bool {
 if !m12_adapter_verify::verify(p,source) || !m12_internal_target::verify(p,source,target) {return false;}
 if x.kernel_depth!=2 || x.kernel_frame!=256 || x.adapter_depth!=3 || x.adapter_frame!=512 ||
    x.wrapper_depth!=4 || x.machine_path!=6 || x.fixed_frontier!=0 || x.qualified || x.wrapper_span!=176 || x.adapter_local!=40 || x.reserved!=768 || x.slots!=slots() {return false;}
 if x.kernel_depth==0 || x.kernel_depth>=128 || x.adapter_depth<=x.kernel_depth || x.wrapper_depth<=x.adapter_depth || x.wrapper_depth>128 {return false;}
 if x.adapter_local>x.adapter_frame || x.kernel_frame>x.adapter_frame-x.adapter_local {return false;}
 if x.wrapper_span>x.reserved || x.adapter_frame>x.reserved-x.wrapper_span {return false;}
 return geometry(x.slots,x.reserved);
}
// Abstract subtraction preflight only: the actual fixed adapter requires
// frontier zero. These arithmetic results do not establish target support.
fn reserve(capacity:u32,top:u32,needed:u32)->u32,bool {
 if top>capacity || needed>capacity-top {return top,false;}return top+needed,true;
}
