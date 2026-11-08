// Immutable checked-body auxiliary records with explicit edge roles.
namespace blot_reuse_body_auxiliary;
import check.check;
import check.types;
import check.numeric_proof_bodies;
import check.numeric_proof_terms;
import check.generative_schemes;
import reuse.principal_interface;
import support.error;
import support.option;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
import support.structural;
type Error=blot_error::Error;
type List=blot_check_types::List;
type Identity=blot_check_types::NominalIdentity;
type Proof=blot_check_check::DictionaryProof;
enum Route {word,node,binding,ty,row,label,name,instance,scope,constructor,types,bindings,request_arms,resolver_ops,resolver_completions,carries,template,goal,proof,contract_identity,operation_identity,callee_identity,nodes_pair,proposition}
struct Tables {
usage_loans:blot_check_check::UsageLoan[:]=default<blot_check_check::UsageLoan[:]>(),
rank_implementations:blot_check_check::RankImplementation[:]=default<blot_check_check::RankImplementation[:]>(),
generative_bindings:blot_check_generative_schemes::Binder[:]=default<blot_check_generative_schemes::Binder[:]>(),
dictionary_selections:blot_check_check::DictionarySelection[:]=default<blot_check_check::DictionarySelection[:]>(),
dictionary_uses:blot_check_check::DictionaryUse[:]=default<blot_check_check::DictionaryUse[:]>(),
computations:blot_check_check::Computation[:]=default<blot_check_check::Computation[:]>(),
request_loops:blot_check_check::RequestLoop[:]=default<blot_check_check::RequestLoop[:]>(),
request_arms:blot_check_check::RequestArm[:]=default<blot_check_check::RequestArm[:]>(),
request_controls:blot_check_check::RequestControl[:]=default<blot_check_check::RequestControl[:]>(),
reflections:blot_check_check::Reflection[:]=default<blot_check_check::Reflection[:]>(),
effect_scopes:blot_check_check::EffectScope[:]=default<blot_check_check::EffectScope[:]>(),
effect_runners:blot_check_check::EffectRunner[:]=default<blot_check_check::EffectRunner[:]>(),
provider_blocks:blot_check_check::ProviderBlock[:]=default<blot_check_check::ProviderBlock[:]>(),
resolver_blocks:blot_check_check::ResolverBlock[:]=default<blot_check_check::ResolverBlock[:]>(),
resolver_ops:blot_check_check::ResolverOp[:]=default<blot_check_check::ResolverOp[:]>(),
resolver_joins:blot_check_check::ResolverJoin[:]=default<blot_check_check::ResolverJoin[:]>(),
resolver_completions:blot_check_check::ResolverCompletion[:]=default<blot_check_check::ResolverCompletion[:]>(),
resolver_loops:blot_check_check::ResolverLoop[:]=default<blot_check_check::ResolverLoop[:]>(),
operation_uses:blot_check_check::OperationUse[:]=default<blot_check_check::OperationUse[:]>(),
statement_arms:blot_check_check::StatementArm[:]=default<blot_check_check::StatementArm[:]>(),
}
struct Selection {predicate:blot_check_types::Obligation,arguments:List=List{..},implementation:bool}
struct Index {node:u32,table:u32,value:u32}
struct OperationBinding {binding:u32,operation:u32}
struct Constructor {nominal:Identity,tag:u32}
struct Iterator {node:u32,body:u32}
struct Owner {
 tables:Tables=Tables{..},extra:u32[:]=default<u32[:]>(),origins:u32[:]=default<u32[:]>(),binding_origins:u32[:]=default<u32[:]>(),dependencies:u32[:]=default<u32[:]>(),
 iterators:Iterator[:]=default<Iterator[:]>(),constructors:Constructor[:]=default<Constructor[:]>(),indices:Index[:]=default<Index[:]>(),operation_bindings:OperationBinding[:]=default<OperationBinding[:]>(),selections:Selection[:]=default<Selection[:]>(),
 numeric_body:blot_check_numeric_proof_bodies::Owned=blot_check_numeric_proof_bodies::Owned{..},proof_parameters:u32[:]=default<u32[:]>(),proof_debit:blot_support::Option<blot_check_numeric_proof_bodies::Debit> =blot_support::none<blot_check_numeric_proof_bodies::Debit>(),live:bool=false,slot:u32=0,
}
reusable var owners:Owner[>..]=[];
fn ownerIndex(owner:const Owner&)->i64 {assert(owner.live && owner.slot!=0);let index=owner.slot as i64-1;assert(index<owners.len);let canonical:const Owner& =owners[index];assert(canonical .== owner);return index;}
reusable[] var pool_blot_check_check__UsageLoan:blot_check_check::UsageLoan[>..]=[];
fn copyOwned(values:const blot_check_check::UsageLoan[:])->blot_check_check::UsageLoan[:] {if values.len==0 {return default<blot_check_check::UsageLoan[:]>();}let run=pool_blot_check_check__UsageLoan.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::UsageLoan[:]) {if values.len==0 {return;}pool_blot_check_check__UsageLoan.free_slice(values);}
reusable[] var pool_blot_check_check__RankImplementation:blot_check_check::RankImplementation[>..]=[];
fn copyOwned(values:const blot_check_check::RankImplementation[:])->blot_check_check::RankImplementation[:] {if values.len==0 {return default<blot_check_check::RankImplementation[:]>();}let run=pool_blot_check_check__RankImplementation.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::RankImplementation[:]) {if values.len==0 {return;}pool_blot_check_check__RankImplementation.free_slice(values);}
reusable[] var pool_blot_check_generative_schemes__Binder:blot_check_generative_schemes::Binder[>..]=[];
fn copyOwned(values:const blot_check_generative_schemes::Binder[:])->blot_check_generative_schemes::Binder[:] {if values.len==0 {return default<blot_check_generative_schemes::Binder[:]>();}let run=pool_blot_check_generative_schemes__Binder.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_generative_schemes::Binder[:]) {if values.len==0 {return;}pool_blot_check_generative_schemes__Binder.free_slice(values);}
reusable[] var pool_blot_check_check__DictionarySelection:blot_check_check::DictionarySelection[>..]=[];
fn copyOwned(values:const blot_check_check::DictionarySelection[:])->blot_check_check::DictionarySelection[:] {if values.len==0 {return default<blot_check_check::DictionarySelection[:]>();}let run=pool_blot_check_check__DictionarySelection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::DictionarySelection[:]) {if values.len==0 {return;}pool_blot_check_check__DictionarySelection.free_slice(values);}
reusable[] var pool_blot_check_check__DictionaryUse:blot_check_check::DictionaryUse[>..]=[];
fn copyOwned(values:const blot_check_check::DictionaryUse[:])->blot_check_check::DictionaryUse[:] {if values.len==0 {return default<blot_check_check::DictionaryUse[:]>();}let run=pool_blot_check_check__DictionaryUse.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::DictionaryUse[:]) {if values.len==0 {return;}pool_blot_check_check__DictionaryUse.free_slice(values);}
reusable[] var pool_blot_check_check__Computation:blot_check_check::Computation[>..]=[];
fn copyOwned(values:const blot_check_check::Computation[:])->blot_check_check::Computation[:] {if values.len==0 {return default<blot_check_check::Computation[:]>();}let run=pool_blot_check_check__Computation.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::Computation[:]) {if values.len==0 {return;}pool_blot_check_check__Computation.free_slice(values);}
reusable[] var pool_blot_check_check__RequestLoop:blot_check_check::RequestLoop[>..]=[];
fn copyOwned(values:const blot_check_check::RequestLoop[:])->blot_check_check::RequestLoop[:] {if values.len==0 {return default<blot_check_check::RequestLoop[:]>();}let run=pool_blot_check_check__RequestLoop.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::RequestLoop[:]) {if values.len==0 {return;}pool_blot_check_check__RequestLoop.free_slice(values);}
reusable[] var pool_blot_check_check__RequestArm:blot_check_check::RequestArm[>..]=[];
fn copyOwned(values:const blot_check_check::RequestArm[:])->blot_check_check::RequestArm[:] {if values.len==0 {return default<blot_check_check::RequestArm[:]>();}let run=pool_blot_check_check__RequestArm.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::RequestArm[:]) {if values.len==0 {return;}pool_blot_check_check__RequestArm.free_slice(values);}
reusable[] var pool_blot_check_check__RequestControl:blot_check_check::RequestControl[>..]=[];
fn copyOwned(values:const blot_check_check::RequestControl[:])->blot_check_check::RequestControl[:] {if values.len==0 {return default<blot_check_check::RequestControl[:]>();}let run=pool_blot_check_check__RequestControl.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::RequestControl[:]) {if values.len==0 {return;}pool_blot_check_check__RequestControl.free_slice(values);}
reusable[] var pool_blot_check_check__Reflection:blot_check_check::Reflection[>..]=[];
fn copyOwned(values:const blot_check_check::Reflection[:])->blot_check_check::Reflection[:] {if values.len==0 {return default<blot_check_check::Reflection[:]>();}let run=pool_blot_check_check__Reflection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::Reflection[:]) {if values.len==0 {return;}pool_blot_check_check__Reflection.free_slice(values);}
reusable[] var pool_blot_check_check__EffectScope:blot_check_check::EffectScope[>..]=[];
fn copyOwned(values:const blot_check_check::EffectScope[:])->blot_check_check::EffectScope[:] {if values.len==0 {return default<blot_check_check::EffectScope[:]>();}let run=pool_blot_check_check__EffectScope.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::EffectScope[:]) {if values.len==0 {return;}pool_blot_check_check__EffectScope.free_slice(values);}
reusable[] var pool_blot_check_check__EffectRunner:blot_check_check::EffectRunner[>..]=[];
fn copyOwned(values:const blot_check_check::EffectRunner[:])->blot_check_check::EffectRunner[:] {if values.len==0 {return default<blot_check_check::EffectRunner[:]>();}let run=pool_blot_check_check__EffectRunner.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::EffectRunner[:]) {if values.len==0 {return;}pool_blot_check_check__EffectRunner.free_slice(values);}
reusable[] var pool_blot_check_check__ProviderBlock:blot_check_check::ProviderBlock[>..]=[];
fn copyOwned(values:const blot_check_check::ProviderBlock[:])->blot_check_check::ProviderBlock[:] {if values.len==0 {return default<blot_check_check::ProviderBlock[:]>();}let run=pool_blot_check_check__ProviderBlock.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ProviderBlock[:]) {if values.len==0 {return;}pool_blot_check_check__ProviderBlock.free_slice(values);}
reusable[] var pool_blot_check_check__ResolverBlock:blot_check_check::ResolverBlock[>..]=[];
fn copyOwned(values:const blot_check_check::ResolverBlock[:])->blot_check_check::ResolverBlock[:] {if values.len==0 {return default<blot_check_check::ResolverBlock[:]>();}let run=pool_blot_check_check__ResolverBlock.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ResolverBlock[:]) {if values.len==0 {return;}pool_blot_check_check__ResolverBlock.free_slice(values);}
reusable[] var pool_blot_check_check__ResolverOp:blot_check_check::ResolverOp[>..]=[];
fn copyOwned(values:const blot_check_check::ResolverOp[:])->blot_check_check::ResolverOp[:] {if values.len==0 {return default<blot_check_check::ResolverOp[:]>();}let run=pool_blot_check_check__ResolverOp.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ResolverOp[:]) {if values.len==0 {return;}pool_blot_check_check__ResolverOp.free_slice(values);}
reusable[] var pool_blot_check_check__ResolverJoin:blot_check_check::ResolverJoin[>..]=[];
fn copyOwned(values:const blot_check_check::ResolverJoin[:])->blot_check_check::ResolverJoin[:] {if values.len==0 {return default<blot_check_check::ResolverJoin[:]>();}let run=pool_blot_check_check__ResolverJoin.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ResolverJoin[:]) {if values.len==0 {return;}pool_blot_check_check__ResolverJoin.free_slice(values);}
reusable[] var pool_blot_check_check__ResolverCompletion:blot_check_check::ResolverCompletion[>..]=[];
fn copyOwned(values:const blot_check_check::ResolverCompletion[:])->blot_check_check::ResolverCompletion[:] {if values.len==0 {return default<blot_check_check::ResolverCompletion[:]>();}let run=pool_blot_check_check__ResolverCompletion.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ResolverCompletion[:]) {if values.len==0 {return;}pool_blot_check_check__ResolverCompletion.free_slice(values);}
reusable[] var pool_blot_check_check__ResolverLoop:blot_check_check::ResolverLoop[>..]=[];
fn copyOwned(values:const blot_check_check::ResolverLoop[:])->blot_check_check::ResolverLoop[:] {if values.len==0 {return default<blot_check_check::ResolverLoop[:]>();}let run=pool_blot_check_check__ResolverLoop.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::ResolverLoop[:]) {if values.len==0 {return;}pool_blot_check_check__ResolverLoop.free_slice(values);}
reusable[] var pool_blot_check_check__OperationUse:blot_check_check::OperationUse[>..]=[];
fn copyOwned(values:const blot_check_check::OperationUse[:])->blot_check_check::OperationUse[:] {if values.len==0 {return default<blot_check_check::OperationUse[:]>();}let run=pool_blot_check_check__OperationUse.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::OperationUse[:]) {if values.len==0 {return;}pool_blot_check_check__OperationUse.free_slice(values);}
reusable[] var pool_blot_check_check__StatementArm:blot_check_check::StatementArm[>..]=[];
fn copyOwned(values:const blot_check_check::StatementArm[:])->blot_check_check::StatementArm[:] {if values.len==0 {return default<blot_check_check::StatementArm[:]>();}let run=pool_blot_check_check__StatementArm.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_check::StatementArm[:]) {if values.len==0 {return;}pool_blot_check_check__StatementArm.free_slice(values);}
reusable[] var pool_u32:u32[>..]=[];
fn copyOwned(values:const u32[:])->u32[:] {if values.len==0 {return default<u32[:]>();}let run=pool_u32.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const u32[:]) {if values.len==0 {return;}pool_u32.free_slice(values);}
reusable[] var pool_Iterator:Iterator[>..]=[];
fn copyOwned(values:const Iterator[:])->Iterator[:] {if values.len==0 {return default<Iterator[:]>();}let run=pool_Iterator.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Iterator[:]) {if values.len==0 {return;}pool_Iterator.free_slice(values);}
reusable[] var pool_Constructor:Constructor[>..]=[];
fn copyOwned(values:const Constructor[:])->Constructor[:] {if values.len==0 {return default<Constructor[:]>();}let run=pool_Constructor.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Constructor[:]) {if values.len==0 {return;}pool_Constructor.free_slice(values);}
reusable[] var pool_Index:Index[>..]=[];
fn copyOwned(values:const Index[:])->Index[:] {if values.len==0 {return default<Index[:]>();}let run=pool_Index.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Index[:]) {if values.len==0 {return;}pool_Index.free_slice(values);}
reusable[] var pool_OperationBinding:OperationBinding[>..]=[];
fn copyOwned(values:const OperationBinding[:])->OperationBinding[:] {if values.len==0 {return default<OperationBinding[:]>();}let run=pool_OperationBinding.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const OperationBinding[:]) {if values.len==0 {return;}pool_OperationBinding.free_slice(values);}
reusable[] var pool_Selection:Selection[>..]=[];
fn copyOwned(values:const Selection[:])->Selection[:] {if values.len==0 {return default<Selection[:]>();}let run=pool_Selection.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const Selection[:]) {if values.len==0 {return;}pool_Selection.free_slice(values);}
reusable[] var pool_blot_check_numeric_proof_terms__Term:blot_check_numeric_proof_terms::Term[>..]=[];
fn copyOwned(values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {if values.len==0 {return default<blot_check_numeric_proof_terms::Term[:]>();}let run=pool_blot_check_numeric_proof_terms__Term.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_numeric_proof_terms::Term[:]) {if values.len==0 {return;}pool_blot_check_numeric_proof_terms__Term.free_slice(values);}
reusable[] var pool_blot_check_numeric_proof_bodies__Debit:blot_check_numeric_proof_bodies::Debit[>..]=[];
fn copyOwned(values:const blot_check_numeric_proof_bodies::Debit[:])->blot_check_numeric_proof_bodies::Debit[:] {if values.len==0 {return default<blot_check_numeric_proof_bodies::Debit[:]>();}let run=pool_blot_check_numeric_proof_bodies__Debit.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_numeric_proof_bodies::Debit[:]) {if values.len==0 {return;}pool_blot_check_numeric_proof_bodies__Debit.free_slice(values);}
reusable[] var pool_blot_check_numeric_proof_bodies__Introduction:blot_check_numeric_proof_bodies::Introduction[>..]=[];
fn copyOwned(values:const blot_check_numeric_proof_bodies::Introduction[:])->blot_check_numeric_proof_bodies::Introduction[:] {if values.len==0 {return default<blot_check_numeric_proof_bodies::Introduction[:]>();}let run=pool_blot_check_numeric_proof_bodies__Introduction.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_numeric_proof_bodies::Introduction[:]) {if values.len==0 {return;}pool_blot_check_numeric_proof_bodies__Introduction.free_slice(values);}
reusable[] var pool_blot_check_numeric_proof_bodies__Parameter:blot_check_numeric_proof_bodies::Parameter[>..]=[];
fn copyOwned(values:const blot_check_numeric_proof_bodies::Parameter[:])->blot_check_numeric_proof_bodies::Parameter[:] {if values.len==0 {return default<blot_check_numeric_proof_bodies::Parameter[:]>();}let run=pool_blot_check_numeric_proof_bodies__Parameter.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_numeric_proof_bodies::Parameter[:]) {if values.len==0 {return;}pool_blot_check_numeric_proof_bodies__Parameter.free_slice(values);}
reusable[] var pool_blot_check_numeric_proof_bodies__Use:blot_check_numeric_proof_bodies::Use[>..]=[];
fn copyOwned(values:const blot_check_numeric_proof_bodies::Use[:])->blot_check_numeric_proof_bodies::Use[:] {if values.len==0 {return default<blot_check_numeric_proof_bodies::Use[:]>();}let run=pool_blot_check_numeric_proof_bodies__Use.alloc_slice(values.len);for value,index in values {run[index]=value;}return run;}
fn releaseOwned(values:const blot_check_numeric_proof_bodies::Use[:]) {if values.len==0 {return;}pool_blot_check_numeric_proof_bodies__Use.free_slice(values);}
fn deinit(self_:Owner&) {let at=ownerIndex(self_);
releaseOwned(self_.tables.usage_loans);
releaseOwned(self_.tables.rank_implementations);
releaseOwned(self_.tables.generative_bindings);
releaseOwned(self_.tables.dictionary_selections);
releaseOwned(self_.tables.dictionary_uses);
releaseOwned(self_.tables.computations);
releaseOwned(self_.tables.request_loops);
releaseOwned(self_.tables.request_arms);
releaseOwned(self_.tables.request_controls);
releaseOwned(self_.tables.reflections);
releaseOwned(self_.tables.effect_scopes);
releaseOwned(self_.tables.effect_runners);
releaseOwned(self_.tables.provider_blocks);
releaseOwned(self_.tables.resolver_blocks);
releaseOwned(self_.tables.resolver_ops);
releaseOwned(self_.tables.resolver_joins);
releaseOwned(self_.tables.resolver_completions);
releaseOwned(self_.tables.resolver_loops);
releaseOwned(self_.tables.operation_uses);
releaseOwned(self_.tables.statement_arms);
releaseOwned(self_.extra);
releaseOwned(self_.origins);
releaseOwned(self_.binding_origins);
releaseOwned(self_.dependencies);
releaseOwned(self_.iterators);
releaseOwned(self_.constructors);
releaseOwned(self_.indices);
releaseOwned(self_.operation_bindings);
releaseOwned(self_.selections);
releaseOwned(self_.proof_parameters);
releaseOwned(self_.numeric_body.debits);
releaseOwned(self_.numeric_body.operands);
releaseOwned(self_.numeric_body.introductions);
releaseOwned(self_.numeric_body.parameters);
releaseOwned(self_.numeric_body.uses);
self_=Owner{..};owners.free(at);}
fn clone(source:const Owner&)->Owner?,Error {assert(source.live);let at=owners.alloc_index(Owner{live:true, ..});let result:Owner& =owners[at];result.slot=(at+1) as u32;
result.tables.usage_loans=copyOwned(source.tables.usage_loans);
result.tables.rank_implementations=copyOwned(source.tables.rank_implementations);
result.tables.generative_bindings=copyOwned(source.tables.generative_bindings);
result.tables.dictionary_selections=copyOwned(source.tables.dictionary_selections);
result.tables.dictionary_uses=copyOwned(source.tables.dictionary_uses);
result.tables.computations=copyOwned(source.tables.computations);
result.tables.request_loops=copyOwned(source.tables.request_loops);
result.tables.request_arms=copyOwned(source.tables.request_arms);
result.tables.request_controls=copyOwned(source.tables.request_controls);
result.tables.reflections=copyOwned(source.tables.reflections);
result.tables.effect_scopes=copyOwned(source.tables.effect_scopes);
result.tables.effect_runners=copyOwned(source.tables.effect_runners);
result.tables.provider_blocks=copyOwned(source.tables.provider_blocks);
result.tables.resolver_blocks=copyOwned(source.tables.resolver_blocks);
result.tables.resolver_ops=copyOwned(source.tables.resolver_ops);
result.tables.resolver_joins=copyOwned(source.tables.resolver_joins);
result.tables.resolver_completions=copyOwned(source.tables.resolver_completions);
result.tables.resolver_loops=copyOwned(source.tables.resolver_loops);
result.tables.operation_uses=copyOwned(source.tables.operation_uses);
result.tables.statement_arms=copyOwned(source.tables.statement_arms);
result.extra=copyOwned(source.extra);
result.origins=copyOwned(source.origins);
result.binding_origins=copyOwned(source.binding_origins);
result.dependencies=copyOwned(source.dependencies);
result.iterators=copyOwned(source.iterators);
result.constructors=copyOwned(source.constructors);
result.indices=copyOwned(source.indices);
result.operation_bindings=copyOwned(source.operation_bindings);
result.selections=copyOwned(source.selections);
result.proof_parameters=copyOwned(source.proof_parameters);
result.numeric_body.debits=copyOwned(source.numeric_body.debits);
result.numeric_body.operands=copyOwned(source.numeric_body.operands);
result.numeric_body.introductions=copyOwned(source.numeric_body.introductions);
result.numeric_body.parameters=copyOwned(source.numeric_body.parameters);
result.numeric_body.uses=copyOwned(source.numeric_body.uses);
result.proof_debit=source.proof_debit;return result,blot_error::Error.none;}
fn list(self_:const Owner&,span:List)->const u32[:] {return self_.extra[span.start..span.start+span.len];}
fn bytes(self_:const Owner&)->i64 {var result:i64=626;
result+=self_.tables.usage_loans.len*25;
result+=self_.tables.rank_implementations.len*12;
result+=self_.tables.generative_bindings.len*16;
result+=self_.tables.dictionary_selections.len*45;
result+=self_.tables.dictionary_uses.len*24;
result+=self_.tables.computations.len*16;
result+=self_.tables.request_loops.len*64;
result+=self_.tables.request_arms.len*44;
result+=self_.tables.request_controls.len*25;
result+=self_.tables.reflections.len*25;
result+=self_.tables.effect_scopes.len*24;
result+=self_.tables.effect_runners.len*57;
result+=self_.tables.provider_blocks.len*24;
result+=self_.tables.resolver_blocks.len*20;
result+=self_.tables.resolver_ops.len*49;
result+=self_.tables.resolver_joins.len*16;
result+=self_.tables.resolver_completions.len*24;
result+=self_.tables.resolver_loops.len*48;
result+=self_.tables.operation_uses.len*41;
result+=self_.tables.statement_arms.len*4;
result+=self_.extra.len*4;
result+=self_.origins.len*4;
result+=self_.binding_origins.len*4;
result+=self_.dependencies.len*4;
result+=self_.iterators.len*8;
result+=self_.constructors.len*12;
result+=self_.indices.len*12;
result+=self_.operation_bindings.len*8;
result+=self_.selections.len*57;
result+=self_.proof_parameters.len*4;
result+=self_.numeric_body.debits.len*64;
result+=self_.numeric_body.operands.len*10;
result+=self_.numeric_body.introductions.len*25;
result+=self_.numeric_body.parameters.len*17;
result+=self_.numeric_body.uses.len*21;
return result;}
fn registeredField(value:blot_check_numeric_proof_bodies::Introduction,name:const u8[:])->bool {return name=="source" || name=="owner" || name=="arguments" || name=="proposition";}
fn mapRecord<M>(value:blot_check_numeric_proof_bodies::Introduction,mapper:M&)->blot_check_numeric_proof_bodies::Introduction,Error {const for <N,A> in fields<blot_check_numeric_proof_bodies::Introduction> {if !registeredField(value,N) {return default<blot_check_numeric_proof_bodies::Introduction>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Introduction>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_node(value.owner);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Introduction>(),error;}result.owner=mapped;}
{let mapped,error=mapper.map_nodes_pair(value.arguments);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Introduction>(),error;}result.arguments=mapped;}
{let mapped,error=mapper.map_proposition(value.proposition);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Introduction>(),error;}result.proposition=mapped;}
return result,blot_error::Error.none;}
fn registeredField(value:blot_check_numeric_proof_bodies::Parameter,name:const u8[:])->bool {return name=="binding" || name=="contract" || name=="proposition";}
fn mapRecord<M>(value:blot_check_numeric_proof_bodies::Parameter,mapper:M&)->blot_check_numeric_proof_bodies::Parameter,Error {const for <N,A> in fields<blot_check_numeric_proof_bodies::Parameter> {if !registeredField(value,N) {return default<blot_check_numeric_proof_bodies::Parameter>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_binding(value.binding);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Parameter>(),error;}result.binding=mapped;}
{let mapped,error=mapper.map_proposition(value.proposition);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Parameter>(),error;}result.proposition=mapped;}
return result,blot_error::Error.none;}
fn registeredField(value:blot_check_numeric_proof_bodies::Use,name:const u8[:])->bool {return name=="source" || name=="callee" || name=="witness" || name=="proposition";}
fn mapRecord<M>(value:blot_check_numeric_proof_bodies::Use,mapper:M&)->blot_check_numeric_proof_bodies::Use,Error {const for <N,A> in fields<blot_check_numeric_proof_bodies::Use> {if !registeredField(value,N) {return default<blot_check_numeric_proof_bodies::Use>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Use>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_binding(value.callee);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Use>(),error;}result.callee=mapped;}
{let mapped,error=mapper.map_node(value.witness);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Use>(),error;}result.witness=mapped;}
{let mapped,error=mapper.map_proposition(value.proposition);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_bodies::Use>(),error;}result.proposition=mapped;}
return result,blot_error::Error.none;}
fn registeredField(value:blot_check_check::UsageLoan,name:const u8[:])->bool {return name=="source" || name=="callback" || name=="parameter" || name=="region" || name=="mutable" || name=="acquire" || name=="release";}
fn mapRecord<M>(value:blot_check_check::UsageLoan,mapper:M&)->blot_check_check::UsageLoan,Error {const for <N,A> in fields<blot_check_check::UsageLoan> {if !registeredField(value,N) {return default<blot_check_check::UsageLoan>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_node(value.callback);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.callback=mapped;}
{let mapped,error=mapper.map_node(value.parameter);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.parameter=mapped;}
{let mapped,error=mapper.map_ty(value.region);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.region=mapped;}
{let mapped,error=mapper.map_node(value.acquire);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.acquire=mapped;}
{let mapped,error=mapper.map_node(value.release);if error!=blot_error::Error.none {return default<blot_check_check::UsageLoan>(),error;}result.release=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::UsageLoan)->u32 {return value.source;}
fn registeredField(value:blot_check_generative_schemes::Binder,name:const u8[:])->bool {return name=="owner" || name=="origin" || name=="arrow" || name=="selection";}
fn mapRecord<M>(value:blot_check_generative_schemes::Binder,mapper:M&)->blot_check_generative_schemes::Binder,Error {const for <N,A> in fields<blot_check_generative_schemes::Binder> {if !registeredField(value,N) {return default<blot_check_generative_schemes::Binder>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.owner);if error!=blot_error::Error.none {return default<blot_check_generative_schemes::Binder>(),error;}result.owner=mapped;}
{let mapped,error=mapper.map_node(value.origin);if error!=blot_error::Error.none {return default<blot_check_generative_schemes::Binder>(),error;}result.origin=mapped;}
{let mapped,error=mapper.map_ty(value.arrow);if error!=blot_error::Error.none {return default<blot_check_generative_schemes::Binder>(),error;}result.arrow=mapped;}
{let mapped,error=mapper.map_ty(value.selection);if error!=blot_error::Error.none {return default<blot_check_generative_schemes::Binder>(),error;}result.selection=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_generative_schemes::Binder)->u32 {return value.owner;}
fn registeredField(value:blot_check_check::RankImplementation,name:const u8[:])->bool {return name=="scope" || name=="quantified" || name=="node";}
fn mapRecord<M>(value:blot_check_check::RankImplementation,mapper:M&)->blot_check_check::RankImplementation,Error {const for <N,A> in fields<blot_check_check::RankImplementation> {if !registeredField(value,N) {return default<blot_check_check::RankImplementation>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_scope(value.scope);if error!=blot_error::Error.none {return default<blot_check_check::RankImplementation>(),error;}result.scope=mapped;}
{let mapped,error=mapper.map_ty(value.quantified);if error!=blot_error::Error.none {return default<blot_check_check::RankImplementation>(),error;}result.quantified=mapped;}
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::RankImplementation>(),error;}result.node=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::RankImplementation)->u32 {return value.node;}
fn registeredField(value:blot_check_check::DictionarySelection,name:const u8[:])->bool {return name=="source" || name=="quantifier" || name=="goal" || name=="proof";}
fn mapRecord<M>(value:blot_check_check::DictionarySelection,mapper:M&)->blot_check_check::DictionarySelection,Error {const for <N,A> in fields<blot_check_check::DictionarySelection> {if !registeredField(value,N) {return default<blot_check_check::DictionarySelection>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_check::DictionarySelection>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_ty(value.quantifier);if error!=blot_error::Error.none {return default<blot_check_check::DictionarySelection>(),error;}result.quantifier=mapped;}
{let mapped,error=mapper.map_goal(value.goal);if error!=blot_error::Error.none {return default<blot_check_check::DictionarySelection>(),error;}result.goal=mapped;}
{let mapped,error=mapper.map_proof(value.proof);if error!=blot_error::Error.none {return default<blot_check_check::DictionarySelection>(),error;}result.proof=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::DictionarySelection)->u32 {return value.source;}
fn registeredField(value:blot_check_check::DictionaryUse,name:const u8[:])->bool {return name=="source" || name=="opening" || name=="introduction" || name=="quantifier" || name=="goal" || name=="member";}
fn mapRecord<M>(value:blot_check_check::DictionaryUse,mapper:M&)->blot_check_check::DictionaryUse,Error {const for <N,A> in fields<blot_check_check::DictionaryUse> {if !registeredField(value,N) {return default<blot_check_check::DictionaryUse>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryUse>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_binding(value.opening);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryUse>(),error;}result.opening=mapped;}
{let mapped,error=mapper.map_node(value.introduction);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryUse>(),error;}result.introduction=mapped;}
{let mapped,error=mapper.map_ty(value.quantifier);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryUse>(),error;}result.quantifier=mapped;}
{let mapped,error=mapper.map_goal(value.goal);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryUse>(),error;}result.goal=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::DictionaryUse)->u32 {return value.source;}
fn registeredField(value:blot_check_check::DictionaryGiven,name:const u8[:])->bool {return name=="opening" || name=="introduction" || name=="quantifier" || name=="goal" || name=="arguments" || name=="member_types";}
fn mapRecord<M>(value:blot_check_check::DictionaryGiven,mapper:M&)->blot_check_check::DictionaryGiven,Error {const for <N,A> in fields<blot_check_check::DictionaryGiven> {if !registeredField(value,N) {return default<blot_check_check::DictionaryGiven>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_binding(value.opening);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.opening=mapped;}
{let mapped,error=mapper.map_node(value.introduction);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.introduction=mapped;}
{let mapped,error=mapper.map_ty(value.quantifier);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.quantifier=mapped;}
{let mapped,error=mapper.map_goal(value.goal);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.goal=mapped;}
{let mapped,error=mapper.map_types(value.arguments);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.arguments=mapped;}
{let mapped,error=mapper.map_types(value.member_types);if error!=blot_error::Error.none {return default<blot_check_check::DictionaryGiven>(),error;}result.member_types=mapped;}
return result,blot_error::Error.none;}
fn registeredField(value:blot_check_check::Computation,name:const u8[:])->bool {return name=="node" || name=="action" || name=="ty" || name=="action_type";}
fn mapRecord<M>(value:blot_check_check::Computation,mapper:M&)->blot_check_check::Computation,Error {const for <N,A> in fields<blot_check_check::Computation> {if !registeredField(value,N) {return default<blot_check_check::Computation>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::Computation>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.action);if error!=blot_error::Error.none {return default<blot_check_check::Computation>(),error;}result.action=mapped;}
{let mapped,error=mapper.map_ty(value.ty);if error!=blot_error::Error.none {return default<blot_check_check::Computation>(),error;}result.ty=mapped;}
{let mapped,error=mapper.map_ty(value.action_type);if error!=blot_error::Error.none {return default<blot_check_check::Computation>(),error;}result.action_type=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::Computation)->u32 {return value.node;}
fn registeredField(value:blot_check_check::RequestLoop,name:const u8[:])->bool {return name=="node" || name=="computation" || name=="value_type" || name=="result_type" || name=="state_type" || name=="action_type" || name=="arms" || name=="completion" || name=="complete_pattern" || name=="complete_suite" || name=="complete_state_bindings" || name=="carried" || name=="return_scope";}
fn mapRecord<M>(value:blot_check_check::RequestLoop,mapper:M&)->blot_check_check::RequestLoop,Error {const for <N,A> in fields<blot_check_check::RequestLoop> {if !registeredField(value,N) {return default<blot_check_check::RequestLoop>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.computation);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.computation=mapped;}
{let mapped,error=mapper.map_ty(value.value_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.value_type=mapped;}
{let mapped,error=mapper.map_ty(value.result_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.result_type=mapped;}
{let mapped,error=mapper.map_ty(value.state_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.state_type=mapped;}
{let mapped,error=mapper.map_ty(value.action_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.action_type=mapped;}
{let mapped,error=mapper.map_request_arms(value.arms);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.arms=mapped;}
{let mapped,error=mapper.map_node(value.completion);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.completion=mapped;}
{let mapped,error=mapper.map_node(value.complete_pattern);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.complete_pattern=mapped;}
{let mapped,error=mapper.map_node(value.complete_suite);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.complete_suite=mapped;}
{let mapped,error=mapper.map_bindings(value.complete_state_bindings);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.complete_state_bindings=mapped;}
{let mapped,error=mapper.map_carries(value.carried);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.carried=mapped;}
{let mapped,error=mapper.map_node(value.return_scope);if error!=blot_error::Error.none {return default<blot_check_check::RequestLoop>(),error;}result.return_scope=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::RequestLoop)->u32 {return value.node;}
fn registeredField(value:blot_check_check::RequestArm,name:const u8[:])->bool {return name=="node" || name=="loop" || name=="operation_source" || name=="operation" || name=="parameter_type" || name=="reply_type" || name=="signature" || name=="pattern" || name=="suite" || name=="state_bindings";}
fn mapRecord<M>(value:blot_check_check::RequestArm,mapper:M&)->blot_check_check::RequestArm,Error {const for <N,A> in fields<blot_check_check::RequestArm> {if !registeredField(value,N) {return default<blot_check_check::RequestArm>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.loop_);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.loop_=mapped;}
{let mapped,error=mapper.map_node(value.operation_source);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.operation_source=mapped;}
{let mapped,error=mapper.map_label(value.operation);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.operation=mapped;}
{let mapped,error=mapper.map_ty(value.parameter_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.parameter_type=mapped;}
{let mapped,error=mapper.map_ty(value.reply_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.reply_type=mapped;}
{let mapped,error=mapper.map_ty(value.signature);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.signature=mapped;}
{let mapped,error=mapper.map_node(value.pattern);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.pattern=mapped;}
{let mapped,error=mapper.map_node(value.suite);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.suite=mapped;}
{let mapped,error=mapper.map_bindings(value.state_bindings);if error!=blot_error::Error.none {return default<blot_check_check::RequestArm>(),error;}result.state_bindings=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::RequestArm)->u32 {return value.node;}
fn registeredField(value:blot_check_check::RequestControl,name:const u8[:])->bool {return name=="node" || name=="loop" || name=="kind" || name=="value_type" || name=="bindings" || name=="target_scope";}
fn mapRecord<M>(value:blot_check_check::RequestControl,mapper:M&)->blot_check_check::RequestControl,Error {const for <N,A> in fields<blot_check_check::RequestControl> {if !registeredField(value,N) {return default<blot_check_check::RequestControl>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::RequestControl>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.loop_);if error!=blot_error::Error.none {return default<blot_check_check::RequestControl>(),error;}result.loop_=mapped;}
{let mapped,error=mapper.map_ty(value.value_type);if error!=blot_error::Error.none {return default<blot_check_check::RequestControl>(),error;}result.value_type=mapped;}
{let mapped,error=mapper.map_bindings(value.bindings);if error!=blot_error::Error.none {return default<blot_check_check::RequestControl>(),error;}result.bindings=mapped;}
{let mapped,error=mapper.map_node(value.target_scope);if error!=blot_error::Error.none {return default<blot_check_check::RequestControl>(),error;}result.target_scope=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::RequestControl)->u32 {return value.node;}
fn registeredField(value:blot_check_check::Reflection,name:const u8[:])->bool {return name=="node" || name=="kind" || name=="left" || name=="right" || name=="binding" || name=="row" || name=="label";}
fn mapRecord<M>(value:blot_check_check::Reflection,mapper:M&)->blot_check_check::Reflection,Error {const for <N,A> in fields<blot_check_check::Reflection> {if !registeredField(value,N) {return default<blot_check_check::Reflection>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.left);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.left=mapped;}
{let mapped,error=mapper.map_node(value.right);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.right=mapped;}
{let mapped,error=mapper.map_binding(value.binding);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.binding=mapped;}
{let mapped,error=mapper.map_row(value.row);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.row=mapped;}
{let mapped,error=mapper.map_label(value.label);if error!=blot_error::Error.none {return default<blot_check_check::Reflection>(),error;}result.label=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::Reflection)->u32 {return value.node;}
fn registeredField(value:blot_check_check::EffectScope,name:const u8[:])->bool {return name=="node" || name=="callback" || name=="parameter" || name=="capability" || name=="result" || name=="body_effects";}
fn mapRecord<M>(value:blot_check_check::EffectScope,mapper:M&)->blot_check_check::EffectScope,Error {const for <N,A> in fields<blot_check_check::EffectScope> {if !registeredField(value,N) {return default<blot_check_check::EffectScope>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.callback);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.callback=mapped;}
{let mapped,error=mapper.map_node(value.parameter);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.parameter=mapped;}
{let mapped,error=mapper.map_ty(value.capability);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.capability=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_row(value.body_effects);if error!=blot_error::Error.none {return default<blot_check_check::EffectScope>(),error;}result.body_effects=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::EffectScope)->u32 {return value.node;}
fn registeredField(value:blot_check_check::EffectRunner,name:const u8[:])->bool {return name=="node" || name=="kind" || name=="read_token" || name=="write_token" || name=="initial" || name=="witness" || name=="implementation" || name=="action" || name=="state_type" || name=="body_result" || name=="result" || name=="implementation_type" || name=="action_type" || name=="body_effects" || name=="outer_effects";}
fn mapRecord<M>(value:blot_check_check::EffectRunner,mapper:M&)->blot_check_check::EffectRunner,Error {const for <N,A> in fields<blot_check_check::EffectRunner> {if !registeredField(value,N) {return default<blot_check_check::EffectRunner>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_ty(value.read_token);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.read_token=mapped;}
{let mapped,error=mapper.map_ty(value.write_token);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.write_token=mapped;}
{let mapped,error=mapper.map_node(value.initial);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.initial=mapped;}
{let mapped,error=mapper.map_node(value.witness);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.witness=mapped;}
{let mapped,error=mapper.map_node(value.implementation);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.implementation=mapped;}
{let mapped,error=mapper.map_node(value.action);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.action=mapped;}
{let mapped,error=mapper.map_ty(value.state_type);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.state_type=mapped;}
{let mapped,error=mapper.map_ty(value.body_result);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.body_result=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_ty(value.implementation_type);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.implementation_type=mapped;}
{let mapped,error=mapper.map_ty(value.action_type);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.action_type=mapped;}
{let mapped,error=mapper.map_row(value.body_effects);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.body_effects=mapped;}
{let mapped,error=mapper.map_row(value.outer_effects);if error!=blot_error::Error.none {return default<blot_check_check::EffectRunner>(),error;}result.outer_effects=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::EffectRunner)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ProviderBlock,name:const u8[:])->bool {return name=="node" || name=="provider" || name=="body_result" || name=="result" || name=="body_effects" || name=="outer_effects";}
fn mapRecord<M>(value:blot_check_check::ProviderBlock,mapper:M&)->blot_check_check::ProviderBlock,Error {const for <N,A> in fields<blot_check_check::ProviderBlock> {if !registeredField(value,N) {return default<blot_check_check::ProviderBlock>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_node(value.provider);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.provider=mapped;}
{let mapped,error=mapper.map_ty(value.body_result);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.body_result=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_row(value.body_effects);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.body_effects=mapped;}
{let mapped,error=mapper.map_row(value.outer_effects);if error!=blot_error::Error.none {return default<blot_check_check::ProviderBlock>(),error;}result.outer_effects=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ProviderBlock)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ResolverBlock,name:const u8[:])->bool {return name=="node" || name=="resolver" || name=="result" || name=="body_effects" || name=="fallthrough";}
fn mapRecord<M>(value:blot_check_check::ResolverBlock,mapper:M&)->blot_check_check::ResolverBlock,Error {const for <N,A> in fields<blot_check_check::ResolverBlock> {if !registeredField(value,N) {return default<blot_check_check::ResolverBlock>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ResolverBlock>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_binding(value.resolver);if error!=blot_error::Error.none {return default<blot_check_check::ResolverBlock>(),error;}result.resolver=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::ResolverBlock>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_row(value.body_effects);if error!=blot_error::Error.none {return default<blot_check_check::ResolverBlock>(),error;}result.body_effects=mapped;}
{let mapped,error=mapper.map_resolver_completions(value.fallthrough);if error!=blot_error::Error.none {return default<blot_check_check::ResolverBlock>(),error;}result.fallthrough=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ResolverBlock)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ResolverOp,name:const u8[:])->bool {return name=="node" || name=="kind" || name=="member" || name=="resolver" || name=="method" || name=="method_type" || name=="payload" || name=="result" || name=="continuation_parameter" || name=="completed_types" || name=="done_constructor" || name=="completion";}
fn mapRecord<M>(value:blot_check_check::ResolverOp,mapper:M&)->blot_check_check::ResolverOp,Error {const for <N,A> in fields<blot_check_check::ResolverOp> {if !registeredField(value,N) {return default<blot_check_check::ResolverOp>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_name(value.member);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.member=mapped;}
{let mapped,error=mapper.map_binding(value.resolver);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.resolver=mapped;}
{let mapped,error=mapper.map_binding(value.method);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.method=mapped;}
{let mapped,error=mapper.map_ty(value.method_type);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.method_type=mapped;}
{let mapped,error=mapper.map_ty(value.payload);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.payload=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_binding(value.continuation_parameter);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.continuation_parameter=mapped;}
{let mapped,error=mapper.map_types(value.completed_types);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.completed_types=mapped;}
{let mapped,error=mapper.map_constructor(value.done_constructor);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.done_constructor=mapped;}
{let mapped,error=mapper.map_resolver_completions(value.completion);if error!=blot_error::Error.none {return default<blot_check_check::ResolverOp>(),error;}result.completion=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ResolverOp)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ResolverJoin,name:const u8[:])->bool {return name=="node" || name=="parameter" || name=="ty" || name=="result";}
fn mapRecord<M>(value:blot_check_check::ResolverJoin,mapper:M&)->blot_check_check::ResolverJoin,Error {const for <N,A> in fields<blot_check_check::ResolverJoin> {if !registeredField(value,N) {return default<blot_check_check::ResolverJoin>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ResolverJoin>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_binding(value.parameter);if error!=blot_error::Error.none {return default<blot_check_check::ResolverJoin>(),error;}result.parameter=mapped;}
{let mapped,error=mapper.map_ty(value.ty);if error!=blot_error::Error.none {return default<blot_check_check::ResolverJoin>(),error;}result.ty=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_check::ResolverJoin>(),error;}result.result=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ResolverJoin)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ResolverCompletion,name:const u8[:])->bool {return name=="node" || name=="bind" || name=="pure" || name=="completed_types" || name=="done_constructor";}
fn mapRecord<M>(value:blot_check_check::ResolverCompletion,mapper:M&)->blot_check_check::ResolverCompletion,Error {const for <N,A> in fields<blot_check_check::ResolverCompletion> {if !registeredField(value,N) {return default<blot_check_check::ResolverCompletion>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ResolverCompletion>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_resolver_ops(value.bind);if error!=blot_error::Error.none {return default<blot_check_check::ResolverCompletion>(),error;}result.bind=mapped;}
{let mapped,error=mapper.map_resolver_ops(value.pure);if error!=blot_error::Error.none {return default<blot_check_check::ResolverCompletion>(),error;}result.pure=mapped;}
{let mapped,error=mapper.map_types(value.completed_types);if error!=blot_error::Error.none {return default<blot_check_check::ResolverCompletion>(),error;}result.completed_types=mapped;}
{let mapped,error=mapper.map_constructor(value.done_constructor);if error!=blot_error::Error.none {return default<blot_check_check::ResolverCompletion>(),error;}result.done_constructor=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ResolverCompletion)->u32 {return value.node;}
fn registeredField(value:blot_check_check::ResolverLoop,name:const u8[:])->bool {return name=="node" || name=="cursor_parameter" || name=="first_binding" || name=="end_binding" || name=="cursor" || name=="step_result" || name=="suffix_result" || name=="iterate" || name=="continued" || name=="finish" || name=="continue_constructor" || name=="done_constructor";}
fn mapRecord<M>(value:blot_check_check::ResolverLoop,mapper:M&)->blot_check_check::ResolverLoop,Error {const for <N,A> in fields<blot_check_check::ResolverLoop> {if !registeredField(value,N) {return default<blot_check_check::ResolverLoop>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_binding(value.cursor_parameter);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.cursor_parameter=mapped;}
{let mapped,error=mapper.map_binding(value.first_binding);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.first_binding=mapped;}
{let mapped,error=mapper.map_binding(value.end_binding);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.end_binding=mapped;}
{let mapped,error=mapper.map_ty(value.cursor);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.cursor=mapped;}
{let mapped,error=mapper.map_ty(value.step_result);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.step_result=mapped;}
{let mapped,error=mapper.map_ty(value.suffix_result);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.suffix_result=mapped;}
{let mapped,error=mapper.map_resolver_ops(value.iterate);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.iterate=mapped;}
{let mapped,error=mapper.map_resolver_ops(value.continued);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.continued=mapped;}
{let mapped,error=mapper.map_resolver_completions(value.finish);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.finish=mapped;}
{let mapped,error=mapper.map_constructor(value.continue_constructor);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.continue_constructor=mapped;}
{let mapped,error=mapper.map_constructor(value.done_constructor);if error!=blot_error::Error.none {return default<blot_check_check::ResolverLoop>(),error;}result.done_constructor=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::ResolverLoop)->u32 {return value.node;}
fn registeredField(value:blot_check_check::StatementArm,name:const u8[:])->bool {return name=="node";}
fn mapRecord<M>(value:blot_check_check::StatementArm,mapper:M&)->blot_check_check::StatementArm,Error {const for <N,A> in fields<blot_check_check::StatementArm> {if !registeredField(value,N) {return default<blot_check_check::StatementArm>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::StatementArm>(),error;}result.node=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::StatementArm)->u32 {return value.node;}
fn registeredField(value:blot_check_check::OperationUse,name:const u8[:])->bool {return name=="node" || name=="template" || name=="arguments" || name=="signature" || name=="instance" || name=="capability" || name=="capability_binding" || name=="call" || name=="operand";}
fn mapRecord<M>(value:blot_check_check::OperationUse,mapper:M&)->blot_check_check::OperationUse,Error {const for <N,A> in fields<blot_check_check::OperationUse> {if !registeredField(value,N) {return default<blot_check_check::OperationUse>(),blot_error::Error.dependency_limit;}}var result=value;
{let mapped,error=mapper.map_node(value.node);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.node=mapped;}
{let mapped,error=mapper.map_template(value.template);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.template=mapped;}
{let mapped,error=mapper.map_types(value.arguments);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.arguments=mapped;}
{let mapped,error=mapper.map_ty(value.signature);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.signature=mapped;}
{let mapped,error=mapper.map_instance(value.instance);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.instance=mapped;}
{let mapped,error=mapper.map_node(value.capability);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.capability=mapped;}
{let mapped,error=mapper.map_binding(value.capability_binding);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.capability_binding=mapped;}
{let mapped,error=mapper.map_node(value.operand);if error!=blot_error::Error.none {return default<blot_check_check::OperationUse>(),error;}result.operand=mapped;}
return result,blot_error::Error.none;}
fn source(value:blot_check_check::OperationUse)->u32 {return value.node;}
fn mapPredicate<M>(value:blot_check_types::Obligation,mapper:M&)->blot_check_types::Obligation,Error {
 var result=value;
{let mapped,error=mapper.map_ty(value.ty);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.ty=mapped;}
{let mapped,error=mapper.map_ty(value.other);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.other=mapped;}
{let mapped,error=mapper.map_ty(value.result);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.result=mapped;}
{let mapped,error=mapper.map_ty(value.signature);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.signature=mapped;}
{let mapped,error=mapper.map_node(value.source);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.source=mapped;}
{let mapped,error=mapper.map_name(value.name);if error!=blot_error::Error.none {return default<blot_check_types::Obligation>(),error;}result.name=mapped;}
match value.kind {
 contract=>{let mapped,error=mapper.map_contract_identity(value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=mapped;},
 effect_operation=>{let mapped,error=mapper.map_operation_identity(value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=mapped;},
 callee_use=>{let mapped,error=mapper.map_callee_identity(value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=mapped;},_=>{}
 }return result,blot_error::Error.none;
}
fn contains(ids:const u32[:],id:u32)->bool {for value in ids {if value==id {return true;}}return false;}
fn nodePosition(ids:const u32[:],id:u32)->u32,Error {if id==0 {return 0,blot_error::Error.none;}for value,index in ids {if value==id {return (index+1) as u32,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_usage_loans(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.usage_loans.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.usage_loans {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_rank_implementations(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.rank_implementations.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.rank_implementations {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_generative_bindings(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.generative_bindings.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.generative_bindings {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_dictionary_selections(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.dictionary_selections.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.dictionary_selections {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_dictionary_uses(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.dictionary_uses.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.dictionary_uses {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_computations(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.computations.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.computations {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_request_loops(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.request_loops.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.request_loops {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_request_arms(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.request_arms.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.request_arms {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_request_controls(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.request_controls.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.request_controls {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_reflections(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.reflections.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.reflections {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_effect_scopes(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.effect_scopes.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.effect_scopes {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_effect_runners(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.effect_runners.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.effect_runners {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_provider_blocks(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.provider_blocks.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.provider_blocks {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_resolver_blocks(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.resolver_blocks.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.resolver_blocks {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_resolver_ops(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.resolver_ops.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.resolver_ops {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_resolver_joins(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.resolver_joins.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.resolver_joins {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_resolver_completions(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.resolver_completions.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.resolver_completions {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_resolver_loops(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.resolver_loops.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.resolver_loops {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_operation_uses(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.operation_uses.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.operation_uses {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
fn index_statement_arms(checked:const blot_check_check::Checked&,ids:const u32[:],index:u32)->u32,Error {if index==0 {return 0,blot_error::Error.none;}if index>checked.statement_arms.len {return 0,blot_error::Error.dependency_limit;}var selected:u32=0;for entry,ordinal in checked.statement_arms {if !contains(ids,source(entry)) {continue;}selected+=1;if ordinal==index-1 {return selected,blot_error::Error.none;}}return 0,blot_error::Error.dependency_limit;}
struct Capture {checked:const blot_check_check::Checked&,ids:const u32[:],extra:u32[>..<]&,selections:Selection[>..<]&,source:u32=0}
fn map_node(self_:Capture&,value:u32)->u32,Error {return nodePosition(self_.ids,value);}
fn map_resolver_ops(self_:Capture&,value:u32)->u32,Error {return index_resolver_ops(self_.checked,self_.ids,value);}
fn map_resolver_completions(self_:Capture&,value:u32)->u32,Error {return index_resolver_completions(self_.checked,self_.ids,value);}
fn captureList(self_:Capture&,value:List,arms:bool)->List,Error {let start=self_.extra.len;let items=self_.checked.types.list(value);if items.len>4096-start {return List{..},blot_error::Error.dependency_limit;}for item in items {var mapped=item;if arms {let result,error=index_request_arms(self_.checked,self_.ids,item+1);if error!=blot_error::Error.none {return List{..},error;}mapped=result;}self_.extra.push(mapped);}return List{start as u32,value.len, ..},blot_error::Error.none;}
fn map_types(self_:Capture&,value:List)->List,Error {return captureList(self_,value,false);}
fn map_bindings(self_:Capture&,value:List)->List,Error {return captureList(self_,value,false);}
fn map_request_arms(self_:Capture&,value:List)->List,Error {return captureList(self_,value,true);}
fn map_carries(self_:Capture&,value:List)->List,Error {if value.len==0 {return List{..},blot_error::Error.none;}if value.start>=self_.checked.loop_carries.len {return List{..},blot_error::Error.dependency_limit;}let node=self_.checked.loop_carries[value.start].node;if value!=self_.checked.loop_ranges[node] {return List{..},blot_error::Error.dependency_limit;}let position,error=nodePosition(self_.ids,node);return List{position,value.len, ..},error;}
recursive fn map_proof(self_:Capture&,value:Proof)->Proof,Error {match value {
 given payload=>{if payload.value.goal>=self_.checked.types.quantifierGoals(payload.value.quantifier).len {return default<Proof>(),blot_error::Error.dependency_limit;}let mapped,error=mapRecord(payload.value,self_);return blot_check_check::DictionaryProof.given{value:mapped, ..},error;},
 selected payload=>{if payload.value>=self_.checked.selected_proofs.len || self_.selections.len>=4096 {return default<Proof>(),blot_error::Error.dependency_limit;}let old=self_.checked.selected_proofs[payload.value];var predicate=old.predicate;let implementation=old.kind==blot_reuse_principal_interface::SelectedProofKind.implementation;if implementation {predicate=blot_check_types::Obligation{ ty:0, kind:blot_check_types::ObligationKind.contract, source:self_.source, identity:old.contract, .. };}predicate.source=self_.source;if predicate.qualification_span.present || predicate.qualification_unit!=0 {return default<Proof>(),blot_error::Error.dependency_limit;}if predicate.kind!=blot_check_types::ObligationKind.contract && predicate.kind!=blot_check_types::ObligationKind.effect_operation && predicate.kind!=blot_check_types::ObligationKind.callee_use && (predicate.identity.unit!=0 || predicate.identity.decl!=0) {return default<Proof>(),blot_error::Error.dependency_limit;}let saved,error=mapPredicate(predicate,self_);if error!=blot_error::Error.none {return default<Proof>(),error;}var arguments=List{..};if implementation {let mapped,error=self_.map_types(old.arguments);if error!=blot_error::Error.none {return default<Proof>(),error;}arguments=mapped;}let slot=self_.selections.len as u32;self_.selections.push(Selection{saved,arguments,implementation, ..});return blot_check_check::DictionaryProof.selected{value:slot, ..},blot_error::Error.none;},
}}
fn map_binding(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_ty(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_row(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_label(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_name(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_instance(self_:Capture&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_scope(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_constructor(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_template(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_goal(self_:Capture&,value:u32)->u32,Error {return value,blot_error::Error.none;}
fn map_contract_identity(self_:Capture&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_operation_identity(self_:Capture&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_callee_identity(self_:Capture&,value:Identity)->Identity,Error {return value,blot_error::Error.none;}
fn map_nodes_pair(self_:Capture&,value:u32[2])->u32[2],Error {return value,blot_error::Error.none;}
fn map_proposition(self_:Capture&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,blot_error::Error.none;}
struct Visitor<M> {owner:Owner&,mapper:M&}
fn map_types<M>(self_:Visitor<M>&,value:List)->List,Error {for index in value.len {let at=value.start+index;let mapped,error=self_.mapper.map_ty(self_.owner.extra[at]);if error!=blot_error::Error.none {return List{..},error;}self_.owner.extra[at]=mapped;}return value,blot_error::Error.none;}
fn map_bindings<M>(self_:Visitor<M>&,value:List)->List,Error {for index in value.len {let at=value.start+index;let mapped,error=self_.mapper.map_binding(self_.owner.extra[at]);if error!=blot_error::Error.none {return List{..},error;}self_.owner.extra[at]=mapped;}return value,blot_error::Error.none;}
fn map_instance<M>(self_:Visitor<M>&,value:Identity)->Identity,Error {if value.unit==0 && value.decl!=0 {let mapped,error=self_.mapper.map_ty(value.decl);return Identity{0,mapped, ..},error;}return self_.mapper.map_instance(value);}
fn map_proposition<M>(self_:Visitor<M>&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {return value,blot_error::Error.none;}
fn map_nodes_pair<M>(self_:Visitor<M>&,value:u32[2])->u32[2],Error {var result=value;for item,index in value {let mapped,error=self_.mapper.map_node(item);if error!=blot_error::Error.none {return result,error;}result[index]=mapped;}return result,blot_error::Error.none;}
recursive fn map_proof<M>(self_:Visitor<M>&,value:Proof)->Proof,Error {match value {given payload=>{let mapped,error=mapRecord(payload.value,self_);return blot_check_check::DictionaryProof.given{value:mapped, ..},error;},selected=>{return self_.mapper.map_proof(value);}}}
fn map_node<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_node(value);}
fn map_binding<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_binding(value);}
fn map_ty<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_ty(value);}
fn map_row<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_row(value);}
fn map_label<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_label(value);}
fn map_name<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_name(value);}
fn map_scope<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_scope(value);}
fn map_constructor<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_constructor(value);}
fn map_template<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_template(value);}
fn map_goal<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_goal(value);}
fn map_contract_identity<M>(self_:Visitor<M>&,value:Identity)->Identity,Error {return self_.mapper.map_contract_identity(value);}
fn map_operation_identity<M>(self_:Visitor<M>&,value:Identity)->Identity,Error {return self_.mapper.map_operation_identity(value);}
fn map_callee_identity<M>(self_:Visitor<M>&,value:Identity)->Identity,Error {return self_.mapper.map_callee_identity(value);}
fn map_request_arms<M>(self_:Visitor<M>&,value:List)->List,Error {return self_.mapper.map_request_arms(value);}
fn map_resolver_ops<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_resolver_ops(value);}
fn map_resolver_completions<M>(self_:Visitor<M>&,value:u32)->u32,Error {return self_.mapper.map_resolver_completions(value);}
fn map_carries<M>(self_:Visitor<M>&,value:List)->List,Error {return self_.mapper.map_carries(value);}
fn transform<M>(self_:Owner&,mapper:M&)->Error {var visitor=Visitor<M>{self_,mapper, ..};
for entry,index in self_.tables.usage_loans {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.usage_loans[index]=mapped;}
for entry,index in self_.tables.rank_implementations {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.rank_implementations[index]=mapped;}
for entry,index in self_.tables.generative_bindings {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.generative_bindings[index]=mapped;}
for entry,index in self_.tables.dictionary_selections {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.dictionary_selections[index]=mapped;}
for entry,index in self_.tables.dictionary_uses {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.dictionary_uses[index]=mapped;}
for entry,index in self_.tables.computations {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.computations[index]=mapped;}
for entry,index in self_.tables.request_loops {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.request_loops[index]=mapped;}
for entry,index in self_.tables.request_arms {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.request_arms[index]=mapped;}
for entry,index in self_.tables.request_controls {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.request_controls[index]=mapped;}
for entry,index in self_.tables.reflections {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.reflections[index]=mapped;}
for entry,index in self_.tables.effect_scopes {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.effect_scopes[index]=mapped;}
for entry,index in self_.tables.effect_runners {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.effect_runners[index]=mapped;}
for entry,index in self_.tables.provider_blocks {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.provider_blocks[index]=mapped;}
for entry,index in self_.tables.resolver_blocks {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.resolver_blocks[index]=mapped;}
for entry,index in self_.tables.resolver_ops {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.resolver_ops[index]=mapped;}
for entry,index in self_.tables.resolver_joins {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.resolver_joins[index]=mapped;}
for entry,index in self_.tables.resolver_completions {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.resolver_completions[index]=mapped;}
for entry,index in self_.tables.resolver_loops {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.resolver_loops[index]=mapped;}
for entry,index in self_.tables.operation_uses {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.operation_uses[index]=mapped;}
for entry,index in self_.tables.statement_arms {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}self_.tables.statement_arms[index]=mapped;}
for operand,index in self_.numeric_body.operands {if operand.tag!=blot_check_numeric_proof_terms::Tag.version {continue;}var mapped=operand.a;if operand.b==1 {let value,error=mapper.map_binding(operand.a);if error!=blot_error::Error.none {return error;}mapped=value;}else if operand.b==2 {let value,error=mapper.map_node(operand.a);if error!=blot_error::Error.none {return error;}mapped=value;}else {return blot_error::Error.dependency_limit;}let first:const blot_check_numeric_proof_terms::Term& =self_.numeric_body.operands[0];let at=pool_blot_check_numeric_proof_terms__Term.index_of(first);pool_blot_check_numeric_proof_terms__Term[at+index].a=mapped;}
for entry,index in self_.numeric_body.introductions {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}let first:const blot_check_numeric_proof_bodies::Introduction& =self_.numeric_body.introductions[0];let at=pool_blot_check_numeric_proof_bodies__Introduction.index_of(first);pool_blot_check_numeric_proof_bodies__Introduction[at+index]=mapped;}
for entry,index in self_.numeric_body.parameters {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}let first:const blot_check_numeric_proof_bodies::Parameter& =self_.numeric_body.parameters[0];let at=pool_blot_check_numeric_proof_bodies__Parameter.index_of(first);pool_blot_check_numeric_proof_bodies__Parameter[at+index]=mapped;}
for entry,index in self_.numeric_body.uses {let mapped,error=mapRecord(entry,visitor);if error!=blot_error::Error.none {return error;}let first:const blot_check_numeric_proof_bodies::Use& =self_.numeric_body.uses[0];let at=pool_blot_check_numeric_proof_bodies__Use.index_of(first);pool_blot_check_numeric_proof_bodies__Use[at+index]=mapped;}
for binding,index in self_.proof_parameters {let mapped,error=mapper.map_binding(binding);if error!=blot_error::Error.none {return error;}self_.proof_parameters[index]=mapped;}for selection,index in self_.selections {let predicate,error=mapPredicate(selection.predicate,visitor);if error!=blot_error::Error.none {return error;}let arguments,error=visitor.map_types(selection.arguments);if error!=blot_error::Error.none {return error;}self_.selections[index].predicate=predicate;self_.selections[index].arguments=arguments;}return blot_error::Error.none;}
fn capture(checked:const blot_check_check::Checked&,ids:const u32[:])->Owner?,Error {
 if ids.len==0 {return null,blot_error::Error.none;}var count:i64=0;
for entry in checked.usage_loans {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.rank_implementations {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.generative_bindings {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.dictionary_selections {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.dictionary_uses {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.computations {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.request_loops {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.request_arms {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.request_controls {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.reflections {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.effect_scopes {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.effect_runners {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.provider_blocks {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.resolver_blocks {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.resolver_ops {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.resolver_joins {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.resolver_completions {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.resolver_loops {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.operation_uses {if contains(ids,source(entry)) {count+=1;}}
for entry in checked.statement_arms {if contains(ids,source(entry)) {count+=1;}}
for id in ids {if id<checked.iterator_bodies.len && checked.iterator_bodies[id]!=0 {count+=1;}}
 let global=checked.resolved[ids[0]];
 if count==0 {for node in checked.types.nodes.items {if node.tag==blot_check_types::Tag.scoped && node.b==checked.unit && contains(ids,node.c) {count=1;break;}}}
 for entry in checked.proof_bodies.introductions {if contains(ids,entry.source) {count+=1;}}
 for entry in checked.proof_bodies.uses {if contains(ids,entry.source) {count+=1;}}
 for entry in checked.proof_bodies.parameters {if entry.contract==global {count+=1;}}
 for contract in checked.proof_contracts {if contract.binding==global {count+=1;}}
 for debit in checked.proof_bodies.debits {if debit.binding==global {count+=1;}}
 if count==0 {return null,blot_error::Error.none;}if count>4096 {return null,blot_error::Error.dependency_limit;}
 let at=owners.alloc_index(Owner{live:true, ..});let owner:Owner& =owners[at];owner.slot=(at+1) as u32;let error=captureInto(owner,checked,ids,global);if error!=blot_error::Error.none {owner.deinit();return null,error;}return owner,blot_error::Error.none;
}
fn captureInto(owner:Owner&,checked:const blot_check_check::Checked&,ids:const u32[:],global:u32)->Error {
 var extra:u32[>..<]=[];var selections:Selection[>..<]=[];var mapper=Capture{checked,ids,extra,selections, ..};
{var entries:blot_check_check::UsageLoan[>..<]=[];for entry in checked.usage_loans {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.usage_loans=copyOwned(entries[..]);}
{var entries:blot_check_check::RankImplementation[>..<]=[];for entry in checked.rank_implementations {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.rank_implementations=copyOwned(entries[..]);}
{var entries:blot_check_generative_schemes::Binder[>..<]=[];for entry in checked.generative_bindings {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.generative_bindings=copyOwned(entries[..]);}
{var entries:blot_check_check::DictionarySelection[>..<]=[];for entry in checked.dictionary_selections {if !contains(ids,source(entry)) {continue;}if entry.goal>=checked.types.quantifierGoals(entry.quantifier).len {return blot_error::Error.dependency_limit;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.dictionary_selections=copyOwned(entries[..]);}
{var entries:blot_check_check::DictionaryUse[>..<]=[];for entry in checked.dictionary_uses {if !contains(ids,source(entry)) {continue;}if entry.goal>=checked.types.quantifierGoals(entry.quantifier).len {return blot_error::Error.dependency_limit;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.dictionary_uses=copyOwned(entries[..]);}
{var entries:blot_check_check::Computation[>..<]=[];for entry in checked.computations {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.computations=copyOwned(entries[..]);}
{var entries:blot_check_check::RequestLoop[>..<]=[];for entry in checked.request_loops {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.request_loops=copyOwned(entries[..]);}
{var entries:blot_check_check::RequestArm[>..<]=[];for entry in checked.request_arms {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.request_arms=copyOwned(entries[..]);}
{var entries:blot_check_check::RequestControl[>..<]=[];for entry in checked.request_controls {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.request_controls=copyOwned(entries[..]);}
{var entries:blot_check_check::Reflection[>..<]=[];for entry in checked.reflections {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.reflections=copyOwned(entries[..]);}
{var entries:blot_check_check::EffectScope[>..<]=[];for entry in checked.effect_scopes {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.effect_scopes=copyOwned(entries[..]);}
{var entries:blot_check_check::EffectRunner[>..<]=[];for entry in checked.effect_runners {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.effect_runners=copyOwned(entries[..]);}
{var entries:blot_check_check::ProviderBlock[>..<]=[];for entry in checked.provider_blocks {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.provider_blocks=copyOwned(entries[..]);}
{var entries:blot_check_check::ResolverBlock[>..<]=[];for entry in checked.resolver_blocks {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.resolver_blocks=copyOwned(entries[..]);}
{var entries:blot_check_check::ResolverOp[>..<]=[];for entry in checked.resolver_ops {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.resolver_ops=copyOwned(entries[..]);}
{var entries:blot_check_check::ResolverJoin[>..<]=[];for entry in checked.resolver_joins {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.resolver_joins=copyOwned(entries[..]);}
{var entries:blot_check_check::ResolverCompletion[>..<]=[];for entry in checked.resolver_completions {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.resolver_completions=copyOwned(entries[..]);}
{var entries:blot_check_check::ResolverLoop[>..<]=[];for entry in checked.resolver_loops {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.resolver_loops=copyOwned(entries[..]);}
{var entries:blot_check_check::OperationUse[>..<]=[];for entry in checked.operation_uses {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.operation_uses=copyOwned(entries[..]);}
{var entries:blot_check_check::StatementArm[>..<]=[];for entry in checked.statement_arms {if !contains(ids,source(entry)) {continue;}mapper.source=source(entry);let mapped,error=mapRecord(entry,mapper);if error!=blot_error::Error.none {return error;}entries.push(mapped);}owner.tables.statement_arms=copyOwned(entries[..]);}
var iterators:Iterator[>..<]=[];for id in ids {if id>=checked.iterator_bodies.len || checked.iterator_bodies[id]==0 {continue;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}let body,error=nodePosition(ids,checked.iterator_bodies[id]);if error!=blot_error::Error.none {return error;}iterators.push(Iterator{node,body, ..});}owner.iterators=copyOwned(iterators[..]);
 var indices:Index[>..<]=[];
for id in ids {if id>=checked.effect_scope_ids.len || checked.effect_scope_ids[id]==0 {continue;}let target,error=index_effect_scopes(checked,ids,checked.effect_scope_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,0,target, ..});}
for id in ids {if id>=checked.effect_runner_ids.len || checked.effect_runner_ids[id]==0 {continue;}let target,error=index_effect_runners(checked,ids,checked.effect_runner_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,1,target, ..});}
for id in ids {if id>=checked.provider_block_ids.len || checked.provider_block_ids[id]==0 {continue;}let target,error=index_provider_blocks(checked,ids,checked.provider_block_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,2,target, ..});}
for id in ids {if id>=checked.resolver_block_ids.len || checked.resolver_block_ids[id]==0 {continue;}let target,error=index_resolver_blocks(checked,ids,checked.resolver_block_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,3,target, ..});}
for id in ids {if id>=checked.resolver_op_ids.len || checked.resolver_op_ids[id]==0 {continue;}let target,error=index_resolver_ops(checked,ids,checked.resolver_op_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,4,target, ..});}
for id in ids {if id>=checked.resolver_join_ids.len || checked.resolver_join_ids[id]==0 {continue;}let target,error=index_resolver_joins(checked,ids,checked.resolver_join_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,5,target, ..});}
for id in ids {if id>=checked.resolver_loop_ids.len || checked.resolver_loop_ids[id]==0 {continue;}let target,error=index_resolver_loops(checked,ids,checked.resolver_loop_ids[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,6,target, ..});}
for id in ids {if id>=checked.operation_refs.len || checked.operation_refs[id]==0 {continue;}let target,error=index_operation_uses(checked,ids,checked.operation_refs[id]);if error!=blot_error::Error.none {return error;}let node,error=nodePosition(ids,id);if error!=blot_error::Error.none {return error;}indices.push(Index{node,7,target, ..});}
let numeric,error=captureNumeric(checked,ids,global);if error!=blot_error::Error.none {return error;}owner.numeric_body=numeric;
 for debit in checked.proof_bodies.debits {if debit.binding!=global {continue;}if owner.proof_debit.present {return blot_error::Error.dependency_limit;}var saved=debit;saved.binding=0;owner.proof_debit=blot_support::some(saved);}
 if (owner.numeric_body.operands.len!=0 || owner.numeric_body.parameters.len!=0) && !owner.proof_debit.present {return blot_error::Error.dependency_limit;}
 for contract in checked.proof_contracts {if contract.binding==global {releaseOwned(owner.proof_parameters);owner.proof_parameters=copyOwned(contract.parameters);}}
 owner.indices=copyOwned(indices[..]);owner.extra=copyOwned(extra[..]);owner.origins=copyOwned(ids);owner.selections=copyOwned(selections[..]);return blot_error::Error.none;
}
type Term=blot_check_numeric_proof_terms::Term;
type Proposition=blot_check_numeric_proof_terms::Proposition;
type NumericOwned=blot_check_numeric_proof_bodies::Owned;
type NumericIntroduction=blot_check_numeric_proof_bodies::Introduction;
type NumericParameter=blot_check_numeric_proof_bodies::Parameter;
type NumericUse=blot_check_numeric_proof_bodies::Use;
type WordMap=blot_support_pooled_map::Map<u32,u32>;
type TermMap=blot_support_pooled_map::Map<Term,u32>;
reusable[] var word_slots:dictionary_slot<u32,u32>[>..]=[];
reusable[] var term_slots:dictionary_slot<Term,u32>[>..]=[];
struct NumericCapture {
 checked:const blot_check_check::Checked&,ids:const u32[:],global:u32,
 mapped:WordMap=WordMap{..},expressions:WordMap=WordMap{..},interned:TermMap=TermMap{..},
 terms:blot_support_pooled_buffer::Buffer<Term> =blot_support_pooled_buffer::Buffer<Term>{},
 introductions:blot_support_pooled_buffer::Buffer<NumericIntroduction> =blot_support_pooled_buffer::Buffer<NumericIntroduction>{},
 parameters:blot_support_pooled_buffer::Buffer<NumericParameter> =blot_support_pooled_buffer::Buffer<NumericParameter>{},
 uses:blot_support_pooled_buffer::Buffer<NumericUse> =blot_support_pooled_buffer::Buffer<NumericUse>{},visits:i64=0,
}
fn deinit(self_:NumericCapture&) {
 blot_support_pooled_map::deinit(self_.mapped,word_slots);blot_support_pooled_map::deinit(self_.expressions,word_slots);blot_support_pooled_map::deinit(self_.interned,term_slots);
 blot_support_pooled_buffer::deinit(self_.terms,pool_blot_check_numeric_proof_terms__Term);
 blot_support_pooled_buffer::deinit(self_.introductions,pool_blot_check_numeric_proof_bodies__Introduction);
 blot_support_pooled_buffer::deinit(self_.parameters,pool_blot_check_numeric_proof_bodies__Parameter);
 blot_support_pooled_buffer::deinit(self_.uses,pool_blot_check_numeric_proof_bodies__Use);
}
fn charge(self_:NumericCapture&)->Error {if self_.visits>=65536 {return blot_error::Error.proof_analysis_limit;}self_.visits+=1;return blot_error::Error.none;}
recursive fn intern(self_:NumericCapture&,term:Term)->u32,Error {
 let error=self_.charge();if error!=blot_error::Error.none {return 0,error;}
 match term.tag {
 literal=>{if term.kind!=blot_check_numeric_proof_terms::Kind.unsigned32 || term.b!=0 {return 0,blot_error::Error.invalid_proof_operand;}},
 formal,capture=>{if term.b!=0 {return 0,blot_error::Error.invalid_proof_operand;}},
 version=>{if term.a==0 || term.b==0 {return 0,blot_error::Error.invalid_proof_operand;}},
 length=>{if term.kind!=blot_check_numeric_proof_terms::Kind.unsigned32 || term.b!=0 || term.a==0 || term.a>self_.terms.items.len {return 0,blot_error::Error.invalid_proof_operand;}if self_.terms.items[term.a-1].kind==blot_check_numeric_proof_terms::Kind.unsigned32 {return 0,blot_error::Error.invalid_proof_operand;}},
 complement=>{
  if term.kind!=blot_check_numeric_proof_terms::Kind.unsigned32 || term.b!=0 || term.a==0 || term.a>self_.terms.items.len {return 0,blot_error::Error.invalid_proof_operand;}let child=self_.terms.items[term.a-1];if child.kind!=blot_check_numeric_proof_terms::Kind.unsigned32 {return 0,blot_error::Error.invalid_proof_operand;}
  if child.tag==blot_check_numeric_proof_terms::Tag.literal {return self_.intern(Term{tag:blot_check_numeric_proof_terms::Tag.literal,a:0xffffffff-child.a, ..});}if child.tag==blot_check_numeric_proof_terms::Tag.complement {return child.a,blot_error::Error.none;}
 },
 }
 let saved .= blot_support_pooled_map::get(self_.interned,term);if saved {return saved,blot_error::Error.none;}
 if self_.terms.items.len>=4096 {return 0,blot_error::Error.proof_analysis_limit;}
 let error=blot_support_pooled_buffer::push(self_.terms,term,pool_blot_check_numeric_proof_terms__Term);if error!=blot_error::Error.none {return 0,error;}let id=self_.terms.items.len as u32;blot_support_pooled_map::insert(self_.interned,term,id,term_slots);return id,blot_error::Error.none;
}
recursive fn term(self_:NumericCapture&,id:u32,depth:i64)->u32,Error {
 let saved .= blot_support_pooled_map::get(self_.mapped,id);if saved {return saved,blot_error::Error.none;}
 if depth>=128 || self_.mapped.count>=4096 || id==0 || id>self_.checked.proof_bodies.operands.len {return 0,blot_error::Error.dependency_limit;}
 var value=self_.checked.proof_bodies.operands[id-1];
 match value.tag {
 length,complement=>{let mapped,error=self_.term(value.a,depth+1);if error!=blot_error::Error.none {return 0,error;}value.a=mapped;},
 version=>{
  if value.b==1 {
   if value.a==0 || value.a>=self_.checked.bindings.len {return 0,blot_error::Error.dependency_limit;}let binding=self_.checked.bindings[value.a];
   if binding.kind==blot_reuse_principal_interface::Kind.parameter || binding.kind==blot_reuse_principal_interface::Kind.local {if !contains(self_.ids,binding.declaration) || !contains(self_.ids,binding.owner) {return 0,blot_error::Error.dependency_limit;}}
   else if binding.kind!=blot_reuse_principal_interface::Kind.global && binding.kind!=blot_reuse_principal_interface::Kind.external {return 0,blot_error::Error.dependency_limit;}
   let tag=self_.checked.types.node(self_.checked.types.head(binding.ty,0)).tag;var expected=blot_check_types::Tag.unsigned32;match value.kind {unsigned32=>{},array=>{expected=blot_check_types::Tag.array;},list=>{expected=blot_check_types::Tag.list;}}
   if tag!=expected {return 0,blot_error::Error.dependency_limit;}
  }else if value.b==2 {let ignored,error=nodePosition(self_.ids,value.a);if error!=blot_error::Error.none {return 0,error;}}else {return 0,blot_error::Error.dependency_limit;}
 },
 literal=>{},
 formal,capture=>{return 0,blot_error::Error.dependency_limit;},
 }
 let mapped,error=self_.intern(value);if error!=blot_error::Error.none {return 0,error;}blot_support_pooled_map::insert(self_.mapped,id,mapped,word_slots);return mapped,blot_error::Error.none;
}
fn proposition(self_:NumericCapture&,value:Proposition)->Proposition,Error {let left,error=self_.term(value.left,0);if error!=blot_error::Error.none {return default<Proposition>(),error;}let right,error=self_.term(value.right,0);if error!=blot_error::Error.none {return default<Proposition>(),error;}return Proposition{value.relation,left,right, ..},blot_error::Error.none;}
fn validate(self_:NumericCapture&,value:Proposition)->Error {return blot_check_numeric_proof_terms::proposition(blot_check_numeric_proof_terms::View{terms:self_.terms.items, ..},value);}
fn captureNumeric(checked:const blot_check_check::Checked&,ids:const u32[:],global:u32)->NumericOwned,Error {
 var work=NumericCapture{checked,ids,global, ..};let result,error=numericInto(work);work.deinit();return result,error;
}
fn numericInto(self_:NumericCapture&)->NumericOwned,Error {
 for entry in self_.checked.proof_bodies.introductions {
  if !contains(self_.ids,entry.source) {continue;}var mapped=entry;
  let proposition,error=self_.proposition(entry.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.proposition=proposition;
  let source,error=nodePosition(self_.ids,entry.source);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.source=source;
  let owner,error=nodePosition(self_.ids,entry.owner);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.owner=owner;
  for node,index in entry.arguments {let position,error=nodePosition(self_.ids,node);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.arguments[index]=position;}
  let error=self_.charge();if error!=blot_error::Error.none {return NumericOwned{..},error;}let error=self_.validate(mapped.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}
  if self_.introductions.items.len>=4096 {return NumericOwned{..},blot_error::Error.proof_analysis_limit;}
  let slot .= blot_support_pooled_map::get(self_.expressions,mapped.source);if slot {if !blot_structural::equal(self_.introductions.items[slot],mapped) {return NumericOwned{..},blot_error::Error.invalid_proof_operand;}continue;}
  blot_support_pooled_map::insert(self_.expressions,mapped.source,self_.introductions.items.len as u32,word_slots);let error=blot_support_pooled_buffer::push(self_.introductions,mapped,pool_blot_check_numeric_proof_bodies__Introduction);if error!=blot_error::Error.none {return NumericOwned{..},error;}
 }
 for entry in self_.checked.proof_bodies.parameters {
  if entry.contract!=self_.global {continue;}var mapped=entry;mapped.contract=0;let proposition,error=self_.proposition(entry.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.proposition=proposition;
  let error=self_.charge();if error!=blot_error::Error.none {return NumericOwned{..},error;}let error=self_.validate(mapped.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}if self_.parameters.items.len>=4096 {return NumericOwned{..},blot_error::Error.proof_analysis_limit;}
  let error=blot_support_pooled_buffer::push(self_.parameters,mapped,pool_blot_check_numeric_proof_bodies__Parameter);if error!=blot_error::Error.none {return NumericOwned{..},error;}
 }
 for entry in self_.checked.proof_bodies.uses {
  if !contains(self_.ids,entry.source) {continue;}var mapped=entry;
  let source,error=nodePosition(self_.ids,entry.source);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.source=source;let witness,error=nodePosition(self_.ids,entry.witness);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.witness=witness;
  let proposition,error=self_.proposition(entry.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}mapped.proposition=proposition;
  let error=self_.charge();if error!=blot_error::Error.none {return NumericOwned{..},error;}let error=self_.validate(mapped.proposition);if error!=blot_error::Error.none {return NumericOwned{..},error;}if self_.uses.items.len>=4096 {return NumericOwned{..},blot_error::Error.proof_analysis_limit;}
  let error=blot_support_pooled_buffer::push(self_.uses,mapped,pool_blot_check_numeric_proof_bodies__Use);if error!=blot_error::Error.none {return NumericOwned{..},error;}
 }
 for debit in self_.checked.proof_bodies.debits {if debit.binding!=self_.global {continue;}if debit.output.terms>self_.checked.proof_bodies.operands.len || debit.frontier.terms>debit.output.terms {return NumericOwned{..},blot_error::Error.dependency_limit;}for index in debit.output.terms-debit.frontier.terms {let ignored,error=self_.term(debit.frontier.terms+index+1,0);if error==blot_error::Error.out_of_memory {return NumericOwned{..},error;}}}
 let operands=copyOwned(self_.terms.items);for operand,index in operands {if operand.tag==blot_check_numeric_proof_terms::Tag.version && operand.b==2 {let position,error=nodePosition(self_.ids,operand.a);if error!=blot_error::Error.none {releaseOwned(operands);return NumericOwned{..},error;}operands[index].a=position;}}
 return NumericOwned{operands:operands,introductions:copyOwned(self_.introductions.items),parameters:copyOwned(self_.parameters.items),uses:copyOwned(self_.uses.items), ..},blot_error::Error.none;
}
