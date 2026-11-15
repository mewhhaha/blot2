// Concrete declaration publication without constructing an inference Engine.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import check.check_owners;
import check.capability_flow;
import check.types;
import check.parameter_patterns;
import reuse.principal_interface;
import support.error;
import support.option;
type Declaration=blot_check_check::SourceDeclaration;
type Validation=blot_check_check::SourceValidation;
fn publish(populated:bool)->Validation {
    let owner,error=blot_check_check::newCheckedOwner();assert(error==blot_error::Error.none);
    var types,error=blot_check_types::initPooled();assert(error==blot_error::Error.none);
    var patterns,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
    var checked=default<blot_check_check::Checked>();
    checked.owner=owner;checked.types=types;checked.parameter_patterns=patterns;checked.unit=7;
    var declarations:Declaration[>..]=[];
    if populated {
        declarations.push(Declaration{capability_flow:blot_check_capability_flow::Contract.identity,
            capability_parameters:blot_check_capability_flow::Parameters{
                kind:blot_check_capability_flow::ParameterResult.invoke_input,mask:3,inputs:2,invocation_arguments:5,invocation_count:1},
            private:true,name:11,declaration:21,kind:blot_reuse_principal_interface::Kind.global,
            named_function:true,external:blot_support::none<blot_check_check::ExternalTarget>()});
        declarations.push(Declaration{capability_flow:blot_check_capability_flow::Contract.spawn_task,
            capability_parameters:blot_check_capability_flow::Parameters{..},
            private:false,name:12,declaration:22,kind:blot_reuse_principal_interface::Kind.external,
            named_function:false,external:blot_support::some(blot_check_check::ExternalTarget{7,9})});
    }
    let owned=blot_check_check::ownChecked_declarations(owner,declarations);
    if populated {declarations[0].name=999;declarations[0].capability_parameters.mask=0;}
    declarations.clear();
    var result=blot_check_check::ownedSourceValidation(checked,owned);
    blot_check_check::releaseCheckedBodies(checked.owner);
    checked.owner=blot_check_check::CheckedOwner{..};
    return result;
}
fn retained(populated:bool) {
    var validation=publish(populated);
    let owner=validation.owner;assert(owner.valid() && validation.unit==7);
    assert(validation.types.valid() && validation.parameter_patterns.valid());
    if populated {
        assert(validation.declarations.len==2);
        let first=validation.declarations[0];
        assert(first.capability_flow==blot_check_capability_flow::Contract.identity);
        assert(first.private && first.name==11 && first.declaration==21 && first.named_function);
        assert(first.kind==blot_reuse_principal_interface::Kind.global && !first.external.present);
        assert(first.capability_parameters.kind==blot_check_capability_flow::ParameterResult.invoke_input);
        assert(first.capability_parameters.mask==3 && first.capability_parameters.inputs==2);
        assert(first.capability_parameters.invocation_arguments==5 && first.capability_parameters.invocation_count==1);
        let second=validation.declarations[1];
        assert(second.capability_flow==blot_check_capability_flow::Contract.spawn_task);
        assert(!second.private && second.name==12 && second.declaration==22 && !second.named_function);
        assert(second.kind==blot_reuse_principal_interface::Kind.external && second.external.present);
        assert(second.external.value.unit==7 && second.external.value.binding==9);
    } else {assert(validation.declarations.len==0);}
    validation.deinit();assert(!owner.valid());
    var replacement,error=blot_check_check::newCheckedOwner();assert(error==blot_error::Error.none);
    assert(replacement.lease==owner.lease && replacement.generation!=owner.generation && !owner.valid());
    replacement.deinit();
}
fn main() {
    for cycle in 0..3 {retained(false);retained(true);}
    print("source validation ownership passed: declaration copy, registered publication, retained records and release/reuse");
}
