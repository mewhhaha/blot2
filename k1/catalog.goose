// Closed identifiers for the experimental K1 scalar fixture. These do not
// certify an artifact or imply that later K1 operations are implemented.
namespace catalog;

fn edition() -> u8[:] { return "k1"; }
fn semantic_policy() -> u8[:] { return "K1-SEM-POLICY-1"; }
fn optimization_policy() -> u8[:] { return "K1-OPT-POLICY-1"; }
fn wasm_abi() -> u8[:] { return "K1-WASM32-ABI1"; }

// K1-LANG section 11 is the closed category list. Empty means no such ID.
fn diagnostic_count() -> i64 { return 35; }
fn diagnostic(id: i64) -> u8[:] {
    if id == 0 { return "k1_syntax"; }
    if id == 1 { return "k1_unbound_name"; }
    if id == 2 { return "k1_type_mismatch"; }
    if id == 3 { return "k1_kind_mismatch"; }
    if id == 4 { return "k1_nonexhaustive_case"; }
    if id == 5 { return "k1_effect_mismatch"; }
    if id == 6 { return "k1_contract_not_established"; }
    if id == 7 { return "k1_missing_return"; }
    if id == 8 { return "k1_bad_control_target"; }
    if id == 9 { return "k1_bounds_not_established"; }
    if id == 10 { return "k1_arithmetic_not_established"; }
    if id == 11 { return "k1_domain_mismatch"; }
    if id == 12 { return "k1_use_after_move"; }
    if id == 13 { return "k1_usage_not_permitted"; }
    if id == 14 { return "k1_ownership_not_discharged"; }
    if id == 15 { return "k1_lifetime_escape"; }
    if id == 16 { return "k1_loan_conflict"; }
    if id == 17 { return "k1_incomplete_initialization"; }
    if id == 18 { return "k1_invalid_capture"; }
    if id == 19 { return "k1_invalid_owned_payload"; }
    if id == 20 { return "k1_unhandled_result"; }
    if id == 21 { return "k1_recursive_call"; }
    if id == 22 { return "k1_resource_bound"; }
    if id == 23 { return "k1_layout_limit"; }
    if id == 24 { return "k1_environment_capacity"; }
    if id == 25 { return "k1_incomplete_interface"; }
    if id == 26 { return "k1_unsupported_fact"; }
    if id == 27 { return "k1_unsupported_feature"; }
    if id == 28 { return "k1_source_limit"; }
    if id == 29 { return "k1_semantic_limit"; }
    if id == 30 { return "k1_core_limit"; }
    if id == 31 { return "k1_proof_limit"; }
    if id == 32 { return "k1_static_limit"; }
    if id == 33 { return "k1_invalid_artifact"; }
    if id == 34 { return "k1_incompatible_artifact"; }
    return "";
}

fn diagnostic_known(name: u8[:]) -> bool {
    for i in diagnostic_count() {
        if name == diagnostic(i) { return true; }
    }
    return false;
}

// Transient frontend statuses, not portable diagnostic IDs. Unknown statuses
// have no mapping and must not be mistaken for a supported category.
fn source_diagnostic(status: i64) -> u8[:] {
    if status == 1 { return diagnostic(0); }
    if status == 2 { return diagnostic(27); }
    if status == 3 { return diagnostic(1); }
    if status == 4 { return diagnostic(7); }
    if status == 5 { return diagnostic(28); }
    if status == 6 { return diagnostic(8); }
    if status == 7 { return diagnostic(2); }
    return "";
}

// The parameter and return terminator are not primitive operations. This
// registry covers only the scalar operations in the frozen fixture schema,
// not the complete K1 operation registry. IDs are local to this
// experimental in-memory representation and are not serialized artifact IDs.
struct Operation {
    known: bool = false,
    pure: bool = false,
    reads: bool = false,
    writes: bool = false,
    may_fail: bool = false,
    may_diverge: bool = false,
    reserves: bool = false,
    consumes_ownership: bool = false,
    creates_identity: bool = false,
    cleanup: bool = false,
    id: const u8[:] = "",
    operands: const u8[:] = "",
    result: const u8[:] = "",
    effects: const u8[:] = "",
    propositions: const u8[:] = "",
    ownership: const u8[:] = "",
    initialization: const u8[:] = "",
    failure: const u8[:] = "",
    target: const u8[:] = "",
    evaluation: const u8[:] = "",
    lowering: const u8[:] = ""
}

fn operation(id: u8[:]) -> Operation {
    if id == "k1.u32.constant.v1" {
        return Operation {
            known: true,
            pure: true,
            id: "k1.u32.constant.v1",
            operands: "literal U32 bits",
            result: "U32",
            effects: "pure; no reads, writes, failure, divergence, reservation, ownership, identity or cleanup",
            propositions: "none",
            ownership: "no affine transition",
            initialization: "produces an initialized scalar",
            failure: "none",
            target: "Wasm32 i32 constant; preserve all U32 bits",
            evaluation: "U32 literal bits",
            lowering: "i32.const"
        };
    }
    if id == "k1.u32.bitand.v1" {
        return Operation {
            known: true, pure: true, id: "k1.u32.bitand.v1",
            operands: "(U32,U32)", result: "U32",
            effects: "pure; no reads, writes, failure, divergence, reservation, ownership, identity or cleanup",
            propositions: "none", ownership: "no affine transition",
            initialization: "produces an initialized scalar", failure: "none",
            target: "Wasm32 i32; preserve all U32 bits",
            evaluation: "bitwise conjunction", lowering: "i32.and"
        };
    }
    if id == "k1.u32.lt.v1" {
        return Operation {
            known: true, pure: true, id: "k1.u32.lt.v1",
            operands: "(U32,U32)", result: "Bool",
            effects: "pure; no reads, writes, failure, divergence, reservation, ownership, identity or cleanup",
            propositions: "none; expression does not establish edge facts",
            ownership: "no affine transition", initialization: "produces an initialized scalar",
            failure: "none", target: "Wasm32 i32; Bool is 0 or 1",
            evaluation: "unsigned less-than", lowering: "i32.lt_u"
        };
    }
    return Operation {};
}
