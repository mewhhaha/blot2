import owned_scalar_source;
import owned_scalar_verify;
import owned_scalar_runtime;
fn check(source: u8[:]) {
    let original = owned_scalar_source::parse(source); assert(original.status == 0);
    var bytes: u8[>..] = []; bytes.append(source);
    let replacements: u8[7] = [0, ' ', '\n', '#', 'x', '9', 255];
    var clock = owned_scalar_runtime::Clock {};
    for i in bytes.len {
      let previous = bytes[i];
      for value in replacements {
        bytes[i] = value;
        let parsed = owned_scalar_source::parse(bytes);
        if parsed.status == 0 { assert(owned_scalar_verify::verify(bytes, parsed.core)); }
        let same = owned_scalar_verify::verify(bytes, original.core);
        var state = owned_scalar_runtime::State {};
        assert(owned_scalar_runtime::initialize(state,clock));
        let memory = copy(state.memory); let result = owned_scalar_runtime::construct(state,bytes,original.core);
        if same {
          assert(parsed.status == 0 && parsed.core.work_bytes == original.core.work_bytes && parsed.core.terminal == original.core.terminal && parsed.core.value == original.core.value);
          assert(result.status == (if original.core.terminal == 1 { 0 } else { 1 }));
        } else {
          assert(result.status == 2 && state.slot == 0 && state.slots[0].state == 0 && state.slots[0].generation == 0 && state.bitmap[0] == 0 && state.memory[..] == memory[..]);
        }
      }
      bytes[i] = previous;
    }
}
fn main() {
  check("owned@[ScalarPayload[_],#Cancelled](3840) as r free in do:\n  seal(free,4294967295)\n");
  check("owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  abort(free,#Cancelled)\n");
  print("source/Core mutation and initialized-state publication controls passed");
}
