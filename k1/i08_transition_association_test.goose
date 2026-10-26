import i08_link_build;
import i08_link_affine;
import i08_transition_build;
import i08_transition_verify;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
 var p,status=i08_link_build::build(text);assert(status==0);let a=i08_link_affine::build(p,text);assert(a.status==0);
 let proof=i08_transition_build::build(p,text,a.plan);assert(proof.status==0 && i08_transition_verify::verify(p,text,a.plan,proof.proof));
 for i in 6 {for f in 13 {var b=proof.proof;
  if f==0 {b.steps[i].kind^=1;}else if f==1 {b.steps[i].node^=1;}else if f==2 {b.steps[i].site^=1;}
  else if f==3 {b.steps[i].subject^=1;}else if f==4 {b.steps[i].version^=1;}else if f==5 {b.steps[i].result^=1;}
  else if f==6 {b.steps[i].result_version^=1;}else if f==7 {b.steps[i].index^=1;}else if f==8 {b.steps[i].nat^=1;}
  else if f==9 {b.steps[i].capacity^=1;}else if f==10 {b.steps[i].dep1^=1;}else if f==11 {b.steps[i].dep2^=1;}else {b.steps[i].dep3^=1;}
  assert(!i08_transition_verify::verify(p,text,a.plan,b));
 }}
 for field in 16 {var plan=a.plan;
  if field==0 {plan.initial=-1;}else if field==1 {plan.view=-1;}else if field==2 {plan.nat=-1;}else if field==3 {plan.capacity=-1;}
  else if field==4 {plan.loop_id=-1;}else if field==5 {plan.index=-1;}else if field==6 {plan.carry_id=-1;}else if field==7 {plan.result=-1;}
  else if field==8 {plan.carry_node=-1;}else if field==9 {plan.invariant_id=-1;}else if field==10 {plan.next_node=-1;}else if field==11 {plan.append=-1;}
  else if field==12 {plan.row=-1;}else if field==13 {plan.freeze=-1;}else if field==14 {plan.return_node=-1;}else {plan.root=-1;}
  assert(!i08_transition_verify::verify(p,text,plan,proof.proof));
 }
 var altered=copy(p);altered.cap.job.events[altered.cap.job.events.len-4].version+=1;
 assert(!i08_transition_verify::verify(altered,text,a.plan,proof.proof));
 let changed=source("source[i].vx","source[i].x");assert(!i08_transition_verify::verify(p,changed,a.plan,proof.proof));
 print("independent conditional transition association passed");
}
