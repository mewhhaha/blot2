import static_m_cache;
fn main() {
 for source in ["static let x: U32 = (1 + 2) * 3\n", "static let x: F32 = -0.0 / 0.0\n", "static let x: U32 = U32.wrapping_add(1,2)\n"] {
  let a=static_m_cache::run(source,3,0,false);let b=static_m_cache::run(source,3,0,true);
  assert(a.status==0 && b.status==0 && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..] && a.completed==3 && b.completed==3);
  let work=a.meter.semantic;for slack in 0..(work+2) {
   let seed=if slack>1048576 {0} else {1048576-slack};
   let x=static_m_cache::run(source,3,seed,false);let y=static_m_cache::run(source,3,seed,true);
   assert(x.status==y.status && x.completed==y.completed && x.meter.semantic==y.meter.semantic && x.meter.phase_semantic[..]==y.meter.phase_semantic[..]);
   if slack<work {assert(x.status==4 && x.meter.semantic==1048576);}else {assert(x.status==0);}
  }
 }
 for source in ["static let x: U32 = 1 +", "static let x: U32 = host()", "static let x: U32 = 1.0"] {
  let a=static_m_cache::run(source,3,0,false);let b=static_m_cache::run(source,3,0,true);
  assert(a.status!=0 && a.status==b.status && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
 }
 print("instrumented scalar helper cold/cache logical-visit parity passed");
}
