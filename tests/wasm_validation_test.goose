import src.wasm;
import src.wasm_validate;
fn test_wasm_validation() {
  let params=[0x7f as u8,0x7d];
  let signatures=[wasmcheck::Signature {Span {0,0},0},wasmcheck::Signature {Span {0,1},0x7f},wasmcheck::Signature {Span {1,1},0x7d},wasmcheck::Signature {Span {0,0},0x7f}];
  let functions=[1 as u32,2,0];
  assert(wasmcheck::body([0,0x20,0,0x0b],signatures,params,functions,1,1));
  assert(!wasmcheck::body([0,0x43,0,0,0,0,0x0b],signatures,params,functions,1,1));
  assert(!wasmcheck::body([0,0x41,1,0x0b],signatures,params,functions,0,1));
  assert(!wasmcheck::body([0,0x6a,0x1a,0x0b],signatures,params,functions,0,1));
  assert(!wasmcheck::body([0,0x41,1,0x10,1,0x1a,0x0b],signatures,params,functions,0,1));
  assert(wasmcheck::body([0,0x41,7,0x41,0,0x11,1,0,0x1a,0x0b],signatures,params,functions,0,1));
  assert(!wasmcheck::body([0,0x41,7,0x41,0,0x11,2,0,0x1a,0x0b],signatures,params,functions,0,1));
  assert(!wasmcheck::body([0,0x41,7,0x41,0,0x11,1,1,0x1a,0x0b],signatures,params,functions,0,1));
  assert(wasmcheck::body([0,0x41,1,0x04,0x7f,0x41,2,0x05,0x41,3,0x0b,0x0b],signatures,params,functions,3,1));
  assert(!wasmcheck::body([0,0x41,1,0x04,0x7f,0x41,2,0x0b,0x0b],signatures,params,functions,3,1));
  assert(!wasmcheck::body([0,0x41,1,0x04,0x40,0x05,0x05,0x0b,0x0b],signatures,params,functions,0,1));
  assert(wasmcheck::body([0,0x02,0x7f,0x41,7,0x41,1,0x0d,0,0x0b,0x0b],signatures,params,functions,3,1));
  assert(!wasmcheck::body([0,0x02,0x7f,0x43,0,0,0,0,0x0c,0,0x0b,0x0b],signatures,params,functions,3,1));
  assert(wasmcheck::body([0,0x00,0x0b],signatures,params,functions,3,1));
  assert(!wasmcheck::body([0,0x41,0,0x40,0,0x1a,0x0b],signatures,params,functions,0,1));
  assert(wasmcheck::body([0,0x43,0x40,0x40,0x40,0x40,0x1a,0x0b],signatures,params,functions,0,1));
  assert(!wasmcheck::body([0,0x41,0xff,0xff,0xff,0xff,0x0f,0x1a,0x0b],signatures,params,functions,0,1));
  let map,valid=runtime::make_map(runtime::Config {}); assert(valid);
  with_core() { core => wasm::with_module(map) { m =>
    let sig=wasm::signature(m,[],0); let index=wasm::function(m,sig,[0,0x0b]);
    m.functions[index].role=1; m.functions[index].depth=1;
    var encoded:u8[>..]=[]; wasm::encode(m,encoded);
    var certificate:u8[>..]=[]; var diagnostics:Diagnostic[>..]=[];
    assert(wasm::certificate(core_view(core),m,encoded,certificate,diagnostics));
    // Altering only the final encoded body must fail even while the encoder's
    // original body buffer and inventory remain internally consistent.
    encoded[encoded.len-1]=0x00; certificate.resize(0); diagnostics.resize(0);
    assert(!wasm::certificate(core_view(core),m,encoded,certificate,diagnostics));
    assert(diagnostics[0].code==3038);
    encoded[encoded.len-1]=0x0b; m.functions[index].role=0; certificate.resize(0); diagnostics.resize(0);
    assert(!wasm::certificate(core_view(core),m,encoded,certificate,diagnostics)); assert(diagnostics[0].code==3030);
  } }
}
