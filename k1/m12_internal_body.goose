// Fixed private Wasm invocation body for a source-checked adapter. This is a
// witness, not a public M12 ABI, C09 receipt, checked frame plan or general
// source ownership checker. Input/output windows and state are fixture-private.
namespace m12_internal_body;
import pool_guest;
import wasm;
fn b(o:u8[>..]&,v:u8){o.push(v);}
fn c(o:u8[>..]&,v:u32){pool_guest::constant(o,v);}
fn get(o:u8[>..]&,i:i64){pool_guest::get(o,i);}
fn set(o:u8[>..]&,i:i64){pool_guest::set(o,i);}
fn call(o:u8[>..]&,i:i64){pool_guest::call(o,i);}
fn load(o:u8[>..]&,off:i64){pool_guest::load(o,off);}
fn store(o:u8[>..]&,off:i64){pool_guest::store(o,off);}
fn open(o:u8[>..]&){b(o,0x04);b(o,0x40);}
fn end(o:u8[>..]&){b(o,0x0b);}
fn check_zero(o:u8[>..]&){b(o,0x45);b(o,0x45);open(o);b(o,0x00);end(o);}
fn memload(o:u8[>..]&,addr:u32){c(o,addr);load(o,0);}
fn setword(o:u8[>..]&,addr:u32,val:u32){c(o,addr);c(o,val);store(o,0);}
fn header(o:u8[>..]&,status:i64,payload:i64,required:i64,items:i64,detail:i64) {
 setword(o,36864,0x4b310001);setword(o,36868,91);
 c(o,36872);get(o,status);store(o,0);c(o,36876);get(o,payload);store(o,0);c(o,36880);get(o,required);store(o,0);c(o,36884);get(o,items);store(o,0);c(o,36888);get(o,detail);store(o,0);
 setword(o,36892,0);
}
fn clear_busy(o:u8[>..]&){setword(o,416,0);}
fn ret_invalid(o:u8[>..]&){c(o,1);set(o,3);c(o,0);set(o,4);setword(o,36872,1);setword(o,36864,0x4b310001);setword(o,36868,91);for a in [36876 as u32,36880,36884,36888,36892] {setword(o,a,0);}clear_busy(o);c(o,1);b(o,0x0f);}
// All invalid fields are combined before entering this branch.
fn invalid_if(o:u8[>..]&){open(o);ret_invalid(o);end(o);}
fn trap_if(o:u8[>..]&){open(o);b(o,0x00);end(o);}
fn body()->u8[] {
 // params export/input_bytes/output_capacity, i32 locals 3..15.
 var o:u8[>..]=[1,13,0x7f];
 // Busy rejection leaves both windows and every control word untouched.
 memload(o,416);open(o);c(o,4);b(o,0x0f);end(o);setword(o,416,1);
 // Before any input read, validate call-level limits and fixed window header.
 get(o,0);c(o,91);b(o,0x47);get(o,1);c(o,44);b(o,0x49);b(o,0x72);get(o,1);c(o,256);b(o,0x4b);b(o,0x72);get(o,2);c(o,224);b(o,0x4b);b(o,0x72);invalid_if(o);
 memload(o,32768);c(o,0x4b310001);b(o,0x47);memload(o,32772);c(o,91);b(o,0x47);b(o,0x72);
 for addr in [32776 as u32,32784,32788,32792,32796] {memload(o,addr);b(o,0x45);b(o,0x45);b(o,0x72);}
 memload(o,32780);get(o,1);c(o,32);b(o,0x6b);b(o,0x47);b(o,0x72);invalid_if(o);
 get(o,1);c(o,32);b(o,0x6b);set(o,13);memload(o,32800);set(o,5);memload(o,32804);set(o,6);
 // offset >= 12, aligned, within payload; count <= 8 and in-range.
 get(o,5);c(o,8);b(o,0x4b);get(o,6);c(o,3);b(o,0x71);b(o,0x45);b(o,0x45);b(o,0x72);get(o,6);c(o,12);b(o,0x49);b(o,0x72);get(o,6);get(o,13);b(o,0x4b);b(o,0x72);invalid_if(o);
 get(o,5);c(o,16);b(o,0x6c);get(o,13);get(o,6);b(o,0x6b);b(o,0x4b);invalid_if(o);
 // Unused/padding bytes are required zero, including zero-length input.
 c(o,12);set(o,12);b(o,0x02);b(o,0x40);b(o,0x03);b(o,0x40);
 get(o,12);get(o,13);b(o,0x4f);b(o,0x0d);b(o,1);
 get(o,12);get(o,6);b(o,0x49);get(o,12);get(o,6);get(o,5);c(o,16);b(o,0x6c);b(o,0x6a);b(o,0x4f);b(o,0x72);open(o);
 c(o,32800);get(o,12);b(o,0x6a);b(o,0x2d);b(o,0);b(o,0);b(o,0x45);b(o,0x45);invalid_if(o);end(o);
 get(o,12);c(o,1);b(o,0x6a);set(o,12);b(o,0x0c);b(o,0);end(o);end(o);
 // Fixed adapter scratch addresses require frame frontier zero. Reject before
 // configuration, reservation, copying or source effects; do not trap.
 memload(o,404);b(o,0x45);b(o,0x45);open(o);
 setword(o,36864,0x4b310001);setword(o,36868,91);setword(o,36872,5);
 for a in [36876 as u32,36880,36884,36888,36892] {setword(o,a,0);}
 clear_busy(o);c(o,5);b(o,0x0f);end(o);
 // Frame entry precedes all reservation and placement.
 c(o,1024);call(o,16);check_zero(o);call(o,18);set(o,14);get(o,14);b(o,0x45);b(o,0x45);open(o);
 get(o,14);c(o,4294967291);b(o,0x47);trap_if(o);
 setword(o,36864,0x4b310001);setword(o,36868,91);setword(o,36872,5);for a in [36876 as u32,36880,36884,36888,36892] {setword(o,a,0);}clear_busy(o);c(o,5);b(o,0x0f);end(o);
 c(o,192);call(o,0);set(o,7);
 get(o,7);c(o,0);b(o,0x4c);open(o);
 // Actual allocator errors -1/-2/-3 map to Result error tags 0/1/2;
 // unknown runtime state is a trap, never a recoverable reservation error.
 get(o,7);b(o,0x45);trap_if(o);get(o,7);c(o,4294967293);b(o,0x48);trap_if(o);
 c(o,0);get(o,7);b(o,0x6b);c(o,1);b(o,0x6b);set(o,4);call(o,19);check_zero(o);
 setword(o,36864,0x4b310001);setword(o,36868,91);setword(o,36872,3);for a in [36876 as u32,36880,36884,36892] {setword(o,a,0);}c(o,36888);get(o,4);store(o,0);clear_busy(o);c(o,3);b(o,0x0f);end(o);
 get(o,7);c(o,1);b(o,0x47);trap_if(o);memload(o,32);set(o,8);
 get(o,7);get(o,8);get(o,5);call(o,5);check_zero(o);memload(o,264);set(o,9);
 // Copy source bytes to newly reserved exclusive input before freezing.
 c(o,0);set(o,12);b(o,0x02);b(o,0x40);b(o,0x03);b(o,0x40);
 get(o,12);get(o,5);c(o,16);b(o,0x6c);b(o,0x4f);b(o,0x0d);b(o,1);
 get(o,9);get(o,12);b(o,0x6a);c(o,32800);get(o,6);b(o,0x6a);get(o,12);b(o,0x6a);b(o,0x2d);b(o,0);b(o,0);b(o,0x3a);b(o,0);b(o,0);
 get(o,12);c(o,1);b(o,0x6a);set(o,12);b(o,0x0c);b(o,0);end(o);end(o);
 get(o,7);get(o,8);call(o,6);get(o,5);b(o,0x47);trap_if(o);
 get(o,7);get(o,8);c(o,8);call(o,8);check_zero(o);memload(o,328);set(o,10);
 // Construct source-order aggregate input inside the entered private frame.
 c(o,49280);get(o,5);b(o,0x45);b(o,0x04);b(o,0x7f);c(o,0);b(o,0x05);get(o,9);end(o);store(o,0);
 c(o,49280);get(o,5);store(o,4);c(o,49280);memload(o,32808);store(o,8);c(o,49280);get(o,10);store(o,12);c(o,49280);c(o,8);store(o,16);
 // Direct source-bound canonical adapter; no host callback.
 c(o,0);c(o,49312);c(o,49280);call(o,21);
 memload(o,49312);b(o,0x45);b(o,0x45);trap_if(o);memload(o,49316);get(o,5);b(o,0x47);trap_if(o);memload(o,49324);get(o,5);b(o,0x47);trap_if(o);
 memload(o,49320);get(o,5);b(o,0x45);b(o,0x04);b(o,0x7f);c(o,0);b(o,0x05);get(o,10);end(o);b(o,0x47);trap_if(o);
 // Required output size is known only after the one source call.
 c(o,8);get(o,5);c(o,8);b(o,0x6c);b(o,0x6a);set(o,11);c(o,0);set(o,3);
 get(o,11);get(o,2);b(o,0x4b);open(o);c(o,2);set(o,3);b(o,0x05);
 c(o,36896);get(o,5);store(o,0);setword(o,36900,8);
 c(o,0);set(o,12);b(o,0x02);b(o,0x40);b(o,0x03);b(o,0x40);
 get(o,12);get(o,5);c(o,8);b(o,0x6c);b(o,0x4f);b(o,0x0d);b(o,1);
 c(o,36904);get(o,12);b(o,0x6a);get(o,10);get(o,12);b(o,0x6a);b(o,0x2d);b(o,0);b(o,0);b(o,0x3a);b(o,0);b(o,0);
 get(o,12);c(o,1);b(o,0x6a);set(o,12);b(o,0x0c);b(o,0);end(o);end(o);end(o);
 // Drop both live views, then owner, then frame before publishing the header.
 get(o,7);get(o,8);call(o,13);check_zero(o);get(o,7);get(o,8);call(o,12);check_zero(o);get(o,7);get(o,8);call(o,11);check_zero(o);call(o,19);check_zero(o);
 c(o,0);set(o,4);get(o,3);b(o,0x45);b(o,0x04);b(o,0x7f);get(o,11);b(o,0x05);c(o,0);end(o);set(o,14);header(o,3,14,11,5,4);clear_busy(o);get(o,3);end(o);return o;
}
