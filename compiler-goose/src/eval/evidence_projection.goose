namespace blot_eval_evidence_projection;
import .type_evidence;
import check.types;
import support.error;
type View=blot_eval_type_evidence::View;
type Tag=blot_eval_type_evidence::Tag;
type Error=blot_error::Error;
struct Comparison { view: View,shift: u32,remaining: i64& }
fn step(self: Comparison&,depth: i64) -> Error { if depth>=128||self.remaining==0 { return Error.evidence_limit; } self.remaining--; return Error.none; }
fn equal(self: Comparison&,left: u32,right: u32,local: i64,depth: i64) -> bool,Error {
 let err=step(self,depth); if err!=Error.none { return false,err; }
 if left==0||right==0||left>=self.view.nodes.len||right>=self.view.nodes.len { return false,Error.type_mismatch; }
 let a=self.view.node(left); let b=self.view.node(right); if a.tag!=b.tag { return false,Error.none; }
 if a.tag==Tag.bound { var expected=a.c; if expected>=local { if expected>0xffffffff-self.shift { return false,Error.evidence_limit; } expected+=self.shift; } return a.a==b.a&&a.b==b.b&&expected==b.c,Error.none; }
 if a.tag==Tag.forall||a.tag==Tag.existential {
  if a.b!=b.b { return false,Error.none; }
  let xs=self.view.children(left); let ys=self.view.children(right);
  for x,index in xs { let first=self.view.node(x); let second=self.view.node(ys[index]); if first.tag!=Tag.bound||second.tag!=Tag.bound||first.a!=second.a||first.b!=second.b||first.c!=0||second.c!=0 { return false,Error.none; } }
  let goals=self.view.quantifierGoals(left); let others=self.view.quantifierGoals(right); if goals.len!=others.len { return false,Error.none; }
  for x,index in goals {
   let y=others[index]; if x.kind!=y.kind||x.name!=y.name||x.operator!=y.operator||x.identity!=y.identity { return false,Error.none; }
   let first: u32[4]=[x.ty,x.other,x.result,x.signature]; let second: u32[4]=[y.ty,y.other,y.result,y.signature];
   for value,i in first { if (value==0)!=(second[i]==0) { return false,Error.none; } if value!=0 { let same,e=equal(self,value,second[i],local+1,depth+1); if e!=Error.none||!same { return same,e; } } }
  }
  return equal(self,a.a,b.a,local+1,depth+1);
 }
 if a.tag==Tag.function||a.tag==Tag.state_provider {
  let x,e=equal(self,a.a,b.a,local,depth+1); if e!=Error.none||!x { return x,e; } let y,error=equal(self,a.b,b.b,local,depth+1); if error!=Error.none||!y { return y,error; }
  if a.tag==Tag.function { return row(self,a.c,b.c,local,depth+1); } return equal(self,a.c,b.c,local,depth+1);
 }
 if a.tag==Tag.usage { if a.b!=b.b||(a.c==0)!=(b.c==0) { return false,Error.none; } let same,e=equal(self,a.a,b.a,local,depth+1); if e!=Error.none||!same { return same,e; } if a.c==0 { return true,Error.none; } return equal(self,a.c,b.c,local,depth+1); }
 if a.tag==Tag.provider { let same,e=equal(self,a.a,b.a,local,depth+1); if e!=Error.none||!same { return same,e; } return row(self,a.c,b.c,local,depth+1); }
 if a.tag==Tag.array||a.tag==Tag.list||a.tag==Tag.cursor||a.tag==Tag.resolver { return equal(self,a.a,b.a,local,depth+1); }
 if a.tag==Tag.projection||a.tag==Tag.nominal||a.tag==Tag.product||a.tag==Tag.record {
  if (a.tag==Tag.projection||a.tag==Tag.nominal)&&(a.a!=b.a||a.b!=b.b) { return false,Error.none; }
  if a.tag==Tag.projection { let x=self.view.projection(left); let y=self.view.projection(right); var scope=x.scope; if scope>=local { if scope>0xffffffff-self.shift { return false,Error.evidence_limit; } scope+=self.shift; } if x.member!=y.member||scope!=y.scope||x.goal!=y.goal { return false,Error.none; } }
  let xs=self.view.children(left); let ys=self.view.children(right); if xs.len!=ys.len { return false,Error.none; }
  for x,index in xs { if a.tag==Tag.record&&index%2==0 { if x!=ys[index] { return false,Error.none; } } else { let same,e=equal(self,x,ys[index],local,depth+1); if e!=Error.none||!same { return same,e; } } } return true,Error.none;
 }
 if a.tag==Tag.type_constructor { return a.a==b.a&&a.b==b.b,Error.none; }
 if a.tag==Tag.absent||a.tag==Tag.scoped||a.tag==Tag.erased_proof { return false,Error.unresolved_type; } return true,Error.none;
}
fn row(self: Comparison&,left: u32,right: u32,local: i64,depth: i64) -> bool,Error {
 let err=step(self,depth); if err!=Error.none { return false,err; }
 if left>=self.view.effects.rows.len||right>=self.view.effects.rows.len { return false,Error.type_mismatch; }
 let a=self.view.effects.rows[left]; let b=self.view.effects.rows[right]; if (a.formal==0)!=(b.formal==0) { return false,Error.none; }
 if a.formal!=0 { let same,e=equal(self,a.formal,b.formal,local,depth+1); if e!=Error.none||!same { return same,e; } }
 let xs=self.view.effects.rowLabels(left); let ys=self.view.effects.rowLabels(right); if xs.len!=ys.len||xs.len>256 { return false,Error.none; } var used: bool[256]=[false;256];
 for x in xs {
  var found=false;
  for y,index in ys {
   let e=step(self,depth); if e!=Error.none { return false,e; } if used[index] { continue; } let first=self.view.effects.operation(x); let second=self.view.effects.operation(y);
   if first.identity!=second.identity||first.instance!=second.instance { continue; } let args=self.view.effects.operationArguments(x); let other=self.view.effects.operationArguments(y); if args.len!=other.len { continue; }
   var same=true; for expected,i in args { let matched,error=equal(self,expected,other[i],local,depth+1); if error!=Error.none { return false,error; } if !matched { same=false; break; } }
   if !same { continue; } used[index]=true; found=true; break;
  }
  if !found { return false,Error.none; }
 }
 return true,Error.none;
}
fn validate(view: View,id: u32,goal: blot_eval_type_evidence::Goal,remaining: i64&) -> Error {
 let n=view.node(id); if goal.kind!=blot_check_types::ObligationKind.contract||goal.identity.unit!=n.a||goal.identity.decl!=n.b||goal.ty==0||goal.ty>=view.nodes.len { return Error.type_mismatch; }
 let tuple=view.node(goal.ty); if tuple.tag!=Tag.product||tuple.a>view.extra.len||tuple.b>view.extra.len-tuple.a { return Error.type_mismatch; }
 let expected=view.children(goal.ty); let actual=view.children(id); if expected.len!=actual.len { return Error.type_mismatch; }
 var proof=Comparison {view,view.projection(id).scope,remaining}; for left,index in expected { let same,e=equal(proof,left,actual[index],0,0); if e!=Error.none { return e; } if !same { return Error.type_mismatch; } } return Error.none;
}
