// Phase 1 constructs retained source and independently re-playable scalar
// trees. It records source-copy telemetry before copying each source buffer.
namespace static_order_parse;
import work;
import static_core;
import static_order_b_parse;
import static_order_ag_parse;
import static_order_core;
fn parse(source:u8[:],w:work::ScheduledWork&)->static_order_core::Parsed {
 var parsed=static_order_ag_parse::parse(source,w.meter);w.meter=parsed.meter;
 if parsed.status!=0{return static_order_core::Parsed {status:parsed.status};}
 if !parsed.tree.is_array{return static_order_core::Parsed {};}
 var trees:static_core::Tree[>..]=[];
 for i in parsed.tree.parts.len {
  let visit=work::scheduled_charge(w,1,3);if visit.status!=0{return static_order_core::Parsed {status:if visit.status==1 {4} else {5}};}
  let part=parsed.tree.parts[i];var own:u8[>..]=[];if part.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
  let read=work::source_read(w.meter,(part.end-part.start) as u64);if read.status!=0{return static_order_core::Parsed {status:if read.status==5 {5} else {6}};}
  own.append(source[part.start..part.end]);own.push('\n');var scalar=static_order_b_parse::parse(own,w.meter);w.meter=scalar.meter;
  if scalar.status!=0{return static_order_core::Parsed {status:scalar.status};}
  // The retained scalar descriptor is an additional source-derived object.
  let node=work::scheduled_charge(w,1,2);if node.status!=0{return static_order_core::Parsed {status:if node.status==1 {4} else {5}};}
  let retain=work::source_read(w.meter,scalar.tree.source.len as u64);if retain.status!=0{return static_order_core::Parsed {status:if retain.status==5 {5} else {6}};}
  trees.push(copy(scalar.tree));
 }
 let retained=work::source_read(w.meter,parsed.tree.source.len as u64);if retained.status!=0{return static_order_core::Parsed {status:if retained.status==5 {5} else {6}};}
 return static_order_core::Parsed {status:0,owned:static_order_core::Owned {product:copy(parsed.tree),scalars:trees}};
}
