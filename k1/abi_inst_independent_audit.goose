import abi_inst_source;
import abi_inst_check;
import abi_inst_compile;

fn make(t:u8[:])->u8[] {
 var s:u8[>..]=[]; s.append(abi_inst_source::generic()); s.append(abi_inst_source::head()); s.append(t); s.append(", "); s.append(t);
 s.append("] ! {} resources {depth: 2, frame: 256} = fn x => return identity@["); s.append(t); s.append("](x)\n"); return s;
}
fn main() {
 let a=make("( U32 , U32 )"); let b=make("(U32,U32,U32)"); let ta=abi_inst_source::parse(a); let tb=abi_inst_source::parse(b);
 assert(abi_inst_source::verify(a,ta) && abi_inst_source::verify(b,tb));
 let wa=abi_inst_compile::emit(a); let wb=abi_inst_compile::emit(b);
 assert(wa.len>0 && wb.len>0 && !abi_inst_check::verify(a,wb) && !abi_inst_check::verify(b,wa));
 var bad=copy(ta); bad.ok=false; assert(!abi_inst_source::verify(a,bad));
 for x in [-9223372036854775807, -1, 0, 1, 9223372036854775807] {
  bad=copy(ta); bad.start=x; assert(!abi_inst_source::verify(a,bad));
  bad=copy(ta); bad.end=x; assert(!abi_inst_source::verify(a,bad));
  bad=copy(ta); bad.count=x; assert(!abi_inst_source::verify(a,bad));
 }
 for i in a.len {for c in [0 as u8, 10 as u8, 13 as u8, 32 as u8, 47 as u8, 127 as u8, 128 as u8, 255 as u8] {
  if a[i]!=c {var m=copy(a);m[i]=c;assert(!abi_inst_check::verify(m,wa));}
 }}
 var mutant=copy(wa); mutant[90]^=1; assert(!abi_inst_check::verify(a,mutant));
 var mutant2=copy(wa); mutant2[108]=12; assert(!abi_inst_check::verify(a,mutant2));
 var mutant3:u8[>..]=[]; mutant3.append(wa); mutant3.push(0); assert(!abi_inst_check::verify(a,mutant3));
 print("independent exact-source, cross-type target and forged span controls passed");
}
