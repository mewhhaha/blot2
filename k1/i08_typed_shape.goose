// Source-replayed type-shape experiment for the fixed particle declaration.
// A successful check grants no View loan, builder authority, proof, emission,
// ABI or capability; indexed reads and affine operations remain obligations.
namespace i08_typed_shape;
import i08_core;
import i08_header_verify;
// value types: 1 U32/Nat, 2 F32, 3 input View, 4 Builder,
// 5 input row, 6 output row, 7 output View, 8 carry, 9 stmt,
// 10 fact, 11 fact list, 12 Region, 13 Domain, 14 Bool.
fn get(t:u8[:],id:i64)->u8 {if id<1 || id>t.len{return 0;}return t[id-1];}
fn verify(tree:i08_core::Tree&,expected:u8[:])->bool {
 if !i08_header_verify::verify(tree,expected) || tree.bindings.len<8 || tree.bindings.len>256{return false;}
 var binds:u8[256]=[0;256];var types:u8[>..]=[];var returns:i64=0;
 binds[0]=12;binds[1]=12;binds[2]=1;binds[3]=1;binds[4]=13;
 binds[5]=3;binds[6]=2;binds[7]=4;
 for b,i in tree.bindings {
  if i<2 {if b.kind!=6{return false;}}else if i<4 {if b.kind!=5{return false;}}
  else if i==4 {if b.kind!=7{return false;}}else if i<8 {if b.kind!=1{return false;}}
  else if b.kind==2 {binds[i]=1;}else if b.kind!=3 && b.kind!=4 {return false;}
 }
 for node in tree.nodes {
  var ty:u8=0;
  if node.tag==1 {if node.a<1 || node.a>tree.bindings.len{return false;}ty=binds[node.a-1];if ty==0{return false;}}
  else if node.tag==2 {ty=1;}
  else if node.tag==3 || node.tag==4 {ty=14;}
  else if node.tag==5 {let a=get(types,node.a);let b=get(types,node.b);if (a!=10 && a!=11) || b!=10 {return false;}ty=11;}
  else if node.tag==6 {
   let a=get(types,node.a);if (a!=1 && a!=4) || node.b<1 || node.b>tree.bindings.len || tree.bindings[node.b-1].kind!=3 || binds[node.b-1]!=0{return false;}
   binds[node.b-1]=a;ty=8;
  }
  else if node.tag==7 {if get(types,node.a)!=4 || node.b<1 || node.b>3{return false;}ty=1;}
  else if node.tag==8 {if node.c<1 || node.c>6 || get(types,node.a)!=1 || get(types,node.b)!=1 || node.d!=0{return false;}ty=10;}
  else if node.tag==9 || node.tag==10 {
   if node.b!=1{return false;}var found=false;
   for item in tree.nodes {if item.tag==15 && item.target==node.target {
    if found || item.g!=1 || item.c<1 || item.c>tree.nodes.len{return false;}
    let carry=tree.nodes[item.c-1];if carry.tag!=6 || carry.b<1 || carry.b>tree.bindings.len ||
       binds[carry.b-1]==0 || get(types,node.a)!=binds[carry.b-1] {return false;}found=true;
   }}if !found{return false;}ty=9;
  }
  else if node.tag==11 || node.tag==12 {ty=9;}
  else if node.tag==13 {if get(types,node.a)!=7{return false;}returns+=1;ty=9;}
  else if node.tag==14 {if get(types,node.a)!=14 || get(types,node.b)!=9 || (node.c!=0 && get(types,node.c)!=9){return false;}ty=9;}
  else if node.tag==15 {
   if get(types,node.a)!=1 || get(types,node.b)!=1 || node.g!=1 || get(types,node.c)!=8 || get(types,node.e)!=9 ||
      node.f<1 || node.f>tree.bindings.len || tree.bindings[node.f-1].kind!=2 ||
      (node.d!=0 && get(types,node.d)!=10 && get(types,node.d)!=11){return false;}
   let c=tree.nodes[node.c-1];if c.b<1 || c.b>tree.bindings.len{return false;}ty=binds[c.b-1];
  }
  else if node.tag==16 {let a=get(types,node.a);if a==0 || node.b<1 || node.b>tree.bindings.len || tree.bindings[node.b-1].kind!=4 || binds[node.b-1]!=0{return false;}binds[node.b-1]=a;ty=9;}
  else if node.tag==17 {if get(types,node.a)!=9 || get(types,node.b)!=9{return false;}ty=9;}
  else if node.tag==18 {if node.b!=3 || get(types,node.a)!=9{return false;}ty=9;}
  else if node.tag==19 {if get(types,node.a)!=1 || get(types,node.b)!=1{return false;}ty=1;}
  else if node.tag==20 {ty=get(types,node.a);if ty==0 || ty==9{return false;}}
  else if node.tag==21 {let a=get(types,node.a);if (a!=1 && a!=2) || get(types,node.b)!=a{return false;}ty=a;}
  else if node.tag==22 {if get(types,node.a)!=1 || get(types,node.b)!=1{return false;}ty=14;}
  else if node.tag==23 {let a=get(types,node.a);if node.b>=1 && node.b<=4 && a==5 {ty=2;}else if node.b==5 && a==3 {ty=1;}else {return false;}}
  else if node.tag==24 {if get(types,node.a)!=3 || get(types,node.b)!=1{return false;}ty=5;}
  else if node.tag==25 {if get(types,node.a)!=2 || get(types,node.b)!=2{return false;}ty=2;}
  else if node.tag==26 {if get(types,node.a)!=2 || get(types,node.b)!=2{return false;}ty=6;}
  else if node.tag==27 {if get(types,node.a)!=4 || get(types,node.b)!=6{return false;}ty=4;}
  else if node.tag==28 {if get(types,node.a)!=4{return false;}ty=7;}
  else if node.tag==29 {ty=2;}
  else {return false;}
  types.push(ty);
 }
 return returns>0 && tree.root>0 && tree.root<=tree.nodes.len && tree.nodes[tree.root-1].tag==18 && get(types,tree.root)==9;
}
