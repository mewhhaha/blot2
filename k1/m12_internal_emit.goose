// Scratch wrapper emitter: appends one fixed source-bound internal invocation
// function to the independently checked one-module fixture. Raw exports are
// still test-only; this is not a public ABI or ownership certificate.
namespace m12_internal_emit;
import m12_adapter_core;
import m12_adapter_verify;
import m12_one_emit;
import m12_one_target;
import m12_internal_body;
import m12_internal_target;
import i08_same_target;
import pool_guest;
fn emit(p:m12_adapter_core::Program&,source:u8[:])->u8[] {
 if !m12_adapter_verify::verify(p,source) {return [];}
 let base=m12_one_emit::emit(p,source);if base.len<8 || !m12_one_target::verify(p,source,base) {return [];}
 var cursor:i64=8;var out:u8[>..]=[];out.append(base[..8]);
 let t=i08_same_target::section(base,cursor,1);if !t.ok {return [];}out.append(base[t.start..t.end]);cursor=t.end;
 let f=i08_same_target::section(base,cursor,3);if !f.ok || f.payload>=f.end || base[f.payload]!=22 {return [];}
 var funcs:u8[>..]=[23];funcs.append(base[f.payload+1..f.end]);funcs.push(3);pool_guest::section(out,3,funcs);cursor=f.end;
 let m=i08_same_target::section(base,cursor,5);if !m.ok {return [];}out.append(base[m.start..m.end]);cursor=m.end;
 let e=i08_same_target::section(base,cursor,7);if !e.ok || e.payload>=e.end || base[e.payload]!=16 {return [];}
 var exports:u8[>..]=[17];exports.append(base[e.payload+1..e.end]);exports.append([6,'i','n','v','o','k','e',0,22]);pool_guest::section(out,7,exports);cursor=e.end;
 let code=i08_same_target::section(base,cursor,10);if !code.ok || code.end!=base.len || code.payload>=code.end || base[code.payload]!=22 {return [];}
 var bodies:u8[>..]=[23];bodies.append(base[code.payload+1..code.end]);let invoke=m12_internal_body::body();if invoke.len==0 {return [];}pool_guest::add_body(bodies,invoke);pool_guest::section(out,10,bodies);if !m12_internal_target::verify(p,source,out) {return [];}return out;
}
