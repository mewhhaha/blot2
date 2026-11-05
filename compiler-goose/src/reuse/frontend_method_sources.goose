// Ephemeral complete method facts; no source borrow enters a returned slot map.
namespace blot_reuse_frontend_method_sources;
import check.core;
import check.check;
import check.types;
import check.capability_flow;
import check.capability_contracts;
import parse.symbols;
import reuse.principal_interface;
import support.option;
struct Role {implementation:blot_check_types::NominalIdentity,member:u32}
struct Header {flow:blot_check_capability_flow::Contract,parameters:blot_check_capability_flow::Parameters,recipe:blot_support::Option<blot_check_capability_contracts::Recipe>}
// Production compares retained Core against the current Checked publication.
// Static generic read handles the two concrete owners without function pointers.
struct Context {before:const blot_check_core::Module&,after:const blot_check_check::Checked&,names:const blot_parse_symbols::Pool&,remaining:i64=4096}
struct Sources {context:Context?=null}
fn view(self:Context&)->Sources {return Sources {self};}
fn before(self:Sources,role:Role,binding:u32)->blot_support::Option<Header> {let context=self.context;if !context {return blot_support::none<Header>();}return read(context,context.before,role,binding,false);}
fn after(self:Sources,role:Role,binding:u32)->blot_support::Option<Header> {let context=self.context;if !context {return blot_support::none<Header>();}return read(context,context.after,role,binding,true);}
fn work(self:Context&)->bool {if self.remaining==0 {return false;}self.remaining--;return true;}
fn read<O>(self:Context&,owner:const O&,role:Role,binding:u32,current:bool)->blot_support::Option<Header> {
 if !self.work()||owner.unit!=role.implementation.unit||binding==0||binding>=owner.bindings.len {return blot_support::none<Header>();}var found=false;
 for implementation in owner.implementations {
  if !self.work() {return blot_support::none<Header>();}if implementation.private||implementation.identity!=role.implementation {continue;}
  for member in owner.implementation_members[implementation.members.start..implementation.members.start+implementation.members.len] {
   if !self.work() {return blot_support::none<Header>();}
   if member.kind!=blot_reuse_principal_interface::ImplementationMemberKind.value||member.name!=role.member||member.target.unit!=owner.unit||member.target.binding!=binding {continue;}
   if found {return blot_support::none<Header>();}found=true;
  }
 }
 if !found {return blot_support::none<Header>();}let source=owner.bindings[binding];if !source.private||source.kind!=blot_reuse_principal_interface::Kind.global {return blot_support::none<Header>();}
 if current {
  if !source.named_function||source.name==0||role.implementation.decl&blot_check_types::opaque_name_bit==0 {return blot_support::none<Header>();}
  let name=self.names.get(source.name);let implementation=self.names.get(role.implementation.decl&~blot_check_types::opaque_name_bit);let member=self.names.get(role.member);
  if name.len!=implementation.len+1+member.len||name[..implementation.len]!=implementation||name[implementation.len]!='.'||name[implementation.len+1..]!=member {return blot_support::none<Header>();}
 }
 return blot_support::some(Header {source.capability_flow,source.capability_parameters,owner.capability_contracts.header(binding,source.capability_parameters.arity() as u32)});
}
