// Fixed source-bound bridge lowering. Independent Core replay precedes all
// output; typed operations and branch policies directly emit the caller body.
namespace bridge_plan_emit;
import bridge_plan_core;
import bridge_plan_verify;
import bridge_direct_body;
import m12_adapter_core;
import m12_one_emit;
import m12_one_target;

import m12_internal_target;
import i08_same_target;
import pool_guest;
fn emit(p:m12_adapter_core::Program&,source:u8[:],plan:bridge_plan_core::Plan&)->u8[] {
 if !bridge_plan_verify::verify(p,source,plan){return [];}
 let base=m12_one_emit::emit(p,source);if base.len<8 || !m12_one_target::verify(p,source,base){return [];}
 let code=bridge_direct_body::body(plan);if code.len==0{return [];}
 // Assemble a fresh module directly; no whole caller is emitted before Core.
 var cursor:i64=8;var out:u8[>..]=[];out.append(base[..8]);
 let t=i08_same_target::section(base,cursor,1);if !t.ok{return [];}out.append(base[t.start..t.end]);cursor=t.end;
 let fsec=i08_same_target::section(base,cursor,3);if !fsec.ok || fsec.payload>=fsec.end || base[fsec.payload]!=22{return [];}
 var funcs:u8[>..]=[23];funcs.append(base[fsec.payload+1..fsec.end]);funcs.push(3);pool_guest::section(out,3,funcs);cursor=fsec.end;
 let m=i08_same_target::section(base,cursor,5);if !m.ok{return [];}out.append(base[m.start..m.end]);cursor=m.end;
 let e=i08_same_target::section(base,cursor,7);if !e.ok || e.payload>=e.end || base[e.payload]!=16{return [];}
 var exports:u8[>..]=[17];exports.append(base[e.payload+1..e.end]);exports.append([6,'i','n','v','o','k','e',0,22]);pool_guest::section(out,7,exports);cursor=e.end;
 let c=i08_same_target::section(base,cursor,10);if !c.ok || c.end!=base.len || c.payload>=c.end || base[c.payload]!=22{return [];}
 var bodies:u8[>..]=[23];bodies.append(base[c.payload+1..c.end]);pool_guest::add_body(bodies,code);pool_guest::section(out,10,bodies);
 if !m12_internal_target::verify(p,source,out){return [];}
 return copy(out);
}
