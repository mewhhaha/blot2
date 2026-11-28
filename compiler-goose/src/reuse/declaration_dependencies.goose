// Structural source dependencies survive metadata erased by execution lowering.
namespace squid_reuse_declaration_dependencies;
import std;
import check.core;
import check.types;
import check.check;
import support.error;
import support.option;
import support.structural;
type Error = squid_error::Error;
type Module = squid_check_core::Module;
type BindingRef = squid_check_core::BindingRef;
type Member = squid_check_core::DependencyMember;
type Recipe = squid_check_core::DeclarationDependencies;
enum Work { node { id: u32 }, pattern { id: u32 } }
struct SchemeFrame { scheme: squid_check_types::Scheme, next: u32 = 0 }
let scan_limit: i64 = 16777216;
struct Capture {
    module: const Module&, work: Work[>..]&, references: BindingRef[>..]&, locations: u32[>..]&, members: Member[>..]&, work_top: i64 = 0,
    schemes_seen: u32[:], seen_epoch: u32 = 1, runtime_metadata: u32 = 0, watched_binding: u32 = 0,
    watched_used: bool = false, selection: bool = false, failure: Error = squid_error::Error.none,
}
fn withCapture<C,F>(module: const Module&, context: C, selection: bool = false, watched: u32 = 0) {
    var work: Work[>..] = []; var references: BindingRef[>..] = []; var locations: u32[>..] = []; var members: Member[>..] = [];
    var schemes: u32[>..] = []; for _ in module.bindings.len {schemes.push(0 as u32);} let scheme_marks=schemes[..];
    var scan = Capture { module: module, work: work, references: references, locations: locations, members: members, schemes_seen: scheme_marks, watched_binding: watched, selection: selection , ..};
    return F(scan, context);
}
fn pushWork(self_: Capture&, item: Work) { if self_.work_top < self_.work.len { self_.work[self_.work_top] = item; } else { self_.work.push(item); } self_.work_top++; }
fn node(self_: Capture&, id: u32) { if self_.failure == squid_error::Error.none && id != 0 { self_.pushWork(Work.node { id , ..}); } }
fn pattern(self_: Capture&, id: u32) { if self_.failure == squid_error::Error.none && id != 0 { self_.pushWork(Work.pattern { id , ..}); } }
fn nodes(self_: Capture&, ids: const u32[:]) { var index = ids.len; while index != 0 { index--; self_.node(ids[index]); } }
fn reference(self_: Capture&, target: BindingRef, source: u32) {
    if self_.failure != squid_error::Error.none { return; } if target.binding == 0 { self_.failure = squid_error::Error.core_limit; return; }
    if target.unit == 0 || target.unit == self_.module.unit {
        if target.binding >= self_.module.bindings.len { self_.failure = squid_error::Error.core_limit; return; }
        let kind = self_.module.binding(target.binding).kind;
        if kind == squid_reuse_principal_interface::Kind.local || kind == squid_reuse_principal_interface::Kind.parameter { if target.binding == self_.watched_binding { self_.watched_used = true; } return; }
    }
    self_.references.push(target); self_.locations.push(source);
}
fn member(self_: Capture&, name: u32, op: squid_check_types::Operator) { if self_.failure == squid_error::Error.none && (name != 0 || op != squid_check_types::Operator.none) { self_.members.push(Member { name, op , ..}); } }
fn member(self_: Capture&, name: u32) { self_.member(name, squid_check_types::Operator.none); }
fn scheme(self_: Capture&, value: squid_check_types::Scheme) {
    if self_.failure != squid_error::Error.none || value.obligations.len == 0 { return; }
    var pending: SchemeFrame[>..<] = []; pending.push(SchemeFrame { value , ..}); var remaining = scan_limit;
    while pending.len != 0 {
        let last = pending.len - 1; let frame = pending[last]; if frame.next == frame.scheme.obligations.len { pending.pop(); continue; }
        if remaining == 0 { self_.failure = squid_error::Error.core_limit; return; } remaining--; pending[last].next++;
        let obligation = self_.module.obligations[frame.scheme.obligations.start + frame.next];
        if obligation.kind == squid_check_types::ObligationKind.callee_use {
            if obligation.identity.unit != 0 && obligation.identity.unit != self_.module.unit { self_.failure = squid_error::Error.core_limit; return; }
            let binding = obligation.identity.decl; if binding == 0 || binding >= self_.module.bindings.len { self_.failure = squid_error::Error.core_limit; return; }
            if self_.schemes_seen[binding] != self_.seen_epoch { self_.schemes_seen[binding] = self_.seen_epoch; pending.push(SchemeFrame { self_.module.binding(binding).scheme , ..}); } continue;
        }
        if self_.selection { self_.member(obligation.name, obligation.operator); continue; } if !obligation.explicit { continue; }
        match obligation.kind {
            dispatch, result_dispatch,
            receiver, field, writable_field, update => { self_.member(obligation.name, obligation.operator); },
            _ => {},
        }
    }
}
fn scan(self_: Capture&, body: squid_check_core::Body) -> Recipe, Error {
    let first_reference = self_.references.len; let first_member = self_.members.len;
    if self_.seen_epoch == 0xffffffff { for &mark in self_.schemes_seen { mark = 0; } self_.seen_epoch = 1; } else { self_.seen_epoch++; } self_.runtime_metadata = 0; self_.scheme(body.scheme); self_.node(body.root); var remaining = scan_limit;
    while self_.work_top != 0 {
        if self_.failure != squid_error::Error.none { return Recipe {..}, self_.failure; } if remaining == 0 { return Recipe {..}, squid_error::Error.core_limit; } remaining--;
        self_.work_top--; let item = self_.work[self_.work_top]; match item {
            node entry => { self_.scanNode(entry.id); },
            pattern entry => { self_.scanPattern(entry.id); },
        }
    }
    if self_.failure != squid_error::Error.none { return Recipe {..}, self_.failure; }
    if self_.references.len > 0xffffffff || self_.members.len > 0xffffffff { return Recipe {..}, squid_error::Error.core_limit; }
    return Recipe { references: squid_check_core::List { first_reference as u32, (self_.references.len - first_reference) as u32 , ..}, members: squid_check_core::List { first_member as u32, (self_.members.len - first_member) as u32 , ..}, runtime_metadata: self_.runtime_metadata , ..}, squid_error::Error.none;
}
fn scanNode(self_: Capture&, id: u32) {
    if id >= self_.module.nodes.len { self_.failure = squid_error::Error.core_limit; return; }
    let m .= self_.module; let n = m.node(id);
    var low: i64 = 0; var high = m.erased_declaration_references.len;
    while low < high { let middle = low + (high - low) / 2; if m.erased_declaration_references[middle].node < id { low = middle + 1; } else { high = middle; } }
    if low < m.erased_declaration_references.len && m.erased_declaration_references[low].node == id { self_.reference(m.erased_declaration_references[low].target, id); }
    match n.tag {
        fork_ => { self_.node(n.a); },
        with_handle => { self_.nodes(m.children(id)); self_.node(n.a); },
        comptime_for => { self_.node(n.b); },
        comptime_if => { self_.node(n.c); self_.node(n.b); self_.node(n.a); },
        comptime_meta => { if n.c == 0 { self_.node(n.a); } else if n.c == 8 || n.c == 9 { self_.node(n.b); } },
        spark => { let metadata = m.sparkInfo(id); self_.node(metadata.body); self_.pattern(metadata.pattern); self_.node(metadata.end); self_.node(metadata.source); },
        flat_op => { if n.c <= squid_check_core::flat_op_process_binding_hash { self_.node(n.a); } else if n.c == squid_check_core::flat_op_kernel_handle && n.a < m.kernels.len { let k = m.kernels[n.a]; if k.has_context { self_.reference(k.prepare_target, id); } self_.reference(k.run_target, id); } else if n.c == squid_check_core::flat_op_process_handle && n.a < m.processes.len { let p = m.processes[n.a]; self_.reference(p.init_target, id); self_.reference(p.step_target, id); } },
        contract_method => {
            self_.nodes(m.children(id)); let template = m.member_templates[n.a];
            for implementation in m.implementations {
                if !squid_structural::equal(implementation.contract, template.contract) { continue; }
                for method in m.implementation_members[implementation.members.start..implementation.members.start + implementation.members.len] { if method.kind == squid_reuse_principal_interface::ImplementationMemberKind.value && method.name == template.name { self_.reference(BindingRef { method.target.unit, method.target.binding , ..}, id); } }
            }
        },
        constant, primitive_function, panic, constructor_function, type_constructor => {},
        reference => { self_.reference(m.reference(id), id); },
        staging, scalar, logical, associated,
        type_same, effect_provider, handle => {
            self_.node(n.b); self_.node(n.a); if n.tag == squid_check_core::Tag.associated { self_.member(n.c); }
            if n.tag == squid_check_core::Tag.scalar && n.c != 0 { let op = operator(n.op); if op.present { self_.member(0, op.value); } }
        },
        call => { self_.reference(m.call(id).target, id); self_.nodes(m.children(id)); },
        block_, suite, product, record,
        array, array_op, storage => { self_.nodes(m.children(id)); },
        if_value, if_stmt, state_provider => { self_.node(n.c); self_.node(n.b); self_.node(n.a); },
        bind => { self_.scheme(m.binding(n.a).scheme); self_.node(n.b); },
        return_, project => {
            if self_.selection && n.tag == squid_check_core::Tag.project { if n.b >= m.projections.len { self_.failure = squid_error::Error.core_limit; return; } self_.member(m.projection(n.b).field); } self_.node(n.a);
        },
        result_associated => { self_.member(n.b); self_.node(n.a); },
        construct => { self_.node(n.b); },
        closure => { let metadata = m.closures[n.a]; if metadata.qualifier != 0 { self_.scheme(m.binding(metadata.qualifier).scheme); } self_.node(metadata.body); },
        apply => { self_.node(n.b); self_.node(n.a); },
        effect_reflection => {
            if self_.runtime_metadata == 0 { self_.runtime_metadata = id; }
            if n.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.count) || n.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.has) || n.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.same) { self_.node(n.c); self_.node(n.b); }
        },
        operation_value => { self_.node(m.operation_values[n.a].witness); },
        pattern_bind => { self_.node(n.c); self_.node(n.b); self_.pattern(n.a); },
        match_ => {
            let arms = m.matchArms(id); var index = arms.len;
            while index != 0 { index--; let arm = arms[index]; self_.node(arm.body); self_.node(arm.guard_); let rows = m.armRows(arm); var row = rows.len;
                while row != 0 { row--; let patterns = m.rowPatterns(rows[row]); var item = patterns.len; while item != 0 { item--; self_.pattern(patterns[item]); } }
            }
            self_.nodes(m.matchInputs(id));
        },
        update => {
            let metadata = m.updateInfo(id); self_.node(metadata.value); let selectors = m.updateSelectors(id);
            if self_.selection {
                for name in m.updatePath(id) { self_.member(name); }
                for step in selectors { if step.kind == squid_check_core::UpdateKind.field { if step.projection >= m.projections.len { self_.failure = squid_error::Error.core_limit; return; } self_.member(m.projection(step.projection).field); } }
            }
            var index = selectors.len; while index != 0 { index--; if selectors[index].kind == squid_check_core::UpdateKind.index { self_.node(selectors[index].index); } } self_.node(metadata.root);
        },
        loop_ => { let metadata = m.loopInfo(id); self_.node(metadata.body); self_.pattern(metadata.pattern); self_.node(metadata.end); self_.node(metadata.first); },
        break_ => { self_.nodes(m.breakValues(id)); },
        invalid => { self_.failure = squid_error::Error.core_limit; },
    }
}
fn scanPattern(self_: Capture&, id: u32) {
    if id >= self_.module.patterns.len { self_.failure = squid_error::Error.core_limit; return; } let pattern = self_.module.pattern(id);
    match pattern.tag {
        wildcard, bind, constant => {},
        value => { self_.node(pattern.a); },
        constructor, record_payload => { self_.pattern(pattern.b); },
        product => { let children = self_.module.patternChildren(id); var index = children.len; while index != 0 { index--; self_.pattern(children[index]); } },
        invalid => { self_.failure = squid_error::Error.core_limit; },
    }
}
fn operator(op: squid_check_core::Op) -> squid_support::Option<squid_check_types::Operator> {
    match op {
        add => { return squid_support::some(squid_check_types::Operator.add); }, sub => { return squid_support::some(squid_check_types::Operator.sub); },
        mul => { return squid_support::some(squid_check_types::Operator.mul); }, div => { return squid_support::some(squid_check_types::Operator.div); },
        rem => { return squid_support::some(squid_check_types::Operator.rem); }, equal => { return squid_support::some(squid_check_types::Operator.equal); },
        not_equal => { return squid_support::some(squid_check_types::Operator.not_equal); }, less => { return squid_support::some(squid_check_types::Operator.less); },
        less_equal => { return squid_support::some(squid_check_types::Operator.less_equal); }, greater => { return squid_support::some(squid_check_types::Operator.greater); },
        greater_equal => { return squid_support::some(squid_check_types::Operator.greater_equal); }, bit_and => { return squid_support::some(squid_check_types::Operator.bit_and); },
        bit_or => { return squid_support::some(squid_check_types::Operator.bit_or); }, bit_xor => { return squid_support::some(squid_check_types::Operator.bit_xor); },
        shift_left => { return squid_support::some(squid_check_types::Operator.shift_left); }, shift_right => { return squid_support::some(squid_check_types::Operator.shift_right); },
        _ => { return squid_support::none<squid_check_types::Operator>(); },
    }
}
fn capture(module: const Module&, declarations: Recipe[>..<]&, references: BindingRef[>..<]&, members: Member[>..<]&) -> Error {
    assert(module.declaration_dependencies.len == 0); assert(declarations.len == 0 && references.len == 0 && members.len == 0);
    var work: Work[>..] = []; var locations: u32[>..] = []; var collected_refs: BindingRef[>..] = []; var collected_members: Member[>..] = []; var seen: u32[>..] = []; for _ in module.bindings.len {seen.push(0 as u32);} let seen_marks=seen[..];
    var scan = Capture { module: module, work: work, references: collected_refs, locations: locations, members: collected_members, schemes_seen: seen_marks , ..};
    for index in module.bodies.len { declarations.push(Recipe {..}); }
    for body, offset in module.bodies[1..] { let recipe, error = scan.scan(body); if error != squid_error::Error.none { declarations.clear(); references.clear(); members.clear(); return error; } declarations[offset + 1] = recipe; }
    references.append(collected_refs[..]); members.append(collected_members[..]);
    return squid_error::Error.none;
}
fn spliceDependencies(previous: const Module&, result: const Module&, edited: const u32[:], declarations: Recipe[>..<]&, references: BindingRef[>..<]&, members: Member[>..<]&) -> bool, Error {
    if previous.declaration_dependencies.len != previous.bodies.len || result.bodies.len != previous.bodies.len {
        return false, squid_error::Error.none;
    }
    var is_edited: bool[>..] = [];
    is_edited.resize(result.bodies.len, false);
    for b in edited {
        if b < result.bindings.len {
            let bi = result.bindings[b].body_id;
            if bi != 0 && bi < is_edited.len { is_edited[bi] = true; }
        }
    }
    var work: Work[>..] = []; var locations: u32[>..] = []; var collected_refs: BindingRef[>..] = []; var collected_members: Member[>..] = []; var seen: u32[>..] = [];
    seen.resize(result.bindings.len, 0 as u32);
    let seen_marks = seen[..];
    var scan = Capture { module: result, work: work, references: collected_refs, locations: locations, members: collected_members, schemes_seen: seen_marks , ..};
    for _ in result.bodies.len { declarations.push(Recipe {..}); }
    for bi in 1..result.bodies.len {
        if is_edited[bi] {
            let recipe, error = scan.scan(result.bodies[bi]);
            if error != squid_error::Error.none { declarations.clear(); references.clear(); members.clear(); return false, error; }
            declarations[bi] = recipe;
        } else {
            let prev = previous.declaration_dependencies[bi];
            let first_ref = collected_refs.len;
            let first_mem = collected_members.len;
            if prev.references.len != 0 {
                collected_refs.append(previous.dependency_references[prev.references.start..prev.references.start + prev.references.len]);
            }
            if prev.members.len != 0 {
                collected_members.append(previous.dependency_members[prev.members.start..prev.members.start + prev.members.len]);
            }
            if collected_refs.len > 0xffffffff || collected_members.len > 0xffffffff {
                declarations.clear(); references.clear(); members.clear();
                return false, squid_error::Error.core_limit;
            }
            declarations[bi] = Recipe {
                references: squid_check_core::List { first_ref as u32, prev.references.len , ..},
                members: squid_check_core::List { first_mem as u32, prev.members.len , ..},
                runtime_metadata: prev.runtime_metadata , ..
            };
        }
    }
    references.append(collected_refs[..]);
    members.append(collected_members[..]);
    return true, squid_error::Error.none;
}
struct Selection { body: squid_check_core::Body, output: Member[>..<]& }
fn selectionMembers(module: const Module&, body: squid_check_core::Body, output: Member[>..<]&) -> Error { return withCapture(module, Selection { body, output , ..}, true, 0, select); }
fn select(scan: Capture&, context: Selection) -> Error { let recipe, error = scan.scan(context.body); if error != squid_error::Error.none { return error; } context.output.append(scan.members[..]); return squid_error::Error.none; }
reusable[] var owned_references: BindingRef[>..] = [];
reusable[] var owned_locations: u32[>..] = [];
fn copyReferences(source: const BindingRef[:]) -> BindingRef[:] { if source.len == 0 { return default<BindingRef[:]>(); } let out = owned_references.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn copyLocations(source: const u32[:]) -> u32[:] { if source.len == 0 { return default<u32[:]>(); } let out = owned_locations.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn releaseReferences(source: const BindingRef[:]) { if source.len != 0 { owned_references.free_slice(source); } }
fn releaseLocations(source: const u32[:]) { if source.len != 0 { owned_locations.free_slice(source); } }
struct Expression { references: BindingRef[:] = default<BindingRef[:]>(), locations: u32[:] = default<u32[:]>(), runtime_metadata: u32 = 0 }
fn deinit(self_: Expression&) { releaseReferences(self_.references); releaseLocations(self_.locations); self_ = Expression {..}; }
fn expression(module: const Module&, root: u32) -> Expression, Error { return withCapture(module, root, false, 0, captureExpression); }
fn captureExpression(scan: Capture&, root: u32) -> Expression, Error { let recipe, error = scan.scan(squid_check_core::Body { root: root , ..}); if error != squid_error::Error.none { return Expression {..}, error; } return Expression { copyReferences(scan.references[..]), copyLocations(scan.locations[..]), recipe.runtime_metadata , ..}, squid_error::Error.none; }
fn expressionReferences(module: const Module&, root: u32) -> BindingRef[:], Error { return withCapture(module, root, false, 0, captureReferences); }
fn captureReferences(scan: Capture&, root: u32) -> BindingRef[:], Error { let recipe, error = scan.scan(squid_check_core::Body { root: root , ..}); if error != squid_error::Error.none { return default<BindingRef[:]>(), error; } return copyReferences(scan.references[..]), squid_error::Error.none; }
fn usesBinding(module: const Module&, root: u32, binding: u32) -> bool, Error { return withCapture(module, root, false, binding, checkBinding); }
fn checkBinding(scan: Capture&, root: u32) -> bool, Error { let recipe, error = scan.scan(squid_check_core::Body { root: root , ..}); return scan.watched_used, error; }

// A successful check with frozen principals is insufficient when the old
// or new body participates in recursion with another global. Cold checking
// can infer both sides of a cycle as one component.
fn independentEdits(module:const Module&,edited:const u32[:])->bool {
 return withCapture(module,edited,true,0,independentEditGraph);
}

fn independentEditGraph(scan:Capture&,edited:const u32[:])->bool {
 let module .= scan.module;
 var pending:u32[>..]=[];
 var seen:bool[>..]=[];
 seen.resize(module.bindings.len,false);
 pending.append(edited);
 var i:i64=0;
 while i<pending.len {
  let binding=pending[i];
  i++;
  if seen[binding] {continue;}
  seen[binding]=true;
  let body_id=module.bindings[binding].body_id;
  if body_id==0 {continue;}
  let recipe,error=scan.scan(module.bodies[body_id]);
  if error!=squid_error::Error.none || recipe.runtime_metadata!=0 {return false;}
  for target in scan.references[recipe.references.start..recipe.references.start+recipe.references.len] {
   if !addSpliceDependency(module,target,edited,pending) {return false;}
  }
  for member in scan.members[recipe.members.start..recipe.members.start+recipe.members.len] {
   for method in module.associated {
    if member.name!=0 && member.name==method.member ||
       member.operator!=squid_check_types::Operator.none && member.operator==method.operator {
     if !addSpliceDependency(module,method.target,edited,pending) {return false;}
    }
   }
  }
 }
 return true;
}

fn addSpliceDependency(module:const Module&,reference:BindingRef,edited:const u32[:],pending:u32[>..]&)->bool {
 var target=reference;
 if target.unit==0 && module.bindings[target.binding].kind==squid_reuse_principal_interface::Kind.external {
  target=module.bindings[target.binding].target;
 }
 if target.unit!=0 && target.unit!=module.unit {return true;}
 for binding in edited {if binding==target.binding {return false;}}
 pending.push(target.binding);
 return true;
}
