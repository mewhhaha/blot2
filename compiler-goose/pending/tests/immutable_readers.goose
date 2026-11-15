// Live immutable readers keep scalar leases; producers own every observed run.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import check.types;
import check.parameter_patterns;
import check.frozen_types;
import check.numeric_proof_headers;
import reuse.principal_interface;
import reuse.dependency_payload;
import reuse.dependency_snapshot;
import check.numeric_proof_terms;
import check.numeric_proof_contracts;
import support.error;
fn typeReaders() {
    var store,error=blot_check_types::initPooled();assert(error==blot_error::Error.none);
    let lease=store.lease;let generation=store.owner_generation;
    let reader=blot_check_frozen_types::fromStore(store);
    assert(blot_check_frozen_types::validSource(reader));
    let variable,error=store.fresh();assert(error==blot_error::Error.none);
    let before=store.cursor();assert(reader.head(variable,before)==variable);
    assert(store.appendVersion(variable,blot_check_types::u32_type)==blot_error::Error.none);
    assert(store.cursor()>before && reader.head(variable,before)==blot_check_types::u32_type);
    let span,error=store.saveList([blot_check_types::u32_type,blot_check_types::boolean]);assert(error==blot_error::Error.none);
    let array,error=store.array(blot_check_types::u32_type);assert(error==blot_error::Error.none);
    for index in 0..64 {let id,error=store.array(blot_check_types::boolean);assert(error==blot_error::Error.none);}
    assert(reader.node(array).tag==blot_check_types::Tag.array && reader.node(array).a==blot_check_types::u32_type);
    assert(reader.list(span)==[blot_check_types::u32_type,blot_check_types::boolean]);
    let projection,error=store.projection(blot_check_types::NominalIdentity{7,11},17,[blot_check_types::u32_type]);assert(error==blot_error::Error.none);
    assert(reader.projectionMember(reader.node(projection))==17);
    assert(reader.nominalArguments(reader.node(projection))==[blot_check_types::u32_type]);
    assert(reader.head(projection,store.cursor())==projection);
    assert(store.bindAssociated(projection,blot_check_types::boolean)==blot_error::Error.none);
    assert(reader.head(projection,store.cursor())==blot_check_types::boolean);
    {
        var bindings=[default<blot_check_check::Binding>()];bindings[0].name=23;
        var producer=default<blot_check_check::Checked>();producer.types=store;producer.bindings=bindings[..];
        let callees=blot_check_check::liveCallees(producer);
        assert(callees.bindings.len==1 && callees.bindings[0].name==23);
        assert(callees.obligations.len==0 && callees.proof_contracts.len==0);
        let later,error=store.fresh();assert(error==blot_error::Error.none);
        let position=store.cursor();assert(callees.types.head(later,position)==later);
        assert(store.appendVersion(later,blot_check_types::boolean)==blot_error::Error.none);
        assert(callees.types.head(later,position)==blot_check_types::boolean);
    }
    store.deinit();
    assert(!blot_check_types::validLease(lease,generation) && !blot_check_frozen_types::validSource(reader));
    var replacement,error=blot_check_types::initPooled();assert(error==blot_error::Error.none);
    assert(replacement.lease==lease && replacement.owner_generation!=generation);
    assert(blot_check_frozen_types::validSource(blot_check_frozen_types::fromStore(replacement)));
    assert(!blot_check_frozen_types::validSource(reader));replacement.deinit();
}
fn patternReaders() {
    var store,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
    let lease=store.lease;let generation=store.generation;
    let reader=blot_check_frozen_types::fromPatterns(store);
    assert(blot_check_frozen_types::validPatterns(reader));
    let binding,error=store.add(blot_check_parameter_patterns::Node{blot_check_parameter_patterns::Kind.binding,42});assert(error==blot_error::Error.none);
    let tuple,error=store.sequence(blot_check_parameter_patterns::Kind.tuple,[binding]);assert(error==blot_error::Error.none);
    let record,error=store.record([blot_check_parameter_patterns::Field{7,binding}]);assert(error==blot_error::Error.none);
    for index in 0..64 {let id,error=store.add(blot_check_parameter_patterns::Node{blot_check_parameter_patterns::Kind.binding,index as u32});assert(error==blot_error::Error.none);}
    assert(reader.node(binding).a==42);
    let tuple_node=reader.node(tuple);
    assert(tuple_node.kind==blot_check_parameter_patterns::Kind.tuple);
    assert(reader.list(blot_check_types::List{tuple_node.a,tuple_node.b})==[binding]);
    let field=reader.field(reader.node(record),0);assert(field.name==7 && field.pattern==binding);
    store.deinit();
    assert(!blot_check_parameter_patterns::validLease(lease,generation) && !blot_check_frozen_types::validPatterns(reader));
    var replacement,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
    assert(replacement.lease==lease && replacement.generation!=generation);
    assert(blot_check_frozen_types::validPatterns(blot_check_frozen_types::fromPatterns(replacement)));
    assert(!blot_check_frozen_types::validPatterns(reader));replacement.deinit();
}
fn frozenMetadata(graph:blot_check_frozen_types::Graph,patterns:blot_check_frozen_types::PatternGraph,bindings:const blot_reuse_principal_interface::Binding[:],proofs:const blot_check_numeric_proof_headers::Named[:])->blot_check_check::FrozenProducer {
    var producer=default<blot_reuse_principal_interface::Interface>();
    producer.unit=37;producer.graph=graph;producer.patterns=patterns;producer.bindings=bindings;producer.proof_contracts=proofs;
    return blot_check_check::frozenProducer(producer);
}
fn frozenReaders() {
    var nodes=[default<blot_check_types::Node>(),default<blot_check_types::Node>()];
    nodes[1].tag=blot_check_types::Tag.array;nodes[1].a=23;
    var words=[23 as u32,29 as u32];
    var patterns=[blot_check_parameter_patterns::Node{blot_check_parameter_patterns::Kind.binding,41}];
    var bindings=[default<blot_reuse_principal_interface::Binding>(),default<blot_reuse_principal_interface::Binding>()];
    bindings[1].name=43;bindings[1].named_function=true;bindings[1].scheme.root=1;
    var proofs=[default<blot_check_numeric_proof_headers::Named>()];proofs[0].binding=1;proofs[0].header.arity=3;
    var graph=default<blot_check_frozen_types::Graph>();graph.nodes=nodes[..];graph.extra=words[..];
    let pattern_graph=blot_check_frozen_types::PatternGraph{patterns[..],words[..]};
    let producer=frozenMetadata(graph,pattern_graph,bindings[..],proofs[..]);
    let imported=blot_check_check::ImportedCatalog{frozen:blot_support::some(producer),kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0};
    assert(imported.bindingCount()==2 && imported.declaration(1).name==43);
    let catalog=imported.catalog();assert(catalog.unit==37);
    assert(catalog.types.head(1,0)==1 && catalog.types.node(1).a==23);
    assert(catalog.parameter_patterns.node(0).a==41);
    let interface=imported.interface(1);assert(interface.named_function && interface.scheme.root==1);
    assert(interface.types.head(1,999)==1 && interface.types.node(1).tag==blot_check_types::Tag.array);
    assert(blot_support::same_slice_identity(interface.types.list(blot_check_types::List{0,2}),words[..]));
    let proof=interface.proof_contract;assert(proof.present && proof.value.arity==3);
    let nested=interface.callees.interface(1);assert(nested.present && nested.value.named_function && nested.value.scheme.root==1);
    assert(!interface.callees.interface(0).present && !interface.callees.interface(2).present);
    assert(!interface.callees.capabilityContract(1,0).present);
}
struct ProofArenaHolder {arena:blot_check_check::ImportArena&}
fn retainProofHeader(holder:ProofArenaHolder&,catalog:blot_check_check::ImportedCatalog) {
    let interface=catalog.interface(1);
    holder.arena.records.push(blot_check_check::ImportedBinding{target:blot_check_check::ExternalTarget{7,1},interface:interface,origin:13,..});
}
fn proofPayload(owner:blot_reuse_dependency_payload::Owner&)->blot_check_numeric_proof_headers::Owned {
    let value_slots=[0 as u32];let proof_slots=[1 as u32];
    let values=[blot_check_numeric_proof_terms::Kind.unsigned32];
    let operands=[blot_check_numeric_proof_terms::Term{tag:blot_check_numeric_proof_terms::Tag.literal,a:29,..}];
    let requirements=[blot_check_numeric_proof_contracts::Requirement{before:1,proposition:blot_check_numeric_proof_terms::Proposition{blot_check_numeric_proof_terms::Relation.eq,1,1}}];
    let header,error=blot_reuse_dependency_snapshot::copyProofHeader(owner,blot_check_numeric_proof_headers::Owned{arity:2,value_slots:value_slots[..],proof_slots:proof_slots[..],values:values[..],operands:operands[..],requirements:requirements[..],result:blot_support::some(blot_check_numeric_proof_terms::Proposition{blot_check_numeric_proof_terms::Relation.eq,1,1}),..});
    assert(error==blot_error::Error.none);return header;
}
fn pooledProofCatalog(proofs:const blot_check_numeric_proof_headers::Named[:],bindings:const blot_reuse_principal_interface::Binding[:])->blot_check_check::ImportedCatalog {
    var producer=default<blot_reuse_principal_interface::Interface>();producer.bindings=bindings;producer.proof_contracts=proofs;
    return blot_check_check::ImportedCatalog{frozen:blot_support::some(blot_check_check::frozenProducer(producer)),kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0};
}
fn frozenProofArena() {
    var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
    let expected=proofPayload(owner);
    var staging:blot_check_numeric_proof_headers::Named[>..]=[];
    staging.push(blot_check_numeric_proof_headers::Named{binding:1,header:expected});
    let proofs,error=owner.copy(staging);assert(error==blot_error::Error.none);
    let local_bindings=[default<blot_reuse_principal_interface::Binding>(),default<blot_reuse_principal_interface::Binding>()];
    let bindings,error=owner.copy(local_bindings[..]);assert(error==blot_error::Error.none);
    var arena=blot_check_check::ImportArena{records:[]};
    {let catalog=pooledProofCatalog(proofs,bindings);var holder=ProofArenaHolder{arena:arena};retainProofHeader(holder,catalog);}
    staging.clear();
    let optional=arena.records[0].interface.proof_contract;assert(optional.present);let proof=optional.value;
    assert(proof.arity==2 && proof.value_slots[0]==0 && proof.proof_slots[0]==1);
    assert(proof.values[0]==blot_check_numeric_proof_terms::Kind.unsigned32 && proof.operands[0].a==29);
    assert(proof.requirements[0].before==1 && proof.requirements[0].proposition.left==1);
    assert(proof.result.present && proof.result.value.relation==blot_check_numeric_proof_terms::Relation.eq && proof.result.value.right==1);
    let nested=arena.records[0].interface.callees.interface(1);assert(nested.present && nested.value.proof_contract.present && nested.value.proof_contract.value.arity==2);
    assert(!arena.records[0].interface.callees.interface(0).present && !arena.records[0].interface.callees.interface(2).present);
    assert(blot_support::same_slice_identity(proof.value_slots,expected.value_slots));
    assert(blot_support::same_slice_identity(proof.proof_slots,expected.proof_slots));
    assert(blot_support::same_slice_identity(proof.values,expected.values));
    assert(blot_support::same_slice_identity(proof.operands,expected.operands));
    assert(blot_support::same_slice_identity(proof.requirements,expected.requirements));
    arena.records.clear();owner.deinit();
}
fn main() {
    assert(!blot_check_frozen_types::validSource(blot_check_frozen_types::Source.inactive));
    assert(!blot_check_frozen_types::validPatterns(blot_check_frozen_types::Patterns.inactive));
    for cycle in 0..3 {typeReaders();patternReaders();frozenReaders();frozenProofArena();}
    print("immutable readers passed: live mutations, fixed frozen metadata, node/list/pattern views and stale lease rejection");
}
