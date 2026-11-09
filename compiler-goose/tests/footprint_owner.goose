// Cached dispatch spellings own their bytes; target lists grow without borrowing keys.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.storage_global_footprint;
import driver.compile_workspace;
import support.error;
import support.native;
fn main() {
    for cycle in 0..4 {
        var text:u8[>..]=[];text.append("dispatch");
        let names=[blot_check_core::FieldName{symbol:1,spelling:blot_check_core::Name{0,8}}];
        var associated:blot_check_core::Associated[12]=default<blot_check_core::Associated[12]>();
        var globals:blot_check_core::BindingRef[12]=default<blot_check_core::BindingRef[12]>();
        for index in 0..12 {let target=blot_check_core::BindingRef{1,(index+1) as u32};globals[index]=target;associated[index]=blot_check_core::Associated{identity:blot_check_types::NominalIdentity{..},member:1,operator:blot_check_types::Operator.none,target:target};}
        let units=[blot_check_core::Module{field_names:names[..],unit:1,names:text[..],associated:associated[..],..}];
        var index,error=blot_backend_storage_global_footprint::init(units[..],globals[..]);assert(error==blot_error::Error.none && index.names.count==1);
        {let found=index.names.get("dispatch");assert(found && found.items.len==12 && found.items[11].binding==12);}
        for slot in index.names.slots {if slot.tag!=0 {assert(slot.key==text[..] && !blot_support::same_slice_identity(slot.key,text[..]));}}
        var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
        index.deinit();text=[];
    }
}
