// Exact specialization keys contain static evidence; runtime words remain ABI inputs.
namespace blot_backend_storage_calls;
import check.core;
import check.types;
import check.effects;
import check.storage_ops;
import check.storage_types;
import .collection_ops;
import .simd_intrinsics;
import .optimizer_buffers;
import support.pooled_buffer;
import support.pooled_map;
import support.wyhash;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Ref = blot_check_core::BindingRef;
type Tag = blot_check_core::Tag;
type TypeTag = blot_check_types::Tag;
type Words = blot_backend_optimizer_buffers::Words;
struct Key {unit: u32,binding: u32,context: u32 = 0,context_free: bool = false,evidence: const u32[:]}
fn eql(self_: Key,other: Key) -> bool {return self_.unit == other.unit && self_.binding == other.binding && self_.context == other.context && self_.context_free == other.context_free && self_.evidence == other.evidence;}
fn hash(key: Key) -> u64 {var free: u32 = 0;if key.context_free {free = 1;}let header: u32[4] = [key.unit,key.binding,key.context,free];var state = blot_support_wyhash::init(0);blot_support_wyhash::update(state,bytes_of(header));blot_support_wyhash::update(state,bytes_of(key.evidence));return blot_support_wyhash::final(state);}
struct Entry {key: Key,function: u32,floating: bool,building: bool = true,context_sensitive: bool = true,next: blot_support::Option<i64> = blot_support::none<i64>(),previous: blot_support::Option<i64> = blot_support::none<i64>()}
enum TargetKind {named,closure}
struct Target {unit: u32,id: u32,kind: TargetKind,context: u32 = 0}
struct Frame {target: Target,start: i64,length: i64}
struct Frames {storage: Frame[:] = default<Frame[:]>(),items: Frame[:] = default<Frame[:]>()}
reusable[] var frame_runs: Frame[>..] = [];
struct ActiveCalls {frames: Frames = Frames {..},selections: Words = Words {..}}
fn deinit(self_: ActiveCalls&) {blot_support_pooled_buffer::deinit(self_.frames,frame_runs);self_.selections.deinit();}
fn contains(self_: const ActiveCalls&,target: Target,selection: const u32[:]) -> bool {for frame in self_.frames.items {if frame.target == target && self_.selections.items[frame.start..frame.start + frame.length] == selection {return true;}}return false;}
fn enter(self_: ActiveCalls&,target: Target,selection: const u32[:]) -> bool,Error {
    if self_.contains(target,selection) {return false,blot_error::Error.none;}let frame_capacity = blot_support_pooled_buffer::ensure(self_.frames,self_.frames.items.len + 1,frame_runs);if frame_capacity != blot_error::Error.none {return false,frame_capacity;}let selection_capacity = self_.selections.ensure(self_.selections.len + selection.len);if selection_capacity != blot_error::Error.none {return false,selection_capacity;}let start = self_.selections.len;let added = self_.selections.append(selection);if added != blot_error::Error.none {return false,added;}let framed = blot_support_pooled_buffer::push(self_.frames,Frame {target: target,start: start,length: selection.len},frame_runs);if framed != blot_error::Error.none {self_.selections.resize(start);return false,framed;}return true,blot_error::Error.none;
}
fn leave(self_: ActiveCalls&) {assert(self_.frames.items.len != 0);let frame = self_.frames.items[self_.frames.items.len - 1];blot_support_pooled_buffer::resize(self_.frames,self_.frames.items.len - 1);self_.selections.resize(frame.start);}
struct Admission {key: Key,height: i64}
struct Chain {first: i64,last: i64}
struct Entries {storage: Entry[:] = default<Entry[:]>(),items: Entry[:] = default<Entry[:]>()}
struct Admissions {storage: Admission[:] = default<Admission[:]>(),items: Admission[:] = default<Admission[:]>()}
reusable[] var entry_runs: Entry[>..] = [];
reusable[] var admission_runs: Admission[>..] = [];
reusable[] var evidence_runs: u32[>..] = [];
reusable[] var entry_slots: dictionary_slot<Key,Chain>[>..] = [];
reusable[] var plan_slots: dictionary_slot<Key,i64>[>..] = [];
struct Cache {entries: Entries = Entries {..},plans: Admissions = Admissions {..},entry_positions: blot_support_pooled_map::Map<Key,Chain> = blot_support_pooled_map::Map<Key,Chain> {..},plan_positions: blot_support_pooled_map::Map<Key,i64> = blot_support_pooled_map::Map<Key,i64> {..},removed_keys: i64 = 0}
fn own(key: Key) -> Key {var owned = key;if key.evidence.len == 0 {owned.evidence=default<const u32[:]>();}else {let values = evidence_runs.alloc_slice(key.evidence.len);for index in 0..values.len {values[index] = key.evidence[index];}owned.evidence = values;}return owned;}
fn release(key: Key) {if key.evidence.len != 0 {let first: const u32& = key.evidence[0];let index = evidence_runs.index_of(first);evidence_runs.free_slice(evidence_runs[index..index + key.evidence.len]);}}
fn deinit(self_: Cache&) {blot_support_pooled_map::deinit(self_.entry_positions,entry_slots);blot_support_pooled_map::deinit(self_.plan_positions,plan_slots);for entry in self_.entries.items {release(entry.key);}for plan in self_.plans.items {release(plan.key);}blot_support_pooled_buffer::deinit(self_.entries,entry_runs);blot_support_pooled_buffer::deinit(self_.plans,admission_runs);self_.removed_keys = 0;}
fn checkpoint(self_: const Cache&) -> i64 {return self_.entries.items.len;}
fn rollbackEntries(self_: Cache&,mark: i64) {
    assert(mark <= self_.entries.items.len);var at = self_.entries.items.len;
    while at > mark {at--;let entry = self_.entries.items[at];let chain .= blot_support_pooled_map::get(self_.entry_positions,entry.key);assert(chain != null);assert(chain.last == at && !entry.next.present);if entry.previous.present {self_.entries.items[entry.previous.value].next = blot_support::none<i64>();chain.last = entry.previous.value;}else {assert(chain.first == at);let removed = blot_support_pooled_map::remove(self_.entry_positions,entry.key);assert(removed);self_.removed_keys++;}release(entry.key);}
    blot_support_pooled_buffer::resize(self_.entries,mark);
    // Backward-shift deletion already removes every tombstone. Preserve the
    // native amortization epoch counters without a redundant full-table scan.
    if self_.entry_positions.count == 0 {blot_support_pooled_map::clear(self_.entry_positions);self_.removed_keys = 0;}else if self_.removed_keys >= self_.entry_positions.slots.len / 8 {self_.removed_keys = 0;}
}
fn admitted(self_: const Cache&,key: Key) -> blot_support::Option<i64> {let index .= blot_support_pooled_map::get(self_.plan_positions,key);if !index {return blot_support::none<i64>();}return blot_support::some(self_.plans.items[index].height);}
fn admit(self_: Cache&,key: Key,height: i64) -> Error {
    let existing .= blot_support_pooled_map::get(self_.plan_positions,key);if existing {self_.plans.items[existing].height = max(self_.plans.items[existing].height,height);return blot_error::Error.none;}if self_.plans.items.len >= 65536 {return blot_error::Error.none;}
    let owned = own(key);let capacity = blot_support_pooled_buffer::ensure(self_.plans,self_.plans.items.len + 1,admission_runs);if capacity != blot_error::Error.none {release(owned);return capacity;}let index = self_.plans.items.len;blot_support_pooled_map::insert(self_.plan_positions,owned,index,plan_slots);let inserted = blot_support_pooled_buffer::push(self_.plans,Admission {key: owned,height: height},admission_runs);if inserted != blot_error::Error.none {blot_support_pooled_map::remove(self_.plan_positions,owned);release(owned);}return inserted;
}
fn findExact(self_: const Cache&,key: Key) -> blot_support::Option<i64> {let chain .= blot_support_pooled_map::get(self_.entry_positions,key);if !chain {return blot_support::none<i64>();}return blot_support::some(chain.first);}
fn canonical(key: Key) -> Key {var result = key;result.context = 0;result.context_free = true;return result;}
fn find(self_: const Cache&,key: Key) -> blot_support::Option<i64> {let found = self_.findExact(key);if found.present {return found;}if key.context_free {return blot_support::none<i64>();}return self_.findExact(canonical(key));}
struct Candidates {cache: const Cache&,current: blot_support::Option<i64>,fallback: blot_support::Option<Key>}
fn next(self_: Candidates&) -> blot_support::Option<i64> {if !self_.current.present && self_.fallback.present {self_.current = self_.cache.findExact(self_.fallback.value);self_.fallback = blot_support::none<Key>();}let index = self_.current;if !index.present {return index;}self_.current = self_.cache.entries.items[index.value].next;return index;}
fn candidates(self_: const Cache&,key: Key) -> Candidates {var fallback = blot_support::none<Key>();if !key.context_free {fallback = blot_support::some(canonical(key));}return Candidates {cache: self_,current: self_.findExact(key),fallback: fallback};}
fn complete(self_: Cache&,index: i64,sensitive: bool) -> Error {let entry = self_.entries.items[index];assert(entry.building);assert(!entry.key.context_free || !sensitive);if !sensitive && !entry.key.context_free {let alias,error = self_.insert(canonical(entry.key),entry.function,entry.floating);if error != blot_error::Error.none {return error;}self_.entries.items[alias].building = false;self_.entries.items[alias].context_sensitive = false;}self_.entries.items[index].building = false;self_.entries.items[index].context_sensitive = sensitive;return blot_error::Error.none;}
fn insert(self_: Cache&,key: Key,function: u32,floating: bool) -> i64,Error {
    let owned = own(key);let capacity = blot_support_pooled_buffer::ensure(self_.entries,self_.entries.items.len + 1,entry_runs);if capacity != blot_error::Error.none {release(owned);return 0,capacity;}let index = self_.entries.items.len;var previous = blot_support::none<i64>();let chain .= blot_support_pooled_map::get(self_.entry_positions,key);
    if chain {previous = blot_support::some(chain.last);self_.entries.items[chain.last].next = blot_support::some(index);chain.last = index;}else {blot_support_pooled_map::insert(self_.entry_positions,owned,Chain {first: index,last: index},entry_slots);}
    let error = blot_support_pooled_buffer::push(self_.entries,Entry {key: owned,function: function,floating: floating,previous: previous,..},entry_runs);return index,error;
}
recursive fn scalarBody(m: const Module&,root: u32,remaining: i64&,depth: i64) -> bool {
    if root == 0 {return true;}if remaining == 0 || depth > 128 {return false;}remaining--;let node = m.node(root);if node.ty != blot_check_types::never && node.ty != blot_check_types::unit && node.ty != blot_check_types::boolean && node.ty != blot_check_types::u32_type && node.ty != blot_check_types::f32_type {return false;}
    match node.tag {
        constant=>{},reference=>{let reference = m.reference(root);if reference.unit != 0 && reference.unit != m.unit {return false;}let kind = m.binding(reference.binding).kind;if kind != blot_reuse_principal_interface::Kind.local && kind != blot_reuse_principal_interface::Kind.parameter {return false;}},
        scalar,logical=>{if !scalarBody(m,node.a,remaining,depth + 1) || !scalarBody(m,node.b,remaining,depth + 1) {return false;}},
        bind=>{if !scalarBody(m,node.b,remaining,depth + 1) {return false;}},return_=>{if !scalarBody(m,node.a,remaining,depth + 1) {return false;}},
        if_value,if_stmt=>{if !scalarBody(m,node.a,remaining,depth + 1) || !scalarBody(m,node.b,remaining,depth + 1) || !scalarBody(m,node.c,remaining,depth + 1) {return false;}},
        block_,suite=>{for child in m.children(root) {if !scalarBody(m,child,remaining,depth + 1) {return false;}}},_=>{return false;},
    }return true;
}
fn hash(target: Ref) -> u64 {let words: u32[2] = [target.unit,target.binding];return blot_support_wyhash::hash(0,bytes_of(words));}
reusable[] var completed_slots: dictionary_slot<Ref,i64>[>..] = [];
struct ScalarAdmission {units: const Module[:],scalar_references: blot_support::Option<bool> = blot_support::none<bool>(),nodes: u64 = 0,hits: u64 = 0,completed: blot_support_pooled_map::Map<Ref,i64> = blot_support_pooled_map::Map<Ref,i64> {..},active: Ref[128] = [Ref {..};128],len: i64 = 0}
fn deinit(self_: ScalarAdmission&) {blot_support_pooled_map::deinit(self_.completed,completed_slots);}
fn hasScalarReferences(self_: ScalarAdmission&) -> bool {
    if self_.scalar_references.present {return self_.scalar_references.value;}for module in self_.units {for node in module.nodes {if node.tag != blot_check_core::Tag.storage {continue;}let op,error = blot_check_storage_ops::opFromCode(node.c);if error == blot_error::Error.none && op == blot_check_storage_ops::Op.ref {self_.scalar_references = blot_support::some(true);return true;}}}self_.scalar_references = blot_support::some(false);return false;
}
fn primitive(ty: u32) -> bool {return ty == blot_check_types::unit || ty == blot_check_types::boolean || ty == blot_check_types::u32_type || ty == blot_check_types::f32_type;}
fn closed(scheme: blot_check_types::Scheme) -> bool {return scheme.variables.len == 0 && scheme.row_variables.len == 0 && scheme.obligations.len == 0 && scheme.generative.len == 0;}
fn charge(self_: ScalarAdmission&,remaining: i64&,depth: i64) -> bool {if remaining == 0 || depth > 128 {return false;}remaining--;self_.nodes++;return true;}
fn pureRow(self_: ScalarAdmission&,m: const Module&,id: u32,closed_rows: blot_check_types::List,remaining: i64&,depth: i64) -> bool {
    let row = m.types.row(id);if row.labels.len != 0 {return false;}match row.tail {closed=>{return true;},variable variable=>{for expected in m.types.list(closed_rows) {if !self_.charge(remaining,depth) {return false;}if variable.value == expected {return true;}}return false;},_=>{return false;},}
}
fn admit(self_: ScalarAdmission&,m: const Module&,binding: u32,remaining: i64&) -> bool,Error {let height,error = body(self_,m,binding,remaining,0);return height.present,error;}
recursive fn body(self_: ScalarAdmission&,m: const Module&,binding: u32,remaining: i64&,depth: i64) -> blot_support::Option<i64>,Error {
    if !self_.charge(remaining,depth) || binding == 0 || binding >= m.bindings.len {return blot_support::none<i64>(),blot_error::Error.none;}let target = Ref {unit: m.unit,binding: binding};
    {let height .= blot_support_pooled_map::get(self_.completed,target);if height {if depth + height > 128 || self_.len == 128 {return blot_support::none<i64>(),blot_error::Error.none;}self_.hits++;return blot_support::some<i64>(height),blot_error::Error.none;}}
    if self_.len == 128 || self_.completed.count >= 100000 {return blot_support::none<i64>(),blot_error::Error.none;}for prior in self_.active[..self_.len] {if prior == target {return blot_support::none<i64>(),blot_error::Error.none;}}
    let source .= m.body(binding);if !source || !source.is_function || !closed(source.scheme) || !closed(m.binding(binding).scheme) {return blot_support::none<i64>(),blot_error::Error.none;}
    var signature = m.binding(binding).ty;
    for parameter in m.bodyParameters(source) {if !self_.charge(remaining,depth + 1) || !primitive(parameter.ty) {return blot_support::none<i64>(),blot_error::Error.none;}let arrow = m.types.node(signature);if arrow.tag != blot_check_types::Tag.function || arrow.a != parameter.ty {return blot_support::none<i64>(),blot_error::Error.none;}if !self_.pureRow(m,arrow.c,m.binding(binding).scheme.closed_rows,remaining,depth + 1) {return blot_support::none<i64>(),blot_error::Error.none;}signature = arrow.b;}
    if !primitive(signature) || signature != m.typeOf(source.root) {return blot_support::none<i64>(),blot_error::Error.none;}self_.active[self_.len] = target;self_.len++;
    let walked,error = walk(self_,m,source.root,source.closed_rows,remaining,depth + 1);self_.len--;if error != blot_error::Error.none || !walked.present {return blot_support::none<i64>(),error;}let height = 1 + walked.value;
    if depth + height > 128 || self_.completed.count >= 100000 {return blot_support::none<i64>(),blot_error::Error.none;}blot_support_pooled_map::insert(self_.completed,target,height,completed_slots);return blot_support::some<i64>(height),blot_error::Error.none;
}
recursive fn walk(self_: ScalarAdmission&,m: const Module&,root: u32,closed_rows: blot_check_types::List,remaining: i64&,depth: i64) -> blot_support::Option<i64>,Error {
    if root == 0 {return blot_support::some(0 as i64),blot_error::Error.none;}if !self_.charge(remaining,depth) {return blot_support::none<i64>(),blot_error::Error.none;}let node = m.node(root);if node.ty != blot_check_types::never && !primitive(node.ty) {return blot_support::none<i64>(),blot_error::Error.none;}
    var height: i64 = 0;let operands: u32[3] = [node.a,node.b,node.c];
    match node.tag {
        constant=>{},reference=>{let reference = m.reference(root);if (reference.unit != 0 && reference.unit != m.unit) || reference.binding == 0 || reference.binding >= m.bindings.len {return blot_support::none<i64>(),blot_error::Error.none;}let kind = m.binding(reference.binding).kind;if kind != blot_reuse_principal_interface::Kind.local && kind != blot_reuse_principal_interface::Kind.parameter {return blot_support::none<i64>(),blot_error::Error.none;}},
        scalar,logical=>{if node.tag == blot_check_core::Tag.scalar && (node.c != 0 || blot_backend_simd_intrinsics::literalLanes(node.op)) {return blot_support::none<i64>(),blot_error::Error.none;}return walkChildren(self_,m,operands[..2],closed_rows,remaining,depth,height);},bind=>{return walkChildren(self_,m,operands[1..2],closed_rows,remaining,depth,height);},return_=>{return walkChildren(self_,m,operands[..1],closed_rows,remaining,depth,height);},if_value,if_stmt=>{return walkChildren(self_,m,operands,closed_rows,remaining,depth,height);},block_,suite=>{return walkChildren(self_,m,m.children(root),closed_rows,remaining,depth,height);},
        call=>{
            let call = m.call(root);var target = call.target;if target.unit == 0 {target.unit = m.unit;}if target.unit == 0 || target.unit > self_.units.len {return blot_support::none<i64>(),blot_error::Error.none;}let owner: const Module& = self_.units[target.unit - 1];if target.binding == 0 || target.binding >= owner.bindings.len {return blot_support::none<i64>(),blot_error::Error.none;}let source .= owner.body(target.binding);if !source {return blot_support::none<i64>(),blot_error::Error.none;}let parameters = owner.bodyParameters(source);if call.arguments.len != parameters.len {return blot_support::none<i64>(),blot_error::Error.none;}var signature = call.callee_type;
            for index in 0..parameters.len {let parameter = parameters[index];let argument = call.arguments[index];if !self_.charge(remaining,depth + 1) || !primitive(parameter.ty) || m.typeOf(argument) != parameter.ty {return blot_support::none<i64>(),blot_error::Error.none;}let arrow = m.types.node(signature);if arrow.tag != blot_check_types::Tag.function || arrow.a != parameter.ty {return blot_support::none<i64>(),blot_error::Error.none;}if !self_.pureRow(m,arrow.c,closed_rows,remaining,depth + 1) {return blot_support::none<i64>(),blot_error::Error.none;}signature = arrow.b;}
            if !primitive(signature) || signature != node.ty {return blot_support::none<i64>(),blot_error::Error.none;}let callee,error = body(self_,owner,target.binding,remaining,depth + 1);if error != blot_error::Error.none || !callee.present {return blot_support::none<i64>(),error;}height = 1 + callee.value;return walkChildren(self_,m,call.arguments,closed_rows,remaining,depth,height);
        },_=>{return blot_support::none<i64>(),blot_error::Error.none;},
    }
    return walkChildren(self_,m,default<const u32[:]>(),closed_rows,remaining,depth,height);
}
recursive fn destinationBody(m: const Module&,root: u32,arrays: i64&,remaining: i64&,depth: i64) -> bool {
    if root == 0 {return true;}if remaining == 0 || depth > 128 {return false;}remaining--;let node = m.node(root);
    match node.tag {array=>{arrays++;if arrays > 1 || m.types.node(node.ty).tag != blot_check_types::Tag.array {return false;}for child in m.children(root) {if !scalarBody(m,child,remaining,depth + 1) {return false;}}},reference=>{let reference = m.reference(root);if reference.unit != 0 && reference.unit != m.unit {return false;}let kind = m.binding(reference.binding).kind;if kind != blot_reuse_principal_interface::Kind.local && kind != blot_reuse_principal_interface::Kind.parameter {return false;}},bind=>{return destinationBody(m,node.b,arrays,remaining,depth + 1);},return_=>{return destinationBody(m,node.a,arrays,remaining,depth + 1);},block_,suite=>{for child in m.children(root) {if !destinationBody(m,child,arrays,remaining,depth + 1) {return false;}}},_=>{return scalarBody(m,root,remaining,depth + 1);},}return true;
}
// Numeric scope links keep declaration substitutions alive through recursive
// proof walks without storing a reference to a recursive invocation's frame.
struct InlineInput {ty: u32,environment: u32 = 0}
struct InlineScope {parent: u32 = 0,arguments_environment: u32 = 0,parameters: const u32[:] = default<const u32[:]>(),arguments: const u32[:] = default<const u32[:]>(),singleton: bool = false,formal: u32 = 0,actual: u32 = 0}
struct InlineContext {scopes: InlineScope[256] = [InlineScope {..};256],len: i64 = 0}
fn add(self_: InlineContext&,scope: InlineScope) -> u32 {assert(self_.len < 256);let index = self_.len;self_.scopes[index] = scope;self_.len++;return (index + 1) as u32;}
fn count(scope: InlineScope) -> i64 {if scope.singleton {return 1;}return scope.parameters.len;}
fn parameter(scope: InlineScope,index: i64) -> u32 {if scope.singleton {assert(index == 0);return scope.formal;}return scope.parameters[index];}
fn argument(scope: InlineScope,index: i64) -> u32 {if scope.singleton {assert(index == 0);return scope.actual;}return scope.arguments[index];}
recursive fn inlineBinding(context: InlineContext&,m: const Module&,formal: u32,actual: InlineInput,variable: u32,remaining: i64&,depth: i64) -> blot_support::Option<InlineInput> {
    if remaining == 0 || depth > 128 {return blot_support::none<InlineInput>();}remaining--;if formal == variable {return blot_support::some(actual);}let selected = inlineResolved(context,m,actual,remaining,depth + 1);if !selected.present {return selected;}let left = m.types.node(formal);let right = m.types.node(selected.value.ty);if left.tag != right.tag {return blot_support::none<InlineInput>();}
    if left.tag == blot_check_types::Tag.product {if left.b != right.b {return blot_support::none<InlineInput>();}let first = m.types.list(blot_check_types::List {start: left.a,len: left.b});let second = m.types.list(blot_check_types::List {start: right.a,len: right.b});for index in 0..first.len {if remaining == 0 {return blot_support::none<InlineInput>();}let found = inlineBinding(context,m,first[index],InlineInput {ty: second[index],environment: selected.value.environment},variable,remaining,depth + 1);if found.present {return found;}}}
    else if left.tag == blot_check_types::Tag.record {if left.b != right.b {return blot_support::none<InlineInput>();}for index in 0..left.b {let field = m.types.recordField(left,index);for other in 0..right.b {if remaining == 0 {return blot_support::none<InlineInput>();}remaining--;let candidate = m.types.recordField(right,other);if field.name != candidate.name {continue;}let found = inlineBinding(context,m,field.ty,InlineInput {ty: candidate.ty,environment: selected.value.environment},variable,remaining,depth + 1);if found.present {return found;}}}}
    else if left.tag == blot_check_types::Tag.nominal {if left.a != right.a || left.b != right.b {return blot_support::none<InlineInput>();}let first = m.types.nominalArguments(left);let second = m.types.nominalArguments(right);if first.len != second.len {return blot_support::none<InlineInput>();}for index in 0..first.len {if remaining == 0 {return blot_support::none<InlineInput>();}let found = inlineBinding(context,m,first[index],InlineInput {ty: second[index],environment: selected.value.environment},variable,remaining,depth + 1);if found.present {return found;}}}
    return blot_support::none<InlineInput>();
}
recursive fn inlineResolved(context: InlineContext&,m: const Module&,input: InlineInput,remaining: i64&,depth: i64) -> blot_support::Option<InlineInput> {
    if depth > 128 {return blot_support::none<InlineInput>();}let node = m.types.node(input.ty);if node.tag != blot_check_types::Tag.variable && node.tag != blot_check_types::Tag.bound {return blot_support::some(input);}if remaining == 0 {return blot_support::none<InlineInput>();}remaining--;var environment = input.environment;
    while environment != 0 {let scope = context.scopes[environment - 1];for index in 0..scope.count() {if remaining == 0 {return blot_support::none<InlineInput>();}let found = inlineBinding(context,m,scope.parameter(index),InlineInput {ty: scope.argument(index),environment: scope.arguments_environment},input.ty,remaining,depth + 1);if found.present {return inlineResolved(context,m,found.value,remaining,depth + 1);}}environment = scope.parent;}
    return blot_support::none<InlineInput>();
}
fn inlineType(m: const Module&,ty: u32,remaining: i64&,depth: i64) -> bool {var context = InlineContext {..};return inlineTypeUnder(context,m,InlineInput {ty,..},remaining,depth);}
recursive fn inlineTypeUnder(context: InlineContext&,m: const Module&,input: InlineInput,remaining: i64&,depth: i64) -> bool {
    if remaining == 0 || depth > 128 {return false;}remaining--;let actual = inlineResolved(context,m,input,remaining,depth);if !actual.present {return false;}let node = m.types.node(actual.value.ty);
    if node.tag == blot_check_types::Tag.unit || node.tag == blot_check_types::Tag.boolean || node.tag == blot_check_types::Tag.unsigned32 || node.tag == blot_check_types::Tag.floating32 || node.tag == blot_check_types::Tag.never {return true;}
    if node.tag == blot_check_types::Tag.product || node.tag == blot_check_types::Tag.record {for index in 0..node.b {var child: u32 = 0;if node.tag == blot_check_types::Tag.record {child = m.types.recordField(node,index).ty;}else {child = m.types.list(blot_check_types::List {start: node.a,len: node.b})[index];}if !inlineTypeUnder(context,m,InlineInput {ty: child,environment: actual.value.environment},remaining,depth + 1) {return false;}}return true;}
    if node.tag != blot_check_types::Tag.nominal || blot_check_storage_types::identity(node.a,node.b).present {return false;}
    let arguments = m.types.nominalArguments(node);for argument in arguments {if !inlineTypeUnder(context,m,InlineInput {ty: argument,environment: actual.value.environment},remaining,depth + 1) {return false;}}
    for nominal,index in m.nominals {
        if nominal.identity.unit != node.a || nominal.identity.decl != node.b {continue;}let parameters = m.types.list(nominal.parameters);let constructors = m.nominalConstructors(index as u32);if parameters.len != arguments.len || constructors.len == 0 {return false;}
        let mark = context.len;let scope = context.add(InlineScope {parent: actual.value.environment,arguments_environment: actual.value.environment,parameters: parameters,arguments: arguments,..});
        fn variants() -> bool {
            for id in constructors {let constructor = m.constructor(id);let signature = m.types.node(constructor.scheme.root);var result = constructor.scheme.root;if signature.tag == blot_check_types::Tag.function {result = signature.b;}let returned = m.types.node(result);if returned.tag != blot_check_types::Tag.nominal || returned.a != node.a || returned.b != node.b || m.types.nominalArguments(returned).len != arguments.len {return false;}
                let variant = context.add(InlineScope {parent: scope,arguments_environment: actual.value.environment,singleton: true,formal: result,actual: actual.value.ty,..});
                let valid = constructor.payload == 0 || inlineTypeUnder(context,m,InlineInput {ty: constructor.payload,environment: variant},remaining,depth + 1);context.len--;if !valid {return false;}
            }return true;
        }
        let valid = variants();context.len = mark;return valid;
    }return false;
}
struct ClosedCalls {units: const Module[:],active: Ref[128] = [Ref {..};128],len: i64 = 0}
recursive fn body(self_: ClosedCalls&,m: const Module&,binding: u32,remaining: i64&,depth: i64) -> bool {
    if self_.len == 128 || binding == 0 || binding >= m.bindings.len {return false;}let target = Ref {unit: m.unit,binding: binding};for prior in self_.active[..self_.len] {if prior == target {return false;}}let source .= m.body(binding);if !source || !source.is_function || !closed(source.scheme) {return false;}var signature = m.binding(binding).ty;
    for parameter in m.bodyParameters(source) {if !inlineType(m,parameter.ty,remaining,depth + 1) {return false;}let arrow = m.types.node(signature);if arrow.tag != blot_check_types::Tag.function {return false;}let row = m.types.row(arrow.c);if row.labels.len != 0 {return false;}match row.tail {closed=>{},_=>{return false;},}signature = arrow.b;}
    if !inlineType(m,signature,remaining,depth + 1) {return false;}self_.active[self_.len] = target;self_.len++;let admitted = leafBody(m,source.root,remaining,depth + 1,false,self_);self_.len--;return admitted;
}
fn inlineBody(units: const Module[:],m: const Module&,binding: u32,remaining: i64&) -> bool {let source .= m.body(binding);if !source {return false;}if leafBody(m,source.root,remaining,0,false,null) {return true;}var calls = ClosedCalls {units,..};return calls.body(m,binding,remaining,0);}
recursive fn readerType(m: const Module&,ty: u32,remaining: i64&,depth: i64) -> bool {
    if remaining == 0 || depth > 128 {return false;}remaining--;let node = m.types.node(ty);
    if node.tag == blot_check_types::Tag.array || node.tag == blot_check_types::Tag.list {return inlineType(m,node.a,remaining,depth + 1);}if node.tag == blot_check_types::Tag.cursor {return readerType(m,node.a,remaining,depth + 1);}let storage = blot_check_storage_types::info(m.types,ty);if storage.present {return inlineType(m,storage.value.element,remaining,depth + 1);}
    if node.tag == blot_check_types::Tag.product {for child in m.types.list(blot_check_types::List {start: node.a,len: node.b}) {if !readerType(m,child,remaining,depth + 1) {return false;}}return true;}
    if node.tag == blot_check_types::Tag.record {for index in 0..node.b {if !readerType(m,m.types.recordField(node,index).ty,remaining,depth + 1) {return false;}}return true;}
    if node.tag == blot_check_types::Tag.nominal {if m.types.nominalArguments(node).len != 0 {return false;}for nominal,index in m.nominals {if nominal.identity.unit != node.a || nominal.identity.decl != node.b {continue;}for constructor in m.nominalConstructors(index as u32) {let payload = m.constructor(constructor).payload;if payload != 0 && !readerType(m,payload,remaining,depth + 1) {return false;}}return true;}return false;}
    return inlineType(m,ty,remaining,depth + 1);
}
fn readerBody(m: const Module&,root: u32,remaining: i64&,depth: i64) -> bool {return leafBody(m,root,remaining,depth,true,null);}
recursive fn leafBody(m: const Module&,root: u32,remaining: i64&,depth: i64,readers: bool,calls: ClosedCalls?) -> bool {
    if root == 0 {return true;}if remaining == 0 || depth > 128 {return false;}remaining--;let node = m.node(root);if readers {if !readerType(m,node.ty,remaining,depth + 1) {return false;}}else if !inlineType(m,node.ty,remaining,depth + 1) {return false;}
    match node.tag {
        constant=>{},reference=>{let reference = m.reference(root);if reference.unit != 0 && reference.unit != m.unit {return false;}let kind = m.binding(reference.binding).kind;if kind != blot_reuse_principal_interface::Kind.local && kind != blot_reuse_principal_interface::Kind.parameter {return false;}},
        scalar,logical=>{if node.tag == blot_check_core::Tag.scalar && (node.c != 0 || blot_backend_simd_intrinsics::literalLanes(node.op)) {return false;}if !leafBody(m,node.a,remaining,depth + 1,readers,calls) || !leafBody(m,node.b,remaining,depth + 1,readers,calls) {return false;}},
        bind,construct=>{return leafBody(m,node.b,remaining,depth + 1,readers,calls);},pattern_bind=>{return node.c == 0 && leafBody(m,node.b,remaining,depth + 1,readers,calls);},return_=>{return leafBody(m,node.a,remaining,depth + 1,readers,calls);},
        project=>{let projection = m.projection(node.b);if projection.variants.len == 0 {let receiver = m.types.node(m.typeOf(node.a));var field = false;if receiver.tag == blot_check_types::Tag.record {for index in 0..receiver.b {if m.types.recordField(receiver,index).name == projection.field {field = true;break;}}}if !field {return false;}}return leafBody(m,node.a,remaining,depth + 1,readers,calls);},
        if_value,if_stmt=>{if !leafBody(m,node.a,remaining,depth + 1,readers,calls) || !leafBody(m,node.b,remaining,depth + 1,readers,calls) || !leafBody(m,node.c,remaining,depth + 1,readers,calls) {return false;}},
        block_,suite,product,record=>{for child in m.children(root) {if !leafBody(m,child,remaining,depth + 1,readers,calls) {return false;}}},
        call=>{if !calls {return false;}let call = m.call(root);var target = call.target;if target.unit == 0 {target.unit = m.unit;}if target.unit == 0 || target.unit > calls.units.len {return false;}let owner: const Module& = calls.units[target.unit - 1];let body .= owner.body(target.binding);if !body || call.arguments.len != owner.bodyParameters(body).len {return false;}for argument in call.arguments {if !leafBody(m,argument,remaining,depth + 1,false,calls) {return false;}}if !calls.body(owner,target.binding,remaining,depth + 1) {return false;}},
        storage=>{if !readers {return false;}let op,error = blot_check_storage_ops::opFromCode(node.c);if error != blot_error::Error.none {return false;}match op {at,link,view,load,length,read=>{},_=>{return false;},}for child in m.children(root) {if !leafBody(m,child,remaining,depth + 1,readers,calls) {return false;}}},
        array_op=>{if !readers {return false;}let op,error = blot_backend_collection_ops::opFromCode(node.c);if error != blot_error::Error.none {return false;}match op {length,get,identity,cursor,cursor_has,cursor_value,cursor_advance=>{},_=>{return false;},}for child in m.children(root) {if !leafBody(m,child,remaining,depth + 1,readers,calls) {return false;}}},_=>{return false;},
    }return true;
}

recursive fn walkChildren(self_:ScalarAdmission&,m:const Module&,children:const u32[:],closed_rows:blot_check_types::List,remaining:i64&,depth:i64,initial_height:i64)->blot_support::Option<i64>,Error {var height=initial_height;for child in children {if child == 0 {continue;}let child_height,error = walk(self_,m,child,closed_rows,remaining,depth + 1);if error != blot_error::Error.none || !child_height.present {return blot_support::none<i64>(),error;}height = max(height,1 + child_height.value);}if depth + height > 128 {return blot_support::none<i64>(),blot_error::Error.none;}return blot_support::some<i64>(height),blot_error::Error.none;}
