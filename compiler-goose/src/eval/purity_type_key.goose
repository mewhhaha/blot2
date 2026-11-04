// Frozen state_specialize TypeKey diagnostic grammar.
namespace blot_eval_purity_type_key;
import std;
import check.types;
import check.effects;
import parse.lexer;
import support.error;
type Error=blot_error::Error;
enum Kind { nominal,operation }
struct Identity { module: const u8[:],declaration: const u8[:] }
struct Context<S> { types: blot_check_types::Store&,source: S&,identity_bytes: u8[>..]& }
fn count(text: const u8[:]) -> i64,Error {
 var at=0; var points=0;
 while at<text.len { let width=blot_parse_lexer::utf8_width(text[at]); if width==0||width>text.len-at { return 0,Error.type_limit; } let point,err=blot_parse_lexer::decode_point(text[at..at+width]); if err!=Error.none { return 0,Error.type_limit; } points++; at+=width; } return points,Error.none;
}
fn pack(text: const u8[:]) -> u8[>..],Error { let length,err=count(text); if err!=Error.none { return [],err; } return str(length,":",text),Error.none; }
fn nominal(identity: Identity) -> u8[>..],Error { let module,err=pack(identity.module); if err!=Error.none { return [],err; } let declaration,error=pack(identity.declaration); if error!=Error.none { return [],error; } return str(module,declaration),Error.none; }
fn fixed<S>(self: Context<S>&,module: const u8[:],declaration: const u8[:]) -> Identity {
 let start=self.identity_bytes.len; self.identity_bytes.append(module); let middle=self.identity_bytes.len; self.identity_bytes.append(declaration); return Identity {self.identity_bytes[start..middle],self.identity_bytes[middle..]};
}
fn typesKey<S>(self: Context<S>&,values: const u32[:],fuel: i64) -> u8[>..],Error {
 var owned: u32[>..]=[]; owned.append(values); var bytes: u8[>..]=[]; var remaining=fuel;
 for value in owned { if remaining==0 { return [],Error.specialization_limit; } remaining--; let key,error=typeKey(self,value,remaining); if error!=Error.none { return [],error; } let packed,err=pack(key); if err!=Error.none { return [],err; } bytes.append(packed); }
 if remaining==0 { return [],Error.specialization_limit; } return bytes,Error.none;
}
fn operation<S>(self: Context<S>&,label: u32,fuel: i64) -> Identity,Error {
 let operation=self.types.operation(label);
 if label==blot_check_types::foreign_operation { return fixed(self,"blot:compiler","Foreign"),Error.none; }
 if operation.identity.unit==0xffffffff&&(operation.identity.decl==1||operation.identity.decl==2) {
  let args=self.types.list(operation.arguments); if args.len!=1 { return default<Identity>(),Error.ambiguous_type_key; } let key,err=typeKey(self,args[0],fuel); if err!=Error.none { return default<Identity>(),err; }
  var action: const u8[:]="write"; if operation.identity.decl==1 { action="read"; } let declaration=str(action,":",key); return fixed(self,"blot:state",declaration),Error.none;
 }
 let identity,error=self.source.origin(operation.identity,Kind.operation); if error!=Error.none { return default<Identity>(),error; }
 let args,err=self.source.arguments(operation.identity,Kind.operation,self.types.list(operation.arguments)); if err!=Error.none { return default<Identity>(),err; }
 if args.len==0&&operation.arguments.len==0 { return identity,Error.none; }
 let key,e=typesKey(self,args,fuel); if e!=Error.none { return default<Identity>(),e; } let declaration=str(identity.declaration,"<",key,">"); return fixed(self,identity.module,declaration),Error.none;
}
fn less(left: Identity,right: Identity) -> bool { return left.module<right.module||(left.module==right.module&&left.declaration<right.declaration); }
fn rowKey<S>(self: Context<S>&,row: u32,fuel: i64) -> u8[>..],Error {
 let resolved,err=self.types.resolveEffects(row,0); if err!=Error.none { return [],err; } if self.types.row(resolved).tail!=blot_check_effects::Tail.closed { return [],Error.ambiguous_type_key; }
 var labels: u32[>..]=[]; labels.append(self.types.rowLabels(resolved)); var identities: Identity[>..]=[];
 for label in labels { let identity,error=operation(self,label,65536); if error!=Error.none { return [],error; } identities.push(identity); }
 ::sort(identities,less); var bytes: u8[>..]=[];
 for identity in identities { let name,error=nominal(identity); if error!=Error.none { return [],error; } let key,e=pack(name); if e!=Error.none { return [],e; } bytes.append(key); } return bytes,Error.none;
}
fn functionKey<S>(self: Context<S>&,parameter_id: u32,result_id: u32,row: u32,fuel: i64) -> u8[>..],Error {
 if fuel==0 { return [],Error.specialization_limit; } let parameter,e=typeKey(self,parameter_id,fuel-1); if e!=Error.none { return [],e; }
 let result,error=typeKey(self,result_id,fuel-1); if error!=Error.none { return [],error; } let effects,err=rowKey(self,row,fuel-1); if err!=Error.none { return [],err; }
 let pk,e1=pack(parameter); if e1!=Error.none { return [],e1; } let rk,e2=pack(result); if e2!=Error.none { return [],e2; } let ek,e3=pack(effects); if e3!=Error.none { return [],e3; } return str("c",pk,rk,ek),Error.none;
}
fn typeKey<S>(self: Context<S>&,id: u32,fuel: i64) -> u8[>..],Error {
 if fuel==0 { return [],Error.specialization_limit; } let rest=fuel-1; let resolved,e=self.types.resolve(id,0); if e!=Error.none { return [],e; } let node=self.types.node(resolved); let tag=node.tag;
 if tag==blot_check_types::Tag.unit { return str("u"),Error.none; } if tag==blot_check_types::Tag.unsigned32 { return str("i"),Error.none; } if tag==blot_check_types::Tag.floating32 { return str("f"),Error.none; } if tag==blot_check_types::Tag.boolean { return str("b"),Error.none; }
 if tag==blot_check_types::Tag.nominal {
  let identity=blot_check_types::NominalIdentity {node.a,node.b}; let origin,error=self.source.origin(identity,Kind.nominal); if error!=Error.none { return [],error; }
  let name,err=nominal(origin); if err!=Error.none { return [],err; } let logical,e1=self.source.arguments(identity,Kind.nominal,self.types.nominalArguments(node)); if e1!=Error.none { return [],e1; }
  let args,e2=typesKey(self,logical,rest); if e2!=Error.none { return [],e2; } let packed,e3=pack(args); if e3!=Error.none { return [],e3; } return str("n",name,packed),Error.none;
 }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor {
  let element,error=typeKey(self,node.a,rest); if error!=Error.none { return [],error; } let key,err=pack(element); if err!=Error.none { return [],err; } var prefix: const u8[:]="a"; if tag==blot_check_types::Tag.cursor { prefix="c"; } else if tag==blot_check_types::Tag.list { prefix="l"; } return str(prefix,key),Error.none;
 }
 if tag==blot_check_types::Tag.product { let elements,error=typesKey(self,self.types.extra[node.a..node.a+node.b],rest); if error!=Error.none { return [],error; } let key,err=pack(elements); if err!=Error.none { return [],err; } return str("p",key),Error.none; }
 if tag==blot_check_types::Tag.function { return functionKey(self,node.a,node.b,node.c,fuel); } return [],Error.ambiguous_type_key;
}
