import std;
import work;
import static_publish_build;
import static_ag_pipeline;
fn compare(s:u8[:]) {
 let base=static_publish_build::build(s);let a=static_ag_pipeline::build(s,work::Meter {},false);let b=static_ag_pipeline::build(s,work::Meter {},true);
 assert(a.status==b.status && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
 assert(a.status==base.status);
 if a.status==0 {assert(a.image.source[..]==s && b.image.source[..]==s && a.image.data[..]==base.image.data[..] && b.image.data[..]==base.image.data[..] && a.image.steps==base.image.steps && b.image.steps==base.image.steps);}
 else {assert(a.image.data.len==0 && b.image.data.len==0 && a.image.source.len==0 && b.image.source.len==0 && a.image.rows==0 && b.image.rows==0 && a.image.width==0 && b.image.width==0);}
}
fn main(){for n in 400 {var s:u8[>..]=[];s.append("static let zz = #[");for row in 1+n%5 {if row>0 {s.push(',');}format(s,"(",(n+row)%19,if n%2==0 {"+0"} else {"*1"},",",(n*3+row)%19,if n%3==0 {".0/0.0"} else {".5"},")");}s.push(']');compare(s);}
 for s in ["static let a = #[((1+2),1.5),((1+2),1.5)]", "static let a = #[(4294967295+1,0.0)]", "static let a = #[(1.0,2),(0.5,4294967295*2)]", "static let a = #[(1,2),(3,2.0)]", "static let a = #[(1,2),]", "static let a = #[(1,host())]"] {compare(s);}
 let source="static let q = #[(1,2.0),(1,2.0),(3,2.0)]";let baseline=static_ag_pipeline::build(source,work::Meter {},false);assert(baseline.status==0);
 for cutoff in baseline.meter.source_byte_reads {let bad=static_ag_pipeline::build(source,work::Meter {source_byte_reads:~(0 as u64)-cutoff},false);assert(bad.status==6 && bad.image.data.len==0 && bad.image.source.len==0 && bad.image.rows==0);}
 print("independent aggregate differential and failure atomicity controls passed");}
