// Reachability conservatively preserves every potentially touched global owner.
namespace blot_backend_storage_global_footprint;
import dictionary;
import check.core;
import check.types;
import reuse.declaration_dependencies;
import support.pooled_map;
import support.pooled_buffer;
import support.wyhash;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Ref = blot_check_core::BindingRef;
let limit: i64 = 100000;
struct Node {unit: u32,root: u32,start: u32 = 0,len: u32 = 0}
struct Edges {nodes: const Node[:] = default<const Node[:]>(),slots: const i64[:] = default<const i64[:]>(),all: bool = false}
fn hash(node: Node) -> u64 {let words: u32[4] = [node.unit,node.root,node.start,node.len];return blot_support_wyhash::hash(0,bytes_of(words));}
struct Targets {storage: Ref[:] = default<Ref[:]>(),items: Ref[:] = default<Ref[:]>()}
reusable[] var target_runs: Ref[>..] = [];
fn push(self_: Targets&,value: Ref) -> Error {return blot_support_pooled_buffer::push(self_,value,target_runs);}
fn deinit(self_: Targets&) {blot_support_pooled_buffer::deinit(self_,target_runs);}
struct SlotRun {items: i64[:]}
struct NodeRun {items: Node[:]}
struct SlotRuns {storage: SlotRun[:] = default<SlotRun[:]>(),items: SlotRun[:] = default<SlotRun[:]>()}
struct NodeRuns {storage: NodeRun[:] = default<NodeRun[:]>(),items: NodeRun[:] = default<NodeRun[:]>()}
reusable[] var slots_pool: i64[>..] = [];
reusable[] var nodes_pool: Node[>..] = [];
reusable[] var slot_run_pool: SlotRun[>..] = [];
reusable[] var node_run_pool: NodeRun[>..] = [];
reusable[] var unit_map_pool: dictionary_slot<u32,i64>[>..] = [];
reusable[] var global_map_pool: dictionary_slot<Ref,i64>[>..] = [];
reusable[] var name_map_pool: dictionary_slot<const u8[:],Targets>[>..] = [];
reusable[] var operator_map_pool: dictionary_slot<blot_check_types::Operator,Targets>[>..] = [];
reusable[] var direct_map_pool: dictionary_slot<Node,Edges>[>..] = [];
reusable[] var completed_map_pool: dictionary_slot<Node,const i64[:]>[>..] = [];
struct Index {
    units: const Module[:] = default<const Module[:]>(),unit_indices: blot_support_pooled_map::Map<u32,i64> = blot_support_pooled_map::Map<u32,i64> {..},globals: blot_support_pooled_map::Map<Ref,i64> = blot_support_pooled_map::Map<Ref,i64> {..},names: blot_support_pooled_map::Map<const u8[:],Targets> = blot_support_pooled_map::Map<const u8[:],Targets> {..},operators: blot_support_pooled_map::Map<blot_check_types::Operator,Targets> = blot_support_pooled_map::Map<blot_check_types::Operator,Targets> {..},unknown_names: bool = false,direct: blot_support_pooled_map::Map<Node,Edges> = blot_support_pooled_map::Map<Node,Edges> {..},completed: blot_support_pooled_map::Map<Node,const i64[:]> = blot_support_pooled_map::Map<Node,const i64[:]> {..},all: const i64[:] = default<const i64[:]>(),slot_runs: SlotRuns = SlotRuns {..},node_runs: NodeRuns = NodeRuns {..},
}
fn ownSlots(self_: Index&,values: const i64[:]) -> const i64[:],Error {if values.len == 0 {return default<const i64[:]>(),blot_error::Error.none;}let owned = slots_pool.alloc_slice(values.len);for index in 0..values.len {owned[index] = values[index];}let error = blot_support_pooled_buffer::push(self_.slot_runs,SlotRun {items: owned},slot_run_pool);if error != blot_error::Error.none {slots_pool.free_slice(owned);return default<const i64[:]>(),error;}return owned,blot_error::Error.none;}
fn ownNodes(self_: Index&,values: const Node[:]) -> const Node[:],Error {if values.len == 0 {return default<const Node[:]>(),blot_error::Error.none;}let owned = nodes_pool.alloc_slice(values.len);for index in 0..values.len {owned[index] = values[index];}let error = blot_support_pooled_buffer::push(self_.node_runs,NodeRun {items: owned},node_run_pool);if error != blot_error::Error.none {nodes_pool.free_slice(owned);return default<const Node[:]>(),error;}return owned,blot_error::Error.none;}
fn deinit(self_: Index&) {
    for slot in self_.names.slots {if slot.tag != 0 {var targets = slot.val;targets.deinit();}}for slot in self_.operators.slots {if slot.tag != 0 {var targets = slot.val;targets.deinit();}}
    blot_support_pooled_map::deinit(self_.unit_indices,unit_map_pool);blot_support_pooled_map::deinit(self_.globals,global_map_pool);blot_support_pooled_map::deinit(self_.names,name_map_pool);blot_support_pooled_map::deinit(self_.operators,operator_map_pool);blot_support_pooled_map::deinit(self_.direct,direct_map_pool);blot_support_pooled_map::deinit(self_.completed,completed_map_pool);
    for run in self_.slot_runs.items {slots_pool.free_slice(run.items);}for run in self_.node_runs.items {nodes_pool.free_slice(run.items);}blot_support_pooled_buffer::deinit(self_.slot_runs,slot_run_pool);blot_support_pooled_buffer::deinit(self_.node_runs,node_run_pool);self_.units = [];self_.all = [];
}
fn init(units: const Module[:],globals: const Ref[:]) -> Index,Error {
    var self_ = Index {units,..};if globals.len == 0 {return self_,blot_error::Error.none;}
    fn build() -> Error {
        var all: i64[>..] = [];for index in 0..globals.len {all.push(index);}let owned,error = self_.ownSlots(all);if error != blot_error::Error.none {return error;}self_.all = owned;for target,slot in globals {blot_support_pooled_map::insert(self_.globals,target,slot,global_map_pool);}
        for owner,index in units {blot_support_pooled_map::insert(self_.unit_indices,owner.unit,index,unit_map_pool);
            for candidate in owner.associated {
                var target = candidate.target;if target.unit == 0 {target.unit = owner.unit;}
                if candidate.member != 0 {let name = owner.fieldSpelling(candidate.member);if name.present {if !blot_support_pooled_map::contains(self_.names,name.value) {blot_support_pooled_map::insert(self_.names,name.value,Targets {..},name_map_pool);}let targets .= blot_support_pooled_map::get(self_.names,name.value);assert(targets);let error = targets.push(target);if error != blot_error::Error.none {return error;}}else {self_.unknown_names = true;}}
                if candidate.operator != blot_check_types::Operator.none {if !blot_support_pooled_map::contains(self_.operators,candidate.operator) {blot_support_pooled_map::insert(self_.operators,candidate.operator,Targets {..},operator_map_pool);}let targets .= blot_support_pooled_map::get(self_.operators,candidate.operator);assert(targets);let error = targets.push(target);if error != blot_error::Error.none {return error;}}
            }
        }return blot_error::Error.none;
    }
    let error = build();if error != blot_error::Error.none {self_.deinit();}return self_,error;
}
fn module(self_: const Index&,unit: u32) -> const Module? {let index .= blot_support_pooled_map::get(self_.unit_indices,unit);if !index {return null;}return self_.units[index];}
fn key(unit: u32,root: u32,scheme: blot_check_types::Scheme) -> Node {Node {unit: unit,root: root,start: scheme.obligations.start,len: scheme.obligations.len}}
fn reference(self_: Index&,source: u32,target_: Ref,nodes: dictionary<Node,bool>&,slots: dictionary<i64,bool>&) -> Error {
    var target = target_;if target.unit == 0 {target.unit = source;}var remaining = limit;
    while remaining != 0 {remaining--;let slot .= blot_support_pooled_map::get(self_.globals,target);if slot {slots.insert(slot,true);return blot_error::Error.none;}let owner .= self_.module(target.unit);if !owner || target.binding == 0 || target.binding >= owner.bindings.len {return blot_error::Error.core_limit;}let binding = owner.binding(target.binding);if binding.kind == blot_reuse_principal_interface::Kind.external {target = binding.target;if target.unit == 0 {target.unit = owner.unit;}continue;}if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= owner.bodies.len {return blot_error::Error.core_limit;}let body .= owner.body(target.binding);assert(body);nodes.insert(key(owner.unit,body.root,body.scheme),true);return blot_error::Error.none;}
    return blot_error::Error.core_limit;
}
fn scan(self_: Index&,node: Node) -> Edges,Error {
    let owner .= self_.module(node.unit);if !owner || node.root >= owner.nodes.len || node.start > owner.obligations.len || node.len > owner.obligations.len - node.start {return Edges {..},blot_error::Error.core_limit;}
    let captured,error = blot_reuse_declaration_dependencies::expression(owner,node.root);if error != blot_error::Error.none {return Edges {..},error;}var expression = captured;
    fn capture() -> Edges,Error {
        if expression.runtime_metadata != 0 {return Edges {..},blot_error::Error.core_limit;}var members: blot_check_core::DependencyMember[>..<] = [];
        let selected = blot_reuse_declaration_dependencies::selectionMembers(owner,blot_check_core::Body {root: node.root,scheme: blot_check_types::Scheme {obligations: blot_check_types::List {start: node.start,len: node.len},..},..},members);if selected != blot_error::Error.none {return Edges {..},selected;}
        var nodes: dictionary<Node,bool> = dictionary<Node,bool> {};var slots: dictionary<i64,bool> = dictionary<i64,bool> {};
        for target in expression.references {let error = self_.reference(owner.unit,target,nodes,slots);if error != blot_error::Error.none {return Edges {..},error;}}
        for member in members {
            if member.name != 0 {let name = owner.fieldSpelling(member.name);if !name.present || self_.unknown_names {return Edges {..},blot_error::Error.core_limit;}let targets .= blot_support_pooled_map::get(self_.names,name.value);if targets {for target in targets.items {let error = self_.reference(owner.unit,target,nodes,slots);if error != blot_error::Error.none {return Edges {..},error;}}}}
            if member.operator != blot_check_types::Operator.none {let targets .= blot_support_pooled_map::get(self_.operators,member.operator);if targets {for target in targets.items {let error = self_.reference(owner.unit,target,nodes,slots);if error != blot_error::Error.none {return Edges {..},error;}}}}if nodes.count > limit {return Edges {..},blot_error::Error.core_limit;}
        }
        var children: Node[>..] = [];for slot in nodes.slots {if slot.tag != 0 {children.push(slot.key);}}var global_slots: i64[>..] = [];for slot in slots.slots {if slot.tag != 0 {global_slots.push(slot.key);}}
        let child_nodes,error = self_.ownNodes(children);if error != blot_error::Error.none {return Edges {..},error;}let owned_slots,slot_error = self_.ownSlots(global_slots);if slot_error != blot_error::Error.none {return Edges {..},slot_error;}return Edges {nodes: child_nodes,slots: owned_slots,..},blot_error::Error.none;
    }
    let result,result_error = capture();expression.deinit();return result,result_error;
}
fn edges(self_: Index&,node: Node) -> Edges,Error {let known .= blot_support_pooled_map::get(self_.direct,node);if known {return known,blot_error::Error.none;}let value,error = self_.scan(node);if error == blot_error::Error.out_of_memory {return Edges {..},error;}var selected = value;if error != blot_error::Error.none {selected = Edges {all: true,..};}blot_support_pooled_map::insert(self_.direct,node,selected,direct_map_pool);return selected,blot_error::Error.none;}
fn slots(self_: Index&,unit: u32,root: u32,scheme: blot_check_types::Scheme) -> const i64[:],Error {
    if self_.all.len == 0 {return self_.all,blot_error::Error.none;}let query = key(unit,root,scheme);let cached .= blot_support_pooled_map::get(self_.completed,query);if cached {return cached,blot_error::Error.none;}var pending: Node[>..<] = [];var seen: dictionary<Node,bool> = dictionary<Node,bool> {};var selected: bool[>..] = [];for slot in self_.all {selected.push(false);}pending.push(query);var remaining = limit;
    while pending.len != 0 {
        let node = pending[pending.len - 1];pending.resize(pending.len - 1);if seen.get(node) {continue;}if remaining == 0 {blot_support_pooled_map::insert(self_.completed,query,self_.all,completed_map_pool);return self_.all,blot_error::Error.none;}remaining--;seen.insert(node,true);
        let known .= blot_support_pooled_map::get(self_.completed,node);if known {for slot in known {selected[slot] = true;}continue;}
        let value,error = self_.edges(node);if error != blot_error::Error.none {return default<const i64[:]>(),error;}if value.all {blot_support_pooled_map::insert(self_.completed,query,self_.all,completed_map_pool);return self_.all,blot_error::Error.none;}for slot in value.slots {selected[slot] = true;}
        if value.nodes.len > limit || pending.len > limit - value.nodes.len {blot_support_pooled_map::insert(self_.completed,query,self_.all,completed_map_pool);return self_.all,blot_error::Error.none;}pending.append(value.nodes);
    }
    var selected_slots: i64[>..] = [];for present,slot in selected {if present {selected_slots.push(slot);}}let result,error = self_.ownSlots(selected_slots);if error != blot_error::Error.none {return default<const i64[:]>(),error;}blot_support_pooled_map::insert(self_.completed,query,result,completed_map_pool);return result,blot_error::Error.none;
}
