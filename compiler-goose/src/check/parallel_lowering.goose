// Copied source packets isolate worker storage; caller takes results in order.
namespace blot_check_parallel_lowering;
import support.error;
import support.option;
import .core;
import .check;
import .core_builder;
import reuse.dependency_payload;
import parse.ast;
import parse.symbols;
type Error = blot_error::Error;
let min_nodes: i64 = 4096;
struct Input { tree: blot_parse_ast::Tree, checked: blot_check_check::Checked }
struct Slot { requested: bool = false, taken: bool = false }
// Executor is statically bound. It owns flat packet queues and worker handles;
// prepare copies every borrowed input, lower decodes into lexical owners and
// invokes CoreBuilder.lowerWithOrigins, finish joins before returning results.
struct Batch<Executor> { executor: Executor?=null, slots: Slot[>..<]?=null, workers: i64 = 1, active: bool = false }
fn run<Executor>(executor: Executor&, io_available: bool, requested: u8, names: const blot_parse_symbols::Pool&, origins: blot_check_check::ModuleOrigins, inputs: const blot_support::Option<Input>[:], slots: Slot[>..<]&) -> blot_support::Option<Batch<Executor>>, Error { return runAbove(executor, io_available, requested, names, origins, inputs, slots, min_nodes); }
fn runAbove<Executor>(executor: Executor&, io_available: bool, requested: u8, names: const blot_parse_symbols::Pool&, origins: blot_check_check::ModuleOrigins, inputs: const blot_support::Option<Input>[:], slots: Slot[>..<]&, minimum_nodes: i64) -> blot_support::Option<Batch<Executor>>, Error {
    if requested <= 1 || !io_available { return blot_support::none<Batch<Executor>>(), Error.none; } var jobs: i64 = 0; var nodes: i64 = 0;
    for optional in inputs { if optional.present { jobs += 1; let amount = optional.value.tree.nodes.len; if amount > 0x7fffffffffffffff - nodes { nodes = 0x7fffffffffffffff; } else { nodes += amount; } } }
    if jobs < 2 || nodes < minimum_nodes { return blot_support::none<Batch<Executor>>(), Error.none; }
    var order: u32[>..<]; for input, index in inputs { if input.present { order.append(index as u32); } }
    // Stable insertion order implements source largest-first then source index.
    for ignored in 1..order.len { var index = ignored; while index != 0 { let left = order[index - 1]; let right = order[index]; let l = inputs[left].value.tree.nodes.len; let r = inputs[right].value.tree.nodes.len; if l > r || (l == r && left < right) { break; } order[index - 1] = right; order[index] = left; index -= 1; } }
    slots.clear(); for input in inputs { slots.append(Slot { requested: input.present , ..}); }
    // All owner copies finish before any worker starts. Failed packet creation
    // rolls back the entire prepared batch and leaves the caller's inputs live.
    let err = executor.begin(inputs.len); if err != Error.none { return blot_support::none<Batch<Executor>>(), err; }
    for index in order { let input = inputs[index].value; let err = executor.prepare(index, input.tree, names, input.checked, origins); if err != Error.none { executor.cancelAndJoin(); executor.deinit(); slots.clear(); return blot_support::none<Batch<Executor>>(), err; } }
    let count = min(requested as i64, min(jobs, 16)); var workers: i64 = 1;
    for ignored in 1..count { let started, err = executor.startWorker(); if err != Error.none || !started { break; } workers += 1; }
    // Caller executes the same Goose worker loop. Work indices are claimed by
    // the executor's flat transport; completed/error packets retain their slot.
    executor.executeCaller(order); let err = executor.finish(); if err != Error.none { executor.cancelAndJoin(); executor.deinit(); slots.clear(); return blot_support::none<Batch<Executor>>(), err; }
    return blot_support::some(Batch<Executor> { executor:executor, slots:slots, workers:workers, active:true , ..}), Error.none;
}
fn Batch::take(self: Batch&, index: i64) -> blot_reuse_dependency_payload::Owned<blot_check_core::Module>, Error {
    let executor .= self.executor; let slots .= self.slots; assert(executor && slots);
    assert(self.active && index >= 0 && index < slots.len && slots[index].requested && !slots[index].taken);
    slots[index].taken = true; return executor.take(index);
}
fn Batch::deinit(self: Batch&) {if !self.active {return;}let executor .= self.executor;let slots .= self.slots;assert(executor && slots);executor.cancelAndJoin();for slot,index in slots {if slot.requested && !slot.taken {executor.discard(index);}}executor.deinit();slots.clear();self.executor=null;self.slots=null;self.active=false;}
