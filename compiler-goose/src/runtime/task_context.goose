// A suspended invocation owns a private root and cancellation journal.
namespace blot_runtime_task_context;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import support.emitter;
import support.option;
import support.error;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
type Error = blot_error::Error;
let magic: u32 = 0x7461736b;
let bytes: u32 = 40;
struct Functions { create: u32, save: u32, restore: u32, drop: u32 }
fn valid(c: Code&, context: Local) {
    c.value(context);
    c.op(blot_backend_runtime_ir::OP_i32_eqz);
    c.trap();
    c.value(context);
    c.load(bytes-4);
    c.value(magic);
    c.op(blot_backend_runtime_ir::OP_i32_ne);
    c.trap();
}
fn emit(module: Module&, request_owner: blot_support::Option<u32>) -> Functions, Error {
    let arena, e1 = module.ensureArena(); if e1 != Error.none { return Functions {..},e1; }
    let current, e2 = module.addGlobal(blot_backend_runtime_ir::SC_u32,0,true); if e2 != Error.none { return Functions {..},e2; }
    let i32 = blot_backend_runtime_ir::VT_i32;
    let create, e3 = module.addTypedFunction([i32],i32,blot_backend_runtime_ir::ROLE_scalar); if e3 != Error.none { return Functions {..},e3; }
    let save, e4 = module.addTypedFunction([i32],i32,blot_backend_runtime_ir::ROLE_scalar); if e4 != Error.none { return Functions {..},e4; }
    let restore, e5 = module.addTypedFunction([i32],i32,blot_backend_runtime_ir::ROLE_scalar); if e5 != Error.none { return Functions {..},e5; }
    let drop, e6 = module.addTypedFunction([i32],i32,blot_backend_runtime_ir::ROLE_scalar); if e6 != Error.none { return Functions {..},e6; }
    let functions = Functions {create,save,restore,drop, ..};
    let fields = [arena.root_page,arena.root_top,arena.root_frame,arena.root_active,arena.root_external,arena.root_started,arena.root_host_cursor,arena.root_host_active];
    let context = Local {0, ..};
    {
        var c = blot_emitter::init(module,functions.create);
        c.globalGet(arena.root_enabled);
        c.value(3);
        c.op(blot_backend_runtime_ir::OP_i32_and);
        c.value(3);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.trap();
        let fresh = c.temp();
        c.value(bytes);
        c.call(arena.allocate);
        c.set(fresh);
        c.value(fresh);
        c.value(0);
        c.value(bytes);
        c.zero();
        c.value(fresh);
        c.value(blot_runtime_runtime_layout::ArenaHeader_bytes);
        c.op(blot_backend_runtime_ir::OP_i32_sub);
        c.value(2);
        c.store(blot_runtime_runtime_layout::ArenaHeader_flags);
        c.value(context);
        c.value(1);
        c.op(blot_backend_runtime_ir::OP_i32_gt_u);
        c.trap();
        if module.host_references.present {
            let references = module.host_references.value;
            c.value(context);
            c.when();
            c.value(fresh);
            c.globalGet(references.cursor);
            c.store(24);
            c.value(fresh);
            c.globalGet(references.active);
            c.store(28);
            c.end();
        }
        c.value(fresh);
        c.value(magic);
        c.store(bytes-4);
        c.value(fresh);
        if c.failure != Error.none { return Functions {..},c.failure; }
    }
    {
        var c = blot_emitter::init(module,functions.save);
        valid(c,context);
        c.globalGet(current);
        c.globalGet(current);
        c.value(context);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.op(blot_backend_runtime_ir::OP_i32_and);
        c.trap();
        for field,index in fields {
            c.value(context);
            c.globalGet(field);
            c.store((index*4) as u32);
        }
        if request_owner.present {
            c.value(context);
            c.globalGet(request_owner.value);
            c.store(32);
        }
        c.value(context);
        c.globalSet(current);
        c.value(0);
        if c.failure != Error.none { return Functions {..},c.failure; }
    }
    {
        var c = blot_emitter::init(module,functions.restore);
        valid(c,context);
        c.globalGet(current);
        c.when();
        c.globalGet(current);
        c.call(functions.save);
        c.op(blot_backend_runtime_ir::OP_drop);
        c.end();
        var saved: Local[9] = default<Local[9]>();
        for index in 9 {
            saved[index] = c.temp();
            c.value(context);
            c.load((index*4) as u32);
            c.set(saved[index]);
        }
        for field,index in fields {
            c.value(saved[index]);
            c.globalSet(field);
        }
        if request_owner.present {
            c.value(saved[8]);
            c.globalSet(request_owner.value);
        }
        c.value(context);
        c.globalSet(current);
        c.value(0);
        if c.failure != Error.none { return Functions {..},c.failure; }
    }
    {
        var c = blot_emitter::init(module,functions.drop);
        valid(c,context);
        c.value(context);
        c.globalGet(current);
        c.op(blot_backend_runtime_ir::OP_i32_eq);
        c.when();
        c.value(context);
        c.call(functions.save);
        c.op(blot_backend_runtime_ir::OP_drop);
        c.end();
        c.value(context);
        c.load(8);
        c.value(context);
        c.load(12);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.trap();
        let page = c.temp();
        c.value(context);
        c.load(0);
        c.set(page);
        c.value(page);
        c.when();
        c.value(page);
        c.load(0);
        c.value(context);
        c.load(4);
        c.value(8);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.trap();
        c.value(page);
        c.call(arena.free);
        c.end();
        c.value(context);
        c.value(0);
        c.store(bytes-4);
        c.value(context);
        c.call(arena.free);
        c.value(context);
        c.globalGet(current);
        c.op(blot_backend_runtime_ir::OP_i32_eq);
        c.when();
        for field in fields {
            c.value(0);
            c.globalSet(field);
        }
        c.value(0);
        c.globalSet(current);
        c.end();
        c.value(0);
        if c.failure != Error.none { return Functions {..},c.failure; }
    }
    return functions,Error.none;
}
