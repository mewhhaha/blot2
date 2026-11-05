// Exact immutable foreign owners observed by dependency Core validation.
namespace blot_reuse_dependency_core_inputs;
import check.core;
import check.types;
import reuse.principal_interface;
import check.effects;
import check.check;
import reuse.retained_dependency;
import reuse.frozen_dependency;
import support.error;
import support.option;
type Error=blot_error::Error;
struct Inputs { bits: u64[:],count: i64,remaining: i64&,complete: bool=true }
fn add(self: Inputs&,unit: u32) { if unit==0||unit==0xffffffff { return; } if unit>self.count { self.complete=false; return; } let index=unit-1; self.bits[index/64]|=1u64<<(index%64); }
fn charge(self: Inputs&) -> bool { if self.remaining==0 { self.complete=false; return false; } self.remaining--; return true; }
fn visit<T>(self: Inputs&,values: const T[:]) { if !charge(self) { return; } for value in values { if self.remaining==0 { self.complete=false; break; } visit(self,value); } }
fn visit<T>(self: Inputs&,value: blot_support::Option<T>) { if !charge(self) { return; } if value.present { visit(self,value.value); } }
fn visit(self: Inputs&,value: const blot_check_types::Node&) { if !charge(self) { return; } match value.tag { nominal,projection,type_constructor,instance_selection,instance_version=>{ self.add(value.a); },scoped=>{ self.add(value.b); },absent,unit,boolean,unsigned32,floating32,never,variable,function,product,record,array,list,cursor,resolver,provider,state_provider,erased_proof,forall,existential,bound,rigid,usage=>{}, } }

fn visit(self: Inputs&,value: const blot_check_core::Associated&) { if !charge(self) { return; } visit(self,value.identity); visit(self,value.target); }

fn visit(self: Inputs&,value: const blot_check_core::Binding&) { if !charge(self) { return; } visit(self,value.target); }

fn visit(self: Inputs&,value: const blot_check_core::BindingRef&) { if !charge(self) { return; } self.add(value.unit); }

fn visit(self: Inputs&,value: const blot_check_core::CallInfo&) { if !charge(self) { return; } visit(self,value.target); }

fn visit(self: Inputs&,value: const blot_check_core::Constructor&) { if !charge(self) { return; } visit(self,value.identity); }

fn visit(self: Inputs&,value: const blot_check_core::Contract&) { if !charge(self) { return; } visit(self,value.identity); }

fn visit(self: Inputs&,value: const blot_check_core::ErasedDeclarationReference&) { if !charge(self) { return; } visit(self,value.target); }

fn visit(self: Inputs&,value: const blot_check_core::Nominal&) { if !charge(self) { return; } visit(self,value.identity); }

fn visit(self: Inputs&,value: const blot_check_core::Obligation&) { if !charge(self) { return; } visit(self,value.identity); self.add(value.qualification_unit); }

fn visit(self: Inputs&,value: const blot_check_core::OperationName&) { if !charge(self) { return; } visit(self,value.identity); }

fn visit(self: Inputs&,value: const blot_check_core::OperationValue&) { if !charge(self) { return; } visit(self,value.identity); visit(self,value.instance); }

fn visit(self: Inputs&,value: const blot_check_core::Projection&) { if !charge(self) { return; } visit(self,value.nominal); }

fn visit(self: Inputs&,value: const blot_check_core::ResolverInfo&) { if !charge(self) { return; } visit(self,value.method); }

fn visit(self: Inputs&,value: const blot_check_core::Types&) { if !charge(self) { return; } visit(self,value.nodes); visit(self,value.operations); visit(self,value.quantifier_obligations); }

fn visit(self: Inputs&,value: const blot_check_types::NominalIdentity&) { if !charge(self) { return; } self.add(value.unit); }

fn visit(self: Inputs&,value: const blot_check_types::Obligation&) { if !charge(self) { return; } visit(self,value.identity); self.add(value.qualification_unit); }

fn visit(self: Inputs&,value: const blot_check_types::Operation&) { if !charge(self) { return; } visit(self,value.identity); visit(self,value.instance); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::ContractMember&) { if !charge(self) { return; } visit(self,value.contract); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::ExternalTarget&) { if !charge(self) { return; } self.add(value.unit); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::Implementation&) { if !charge(self) { return; } visit(self,value.identity); visit(self,value.contract); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::ImplementationMember&) { if !charge(self) { return; } visit(self,value.target); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::MemberTemplate&) { if !charge(self) { return; } visit(self,value.contract); }

fn visit(self: Inputs&,value: const blot_reuse_principal_interface::SelectedProof&) { if !charge(self) { return; } visit(self,value.predicate_target); self.add(value.context); visit(self,value.predicate); visit(self,value.implementation); visit(self,value.contract); }

fn module(self: Inputs&,owner: const blot_check_core::Module&) { self.add(owner.unit); visit(self,owner.dependency_references); visit(self,owner.erased_declaration_references); visit(self,owner.types); visit(self,owner.bindings); visit(self,owner.references); visit(self,owner.calls); visit(self,owner.obligations); visit(self,owner.nominals); visit(self,owner.operation_names); visit(self,owner.constructors); visit(self,owner.projections); visit(self,owner.associated); visit(self,owner.contracts); visit(self,owner.contract_members); visit(self,owner.implementations); visit(self,owner.implementation_members); visit(self,owner.member_templates); visit(self,owner.selected_proofs); visit(self,owner.selected_members); visit(self,owner.resolver_ops); visit(self,owner.operation_values); }

fn invocationActive(value: const blot_reuse_frozen_dependency::FrozenDependency&) -> bool { for module in value.modules { for binding in module.core.bindings { if binding.capability_parameters.inputInvokes() { return true; } } } return false; }
struct Owners { stable: bool[:]=[] }
reusable[] var stable_pool: bool[>..]=[];
reusable[] var words_pool: u64[>..]=[];
fn deinit(self: Owners&) { stable_pool.free_slice(self.stable); self.stable=[]; }
fn init(current: const blot_reuse_retained_dependency::Snapshot&,previous: const blot_reuse_retained_dependency::Snapshot&) -> blot_support::Option<Owners>,Error {
 let count=current.initialized; if !previous.validated||count!=previous.initialized||count==0||count>1024 { return blot_support::none<Owners>(),Error.none; } let activation_changed=invocationActive(current.value)!=invocationActive(previous.value); let width=(count+63)/64; if count>0x7fffffffffffffff/width { return blot_support::none<Owners>(),Error.none; } let edge_words=count*width; if count>0x7fffffffffffffff-edge_words { return blot_support::none<Owners>(),Error.none; } let words=edge_words+count; let stable=stable_pool.alloc_slice(count); let storage=words_pool.alloc_slice(words); let edges=storage[..edge_words]; let queue=storage[edge_words..]; for &word in edges { word=0; } var remaining: i64=1000000;
 for &same,id in stable { same=current.shares(previous,id); if same&&activation_changed { for node in current.value.modules[id].core.types.nodes { if node.tag==blot_check_types::Tag.scoped { same=false; break; } } } if !same { continue; } var inputs=Inputs {edges[id*width..id*width+width],count,remaining}; inputs.module(current.value.modules[id].core); same=inputs.complete; }
 var queued=0; for same,id in stable { if !same { queue[queued]=id as u64; queued++; } } var next=0; while next<queued { let target=queue[next]; next++; for &same,id in stable { if !same||(edges[id*width+(target/64) as i64]&(1u64<<((target%64) as u32)))==0 { continue; } same=false; queue[queued]=id as u64; queued++; } } words_pool.free_slice(storage); return blot_support::some(Owners {stable}),Error.none;
}
