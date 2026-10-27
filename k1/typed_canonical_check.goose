// Independent original-header and mixed Core replay. Numeric IDs are local to
// this owner; this conveys no cross-compile, loan or capability authority.
namespace typed_canonical_check;
import typed_canonical_core;
import joined_public_verify;
import mixed_core;
import mixed_compiler_core;
import typed_mixed_validate;
struct Typing {node:u8[]=[],binding:u8[]=[]}
fn types(t:mixed_core::Tree&)->Typing {
 var result:u8[>..]=[];var binding:u8[>..]=[];for b in t.bindings {binding.push(if b.kind>=1 && b.kind<=3 {1} else {0});}
 for n in t.nodes {var ty:u8=0;
  if n.tag==1 {if n.a<1 || n.a>binding.len{return Typing {};}ty=binding[n.a-1];}
  else if n.tag==2 || n.tag==19 || n.tag==21 {ty=1;}
  else if n.tag==3 || n.tag==4 || n.tag==22 {ty=2;}
  else if n.tag==6 {ty=4;}
  else if n.tag==9 || n.tag==10 || n.tag==11 || n.tag==12 || n.tag==13 || n.tag==14 || n.tag==17 || n.tag==18 {ty=3;}
  else if n.tag==16 {if n.a<1 || n.a>result.len || n.b<1 || n.b>binding.len{return Typing {};}binding[n.b-1]=result[n.a-1];ty=3;}
  else if n.tag==15 {ty=if n.g==0 {3} else {1};}
  else if n.tag==20 {if n.a<1 || n.a>result.len{return Typing {};}ty=result[n.a-1];}
  else {return Typing {};}if ty==0{return Typing {};}result.push(ty);
 }
 return Typing {node:copy(result),binding:copy(binding)};
}

fn verify(expected:u8[:],p:typed_canonical_core::Program&)->bool {
 if expected!=p.source {return false;}let a=joined_public_verify::header(expected);let b=p.head;
 if !a.ok || !b.ok || a.let_start!=b.let_start || a.effect_start!=b.effect_start || a.resources_end!=b.resources_end || a.depth!=b.depth || a.frame!=b.frame {return false;}
 let flat=joined_public_verify::project(expected,a);if flat.len==0 {return false;}
 var prior=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 if !typed_mixed_validate::verify(flat,prior) {return false;}
 let retyped=types(p.tree);return retyped.node.len==p.tree.nodes.len && retyped.binding.len==p.tree.bindings.len && retyped.node[..]==p.types && retyped.binding[..]==p.binding_types;
}
