import source_owned_core;
import source_owned_admit;
import source_owned_verify;
fn main() {
 let s="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\n";
 var p=source_owned_admit::admit(s);assert(p.status==0);
 for i in s.len {var altered:u8[>..]=[];altered.append(s);altered[i]^=1;assert(!source_owned_verify::verify(altered,p.program));assert(!source_owned_verify::verify(s[..i],p.program));}
 let candidates:i64[]=[-1,0,1,9223372036854775807];
 for field in 6 {for value in candidates {var h=p.program.head;var old:i64=0;
  if field==0 {old=h.body;h.body=value;}else if field==1 {old=h.owner_start;h.owner_start=value;}else if field==2 {old=h.owner_end;h.owner_end=value;}else if field==3 {old=h.flag_start;h.flag_start=value;}else if field==4 {old=h.flag_end;h.flag_end=value;}else {old=h.mode;h.mode=value;}
  if old!=value {var q=source_owned_core::Program {source:copy(p.program.source),head:h,tree:copy(p.program.tree)};assert(!source_owned_verify::verify(s,q));}
 }}
 print("source-owned byte/truncation and forged extreme headers passed");
}
