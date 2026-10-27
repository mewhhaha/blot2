// Private source-associated caller entry. Every emission constructs and
// independently checks the compiler-owned bridge Core before lowering it.
// Raw exports, public ABI, capability authority and M11 remain unqualified.
namespace m12_internal_emit;
import m12_adapter_core;
import bridge_plan_build;
import bridge_plan_emit;
fn emit(p:m12_adapter_core::Program&,source:u8[:])->u8[] {
 var r=bridge_plan_build::build(p,source);if r.status!=0{return [];}
 return bridge_plan_emit::emit(p,source,r.plan);
}
