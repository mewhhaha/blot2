// Compiler fixture: validates source/Core, constructs a worker from checked
// postorder F32 operations, and independently validates the final module.
// Only setup/helper bodies remain pinned to the previously reviewed private
// fixture. No public K1 ABI, complete loan system or M13 certificate is claimed.
namespace i08_same_wasm;
import pool_guest;
import pool_builder_guest;
import particle_guest;
import i08_same_backend;
import particle_source_core;
import particle_lower_core;
import particle_lower_verify;
import particle_lower_worker;
import i08_same_target;
fn emit(core:particle_lower_core::Core&,source:u8[:],context:particle_source_core::Context)->u8[] {
    if !particle_lower_verify::verify(core,source,context){return [];}
    let body=particle_lower_worker::emit(core);if body.len==0{return [];}
    var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
    let types:u8[42]=[6,0x60,1,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f,
      0x60,3,0x7f,0x7f,0x7f,1,0x7f,0x60,5,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f,
      0x60,6,0x7f,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f];pool_guest::section(out,1,types);
    let funcs:u8[16]=[15,0,1,2,0,1,3,1,3,3,4,5,1,1,1,1];pool_guest::section(out,3,funcs);
    let memory:u8[4]=[1,1,1,1];pool_guest::section(out,5,memory);
    var exports:u8[>..]=[11];i08_same_backend::export_fn(exports,"reserve",0);i08_same_backend::export_fn(exports,"close",11);
    i08_same_backend::export_fn(exports,"input_alloc",5);i08_same_backend::export_fn(exports,"input_freeze",6);
    i08_same_backend::export_fn(exports,"advance",7);i08_same_backend::export_fn(exports,"builder_alloc",8);
    i08_same_backend::export_fn(exports,"project",9);i08_same_backend::export_fn(exports,"input_end",12);i08_same_backend::export_fn(exports,"output_end",13);i08_same_backend::export_fn(exports,"input_discard",14);exports.append([6,'m','e','m','o','r','y',2,0]);pool_guest::section(out,7,exports);
    var code:u8[>..]=[15];pool_guest::add_body(code,pool_guest::reserve());pool_guest::add_body(code,pool_guest::close());
    pool_guest::add_body(code,pool_guest::find_slot());pool_guest::add_body(code,pool_guest::find_run());pool_guest::add_body(code,pool_builder_guest::valid_owner());
    pool_guest::add_body(code,particle_guest::input_alloc());pool_guest::add_body(code,particle_guest::input_freeze());
    pool_guest::add_body(code,i08_same_backend::advance());pool_guest::add_body(code,i08_same_backend::builder_alloc());
    pool_guest::add_body(code,i08_same_backend::project());pool_guest::add_body(code,body);
    pool_guest::add_body(code,i08_same_backend::close_checked());pool_guest::add_body(code,i08_same_backend::end_descriptor(256,1));pool_guest::add_body(code,i08_same_backend::end_descriptor(320,0));pool_guest::add_body(code,i08_same_backend::end_descriptor(256,2));pool_guest::section(out,10,code);
    if !i08_same_target::verify(core,source,context,out){return [];}
    return out;
}
