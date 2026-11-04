// Packed 64-bit native footprints, from Goose spec C.2 and these exact source
// records. These count storage without serializing or exposing host pointers.
// Wire encodings keep their own independent explicit widths.
namespace blot_host_layout;
let pointer: i64 = 8;
let slice: i64 = pointer + 8;
let binding_ref: i64 = 8;
let evaluator_options: i64 = 4 + 7 * 8;
let solved_evidence: i64 = 3 * slice;
let principal_input_key: i64 = 2 + 10 * slice;
let principal_record: i64 = binding_ref + evaluator_options + 1 + principal_input_key + solved_evidence;
let specialization_member: i64 = 2 * slice + 1 + binding_ref + 4 + 8 * 8 + 4 * 8 + 1;
let specialization_record: i64 = 1 + specialization_member + slice + 3 * 4 + evaluator_options + 9 * 8 + 1 + 6 * slice;
let refinement_root: i64 = 1 + binding_ref;
let refinement_key: i64 = refinement_root + 4 + 2 * slice + evaluator_options + 8;
let refinement_record: i64 = refinement_key + specialization_record + solved_evidence;
let type_scheme: i64 = 4 + 5 * 8;
let constant_inputs: i64 = 2 * slice;
let source_interface: i64 = 4 + 1 + 8 + 1;
let constant_query: i64 = 1 + 3 * 4 + binding_ref + source_interface + pointer + 2 * 8;
let constant_judgment: i64 = 1 + 4 * 4 + type_scheme + 8 + 2 + 2 * constant_inputs + slice;
let constant_event: i64 = 1 + 5 * 8;
let constant_record: i64 = slice + 1 + 8 + binding_ref + 4 + evaluator_options + 2 * slice + constant_inputs + pointer;
