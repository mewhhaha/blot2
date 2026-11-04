namespace blot_execution_policy;
import backend.storage_plan;
import compilation_tier;

struct Policy {
    storage: blot_backend_storage_plan::Budgets = default<blot_backend_storage_plan::Budgets>(),
    codegen_tier: blot_compilation_tier::Tier = blot_compilation_tier::Tier.optimized,
    share_machine_code: bool = false,
    memory_profile: bool = false,
    require_collector_free: bool = false,
    codegen_workers: u8 = 1,
    semantic_workers: u8 = 1,
    frontend_workers: u8 = 4,
    semantic_components: bool = false,
}
