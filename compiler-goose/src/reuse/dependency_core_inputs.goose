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
fn add(self_: Inputs&,unit: u32) { if unit==0||unit==0xffffffff { return; } if unit>self_.count { self_.complete=false; return; } let index=unit-1; self_.bits[index/64]|=(1 as u64)<<(index%64); }
fn charge(self_: Inputs&) -> bool { if self_.remaining==0 { self_.complete=false; return false; } self_.remaining--; return true; }
fn visit<T>(self_: Inputs&,values: const T[:]) { if !charge(self_) { return; } for value in values { if self_.remaining==0 { self_.complete=false; break; } visit(self_,value); } }
fn visit<T>(self_: Inputs&,value: blot_support::Option<T>) { if !charge(self_) { return; } if value.present { visit(self_,value.value); } }
fn visit(self_: Inputs&,value: const blot_check_types::Node&) { if !charge(self_) { return; } match value.tag { nominal,projection,type_constructor,instance_selection,instance_version=>{ self_.add(value.a); },scoped=>{ self_.add(value.b); },absent,unit,boolean,unsigned32,floating32,never,variable,function,product,record,array,list,cursor,resolver,provider,state_provider,erased_proof,forall,existential,bound,rigid,usage=>{}, } }

fn visit(self_: Inputs&,value: const blot_check_core::Associated&) { if !charge(self_) { return; } visit(self_,value.identity); visit(self_,value.target); }

fn visit(self_: Inputs&,value: const blot_check_core::Binding&) { if !charge(self_) { return; } visit(self_,value.target); }

fn visit(self_: Inputs&,value: const blot_check_core::BindingRef&) { if !charge(self_) { return; } self_.add(value.unit); }

fn visit(self_: Inputs&,value: const blot_check_core::CallInfo&) { if !charge(self_) { return; } visit(self_,value.target); }

fn visit(self_: Inputs&,value: const blot_check_core::Constructor&) { if !charge(self_) { return; } visit(self_,value.identity); }

fn visit(self_: Inputs&,value: const blot_check_core::Contract&) { if !charge(self_) { return; } visit(self_,value.identity); }

fn visit(self_: Inputs&,value: const blot_check_core::ErasedDeclarationReference&) { if !charge(self_) { return; } visit(self_,value.target); }

fn visit(self_: Inputs&,value: const blot_check_core::Nominal&) { if !charge(self_) { return; } visit(self_,value.identity); }

fn visit(self_: Inputs&,value: const blot_check_core::Obligation&) { if !charge(self_) { return; } visit(self_,value.identity); self_.add(value.qualification_unit); }

fn visit(self_: Inputs&,value: const blot_check_core::OperationName&) { if !charge(self_) { return; } visit(self_,value.identity); }

fn visit(self_: Inputs&,value: const blot_check_core::OperationValue&) { if !charge(self_) { return; } visit(self_,value.identity); visit(self_,value.instance); }

fn visit(self_: Inputs&,value: const blot_check_core::Projection&) { if !charge(self_) { return; } visit(self_,value.nominal); }

fn visit(self_: Inputs&,value: const blot_check_core::ResolverInfo&) { if !charge(self_) { return; } visit(self_,value.method); }

fn visit(self_: Inputs&,value: const blot_check_core::Types&) { if !charge(self_) { return; } visit(self_,value.nodes); visit(self_,value.operations); visit(self_,value.quantifier_obligations); }

fn visit(self_: Inputs&,value: const blot_check_types::NominalIdentity&) { if !charge(self_) { return; } self_.add(value.unit); }

fn visit(self_: Inputs&,value: const blot_check_types::Obligation&) { if !charge(self_) { return; } visit(self_,value.identity); self_.add(value.qualification_unit); }

fn visit(self_: Inputs&,value: const blot_check_types::Operation&) { if !charge(self_) { return; } visit(self_,value.identity); visit(self_,value.instance); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::ContractMember&) { if !charge(self_) { return; } visit(self_,value.contract); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::ExternalTarget&) { if !charge(self_) { return; } self_.add(value.unit); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::Implementation&) { if !charge(self_) { return; } visit(self_,value.identity); visit(self_,value.contract); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::ImplementationMember&) { if !charge(self_) { return; } visit(self_,value.target); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::MemberTemplate&) { if !charge(self_) { return; } visit(self_,value.contract); }

fn visit(self_: Inputs&,value: const blot_reuse_principal_interface::SelectedProof&) { if !charge(self_) { return; } visit(self_,value.predicate_target); self_.add(value.context); visit(self_,value.predicate); visit(self_,value.implementation); visit(self_,value.contract); }

fn module(self_: Inputs&,owner: const blot_check_core::Module&) { self_.add(owner.unit); visit(self_,owner.dependency_references); visit(self_,owner.erased_declaration_references); visit(self_,owner.types); visit(self_,owner.bindings); visit(self_,owner.references); visit(self_,owner.calls); visit(self_,owner.obligations); visit(self_,owner.nominals); visit(self_,owner.operation_names); visit(self_,owner.constructors); visit(self_,owner.projections); visit(self_,owner.associated); visit(self_,owner.contracts); visit(self_,owner.contract_members); visit(self_,owner.implementations); visit(self_,owner.implementation_members); visit(self_,owner.member_templates); visit(self_,owner.selected_proofs); visit(self_,owner.selected_members); visit(self_,owner.resolver_ops); visit(self_,owner.operation_values); }

fn invocationActive(value: const blot_reuse_frozen_dependency::FrozenDependency&) -> bool { for module in value.modules { for binding in module.core.bindings { if binding.capability_parameters.inputInvokes() { return true; } } } return false; }
struct Owners { stable: bool[:]=default<bool[:]>() }
reusable[] var stable_pool: bool[>..]=[];
reusable[] var words_pool: u64[>..]=[];
fn deinit(self_: Owners&) { stable_pool.free_slice(self_.stable); self_.stable=default<bool[:]>(); }
fn init(current: const blot_reuse_retained_dependency::Snapshot&,previous: const blot_reuse_retained_dependency::Snapshot&) -> blot_support::Option<Owners>,Error {
 let count=current.initialized; if !previous.validated||count!=previous.initialized||count==0||count>1024 { return blot_support::none<Owners>(),blot_error::Error.none; } let activation_changed=invocationActive(current.value)!=invocationActive(previous.value); let width=(count+63)/64; if count>0x7fffffffffffffff/width { return blot_support::none<Owners>(),blot_error::Error.none; } let edge_words=count*width; if count>0x7fffffffffffffff-edge_words { return blot_support::none<Owners>(),blot_error::Error.none; } let words=edge_words+count; let stable=stable_pool.alloc_slice(count); let storage=words_pool.alloc_slice(words); let edges=storage[..edge_words]; let queue=storage[edge_words..]; for &word in edges { word=0; } var remaining: i64=1000000;
 for &same,id in stable { same=current.shares(previous,id); if same&&activation_changed { for node in current.value.modules[id].core.types.nodes { if node.tag==blot_check_types::Tag.scoped { same=false; break; } } } if !same { continue; } var inputs=Inputs {edges[id*width..id*width+width],count,remaining}; inputs.module(current.value.modules[id].core); same=inputs.complete; }
 var queued=0; for same,id in stable { if !same { queue[queued]=id as u64; queued++; } } var next=0; while next<queued { let target=queue[next]; next++; for &same,id in stable { if !same||(edges[id*width+(target/64) as i64]&((1 as u64)<<((target%64) as u32)))==0 { continue; } same=false; queue[queued]=id as u64; queued++; } } words_pool.free_slice(storage); return blot_support::some(Owners {stable}),blot_error::Error.none;
}
