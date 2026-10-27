// Native witness only. The process-private runtime state, input handle and
// single Clock remain trusted. This is not K1 target/ABI admission.
namespace source_owned_run;
import source_owned_core;
import source_owned_verify;
import ownership_check;
import ownership_runtime;
import owned_scalar_runtime;
fn run(s:u8[:],p:source_owned_core::Program&,state:owned_scalar_runtime::State&,handle:owned_scalar_runtime::Handle,flag:bool)->ownership_runtime::Result {
 if !source_owned_verify::verify(s,p) {return ownership_runtime::Result {};}
 let h=p.head;var owner:u8[>..]=[];owner.append(s[h.owner_start..h.owner_end]);var condition:u8[>..]=[];condition.append(s[h.flag_start..h.flag_end]);
 var c=ownership_check::Contract {owner:copy(owner),flag:copy(condition),return_mode:h.mode};
 return ownership_runtime::run(p.tree,s[h.body..],c,state,handle,flag);
}
