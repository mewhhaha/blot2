namespace blot_eval_instance_arguments;
import check.types;
import support.error;
import support.native;
type Identity=blot_check_types::NominalIdentity;
struct Span { start: u32, len: u32 }
struct Owned { owner_id: u64=blot_native::fresh_owner_id(), values: const Identity[:], spans: const Span[:] }
struct Store { owner_id: u64=blot_native::fresh_owner_id(), values: Identity[>..<]&, spans: Span[>..<]& }
fn init(values: Identity[>..<]&,spans: Span[>..<]&) -> Store { return Store {values:values,spans:spans}; }
fn get(self: Owned&,id: u32) -> const Identity[:] { if id==0 { return self.values[..0]; } let span=self.spans[id-1]; return self.values[span.start..span.start+span.len]; }
fn get(self: Store&,id: u32) -> const Identity[:] { if id==0 { return self.values[..0]; } let span=self.spans[id-1]; return self.values[span.start..span.start+span.len]; }
fn intern(self: Store&,arguments: const Identity[:]) -> u32,blot_error::Error {
 var present=false; for identity in arguments { present=present||identity.decl!=0; } if !present { return 0,blot_error::Error.none; }
 for span,index in self.spans {
  if span.len!=arguments.len { continue; } var equal=true;
  for right,i in arguments { let left=self.values[span.start+i]; equal=equal&&left.unit==right.unit&&left.decl==right.decl; }
  if equal { return (index+1) as u32,blot_error::Error.none; }
 }
 if arguments.len>16||self.spans.len>=4096 { return 0,blot_error::Error.instance_limit; }
 let start=self.values.len; for arg in arguments { self.values.push(arg); } self.spans.push(Span {start as u32,arguments.len as u32}); return self.spans.len as u32,blot_error::Error.none;
}
fn copyOwned(self: Store&,values: Identity[>..<]&,spans: Span[>..<]&) -> Owned {
 for value in self.values { values.push(value); } for span in self.spans { spans.push(span); } return Owned {values:values,spans:spans};
}
fn deinit(self: Store&) { self.values.clear(); self.spans.clear(); }
