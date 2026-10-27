import static_b_cache;
fn main() {
 let src="static let x: U32 = (1 + 2) * 3\n";
 let cold=static_b_cache::run(src,3,0,0,false);let hot=static_b_cache::run(src,3,0,0,true);
 assert(cold.status==0 && hot.status==0 && cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
 assert(hot.meter.source_byte_reads>0 && cold.meter.source_byte_reads==3*hot.meter.source_byte_reads);
 let total=cold.meter.semantic;for slack in 0..(total+1) {
  let start=1048576-slack;let a=static_b_cache::run(src,3,start,0,false);let b=static_b_cache::run(src,3,start,0,true);
  assert(a.status==b.status && a.completed==b.completed && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
 }
 // source_read is physical telemetry; cache hits genuinely avoid reads. Its
 // overflow is an internal counter failure, not a semantic-limit diagnostic.
 let byte_seed=~(0 as u64)-2*hot.meter.source_byte_reads;
 let a=static_b_cache::run(src,3,0,byte_seed,false);let b=static_b_cache::run(src,3,0,byte_seed,true);
 assert(a.status==6 && a.completed==2 && b.status==0 && b.completed==3);
 print("semantic cache replay and physical source-byte telemetry passed");
}
