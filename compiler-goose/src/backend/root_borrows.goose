// A dominating strong slot may cover exact-copy duplicate lexical owners.
namespace blot_backend_root_borrows;
import .runtime_ir;
import .wasm;
import .wasm_control_flow;
import support.option;
import support.error;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Instruction = blot_backend_runtime_ir::Instruction;
let none: u32 = 4294967295;
let multiple: u32 = 4294967294;
let max_locals: i64 = 8192;
let max_code: i64 = 65536;
let max_members: i64 = 4096;
let max_state_words: i64 = 1048576;
struct Copy {from: u32 = none,read: u32 = none,stale: bool = false}
fn scope(inst: Instruction) -> blot_support::Option<blot_backend_runtime_ir::Ownership> {if inst.op != blot_backend_runtime_ir::OP_ownership {return blot_support::none<blot_backend_runtime_ir::Ownership>();}let marker = blot_backend_runtime_ir::ownership(inst.operand);if marker.kind != blot_backend_runtime_ir::OWN_scope {return blot_support::none<blot_backend_runtime_ir::Ownership>();}return blot_support::some(marker);}
fn assigned(inst: Instruction) -> blot_support::Option<u32> {if inst.op == blot_backend_runtime_ir::OP_local_set || inst.op == blot_backend_runtime_ir::OP_local_tee {return blot_support::some(inst.operand);}let marker = scope(inst);if marker.present && marker.value.chunk == 3 {return blot_support::some(marker.value.roles);}return blot_support::none<u32>();}
fn localType(module: const Module&,source: Function,index: i64) -> blot_backend_runtime_ir::ValueType {if index < source.parameters.len {return module.parameters(source)[index];}return module.locals(source)[index - source.parameters.len];}
fn root(parents: u32[:],first: u32) -> u32 {var current = first;while parents[current] != current {parents[current] = parents[parents[current]];current = parents[current];}return current;}
fn control(op: blot_backend_runtime_ir::Op) -> bool {return op == blot_backend_runtime_ir::OP_unreachable_ || op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ || op == blot_backend_runtime_ir::OP_else_ || op == blot_backend_runtime_ir::OP_end || op == blot_backend_runtime_ir::OP_br || op == blot_backend_runtime_ir::OP_br_if || op == blot_backend_runtime_ir::OP_return_;}
fn listFunction(module: const Module&,id: u32) -> bool {if !module.lists.present {return false;}let lists = module.lists.value;for field in ["new","address","copy","push","set","from_array","to_array","chunk_new","edit","branch","own","insert","replace","refresh","rotate_left","rotate_right","balance","concat","slice","join","cut","directory","leaf_count","write_leaves","address_unchecked","set_unchecked","snapshot"] {let function = lists.functionId(field);if function.present && id == function.value {return true;}}return false;}
fn ordinaryCall(module: const Module&,inst: Instruction) -> bool {if inst.op == blot_backend_runtime_ir::OP_call_indirect {return true;}if inst.op != blot_backend_runtime_ir::OP_call || inst.operand >= module.functions.len {return false;}let id = inst.operand;if module.arena.present {let arena = module.arena.value;for function in [arena.allocate,arena.allocate_scalar,arena.allocate_typed,arena.allocate_shaped,arena.retain,arena.release,arena.store_word,arena.copy_words,arena.mark_acyclic] {if id == function {return true;}}}if listFunction(module,id) {return true;}if module.runtimeHelper(id) || (module.start.present && module.start.value == id) {return false;}return !module.functions[id].entry;}
fn bit(words: const u64[:],index: u32) -> bool {return (words[index / 64] & (1 as u64 << (index % 64))) != 0;}
fn setBit(words: u64[:],index: u32,value: bool) {let mask = 1 as u64 << (index % 64);if value {words[index / 64] |= mask;}else {words[index / 64] &= ~mask;}}
// Module facts are tabulated per body, so the analysis never leads back to module storage.
root struct Analysis {
    local_types: const blot_backend_runtime_ir::ValueType[:],parameters: i64,graph: const blot_backend_wasm_control_flow::Graph&,locals: u32,work: i64 = 4194304,
    ordinary_calls: bool[>..] = [],copies: Copy[>..<] = [],reachable: bool[>..<] = [],parents: u32[>..<] = [],member_next: u32[>..<] = [],member_head: u32[>..<] = [],reserve_at: u32[>..<] = [],sets: u32[>..<] = [],gets: u32[>..<] = [],value_uses: u32[>..<] = [],store_head: u32[>..<] = [],store_next: u32[>..<] = [],depths: i32[>..<] = [],region: u32[>..<] = [],dense: u32[>..<] = [],seen: u32[>..<] = [],queue: u32[>..<] = [],order: u32[>..<] = [],pending: u32[>..<] = [],members: u32[>..<] = [],states: u64[>..<] = [],visited: bool[>..<] = [],scratch: u64[>..<] = [],reservations: u32[>..<] = [],publications: u32[>..<] = [],remove: bool[>..<] = [],removed_slots: bool[>..<] = [],
}
fn spend(self_: Analysis&,amount: i64) -> bool {if self_.work < amount {self_.work = 0;return false;}self_.work -= amount;return true;}
fn prepare(self_: Analysis&,code:const Instruction[:]) -> bool {
    for inst in code {self_.copies.push(Copy {..});self_.store_next.push(none);self_.remove.push(false);}for index in 0..code.len + 1 {self_.reachable.push(false);self_.depths.push(-1);self_.region.push(none);self_.seen.push(0);}
    for index in 0..self_.locals {self_.parents.push(index as u32);self_.member_next.push(none);self_.member_head.push(none);self_.reserve_at.push(none);self_.sets.push(0);self_.gets.push(0);self_.value_uses.push(0);self_.store_head.push(none);self_.dense.push(none);self_.removed_slots.push(false);}
    var stack: Copy[256] = [Copy {..};256];var height: i64 = 0;var store_tail: u32[>..] = [];for index in 0..self_.locals {store_tail.push(none);}
    for inst,index in code {let at = index as u32;let op = inst.op;
        if op == blot_backend_runtime_ir::OP_local_get {if inst.operand >= self_.locals {return false;}self_.gets[inst.operand]++;if height == 256 {height = 0;}stack[height] = Copy {from: inst.operand,read: at,..};height++;}
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {if inst.operand >= self_.locals {return false;}self_.sets[inst.operand]++;if height != 0 {self_.copies[at] = stack[height - 1];self_.parents[root(self_.parents,inst.operand)] = root(self_.parents,stack[height - 1].from);if op == blot_backend_runtime_ir::OP_local_set {height--;}}for slot in 0..height {if stack[slot].from == inst.operand {stack[slot].stale = true;}}}
        else if op == blot_backend_runtime_ir::OP_drop {if height != 0 {height--;}}
        else if op == blot_backend_runtime_ir::OP_nop {}
        else if op == blot_backend_runtime_ir::OP_ownership {let marker = scope(inst);if marker.present {let fact = marker.value;match fact.chunk {
            3=>{if fact.roles >= self_.locals {return false;}var reservation = multiple;if self_.reserve_at[fact.roles] == none {reservation = at;}self_.reserve_at[fact.roles] = reservation;},
            4=>{let slot = fact.roles & 8191;let value = fact.roles >> 13;if slot >= self_.locals || value >= self_.locals {return false;}self_.value_uses[value]++;if store_tail[slot] == none {self_.store_head[slot] = at;}else {self_.store_next[store_tail[slot]] = at;}store_tail[slot] = at;},
            2,5,6=>{if fact.roles >= self_.locals {return false;}self_.value_uses[fact.roles]++;},_=>{},
        }}}
        else {height = 0;}
    }
    for index in 0..self_.locals {let component = root(self_.parents,index as u32);self_.member_next[index] = self_.member_head[component];self_.member_head[component] = index as u32;}
    self_.reachable[0] = true;self_.queue.push(0);var cursor: i64 = 0;while cursor < self_.queue.len {for next in self_.graph.nodes[self_.queue[cursor]].next {if next == blot_backend_wasm_control_flow::absent || self_.reachable[next] {continue;}self_.reachable[next] = true;self_.queue.push(next);}cursor++;}self_.queue.clear();return true;
}
fn reserved(self_: Analysis&,code:const Instruction[:],start: u32,reservation: u32) -> bool {let stamp = start + 1;self_.pending.clear();self_.pending.push(start);self_.seen[start] = stamp;while self_.pending.len != 0 {let point = self_.pending.pop();if point == reservation + 1 {continue;}if point == 0 || !self_.spend(1) {return false;}var edge = self_.graph.nodes[point].first;if edge == blot_backend_wasm_control_flow::absent {return false;}while edge != blot_backend_wasm_control_flow::absent {let previous = self_.graph.predecessors[edge];edge = previous.next;if !self_.reachable[previous.from] {continue;}let marker = scope(code[previous.from]);if marker.present && marker.value.chunk <= 2 {return false;}if self_.seen[previous.from] == stamp {continue;}self_.seen[previous.from] = stamp;self_.pending.push(previous.from);}}return true;}
fn reach(self_: Analysis&,code:const Instruction[:],start: u32,slot: u32) -> bool {
    self_.reservations.clear();self_.publications.clear();self_.queue.push(start + 1);self_.depths[start + 1] = 0;var cursor: i64 = 0;
    while cursor < self_.queue.len {
        if !self_.spend(1) {return false;}let at = self_.queue[cursor];cursor++;if at == start {return false;}let inst = code[at];var depth = self_.depths[at];let op = inst.op;
        if op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_indirect {if !self_.ordinary_calls[at] {return false;}}
        else if op == blot_backend_runtime_ir::OP_call_import || op == blot_backend_runtime_ir::OP_resource_retire || op == blot_backend_runtime_ir::OP_wide_layouts || op == blot_backend_runtime_ir::OP_host_ref_get || op == blot_backend_runtime_ir::OP_host_ref_set || op == blot_backend_runtime_ir::OP_host_ref_size || op == blot_backend_runtime_ir::OP_host_ref_grow || op == blot_backend_runtime_ir::OP_global_set {return false;}
        let marker = scope(inst);if marker.present {let fact = marker.value;match fact.chunk {0=>{depth++;},1=>{if depth == 0 {continue;}depth--;},3=>{if fact.roles == slot {return false;}self_.reservations.push(at);},4=>{},5=>{if self_.local_types[fact.roles] != blot_backend_runtime_ir::VT_i32 {return false;}self_.publications.push(at);},14=>{},_=>{return false;},}}
        for next in self_.graph.nodes[at].next {if next == blot_backend_wasm_control_flow::absent || next == code.len {continue;}if self_.depths[next] != -1 {if self_.depths[next] != depth {return false;}continue;}self_.depths[next] = depth;self_.queue.push(next);}
    }
    for at in self_.queue {self_.region[at] = 0;}self_.pending.clear();self_.pending.append(self_.queue);
    while self_.pending.len != 0 {let at = self_.pending.pop();if self_.region[at] == none || !self_.spend(1) {if self_.work == 0 {return false;}continue;}var edge = self_.graph.nodes[at].first;var entered = false;while edge != blot_backend_wasm_control_flow::absent {let previous = self_.graph.predecessors[edge];edge = previous.next;if self_.reachable[previous.from] && previous.from != start && self_.region[previous.from] == none {entered = true;break;}}if !entered {continue;}self_.region[at] = none;for next in self_.graph.nodes[at].next {if next != blot_backend_wasm_control_flow::absent && next != code.len && self_.region[next] != none {self_.pending.push(next);}}}
    if self_.region[start + 1] == none {return false;}self_.order.clear();for at in self_.queue {if self_.region[at] != none {self_.region[at] = self_.order.len as u32;self_.order.push(at);}}return true;
}
fn initial(self_: Analysis&,code:const Instruction[:],start: u32,value: u32,out: u64[:]) {
    var first = start;while first != 0 && start - first < 4096 && !control(code[first - 1].op) {first--;}var numbers: u32[4096] = [0;4096];for index in 0..self_.members.len {numbers[index] = (index + 1) as u32;}var fresh = (self_.members.len + 1) as u32;var stack: u32[256] = [0;256];var height: i64 = 0;
    for inst in code[first..start] {let op = inst.op;if op == blot_backend_runtime_ir::OP_local_get {if height == 256 {height = 0;}let index = self_.dense[inst.operand];var number: u32 = 0;if index != none {number = numbers[index];}stack[height] = number;height++;}
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {var number: u32 = 0;if height != 0 {number = stack[height - 1];}if op == blot_backend_runtime_ir::OP_local_set && height != 0 {height--;}let index = self_.dense[inst.operand];if index == none {continue;}if number == 0 {number = fresh;fresh++;}numbers[index] = number;}
        else if op == blot_backend_runtime_ir::OP_drop {if height != 0 {height--;}}
        else if op != blot_backend_runtime_ir::OP_nop && op != blot_backend_runtime_ir::OP_ownership {height = 0;}
    }
    for index in 0..out.len {out[index] = 0;}let target = numbers[self_.dense[value]];for index in 0..self_.members.len {if numbers[index] == target {setBit(out,index as u32,true);}}
}
fn flowCopies(self_: Analysis&,code:const Instruction[:],start: u32,value: u32) -> bool {
    let words = (self_.members.len + 63) / 64;let count = self_.order.len;if count * words > max_state_words {return false;}self_.states.resize(count * words,18446744073709551615);for index in 0..self_.states.len {self_.states[index] = 18446744073709551615;}self_.visited.resize(count,false);for index in 0..self_.visited.len {self_.visited[index] = false;}self_.scratch.resize(words,0);self_.initial(code,start,value,self_.states[..words]);self_.visited[0] = true;self_.pending.clear();self_.pending.push(0);
    while self_.pending.len != 0 {let index = self_.pending.pop();if !self_.spend(words + 1) {return false;}let at = self_.order[index];let inst = code[at];for word in 0..words {self_.scratch[word] = self_.states[index * words + word];}
        let assigned = assigned(inst);if assigned.present && self_.dense[assigned.value] != none {var keep = false;let copy = self_.copies[at];if inst.op != blot_backend_runtime_ir::OP_ownership && copy.from != none && !copy.stale && self_.dense[copy.from] != none {keep = bit(self_.scratch,self_.dense[copy.from]);}setBit(self_.scratch,self_.dense[assigned.value],keep);}
        let marker = scope(inst);if marker.present && marker.value.chunk == 1 && self_.depths[at] == 0 {continue;}
        for next in self_.graph.nodes[at].next {if next == blot_backend_wasm_control_flow::absent || next == code.len {continue;}let target = self_.region[next];if target == none {continue;}var changed = !self_.visited[target];for word in 0..words {let met = self_.states[target * words + word] & self_.scratch[word];if met != self_.states[target * words + word] {changed = true;}self_.states[target * words + word] = met;}if !changed {continue;}self_.visited[target] = true;self_.pending.push(target);}
    }return true;
}
fn holds(self_: const Analysis&,at: u32,local: u32) -> bool {let index = self_.region[at];if index == none || !self_.visited[index] {return false;}let member = self_.dense[local];if member == none {return false;}let words = (self_.members.len + 63) / 64;return bit(self_.states[index * words..index * words + words],member);}
fn restore(self_: Analysis&) {for at in self_.queue {self_.depths[at] = -1;self_.region[at] = none;}self_.queue.clear();for local in self_.members {self_.dense[local] = none;}self_.members.clear();}
fn cover(self_: Analysis&,code:const Instruction[:],start: u32) {
    let selected = scope(code[start]);assert(selected.present);let marker = selected.value;let slot = marker.roles & 8191;let value = marker.roles >> 13;let parameters = self_.parameters;
    if start + 1 >= code.len || self_.removed_slots[slot] || slot < parameters || self_.local_types[slot] != blot_backend_runtime_ir::VT_i32 || self_.local_types[value] != blot_backend_runtime_ir::VT_i32 {return;}let reservation = self_.reserve_at[slot];if reservation == none || reservation == multiple || self_.sets[slot] != 0 || self_.gets[slot] != 0 || self_.value_uses[slot] != 0 || !self_.reserved(code,start,reservation) {return;}
    fn prove() {
        if !self_.reach(code,start,slot) {return;}var member = self_.member_head[root(self_.parents,value)];while member != none {if self_.members.len == max_members {return;}self_.dense[member] = self_.members.len as u32;self_.members.push(member);member = self_.member_next[member];}if !self_.flowCopies(code,start,value) {return;}
        var store = self_.store_head[slot];while store != none {let at = store;store = self_.store_next[store];if self_.depths[at] == -1 {continue;}let fact = scope(code[at]);assert(fact.present);if !self_.holds(at,fact.value.roles >> 13) {return;}}
        store = self_.store_head[slot];while store != none {if self_.region[store] != none {self_.remove[store] = true;}store = self_.store_next[store];}
        for at in self_.publications {let fact = scope(code[at]);assert(fact.present);if self_.holds(at,fact.value.roles) {self_.remove[at] = true;}}
        for at in self_.reservations {if self_.region[at] == none {continue;}let fact = scope(code[at]);assert(fact.present);let other = fact.value.roles;if other < parameters || self_.removed_slots[other] || self_.local_types[other] != blot_backend_runtime_ir::VT_i32 || self_.reserve_at[other] != at || self_.sets[other] != 0 || self_.gets[other] != 0 || self_.value_uses[other] != 0 {continue;}var covered = true;var duplicate = self_.store_head[other];while duplicate != none {let marker = scope(code[duplicate]);assert(marker.present);if !self_.holds(duplicate,marker.value.roles >> 13) {covered = false;}duplicate = self_.store_next[duplicate];}if !covered {continue;}self_.remove[at] = true;self_.removed_slots[other] = true;duplicate = self_.store_head[other];while duplicate != none {self_.remove[duplicate] = true;duplicate = self_.store_next[duplicate];}}
    }
    prove();self_.restore();
}
fn run(module: const Module&,source: Function) -> blot_support::Option<blot_backend_runtime_ir::DetachedBody>,Error {
    let drain,has_drain = module.resourceDrainImport();if has_drain {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}var code_copy: Instruction[>..] = [];let code = blot_backend_wasm::copyInstructions(module,source,code_copy);let locals = source.parameters.len + module.locals(source).len;if locals > max_locals || code.len > max_code {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}var stores = false;for inst in code {let marker = scope(inst);if marker.present && marker.value.chunk == 4 {stores = true;break;}}if !stores {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}
    var nodes: blot_backend_wasm_control_flow::Node[>..] = [];var predecessors: blot_backend_wasm_control_flow::Predecessor[>..] = [];let graph = blot_backend_wasm_control_flow::init(nodes,predecessors,code);if !graph.valid {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}
    var local_types: blot_backend_runtime_ir::ValueType[>..] = [];for index in 0..locals {local_types.push(localType(module,source,index as i64));}
    var analysis = Analysis {local_types: local_types[..],parameters: source.parameters.len,graph: graph,locals: locals as u32,..};for inst in code {analysis.ordinary_calls.push(ordinaryCall(module,inst));}if !analysis.prepare(code) {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}
    for inst,start in code {if analysis.work == 0 {break;}let marker = scope(inst);if !marker.present || marker.value.chunk != 4 || analysis.remove[start] {continue;}analysis.cover(code,start as u32);}var changed = false;for omitted in analysis.remove {changed = changed || omitted;}if !changed {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),blot_error::Error.none;}
    var output: Instruction[>..] = [];for inst,index in code {if !analysis.remove[index] {output.push(inst);}}let body,error = blot_backend_runtime_ir::cloneBody(module.locals(source),output);if error != blot_error::Error.none {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}return blot_support::some(body),blot_error::Error.none;
}
