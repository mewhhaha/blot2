// Independent original-header and mixed Core replay. Numeric IDs are local to
// this owner; this conveys no cross-compile, loan or capability authority.
namespace canonical_check;
import canonical_core;
import joined_public_verify;
import mixed_core;
import mixed_compiler_core;
import mixed_validate;
fn types(t:mixed_core::Tree&)->u8[] {
 var result:u8[>..]=[];
 for n in t.nodes {var ty:u8=0;
  if n.tag==1 || n.tag==2 || n.tag==19 || n.tag==21 {ty=1;}
  else if n.tag==3 || n.tag==4 || n.tag==22 {ty=2;}
  else if n.tag==6 {ty=4;}
  else if n.tag==9 || n.tag==10 || n.tag==11 || n.tag==12 || n.tag==13 || n.tag==14 || n.tag==16 || n.tag==17 || n.tag==18 {ty=3;}
  else if n.tag==15 {ty=if n.g==0 {3} else {1};}
  else if n.tag==20 {if n.a<1 || n.a>result.len{return [];}ty=result[n.a-1];}
  else {return [];}
  result.push(ty);
 }
 return result;
}
fn verify(expected:u8[:],p:canonical_core::Program&)->bool {
 if expected!=p.source {return false;}let a=joined_public_verify::header(expected);let b=p.head;
 if !a.ok || !b.ok || a.let_start!=b.let_start || a.effect_start!=b.effect_start || a.resources_end!=b.resources_end || a.depth!=b.depth || a.frame!=b.frame {return false;}
 let flat=joined_public_verify::project(expected,a);if flat.len==0 {return false;}
 var prior=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 if !mixed_validate::verify(flat,prior) {return false;}
 let retyped=types(p.tree);return retyped.len==p.tree.nodes.len && retyped[..]==p.types;
}
