import ownership_parse;
import ownership_verify;
import ownership_check;
fn main() {
 let s="do:\n  if condition:\n    let first = original\n    let x = owned.open(first) as outer item_a in do:\n      let y = owned.open(first) as inner item_b in do:\n        break item_b\n      break item_a\n    owned.close(first)\n    return x\n  else:\n    let z = owned.open(original) as more item_c in do:\n      break item_c\n    owned.close(original)\n    return z\n";
 var p=ownership_parse::parse(s);assert(p.status==0 && ownership_verify::verify(p.tree));
 var c=ownership_check::Contract {owner:"original",flag:"condition",return_mode:2};
 assert(ownership_check::check(p.tree,s,c)==0);
 let values:i64[]=[-1,0,1,2,127,128,255,256,9223372036854775807];
 for i in p.tree.nodes.len {
  let old=p.tree.nodes[i];
  for field in 10 {
   for v in values {
    p.tree.nodes[i]=old;var was:i64=0;
    if field==0 {was=old.tag;p.tree.nodes[i].tag=v;}
    else if field==1 {was=old.start;p.tree.nodes[i].start=v;}
    else if field==2 {was=old.end;p.tree.nodes[i].end=v;}
    else if field==3 {was=old.ref_start;p.tree.nodes[i].ref_start=v;}
    else if field==4 {was=old.ref_end;p.tree.nodes[i].ref_end=v;}
    else if field==5 {was=old.a;p.tree.nodes[i].a=v;}
    else if field==6 {was=old.b;p.tree.nodes[i].b=v;}
    else if field==7 {was=old.bound;p.tree.nodes[i].bound=v;}
    else if field==8 {was=old.region;p.tree.nodes[i].region=v;}
    else {was=old.payload;p.tree.nodes[i].payload=v;}
    if was!=v {assert(!ownership_verify::verify(p.tree));assert(ownership_check::check(p.tree,s,c)==1);}
   }
  }
  p.tree.nodes[i]=old;
 }
 for i in p.tree.bindings.len {
   let old=p.tree.bindings[i];
   for v in values {
    if old.start!=v {p.tree.bindings[i].start=v;assert(!ownership_verify::verify(p.tree));p.tree.bindings[i]=old;}
    if old.end!=v {p.tree.bindings[i].end=v;assert(!ownership_verify::verify(p.tree));p.tree.bindings[i]=old;}
   }
 }
 var accepted:i64=0;var rejected:i64=0;
 for pos in s.len {
  for replacement in [0,10,32,35,40,41,48,49,65,95,120,255] {
   var changed:u8[>..]=[];changed.append(s);changed[pos]=replacement as u8;
   var r=ownership_parse::parse(changed);
   if r.status==0 {accepted+=1;assert(ownership_verify::verify(r.tree));}
   else {rejected+=1;}
   if changed[..]!=s {assert(ownership_check::check(p.tree,changed,c)==1);}
  }
 }
 assert(accepted>0 && rejected>0);
 print("general ownership source/tree mutation laws passed");
}
