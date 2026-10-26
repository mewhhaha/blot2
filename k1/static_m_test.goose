import work;
import static_parse;
import static_verify;
import static_m_parse;
import static_m_verify;
fn main() {
 for src in ["static let a: U32 = 1 + 2 * 3\n", "static let b: F32 = (-0.0 + 1.5) / 0.0\n", "static let c: U32 = U32.wrapping_add(4294967295, 1)\n"] {
  var base=static_parse::parse(src);assert(base.status==0 && static_verify::verify(src,base.tree));
  var instrumented=static_m_parse::parse(src,work::Meter {});assert(instrumented.status==0);
  assert(instrumented.tree.source[..]==base.tree.source[..] && instrumented.tree.ty==base.tree.ty && instrumented.tree.root==base.tree.root && instrumented.tree.nodes.len==base.tree.nodes.len);
  for n,i in base.tree.nodes {let x=instrumented.tree.nodes[i];assert(n.tag==x.tag && n.ty==x.ty && n.start==x.start && n.end==x.end && n.a==x.a && n.b==x.b && n.literal==x.literal && n.half==x.half);}
  let checked=static_m_verify::verify(src,instrumented.tree,instrumented.meter);assert(checked.ok && !checked.limited);
  let parse_work=instrumented.meter.semantic;let verify_work=checked.meter.semantic-parse_work;assert(parse_work>0 && verify_work>0);
  let exact=static_m_parse::parse(src,work::Meter {semantic:1048576-parse_work});assert(exact.status==0 && exact.meter.semantic==1048576);
  let denied=static_m_parse::parse(src,work::Meter {semantic:1048576-parse_work+1});assert(denied.status==4 && denied.meter.semantic==1048576 && denied.tree.nodes.len==0);
  let at=static_m_verify::verify(src,instrumented.tree,work::Meter {semantic:1048576-verify_work});assert(at.ok && !at.limited && at.meter.semantic==1048576);
  let over=static_m_verify::verify(src,instrumented.tree,work::Meter {semantic:1048576-verify_work+1});assert(!over.ok && over.limited && over.meter.semantic==1048576);
  var forged=copy(instrumented.tree);forged.nodes[0].literal^=1;let rejected=static_m_verify::verify(src,forged,work::Meter {});assert(!rejected.ok && !rejected.limited);
 }
 let src="static let x: U32 = 1\n";var valid=static_parse::parse(src);assert(valid.status==0);
 var wrong_gate=work::Meter {gate:2};let wrong=static_m_parse::parse(src,wrong_gate);
 assert(wrong.status==5 && wrong.tree.nodes.len==0);
 var bad_counts=work::Meter {};bad_counts.phase_semantic[0]=1;let bad=static_m_parse::parse(src,bad_counts);
 assert(bad.status==5 && bad.tree.nodes.len==0);
 var validator_gate=work::Meter {gate:1};let vg=static_m_verify::verify(src,valid.tree,validator_gate);
 assert(!vg.ok && !vg.limited && vg.work_status==5);
 var validator_counts=work::Meter {};validator_counts.phase_semantic[1]=1;
 let vc=static_m_verify::verify(src,valid.tree,validator_counts);assert(!vc.ok && !vc.limited && vc.work_status==5);
 print("partial actual scalar parse and validator semantic charging passed");
}
