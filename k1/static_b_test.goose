import work;
import static_parse;
import static_verify;
import static_m_parse;
import static_m_verify;
import static_b_parse;
import static_b_verify;
fn main() {
 for source in ["static let a: U32 = 1 + 2 * 3\n", "static let b: F32 = (-0.0 + 1.5) / 0.0\n", "static let c: U32 = U32.wrapping_add(4294967295, 1)\n"] {
  var old=static_m_parse::parse(source,work::Meter {});var parsed=static_b_parse::parse(source,work::Meter {});
  assert(old.status==0 && parsed.status==0 && parsed.tree.nodes.len==old.tree.nodes.len && parsed.tree.root==old.tree.root);
  assert(parsed.meter.semantic==old.meter.semantic && parsed.meter.phase_semantic[..]==old.meter.phase_semantic[..] && parsed.meter.source_byte_reads>0);
  let ov=static_m_verify::verify(source,old.tree,old.meter);let checked=static_b_verify::verify(source,parsed.tree,parsed.meter);
  assert(ov.ok && checked.ok && checked.meter.semantic==ov.meter.semantic && checked.meter.phase_semantic[..]==ov.meter.phase_semantic[..] && checked.meter.source_byte_reads>parsed.meter.source_byte_reads);
  let parse_visits=parsed.meter.semantic;for allowed in parse_visits {
   let over=static_b_parse::parse(source,work::Meter {semantic:1048576-allowed});
   assert(over.status==4 && over.meter.semantic==1048576 && over.tree.nodes.len==0);
  }
  let exact_visits=static_b_parse::parse(source,work::Meter {semantic:1048576-parse_visits});assert(exact_visits.status==0 && exact_visits.meter.semantic==1048576);
  let verify_visits=checked.meter.semantic-parsed.meter.semantic;
  for allowed in verify_visits {
   let over=static_b_verify::verify(source,parsed.tree,work::Meter {semantic:1048576-allowed});
   assert(!over.ok && over.limited && over.work_status==1 && over.meter.semantic==1048576);
  }
  let verify_exact=static_b_verify::verify(source,parsed.tree,work::Meter {semantic:1048576-verify_visits});assert(verify_exact.ok && verify_exact.meter.semantic==1048576);
  let reads=parsed.meter.source_byte_reads;assert(reads>0 && reads<100000);
  for allowed in reads {
   let overflow=static_b_parse::parse(source,work::Meter {source_byte_reads:~(0 as u64)-allowed});
   assert(overflow.status==6 && overflow.tree.nodes.len==0 && overflow.meter.source_byte_reads==~(0 as u64));
  }
  let exact=static_b_parse::parse(source,work::Meter {source_byte_reads:~(0 as u64)-reads});assert(exact.status==0 && exact.meter.source_byte_reads==~(0 as u64));
  let delta=checked.meter.source_byte_reads-parsed.meter.source_byte_reads;
  for allowed in delta {
   let overflow=static_b_verify::verify(source,parsed.tree,work::Meter {source_byte_reads:~(0 as u64)-allowed});
   assert(!overflow.ok && !overflow.limited && overflow.work_status==6);
  }
  let exact_verify=static_b_verify::verify(source,parsed.tree,work::Meter {source_byte_reads:~(0 as u64)-delta});
  assert(exact_verify.ok && exact_verify.meter.source_byte_reads==~(0 as u64));
 }
 for source in ["static let x: U32 = 1+", "static let x: U32 = host()", "static let x: U32 = 1.0", "static let if: U32 = 1"] {
  let base=static_parse::parse(source);let metered=static_b_parse::parse(source,work::Meter {});assert(base.status==metered.status);
 }
 print("metered scalar token/byte/name telemetry boundaries passed");
}
