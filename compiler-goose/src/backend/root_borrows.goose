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
struct Analysis {
    module: const Module&,source: Function,code: const Instruction[:],graph: const blot_backend_wasm_control_flow::Graph&,locals: u32,work: i64 = 4194304,
    copies: Copy[>..<]&,reachable: bool[>..<]&,parents: u32[>..<]&,member_next: u32[>..<]&,member_head: u32[>..<]&,reserve_at: u32[>..<]&,sets: u32[>..<]&,gets: u32[>..<]&,value_uses: u32[>..<]&,store_head: u32[>..<]&,store_next: u32[>..<]&,depths: i32[>..<]&,region: u32[>..<]&,dense: u32[>..<]&,seen: u32[>..<]&,queue: u32[>..<]&,order: u32[>..<]&,pending: u32[>..<]&,members: u32[>..<]&,states: u64[>..<]&,visited: bool[>..<]&,scratch: u64[>..<]&,reservations: u32[>..<]&,publications: u32[>..<]&,remove: bool[>..<]&,removed_slots: bool[>..<]&,
}
fn spend(self: Analysis&,amount: i64) -> bool {if self.work < amount {self.work = 0;return false;}self.work -= amount;return true;}
fn prepare(self: Analysis&) -> bool {
    for inst in self.code {self.copies.push(Copy {..});self.store_next.push(none);self.remove.push(false);}for index in 0..self.code.len + 1 {self.reachable.push(false);self.depths.push(-1);self.region.push(none);self.seen.push(0);}
    for index in 0..self.locals {self.parents.push(index as u32);self.member_next.push(none);self.member_head.push(none);self.reserve_at.push(none);self.sets.push(0);self.gets.push(0);self.value_uses.push(0);self.store_head.push(none);self.dense.push(none);self.removed_slots.push(false);}
    var stack: Copy[256] = [Copy {..};256];var height: i64 = 0;var store_tail: u32[>..] = [];for index in 0..self.locals {store_tail.push(none);}
    for inst,index in self.code {let at = index as u32;let op = inst.op;
        if op == blot_backend_runtime_ir::OP_local_get {if inst.operand >= self.locals {return false;}self.gets[inst.operand]++;if height == 256 {height = 0;}stack[height] = Copy {from: inst.operand,read: at,..};height++;}
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {if inst.operand >= self.locals {return false;}self.sets[inst.operand]++;if height != 0 {self.copies[at] = stack[height - 1];self.parents[root(self.parents,inst.operand)] = root(self.parents,stack[height - 1].from);if op == blot_backend_runtime_ir::OP_local_set {height--;}}for slot in 0..height {if stack[slot].from == inst.operand {stack[slot].stale = true;}}}
        else if op == blot_backend_runtime_ir::OP_drop {if height != 0 {height--;}}
        else if op == blot_backend_runtime_ir::OP_nop {}
        else if op == blot_backend_runtime_ir::OP_ownership {let marker = scope(inst);if marker.present {let fact = marker.value;match fact.chunk {
            3=>{if fact.roles >= self.locals {return false;}var reservation = multiple;if self.reserve_at[fact.roles] == none {reservation = at;}self.reserve_at[fact.roles] = reservation;},
            4=>{let slot = fact.roles & 8191;let value = fact.roles >> 13;if slot >= self.locals || value >= self.locals {return false;}self.value_uses[value]++;if store_tail[slot] == none {self.store_head[slot] = at;}else {self.store_next[store_tail[slot]] = at;}store_tail[slot] = at;},
            2,5,6=>{if fact.roles >= self.locals {return false;}self.value_uses[fact.roles]++;},_=>{},
        }}}
        else {height = 0;}
    }
    for index in 0..self.locals {let component = root(self.parents,index as u32);self.member_next[index] = self.member_head[component];self.member_head[component] = index as u32;}
    self.reachable[0] = true;self.queue.push(0);var cursor: i64 = 0;while cursor < self.queue.len {for next in self.graph.nodes[self.queue[cursor]].next {if next == blot_backend_wasm_control_flow::absent || self.reachable[next] {continue;}self.reachable[next] = true;self.queue.push(next);}cursor++;}self.queue.clear();return true;
}
fn reserved(self: Analysis&,start: u32,reservation: u32) -> bool {let stamp = start + 1;self.pending.clear();self.pending.push(start);self.seen[start] = stamp;while self.pending.len != 0 {let point = self.pending.pop();if point == reservation + 1 {continue;}if point == 0 || !self.spend(1) {return false;}var edge = self.graph.nodes[point].first;if edge == blot_backend_wasm_control_flow::absent {return false;}while edge != blot_backend_wasm_control_flow::absent {let previous = self.graph.predecessors[edge];edge = previous.next;if !self.reachable[previous.from] {continue;}let marker = scope(self.code[previous.from]);if marker.present && marker.value.chunk <= 2 {return false;}if self.seen[previous.from] == stamp {continue;}self.seen[previous.from] = stamp;self.pending.push(previous.from);}}return true;}
fn reach(self: Analysis&,start: u32,slot: u32) -> bool {
    self.reservations.clear();self.publications.clear();self.queue.push(start + 1);self.depths[start + 1] = 0;var cursor: i64 = 0;
    while cursor < self.queue.len {
        if !self.spend(1) {return false;}let at = self.queue[cursor];cursor++;if at == start {return false;}let inst = self.code[at];var depth = self.depths[at];let op = inst.op;
        if op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_indirect {if !ordinaryCall(self.module,inst) {return false;}}
        else if op == blot_backend_runtime_ir::OP_call_import || op == blot_backend_runtime_ir::OP_resource_retire || op == blot_backend_runtime_ir::OP_wide_layouts || op == blot_backend_runtime_ir::OP_host_ref_get || op == blot_backend_runtime_ir::OP_host_ref_set || op == blot_backend_runtime_ir::OP_host_ref_size || op == blot_backend_runtime_ir::OP_host_ref_grow || op == blot_backend_runtime_ir::OP_global_set {return false;}
        let marker = scope(inst);if marker.present {let fact = marker.value;match fact.chunk {0=>{depth++;},1=>{if depth == 0 {continue;}depth--;},3=>{if fact.roles == slot {return false;}self.reservations.push(at);},4=>{},5=>{if localType(self.module,self.source,fact.roles) != blot_backend_runtime_ir::VT_i32 {return false;}self.publications.push(at);},14=>{},_=>{return false;},}}
        for next in self.graph.nodes[at].next {if next == blot_backend_wasm_control_flow::absent || next == self.code.len {continue;}if self.depths[next] != -1 {if self.depths[next] != depth {return false;}continue;}self.depths[next] = depth;self.queue.push(next);}
    }
    for at in self.queue {self.region[at] = 0;}self.pending.clear();self.pending.append(self.queue);
    while self.pending.len != 0 {let at = self.pending.pop();if self.region[at] == none || !self.spend(1) {if self.work == 0 {return false;}continue;}var edge = self.graph.nodes[at].first;var entered = false;while edge != blot_backend_wasm_control_flow::absent {let previous = self.graph.predecessors[edge];edge = previous.next;if self.reachable[previous.from] && previous.from != start && self.region[previous.from] == none {entered = true;break;}}if !entered {continue;}self.region[at] = none;for next in self.graph.nodes[at].next {if next != blot_backend_wasm_control_flow::absent && next != self.code.len && self.region[next] != none {self.pending.push(next);}}}
    if self.region[start + 1] == none {return false;}self.order.clear();for at in self.queue {if self.region[at] != none {self.region[at] = self.order.len as u32;self.order.push(at);}}return true;
}
fn initial(self: Analysis&,start: u32,value: u32,out: u64[:]) {
    var first = start;while first != 0 && start - first < 4096 && !control(self.code[first - 1].op) {first--;}var numbers: u32[4096] = [0;4096];for index in 0..self.members.len {numbers[index] = (index + 1) as u32;}var fresh = (self.members.len + 1) as u32;var stack: u32[256] = [0;256];var height: i64 = 0;
    for inst in self.code[first..start] {let op = inst.op;if op == blot_backend_runtime_ir::OP_local_get {if height == 256 {height = 0;}let index = self.dense[inst.operand];var number: u32 = 0;if index != none {number = numbers[index];}stack[height] = number;height++;}
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {var number: u32 = 0;if height != 0 {number = stack[height - 1];}if op == blot_backend_runtime_ir::OP_local_set && height != 0 {height--;}let index = self.dense[inst.operand];if index == none {continue;}if number == 0 {number = fresh;fresh++;}numbers[index] = number;}
        else if op == blot_backend_runtime_ir::OP_drop {if height != 0 {height--;}}
        else if op != blot_backend_runtime_ir::OP_nop && op != blot_backend_runtime_ir::OP_ownership {height = 0;}
    }
    for index in 0..out.len {out[index] = 0;}let target = numbers[self.dense[value]];for index in 0..self.members.len {if numbers[index] == target {setBit(out,index as u32,true);}}
}
fn flowCopies(self: Analysis&,start: u32,value: u32) -> bool {
    let words = (self.members.len + 63) / 64;let count = self.order.len;if count * words > max_state_words {return false;}self.states.resize(count * words,18446744073709551615);for index in 0..self.states.len {self.states[index] = 18446744073709551615;}self.visited.resize(count,false);for index in 0..self.visited.len {self.visited[index] = false;}self.scratch.resize(words,0);self.initial(start,value,self.states[..words]);self.visited[0] = true;self.pending.clear();self.pending.push(0);
    while self.pending.len != 0 {let index = self.pending.pop();if !self.spend(words + 1) {return false;}let at = self.order[index];let inst = self.code[at];for word in 0..words {self.scratch[word] = self.states[index * words + word];}
        let assigned = assigned(inst);if assigned.present && self.dense[assigned.value] != none {var keep = false;let copy = self.copies[at];if inst.op != blot_backend_runtime_ir::OP_ownership && copy.from != none && !copy.stale && self.dense[copy.from] != none {keep = bit(self.scratch,self.dense[copy.from]);}setBit(self.scratch,self.dense[assigned.value],keep);}
        let marker = scope(inst);if marker.present && marker.value.chunk == 1 && self.depths[at] == 0 {continue;}
        for next in self.graph.nodes[at].next {if next == blot_backend_wasm_control_flow::absent || next == self.code.len {continue;}let target = self.region[next];if target == none {continue;}var changed = !self.visited[target];for word in 0..words {let met = self.states[target * words + word] & self.scratch[word];if met != self.states[target * words + word] {changed = true;}self.states[target * words + word] = met;}if !changed {continue;}self.visited[target] = true;self.pending.push(target);}
    }return true;
}
fn holds(self: const Analysis&,at: u32,local: u32) -> bool {let index = self.region[at];if index == none || !self.visited[index] {return false;}let member = self.dense[local];if member == none {return false;}let words = (self.members.len + 63) / 64;return bit(self.states[index * words..index * words + words],member);}
fn restore(self: Analysis&) {for at in self.queue {self.depths[at] = -1;self.region[at] = none;}self.queue.clear();for local in self.members {self.dense[local] = none;}self.members.clear();}
fn cover(self: Analysis&,start: u32) {
    let selected = scope(self.code[start]);assert(selected.present);let marker = selected.value;let slot = marker.roles & 8191;let value = marker.roles >> 13;let parameters = self.source.parameters.len;
    if start + 1 >= self.code.len || self.removed_slots[slot] || slot < parameters || localType(self.module,self.source,slot) != blot_backend_runtime_ir::VT_i32 || localType(self.module,self.source,value) != blot_backend_runtime_ir::VT_i32 {return;}let reservation = self.reserve_at[slot];if reservation == none || reservation == multiple || self.sets[slot] != 0 || self.gets[slot] != 0 || self.value_uses[slot] != 0 || !self.reserved(start,reservation) {return;}
    fn prove() {
        if !self.reach(start,slot) {return;}var member = self.member_head[root(self.parents,value)];while member != none {if self.members.len == max_members {return;}self.dense[member] = self.members.len as u32;self.members.push(member);member = self.member_next[member];}if !self.flowCopies(start,value) {return;}
        var store = self.store_head[slot];while store != none {let at = store;store = self.store_next[store];if self.depths[at] == -1 {continue;}let fact = scope(self.code[at]);assert(fact.present);if !self.holds(at,fact.value.roles >> 13) {return;}}
        store = self.store_head[slot];while store != none {if self.region[store] != none {self.remove[store] = true;}store = self.store_next[store];}
        for at in self.publications {let fact = scope(self.code[at]);assert(fact.present);if self.holds(at,fact.value.roles) {self.remove[at] = true;}}
        for at in self.reservations {if self.region[at] == none {continue;}let fact = scope(self.code[at]);assert(fact.present);let other = fact.value.roles;if other < parameters || self.removed_slots[other] || localType(self.module,self.source,other) != blot_backend_runtime_ir::VT_i32 || self.reserve_at[other] != at || self.sets[other] != 0 || self.gets[other] != 0 || self.value_uses[other] != 0 {continue;}var covered = true;var duplicate = self.store_head[other];while duplicate != none {let marker = scope(self.code[duplicate]);assert(marker.present);if !self.holds(duplicate,marker.value.roles >> 13) {covered = false;}duplicate = self.store_next[duplicate];}if !covered {continue;}self.remove[at] = true;self.removed_slots[other] = true;duplicate = self.store_head[other];while duplicate != none {self.remove[duplicate] = true;duplicate = self.store_next[duplicate];}}
    }
    prove();self.restore();
}
fn run(module: const Module&,source: Function) -> blot_support::Option<blot_backend_runtime_ir::DetachedBody>,Error {
    let drain,has_drain = module.resourceDrainImport();if has_drain {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}let code = module.instructions(source);let locals = source.parameters.len + module.locals(source).len;if locals > max_locals || code.len > max_code {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}var stores = false;for inst in code {let marker = scope(inst);if marker.present && marker.value.chunk == 4 {stores = true;break;}}if !stores {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}
    var nodes: blot_backend_wasm_control_flow::Node[>..] = [];var predecessors: blot_backend_wasm_control_flow::Predecessor[>..] = [];let graph = blot_backend_wasm_control_flow::init(nodes,predecessors,code);if !graph.valid {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}
    var copies: Copy[>..<] = [];var reachable: bool[>..<] = [];var parents: u32[>..<] = [];var member_next: u32[>..<] = [];var member_head: u32[>..<] = [];var reserve_at: u32[>..<] = [];var sets: u32[>..<] = [];var gets: u32[>..<] = [];var value_uses: u32[>..<] = [];var store_head: u32[>..<] = [];var store_next: u32[>..<] = [];var depths: i32[>..<] = [];var region: u32[>..<] = [];var dense: u32[>..<] = [];var seen: u32[>..<] = [];var queue: u32[>..<] = [];var order: u32[>..<] = [];var pending: u32[>..<] = [];var members: u32[>..<] = [];var states: u64[>..<] = [];var visited: bool[>..<] = [];var scratch: u64[>..<] = [];var reservations: u32[>..<] = [];var publications: u32[>..<] = [];var remove: bool[>..<] = [];var removed_slots: bool[>..<] = [];
    var analysis = Analysis {module,source,code,graph,locals: locals as u32,copies,reachable,parents,member_next,member_head,reserve_at,sets,gets,value_uses,store_head,store_next,depths,region,dense,seen,queue,order,pending,members,states,visited,scratch,reservations,publications,remove,removed_slots,..};if !analysis.prepare() {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}
    for inst,start in code {if analysis.work == 0 {break;}let marker = scope(inst);if !marker.present || marker.value.chunk != 4 || analysis.remove[start] {continue;}analysis.cover(start as u32);}var changed = false;for omitted in analysis.remove {changed = changed || omitted;}if !changed {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),Error.none;}
    var output: Instruction[>..] = [];for inst,index in code {if !analysis.remove[index] {output.push(inst);}}let body,error = blot_backend_runtime_ir::cloneBody(module.locals(source),output);if error != Error.none {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}return blot_support::some(body),Error.none;
}
