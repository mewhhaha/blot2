// Scratch frame-arena witness. Frame bytes occupy [49152,53248), separate
// from pool and wire fixture windows. A live invocation has exclusive access
// to the instance; traps poison/discard it. This reservation does not prove
// source frame bounds, whole-host engine stack, M12 ABI or loan authority.
namespace frame_arena;
import wasm;
import pool_guest;
import pool_builder_guest;
import particle_guest;
import i08_same_backend;
fn b(o:u8[>..]&,v:u8){pool_guest::byte(o,v);}
fn c(o:u8[>..]&,v:u32){pool_guest::constant(o,v);}
fn get(o:u8[>..]&,i:i64){pool_guest::get(o,i);}
fn set(o:u8[>..]&,i:i64){pool_guest::set(o,i);}
fn load(o:u8[>..]&,i:i64){pool_guest::load(o,i);}
fn store(o:u8[>..]&,i:i64){pool_guest::store(o,i);}
fn fail(o:u8[>..]&,v:u32){pool_guest::return_if(o,v);}
// Retired state 3 is not live. Empty bitmap alone is insufficient: a
// zero-byte reservation owns a slot but consumes no bitmap blocks.
fn no_owners(o:u8[>..]&) {
 c(o,144);load(o,0);b(o,0x45);b(o,0x45);fail(o,4294967292);
 for i in 4 {
  c(o,36+(i as u32)*32);load(o,0);b(o,0x45);
  c(o,36+(i as u32)*32);load(o,0);c(o,3);b(o,0x46);b(o,0x72);b(o,0x45);fail(o,4294967292);
 }
}
// Invocation must occur within an already-entered frame. Entry occurs before
// host reservation/copy; no source operation happens without that proof.
fn invoke()->u8[>..] {
 var o:u8[>..]=[1,1,0x7f]; // old frontier 5
 c(o,412);load(o,0);c(o,1);b(o,0x47);fail(o,4294967291);
 c(o,408);load(o,0);set(o,5);
 c(o,400);load(o,0);c(o,4096);b(o,0x4b);fail(o,4294967291);
 get(o,5);c(o,400);load(o,0);b(o,0x4b);fail(o,4294967291);
 c(o,768);c(o,400);load(o,0);get(o,5);b(o,0x6b);b(o,0x4b);fail(o,4294967291);
 c(o,404);load(o,0);get(o,5);c(o,768);b(o,0x6a);b(o,0x47);fail(o,4294967291);
 for i in 5 {get(o,i);}pool_guest::call(o,9);b(o,0x0b);return o;
}
// Enter happens before guest reserve, copy and builder setup. A failed enter
// does not mutate memory. The host must leave after all normal cleanup.
fn enter()->u8[>..] {
 var o:u8[>..]=[1,1,0x7f];
 // This private invocation begins with an empty owner pool.
 no_owners(o);
 c(o,412);load(o,0);b(o,0x45);b(o,0x45);fail(o,4294967292);
 c(o,404);load(o,0);set(o,0);
 c(o,400);load(o,0);c(o,4096);b(o,0x4b);fail(o,4294967291);
 get(o,0);c(o,400);load(o,0);b(o,0x4b);fail(o,4294967291);
 c(o,768);c(o,400);load(o,0);get(o,0);b(o,0x6b);b(o,0x4b);fail(o,4294967291);
 c(o,408);get(o,0);store(o,0);c(o,404);get(o,0);c(o,768);b(o,0x6a);store(o,0);
 c(o,412);c(o,1);store(o,0);
 c(o,49152);get(o,0);b(o,0x6a);c(o,0);b(o,0x3a);b(o,0);wasm::unsigned_leb(o,0);
 c(o,0);b(o,0x0b);return o;
}
fn leave()->u8[>..] {
 var o:u8[>..]=[1,1,0x7f];
 // Checked close cannot release an owner with live descriptors.
 no_owners(o);
 c(o,412);load(o,0);c(o,1);b(o,0x47);fail(o,4294967292);
 c(o,408);load(o,0);set(o,0);
 c(o,400);load(o,0);c(o,4096);b(o,0x4b);fail(o,4294967292);
 get(o,0);c(o,400);load(o,0);b(o,0x4b);fail(o,4294967292);
 c(o,768);c(o,400);load(o,0);get(o,0);b(o,0x6b);b(o,0x4b);fail(o,4294967292);
 c(o,404);load(o,0);get(o,0);c(o,768);b(o,0x6a);b(o,0x47);fail(o,4294967292);
 c(o,404);get(o,0);store(o,0);c(o,412);c(o,0);store(o,0);c(o,0);b(o,0x0b);return o;
}
fn configure()->u8[>..] {
 var o:u8[>..]=[0];c(o,412);load(o,0);b(o,0x45);b(o,0x45);fail(o,4294967292);
 c(o,404);load(o,0);b(o,0x45);b(o,0x45);fail(o,4294967292);
 get(o,0);c(o,4096);b(o,0x4b);fail(o,4294967292);
 c(o,400);get(o,0);store(o,0);c(o,0);b(o,0x0b);return o;
}
fn top()->u8[>..] {var o:u8[>..]=[0];c(o,404);load(o,0);b(o,0x0b);return o;}
fn emit(fault:i64)->u8[>..] {
 var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
 let types:u8[42]=[6,0x60,1,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f,
  0x60,3,0x7f,0x7f,0x7f,1,0x7f,0x60,5,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f,
  0x60,6,0x7f,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f];pool_guest::section(out,1,types);
 let funcs:u8[21]=[20,0,1,2,0,1,3,1,3,3,4,5,1,1,1,1,4,0,2,2,2];pool_guest::section(out,3,funcs);
 let mem:u8[4]=[1,1,1,1];pool_guest::section(out,5,mem);
 var exports:u8[>..]=[15];
 i08_same_backend::export_fn(exports,"reserve",0);
 i08_same_backend::export_fn(exports,"close",11);
 i08_same_backend::export_fn(exports,"input_alloc",5);
 i08_same_backend::export_fn(exports,"input_freeze",6);
 i08_same_backend::export_fn(exports,"advance",7);
 i08_same_backend::export_fn(exports,"builder_alloc",8);
 i08_same_backend::export_fn(exports,"project",15);
 i08_same_backend::export_fn(exports,"input_end",12);
 i08_same_backend::export_fn(exports,"output_end",13);
 i08_same_backend::export_fn(exports,"input_discard",14);
 i08_same_backend::export_fn(exports,"frame_config",16);
 i08_same_backend::export_fn(exports,"frame_top",17);
 i08_same_backend::export_fn(exports,"frame_enter",18);
 i08_same_backend::export_fn(exports,"frame_leave",19);
 exports.append([6,'m','e','m','o','r','y',2,0]);pool_guest::section(out,7,exports);
 var code:u8[>..]=[20];pool_guest::add_body(code,pool_guest::reserve());pool_guest::add_body(code,pool_guest::close());
 pool_guest::add_body(code,pool_guest::find_slot());pool_guest::add_body(code,pool_guest::find_run());pool_guest::add_body(code,pool_builder_guest::valid_owner());
 pool_guest::add_body(code,particle_guest::input_alloc());pool_guest::add_body(code,particle_guest::input_freeze());
 pool_guest::add_body(code,i08_same_backend::advance());pool_guest::add_body(code,i08_same_backend::builder_alloc());
 pool_guest::add_body(code,i08_same_backend::project());pool_guest::add_body(code,i08_same_backend::worker(fault));
 pool_guest::add_body(code,i08_same_backend::close_checked());pool_guest::add_body(code,i08_same_backend::end_descriptor(256,1));
 pool_guest::add_body(code,i08_same_backend::end_descriptor(320,0));pool_guest::add_body(code,i08_same_backend::end_descriptor(256,2));
 pool_guest::add_body(code,invoke());pool_guest::add_body(code,configure());pool_guest::add_body(code,top());pool_guest::add_body(code,enter());pool_guest::add_body(code,leave());pool_guest::section(out,10,code);return out;
}
