// Formal-only numerical read obligation for the fixed I08 source. This does
// not authenticate a live View loan, ownership, memory, builder, ABI or code.
namespace i08_bound_shape;
import i08_core;
import i08_typed_shape;
fn exact_zero(t:i08_core::Tree&,id:i64)->bool {
 if id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];return n.tag==2 && n.start>=0 && n.end==n.start+1 && n.end<=t.source.len && t.source[n.start..n.end]=="0";
}
fn ref(t:i08_core::Tree&,id:i64,binding:i64)->bool {return id>0 && id<=t.nodes.len && t.nodes[id-1].tag==1 && t.nodes[id-1].a==binding;}
fn verify(t:i08_core::Tree&,expected:u8[:])->bool {
 if !i08_typed_shape::verify(t,expected) {return false;}
 var reads:i64=0;
 for read in t.nodes {
  if read.tag!=24 {continue;}reads+=1;
  if !ref(t,read.a,6) || read.b<1 || read.b>t.nodes.len {return false;}
  let index=t.nodes[read.b-1];if index.tag!=1 || index.a<1 || index.a>t.bindings.len || t.bindings[index.a-1].kind!=2 {return false;}
  var found=false;
  for candidate in t.nodes {
   if candidate.tag!=15 || candidate.f!=index.a {continue;}
   if found || !exact_zero(t,candidate.a) || !ref(t,candidate.b,3) || candidate.e<1 || candidate.e>t.nodes.len {return false;}
   let body=t.nodes[candidate.e-1];if read.start<body.start || read.end>body.end {return false;}found=true;
  }
  if !found {return false;}
 }
 return reads>0;
}
