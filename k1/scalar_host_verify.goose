// Exact source/target association and independently fixed wrapper bytes.
// This is not a general ABI, M11 qualification, or source capability.
namespace scalar_host_verify;
import generic_bool_core;
import generic_bool_verify;
import generic_bool_wasm;
import generic_bool_target;
import i08_same_target;
fn verify(source:u8[:],p:generic_bool_core::Program&,candidate:u8[:])->bool {
 if !generic_bool_verify::verify(source,p) || p.head.depth!=1 || p.head.frame!=0 || candidate.len<8 || candidate.len>65536{return false;}
 let base=generic_bool_wasm::emit(source,p);if base.len<8 || !generic_bool_target::verify(source,p,base) || candidate[..8]!=base[..8]{return false;}
 var a:i64=8;var b:i64=8;
 let ty=i08_same_target::section(candidate,a,1);let bt=i08_same_target::section(base,b,1);if !ty.ok || !bt.ok || base[bt.payload..bt.end]!=[1 as u8,0x60,2,0x7f,0x7f,1,0x7f] || candidate[ty.payload..ty.end]!=[2 as u8,0x60,2,0x7f,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7e]{return false;}a=ty.end;b=bt.end;
 let f=i08_same_target::section(candidate,a,3);let bf=i08_same_target::section(base,b,3);if !f.ok || !bf.ok || base[bf.payload..bf.end]!=[1 as u8,0] || candidate[f.payload..f.end]!=[2 as u8,0,1]{return false;}a=f.end;b=bf.end;
 let m=i08_same_target::section(candidate,a,5);let bm=i08_same_target::section(base,b,5);if !m.ok || !bm.ok || candidate[m.start..m.end]!=base[bm.start..bm.end]{return false;}a=m.end;b=bm.end;
 let e=i08_same_target::section(candidate,a,7);let be=i08_same_target::section(base,b,7);if !e.ok || !be.ok || candidate[e.payload..e.end]!=[1 as u8,6,'i','n','v','o','k','e',0,1]{return false;}a=e.end;b=be.end;
 let c=i08_same_target::section(candidate,a,10);let bc=i08_same_target::section(base,b,10);if !c.ok || !bc.ok || c.payload>=c.end || bc.payload>=bc.end || candidate[c.payload]!=2 || base[bc.payload]!=1 {return false;}
 let prefix=bc.end-bc.payload-1;if prefix<0 || prefix>c.end-c.payload-1 || candidate[c.payload+1..c.payload+1+prefix]!=base[bc.payload+1..bc.end]{return false;}
 let at=c.payload+1+prefix;let n=i08_same_target::read_leb(candidate,at,c.end);let expected:u8[46]=[0,0x20,0,0x41,1,0x4b,0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x10,0x0f,0x0b,0x20,1,0x41,2,0x49,0x20,1,0x41,0x80,1,0x4b,0x72,0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x20,0x0f,0x0b,0x41,0,0x20,0,0x10,0,0xad,0x0b];
 if !n.ok || n.value!=expected.len || n.next+n.value!=c.end || candidate[n.next..c.end]!=expected[..]{return false;}a=c.end;b=bc.end;
 let custom=i08_same_target::section(candidate,a,0);let old=i08_same_target::section(base,b,0);return custom.ok && old.ok && custom.end==candidate.len && old.end==base.len && candidate[custom.start..custom.end]==base[old.start..old.end];
}
