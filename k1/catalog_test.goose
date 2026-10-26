import std;
import catalog;

fn require(ok: bool, message: u8[:]) {
    if !ok { abort(str("catalog test: ", message)); }
}

fn main() {
    require(catalog::edition() == "k1", "edition");
    require(catalog::semantic_policy() == "K1-SEM-POLICY-1", "semantic policy");
    require(catalog::optimization_policy() == "K1-OPT-POLICY-1", "optimizer policy");
    require(catalog::wasm_abi() == "K1-WASM32-ABI1", "ABI");
    require(catalog::diagnostic_count() == 35, "closed diagnostic count");
    for i in catalog::diagnostic_count() {
        let name = catalog::diagnostic(i);
        require(name.len > 0 && catalog::diagnostic_known(name), "known diagnostic");
        for j in i { require(name != catalog::diagnostic(j), "duplicate diagnostic"); }
    }
    require(catalog::diagnostic_known("k1_syntax"), "required category k1_syntax");
    require(catalog::diagnostic_known("k1_unbound_name"), "required category k1_unbound_name");
    require(catalog::diagnostic_known("k1_type_mismatch"), "required category k1_type_mismatch");
    require(catalog::diagnostic_known("k1_kind_mismatch"), "required category k1_kind_mismatch");
    require(catalog::diagnostic_known("k1_nonexhaustive_case"), "required category k1_nonexhaustive_case");
    require(catalog::diagnostic_known("k1_effect_mismatch"), "required category k1_effect_mismatch");
    require(catalog::diagnostic_known("k1_contract_not_established"), "required category k1_contract_not_established");
    require(catalog::diagnostic_known("k1_missing_return"), "required category k1_missing_return");
    require(catalog::diagnostic_known("k1_bad_control_target"), "required category k1_bad_control_target");
    require(catalog::diagnostic_known("k1_bounds_not_established"), "required category k1_bounds_not_established");
    require(catalog::diagnostic_known("k1_arithmetic_not_established"), "required category k1_arithmetic_not_established");
    require(catalog::diagnostic_known("k1_domain_mismatch"), "required category k1_domain_mismatch");
    require(catalog::diagnostic_known("k1_use_after_move"), "required category k1_use_after_move");
    require(catalog::diagnostic_known("k1_usage_not_permitted"), "required category k1_usage_not_permitted");
    require(catalog::diagnostic_known("k1_ownership_not_discharged"), "required category k1_ownership_not_discharged");
    require(catalog::diagnostic_known("k1_lifetime_escape"), "required category k1_lifetime_escape");
    require(catalog::diagnostic_known("k1_loan_conflict"), "required category k1_loan_conflict");
    require(catalog::diagnostic_known("k1_incomplete_initialization"), "required category k1_incomplete_initialization");
    require(catalog::diagnostic_known("k1_invalid_capture"), "required category k1_invalid_capture");
    require(catalog::diagnostic_known("k1_invalid_owned_payload"), "required category k1_invalid_owned_payload");
    require(catalog::diagnostic_known("k1_unhandled_result"), "required category k1_unhandled_result");
    require(catalog::diagnostic_known("k1_recursive_call"), "required category k1_recursive_call");
    require(catalog::diagnostic_known("k1_resource_bound"), "required category k1_resource_bound");
    require(catalog::diagnostic_known("k1_layout_limit"), "required category k1_layout_limit");
    require(catalog::diagnostic_known("k1_environment_capacity"), "required category k1_environment_capacity");
    require(catalog::diagnostic_known("k1_incomplete_interface"), "required category k1_incomplete_interface");
    require(catalog::diagnostic_known("k1_unsupported_fact"), "required category k1_unsupported_fact");
    require(catalog::diagnostic_known("k1_unsupported_feature"), "required category k1_unsupported_feature");
    require(catalog::diagnostic_known("k1_source_limit"), "required category k1_source_limit");
    require(catalog::diagnostic_known("k1_semantic_limit"), "required category k1_semantic_limit");
    require(catalog::diagnostic_known("k1_core_limit"), "required category k1_core_limit");
    require(catalog::diagnostic_known("k1_proof_limit"), "required category k1_proof_limit");
    require(catalog::diagnostic_known("k1_static_limit"), "required category k1_static_limit");
    require(catalog::diagnostic_known("k1_invalid_artifact"), "required category k1_invalid_artifact");
    require(catalog::diagnostic_known("k1_incompatible_artifact"), "required category k1_incompatible_artifact");
    require(catalog::diagnostic(-1) == "" && catalog::diagnostic(35) == "", "unknown diagnostic ID");
    require(!catalog::diagnostic_known("") && !catalog::diagnostic_known("k1_fake"), "unknown diagnostic name");
    require(catalog::source_diagnostic(1) == "k1_syntax" &&
            catalog::source_diagnostic(6) == "k1_bad_control_target" &&
            catalog::source_diagnostic(7) == "k1_type_mismatch" &&
            catalog::source_diagnostic(0) == "" && catalog::source_diagnostic(8) == "",
            "frontend status mapping");
    let op = catalog::operation("k1.u32.constant.v1");
    require(op.known && op.result == "U32" && op.operands == "literal U32 bits", "constant schema");
    require(op.pure && !op.reads && !op.writes && !op.may_fail && !op.may_diverge &&
            !op.reserves && !op.consumes_ownership && !op.creates_identity && !op.cleanup,
            "constant effects");
    require(op.propositions == "none" && op.failure == "none" && op.lowering == "i32.const", "constant contract");
    let bitand = catalog::operation("k1.u32.bitand.v1");
    require(bitand.known && bitand.pure && bitand.operands == "(U32,U32)" &&
            bitand.result == "U32" && bitand.lowering == "i32.and" && !bitand.may_fail,
            "bitand contract");
    let less = catalog::operation("k1.u32.lt.v1");
    require(less.known && less.pure && less.operands == "(U32,U32)" &&
            less.result == "Bool" && less.lowering == "i32.lt_u" && !less.may_fail,
            "unsigned less-than contract");
    let add = catalog::operation("k1.u32.add_checked.v1");
    require(add.known && add.pure && !add.may_fail && add.result == "U32" &&
            add.operands == "(U32,U32) with checked AddFits evidence" && add.lowering == "i32.add" &&
            add.propositions == "AddFits(left,right) required before lowering; result is a distinct value",
            "checked addition requires evidence before lowering");
    require(!catalog::operation("").known && !catalog::operation("k1.u32.add.v1").known,
            "unknown operation rejected");
    print("catalog tests passed");
}
