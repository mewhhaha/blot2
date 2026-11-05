// Instance-bound leases retain checked owners beyond invocation frames.
namespace blot_runtime_public_owners;
import backend.wasm;
import backend.runtime_ir;
import runtime.runtime_layout;
import reuse.artifact_emitter;
import support.emitter;
import support.error;
import backend.runtime_code;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_code::Local;
let lease_bytes = blot_runtime_runtime_layout::PublicOwnerLease_bytes;
let lease_owner = blot_runtime_runtime_layout::PublicOwnerLease_owner;
let lease_next = blot_runtime_runtime_layout::PublicOwnerLease_next;
let lease_token = blot_runtime_runtime_layout::PublicOwnerLease_token;
let lease_schema = blot_runtime_runtime_layout::PublicOwnerLease_schema;
let lease_kind = blot_runtime_runtime_layout::PublicOwnerLease_kind;
let header_bytes = blot_runtime_runtime_layout::ArenaHeader_bytes;
let header_requested = blot_runtime_runtime_layout::ArenaHeader_requested;
let owning_bytes = blot_runtime_runtime_layout::Owning_bytes;
let view_bytes = blot_runtime_runtime_layout::OwningView_bytes;
struct Runtime { head: u32, count: u32, next: u32, publish: u32, take: u32, release: u32, token: u32 }
fn emit(m: Module&) -> Runtime, Error {
    let a, error = m.ensureArena(); if error != Error.none { return Runtime {}, error; }
    if !m.start.present {
        let initializer, error = m.addTypedFunction([], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar);
        if error != Error.none { return Runtime {}, error; }
        let recorded = m.setStart(initializer); if recorded != Error.none { return Runtime {}, recorded; }
    }
    let head, e1 = m.addGlobal(blot_backend_runtime_ir::SC_pointer, 0, true); if e1 != Error.none { return Runtime {}, e1; }
    let count, e2 = m.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if e2 != Error.none { return Runtime {}, e2; }
    let next, e3 = m.addGlobal(blot_backend_runtime_ir::SC_u32, 1, true); if e3 != Error.none { return Runtime {}, e3; }
    let i32 = blot_backend_runtime_ir::VT_i32;
    let publish, e4 = m.addTypedFunction([i32,i32,i32], i32, blot_backend_runtime_ir::ROLE_scalar); if e4 != Error.none { return Runtime {}, e4; }
    let take, e5 = m.addTypedFunction([i32,i32,i32,i32], i32, blot_backend_runtime_ir::ROLE_reference); if e5 != Error.none { return Runtime {}, e5; }
    let release, e6 = m.addTypedFunction([i32], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar); if e6 != Error.none { return Runtime {}, e6; }
    let token, e7 = m.addTypedFunction([i32,i32,i32], i32, blot_backend_runtime_ir::ROLE_scalar); if e7 != Error.none { return Runtime {}, e7; }
    let r = Runtime {head,count,next,publish,take,release,token};
    let scalar = blot_backend_runtime_ir::ROLE_scalar; let reference = blot_backend_runtime_ir::ROLE_reference;
    let p1 = m.setParameterRoles(publish, blot_backend_runtime_ir::packParameterRoles([reference,scalar,scalar])); if p1 != Error.none { return Runtime {}, p1; }
    let p2 = m.setParameterRoles(take, blot_backend_runtime_ir::packParameterRoles([scalar,scalar,scalar,scalar])); if p2 != Error.none { return Runtime {}, p2; }
    let p3 = m.setParameterRoles(release, blot_backend_runtime_ir::packParameterRoles([scalar])); if p3 != Error.none { return Runtime {}, p3; }
    let p4 = m.setParameterRoles(token, blot_backend_runtime_ir::packParameterRoles([scalar,scalar,scalar])); if p4 != Error.none { return Runtime {}, p4; }
    {
        var c = blot_emitter::init(m, r.publish);
        c.globalGet(r.count);
        c.value(4096);
        c.op(blot_backend_runtime_ir::OP_i32_ge_u);
        c.globalGet(r.next);
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.trap();
        c.value(Local {0});
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.trap();
        c.value(Local {1});
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.value(Local {2});
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.value(Local {2});
        c.value(2);
        c.op(blot_backend_runtime_ir::OP_i32_gt_u);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.trap();
        let lease = c.temp();
        var scratch: blot_backend_runtime_ir::Instruction[17] = default<blot_backend_runtime_ir::Instruction[17]>();
        let annotations = blot_backend_runtime_ir::annotations([reference,reference,scalar,scalar,scalar], scalar, scratch);
        for annotation in scratch[..annotations] { c.annotation(annotation); }
        c.value(lease_bytes);
        c.call(a.allocate);
        c.set(lease);
        c.value(lease);
        c.value(Local {0});
        c.store(lease_owner);
        c.value(lease);
        c.globalGet(r.head);
        c.store(lease_next);
        c.value(lease);
        c.globalGet(r.next);
        c.store(lease_token);
        c.value(lease);
        c.value(Local {1});
        c.store(lease_schema);
        c.value(lease);
        c.value(Local {2});
        c.store(lease_kind);
        c.value(lease);
        c.globalSet(r.head);
        c.globalGet(r.count);
        c.value(1);
        c.op(blot_backend_runtime_ir::OP_i32_add);
        c.globalSet(r.count);
        c.globalGet(r.next);
        c.value(1);
        c.op(blot_backend_runtime_ir::OP_i32_add);
        c.globalSet(r.next);
        c.value(lease);
        c.load(lease_token);
        if c.failure != Error.none { return Runtime {},c.failure; }
    }
    {
        var c = blot_emitter::init(m,r.take);
        let token = Local {0}; let schema = Local {1}; let kind = Local {2}; let consume = Local {3};
        let node = c.temp(); let previous = c.temp(); let next = c.temp(); let owner = c.temp(); let steps = c.temp();
        c.value(token);
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.trap();
        c.value(consume);
        c.value(1);
        c.op(blot_backend_runtime_ir::OP_i32_gt_u);
        c.trap();
        c.globalGet(r.head);
        c.set(node);
        c.loopStart();
        c.value(node);
        c.loopTest();
        c.value(steps);
        c.value(4096);
        c.op(blot_backend_runtime_ir::OP_i32_ge_u);
        c.trap();
        c.next(steps);
        c.value(node);
        c.load(lease_token);
        c.value(token);
        c.op(blot_backend_runtime_ir::OP_i32_eq);
        c.when();
        c.value(schema);
        c.value(0);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.value(node);
        c.load(lease_schema);
        c.value(schema);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.op(blot_backend_runtime_ir::OP_i32_and);
        c.trap();
        c.value(kind);
        c.value(0);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.value(node);
        c.load(lease_kind);
        c.value(kind);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.op(blot_backend_runtime_ir::OP_i32_and);
        c.trap();
        c.value(node);
        c.load(lease_owner);
        c.set(owner);
        c.value(owner);
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.trap();
        c.value(consume);
        c.when();
        for live in [node,owner] {
            c.op(blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::pack(blot_backend_runtime_ir::Ownership {blot_backend_runtime_ir::OWN_scope,5,live.id}));
        }
        c.value(node);
        c.load(lease_next);
        c.set(next);
        c.value(previous);
        c.when();
        c.value(previous);
        c.value(previous);
        c.value(lease_next);
        c.op(blot_backend_runtime_ir::OP_i32_add);
        c.value(next);
        c.call(a.store_word);
        c.op(blot_backend_runtime_ir::OP_else_);
        c.value(next);
        c.globalSet(r.head);
        c.end();
        c.value(node);
        c.value(node);
        c.value(0);
        c.call(a.store_word);
        c.value(node);
        c.value(node);
        c.value(lease_next);
        c.op(blot_backend_runtime_ir::OP_i32_add);
        c.value(0);
        c.call(a.store_word);
        c.globalGet(r.count);
        c.value(1);
        c.op(blot_backend_runtime_ir::OP_i32_sub);
        c.globalSet(r.count);
        c.end();
        c.value(owner);
        c.ret();
        c.end();
        c.value(node);
        c.set(previous);
        c.value(node);
        c.load(lease_next);
        c.set(node);
        c.again();
        c.op(blot_backend_runtime_ir::OP_unreachable_);
        if c.failure != Error.none { return Runtime {},c.failure; }
    }
    {
        var c = blot_emitter::init(m,r.release);
        c.value(Local {0});
        c.value(0);
        c.value(0);
        c.value(1);
        c.call(r.take);
        c.op(blot_backend_runtime_ir::OP_drop);
        if c.failure != Error.none { return Runtime {},c.failure; }
    }
    {
        var c = blot_emitter::init(m,r.token);
        c.value(Local {1});
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.trap();
        c.value(Local {2});
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.value(Local {2});
        c.value(2);
        c.op(blot_backend_runtime_ir::OP_i32_gt_u);
        c.op(blot_backend_runtime_ir::OP_i32_or);
        c.trap();
        let owner = c.temp(); let size = c.temp(); let steps = c.temp();
        c.value(Local {0});
        c.value(Local {1});
        c.value(Local {2});
        c.value(0);
        c.call(r.take);
        c.set(owner);
        c.loopStart();
        c.value(1);
        c.loopTest();
        c.value(steps);
        c.value(128);
        c.op(blot_backend_runtime_ir::OP_i32_ge_u);
        c.trap();
        c.next(steps);
        c.value(owner);
        c.value(header_bytes);
        c.op(blot_backend_runtime_ir::OP_i32_sub);
        c.load(header_requested);
        c.set(size);
        c.value(size);
        c.value(owning_bytes);
        c.op(blot_backend_runtime_ir::OP_i32_eq);
        c.when();
        c.value(owner);
        c.load(blot_runtime_runtime_layout::Owning_token);
        c.ret();
        c.end();
        c.value(size);
        c.value(view_bytes);
        c.op(blot_backend_runtime_ir::OP_i32_ne);
        c.trap();
        c.value(owner);
        c.load(blot_runtime_runtime_layout::OwningView_owner);
        c.set(owner);
        c.value(owner);
        c.op(blot_backend_runtime_ir::OP_i32_eqz);
        c.trap();
        c.again();
        c.op(blot_backend_runtime_ir::OP_unreachable_);
        if c.failure != Error.none { return Runtime {},c.failure; }
    }
    { let optional_source_60 .= m.artifacts; if optional_source_60 { let journal .= optional_source_60; let error = journal.recordPublicOwners(r); if error != Error.none { return Runtime {},error; }  } }
    return r,Error.none;
}
