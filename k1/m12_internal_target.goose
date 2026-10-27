// Source-bound complete byte check for one fixed private caller. The previous
// 22 functions are checked against the independently validated source target;
// the appended caller is pinned separately. This is not a general validator.
namespace m12_internal_target;
import m12_adapter_core;
import m12_adapter_verify;
import m12_one_emit;
import m12_one_target;
import m12_internal_golden;
import i08_same_target;
fn verify(p:m12_adapter_core::Program&,source:u8[:],candidate:u8[:])->bool {
 if !m12_adapter_verify::verify(p,source) || candidate.len<8 || candidate.len>65536 {return false;}
 let base=m12_one_emit::emit(p,source);if base.len<8 || !m12_one_target::verify(p,source,base) || candidate[..8]!=base[..8] {return false;}
 var a:i64=8;var z:i64=8;
 let t=i08_same_target::section(candidate,a,1);let bt=i08_same_target::section(base,z,1);if !t.ok || !bt.ok || candidate[t.start..t.end]!=base[bt.start..bt.end] {return false;}a=t.end;z=bt.end;
 let f=i08_same_target::section(candidate,a,3);let bf=i08_same_target::section(base,z,3);
 if !f.ok || !bf.ok || f.payload>=f.end || bf.payload>=bf.end || candidate[f.payload]!=23 || base[bf.payload]!=22 ||
    f.end-f.payload!=bf.end-bf.payload+1 || candidate[f.payload+1..f.end-1]!=base[bf.payload+1..bf.end] || candidate[f.end-1]!=3 {return false;}a=f.end;z=bf.end;
 let m=i08_same_target::section(candidate,a,5);let bm=i08_same_target::section(base,z,5);if !m.ok || !bm.ok || candidate[m.start..m.end]!=base[bm.start..bm.end] {return false;}a=m.end;z=bm.end;
 let e=i08_same_target::section(candidate,a,7);let be=i08_same_target::section(base,z,7);if !e.ok || !be.ok || e.payload>=e.end || be.payload>=be.end || candidate[e.payload]!=17 || base[be.payload]!=16 {return false;}
 let suffix:u8[9]=[6,'i','n','v','o','k','e',0,22];if e.end-e.payload!=be.end-be.payload+suffix.len || candidate[e.payload+1..e.end-suffix.len]!=base[be.payload+1..be.end] || candidate[e.end-suffix.len..e.end]!=suffix[..] {return false;}a=e.end;z=be.end;
 let c=i08_same_target::section(candidate,a,10);let bc=i08_same_target::section(base,z,10);if !c.ok || !bc.ok || c.end!=candidate.len || bc.end!=base.len || c.payload>=c.end || bc.payload>=bc.end || candidate[c.payload]!=23 || base[bc.payload]!=22 {return false;}
 let prefix=bc.end-bc.payload-1;if prefix>c.end-c.payload-1 || candidate[c.payload+1..c.payload+1+prefix]!=base[bc.payload+1..bc.end] {return false;}
 let start=c.payload+1+prefix;let n=i08_same_target::read_leb(candidate,start,c.end);if !n.ok || n.value>c.end-n.next || n.next+n.value!=c.end {return false;}
 let expected=m12_internal_golden::bytes();return candidate[n.next..c.end]==expected[..];
}
