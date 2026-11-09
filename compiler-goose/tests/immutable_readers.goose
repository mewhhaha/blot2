// Live immutable readers keep scalar leases; producers own every observed run.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import check.types;
import check.parameter_patterns;
import check.frozen_types;
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
fn main() {
    assert(!blot_check_frozen_types::validSource(blot_check_frozen_types::Source.inactive));
    assert(!blot_check_frozen_types::validPatterns(blot_check_frozen_types::Patterns.inactive));
    for cycle in 0..3 {typeReaders();patternReaders();}
    print("immutable readers passed: live mutations, metadata, node/list/pattern views and stale lease rejection");
}
