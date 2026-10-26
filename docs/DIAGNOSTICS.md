# K1 diagnostic catalogue

Generated from diagnostic-name consumers. Numeric codes identify the producing
subsystem; the `k1_*` category is the stable source-facing contract. Imported
artifact failures wrap their validation cause as `k1_invalid_artifact`.

| Code | Category | Producer |
| ---: | --- | --- |
| 1000 | `k1_syntax` | `frontend.goose` |
| 1001 | `k1_unbound_name` | `frontend.goose` |
| 1002 | `k1_type_mismatch` | `frontend.goose` |
| 1003 | `k1_kind_mismatch` | `frontend.goose` |
| 1004 | `k1_nonexhaustive_case` | `frontend.goose` |
| 1005 | `k1_effect_mismatch` | `frontend.goose` |
| 1006 | `k1_contract_not_established` | `frontend.goose` |
| 1007 | `k1_missing_return` | `frontend.goose` |
| 1008 | `k1_bad_control_target` | `frontend.goose` |
| 1009 | `k1_bounds_not_established` | `frontend.goose` |
| 1010 | `k1_arithmetic_not_established` | `frontend.goose` |
| 1011 | `k1_domain_mismatch` | `frontend.goose` |
| 1012 | `k1_use_after_move` | `frontend.goose` |
| 1013 | `k1_usage_not_permitted` | `frontend.goose` |
| 1014 | `k1_ownership_not_discharged` | `frontend.goose` |
| 1015 | `k1_lifetime_escape` | `frontend.goose` |
| 1016 | `k1_loan_conflict` | `frontend.goose` |
| 1017 | `k1_incomplete_initialization` | `frontend.goose` |
| 1018 | `k1_invalid_capture` | `frontend.goose` |
| 1019 | `k1_invalid_owned_payload` | `frontend.goose` |
| 1020 | `k1_unhandled_result` | `frontend.goose` |
| 1021 | `k1_recursive_call` | `frontend.goose` |
| 1022 | `k1_resource_bound` | `frontend.goose` |
| 1023 | `k1_layout_limit` | `frontend.goose` |
| 1024 | `k1_environment_capacity` | `frontend.goose` |
| 1025 | `k1_incomplete_interface` | `frontend.goose` |
| 1026 | `k1_unsupported_fact` | `frontend.goose` |
| 1027 | `k1_unsupported_feature` | `frontend.goose` |
| 1028 | `k1_source_limit` | `frontend.goose` |
| 1029 | `k1_semantic_limit` | `frontend.goose` |
| 1030 | `k1_core_limit` | `frontend.goose` |
| 1031 | `k1_proof_limit` | `frontend.goose` |
| 1032 | `k1_static_limit` | `frontend.goose` |
| 2003 | `k1_type_mismatch` | `validate.goose` |
| 2004 | `k1_kind_mismatch` | `validate.goose` |
| 2005 | `k1_nonexhaustive_case` | `validate.goose` |
| 2006 | `k1_effect_mismatch` | `validate.goose` |
| 2007 | `k1_contract_not_established` | `validate.goose` |
| 2008 | `k1_missing_return` | `validate.goose` |
| 2010 | `k1_bounds_not_established` | `validate.goose` |
| 2011 | `k1_arithmetic_not_established` | `validate.goose` |
| 2012 | `k1_domain_mismatch` | `validate.goose` |
| 2013 | `k1_use_after_move` | `validate.goose` |
| 2014 | `k1_usage_not_permitted` | `validate.goose` |
| 2015 | `k1_ownership_not_discharged` | `validate.goose` |
| 2016 | `k1_lifetime_escape` | `validate.goose` |
| 2017 | `k1_loan_conflict` | `validate.goose` |
| 2018 | `k1_incomplete_initialization` | `validate.goose` |
| 2019 | `k1_invalid_capture` | `validate.goose` |
| 2020 | `k1_invalid_owned_payload` | `validate.goose` |
| 2021 | `k1_unhandled_result` | `validate.goose` |
| 2023 | `k1_resource_bound` | `validate.goose` |
| 2024 | `k1_layout_limit` | `validate.goose` |
| 2025 | `k1_environment_capacity` | `validate.goose` |
| 2026 | `k1_incomplete_interface` | `validate.goose` |
| 2027 | `k1_unsupported_fact` | `validate.goose` |
| 2028 | `k1_unsupported_feature` | `validate.goose` |
| 2030 | `k1_semantic_limit` | `validate.goose` |
| 2031 | `k1_core_limit` | `validate.goose` |
| 2032 | `k1_proof_limit` | `validate.goose` |
| 2034 | `k1_invalid_artifact` | `validate.goose` |
| 2035 | `k1_incompatible_artifact` | `validate.goose` |
| 4000 | `k1_io_error` | `loader.goose` |
| 4001 | `k1_package_escape` | `loader.goose` |
| 4002 | `k1_import_cycle` | `loader.goose` |
| 4003 | `k1_duplicate_import` | `loader.goose` |
| 4004 | `k1_module_limit` | `loader.goose` |
| 4005 | `k1_edition_mismatch` | `loader.goose` |
| 4006 | `k1_invalid_option` | `loader.goose` |
| 4007 | `k1_invalid_export` | `loader.goose` |
| 4008 | `k1_phase_violation` | `loader.goose` |
| 4009 | `k1_cancelled` | `loader.goose` |
| 4010 | `k1_allocation_failure` | `loader.goose` |
| 4011 | `k1_invalid_manifest` | `loader.goose` |
| 4012 | `k1_layout_limit` | `loader.goose` |
| 4013 | `k1_resource_contract` | `loader.goose` |
| 4014 | `k1_formatter_invariant` | `loader.goose` |
| 4015 | `k1_optimizer_invariant` | `loader.goose` |
| 4016 | `k1_interface_fingerprint_limit` | `loader.goose` |
| 4020 | `k1_static_incompatible` | `loader.goose` |
| 4021 | `k1_static_limit` | `loader.goose` |
| 4022 | `k1_static_limit` | `loader.goose` |
| 4023 | `k1_static_limit` | `loader.goose` |
| 4024 | `k1_static_invalid_core` | `loader.goose` |
| 4025 | `k1_semantic_limit` | `loader.goose` |

Syntax-only parser failures also carry a byte range and explanatory message.
Tests assert categories and relevant spans, not incidental wording.
