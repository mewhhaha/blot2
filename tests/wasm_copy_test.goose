import std;
import os;
import src.wasm;
import src.runtime;

fn test_wasm_word_copy_fixture() {
  let map,valid=runtime::make_map(runtime::Config{pool_bytes:4096,owner_slots:1,frame_bytes:256,ingress_bytes:256,egress_bytes:256});assert(valid);
  wasm::with_module(map) {m=>
    let dynamic=wasm::signature(m,[0x7f as u8,0x7f,0x7f],0);
    var fast:u8[>..]=[];wasm::local_declarations(fast,3,0x7f);wasm::get(fast,0);wasm::get(fast,1);wasm::get(fast,2);wasm::copy_dynamic_word(fast,3,4,5);wasm::end(fast);
    let fast_id=wasm::function(m,dynamic,fast);wasm::export_function(m,"copy",fast_id);
    var bulk:u8[>..]=[0,0x20,0,0x20,1,0x20,2,0xfc,10,0,0,0x0b];let bulk_id=wasm::function(m,dynamic,bulk);wasm::export_function(m,"bulk",bulk_id);
    let fixed=wasm::signature(m,[0x7f as u8,0x7f],0);
    var word:u8[>..]=[0,0x20,0,0x20,1,0x28,2,0,0x36,2,0,0x0b];let word_id=wasm::function(m,fixed,word);wasm::export_function(m,"word",word_id);
    wasm::export_memory(m);var output:u8[>..]=[];wasm::encode(m,output);
    assert(write_file("/tmp/blot-k1-word-copy.wasm",output));
  }
  print("WASM word-copy and bulk-reference fixture emitted for overlap, zero-length and boundary laws");
}
