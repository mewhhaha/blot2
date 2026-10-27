// Explicit private policy: status in high U32, scalar in low U32.
namespace scalar_host_emit;
import generic_bool_core;
import generic_bool_verify;
import generic_bool_wasm;
import generic_bool_target;
import scalar_host_policy;
import scalar_host_verify;
import i08_same_target;
import pool_guest;
fn emit(source:u8[:],p:generic_bool_core::Program&)->u8[] {
 if !generic_bool_verify::verify(source,p) || p.head.depth!=1 || p.head.frame!=0{return [];}
 let base=generic_bool_wasm::emit(source,p);if base.len<8 || !generic_bool_target::verify(source,p,base){return [];}
 var at:i64=8;var out:u8[>..]=[];out.append(base[..8]);
 let ty=i08_same_target::section(base,at,1);if !ty.ok || base[ty.payload..ty.end]!=[1 as u8,0x60,2,0x7f,0x7f,1,0x7f]{return [];}
 pool_guest::section(out,1,[2 as u8,0x60,2,0x7f,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7e]);at=ty.end;
 let f=i08_same_target::section(base,at,3);if !f.ok || base[f.payload..f.end]!=[1 as u8,0]{return [];}pool_guest::section(out,3,[2 as u8,0,1]);at=f.end;
 let m=i08_same_target::section(base,at,5);if !m.ok{return [];}out.append(base[m.start..m.end]);at=m.end;
 let e=i08_same_target::section(base,at,7);if !e.ok{return [];}pool_guest::section(out,7,[1 as u8,6,'i','n','v','o','k','e',0,1]);at=e.end;
 let code=i08_same_target::section(base,at,10);if !code.ok || code.payload>=code.end || base[code.payload]!=1{return [];}
 var bodies:u8[>..]=[2];bodies.append(base[code.payload+1..code.end]);let wrapper=scalar_host_policy::body();pool_guest::add_body(bodies,wrapper);pool_guest::section(out,10,bodies);at=code.end;
 let custom=i08_same_target::section(base,at,0);if !custom.ok || custom.end!=base.len{return [];}out.append(base[custom.start..custom.end]);
 if !scalar_host_verify::verify(source,p,out){return [];}return copy(out);
}
