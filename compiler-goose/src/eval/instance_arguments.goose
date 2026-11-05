namespace blot_eval_instance_arguments;
import check.types;
import support.error;
import support.native;

type Identity=blot_check_types::NominalIdentity;
struct Span { start: u32, len: u32 }
struct Owned { owner_id: u64=blot_native::fresh_owner_id(), values: const Identity[:], spans: const Span[:] }
struct Store { owner_id: u64=blot_native::fresh_owner_id(), values: Identity[>..<]&, spans: Span[>..<]& }
fn init(values: Identity[>..<]&,spans: Span[>..<]&) -> Store { return Store {values:values,spans:spans}; }
fn get(self_: Owned&,id: u32) -> const Identity[:] { if id==0 { return self_.values[..0]; } let span=self_.spans[id-1]; return self_.values[span.start..span.start+span.len]; }
fn get(self_: Store&,id: u32) -> const Identity[:] { if id==0 { return self_.values[..0]; } let span=self_.spans[id-1]; return self_.values[span.start..span.start+span.len]; }
fn intern(self_: Store&,arguments: const Identity[:]) -> u32,blot_error::Error {
 var present=false; for identity in arguments { present=present||identity.decl!=0; } if !present { return 0,blot_error::Error.none; }
 for span,index in self_.spans {
  if span.len!=arguments.len { continue; } var equal=true;
  for right,i in arguments { let left=self_.values[span.start+i]; equal=equal&&left.unit==right.unit&&left.decl==right.decl; }
  if equal { return (index+1) as u32,blot_error::Error.none; }
 }
 if arguments.len>16||self_.spans.len>=4096 { return 0,blot_error::Error.instance_limit; }
 let start=self_.values.len; for arg in arguments { self_.values.push(arg); } self_.spans.push(Span {start as u32,arguments.len as u32}); return self_.spans.len as u32,blot_error::Error.none;
}
fn copyOwned(self_: Store&,values: Identity[>..<]&,spans: Span[>..<]&) -> Owned {
 for value in self_.values { values.push(value); } for span in self_.spans { spans.push(span); } return Owned {values:values,spans:spans};
}
fn deinit(self_: Store&) { self_.values.clear(); self_.spans.clear(); }
