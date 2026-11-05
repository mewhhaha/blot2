// Finite source access footprints for fixed-owner recursive calls.
namespace blot_backend_storage_recursive_admission;
import dictionary;
import check.core;
import check.types;
import eval.body_recipe;
import .collection_ops;
import .optimizer_buffers;
import support.error;
import support.option;
import support.pooled_map;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Ref = blot_check_core::BindingRef;
type TypeTag = blot_check_types::Tag;
let limit: i64 = 100000;
struct Access {read: bool = false,write: bool = false}
struct Contract {parameter_access: const Access[:],self_recursive: bool,work: i64,backedges: i64}
struct Edge {target: Ref,owners: const blot_support::Option<i64>[:]}
struct Direct {access: Access[:],edges: const Edge[:],self_edges: i64,result: TypeTag,work: i64}
struct Accesses {storage: Access[:] = [],items: Access[:] = []}
struct Edges {storage: Edge[:] = [],items: Edge[:] = []}
struct Contracts {storage: Contract[:] = [],items: Contract[:] = []}
reusable[] var access_pool: Access[>..] = [];
reusable[] var edge_pool: Edge[>..] = [];
reusable[] var owner_pool: blot_support::Option<i64>[>..] = [];
reusable[] var contract_pool: Contract[>..] = [];
reusable[] var candidate_pool: dictionary_slot<Ref,bool>[>..] = [];
reusable[] var source_pool: dictionary_slot<Ref,blot_support::Option<Direct>>[>..] = [];
reusable[] var completed_pool: dictionary_slot<Ref,blot_support::Option<Contract>>[>..] = [];
reusable[] var solved_pool: dictionary_slot<Ref,Contract>[>..] = [];
reusable[] var alias_pool: dictionary_slot<u32,u32>[>..] = [];
struct Cache {candidates: blot_support_pooled_map::Map<Ref,bool> = blot_support_pooled_map::Map<Ref,bool> {..},sources: blot_support_pooled_map::Map<Ref,blot_support::Option<Direct>> = blot_support_pooled_map::Map<Ref,blot_support::Option<Direct>> {..},completed: blot_support_pooled_map::Map<Ref,blot_support::Option<Contract>> = blot_support_pooled_map::Map<Ref,blot_support::Option<Contract>> {..},contracts: Contracts = Contracts {..},discovery_bodies: i64 = 0,discovery_nodes: i64 = 0,scans: i64 = 0,nodes: i64 = 0}
fn freeAccess(values: const Access[:]) {if values.len != 0 {let first: const Access& = values[0];let index = access_pool.index_of(first);access_pool.free_slice(access_pool[index..index + values.len]);}}
fn freeOwners(values: const blot_support::Option<i64>[:]) {if values.len != 0 {let first: const blot_support::Option<i64>& = values[0];let index = owner_pool.index_of(first);owner_pool.free_slice(owner_pool[index..index + values.len]);}}
fn freeEdges(values: const Edge[:]) {for edge in values {freeOwners(edge.owners);}if values.len != 0 {let first: const Edge& = values[0];let index = edge_pool.index_of(first);edge_pool.free_slice(edge_pool[index..index + values.len]);}}
fn deinit(self: Cache&) {for slot in self.sources.slots {if slot.tag != 0 && slot.val.present {freeAccess(slot.val.value.access);freeEdges(slot.val.value.edges);}}for contract in self.contracts.items {freeAccess(contract.parameter_access);}blot_support_pooled_buffer::deinit(self.contracts,contract_pool);blot_support_pooled_map::deinit(self.candidates,candidate_pool);blot_support_pooled_map::deinit(self.sources,source_pool);blot_support_pooled_map::deinit(self.completed,completed_pool);self = Cache {..};}
fn owner(units: const Module[:],unit: u32) -> const Module? {if unit != 0 && unit <= units.len && units[unit - 1].unit == unit {return units[unit - 1];}for &module in units {if module.unit == unit {return module;}}return null;}
fn canonical(units: const Module[:],target_: Ref) -> blot_support::Option<Ref> {var target = target_;for attempt in 0..128 {let module .= owner(units,target.unit);if !module || target.binding == 0 || target.binding >= module.bindings.len {return blot_support::none<Ref>();}let binding = module.binding(target.binding);if binding.kind != blot_check_core::BindingKind.external {return blot_support::some(target);}target = binding.target;if target.unit == 0 {target.unit = module.unit;}}return blot_support::none<Ref>();}
fn scalar(module: const Module&,ty: u32) -> bool {let tag = module.types.node(ty).tag;return tag == TypeTag.unit || tag == TypeTag.unsigned32 || tag == TypeTag.boolean || tag == TypeTag.never;}
fn array(module: const Module&,ty: u32) -> bool {let node = module.types.node(ty);return node.tag == TypeTag.array && module.types.node(node.a).tag == TypeTag.unsigned32;}
fn closed(scheme: blot_check_types::Scheme) -> bool {return scheme.variables.len == 0 && scheme.obligations.len == 0 && scheme.generative.len == 0;}
fn pureRow(module: const Module&,row: u32,scheme: blot_check_types::Scheme) -> bool {let value = module.types.row(row);if value.labels.len != 0 {return false;}match value.tail {closed=>{return true;},variable variable=>{for expected in module.types.list(scheme.closed_rows) {if variable.value == expected {return true;}}for expected in module.types.list(scheme.row_variables) {if variable.value == expected {return true;}}return false;},_=>{return false;},}}
struct Walk {units: const Module[:],module: const Module&,body: const blot_check_core::Body&,target: Ref,aliases: blot_support_pooled_map::Map<u32,u32> = blot_support_pooled_map::Map<u32,u32> {..},remaining: i64 = limit}
recursive fn origin(self: Walk&,id: u32,depth: i64) -> i64,Error {if id == 0 || depth == 128 || self.remaining == 0 {return 0,Error.declined;}self.remaining--;let node = self.module.node(id);if node.tag == blot_check_core::Tag.update {return bindingOriginFromUpdate(self,id,depth);}if node.tag != blot_check_core::Tag.reference {return 0,Error.declined;}let reference = self.module.reference(id);if reference.unit != 0 && reference.unit != self.module.unit {return 0,Error.declined;}return self.bindingOrigin(reference.binding,depth + 1);}
recursive fn bindingOriginFromUpdate(self: Walk&,id: u32,depth: i64) -> i64,Error {return self.origin(self.module.updateInfo(id).root,depth + 1);}
recursive fn bindingOrigin(self: Walk&,binding: u32,depth: i64) -> i64,Error {if depth >= 128 || binding == 0 || binding >= self.module.bindings.len || self.remaining == 0 {return 0,Error.declined;}self.remaining--;for parameter,index in self.module.bodyParameters(self.body) {if parameter.binding == binding && array(self.module,parameter.ty) {return index,Error.none;}}let prior .= blot_support_pooled_map::get(self.aliases,binding);if prior {return self.bindingOrigin(prior,depth + 1);}let source = self.module.binding(binding);if source.kind != blot_check_core::BindingKind.local || source.initializer == 0 {return 0,Error.declined;}return self.origin(source.initializer,depth + 1);}
fn scalarBinding(self: const Walk&,binding: u32) -> bool {return binding != 0 && binding < self.module.bindings.len && scalar(self.module,self.module.binding(binding).ty);}
fn scan(self: Walk&) -> Direct,Error {
    let module .= self.module;let source = module.binding(self.target.binding);if !self.body.is_function || source.kind != blot_check_core::BindingKind.global || !closed(self.body.scheme) || !closed(source.scheme) {return Direct {..},Error.declined;}let parameters = module.bodyParameters(self.body);if source.scheme.closed_rows.len > limit || source.scheme.row_variables.len > limit || parameters.len > 128 {return Direct {..},Error.declined;}var signature = source.ty;
    for parameter in parameters {let arrow = module.types.node(signature);if (!scalar(module,parameter.ty) && !array(module,parameter.ty)) || arrow.tag != TypeTag.function || arrow.a != parameter.ty || !pureRow(module,arrow.c,source.scheme) {return Direct {..},Error.declined;}signature = arrow.b;}
    if !scalar(module,signature) || signature != module.typeOf(self.body.root) {return Direct {..},Error.declined;}var recipes = blot_eval_body_recipe::Cache {..};var owner_index: i64 = -1;for unit,index in self.units {if unit.unit == module.unit {owner_index = index;break;}}if owner_index < 0 {return Direct {..},Error.declined;}
    let recipe,recipe_error = recipes.get(self.units,blot_eval_body_recipe::Key {owner: owner_index,body: self.body.root,callables: false},limit);if recipe_error != Error.none || !recipe {recipes.deinit();if recipe_error == Error.none {return Direct {..},Error.declined;}return Direct {..},recipe_error;}
    let visits = recipe.visits;var accesses = Accesses {..};var edges = Edges {..};var transferred = false;
    fn walkVisits() -> Direct,Error {
        for id in visits {let node = module.node(id);if node.tag == blot_check_core::Tag.loop_ {for carry in module.loopCarries(id) {if self.scalarBinding(carry.incoming) {continue;}blot_support_pooled_map::insert(self.aliases,carry.iteration,carry.incoming,alias_pool);blot_support_pooled_map::insert(self.aliases,carry.outgoing,carry.incoming,alias_pool);}}
            else if node.tag == blot_check_core::Tag.if_value || node.tag == blot_check_core::Tag.if_stmt {for merge in module.branchMerges(id) {if !self.scalarBinding(merge.result) {blot_support_pooled_map::insert(self.aliases,merge.result,merge.then_binding,alias_pool);}}}
        }
        for parameter in parameters {let error = blot_support_pooled_buffer::push(accesses,Access {..},access_pool);if error != Error.none {return Direct {..},error;}}var self_edges: i64 = 0;
        for id in visits {let node = module.node(id);if !scalar(module,node.ty) && !array(module,node.ty) {return Direct {..},Error.declined;}
            match node.tag {
                constant=>{if !scalar(module,node.ty) {return Direct {..},Error.declined;}},
                reference=>{let reference = module.reference(id);if (reference.unit != 0 && reference.unit != module.unit) || reference.binding == 0 || reference.binding >= module.bindings.len {return Direct {..},Error.declined;}let kind = module.binding(reference.binding).kind;if kind != blot_check_core::BindingKind.local && kind != blot_check_core::BindingKind.parameter {return Direct {..},Error.declined;}if array(module,node.ty) {let owner,error = self.origin(id,0);if error != Error.none {return Direct {..},error;}}},
                scalar=>{if node.c != 0 {return Direct {..},Error.declined;}match node.op {add,sub,mul,div,rem,equal,not_equal,less,less_equal,greater,greater_equal,bit_and,bit_or,bit_xor,shift_left,shift_right,min,max,bit_not,neg=>{},_=>{return Direct {..},Error.declined;},}},
                logical,bind,return_,block_,suite,panic,break_=>{},
                pattern_bind=>{match module.pattern(node.a).tag {bind,wildcard=>{},_=>{return Direct {..},Error.declined;},}},
                if_value,if_stmt=>{for merge in module.branchMerges(id) {if !self.scalarBinding(merge.result) {let first,error = self.bindingOrigin(merge.then_binding,0);if error != Error.none {return Direct {..},error;}let second,second_error = self.bindingOrigin(merge.else_binding,0);if second_error != Error.none {return Direct {..},second_error;}if first != second {return Direct {..},Error.declined;}}}},
                loop_=>{let loop = module.loopInfo(id);match loop.kind {array=>{return Direct {..},Error.declined;},_=>{},}if loop.pattern != 0 {match module.pattern(loop.pattern).tag {bind,wildcard=>{},_=>{return Direct {..},Error.declined;},}}for carry in module.loopCarries(id) {if !self.scalarBinding(carry.incoming) {let first,error = self.bindingOrigin(carry.incoming,0);if error != Error.none {return Direct {..},error;}let second,second_error = self.bindingOrigin(carry.backedge,0);if second_error != Error.none {return Direct {..},second_error;}if first != second {return Direct {..},Error.declined;}}}},
                update=>{let update = module.updateInfo(id);let selectors = module.updateSelectors(id);if module.updatePath(id).len != 0 || selectors.len != 1 || !array(module,selectors[0].source_type) || module.types.node(selectors[0].result_type).tag != TypeTag.unsigned32 {return Direct {..},Error.declined;}match selectors[0].kind {index=>{},_=>{return Direct {..},Error.declined;},}let owner,error = self.origin(update.root,0);if error != Error.none {return Direct {..},error;}accesses.items[owner].read = true;accesses.items[owner].write = true;},
                array_op=>{let operands = module.children(id);let op = module.arrayOperation(id);if (op != blot_backend_collection_ops::Op.get && op != blot_backend_collection_ops::Op.length) || operands.len == 0 || !array(module,module.typeOf(operands[0])) {return Direct {..},Error.declined;}let index,error = self.origin(operands[0],0);if error != Error.none {return Direct {..},error;}if op == blot_backend_collection_ops::Op.get {accesses.items[index].read = true;}},
                call=>{
                    let call = module.call(id);var called = call.target;if called.unit == 0 {called.unit = module.unit;}let resolved = canonical(self.units,called);if !resolved.present {return Direct {..},Error.declined;}called = resolved.value;let callee .= owner(self.units,called.unit);assert(callee);let body .= callee.body(called.binding);if !body {return Direct {..},Error.declined;}let formals = callee.bodyParameters(body);if formals.len > 128 || call.arguments.len != formals.len {return Direct {..},Error.declined;}let owners = owner_pool.alloc_slice(formals.len);for index in 0..formals.len {owners[index] = blot_support::none<i64>();}
                    fn arguments() -> Error {for index in 0..formals.len {let formal = formals[index];let argument = call.arguments[index];if array(callee,formal.ty) {if !array(module,module.typeOf(argument)) {return Error.declined;}let original,error = self.origin(argument,0);if error != Error.none {return error;}owners[index] = blot_support::some(original);if called == self.target && original != index {return Error.declined;}}else if !scalar(callee,formal.ty) || module.types.node(module.typeOf(argument)).tag != callee.types.node(formal.ty).tag {return Error.declined;}}return Error.none;}
                    let checked = arguments();if checked != Error.none {freeOwners(owners);return Direct {..},checked;}if called == self.target {self_edges++;freeOwners(owners);}else {let error = blot_support_pooled_buffer::push(edges,Edge {target: called,owners},edge_pool);if error != Error.none {freeOwners(owners);return Direct {..},error;}}
                },_=>{return Direct {..},Error.declined;},
            }
        }
        // Move exact live runs, releasing excess backing capacity first.
        let access = access_pool.alloc_slice(accesses.items.len);for index in 0..access.len {access[index] = accesses.items[index];}
        let selected_edges = edge_pool.alloc_slice(edges.items.len);for index in 0..selected_edges.len {selected_edges[index] = edges.items[index];}
        transferred = true;return Direct {access,edges: selected_edges,self_edges,result: module.types.node(signature).tag,work: visits.len},Error.none;
    }
    let result,error = walkVisits();if !transferred {for edge in edges.items {freeOwners(edge.owners);}}blot_support_pooled_buffer::deinit(edges,edge_pool);blot_support_pooled_buffer::deinit(accesses,access_pool);recipes.deinit();return result,error;
}
fn direct(self: Cache&,units: const Module[:],target: Ref) -> Direct,Error {
    let known .= blot_support_pooled_map::get(self.sources,target);if known {if known.present {return known.value,Error.none;}return Direct {..},Error.declined;}
    let module .= owner(units,target.unit);if !module {return Direct {..},Error.declined;}let body .= module.body(target.binding);if !body {return Direct {..},Error.declined;}var walk = Walk {units,module,body,target,..};let result,error = walk.scan();blot_support_pooled_map::deinit(walk.aliases,alias_pool);
    if error == Error.out_of_memory {return Direct {..},error;}var retained = blot_support::none<Direct>();if error == Error.none {retained = blot_support::some(result);}blot_support_pooled_map::insert(self.sources,target,retained,source_pool);self.scans++;if retained.present {self.nodes += result.work;return result,Error.none;}return Direct {..},Error.declined;
}
struct Solve {cache: Cache&,units: const Module[:],root: Ref,active: Ref[128] = [Ref {..};128],completed: blot_support_pooled_map::Map<Ref,Contract> = blot_support_pooled_map::Map<Ref,Contract> {..},remaining: i64 = limit}
recursive fn run(self: Solve&,target: Ref,depth: i64) -> Contract,Error {
    if depth == 128 || self.remaining == 0 {return Contract {..},Error.declined;}let known .= blot_support_pooled_map::get(self.completed,target);if known {return known,Error.none;}for active in self.active[..depth] {if active == target {return Contract {..},Error.declined;}}self.remaining--;
    let direct,error = self.cache.direct(self.units,target);if error != Error.none {return Contract {..},error;}if direct.work > self.remaining {return Contract {..},Error.declined;}self.remaining -= direct.work;let root = self.root == target;
    if !root && direct.self_edges != 0 {return Contract {..},Error.declined;}
    if root {let module .= owner(self.units,target.unit);assert(module);let body .= module.body(target.binding);assert(body);for parameter in module.bodyParameters(body) {if module.types.node(parameter.ty).tag != TypeTag.unsigned32 && !array(module,parameter.ty) {return Contract {..},Error.declined;}}if direct.result != TypeTag.unit || direct.self_edges == 0 {return Contract {..},Error.declined;}}
    self.active[depth] = target;let access = access_pool.alloc_slice(direct.access.len);for index in 0..access.len {access[index] = direct.access[index];}var work = direct.work;
    for edge in direct.edges {let child,error = self.run(edge.target,depth + 1);if error != Error.none {freeAccess(access);return Contract {..},error;}if child.work > limit - work {freeAccess(access);return Contract {..},Error.declined;}work += child.work;assert(child.parameter_access.len == edge.owners.len);for effect,index in child.parameter_access {let ordinal = edge.owners[index];if ordinal.present {access[ordinal.value].read = access[ordinal.value].read || effect.read;access[ordinal.value].write = access[ordinal.value].write || effect.write;}}}
    let result = Contract {parameter_access: access,self_recursive: root,work,backedges: direct.self_edges};let recorded = blot_support_pooled_buffer::push(self.cache.contracts,result,contract_pool);if recorded != Error.none {freeAccess(access);return Contract {..},recorded;}blot_support_pooled_map::insert(self.completed,target,result,solved_pool);return result,Error.none;
}
fn analyze(self: Cache&,units: const Module[:],target_: Ref) -> blot_support::Option<Contract>,Error {
    let selected = canonical(units,target_);if !selected.present {return blot_support::none<Contract>(),Error.none;}let target = selected.value;let cached .= blot_support_pooled_map::get(self.completed,target);if cached {return cached,Error.none;}let module .= owner(units,target.unit);assert(module);let body .= module.body(target.binding);if !body {return blot_support::none<Contract>(),Error.none;}
    var candidate = false;
    {let known .= blot_support_pooled_map::get(self.candidates,target);if known {candidate = known;}else {
        self.discovery_bodies++;var pending_items: u32[>..<] = [];var pending = blot_eval_body_recipe::Pending {items: pending_items,limit};var seen: dictionary<u32,bool> = {};var found = false;let queued = pending.append(body.root);if queued == Error.out_of_memory {return blot_support::none<Contract>(),queued;}if queued == Error.plan_limit {return blot_support::none<Contract>(),Error.none;}
        while pending_items.len != 0 {
            let id = pending_items[pending_items.len - 1];pending_items.resize(pending_items.len - 1);if id == 0 || seen.get(id) {continue;}if id >= module.nodes.len || seen.count == limit {break;}seen.insert(id,true);self.discovery_nodes++;let node = module.node(id);
            if node.tag == blot_check_core::Tag.call {var called = module.call(id).target;if called.unit == 0 {called.unit = module.unit;}let resolved = canonical(units,called);if resolved.present && resolved.value == target {found = true;break;}}
            let appended = blot_eval_body_recipe::appendChildren(pending,module,id,false);if appended == Error.out_of_memory {return blot_support::none<Contract>(),appended;}if appended == Error.plan_limit {break;}
        }
        blot_support_pooled_map::insert(self.candidates,target,found,candidate_pool);candidate = found;
    }}
    var result = blot_support::none<Contract>();if candidate {var solve = Solve {cache: self,units,root: target,..};let contract,error = solve.run(target,0);blot_support_pooled_map::deinit(solve.completed,solved_pool);if error == Error.out_of_memory {return result,error;}if error == Error.none {result = blot_support::some(contract);}}
    blot_support_pooled_map::insert(self.completed,target,result,completed_pool);return result,Error.none;
}
