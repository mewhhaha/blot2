// Independent exact source/target and wrapper-body checker, private only.
namespace leaf_runtime_verify;
import typed_canonical_core;
import typed_canonical_wasm;
import typed_canonical_target;
import leaf_resource_core;
import leaf_resource_verify;
import i08_same_target;
import wasm;
fn expect(depth:u32,frame:u32)->u8[] {
 var x:u8[>..]=[1,3,0x7f,0x41,0,0x28,2,0,0x21,1,0x41,4,0x28,2,0,0x21,2,
  0x20,1,0x41,0x80,1,0x4b,0x41,0x80,1,0x20,1,0x6b,0x41];
 wasm::signed_i32_leb(x,depth+1);x.append([0x49,0x72,0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x20,0x0f,0x0b,
  0x20,2,0x41,0x80,0x80,0xc0,0,0x4b,0x41,0x80,0x80,0xc0,0,0x20,2,0x6b,0x41]);
 wasm::signed_i32_leb(x,frame);x.append([0x49,0x72,0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x30,0x0f,0x0b,
  0x41,0,0x20,1,0x41]);wasm::signed_i32_leb(x,depth+1);
 x.append([0x6a,0x36,2,0,0x41,4,0x20,2,0x41]);wasm::signed_i32_leb(x,frame);
 x.append([0x6a,0x36,2,0,0x41,0,0x20,0,0x10,0,0x21,3,0x41,4,0x20,2,0x36,2,0,0x41,0,0x20,1,0x36,2,0,0x20,3,0xad,0x0b]);return copy(x);
}
fn verify(source:u8[:],p:typed_canonical_core::Program&,s:leaf_resource_core::Summary&,candidate:u8[:])->bool {
 let base=typed_canonical_wasm::emit(source,p);if base.len<8 || !typed_canonical_target::verify(source,p,base) || !leaf_resource_verify::verify(source,p,base,s) || candidate.len<8 || candidate.len>65536 || candidate[..8]!=base[..8]{return false;}
 var a:i64=8;var b:i64=8;
 let t=i08_same_target::section(candidate,a,1);let bt=i08_same_target::section(base,b,1);if !t.ok || !bt.ok || base[bt.payload..bt.end]!=[1 as u8,0x60,2,0x7f,0x7f,1,0x7f] || candidate[t.payload..t.end]!=[2 as u8,0x60,2,0x7f,0x7f,1,0x7f,0x60,1,0x7f,1,0x7e]{return false;}a=t.end;b=bt.end;
 let f=i08_same_target::section(candidate,a,3);let bf=i08_same_target::section(base,b,3);if !f.ok || !bf.ok || base[bf.payload..bf.end]!=[1 as u8,0] || candidate[f.payload..f.end]!=[2 as u8,0,1]{return false;}a=f.end;b=bf.end;
 let m=i08_same_target::section(candidate,a,5);let bm=i08_same_target::section(base,b,5);if !m.ok || !bm.ok || candidate[m.start..m.end]!=base[bm.start..bm.end]{return false;}a=m.end;b=bm.end;
 let e=i08_same_target::section(candidate,a,7);let be=i08_same_target::section(base,b,7);if !e.ok || !be.ok || candidate[e.payload..e.end]!=[1 as u8,6,'i','n','v','o','k','e',0,1]{return false;}a=e.end;b=be.end;
 let c=i08_same_target::section(candidate,a,10);let bc=i08_same_target::section(base,b,10);if !c.ok || !bc.ok || c.payload>=c.end || bc.payload>=bc.end || candidate[c.payload]!=2 || base[bc.payload]!=1{return false;}
 let n=bc.end-bc.payload-1;if n<0 || n>c.end-c.payload-1 || candidate[c.payload+1..c.payload+1+n]!=base[bc.payload+1..bc.end]{return false;}
 let pos=c.payload+1+n;let size=i08_same_target::read_leb(candidate,pos,c.end);let body=expect(s.declared_depth,s.declared_frame);
 if !size.ok || size.value!=body.len || size.next+size.value!=c.end || candidate[size.next..c.end]!=body[..]{return false;}a=c.end;b=bc.end;
 let custom=i08_same_target::section(candidate,a,0);let old=i08_same_target::section(base,b,0);return custom.ok && old.ok && custom.end==candidate.len && old.end==base.len && candidate[custom.start..custom.end]==base[old.start..old.end];
}
