// Copied source packets isolate worker storage; caller takes results in order.
namespace blot_check_parallel_lowering;
import check.check_packet_owner;
import check.core;
import parse.ast;
import parse.symbols;
import reuse.dependency_payload;
import support.error;
import support.option;

import .check;
import .core_builder;
type Error = blot_error::Error;
let min_nodes: i64 = 4096;
struct Input { tree: blot_parse_ast::Tree, checked: blot_check_check::Checked }
struct Slot { requested: bool = false, taken: bool = false }
// Executor is statically bound. It owns flat packet queues and worker handles;
// prepare copies every borrowed input, lower decodes into lexical owners and
// invokes CoreBuilder.lowerWithOrigins, finish joins before returning results.
reusable[] var slot_runs:Slot[>..]=[];
struct Batch<Executor> { executor: Executor?=null, slots: Slot[:]=default<Slot[:]>(), workers: i64 = 1, active: bool = false }
fn run<Executor>(executor: Executor&, io_available: bool, requested: u8, names: const blot_parse_symbols::Pool&, origins: blot_check_check::ModuleOrigins, inputs: const blot_support::Option<Input>[:]) -> blot_support::Option<Batch<Executor>>, Error { return runAbove(executor, io_available, requested, names, origins, inputs, min_nodes); }
fn runAbove<Executor>(executor: Executor&, io_available: bool, requested: u8, names: const blot_parse_symbols::Pool&, origins: blot_check_check::ModuleOrigins, inputs: const blot_support::Option<Input>[:], minimum_nodes: i64) -> blot_support::Option<Batch<Executor>>, Error {
    if requested <= 1 || !io_available { return blot_support::none<Batch<Executor>>(), blot_error::Error.none; } var jobs: i64 = 0; var nodes: i64 = 0;
    for optional in inputs { if optional.present { jobs += 1; let amount = optional.value.tree.nodes.len; if amount > 0x7fffffffffffffff - nodes { nodes = 0x7fffffffffffffff; } else { nodes += amount; } } }
    if jobs < 2 || nodes < minimum_nodes { return blot_support::none<Batch<Executor>>(), blot_error::Error.none; }
    var order: u32[>..<]=[]; for input, index in inputs { if input.present { order.push(index as u32); } }
    // Stable insertion order implements source largest-first then source index.
    for ignored in 1..order.len { var index = ignored; while index != 0 { let left = order[index - 1]; let right = order[index]; let l = inputs[left].value.tree.nodes.len; let r = inputs[right].value.tree.nodes.len; if l > r || (l == r && left < right) { break; } order[index - 1] = right; order[index] = left; index -= 1; } }
    let slots=slot_runs.alloc_slice(inputs.len);for input,index in inputs {slots[index]=Slot{requested:input.present,..};}
    // All owner copies finish before any worker starts. Failed packet creation
    // rolls back the entire prepared batch and leaves the caller's inputs live.
    let err = executor.begin(inputs.len); if err != blot_error::Error.none {slot_runs.free_slice(slots);return blot_support::none<Batch<Executor>>(), err; }
    for index in order { let input = inputs[index].value; let err = executor.prepare(index, input.tree, names, input.checked, origins); if err != blot_error::Error.none { executor.cancelAndJoin(); executor.deinit(); slot_runs.free_slice(slots); return blot_support::none<Batch<Executor>>(), err; } }
    let count = min(requested as i64, min(jobs, 16));
    // The full request image already exists. All requested process workers now
    // execute copied packets; this boundary never fabricates a worker start.
    let err = executor.execute(order[..],count); if err != blot_error::Error.none { executor.cancelAndJoin(); executor.deinit(); slot_runs.free_slice(slots); return blot_support::none<Batch<Executor>>(),err; }
    return blot_support::some(Batch<Executor> { executor:executor, slots:slots, workers:count, active:true , ..}), blot_error::Error.none;
}
fn take<Executor>(self_: Batch<Executor>&, index: i64) -> blot_reuse_dependency_payload::Owned<blot_check_core::Module>, Error {
    let executor .= self_.executor;let slots=self_.slots;assert(executor);
    assert(self_.active && index >= 0 && index < slots.len && slots[index].requested && !slots[index].taken);
    slots[index].taken = true; return executor.take(index);
}
fn deinit<Executor>(self_:Batch<Executor>&) {
 if !self_.active {return;}let executor .= self_.executor;assert(executor);executor.cancelAndJoin();let count=self_.slots.len;
 for index in 0..count {let slot=self_.slots[index];if slot.requested && !slot.taken {executor.discard(index);}}
 executor.deinit();slot_runs.free_slice(self_.slots);self_.executor .= null;self_.slots=default<Slot[:]>();self_.active=false;
}
