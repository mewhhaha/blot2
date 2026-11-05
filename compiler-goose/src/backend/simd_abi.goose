// Direct-call vector workers retain the original boxed ABI for tables/exports.
namespace blot_backend_simd_abi;
import .cohort_candidate;
type View = blot_backend_cohort_candidate::Extension;
import .wasm;
import .runtime_ir;
import .wasm_inline;
import .optimizer_buffers;
import runtime.region_runtime;
import support.error;
import support.option;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Instruction = blot_backend_runtime_ir::Instruction;
type Words = blot_backend_optimizer_buffers::Words;
type Flags = blot_backend_optimizer_buffers::Flags;
type Bytes = blot_backend_optimizer_buffers::Bytes;
type Types = blot_backend_optimizer_buffers::Types;
type Code = blot_backend_optimizer_buffers::Code;
let none: u32 = 4294967295;
let whole_flag: u8 = 1;
let mixed_flag: u8 = 2;
struct Classes {parent: Words = Words {..},flags: Bytes = Bytes {..}}
fn deinit(self: Classes&) {self.parent.deinit();self.flags.deinit();}
fn add(self: Classes&,count: i64) -> Error {let first = self.parent.len;let parent = self.parent.ensure(first + count);if parent != Error.none {return parent;}let flags = self.flags.ensure(first + count);if flags != Error.none {return flags;}for offset in 0..count {let inserted = self.parent.push((first + offset) as u32);if inserted != Error.none {return inserted;}let marked = self.flags.push(0);if marked != Error.none {return marked;}}return Error.none;}
fn root(self: Classes&,initial: u32) -> u32 {var id = initial;while self.parent.items[id] != id {id = self.parent.items[id];}var next = initial;while next != id {let parent = self.parent.items[next];self.parent.items[next] = id;next = parent;}return id;}
fn mark(self: Classes&,id: u32,flag: u8) {self.flags.items[self.root(id)] |= flag;}
struct Value {class: u32 = none,mixed: bool = false}
fn flow(self: Classes&,destination: u32,value: Value) {if value.mixed {self.mark(destination,mixed_flag);}if value.class == none {return;}let left = self.root(destination);let right = self.root(value.class);if left == right {return;}self.parent.items[right] = left;self.flags.items[left] |= self.flags.items[right];}
fn vector(self: Classes&,id: u32) -> bool {return self.flags.items[self.root(id)] == whole_flag;}
struct Control {height: i64,class: u32}
struct Values {storage: Value[:] = [],items: Value[:] = []}
struct Controls {storage: Control[:] = [],items: Control[:] = []}
reusable[] var value_runs: Value[>..] = [];
reusable[] var control_runs: Control[>..] = [];
fn push(self: Values&,value: Value) -> Error {return blot_support_pooled_buffer::push(self,value,value_runs);}
fn clear(self: Values&) {blot_support_pooled_buffer::clear(self);}
fn resize(self: Values&,length: i64) {blot_support_pooled_buffer::resize(self,length);}
fn pop(self: Values&) -> Value {assert(self.items.len != 0);let value = self.items[self.items.len - 1];self.resize(self.items.len - 1);return value;}
fn deinit(self: Values&) {blot_support_pooled_buffer::deinit(self,value_runs);}
fn push(self: Controls&,value: Control) -> Error {return blot_support_pooled_buffer::push(self,value,control_runs);}
fn clear(self: Controls&) {blot_support_pooled_buffer::clear(self);}
fn pop(self: Controls&) {assert(self.items.len != 0);blot_support_pooled_buffer::resize(self,self.items.len - 1);}
fn deinit(self: Controls&) {blot_support_pooled_buffer::deinit(self,control_runs);}
struct Scan {module: const Module&,helpers: const bool[:],bases: const u32[:],classes: Classes = Classes {..},calls: u32[:],exits: bool[:],stack: Values = Values {..},controls: Controls = Controls {..},arguments: Values = Values {..}}
fn deinit(self: Scan&) {self.classes.deinit();self.stack.deinit();self.controls.deinit();self.arguments.deinit();}
fn result(self: const Scan&,id: u32) -> u32 {let body = self.module.functions[id];return self.bases[id] + (body.parameters.len + self.module.locals(body).len) as u32;}
fn floor(self: const Scan&) -> i64 {if self.controls.items.len == 0 {return 0;}return self.controls.items[self.controls.items.len - 1].height;}
fn pop(self: Scan&) -> Value {if self.stack.items.len > self.floor() {return self.stack.pop();}return Value {..};}
fn push(self: Scan&,value: Value) -> Error {return self.stack.push(value);}
fn discard(self: Scan&) {self.stack.resize(self.floor());}
fn lane(self: Scan&,address: Value,offset: u32) {if address.class != none && (offset >= 16 || offset % 4 != 0) {self.classes.mark(address.class,mixed_flag);}}
fn whole(self: Scan&,address: Value,offset: u32) {if address.class != none {var flag = mixed_flag;if offset == 0 {flag = whole_flag;}self.classes.mark(address.class,flag);}}
fn reference(module: const Module&,body: Function,parameter: i64) -> bool {return parameter < 32 && module.parameters(body)[parameter] == blot_backend_runtime_ir::VT_i32 && blot_backend_runtime_ir::parameterRole(body,parameter) == blot_backend_runtime_ir::ROLE_reference && parameter != body.provider_parameter;}
fn call(self: Scan&,instructions: const Instruction[:],at: i64) -> Error {
    let module .= self.module;let callee = instructions[at].operand;let target = module.functions[callee];assert(module.arena.present);let arena = module.arena.value;
    if blot_backend_wasm::isAllocation(arena,callee) {
        for parameter in 0..target.parameters.len {self.pop();}var size: u32 = 0;if at != 0 && instructions[at - 1].op == blot_backend_runtime_ir::OP_i32_const && !instructions[at - 1].table_reference {size = instructions[at - 1].operand;}
        var scalar = callee == arena.allocate_scalar;
        if !scalar {let roles = blot_backend_runtime_ir::allocationAnnotations(instructions,at);scalar = roles.len != 0;for word in 0..4 {scalar = scalar && blot_backend_runtime_ir::wordRole(roles,word) == blot_backend_runtime_ir::ROLE_scalar;}}
        return self.push(Value {mixed: size != 16 || !scalar,..});
    }
    self.arguments.clear();for parameter in 0..target.parameters.len {let error = self.arguments.push(Value {..});if error != Error.none {return error;}}
    var index = target.parameters.len;while index != 0 {index--;self.arguments.items[index] = self.pop();}
    let source = !self.helpers[callee];if source {if self.calls[callee] != 4294967295 {self.calls[callee]++;}for parameter in 0..self.arguments.items.len {if reference(module,target,parameter) {self.classes.flow(self.bases[callee] + parameter as u32,self.arguments.items[parameter]);}}}
    if target.result == blot_backend_runtime_ir::VT_none {return Error.none;}
    if source && target.result == blot_backend_runtime_ir::VT_i32 && target.result_role == blot_backend_runtime_ir::ROLE_reference {return self.push(Value {class: self.result(callee),..});}
    return self.push(Value {mixed: target.result == blot_backend_runtime_ir::VT_i32,..});
}
fn function(self: Scan&,id: u32) -> Error {
    let module .= self.module;let body = module.functions[id];let instructions = module.instructions(body);let base = self.bases[id];self.stack.clear();self.controls.clear();
    for inst,at in instructions {
        let op = inst.op;var error = Error.none;
        if op == blot_backend_runtime_ir::OP_local_get {error = self.push(Value {class: base + inst.operand,..});}
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {self.classes.flow(base + inst.operand,self.pop());if op == blot_backend_runtime_ir::OP_local_tee {error = self.push(Value {class: base + inst.operand,..});}}
        else if op == blot_backend_runtime_ir::OP_i32_const {let constructor,has_constructor = blot_backend_runtime_ir::staticConstructor(instructions,at);error = self.push(Value {mixed: inst.table_reference || has_constructor || !blot_backend_runtime_ir::hasImmortalReference(instructions,at),..});}
        else if op == blot_backend_runtime_ir::OP_global_get {error = self.push(Value {..});}
        else if op == blot_backend_runtime_ir::OP_i32_load || op == blot_backend_runtime_ir::OP_f32_load {self.lane(self.pop(),inst.operand);error = self.push(Value {mixed: op == blot_backend_runtime_ir::OP_f32_load,..});}
        else if op == blot_backend_runtime_ir::OP_i32_store || op == blot_backend_runtime_ir::OP_f32_store {self.pop();self.lane(self.pop(),inst.operand);}
        else if op == blot_backend_runtime_ir::OP_v128_load {self.whole(self.pop(),inst.operand);error = self.push(Value {..});}
        else if op == blot_backend_runtime_ir::OP_v128_store {self.pop();self.whole(self.pop(),inst.operand);}
        else if op == blot_backend_runtime_ir::OP_call {error = self.call(instructions,at);}
        else if op == blot_backend_runtime_ir::OP_call_indirect || op == blot_backend_runtime_ir::OP_call_import {let signature = blot_backend_runtime_ir::call(module,inst);if op == blot_backend_runtime_ir::OP_call_indirect {self.pop();}for parameter in 0..signature.parameters.len {self.pop();}if signature.result != blot_backend_runtime_ir::VT_none {error = self.push(Value {mixed: op == blot_backend_runtime_ir::OP_call_import,..});}}
        else if op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ {
            if op == blot_backend_runtime_ir::OP_if_ {self.pop();}var class = none;
            if inst.operand != 0 && inst.operand != blot_backend_runtime_ir::VT_none {class = self.classes.parent.len as u32;let added = self.classes.add(1);if added != Error.none {return added;}if op == blot_backend_runtime_ir::OP_loop {self.classes.mark(class,mixed_flag);}}
            error = self.controls.push(Control {height: self.stack.items.len,class});
        }
        else if op == blot_backend_runtime_ir::OP_else_ || op == blot_backend_runtime_ir::OP_end {
            if self.controls.items.len == 0 {self.exits[id] = true;return Error.none;}let control = self.controls.items[self.controls.items.len - 1];if control.class != none && self.stack.items.len > control.height {self.classes.flow(control.class,self.pop());}self.discard();if op == blot_backend_runtime_ir::OP_end {self.controls.pop();if control.class != none {error = self.push(Value {class: control.class,..});}}
        }
        else if op == blot_backend_runtime_ir::OP_br || op == blot_backend_runtime_ir::OP_br_if {
            if op == blot_backend_runtime_ir::OP_br_if {self.pop();}if inst.operand >= self.controls.items.len {self.exits[id] = true;}else {let target = self.controls.items[self.controls.items.len - 1 - inst.operand];if target.class != none && self.stack.items.len > self.floor() {self.classes.flow(target.class,self.stack.items[self.stack.items.len - 1]);}}if op == blot_backend_runtime_ir::OP_br {self.discard();}
        }
        else if op == blot_backend_runtime_ir::OP_return_ {if body.result != blot_backend_runtime_ir::VT_none {self.classes.flow(self.result(id),self.pop());}self.discard();}
        else if op == blot_backend_runtime_ir::OP_unreachable_ {self.discard();}
        else if op == blot_backend_runtime_ir::OP_drop {self.pop();}
        else {let contract = blot_backend_runtime_ir::contract(module,body,inst);for input in 0..contract.arity {self.pop();}if contract.result != blot_backend_runtime_ir::VT_none {error = self.push(Value {mixed: contract.result == blot_backend_runtime_ir::VT_i32,..});}}
        if error != Error.none {return error;}
    }
    if self.controls.items.len != 0 {self.exits[id] = true;return Error.none;}if body.result != blot_backend_runtime_ir::VT_none {self.classes.flow(self.result(id),self.pop());}return Error.none;
}
struct Plan {worker: u32 = none,vectors: u32 = 0,result: bool = false}
fn vector(self: Plan,parameter: i64) -> bool {return parameter < 32 && (self.vectors & (1 as u32 << parameter)) != 0;}
reusable[] var plan_runs: Plan[>..] = [];
fn privateFunction(module: const Module&,id: u32) -> bool {
    let body = module.functions[id];if body.entry || (module.start.present && module.start.value == id) || body.parameters.len > 32 {return false;}let locals = body.parameters.len + module.locals(body).len;if locals >= 4096 {return false;}if module.resourceAdapterFunction(id) || module.taskAdapterFunction(id) {return false;}if blot_runtime_region_runtime::scope(module,id).present {return false;}
    for inst in module.instructions(body) {if inst.op != blot_backend_runtime_ir::OP_call {continue;}if module.cohorts.present {let cohorts = module.cohorts.value;if inst.operand == cohorts.begin || inst.operand == cohorts.allocate || inst.operand == cohorts.retire_members {return false;}}if module.regions.present && module.regions.value.runtime.contains(inst.operand) {return false;}}
    return true;
}
fn prepareInto(view: View&,source: const Module&) -> bool,Error {
    if !source.arena.present {return false,Error.none;}var vectors = false;for body in source.functions {for inst in source.instructions(body) {if inst.op == blot_backend_runtime_ir::OP_v128_load || inst.op == blot_backend_runtime_ir::OP_v128_store {vectors = true;break;}}}if !vectors {return false,Error.none;}
    let count = source.functions.len;var helpers = Flags {..};var bases = Words {..};var calls = Words {..};var exits = Flags {..};let plans = plan_runs.alloc_slice(count);for index in 0..count {plans[index] = Plan {..};}
    fn analyze() -> bool,Error {
        var classes: i64 = 0;
        for id in 0..count {if classes > 2147483647 {return false,Error.none;}let helper = helpers.push(source.runtimeHelper(id));if helper != Error.none {return false,helper;}let base = bases.push(classes as u32);if base != Error.none {return false,base;}let called = calls.push(0);if called != Error.none {return false,called;}let exited = exits.push(false);if exited != Error.none {return false,exited;}classes += source.functions[id].parameters.len + source.locals(source.functions[id]).len + 1;}
        var scan = Scan {module: source,helpers: helpers.items,bases: bases.items,calls: calls.items,exits: exits.items,..};
        fn scanAll() -> bool,Error {
            let added = scan.classes.add(classes);if added != Error.none {return false,added;}for id in 0..count {if !helpers.items[id] {let error = scan.function(id as u32);if error != Error.none {return false,error;}}}
            var any = false;
            for id in 0..count {let body = source.functions[id];if helpers.items[id] || exits.items[id] || calls.items[id] == 0 || !privateFunction(source,id as u32) {continue;}
                for parameter in 0..body.parameters.len {if reference(source,body,parameter) && scan.classes.vector(bases.items[id] + parameter as u32) {plans[id].vectors |= 1 as u32 << parameter;}}
                plans[id].result = body.result == blot_backend_runtime_ir::VT_i32 && body.result_role == blot_backend_runtime_ir::ROLE_reference && scan.classes.vector(scan.result(id as u32));if plans[id].vectors == 0 && !plans[id].result {continue;}if blot_backend_wasm_inline::expands(source,id as u32) {plans[id] = Plan {..};continue;}any = true;
            }
            if !any {return false,Error.none;}
            for id in 0..count {if helpers.items[id] {continue;}let body = source.functions[id];let plan = plans[id];var added: i64 = 0;if plan.vectors != 0 || plan.result {added = 33;}for inst in source.instructions(body) {if inst.op == blot_backend_runtime_ir::OP_call {let callee = plans[inst.operand];if callee.vectors != 0 || callee.result {added += 34;}}}if added == 0 {continue;}let frame = body.parameters.len + source.locals(body).len;if frame >= 4096 || added >= 4096 - frame {return false,Error.none;}}
            let error = rewriteInto(view,source,helpers.items,plans);return error == Error.none,error;
        }
        let admitted,error = scanAll();scan.deinit();return admitted,error;
    }
    let admitted,error = analyze();plan_runs.free_slice(plans);exits.deinit();calls.deinit();bases.deinit();helpers.deinit();return admitted,error;
}
fn rewriteInto(view: View&,source: const Module&,helpers: const bool[:],plans: Plan[:]) -> Error {
    let detached = blot_backend_cohort_candidate::detachedInto(view,source);if detached != Error.none {return detached;}let module .= view.module;var kept = Flags {..};
    fn rewrite() -> Error {
        let initialized = kept.resize(source.functions.len,false);if initialized != Error.none {return initialized;}
        for item in source.exports {if !item.global && item.index < kept.len {kept.items[item.index] = true;}}if source.start.present {kept.items[source.start.value] = true;}for target in source.table_functions {if target < kept.len {kept.items[target] = true;}}
        for body,id in source.functions {for inst in source.instructions(body) {if inst.op == blot_backend_runtime_ir::OP_i32_const && inst.table_reference && inst.operand < kept.len {kept.items[inst.operand] = true;}if inst.op == blot_backend_runtime_ir::OP_call && helpers[id] && inst.operand < kept.len {kept.items[inst.operand] = true;}}}
        for id in 0..source.functions.len {
            let body = source.functions[id];let plan = plans[id];if plan.vectors == 0 && !plan.result {continue;}
            var parameters: blot_backend_runtime_ir::ValueType[32] = [blot_backend_runtime_ir::VT_none;32];let original = source.parameters(body);for parameter in 0..original.len {parameters[parameter] = original[parameter];}var roles = body.parameter_roles;
            for parameter in 0..body.parameters.len {if plan.vector(parameter) {parameters[parameter] = blot_backend_runtime_ir::VT_v128;roles &= ~(3 as u64 << (parameter * 2));roles |= blot_backend_runtime_ir::ROLE_scalar as u64 << (parameter * 2);}}
            var result = body.result;var role = body.result_role;if plan.result {result = blot_backend_runtime_ir::VT_v128;role = blot_backend_runtime_ir::ROLE_scalar;}
            let signature,error = module.internType(parameters[..body.parameters.len],result);if error != Error.none {return error;}let worker,worker_error = module.addTypedFunctionForSignature(signature,role);if worker_error != Error.none {return worker_error;}plans[id].worker = worker;module.functions[worker].parameter_roles = roles;module.functions[worker].provider_parameter = body.provider_parameter;
        }
        for id in 0..source.functions.len {
            let plan = plans[id];if plan.worker == none {continue;}let transformed,error = transform(source,source.functions[id],plan,plans);if error != Error.none {return error;}var output = transformed;let installed = module.replaceBody(plan.worker,output);output.deinit();if installed != Error.none {return installed;}
        }
        for id in 0..source.functions.len {
            if helpers[id] {continue;}let body = source.functions[id];let plan = plans[id];
            if plan.worker != none && !kept.items[id] {let installed = module.publishFunctionBody(id as u32,[],[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_)]);if installed != Error.none {return installed;}view.owned.items[id] = true;continue;}
            var calls = false;for inst in source.instructions(body) {if inst.op == blot_backend_runtime_ir::OP_call && plans[inst.operand].worker != none {calls = true;break;}}if !calls {continue;}
            let transformed,error = transform(source,body,Plan {..},plans);if error != Error.none {return error;}var output = transformed;let installed = module.replaceBody(id as u32,output);output.deinit();if installed != Error.none {return installed;}view.owned.items[id] = true;
        }
        return Error.none;
    }
    let error = rewrite();kept.deinit();if error != Error.none {view.deinit();}return error;
}
fn annotations(instructions: const Instruction[:]) -> u32 {var count: u32 = 0;for inst in instructions {if inst.op == blot_backend_runtime_ir::OP_ownership {count++;}}return count;}
struct Output {locals: Types = Types {..},code: Code = Code {..},failure: Error = Error.none}
fn emit(self: Output&,op: blot_backend_runtime_ir::Op,operand: u32 = 0) {if self.failure != Error.none {return;}self.failure = self.code.push(blot_backend_runtime_ir::instruction(op,operand));}
fn append(self: Output&,code: const Instruction[:]) {if self.failure != Error.none {return;}self.failure = self.code.append(code);}
fn push(self: Output&,instruction: Instruction) {if self.failure != Error.none {return;}self.failure = self.code.push(instruction);}
fn deinit(self: Output&) {self.code.deinit();self.locals.deinit();}
fn local(self: Output&,parameters: i64,ty: blot_backend_runtime_ir::ValueType) -> u32 {if self.failure != Error.none {return 0;}let id = (parameters + self.locals.len) as u32;self.failure = self.locals.push(ty);return id;}
fn follow(id: u32,table: const u32[:]) -> u32 {if id < table.len {return table[id];}return id;}
fn remapped(operand: u32,boxes: const u32[:]) -> u32 {
    var fact = blot_backend_runtime_ir::ownership(operand);
    if fact.kind == blot_backend_runtime_ir::OWN_rest && fact.chunk == 8 {fact.roles = follow(fact.roles,boxes);}
    else if fact.kind == blot_backend_runtime_ir::OWN_scope {if fact.chunk == 2 || fact.chunk == 3 || fact.chunk == 5 || fact.chunk == 6 {fact.roles = follow(fact.roles,boxes);}else if fact.chunk == 4 {fact.roles = follow(fact.roles & 8191,boxes) | (follow(fact.roles >> 13,boxes) << 13);}}
    return blot_backend_runtime_ir::pack(fact);
}
fn emitBox(out: Output&,module: const Module&,lanes: u32,box: u32) {
    var buffer: Instruction[17] = [Instruction {..};17];let count = blot_backend_runtime_ir::annotations([],blot_backend_runtime_ir::ROLE_scalar,buffer);out.append(buffer[..count]);assert(module.arena.present);out.emit(blot_backend_runtime_ir::OP_i32_const,16);out.emit(blot_backend_runtime_ir::OP_call,module.arena.value.allocate_scalar);out.emit(blot_backend_runtime_ir::OP_local_set,box);out.emit(blot_backend_runtime_ir::OP_local_get,box);out.emit(blot_backend_runtime_ir::OP_local_get,lanes);out.emit(blot_backend_runtime_ir::OP_v128_store);
}
fn emitUnbox(out: Output&,returned: u32) {out.emit(blot_backend_runtime_ir::OP_local_set,returned);out.emit(blot_backend_runtime_ir::OP_local_get,returned);out.emit(blot_backend_runtime_ir::OP_v128_load);}
fn emitCall(out: Output&,module: const Module&,parameters: i64,callee: u32,plan: Plan,spill: bool) {
    let target = module.functions[callee];
    if spill {
        var temporaries: u32[32] = [0;32];var index = target.parameters.len;
        while index != 0 {index--;temporaries[index] = out.local(parameters,module.parameters(target)[index]);out.emit(blot_backend_runtime_ir::OP_local_set,temporaries[index]);}
        for parameter in 0..target.parameters.len {out.emit(blot_backend_runtime_ir::OP_local_get,temporaries[parameter]);if plan.vector(parameter) {out.emit(blot_backend_runtime_ir::OP_v128_load);}}
    }
    out.emit(blot_backend_runtime_ir::OP_call,plan.worker);if !plan.result {return;}let lanes = out.local(parameters,blot_backend_runtime_ir::VT_v128);let box = out.local(parameters,blot_backend_runtime_ir::VT_i32);out.emit(blot_backend_runtime_ir::OP_local_set,lanes);emitBox(out,module,lanes,box);out.emit(blot_backend_runtime_ir::OP_local_get,box);
}
fn transform(module: const Module&,body: Function,own: Plan,plans: const Plan[:]) -> blot_backend_runtime_ir::DetachedBody,Error {
    let instructions = module.instructions(body);var out = Output {..};out.failure = out.locals.append(module.locals(body));let parameters = body.parameters.len;var boxes = Words {..};
    for parameter in 0..parameters {var box = parameter as u32;if own.vector(parameter) {box = out.local(parameters,blot_backend_runtime_ir::VT_i32);}let added = boxes.push(box);if out.failure == Error.none {out.failure = added;}}
    var returned = none;if own.result {returned = out.local(parameters,blot_backend_runtime_ir::VT_i32);}for parameter in 0..parameters {if own.vector(parameter) {emitBox(out,module,parameter as u32,boxes.items[parameter]);}}
    var loads = Flags {..};var spills = Flags {..};
    fn lower() -> Error {
        let initialized = loads.resize(instructions.len,false);if initialized != Error.none {return initialized;}let spill_initialized = spills.resize(instructions.len,false);if spill_initialized != Error.none {return spill_initialized;}
        for inst,at in instructions {
            if inst.op != blot_backend_runtime_ir::OP_call || plans[inst.operand].worker == none {continue;}let plan = plans[inst.operand];let count = module.functions[inst.operand].parameters.len;var positions: i64[32] = [0;32];var found: i64 = 0;var cursor = at;
            while found < count && cursor != 0 {
                cursor--;let op = instructions[cursor].op;
                if op == blot_backend_runtime_ir::OP_ownership {continue;}
                if op == blot_backend_runtime_ir::OP_local_get || op == blot_backend_runtime_ir::OP_i32_const || op == blot_backend_runtime_ir::OP_f32_const {positions[count - 1 - found] = cursor;found++;}else {break;}
            }
            if found != count {spills.items[at] = true;continue;}for parameter in 0..count {if plan.vector(parameter) {loads.items[positions[parameter]] = true;}}
        }
        for inst,at in instructions {
            var copy = inst;
            if copy.op == blot_backend_runtime_ir::OP_local_get || copy.op == blot_backend_runtime_ir::OP_local_set || copy.op == blot_backend_runtime_ir::OP_local_tee || copy.op == blot_backend_runtime_ir::OP_resource_retire {if copy.operand < parameters {copy.operand = boxes.items[copy.operand];}}
            else if copy.op == blot_backend_runtime_ir::OP_ownership {copy.operand = remapped(copy.operand,boxes.items);}
            if copy.op == blot_backend_runtime_ir::OP_call && plans[copy.operand].worker != none {emitCall(out,module,parameters,copy.operand,plans[copy.operand],spills.items[at]);}
            else if copy.op == blot_backend_runtime_ir::OP_return_ && own.result {emitUnbox(out,returned);out.push(copy);}
            else {out.push(copy);}if loads.items[at] {out.emit(blot_backend_runtime_ir::OP_v128_load);}
        }
        if own.result {var has_last = false;var last: blot_backend_runtime_ir::Op = 0;for inst in instructions {if inst.op != blot_backend_runtime_ir::OP_ownership {last = inst.op;has_last = true;}}if !has_last || (last != blot_backend_runtime_ir::OP_return_ && last != blot_backend_runtime_ir::OP_unreachable_) {emitUnbox(out,returned);}}
        return out.failure;
    }
    let error = lower();spills.deinit();loads.deinit();boxes.deinit();if error != Error.none {out.deinit();return blot_backend_runtime_ir::DetachedBody {..},error;}
    let result,result_error = blot_backend_runtime_ir::cloneBody(out.locals.items,out.code.items);out.deinit();return result,result_error;
}
