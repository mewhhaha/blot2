// Semantic scope edges bind to invocation-local labels and cleanup marks.
namespace blot_backend_resolved_flow;
import check.core;
import .runtime_ir;
import runtime.runtime_cleanup;
import support.option;
enum ExitKind { return_,break_,continue_,request_return,request_break }
struct Exit {
    kind: ExitKind,source: u32,target: u32,label: u32,cleanup: blot_runtime_runtime_cleanup::Mark,template_result: bool = false,value: u32 = 0,result_role: blot_backend_runtime_ir::Role = blot_backend_runtime_ir::ROLE_scalar,
    values: const u32[:] = default<const u32[:]>(),carries: const blot_check_core::LoopCarry[:] = default<const blot_check_core::LoopCarry[:]>(),
}
fn depthAt(exit: Exit,labels: u32) -> u32 { labels - 1 - exit.label }
struct SymbolicExit { kind: ExitKind,source: u32,target: u32,template_result: bool = false,value: u32 = 0,result_role: blot_backend_runtime_ir::Role = blot_backend_runtime_ir::ROLE_scalar,values: const u32[:] = default<const u32[:]>(),carries: const blot_check_core::LoopCarry[:] = default<const blot_check_core::LoopCarry[:]>() }
fn bind(exit: SymbolicExit,label: u32,cleanup: blot_runtime_runtime_cleanup::Mark) -> Exit { Exit { kind: exit.kind,source: exit.source,target: exit.target,label: label,cleanup: cleanup,template_result: exit.template_result,value: exit.value,result_role: exit.result_role,values: exit.values,carries: exit.carries } }
struct RequestLoop { node: u32,arms: const blot_check_core::RequestArm[:],operations: const u32[:],exited: SymbolicExit,broken: SymbolicExit,completion_pattern: u32,completion_body: u32 }
struct Join { node: u32,result: blot_support::Option<blot_backend_runtime_ir::ValueType>,merges: const blot_check_core::Merge[:],else_arm: bool = false }
struct Match { join: Join,inputs: const u32[:],arms: const blot_check_core::MatchArm[:],statement: bool }
struct Collection { input: u32,incoming: u32,iteration: u32,rest: u32,receiver: u32,pattern: u32 }
struct Loop { node: u32,kind: blot_check_core::LoopKind,carries: const blot_check_core::LoopCarry[:],carry_roles: u64 = 0,collection: blot_support::Option<Collection>,roots: bool = true,refutable: bool,diverges: bool }
reusable[] var owned_operations: u32[>..] = [];
fn allocateOperations(count: i64) -> u32[:] { owned_operations.alloc_slice(count) }
fn copyOperations(values: const u32[:]) -> const u32[:] { if values.len == 0 { return default<const u32[:]>(); } let out = owned_operations.alloc_slice(values.len); for value,index in values { out[index] = value; } return out; }
fn deinit(request: RequestLoop&) { if request.operations.len != 0 { owned_operations.free_slice(request.operations); } request.operations = []; }
