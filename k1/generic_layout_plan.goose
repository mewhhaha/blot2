// Restricted layout premises and trusted pre-lowering slot checks. These
// helpers do not establish semantic types, loans, initialization or producer
// identity; the caller supplies that compiler-checked authority.
namespace generic_layout_plan;
import generic_dictionary;
import generic_dictionary_verify;
import generic_identity;
import generic_identity_verify;
import blake3;

struct Plan { status: i64 = 1, body_key: u8[32] = [0; 32], size: u32 = 0, alignment: u32 = 0, schema_id: u32 = 0 }
struct ResultLayout { status: i64 = 1, size: u32 = 0, alignment: u32 = 0 }
// One checked body has one source-derived key across concrete substitutions;
// its dictionary remains tied to an exact independently supplied schema.
fn instantiate(source: u8[:], body: generic_identity::Body, concrete: generic_dictionary::Result&,
               expected_schema: u8[:], expected_id: u32) -> Plan {
    if !generic_identity_verify::verify(source, body) ||
       !generic_dictionary_verify::verify(concrete, expected_schema, expected_id) { return Plan {}; }
    return Plan { status: 0, body_key: blake3::hash(source), size: concrete.dictionary.size,
        alignment: concrete.dictionary.alignment, schema_id: expected_id };
}
// Result<T,E> is a four-byte tag and the larger payload in this all-word
// restricted schema. No body is rechecked to compute this premise.
fn result_layout(left: generic_dictionary::Result&, left_schema: u8[:], left_id: u32,
                 right: generic_dictionary::Result&, right_schema: u8[:], right_id: u32) -> ResultLayout {
    if !generic_dictionary_verify::verify(left, left_schema, left_id) ||
       !generic_dictionary_verify::verify(right, right_schema, right_id) { return ResultLayout {}; }
    let largest = if left.dictionary.size > right.dictionary.size { left.dictionary.size } else { right.dictionary.size };
    if largest > 252 { return ResultLayout { status: 2 }; }
    return ResultLayout { status: 0, size: largest + 4, alignment: 4 };
}
fn plain_element(candidate: generic_dictionary::Result&, schema: u8[:], id: u32) -> bool {
    return generic_dictionary_verify::verify(candidate, schema, id) &&
        (candidate.dictionary.flags & 1) != 0 && candidate.dictionary.size <= 64;
}
fn disjoint(a: u64, alen: u64, b: u64, blen: u64) -> bool {
    if alen == 0 || blen == 0 { return true; }
    return a + alen <= b || b + blen <= a;
}
// Caller-supplied booleans represent trusted compiler evidence, not values
// supplied by a source program or host. A zero-sized value requires no input
// or result memory; the dictionary is still a real 16-byte immutable record.
fn slots(plan: Plan, input: u32, output: u32, dict: u32, memory_bytes: u64,
         input_initialized: bool, result_exclusive: bool) -> bool {
    if plan.status != 0 || plan.size > 256 || (plan.alignment != 1 && plan.alignment != 4) ||
       memory_bytes > 4294967296 || !input_initialized || !result_exclusive ||
       dict % 4 != 0 || (input % plan.alignment) != 0 || (output % plan.alignment) != 0 { return false; }
    let p = input as u64; let q = output as u64; let d = dict as u64; let n = plan.size as u64;
    if p + n > memory_bytes || q + n > memory_bytes || d + 16 > memory_bytes { return false; }
    return disjoint(p, n, q, n) && disjoint(p, n, d, 16) && disjoint(q, n, d, 16);
}
// This public-facing fixture helper reconstructs its plan from the checked
// source/body and the independently expected dictionary schema. It does not
// trust a caller-supplied Plan's size, status, or body hash as authority.
fn slots_checked(source: u8[:], body: generic_identity::Body, concrete: generic_dictionary::Result&,
                 schema: u8[:], id: u32, input: u32, output: u32, dict: u32,
                 memory_bytes: u64, input_initialized: bool, result_exclusive: bool) -> bool {
    let plan = instantiate(source, body, concrete, schema, id);
    return slots(plan, input, output, dict, memory_bytes, input_initialized, result_exclusive);
}
