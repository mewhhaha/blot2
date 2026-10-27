import std;
import work;
import static_parse;
import static_verify;
import static_m_parse;
import static_m_verify;
import static_b_parse;
import static_b_verify;
import static_m_cache;
fn main() {
 for a in ["0","1","4294967295","0.0","1.5","-0.0","host()","4294967296","(1+2)","U32.wrapping_add(1,2)"] {
 for b in ["0","1","4294967295","0.0","1.5","-0.0","host()","4294967296","(1+2)","U32.wrapping_add(1,2)"] {
 for op in ["+","-","*","/"] {
  for declared in ["U32","F32"] {
   var source:u8[>..]=[];source.append("static let x: ");source.append(declared);source.append(" = ");source.append(a);source.push(' ');source.append(op);source.push(' ');source.append(b);source.push('\n');
   var old=static_parse::parse(source);var metered=static_m_parse::parse(source,work::Meter {});
   assert(old.status==metered.status);
   var with_bytes=static_b_parse::parse(source,work::Meter {});assert(with_bytes.status==metered.status);
   assert(with_bytes.meter.semantic==metered.meter.semantic && with_bytes.meter.phase_semantic[..]==metered.meter.phase_semantic[..]);
   if old.status==0 {
    assert(static_verify::verify(source,old.tree));let v=static_m_verify::verify(source,metered.tree,metered.meter);assert(v.ok && !v.limited);let bv=static_b_verify::verify(source,with_bytes.tree,with_bytes.meter);
    assert(bv.ok && !bv.limited && bv.meter.semantic==v.meter.semantic && bv.meter.phase_semantic[..]==v.meter.phase_semantic[..]);
    let cold=static_m_cache::run(source,3,0,false);let hot=static_m_cache::run(source,3,0,true);
    assert(cold.status==0 && hot.status==0 && cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
   }
  }
 }}}
 print("instrumented scalar source/byte/visit differential passed");
}
