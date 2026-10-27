// Source/target-bound private runtime wrapper; not a public ABI.
namespace leaf_runtime_emit;
import typed_canonical_core;
import typed_canonical_wasm;
import typed_canonical_target;
import leaf_resource_core;
import leaf_resource_verify;
import leaf_runtime_body;
import leaf_runtime_verify;
import i08_same_target;
import pool_guest;
fn emit(source:u8[:],p:typed_canonical_core::Program&,s:leaf_resource_core::Summary&)->u8[] {
 let base=typed_canonical_wasm::emit(source,p);if base.len<8 || !typed_canonical_target::verify(source,p,base) || !leaf_resource_verify::verify(source,p,base,s){return [];}
 var pos:i64=8;var out:u8[>..]=[];out.append(base[..8]);
 let t=i08_same_target::section(base,pos,1);if !t.ok || base[t.payload..t.end]!=[1 as u8,0x60,2,0x7f,0x7f,1,0x7f]{return [];}
 pool_guest::section(out,1,[2 as u8,0x60,2,0x7f,0x7f,1,0x7f,0x60,1,0x7f,1,0x7e]);pos=t.end;
 let f=i08_same_target::section(base,pos,3);if !f.ok || base[f.payload..f.end]!=[1 as u8,0]{return [];}pool_guest::section(out,3,[2 as u8,0,1]);pos=f.end;
 let m=i08_same_target::section(base,pos,5);if !m.ok{return [];}out.append(base[m.start..m.end]);pos=m.end;
 let e=i08_same_target::section(base,pos,7);if !e.ok{return [];}pool_guest::section(out,7,[1 as u8,6,'i','n','v','o','k','e',0,1]);pos=e.end;
 let code=i08_same_target::section(base,pos,10);if !code.ok || code.payload>=code.end || base[code.payload]!=1{return [];}
 var bodies:u8[>..]=[2];bodies.append(base[code.payload+1..code.end]);let wrapper=leaf_runtime_body::body(s.declared_depth,s.declared_frame);pool_guest::add_body(bodies,wrapper);pool_guest::section(out,10,bodies);pos=code.end;
 let custom=i08_same_target::section(base,pos,0);if !custom.ok || custom.end!=base.len{return [];}out.append(base[custom.start..custom.end]);
 if !leaf_runtime_verify::verify(source,p,s,out){return [];}return copy(out);
}
