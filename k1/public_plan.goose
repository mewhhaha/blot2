// Experimental scalar lowering-plan envelope; not a Wasm certificate or
// authority to execute. The expected producer, target geometry and ABI digest
// must be independently established by the caller, and the executable must be
// regenerated from independently checked Core. No supplied machine bytes are
// accepted here. The complete manifest, helper-role certificate, host bridge,
// resource preflight, shared work receipt and transactional publication remain
// separate, mandatory obligations.
//
// K1PUBP02: magic[8], u32 total, u32 payload length, the same compatibility
// header as public_function, payload, 32-byte plan digest. Payload is
// "K1PUBPL2", u32 function semantic length, 32-byte interface fingerprint,
// 32-byte function fingerprint, exact function semantic bytes and thirteen
// u32 target fields. Exact linked bytes must match even if digests collide.
// Unlike semantic interface/body fingerprints, the
// plan digest covers the compatibility header as well as the target payload.
namespace public_plan;
import catalog;
import blake3;
import scalar_core;
import public_artifact;
import public_frontend;
import public_function;

struct Decoded { status: i64 = 1, opcode: u32 = 0, pages: u32 = 0 }
// For v02 the plan is exactly function_length + 88 bytes. Reject by checked
// subtraction before source revalidation or creating any output candidate.
fn fits_function(function_length: i64) -> bool {
    return function_length >= 0 && function_length <= 16777216 - 88;
}
fn opcode(core: scalar_core::ScalarCore) -> u32 {
    if !scalar_core::validate_structure(core) { return 0; }
    let result = core.values[core.result_id];
    if result.producer == 1 { return 0x20; } // local.get
    if result.producer == 2 { return 0x41; } // i32.const
    if result.producer == 3 && result.op_id == 1 { return 0x71; } // i32.and
    if result.producer == 3 && result.op_id == 2 { return 0x49; } // i32.lt_u
    return 0;
}
fn fields(out: u8[>..]&, pages: u32, selected: u32) {
    // Canonical scalar ABI: i32 argument/result, env first, no result slot,
    // adapters, imported helpers, allocation or memory.grow; one fixed memory.
    for n in [1, 1, 1, 0, 0, 0, 0, 0, pages, pages, 1, 0, selected] {
        public_artifact::put32(out, n as u32);
    }
}
fn encode(source: u8[:], candidate: public_frontend::Candidate, interface: u8[:],
          function: u8[:], package: u8[:], module: u8[:], declaration: u8[:],
          abi: u8[:], pages: u32) -> u8[>..] {
    var out: u8[>..] = [];
    if !fits_function(function.len) || pages == 0 || pages > 16384 ||
       public_function::verify_source(function, source, candidate, interface,
                                      package, module, declaration, abi) != 0 { return out; }
    let chosen = opcode(candidate.core);
    if chosen == 0 { return out; }
    let start = 16 + public_artifact::header_size();
    let function_start = 16 + public_artifact::header_size();
    let function_length: i64 = public_artifact::get32(function, 12);
    if function_length > 16777216 - start - 128 - 32 { return out; }
    let payload_len = 128 + function_length;
    let total = start + payload_len + 32;
    out.append("K1PUBP02"); public_artifact::put32(out, total as u32);
    public_artifact::put32(out, payload_len as u32); public_function::header(out, abi);
    out.append("K1PUBPL2"); public_artifact::put32(out, function_length as u32);
    out.append(interface[interface.len - 32..]);
    let function_digest = function_start + function_length;
    out.append(function[function_digest..function_digest + 32]);
    out.append(function[function_start..function_digest]);
    fields(out, pages, chosen);
    let digest = blake3::hash(out[16..]); out.append(digest);
    return out;
}
fn decode(bytes: u8[:], interface: u8[:], function: u8[:], package: u8[:],
          module: u8[:], declaration: u8[:], abi: u8[:], pages: u32) -> Decoded {
    let function_value = public_function::decode(function, interface, package, module, declaration, abi);
    if function_value.status != 0 { return Decoded { status: function_value.status }; }
    if pages == 0 || pages > 16384 { return Decoded {}; }
    let selected = opcode(function_value.core);
    if selected == 0 { return Decoded {}; }
    let start = 16 + public_artifact::header_size();
    if bytes.len > 16777216 || bytes.len < start + 128 + 32 || bytes[0..8] != "K1PUBP02" ||
       public_artifact::get32(bytes, 8) != bytes.len { return Decoded {}; }
    let payload_len: i64 = public_artifact::get32(bytes, 12);
    if payload_len != bytes.len - start - 32 || payload_len < 128 { return Decoded {}; }
    let end = start + payload_len;
    if !public_function::header_valid(bytes, start, abi) { return Decoded { status: 2 }; }
    if bytes[start..start + 8] != "K1PUBPL2" ||
       bytes[start + 12..start + 44] != interface[interface.len - 32..] { return Decoded {}; }
    let function_start = 16 + public_artifact::header_size();
    let function_length: i64 = public_artifact::get32(bytes, start + 8);
    if function_length != payload_len - 128 || function_length != public_artifact::get32(function, 12) { return Decoded {}; }
    let function_digest = function_start + function_length;
    let link_start = start + 76;
    let link_end = link_start + function_length;
    if !public_function::same_link(bytes[link_start..link_end], bytes[start + 44..start + 76],
                                  function[function_start..function_digest],
                                  function[function_digest..function_digest + 32]) { return Decoded {}; }
    var p = link_end;
    let exact: u32[13] = [1, 1, 1, 0, 0, 0, 0, 0, pages, pages, 1, 0, selected];
    for value in exact { if public_artifact::get32(bytes, p) != value { return Decoded {}; } p += 4; }
    if p != end { return Decoded {}; }
    if blake3::hash(bytes[16..end])[..] != bytes[end..] { return Decoded { status: 3 }; }
    return Decoded { status: 0, opcode: selected, pages: pages };
}
fn verify_source(bytes: u8[:], source: u8[:], candidate: public_frontend::Candidate,
                 interface: u8[:], function: u8[:], package: u8[:], module: u8[:],
                 declaration: u8[:], abi: u8[:], pages: u32) -> i64 {
    if public_function::verify_source(function, source, candidate, interface,
                                      package, module, declaration, abi) != 0 { return 1; }
    return decode(bytes, interface, function, package, module, declaration, abi, pages).status;
}
