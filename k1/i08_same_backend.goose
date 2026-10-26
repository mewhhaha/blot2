// Trusted private target component for one closed particle-source fixture.
// Setup allocates an output Builder separately. The source worker receives an
// already-created zero-length builder and immutable input, performs no
// placement/reservation/owner checks or helper calls, and freezes that builder.
// Raw exported setup/handles are test fixtures, not a public K1 ABI or source
// authority. Global slot/bitmap consistency, input initialization, affine
// consumption and lexical loans remain caller-established invariants.
namespace i08_same_backend;
import wasm;
import pool_guest;
import pool_builder_guest;
import particle_guest;
fn b(out:u8[>..]&,v:u8) {pool_guest::byte(out,v);}
fn c(out:u8[>..]&,v:u32) {pool_guest::constant(out,v);}
fn get(out:u8[>..]&,i:i64) {pool_guest::get(out,i);}
fn set(out:u8[>..]&,i:i64) {pool_guest::set(out,i);}
fn call(out:u8[>..]&,i:i64) {pool_guest::call(out,i);}
fn load(out:u8[>..]&,i:i64) {pool_guest::load(out,i);}
fn store(out:u8[>..]&,i:i64) {pool_guest::store(out,i);}
fn field(out:u8[>..]&,p:i64,i:i64) {pool_guest::field(out,p,i);}
fn set_field(out:u8[>..]&,p:i64,i:i64,v:u32) {pool_guest::field_const(out,p,i,v);}
fn local_field(out:u8[>..]&,p:i64,i:i64,l:i64) {pool_guest::field_local(out,p,i,l);}
fn fail(out:u8[>..]&,v:u32) {pool_guest::return_if(out,v);}
fn desc(out:u8[>..]&,slot:i64,base:u32) {
 c(out,base);get(out,slot);c(out,1);b(out,0x6b);c(out,16);b(out,0x6c);b(out,0x6a);
}
fn capaddr(out:u8[>..]&,slot:i64) {c(out,384);get(out,slot);c(out,1);b(out,0x6b);c(out,4);b(out,0x6c);b(out,0x6a);}
fn indexed(out:u8[>..]&,base:i64,index:i64,stride:u32) {get(out,base);get(out,index);c(out,stride);b(out,0x6c);b(out,0x6a);}
fn loadf(out:u8[>..]&,offset:i64) {b(out,0x2a);b(out,2);wasm::unsigned_leb(out,offset);}
fn storef(out:u8[>..]&,offset:i64) {b(out,0x38);b(out,2);wasm::unsigned_leb(out,offset);}
// Setup only: consume the raw fixture frontier by aligned byte count. No K1
// source function can obtain this authority from a number.
fn advance()->u8[>..] {
 var out:u8[>..]=[1,2,0x7f]; // owner 3, aligned 4
 get(out,0);get(out,1);call(out,4);set(out,3);get(out,3);b(out,0x45);fail(out,4294967292);
 field(out,3,12);c(out,3);b(out,0x6a);c(out,4294967292);b(out,0x71);set(out,4);
 get(out,4);field(out,3,4);b(out,0x4b);fail(out,4294967294);
 get(out,2);field(out,3,4);get(out,4);b(out,0x6b);b(out,0x4b);fail(out,4294967294);
 get(out,3);get(out,4);get(out,2);b(out,0x6a);store(out,12);
 c(out,0);b(out,0x0b);return out;
}
// Setup only: (owner,generation,capacity)->0/-1 overflow/-2 no space/-4 fault.
// The resulting builder occupies [aligned(top),aligned(top)+8*C); earlier
// allocations stay untouched. Invalid outcomes do not change any byte.
fn builder_alloc()->u8[>..] {
 var out:u8[>..]=[1,5,0x7f]; // owner3 desc4 aligned5 bytes6 data7
 get(out,0);get(out,1);call(out,4);set(out,3);get(out,3);b(out,0x45);fail(out,4294967292);
 desc(out,0,320);set(out,4);
 field(out,4,0);b(out,0x45);b(out,0x45);field(out,4,4);get(out,1);b(out,0x46);b(out,0x71);fail(out,4294967292);
 get(out,2);c(out,536870911);b(out,0x4b);fail(out,4294967295);
 get(out,2);c(out,8);b(out,0x6c);set(out,6);
 field(out,3,12);c(out,3);b(out,0x6a);c(out,4294967292);b(out,0x71);set(out,5);
 get(out,5);field(out,3,4);b(out,0x4b);fail(out,4294967294);
 get(out,6);field(out,3,4);get(out,5);b(out,0x6b);b(out,0x4b);fail(out,4294967294);
 field(out,3,0);get(out,5);b(out,0x6a);set(out,7);
 get(out,3);get(out,5);get(out,6);b(out,0x6a);store(out,12);
 set_field(out,4,0,1);local_field(out,4,4,1);local_field(out,4,8,7);set_field(out,4,12,0);
 capaddr(out,0);get(out,2);store(out,0);
 c(out,0);b(out,0x0b);return out;
}
// Source worker: (input data,n,builder data,builder record,c,dt)->n. All
// ownership/extent/initialization/precondition checks belong to the caller.
// It consumes the supplied builder, writes each full row then publishes its
// length, freezes on return, and never places storage or calls a helper.
fn worker(fault_after:i64)->u8[>..] {
 var out:u8[>..]=[2,1,0x7f,2,0x7d]; // i=6, evaluated x=7 and y=8
 if fault_after==0 {b(out,0x00);}
 c(out,0);set(out,6);b(out,0x02);b(out,0x40);b(out,0x03);b(out,0x40);
  get(out,6);get(out,1);b(out,0x4f);b(out,0x0d);wasm::unsigned_leb(out,1);
  indexed(out,0,6,16);loadf(out,0);
  indexed(out,0,6,16);loadf(out,8);get(out,5);b(out,0x94);b(out,0x92);set(out,7);
  indexed(out,0,6,16);loadf(out,4);
  indexed(out,0,6,16);loadf(out,12);get(out,5);b(out,0x94);b(out,0x92);set(out,8);
  indexed(out,2,6,8);get(out,7);storef(out,0);
  indexed(out,2,6,8);get(out,8);storef(out,4);
  get(out,3);get(out,6);c(out,1);b(out,0x6a);store(out,12);
  if fault_after>0 {get(out,6);c(out,(fault_after-1) as u32);b(out,0x46);b(out,0x04);b(out,0x40);b(out,0x00);b(out,0x0b);}
  get(out,6);c(out,1);b(out,0x6a);set(out,6);b(out,0x0c);wasm::unsigned_leb(out,0);
 b(out,0x0b);b(out,0x0b);
 get(out,1);b(out,0x45);b(out,0x04);b(out,0x40);set_field(out,3,8,0);b(out,0x0b);
 set_field(out,3,0,2);get(out,1);b(out,0x0b);return out;
}
// Test wrapper validates trusted owner/descriptor geometry and the source
// precondition and concrete non-overlap before entering the worker. It never places or advances output.
// (in slot,in gen,out slot,out gen,dt)->n or -3 capacity/-4 fault.
fn project()->u8[>..] {
 var out:u8[>..]=[1,9,0x7f]; // inowner5 outowner6 indesc7 outdesc8 n9 cap10 offset11 bytes12 data13
 get(out,0);get(out,1);call(out,4);set(out,5);get(out,5);b(out,0x45);fail(out,4294967292);
 get(out,2);get(out,3);call(out,4);set(out,6);get(out,6);b(out,0x45);fail(out,4294967292);
 get(out,0);get(out,2);b(out,0x47);fail(out,4294967292);
 desc(out,0,256);set(out,7);field(out,7,0);c(out,2);b(out,0x47);fail(out,4294967292);
 field(out,7,4);get(out,1);b(out,0x47);fail(out,4294967292);field(out,7,12);set(out,9);
 get(out,9);c(out,268435455);b(out,0x4b);fail(out,4294967292);
 get(out,9);c(out,16);b(out,0x6c);field(out,5,12);b(out,0x4b);fail(out,4294967292);
 get(out,9);b(out,0x45);b(out,0x04);b(out,0x40);
  field(out,7,8);b(out,0x45);b(out,0x45);fail(out,4294967292);
 b(out,0x05);field(out,7,8);field(out,5,0);b(out,0x47);fail(out,4294967292);b(out,0x0b);
 desc(out,2,320);set(out,8);field(out,8,0);c(out,1);b(out,0x47);fail(out,4294967292);
 field(out,8,4);get(out,3);b(out,0x47);fail(out,4294967292);
 field(out,8,12);b(out,0x45);b(out,0x45);fail(out,4294967292); // source initial length is zero
 capaddr(out,2);load(out,0);set(out,10);get(out,10);c(out,536870911);b(out,0x4b);fail(out,4294967292);
 get(out,10);c(out,8);b(out,0x6c);set(out,12);field(out,8,8);set(out,13);
 get(out,13);field(out,6,0);b(out,0x49);fail(out,4294967292);
 get(out,13);field(out,6,0);b(out,0x6b);set(out,11);
 get(out,11);c(out,3);b(out,0x71);b(out,0x45);b(out,0x45);fail(out,4294967292);
 get(out,11);field(out,6,12);b(out,0x4b);fail(out,4294967292);
 get(out,12);field(out,6,12);get(out,11);b(out,0x6b);b(out,0x4b);fail(out,4294967292);
 // Nonempty builder range must start after the complete frozen input. Both
 // offsets have been checked against the same owner frontier above.
 get(out,9);b(out,0x45);b(out,0x45);get(out,12);b(out,0x45);b(out,0x45);b(out,0x71);b(out,0x04);b(out,0x40);
  get(out,11);get(out,9);c(out,16);b(out,0x6c);b(out,0x49);fail(out,4294967292);
 b(out,0x0b);
 get(out,9);get(out,10);b(out,0x4b);fail(out,4294967293);
 // Prepared arguments: immutable view, existing builder and its capacity.
 field(out,7,8);get(out,9);get(out,13);get(out,8);get(out,10);get(out,4);call(out,10);b(out,0x0b);return out;
}
// Fixture-only descriptor lifetime controls. End the frozen input loan or the
// output builder/view before close. Host memory is mutable; source ownership
// and hidden runtime handles are not established by these numeric records.
fn close_checked()->u8[>..] {
 var out:u8[>..]=[1,1,0x7f];
 get(out,0);get(out,1);call(out,4);set(out,2);get(out,2);b(out,0x45);fail(out,4294967292);
 desc(out,0,256);set(out,2);field(out,2,0);b(out,0x45);b(out,0x45);field(out,2,4);get(out,1);b(out,0x46);b(out,0x71);fail(out,4294967292);
 desc(out,0,320);set(out,2);field(out,2,0);b(out,0x45);b(out,0x45);field(out,2,4);get(out,1);b(out,0x46);b(out,0x71);fail(out,4294967292);
 get(out,0);get(out,1);call(out,1);b(out,0x0b);return out;
}
fn end_descriptor(base:u32,kind:u32)->u8[>..] {
 var out:u8[>..]=[1,1,0x7f];
 get(out,0);get(out,1);call(out,4);set(out,2);get(out,2);b(out,0x45);fail(out,4294967292);
 desc(out,0,base);set(out,2);field(out,2,4);get(out,1);b(out,0x47);fail(out,4294967292);
 if kind==1 {field(out,2,0);c(out,2);b(out,0x47);fail(out,4294967292);}
 else if kind==2 {field(out,2,0);c(out,1);b(out,0x47);fail(out,4294967292);}
 else {field(out,2,0);c(out,1);b(out,0x46);field(out,2,0);c(out,2);b(out,0x46);b(out,0x72);b(out,0x45);fail(out,4294967292);}
 set_field(out,2,0,0);c(out,0);b(out,0x0b);return out;
}
fn export_fn(out:u8[>..]&,name:u8[:],index:i64) {wasm::unsigned_leb(out,name.len);out.append(name);b(out,0);wasm::unsigned_leb(out,index);}
fn emit_test(fault_after:i64)->u8[>..] {
 var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
 // (i32), (i32,i32), (), (i32,i32,i32), (4 i32,f32), (5 i32,f32), all -> i32.
 let types:u8[42]=[6,0x60,1,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f,
  0x60,3,0x7f,0x7f,0x7f,1,0x7f,0x60,5,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f,
  0x60,6,0x7f,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f];
 pool_guest::section(out,1,types);
 let funcs:u8[16]=[15,0,1,2,0,1,3,1,3,3,4,5,1,1,1,1];pool_guest::section(out,3,funcs);
 let memory:u8[4]=[1,1,1,1];pool_guest::section(out,5,memory);
 var exports:u8[>..]=[11];export_fn(exports,"reserve",0);export_fn(exports,"close",11);export_fn(exports,"input_alloc",5);
 export_fn(exports,"input_freeze",6);export_fn(exports,"advance",7);export_fn(exports,"builder_alloc",8);export_fn(exports,"project",9);export_fn(exports,"input_end",12);export_fn(exports,"output_end",13);export_fn(exports,"input_discard",14);
 exports.append([6,'m','e','m','o','r','y',2,0]);pool_guest::section(out,7,exports);
 var code:u8[>..]=[15];pool_guest::add_body(code,pool_guest::reserve());pool_guest::add_body(code,pool_guest::close());
 pool_guest::add_body(code,pool_guest::find_slot());pool_guest::add_body(code,pool_guest::find_run());pool_guest::add_body(code,pool_builder_guest::valid_owner());
 pool_guest::add_body(code,particle_guest::input_alloc());pool_guest::add_body(code,particle_guest::input_freeze());
 pool_guest::add_body(code,advance());pool_guest::add_body(code,builder_alloc());pool_guest::add_body(code,project());pool_guest::add_body(code,worker(fault_after));
 pool_guest::add_body(code,close_checked());pool_guest::add_body(code,end_descriptor(256,1));pool_guest::add_body(code,end_descriptor(320,0));pool_guest::add_body(code,end_descriptor(256,2));
 pool_guest::section(out,10,code);return out;
}
fn emit()->u8[>..] {return emit_test(-1);}
