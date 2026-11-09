// Imported metadata stays in one owner; growing maps contain scalar indices.
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
type ImportedMap=dictionary<ExternalTarget,u32>;
// The record owns its grow-only arena; no growable-array reference is stored.
struct ImportArena {records:ImportedBinding[>..]}
struct Holder {map:ImportedMap&,arena:ImportArena&}
struct Context {holder:Holder&}
fn register(holder:Holder&,imported:ImportedBinding) {
    if holder.map.contains(imported.target) {return;}
    let index=holder.arena.records.len as u32;holder.arena.records.push(imported);
    holder.map.insert(imported.target,index);
}
fn collect(holder:Holder&,imports:const ImportedBinding[:]) {
    // Catalog methods enter before exposed imports; duplicate targets keep that first row.
    register(holder,ImportedBinding{target:ExternalTarget{unit:2,binding:0},interface:imports[0].interface,origin:30,expose:false,..});
    for imported in imports {register(holder,imported);}
    for index in 0..64 {
        var imported=imports[0];imported.target=ExternalTarget{unit:3,binding:index as u32};imported.origin=(100+index) as u32;
        register(holder,imported);
    }
}
fn collectContext(context:Context&,imports:const ImportedBinding[:]) {collect(context.holder,imports);}
fn probe() {
    var store,error=blot_check_types::init();assert(error==blot_error::Error.none);
    var patterns,error=blot_check_parameter_patterns::init();assert(error==blot_error::Error.none);
    let variable,error=store.fresh();assert(error==blot_error::Error.none);
    var bindings=[blot_check_check::Binding{name:0,declaration:0,owner:0,kind:blot_reuse_principal_interface::Kind.global,named_function:false,ty:variable,scheme:blot_check_types::Scheme{root:variable,..},..}];
    var producer=blot_check_check::Checked{types:store,parameter_patterns:patterns,bindings:bindings[..],..};
    let reader=blot_check_check::liveCallees(producer);
    let interface=blot_check_check::SchemeInterface{types:reader.types,scheme:bindings[0].scheme,obligations:reader.obligations,callees:blot_check_check::Callees.live{reader},..};
    let inputs=[ImportedBinding{target:ExternalTarget{unit:1,binding:0},interface:interface,origin:10,..},ImportedBinding{target:ExternalTarget{unit:1,binding:0},interface:interface,origin:20,..},ImportedBinding{target:ExternalTarget{unit:2,binding:0},interface:interface,origin:40,..}];
    var map=ImportedMap{};var arena=ImportArena{records:[]};{var holder=Holder{map:map,arena:arena};
    {
        var context=Context{holder:holder};collectContext(context,inputs[..]);
        assert(inputs[0].interface.types.head(variable,0)==variable && inputs[1].origin==20);
    }
    assert(map.count==66 && holder.arena.records.len==66);
    {
        let found .= map.get(inputs[0].target);assert(found!=null);let index:u32=found;
        assert(holder.arena.records[index].origin==10);
    }
    {
        let found .= map.get(ExternalTarget{unit:2,binding:0});assert(found!=null);let index:u32=found;
        assert(holder.arena.records[index].origin==30 && !holder.arena.records[index].expose);
    }
    {
        let found .= map.get(ExternalTarget{unit:3,binding:63});assert(found!=null);let index:u32=found;
        assert(holder.arena.records[index].origin==163 && holder.arena.records[index].interface.types.head(variable,0)==variable);
    }
    }
    arena.records.clear();map.clear();patterns.deinit();store.deinit();
}

fn main() {probe();print("import arena passed: first-wins, synthetic order, growth, readonly producer metadata");}
