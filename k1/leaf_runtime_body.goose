// Private scalar wrapper; reserves real fixed frame/depth counters. Traps poison.
namespace leaf_runtime_body;
import pool_guest;
fn body(depth:u32,frame:u32)->u8[] {
 var o:u8[>..]=[1,3,0x7f]; // arg0; locals old-depth=1, old-frame=2, result=3
 pool_guest::constant(o,0);pool_guest::load(o,0);pool_guest::set(o,1);
 pool_guest::constant(o,4);pool_guest::load(o,0);pool_guest::set(o,2);
 // Reject malformed/exhausted depth before any reservation or source effect.
 pool_guest::get(o,1);pool_guest::constant(o,128);o.push(0x4b); // old > 128
 pool_guest::constant(o,128);pool_guest::get(o,1);o.push(0x6b);pool_guest::constant(o,depth+1);o.push(0x49);o.push(0x72);
 o.append([0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x20,0x0f,0x0b]); // status 2
 // Guard old frontier before subtraction, then require full declared frame.
 pool_guest::get(o,2);pool_guest::constant(o,1048576);o.push(0x4b);
 pool_guest::constant(o,1048576);pool_guest::get(o,2);o.push(0x6b);pool_guest::constant(o,frame);o.push(0x49);o.push(0x72);
 o.append([0x04,0x40,0x42,0x80,0x80,0x80,0x80,0x30,0x0f,0x0b]); // status 3
 // Reserve both counters, call the exact source leaf with environment 0.
 pool_guest::constant(o,0);pool_guest::get(o,1);pool_guest::constant(o,depth+1);o.push(0x6a);pool_guest::store(o,0);
 pool_guest::constant(o,4);pool_guest::get(o,2);pool_guest::constant(o,frame);o.push(0x6a);pool_guest::store(o,0);
 pool_guest::constant(o,0);pool_guest::get(o,0);pool_guest::call(o,0);pool_guest::set(o,3);
 // Only normal return reaches restoration; unexpected traps poison instance.
 pool_guest::constant(o,4);pool_guest::get(o,2);pool_guest::store(o,0);
 pool_guest::constant(o,0);pool_guest::get(o,1);pool_guest::store(o,0);
 pool_guest::get(o,3);o.push(0xad);o.push(0x0b);return copy(o);
}
