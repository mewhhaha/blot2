// Initialization dependencies are proved and sorted before any Wasm publication.
namespace blot_backend_storage_globals;
import dictionary;
import check.core;
import .storage_collections;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Ref = blot_check_core::BindingRef;
struct Node {unit: u32,id: u32}
struct Limits {nodes_per_module: i64 = 100000}
reusable[] var binding_runs: Ref[>..] = [];
fn ownBindings(values: const Ref[:]) -> Ref[:] {if values.len == 0 {return [];}let result = binding_runs.alloc_slice(values.len);for index in 0..values.len {result[index] = values[index];}return result;}
fn release(values: const Ref[:]) {if values.len != 0 {let first: const Ref& = values[0];let start = binding_runs.index_of(first);binding_runs.free_slice(binding_runs[start..start + values.len]);}}
fn discover(units: const Module[:],roots: const Node[:],follow_arrays: bool,limits: Limits) -> Ref[:],Error {
    var pending: Node[>..<] = [];var seen: dictionary<u64,bool> = {};var globals: Ref[>..] = [];var remaining: i64[>..] = [];for unit in units {remaining.push(limits.nodes_per_module);}pending.append(roots);
    while pending.len != 0 {
        let current = pending[pending.len - 1];pending.resize(pending.len - 1);if current.id == 0 {continue;}if current.unit == 0 || current.unit > units.len {return [],Error.invalid_global;}let key = (current.unit as u64 << 32) | current.id;if seen.get(key) {continue;}seen.insert(key,true);if remaining[current.unit - 1] == 0 {return [],Error.limit;}remaining[current.unit - 1]--;
        let module: const Module& = units[current.unit - 1];if current.id >= module.nodes.len {return [],Error.invalid_global;}let node = module.node(current.id);for child in module.children(current.id) {pending.push(Node {unit: module.unit,id: child});}
        match node.tag {
            reference,call=>{
                var target = Ref {..};if node.tag == blot_check_core::Tag.call {target = module.call(current.id).target;}else {target = module.reference(current.id);}if target.unit == 0 {target.unit = module.unit;}if target.unit == 0 || target.unit > units.len {return [],Error.invalid_global;}let owner: const Module& = units[target.unit - 1];if target.binding == 0 || target.binding >= owner.bindings.len {return [],Error.invalid_global;}let binding = owner.binding(target.binding);if binding.kind != blot_check_core::BindingKind.global {continue;}
                if blot_backend_storage_collections::element(owner,binding.ty).present {var found = false;for prior in globals {if prior == target {found = true;break;}}if !found {globals.push(target);}if !follow_arrays {continue;}}
                let body .= owner.body(target.binding);if body {pending.push(Node {unit: owner.unit,id: body.root});}
            },
            scalar,associated,logical,apply,record_merge,proof_guard=>{pending.push(Node {unit: module.unit,id: node.a});pending.push(Node {unit: module.unit,id: node.b});},
            if_value,if_stmt=>{for id in [node.a,node.b,node.c] {pending.push(Node {unit: module.unit,id});}},
            bind,construct,pattern_bind=>{pending.push(Node {unit: module.unit,id: node.b});},
            update=>{let info = module.updateInfo(current.id);pending.push(Node {unit: module.unit,id: info.root});for selector in module.updateSelectors(current.id) {match selector.kind {index=>{pending.push(Node {unit: module.unit,id: selector.index});},_=>{},}}pending.push(Node {unit: module.unit,id: info.value});},
            return_,project,usage_read,usage_share=>{pending.push(Node {unit: module.unit,id: node.a});},closure=>{pending.push(Node {unit: module.unit,id: module.closure(current.id).body});},
            loop_=>{let loop = module.loopInfo(current.id);for id in [loop.first,loop.end,loop.body] {pending.push(Node {unit: module.unit,id});}},
            match_=>{for id in module.matchInputs(current.id) {pending.push(Node {unit: module.unit,id});}for arm in module.matchArms(current.id) {pending.push(Node {unit: module.unit,id: arm.guard});pending.push(Node {unit: module.unit,id: arm.body});}},_=>{},
        }
    }
    return ownBindings(globals),Error.none;
}
struct Initializer {target: Ref,root: u32,dependencies: const Ref[:]}
struct Plan {initializers: Initializer[:] = []}
reusable[] var initializer_runs: Initializer[>..] = [];
fn deinit(self: Plan&) {for item in self.initializers {release(item.dependencies);}if self.initializers.len != 0 {initializer_runs.free_slice(self.initializers);}self.initializers = [];}
fn indexOf(bindings: const Ref[:],target: Ref) -> blot_support::Option<i64> {for binding,index in bindings {if binding == target {return blot_support::some(index);}}return blot_support::none<i64>();}
struct Frame {index: i64,next: i64 = 0}
fn plan(units: const Module[:],entry: u32) -> Plan,Error {return planWithLimits(units,entry,Limits {..});}
fn planWithLimits(units: const Module[:],entry: u32,limits: Limits) -> Plan,Error {
    if entry == 0 || entry > units.len {return Plan {..},Error.invalid_global;}var roots: Node[>..] = [];for body in units[entry - 1].bodies {if body.exported {roots.push(Node {unit: entry,id: body.root});}}
    let bindings,error = discover(units,roots,true,limits);if error != Error.none {return Plan {..},error;}var entries: Initializer[>..] = [];var transferred = false;
    fn order() -> Plan,Error {
        for target in bindings {let module: const Module& = units[target.unit - 1];let body .= module.body(target.binding);if !body {return Plan {..},Error.invalid_global;}let dependencies,error = discover(units,[Node {unit: target.unit,id: body.root}],false,limits);if error != Error.none {return Plan {..},error;}entries.push(Initializer {target,root: body.root,dependencies});}
        var states: u8[>..] = [];for entry in entries {states.push(0);}var stack: Frame[>..<] = [];var order: i64[>..] = [];
        for start in 0..bindings.len {if states[start] != 0 {continue;}states[start] = 1;stack.push(Frame {index: start,..});
            while stack.len != 0 {let top: Frame& = stack[stack.len - 1];let dependencies = entries[top.index].dependencies;
                if top.next == dependencies.len {let done = top.index;stack.resize(stack.len - 1);states[done] = 2;order.push(done);continue;}
                let next = indexOf(bindings,dependencies[top.next]);if !next.present {return Plan {..},Error.invalid_global;}top.next++;if states[next.value] == 1 {return Plan {..},Error.initialization_cycle;}if states[next.value] == 2 {continue;}states[next.value] = 1;stack.push(Frame {index: next.value,..});
            }
        }
        var ordered: Initializer[:] = [];if entries.len != 0 {ordered = initializer_runs.alloc_slice(entries.len);for index in 0..order.len {ordered[index] = entries[order[index]];}}transferred = true;return Plan {initializers: ordered},Error.none;
    }
    let result,result_error = order();if !transferred {for item in entries {release(item.dependencies);}}release(bindings);return result,result_error;
}
fn collect(units: const Module[:],entry: u32) -> Ref[:],Error {let initialized,error = plan(units,entry);if error != Error.none {return [],error;}var evidence = initialized;var bindings: Ref[>..] = [];for item in evidence.initializers {bindings.push(item.target);}let result = ownBindings(bindings);evidence.deinit();return result,Error.none;}
