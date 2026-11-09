// Exploratory source-only effect probe; this is not a qualification law.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import dictionary;
import check.check;
import check.types;
import check.parameter_patterns;
import check.frozen_types;
import support.error;
type ImportedBinding=blot_check_check::ImportedBinding;
type ExternalTarget=blot_check_check::ExternalTarget;
type ImportedMap=dictionary<ExternalTarget,ImportedBinding>;
struct Holder {map:ImportedMap&}
fn collect(holder:Holder&,imports:const ImportedBinding[:]) {
    for imported in imports {holder.map.insert(imported.target,imported);}
    for index in 0..64 {
        var value=imports[0];value.target=ExternalTarget{unit:2,binding:index as u32};
        holder.map.insert(value.target,value);
    }
}
fn collectDirect(map:ImportedMap&,imports:const ImportedBinding[:]) {
    for imported in imports {map.insert(imported.target,imported);}
    for index in 0..64 {
        var value=imports[0];value.target=ExternalTarget{unit:3,binding:index as u32};
        map.insert(value.target,value);
    }
}
fn probe() {
    var store,error=blot_check_types::init();assert(error==blot_error::Error.none);
    var patterns,error=blot_check_parameter_patterns::init();assert(error==blot_error::Error.none);
    let variable,error=store.fresh();assert(error==blot_error::Error.none);
    var bindings=[blot_check_check::Binding{name:0,declaration:0,owner:0,kind:blot_reuse_principal_interface::Kind.global,named_function:false,ty:variable,scheme:blot_check_types::Scheme{root:variable,..},..}];
    var producer=blot_check_check::Checked{types:store,parameter_patterns:patterns,bindings:bindings[..],..};
    let reader=blot_check_check::liveCallees(producer);
    let inputs=[ImportedBinding{target:ExternalTarget{unit:1,binding:0},interface:blot_check_check::SchemeInterface{types:reader.types,scheme:bindings[0].scheme,obligations:reader.obligations,callees:blot_check_check::Callees.live{reader},..},origin:0,..}];
    var held=ImportedMap{};var direct=ImportedMap{};
    {
        var holder=Holder{map:held};collect(holder,inputs[..]);
        assert(inputs[0].interface.types.head(variable,0)==variable);
    }
    collectDirect(direct,inputs[..]);
    assert(inputs[0].interface.callees.interface(0).present==false);
    assert(held.count==65 && direct.count==65);
    held.clear();direct.clear();patterns.deinit();store.deinit();
}
fn main() {probe();print("import shrink probe completed");}
