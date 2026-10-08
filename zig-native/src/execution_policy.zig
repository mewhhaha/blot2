//! Execution choices are owned by a compilation/session. They never grant
//! cache validity; source, evidence, executable and value checks remain distinct.
//! Tests may override individual fields to compare the reference implementation.
pub const Policy = struct {
    codegen_tier: @import("compilation_tier.zig").Tier = .optimized,
    share_machine_code: bool = false,
    codegen_workers: u8 = 1,
    semantic_workers: u8 = 1,
    /// Experimental resolved SSA for closed straight-line scalar bodies.
    resolve_scalar_bodies: bool = false,
    /// Same-binary execution policies; none grants semantic cache admission.
    reuse_solver_capacity: bool = true,
    reuse_region_scratch: bool = true,
    reuse_callable_definitions: bool = true,
    reuse_evidence_imports: bool = true,
    reuse_closed_source_types: bool = true,
    reuse_local_refinements: bool = true,
    /// Independently solve closed first-order call boundaries. Qualification
    /// remains opt-in while region/work-limit behavior is being measured.
    split_closed_calls: bool = false,
    /// Successful root conversions within an immutable emitter mapping region.
    memoize_layout_roots: bool = true,
    reuse_refinements: bool = false,
    reuse_body_proof_cutoff: bool = false,
    /// Query-only differential runs still retain principal/refinement inputs.
    reuse_code_fragments: bool = true,
    /// Retain the principal prepasses already executed by a fresh backend.
    capture_fresh_principals: bool = false,
    reuse_projected_principals: bool = false,
    reuse_declaration_principals: bool = false,
    reuse_unaffected_modules: bool = false,
    optimize_completed_query_admission: bool = false,
    reuse_completed_specializations: bool = false,
    reuse_source_effect_queries: bool = false,
    reuse_query_graph_scratch: bool = false,
    share_query_gate: bool = false,
    reuse_fallback_check: bool = false,
    reuse_fallback_core: bool = false,
    /// Recheck changed modules and importers while retaining exact admitted siblings.
    reuse_module_frontends: bool = false,
    /// Keep the already checked/lowered entry across a mixed seed rebuild.
    reuse_prepared_entry: bool = false,
    reuse_entry_interface_cutoff: bool = false,
    reuse_module_interface_cutoff: bool = false,
    share_dependency_storage: bool = false,
    reuse_dependency_validation: bool = false,
    /// Offer retained inference receipts after rebuilding a dependency seed.
    /// Catalog, declaration and dynamic-read checks remain authoritative.
    reuse_rebuilt_queries: bool = false,
    reuse_rebuilt_code: bool = false,
    reuse_optimized_bodies: bool = false,
    prepare_checked_query_importer: bool = false,
    reuse_equivalent_validation: bool = false,
    transport_source_templates: bool = false,
    principal_reuse: bool = true,
    principal_graph_mode: @import("principal_evidence_reuse.zig").GraphMode = .primitive,
    /// Private exact-input output reuse. Production policy remains unchanged.
    reuse_unchanged_output: bool = false,

    stamp_reuse: enum { none, same_storage, exact } = .exact,

    pub const reference: Policy = .{};
    pub const project: Policy = .{
        .capture_fresh_principals = true,
        .reuse_projected_principals = true,
        .reuse_declaration_principals = true,
        .reuse_unaffected_modules = true,
        .reuse_refinements = true,
        .reuse_body_proof_cutoff = true,
        .optimize_completed_query_admission = true,
        .reuse_completed_specializations = true,
        .reuse_source_effect_queries = true,
        .reuse_query_graph_scratch = true,
        .share_query_gate = true,
        .reuse_fallback_check = true,
        .reuse_fallback_core = true,
        .reuse_module_frontends = true,
        .reuse_prepared_entry = true,
        .reuse_entry_interface_cutoff = true,
        .reuse_module_interface_cutoff = true,
        .share_dependency_storage = true,
        .reuse_dependency_validation = true,
        .reuse_rebuilt_queries = true,
        .reuse_rebuilt_code = true,
        .reuse_optimized_bodies = true,
        .prepare_checked_query_importer = true,
        .reuse_equivalent_validation = true,
    };
};
