import i08_link_build;
import i08_link_affine;
import i08_link_verify;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
 var linked,status=i08_link_build::build(text);assert(status==0 && i08_link_verify::verify(linked,text));
 let result=i08_link_affine::build(linked,text);assert(result.status==0 && i08_link_affine::verify(linked,text,result.plan));
 for i in 16 {for v in [-1,0,9223372036854775807] {var p=result.plan;
  if i==0 {p.initial=v;}else if i==1 {p.view=v;}else if i==2 {p.nat=v;}else if i==3 {p.capacity=v;}else if i==4 {p.loop_id=v;}
  else if i==5 {p.index=v;}else if i==6 {p.carry_id=v;}else if i==7 {p.result=v;}else if i==8 {p.carry_node=v;}
  else if i==9 {p.invariant_id=v;}else if i==10 {p.next_node=v;}else if i==11 {p.append=v;}else if i==12 {p.row=v;}
  else if i==13 {p.freeze=v;}else if i==14 {p.return_node=v;}else {p.root=v;}
  assert(!i08_link_affine::verify(linked,text,p));
 }}
 var bad=copy(linked);bad.cap.job.events[0].version+=1;assert(!i08_link_affine::verify(bad,text,result.plan));
 var wrong=copy(linked);wrong.tree.nodes[result.plan.append-1].start+=1;assert(!i08_link_affine::verify(wrong,text,result.plan));
 var text2=source("source[i].vx","source[i].x");assert(!i08_link_affine::verify(linked,text2,result.plan));
 print("independent affine target association passed");
}
